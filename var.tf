variable "ruleset_name" {
  type    = string
  default = "household"
}

variable "inboxes" {
  type    = list(string)
  default = ["jonathan", "maria"]
}

variable "domain" {
  type    = string
  default = "mariapiao.com"
}

variable "s3_bucket_name" {
  type    = string
  default = "mariapiao.com"
}

variable "region" {
  type    = string
  default = "us-west-2"
}

variable "aws_profile" {
  type    = string
  default = "email-admin"
}
