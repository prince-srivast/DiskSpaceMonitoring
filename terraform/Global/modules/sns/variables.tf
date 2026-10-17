variable "topic_name" {
  type = string
}

variable "email" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
