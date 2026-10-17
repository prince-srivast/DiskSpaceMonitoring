# Scalable Disk Monitoring for AWS
**AWS multi-account reference implementation**

## Overview
This project monitors filesystem use on tagged Linux EC2 instances across AWS accounts. Ansible configures the CloudWatch Agent; SSM Session Manager provides access without inbound SSH. The agent sends metrics to CloudWatch, where a central account can view them and route alarms through SNS.

Ansible also stores the shared agent config in Parameter Store. A tag-targeted State Manager association installs and configures the agent on new managed instances. After setup, metric collection continues without the Ansible controller.

## Repository map
```text
ansible/       Agent config, playbooks, and dynamic inventory
cloudwatch/    OAM, alarms, SNS, dashboard, and State Manager templates
iam/           Example role trust and permission policies
scripts/       Account enrollment, SSM checks, and dashboard rendering
terraform/     Two-Region test fleet
docs/          Architecture, security, operations, and cost notes
```

## Architecture at a glance
See [docs/architecture.md](docs/architecture.md) for the diagram and data flow.

## Requirement coverage
| Assignment area | Design / artifacts |
|---|---|
| Secure access across accounts | SSM Session Manager without inbound SSH; temporary STS role sessions with external-ID trust; [IAM examples](iam/) |
| Ansible connection and discovery | `amazon.aws.aws_ec2` discovers tagged instances; `amazon.aws.aws_ssm` connects; `scripts/enroll-account.sh` handles a canary and `scripts/enroll-organization.sh` handles bounded multi-account rollout |
| Disk data collection | CloudWatch Agent role publishes `CWAgent/disk_used_percent` every 300 seconds |
| Central visibility and alerts | Regional CloudWatch OAM sink/link templates, a cross-account dashboard renderer, central-account alarm template, and SNS topic |
| Growth and onboarding | AWS Organizations account/Region discovery, StackSets/account-vending role bootstrap, bounded Ansible concurrency, and tag-targeted State Manager auto-enrollment for new EC2 |
| Canary evidence | An earlier non-production canary published root filesystem metrics. The standalone Terraform inputs here have not been applied. |

## Prerequisites
- AWS Organizations and a management/delegated-administrator profile for discovery, plus a dedicated Ansible role in every target account.
- Linux EC2 instances (Amazon Linux, Ubuntu/Debian, or supported Red Hat-family distributions), SSM Agent, and an instance profile granting `AmazonSSMManagedInstanceCore`, CloudWatch metric publishing, and `ssm:GetParameter` for `/disk-monitoring/cloudwatch-agent-config`. The Ansible role supports Linux only.
- A central monitoring account. Deploy its CloudWatch OAM sink in each monitored Region and link each source account in the same Region.
- A Linux automation runner (or WSL2 Linux distribution) with Bash, AWS CLI, Ansible Core, the AWS Systems Manager Session Manager plugin, the `amazon.aws` and `community.aws` collections, `boto3`, and `botocore`. The Ansible controller is not supported on native Windows.
- Network path to SSM and CloudWatch APIs: NAT/egress or VPC interface endpoints as appropriate.

## Deployment sequence
1. **Bootstrap IAM**: deploy the trust policy and member-role policy in each workload account. The assumed automation role needs scoped `ssm:PutParameter`/`ssm:GetParameter` access to the agent configuration parameter. The EC2 instance role needs `ssm:GetParameter` for that exact parameter in addition to SSM core and CloudWatch metric permissions; see [IAM examples](iam/). The trusted principal must be the dedicated automation role in the Organizations management/delegated administrator account, and the trust policy must require an external ID. Use CloudFormation StackSets/account vending to cover existing and new accounts.
2. **Set up centralized observability**: deploy `cloudwatch/monitoring-account.yaml` in each central monitoring Region with the AWS Organization ID. Record the `ObservabilitySinkArn` output. In every source account and Region, deploy `cloudwatch/source-account-link.yaml` with that Region's sink ARN. Sink and source links are regional; link every Region that publishes metrics. For example:
   ```bash
   aws cloudformation deploy \
     --template-file cloudwatch/monitoring-account.yaml \
     --stack-name disk-monitoring-central \
     --parameter-overrides OrganizationId=o-a1b2c3d4e5 \
     --profile monitoring --region us-east-1
   aws cloudformation describe-stacks \
     --stack-name disk-monitoring-central --profile monitoring --region us-east-1 \
     --query "Stacks[0].Outputs[?OutputKey=='ObservabilitySinkArn'].OutputValue" \
     --output text
   aws cloudformation deploy \
     --template-file cloudwatch/source-account-link.yaml \
     --stack-name disk-monitoring-oam-link \
     --parameter-overrides SinkArn=arn:aws:oam:us-east-1:123456789012:sink:EXAMPLE \
     --profile member-account --region us-east-1
   ```
   Supply the notification address through the `NotificationEmail` parameter when deploying `cloudwatch/monitoring-account.yaml`. Replace the example Organization ID and sink/account values, deploy each source link with the member-account role, and confirm the SNS email subscription.
3. **Enable SSM**: ensure SSM Agent is running, the instance profile includes SSM permissions, and required endpoints/egress are available. Confirm eligible instances appear as `Online` in Systems Manager.
4. **Install Ansible dependencies**:
   ```bash
   python3 -m venv ~/.venvs/aws-disk-monitoring
   source ~/.venvs/aws-disk-monitoring/bin/activate
   cd /path/to/DiskSpaceMonitoring/ansible
   python3 -m pip install 'ansible-core>=2.17' 'boto3>=1.35.0' 'botocore>=1.35.0'
   ansible-galaxy collection install -r requirements.yml
   ```
   Install the AWS CLI and the Session Manager plugin on the controller as well. The controller needs permission to start/terminate SSM sessions and to use the S3 transfer bucket (`s3:GetObject`, `s3:PutObject`, `s3:ListBucket`, `s3:DeleteObject`, and `s3:GetBucketLocation`). Managed instances need network access to SSM and S3 endpoints; they do not need S3 credentials just for the SSM plugin file transfer.
5. **Set up the controller transfer bucket**: use a private, encrypted S3 bucket accessible to the controller and every assumed member role. Set `SSM_TRANSFER_BUCKET_REGION` if it is outside the target Region. The roles need `s3:ListBucket`, `s3:GetBucketLocation`, `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject`; for cross-account access, allow those actions in the bucket policy too. The SSM plugin uses virtual-hosted S3 addressing for cross-Region transfers. Instances need S3 network access, not S3 credentials.
6. **Seed the agent configuration and enable auto-enrollment**: in each workload account and Region, run the localhost configuration publisher with the member role. It stores the same config Ansible applies to existing instances:
   ```bash
   cd ansible
   AWS_PROFILE=member-account AWS_REGION=us-east-1 \
     ansible-playbook -i 'localhost,' playbooks/publish-cloudwatch-agent-config.yml
   ```
   Then deploy `cloudwatch/disk-monitoring-state-manager.yaml` in each workload account and Region. Use StackSets for account-wide rollout. The association installs the agent and applies the Parameter Store config to managed EC2 instances tagged `DiskMonitoring=enabled`. Seed the parameter before creating the association. The normal `scripts/enroll-account.sh` flow publishes/updates it automatically before Ansible enrollment; publishing it directly also handles an account with no tagged instances yet.
7. **Enroll one account/Region** (canary):
   ```bash
   cd ansible
   AWS_PROFILE=member-account AWS_REGION=us-east-1 \
     SSM_TRANSFER_BUCKET=my-private-ssm-transfer-bucket \
     ../scripts/enroll-account.sh
   ```
   The inventory discovers running instances tagged `DiskMonitoring=enabled`, checks that at least one host is found, configures the CloudWatch Agent over SSM, then validates service and config. Verify the profile account and transfer-bucket access before proceeding.
8. **Scale across the Organization**: after the canary succeeds, set `AWS_PROFILE` to the Organizations management/delegated-administrator profile, `AWS_ROLE_EXTERNAL_ID` to the value provisioned in member-role trust, and `SSM_TRANSFER_BUCKET` to the transfer bucket. Optionally set `AWS_MEMBER_ROLE_NAME`, a comma-separated `DISK_MONITORING_REGIONS` allowlist with no spaces, and `MAX_PARALLEL` (default 4, capped at 32), then run:
   ```bash
   cd /path/to/DiskSpaceMonitoring
   ./scripts/enroll-organization.sh
   ```
   It includes the caller account directly, assumes the configured role in other active accounts, validates each assumed account ID, discovers opted-in Regions, checks any Region allowlist against each account, and bounds concurrency. It fails if a required account role cannot be assumed; onboard/fix those accounts before considering coverage complete.
9. **Centralize metrics**: render a dashboard from the source account/Region inventory and deploy it in the monitoring account:
   ```bash
   cd /path/to/DiskSpaceMonitoring
   python3 scripts/render-dashboard.py \
     --sources cloudwatch/source-accounts.example.json \
     --output /tmp/disk-fleet-dashboard.json
   aws cloudwatch put-dashboard \
     --dashboard-name Disk-Fleet-Health \
     --dashboard-body "file:///tmp/disk-fleet-dashboard.json" \
     --profile monitoring --region us-east-1
   ```
   Replace the example inventory with linked source accounts/Regions; do not commit account-specific data. The dashboard renders one search widget per account/Region. Deploy the alarm template in the monitoring account for each filesystem, supplying its source account ID, instance ID, path, and SNS topic ARN.
   ```bash
   aws cloudformation deploy \
     --template-file cloudwatch/root-filesystem-alarm.yaml \
     --stack-name disk-warning-123456789012-i-0123456789abcdef0-root \
     --parameter-overrides \
       SourceAccountId=123456789012 \
       InstanceId=i-0123456789abcdef0 \
       AlertTopicArn=arn:aws:sns:us-east-1:210987654321:disk-monitoring-alerts \
     --profile monitoring --region us-east-1
   ```
   The stack name and identifiers above are synthetic examples. Each stack creates warning and critical alarms for one account/instance/filesystem pair.
10. **Test**: the non-production canary completed Ansible configuration/validation and published `disk_used_percent` for `/` in `CWAgent` (sample observed root utilization ~23.7%). Verify fresh timestamps, missing-metric coverage, State Manager association status for a newly tagged test instance, alarm state, notification, and recovery. Never fill a production filesystem as a test.

For a disposable five-instance lab across two Regions, see [terraform/Global/README.md](terraform/Global/README.md). Terraform prompts for the account ID, Region names, and notification email. The lab creates its own VPCs and is not deployed unless you run `terraform apply`.

## Metric and alert policy
- Metric: `disk_used_percent` from the CloudWatch Agent.
- Default collection interval: 300 seconds to balance detection time and cost.
- Warning: 80% used for 2 of 3 periods.
- Critical: 90% used for 2 of 3 periods.
- Add workload-specific thresholds where justified. Exclude ephemeral/virtual filesystems to avoid noisy alerts.
- Alert on sustained usage and use runbooks; a high percentage on a tiny filesystem may need a different threshold than a large data volume.

## Implementation status and boundaries
- An earlier non-production canary exercised tag discovery, SSM Session Manager, Ansible configuration, and `disk_used_percent` publication. The two-Region Terraform lab has not been applied.
- Included: Organizations rollout, dashboard renderer, OAM and State Manager templates, SNS topic, and warning/critical alarm template.
- Before rollout, deploy the roles and regional links, set the S3 bucket policy, confirm the SNS email, and provide the real source account and filesystem inventory.
- The Organizations rollout assumes every active non-caller account has the configured role and trust external ID. It fails during credential/account validation rather than silently omitting accounts.
- The SSM connection plugin transfers files through S3 using controller-generated presigned URLs. Instances need network access to SSM and S3, but no S3 credentials. The package URLs here target x86_64; use the matching package for ARM64.
- CloudWatch `SEARCH` has result limits. Use filters for large fleets and keep alarms on priority filesystems; a dashboard alone is not an alerting plan.
- Account IDs and ARNs in examples are placeholders.

## License
This project is licensed under the MIT License. See [LICENSE](LICENSE).

## References
- AWS Systems Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html
- CloudWatch Agent: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html
- CloudWatch cross-account observability: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Unified-Cross-Account.html
- Ansible AWS collection: https://docs.ansible.com/ansible/latest/collections/amazon/aws/index.html
