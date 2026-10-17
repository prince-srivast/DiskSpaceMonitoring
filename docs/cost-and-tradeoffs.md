# Cost and trade-offs

## Cost-aware choices
| Component | Benefit | Cost / trade-off |
|---|---|---|
| CloudWatch Agent | Managed metric collection; no third-party agent platform | CloudWatch custom metric and API charges depend on metric cardinality, Region, and interval |
| 300-second interval | Finds sustained growth while reducing metric ingestion volume | Slower detection than 60-second collection |
| SSM | Secure fleet management and automation | SSM features have different pricing; verify the current pricing for the chosen features and Regions |
| CloudWatch alarms | Warning and critical thresholds with SNS notifications | Two alarms per monitored filesystem |
| Cross-account observability | Central view without duplicating every metric | Setup, supported Regions, and monitoring-account design need validation |
| OAM metrics links | Shared metrics are visible in monitoring accounts without copying each metric | Deploy a sink/link per Region and maintain the linked account/Region inventory |
| Fleet dashboard search | Fast discovery and visualization of metric series across linked accounts | CloudWatch search has result limits; use account/Region filters and explicit alarms for priority filesystems |
| Ansible | Reuses existing skill and configuration management | Requires a maintained runner and an account/Region execution strategy |
| SSM State Manager | Tag-targeted agent installation/configuration for new EC2 instances | Requires regional association rollout, Parameter Store config access, and compliance monitoring |

## Cardinality control
Disk metrics can multiply by instance count, mounted filesystem count, and metric dimensions. Keep the collection list focused:
- Start with `disk_used_percent` only.
- Exclude pseudo and ephemeral filesystems that do not represent actionable capacity.
- Use a 300-second collection interval initially.
- Avoid adding device, path, filesystem type, application, and arbitrary tags as metric dimensions unless they are required for alerting or investigation.
- Estimate monthly metric and alarm counts using the actual fleet before enabling across every account.
- The dashboard template renders one search widget per linked account/Region. Split the source inventory across dashboards if the account/Region count approaches CloudWatch dashboard limits; prioritize alarm coverage independently of dashboard search.

## Alternative approaches considered
1. **EC2 basic monitoring only:** does not provide filesystem-level utilization.
2. **Scheduled Ansible `df` polling:** easy to prototype but introduces controller scheduling, polling load, and gaps during controller outages; it is not the preferred continuous telemetry design.
3. **Third-party monitoring:** can offer richer analytics but adds licensing and another platform before native capabilities are evaluated.
4. **Custom Lambda/cron metric publisher:** avoids installing CloudWatch Agent but creates custom code, parsing, retry, and support burden.
5. **CloudWatch Agent + SSM + Ansible (selected):** uses native AWS telemetry and access controls while reusing the existing Ansible investment.

## Thresholds are starting points
80% warning and 90% critical are defaults, not universal truths. For small root volumes, inode exhaustion, rapid growth, and critical databases, tune thresholds based on workload, growth rate, and operational response time.

## Indicative AWS charges

For an existing EC2 fleet, the main monitoring charges are CloudWatch custom metrics and alarms. Systems Manager State Manager and Session Manager have no additional charge for EC2 instances. Standard Parameter Store parameters and standard-throughput requests are free. CloudWatch cross-account observability through OAM adds no charge when metrics are viewed across links without copying them. [Systems Manager pricing](https://aws.amazon.com/systems-manager/pricing/) · [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/)

The current agent configuration defines `aggregation_dimensions` without `drop_original_metrics`. CloudWatch Agent sends both original and aggregated metric series by default. Each unique metric and dimension combination is billable, so a filesystem may produce roughly two series: its original dimension set and the `InstanceId`/`path` aggregate. Confirm the actual count in CloudWatch after a canary deployment. [CloudWatch Agent configuration](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html)

As an estimate using published US East first-tier rates, one filesystem per VM, two custom metric series, and two standard alarms (warning and critical) costs about $0.80 per VM per month: $0.60 for the metrics and $0.20 for the alarms. A 1,000-VM fleet would be about $800 per month before eligible free usage, volume pricing, regional differences, and additional filesystems. If the original series are dropped and only the aggregate is retained, the estimate becomes about $0.50 per filesystem per month. Validate that the alarms still receive data before making this change. These are planning estimates, not a quote. [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/)

Other items to include in an estimate:
- SNS email deliveries are $2 per 100,000, with the first 1,000 notifications per month free. [SNS pricing FAQ](https://aws.amazon.com/sns/faqs/)
- The S3 transfer bucket is billed for storage, requests, and applicable transfer. A short lifecycle keeps temporary files from accumulating. [S3 pricing](https://aws.amazon.com/s3/pricing/)
- The Global test fleet uses five public IPv4 addresses. At $0.005 per address-hour, that is about $18 per 30-day month, before the five `t3.micro` instances and their five 8-GB gp3 volumes. Its VPC, subnets, routes, security groups, and Internet Gateways have no hourly charge by themselves. [VPC pricing](https://aws.amazon.com/vpc/pricing/)
- Private networking can add NAT Gateway or interface endpoint charges. S3 gateway endpoints have no hourly or data-processing charge. Check regional prices when choosing the production network path. [VPC pricing](https://aws.amazon.com/vpc/pricing/)
- An existing Ansible runner adds no new AWS compute cost. A new EC2 runner or paid control plane has its own cost. Enabling CloudWatch Logs for agent or SSM output adds log ingestion and storage charges; this design publishes metrics only.

The 300-second collection interval uses standard-resolution metrics. Cost is mainly driven by unique metric dimensions, monitored filesystems, and alarm count. Estimate those counts for the target Regions with the [AWS Pricing Calculator](https://calculator.aws/).
