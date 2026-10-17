variable "name" {
  type = string
}

variable "instance_count" {
  type = number
}

variable "instance_type" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "instance_profile" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
