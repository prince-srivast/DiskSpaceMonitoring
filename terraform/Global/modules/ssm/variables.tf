variable "name" {
  type = string
}

variable "config_json" {
  type = string
}

variable "target_key" {
  type = string
}

variable "target_value" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
