variable "name" {
  type = string
}

variable "instance_ids" {
  type = list(string)
}

variable "topic_arn" {
  type = string
}

variable "warning_percent" {
  type = number
}

variable "critical_percent" {
  type = number
}

variable "tags" {
  type    = map(string)
  default = {}
}
