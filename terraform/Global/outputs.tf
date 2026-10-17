output "account_id" {
  value = var.account_id
}

output "region_1_instance_ids" {
  value = module.ec2_region_1.instance_ids
}

output "region_1_vpc_id" {
  value = module.network_region_1.vpc_id
}

output "region_2_instance_ids" {
  value = module.ec2_region_2.instance_ids
}

output "region_2_vpc_id" {
  value = module.network_region_2.vpc_id
}

output "region_1_transfer_bucket" {
  value = module.s3_region_1.bucket_name
}

output "region_2_transfer_bucket" {
  value = module.s3_region_2.bucket_name
}

output "region_1_transfer_policy_arn" {
  value = module.iam_region_1.transfer_policy_arn
}

output "region_2_transfer_policy_arn" {
  value = module.iam_region_2.transfer_policy_arn
}

output "region_1_association_id" {
  value = module.ssm_region_1.association_id
}

output "region_2_association_id" {
  value = module.ssm_region_2.association_id
}
