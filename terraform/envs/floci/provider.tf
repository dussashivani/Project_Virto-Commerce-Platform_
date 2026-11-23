# EMULATOR-ONLY provider configuration. Everything here points at Floci (localhost:4566).
# Real AWS lives in ../aws and must never reuse this file.
variable "floci_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test" # dummy credential accepted by the emulator
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    s3             = var.floci_endpoint
    ec2            = var.floci_endpoint
    iam            = var.floci_endpoint
    sts            = var.floci_endpoint
    ecs            = var.floci_endpoint
    logs           = var.floci_endpoint
    secretsmanager = var.floci_endpoint
    elbv2          = var.floci_endpoint
    cloudwatch     = var.floci_endpoint
  }
}
