resource "aws_ssm_parameter" "agent_config" {
  name        = "/disk-monitoring/cloudwatch-agent-config"
  description = "CloudWatch Agent disk metrics configuration."
  type        = "String"
  value       = var.config_json
  overwrite   = true
  tags        = var.tags
}

resource "aws_ssm_document" "install_agent" {
  name            = "DiskMonitoring-InstallCloudWatchAgent"
  document_type   = "Command"
  document_format = "JSON"
  target_type     = "/AWS::EC2::Instance"
  tags            = var.tags

  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Install and configure the CloudWatch Agent."
    mainSteps = [
      {
        action = "aws:configurePackage"
        name   = "installCloudWatchAgent"
        inputs = {
          name   = "AmazonCloudWatchAgent"
          action = "Install"
        }
      },
      {
        action = "aws:runShellScript"
        name   = "configureCloudWatchAgent"
        inputs = {
          runCommand = [
            "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:${aws_ssm_parameter.agent_config.name}"
          ]
        }
      }
    ]
  })
}

resource "aws_ssm_association" "auto_enroll" {
  name                        = aws_ssm_document.install_agent.name
  association_name            = "disk-monitoring-${var.name}"
  max_concurrency             = "10%"
  max_errors                  = "1"
  apply_only_at_cron_interval = false

  targets {
    key    = var.target_key
    values = [var.target_value]
  }
}

output "parameter_arn" {
  value = aws_ssm_parameter.agent_config.arn
}

output "association_id" {
  value = aws_ssm_association.auto_enroll.association_id
}
