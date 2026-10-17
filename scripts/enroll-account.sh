#!/usr/bin/env bash
set -euo pipefail

# Run with credentials for the target member account.
: "${AWS_PROFILE:?Set AWS_PROFILE to the assumed member-account role profile}"
: "${AWS_REGION:=us-east-1}"
: "${SSM_TRANSFER_BUCKET:?Set SSM_TRANSFER_BUCKET to a private S3 bucket accessible to the Ansible controller}"
bucket_region="${SSM_TRANSFER_BUCKET_REGION:-$AWS_REGION}"

if [[ ! "$AWS_REGION" =~ ^[a-z0-9-]+$ ]]; then
  echo "AWS_REGION must contain only lowercase letters, digits, and hyphens." >&2
  exit 2
fi
if [[ ! "$bucket_region" =~ ^[a-z0-9-]+$ ]]; then
  echo "SSM_TRANSFER_BUCKET_REGION must contain only lowercase letters, digits, and hyphens." >&2
  exit 2
fi

if [[ ! "$SSM_TRANSFER_BUCKET" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]]; then
  echo "SSM_TRANSFER_BUCKET must be a valid 3-63 character S3 bucket name." >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
ansible_dir="$repo_root/ansible"
temporary_inventory="$(mktemp "$ansible_dir/inventory/.generated-XXXXXX.aws_ec2.yml")"
trap 'rm -f "$temporary_inventory"' EXIT

sed \
  -e "s/__AWS_REGION__/${AWS_REGION}/g" \
  -e "s/REPLACE_WITH_PRIVATE_SSM_TRANSFER_BUCKET/${SSM_TRANSFER_BUCKET}/g" \
  "$ansible_dir/inventory/aws_ec2.yml" > "$temporary_inventory"

echo "Caller identity:"
aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION"

echo "Checking SSM transfer bucket access: $SSM_TRANSFER_BUCKET"
if ! aws s3api head-bucket \
  --bucket "$SSM_TRANSFER_BUCKET" \
  --profile "$AWS_PROFILE" \
  --region "$bucket_region"; then
  echo "Cannot access SSM_TRANSFER_BUCKET='$SSM_TRANSFER_BUCKET' in '$bucket_region'. Check the bucket and s3:ListBucket access for '$AWS_PROFILE'." >&2
  exit 1
fi

echo "Running inventory and configuration for profile=${AWS_PROFILE}, region=${AWS_REGION}"
cd "$ansible_dir"
if ! ANSIBLE_CONFIG="$ansible_dir/ansible.cfg" ansible-doc -t inventory amazon.aws.aws_ec2 >/dev/null ||
   ! ANSIBLE_CONFIG="$ansible_dir/ansible.cfg" ansible-doc -t connection amazon.aws.aws_ssm >/dev/null; then
  echo "Required amazon.aws inventory/SSM plugins are unavailable. Install them with: ansible-galaxy collection install -r \"$repo_root/ansible/requirements.yml\"" >&2
  exit 1
fi

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  echo "The AWS Session Manager plugin is required in the Ansible controller environment. Install it using the AWS instructions for your Linux distribution, then rerun this script." >&2
  exit 1
fi

echo "Publishing the Ansible-rendered CloudWatch Agent configuration to Parameter Store"
ANSIBLE_CONFIG="$ansible_dir/ansible.cfg" AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" \
  ansible-playbook -i 'localhost,' playbooks/publish-cloudwatch-agent-config.yml

inventory_json="$(ANSIBLE_CONFIG="$ansible_dir/ansible.cfg" AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" \
  ansible-inventory -i "$temporary_inventory" --list)"
if ! printf '%s\n' "$inventory_json" | python3 -c '
import json
import sys

inventory = json.load(sys.stdin)
hosts = set()
visited_groups = set()

def collect_hosts(group):
    if isinstance(group, str):
        if group in visited_groups:
            return
        visited_groups.add(group)
        group = inventory.get(group, {})
    hosts.update(group.get("hosts", []))
    for child in group.get("children", []):
        collect_hosts(child)

collect_hosts(inventory.get("all", {}))
count = len(hosts)
print(f"Discovered {count} eligible instance(s).")
if count == 0:
    print("No hosts were discovered. Check amazon.aws dependencies, AWS credentials, Region, and DiskMonitoring=enabled tags.", file=sys.stderr)
    sys.exit(1)
'; then
  exit 1
fi

ANSIBLE_CONFIG="$ansible_dir/ansible.cfg" AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" \
  ansible-playbook -i "$temporary_inventory" playbooks/configure-cloudwatch-agent.yml
ANSIBLE_CONFIG="$ansible_dir/ansible.cfg" AWS_PROFILE="$AWS_PROFILE" AWS_REGION="$AWS_REGION" \
  ansible-playbook -i "$temporary_inventory" playbooks/validate-enrollment.yml
