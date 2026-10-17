#!/usr/bin/env bash
set -euo pipefail
: "${AWS_PROFILE:?Set AWS_PROFILE to the assumed member-account role profile}"
: "${AWS_REGION:=us-east-1}"

aws ssm describe-instance-information \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'InstanceInformationList[].{InstanceId:InstanceId,PingStatus:PingStatus,PlatformName:PlatformName,AgentVersion:AgentVersion}' \
  --output table
