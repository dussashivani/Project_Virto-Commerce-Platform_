variable "region" {
  type    = string
  default = "eu-central-1"
}
variable "name" {
  type    = string
  default = "virto-prod"
}
variable "azs" {
  type    = list(string)
  default = ["eu-central-1a", "eu-central-1b"]
}
variable "acm_certificate_arn" {
  type        = string
  description = "ACM certificate for the public HTTPS listener"
}
variable "platform_image" {
  type        = string
  description = "Platform image pinned by digest or version tag, hosted in ECR"
}
variable "storefront_image" {
  type        = string
  description = "Storefront image pinned by digest or version tag, hosted in ECR"
}
variable "db_instance_class" {
  type    = string
  default = "db.t3.xlarge"
}
variable "desired_count" {
  type    = number
  default = 2
}
variable "alarm_email" { type = string }
