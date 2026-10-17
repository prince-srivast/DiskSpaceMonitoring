# Operations runbook

## Disk warning / critical
1. Identify account, Region, instance ID, mount path, application owner, and current utilization trend.
2. Check free bytes and inodes, not only percentage. A small filesystem can reach 100% quickly.
3. Determine whether growth is logs, temporary files, application data, snapshots, or an undersized volume.
4. Follow the workload's approved cleanup procedure. Do not delete files blindly or remove active database files.
5. If appropriate, extend the EBS volume and grow the partition/filesystem under the team's change process.
6. Confirm utilization falls and the alarm returns to OK. Record cause and prevention action.

## No metrics / no SSM
1. Confirm the instance is running and has `DiskMonitoring=enabled`.
2. Confirm SSM Agent is installed/running and the instance appears as `Online` in Systems Manager.
3. Verify the EC2 instance profile includes SSM core permissions and the least-privilege CloudWatch Agent publishing permissions.
4. Verify DNS and outbound access to SSM and CloudWatch endpoints, or required VPC interface endpoints.
5. Inspect `/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log` on Linux.
6. Check the `disk-monitoring-auto-enrollment` State Manager association status and command output. If needed, rerun `scripts/enroll-account.sh` to reapply the Ansible role and validate the instance, then wait for the next collection interval and confirm a fresh datapoint.
7. If an entire account is missing, check member role, trust policy, Region enablement, and central observability configuration.

## Safe validation
- Validate on a non-production instance.
- Use CloudWatch Agent's own status command and check the latest metric timestamp.
- For alert testing, use a temporary test alarm with a deliberately low threshold on a test instance. Do not fill a production disk.
- Verify SNS subscription confirmation and incident routing before declaring the rollout complete.
