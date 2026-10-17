variable "name" {
  type = string
}

variable "parameter_arn" {
  type = string
}

variable "transfer_bucket_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
