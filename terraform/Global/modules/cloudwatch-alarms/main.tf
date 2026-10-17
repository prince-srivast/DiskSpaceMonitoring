resource "aws_cloudwatch_metric_alarm" "warning" {
  count = length(var.instance_ids)

  alarm_name          = "${var.name}-instance-${format("%02d", count.index + 1)}-root-warning"
  alarm_description   = "Root filesystem usage reached the warning threshold."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = var.warning_percent
  treat_missing_data  = "missing"
  dimensions = {
    InstanceId = var.instance_ids[count.index]
    path       = "/"
  }
  alarm_actions = [var.topic_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "critical" {
  count = length(var.instance_ids)

  alarm_name          = "${var.name}-instance-${format("%02d", count.index + 1)}-root-critical"
  alarm_description   = "Root filesystem usage reached the critical threshold."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  metric_name         = "disk_used_percent"
  namespace           = "CWAgent"
  period              = 300
  statistic           = "Average"
  threshold           = var.critical_percent
  treat_missing_data  = "missing"
  dimensions = {
    InstanceId = var.instance_ids[count.index]
    path       = "/"
  }
  alarm_actions = [var.topic_arn]
  tags          = var.tags
}
