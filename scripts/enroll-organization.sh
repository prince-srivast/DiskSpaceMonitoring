#!/usr/bin/env bash
set -euo pipefail

: "${AWS_PROFILE:?Set AWS_PROFILE to an AWS Organizations management/delegated-admin profile}"
: "${AWS_ROLE_EXTERNAL_ID:?Set AWS_ROLE_EXTERNAL_ID to the value configured in each member-role trust policy}"
: "${SSM_TRANSFER_BUCKET:?Set SSM_TRANSFER_BUCKET to a private S3 bucket accessible to the assumed member roles}"
export AWS_PROFILE SSM_TRANSFER_BUCKET

member_role_name="${AWS_MEMBER_ROLE_NAME:-DiskMonitoringAutomationRole}"
max_parallel="${MAX_PARALLEL:-4}"

if [[ ! "$member_role_name" =~ ^[A-Za-z0-9+=,.@_-]{1,64}$ ]]; then
  echo "AWS_MEMBER_ROLE_NAME must be a valid IAM role name without a path." >&2
  exit 2
fi
if [[ ! "$AWS_ROLE_EXTERNAL_ID" =~ ^[A-Za-z0-9+=,.@:/_-]{2,1224}$ ]]; then
  echo "AWS_ROLE_EXTERNAL_ID must be 2-1224 characters and contain no whitespace." >&2
  exit 2
fi
if [[ ! "$max_parallel" =~ ^[0-9]+$ ]] || (( max_parallel < 1 || max_parallel > 32 )); then
  echo "MAX_PARALLEL must be an integer between 1 and 32." >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
original_aws_config="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
management_region="${AWS_REGION:-us-east-1}"
if [[ ! "$management_region" =~ ^[a-z0-9-]+$ ]]; then
  echo "AWS_REGION must contain only lowercase letters, digits, and hyphens." >&2
  exit 2
fi
temporary_aws_config="$(mktemp)"
chmod 600 "$temporary_aws_config"
trap 'rm -f "$temporary_aws_config"' EXIT
if [[ -f "$original_aws_config" ]]; then
  cat "$original_aws_config" > "$temporary_aws_config"
fi
export AWS_CONFIG_FILE="$temporary_aws_config"

source_account_id="$(aws sts get-caller-identity \
  --profile "$AWS_PROFILE" \
  --region "$management_region" \
  --query Account \
  --output text)"
account_ids="$(aws organizations list-accounts \
  --profile "$AWS_PROFILE" \
  --region "$management_region" \
  --query 'Accounts[?State==`ACTIVE`].Id' \
  --output text)"
if [[ -z "$account_ids" ]]; then
  echo "AWS Organizations returned no active accounts." >&2
  exit 1
fi

declare -a job_accounts=()
declare -a job_regions=()
declare -a job_profiles=()
profile_prefix="disk-monitoring-${BASHPID}"
total_jobs=0

for account_id in $account_ids; do
  if [[ ! "$account_id" =~ ^[0-9]{12}$ ]]; then
    echo "Organizations returned an invalid account ID: $account_id" >&2
    exit 1
  fi

  if [[ "$account_id" == "$source_account_id" ]]; then
    target_profile="$AWS_PROFILE"
  else
    target_profile="${profile_prefix}-${account_id}"
    {
      printf '\n[profile %s]\n' "$target_profile"
      printf 'role_arn = arn:aws:iam::%s:role/%s\n' "$account_id" "$member_role_name"
      printf 'source_profile = %s\n' "$AWS_PROFILE"
      printf 'external_id = %s\n' "$AWS_ROLE_EXTERNAL_ID"
      printf 'role_session_name = DiskMonitoringAnsible\n'
    } >> "$temporary_aws_config"
  fi

  resolved_account_id="$(aws sts get-caller-identity \
    --profile "$target_profile" \
    --region us-east-1 \
    --query Account \
    --output text)" || {
    echo "Could not assume the monitoring role in account $account_id." >&2
    exit 1
  }
  if [[ "$resolved_account_id" != "$account_id" ]]; then
    echo "Profile '$target_profile' resolved to account $resolved_account_id, expected $account_id." >&2
    exit 1
  fi

  region_output="$(aws ec2 describe-regions \
    --all-regions \
    --profile "$target_profile" \
    --region us-east-1 \
    --query 'Regions[?OptInStatus==`opt-in-not-required` || OptInStatus==`opted-in`].RegionName' \
    --output text)"
  read -r -a enabled_regions <<< "$region_output"
  if [[ -n "${DISK_MONITORING_REGIONS:-}" ]]; then
    requested_regions="${DISK_MONITORING_REGIONS//,/ }"
    read -r -a regions <<< "$requested_regions"
    for region in "${regions[@]}"; do
      if [[ ! " ${enabled_regions[*]} " == *" $region "* ]]; then
        echo "Requested Region '$region' is not enabled for account $account_id." >&2
        exit 1
      fi
    done
  else
    regions=("${enabled_regions[@]}")
  fi
  if (( ${#regions[@]} == 0 )); then
    echo "No enabled Regions found for account $account_id." >&2
    exit 1
  fi

  for region in "${regions[@]}"; do
    if [[ ! "$region" =~ ^[a-z0-9-]+$ ]]; then
      echo "Invalid AWS Region '$region' in account $account_id." >&2
      exit 2
    fi
    job_accounts+=("$account_id")
    job_regions+=("$region")
    job_profiles+=("$target_profile")
    ((total_jobs += 1))
  done
done

echo "Prepared $total_jobs account/Region enrollment job(s); maximum concurrency: $max_parallel."

declare -a pids=()
failures=0
wait_batch() {
  local pid
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      ((failures += 1))
    fi
  done
  pids=()
}

for index in "${!job_accounts[@]}"; do
  account_id="${job_accounts[$index]}"
  region="${job_regions[$index]}"
  profile="${job_profiles[$index]}"
  echo "Starting enrollment for account=$account_id region=$region"
  (
    export AWS_PROFILE="$profile"
    export AWS_REGION="$region"
    export SSM_TRANSFER_BUCKET
    "$repo_root/scripts/enroll-account.sh"
  ) &
  pids+=("$!")
  if (( ${#pids[@]} >= max_parallel )); then
    wait_batch
  fi
done
if (( ${#pids[@]} > 0 )); then
  wait_batch
fi

if (( failures > 0 )); then
  echo "$failures account/Region enrollment job(s) failed." >&2
  exit 1
fi
echo "All $total_jobs account/Region enrollment job(s) completed successfully."
