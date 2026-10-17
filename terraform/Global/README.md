# Two-Region test fleet

This root creates three tagged EC2 instances in Region 1 and two in Region 2 by default. It uses a separate VPC, SSM transfer bucket, instance role, State Manager association, SNS topic, and pair of disk alarms in each Region. A CloudWatch dashboard in Region 1 shows metrics from both Regions.

Terraform prompts for the account ID, both Regions, and the SNS notification email if they are not supplied in a variables file or on the command line. Keep the two Regions different. The account ID is checked against the active AWS credentials before provider operations continue.

To provide the values in a local file, copy `terraform.tfvars.example` to `terraform.tfvars` and replace the example values. The local file is ignored by Git.

## Layout

| Path | Resources |
|---|---|
| `resources.tf` | Regional module calls and dashboard |
| `locals.tf` | Shared CloudWatch Agent config and tags |
| `modules/vpc` | VPC, two public subnets, Internet Gateway |
| `modules/ec2` | Amazon Linux 2023 instances |
| `modules/iam` | EC2 instance role and Ansible transfer policy |
| `modules/s3` | Private encrypted SSM transfer bucket |
| `modules/ssm` | Agent config parameter, install document, tag-targeted association |
| `modules/sns` | Regional alert topic and email subscription |
| `modules/cloudwatch-alarms` | Warning and critical root filesystem alarms |

No SSH ingress is opened. Instances use public subnets so they can reach SSM, CloudWatch, S3, and the agent package source without NAT Gateways. Public IPv4 addresses and running instances incur charges. SNS sends a subscription request in each Region; confirm both messages to receive alerts.

## Run

From this directory, use the intended AWS profile and initialize the local backend:

```powershell
terraform init -reconfigure
terraform fmt -check -recursive
terraform validate
terraform plan
```

`plan` prompts for `account_id`, `region_1`, `region_2`, and `notification_email` when they are not already set. Review the entire plan before applying it. Terraform stores state locally in this directory. Do not commit `terraform.tfstate`, plan files, or `terraform.tfvars`.

The S3 transfer policy ARN is an output. Attach the policy for a Region to the AWS role used by Ansible in that Region. Use the matching transfer bucket name and set `SSM_TRANSFER_BUCKET_REGION` when the controller bucket is in a different Region.

After deployment, enroll each Region separately with `scripts/enroll-account.sh`. Verify that all five instances are Online in Systems Manager, the State Manager association succeeds, and `CWAgent/disk_used_percent` arrives before relying on the alarms.

## Test an alert

After confirming the SNS subscription email, run this from PowerShell on a machine with AWS CLI credentials for the account. It sends a test notification through one alarm without changing disk usage:

```powershell
$region = "us-east-1"
$alarmName = "disk-$region-instance-01-root-critical"

aws cloudwatch set-alarm-state `
  --alarm-name $alarmName `
  --state-value ALARM `
  --state-reason "Testing the disk alarm email" `
  --region $region
```

Change `$region` to the Region you want to test. The alarm state is temporary and returns to its metric-based state after CloudWatch reevaluates it. This checks the alarm-to-email path; verify `CWAgent/disk_used_percent` separately to confirm metric collection.

Destroy the lab with `terraform destroy` after testing. Empty each S3 transfer bucket first if it still contains files.
