variable "account_id" {
  type = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Enter a 12-digit AWS account ID."
  }
}

variable "region_1" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)+$", var.region_1))
    error_message = "Enter a valid AWS Region name."
  }
}

variable "region_2" {
  type = string

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)+$", var.region_2)) && var.region_2 != var.region_1
    error_message = "Enter a valid AWS Region different from region_1."
  }
}

variable "region_1_vpc_cidr" {
  type    = string
  default = "10.240.0.0/16"

  validation {
    condition     = try(cidrnetmask(var.region_1_vpc_cidr) != "" && tonumber(split("/", var.region_1_vpc_cidr)[1]) >= 16 && tonumber(split("/", var.region_1_vpc_cidr)[1]) <= 20, false)
    error_message = "Use a valid IPv4 CIDR from /16 through /20."
  }
}

variable "region_2_vpc_cidr" {
  type    = string
  default = "10.241.0.0/16"

  validation {
    condition     = try(cidrnetmask(var.region_2_vpc_cidr) != "" && tonumber(split("/", var.region_2_vpc_cidr)[1]) >= 16 && tonumber(split("/", var.region_2_vpc_cidr)[1]) <= 20, false)
    error_message = "Use a valid IPv4 CIDR from /16 through /20."
  }
}

variable "region_1_instance_count" {
  type    = number
  default = 3

  validation {
    condition     = var.region_1_instance_count >= 1 && var.region_1_instance_count <= 10 && floor(var.region_1_instance_count) == var.region_1_instance_count
    error_message = "Use between 1 and 10 instances per Region."
  }
}

variable "region_2_instance_count" {
  type    = number
  default = 2

  validation {
    condition     = var.region_2_instance_count >= 1 && var.region_2_instance_count <= 10 && floor(var.region_2_instance_count) == var.region_2_instance_count
    error_message = "Use between 1 and 10 instances per Region."
  }
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "notification_email" {
  type = string

  validation {
    condition     = can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", var.notification_email))
    error_message = "Enter a valid email address for SNS notifications."
  }
}

variable "disk_warning_percent" {
  type    = number
  default = 80

  validation {
    condition     = var.disk_warning_percent > 0 && var.disk_warning_percent < 100
    error_message = "The warning threshold must be between 1 and 99."
  }
}

variable "disk_critical_percent" {
  type    = number
  default = 90

  validation {
    condition     = var.disk_critical_percent > 0 && var.disk_critical_percent <= 100
    error_message = "The critical threshold must be between 1 and 100."
  }
}
