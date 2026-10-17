# Security, access management, and scalability

## Access management
- Run `scripts/enroll-organization.sh` from an AWS Organizations management/delegated-administrator profile. It uses `organizations:ListAccounts` to discover active accounts, assumes a dedicated member role with the configured external ID, validates the returned account ID, and discovers opted-in Regions. The caller account is handled directly.
- Attach `iam/organization-automation-policy.json` to the source automation identity as a starting point; it grants account discovery and `sts:AssumeRole` only for the designated member-role name. Use a federated identity and restrict the account scope to your Organization.
- Restrict the member role trust policy to the exact automation-role principal and require the external ID in `iam/member-account-monitoring-role-trust-policy.json`. Never trust the entire organization without conditions. Keep external IDs and account-specific trust config out of the public repository.
- Separate permissions: discovery/SSM command execution for automation; CloudWatch metric publishing for the instance profile; alarm/dashboard/SNS administration for the monitoring platform team.
- The sample member policy leaves SSM resources broad. Before production, restrict `ssm:SendCommand` to the documents and tagged instances you use, and limit Session Manager access to those instances. Replace the S3 bucket placeholder; for cross-account access, add a bucket policy for the member role.
- Prefer IAM Identity Center/federated workforce access for humans. No static access keys in playbooks, GitHub, AMIs, or user data.
- Require MFA/approval for privileged interactive access and use SSM Session Manager instead of opening SSH to the internet.
- Encrypt S3 transfer buckets and CloudWatch Logs with KMS where required; block public access and enable CloudTrail in all accounts. The Ansible controller and assumed member roles need only the documented S3 transfer actions on the dedicated bucket/prefix.
- Apply SCPs and permission boundaries to prevent member teams from disabling baseline security controls.

## Minimum instance permissions
Attach `AmazonSSMManagedInstanceCore` to the EC2 instance role (or an equivalent reviewed policy). Add the minimum CloudWatch Agent permissions needed to publish metrics and optionally logs. Avoid attaching broad `CloudWatchFullAccess` or `AdministratorAccess` to instances. If using CloudWatch Agent configuration from Parameter Store, allow `ssm:GetParameter` only on the named parameter ARN.

## Multi-account rollout
- Use AWS Organizations to discover active accounts. The rollout discovers enabled Regions from each assumed account; set `DISK_MONITORING_REGIONS` to limit rollout.
- Deploy the member role and OAM source links with CloudFormation StackSets or an equivalent account bootstrap pipeline. Deploy one central OAM sink per Region in the monitoring account.
- Execute Ansible once per account/Region using the assumed role. `MAX_PARALLEL` defaults to 4 and is capped at 32 to constrain API pressure. Failures remain visible and must be resolved before declaring full coverage.
- Use tags such as `DiskMonitoring=enabled`, `Environment`, `Application`, and `Owner` to control enrollment and route notifications.
- `cloudwatch/disk-monitoring-state-manager.yaml` targets `DiskMonitoring=enabled` instances. It installs the agent and reads configuration from the exact Parameter Store parameter that Ansible publishes. Deploy it per account and Region after seeding the parameter.
- Use CloudWatch cross-account observability for centralized dashboards and cross-account metric visibility. OAM links are regional, so reconcile enabled account/Region pairs against deployed links and the dashboard source inventory.
- The dashboard renderer creates one `SEARCH` widget per linked account/Region. CloudWatch search returns a bounded number of time series; use account/Region filters and dimension drill-down for large fleets, and create explicit alarms for priority filesystems.
- Use AWS Config or an inventory reconciliation job to find untagged EC2s, instances without SSM, and instances that publish no recent metrics.

## Reliability
- The CloudWatch Agent runs on the instance and sends metrics independently of the Ansible runner; a temporary controller outage does not stop metric collection.
- Run two automation workers or use a managed CI/AWX service for controller availability; the controller is not on the critical path for metric emission.
- Keep a bounded retry/backoff policy for SSM and AWS APIs. Do not fan out unbounded parallel requests.
- Alert separately on missing metrics and SSM connectivity, because missing data must not be interpreted as low utilization.
- Roll out to a canary account and non-production instances before production; use staged deployment and rollback to the previous agent config.
- Organization rollout remains the account/Region bootstrap and Ansible validation path. State Manager automatically applies agent setup to new tagged SSM managed nodes; separately reconcile Organizations accounts, association coverage, and recent disk metrics so missing coverage remains visible.

## Operating model
- Platform team owns the baseline role, IAM policies, metric namespace, thresholds, dashboards, and shared runbooks.
- Application teams own disk growth remediation and provide application-specific thresholds/maintenance windows.
- Security team reviews cross-account trust, CloudTrail coverage, S3 bucket policies, and notification destinations.
