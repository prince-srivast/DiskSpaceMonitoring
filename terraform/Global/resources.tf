module "network_region_1" {
  source = "./modules/vpc"

  providers = {
    aws = aws
  }

  name = "disk-monitoring-${var.region_1}"
  cidr = var.region_1_vpc_cidr
  tags = local.common_tags
}

module "network_region_2" {
  source = "./modules/vpc"

  providers = {
    aws = aws.region_2
  }

  name = "disk-monitoring-${var.region_2}"
  cidr = var.region_2_vpc_cidr
  tags = local.common_tags
}

module "s3_region_1" {
  source = "./modules/s3"

  providers = {
    aws = aws
  }

  bucket_name = "diskmon-ssm-${var.account_id}-${var.region_1}"
  tags        = local.common_tags
}

module "s3_region_2" {
  source = "./modules/s3"

  providers = {
    aws = aws.region_2
  }

  bucket_name = "diskmon-ssm-${var.account_id}-${var.region_2}"
  tags        = local.common_tags
}

module "ssm_region_1" {
  source = "./modules/ssm"

  providers = {
    aws = aws
  }

  name         = "disk-monitoring-${var.region_1}"
  config_json  = local.agent_config
  target_key   = "tag:DiskMonitoring"
  target_value = "enabled"
  tags         = local.common_tags
}

module "ssm_region_2" {
  source = "./modules/ssm"

  providers = {
    aws = aws.region_2
  }

  name         = "disk-monitoring-${var.region_2}"
  config_json  = local.agent_config
  target_key   = "tag:DiskMonitoring"
  target_value = "enabled"
  tags         = local.common_tags
}

module "iam_region_1" {
  source = "./modules/iam"

  providers = {
    aws = aws
  }

  name                = "disk-monitoring-${var.region_1}"
  parameter_arn       = module.ssm_region_1.parameter_arn
  transfer_bucket_arn = module.s3_region_1.bucket_arn
  tags                = local.common_tags
}

module "iam_region_2" {
  source = "./modules/iam"

  providers = {
    aws = aws.region_2
  }

  name                = "disk-monitoring-${var.region_2}"
  parameter_arn       = module.ssm_region_2.parameter_arn
  transfer_bucket_arn = module.s3_region_2.bucket_arn
  tags                = local.common_tags
}

module "ec2_region_1" {
  source = "./modules/ec2"

  providers = {
    aws = aws
  }

  name             = "disk-monitoring-${var.region_1}"
  instance_count   = var.region_1_instance_count
  instance_type    = var.instance_type
  subnet_ids       = module.network_region_1.public_subnet_ids
  instance_profile = module.iam_region_1.instance_profile_name
  tags             = local.common_tags

  depends_on = [module.ssm_region_1]
}

module "ec2_region_2" {
  source = "./modules/ec2"

  providers = {
    aws = aws.region_2
  }

  name             = "disk-monitoring-${var.region_2}"
  instance_count   = var.region_2_instance_count
  instance_type    = var.instance_type
  subnet_ids       = module.network_region_2.public_subnet_ids
  instance_profile = module.iam_region_2.instance_profile_name
  tags             = local.common_tags

  depends_on = [module.ssm_region_2]
}

module "sns_region_1" {
  source = "./modules/sns"

  providers = {
    aws = aws
  }

  topic_name = "disk-monitoring-alerts"
  email      = var.notification_email
  tags       = local.common_tags
}

module "sns_region_2" {
  source = "./modules/sns"

  providers = {
    aws = aws.region_2
  }

  topic_name = "disk-monitoring-alerts"
  email      = var.notification_email
  tags       = local.common_tags
}

module "alarms_region_1" {
  source = "./modules/cloudwatch-alarms"

  providers = {
    aws = aws
  }

  name             = "disk-${var.region_1}"
  instance_ids     = module.ec2_region_1.instance_ids
  topic_arn        = module.sns_region_1.topic_arn
  warning_percent  = var.disk_warning_percent
  critical_percent = var.disk_critical_percent
  tags             = local.common_tags
}

module "alarms_region_2" {
  source = "./modules/cloudwatch-alarms"

  providers = {
    aws = aws.region_2
  }

  name             = "disk-${var.region_2}"
  instance_ids     = module.ec2_region_2.instance_ids
  topic_arn        = module.sns_region_2.topic_arn
  warning_percent  = var.disk_warning_percent
  critical_percent = var.disk_critical_percent
  tags             = local.common_tags
}

resource "aws_cloudwatch_dashboard" "fleet" {
  dashboard_name = "Disk-Monitoring-Fleet"
  dashboard_body = jsonencode({
    widgets = concat(
      [{
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# Disk Monitoring Test Fleet\nMetrics are grouped by Region. Missing data means an instance or agent needs attention."
        }
      }],
      [for index, region in [var.region_1, var.region_2] : {
        type   = "metric"
        x      = 0
        y      = 2 + index * 8
        width  = 24
        height = 8
        properties = {
          view   = "timeSeries"
          region = region
          title  = "Disk utilization - ${region}"
          period = 300
          stat   = "Average"
          metrics = [[{
            expression = "SEARCH('{CWAgent,InstanceId,path} MetricName=\"disk_used_percent\"', 'Average', 300)"
            id         = "e1"
          }]]
        }
      }]
    )
  })
}

