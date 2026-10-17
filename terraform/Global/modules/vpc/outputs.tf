output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [for zone in local.availability_zones : aws_subnet.public[zone].id]
}
