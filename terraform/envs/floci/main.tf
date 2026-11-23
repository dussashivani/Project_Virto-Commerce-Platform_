# Emulated landing zone for Virto Commerce. Resources below exist ONLY inside Floci.
locals {
  name = "virto-local"
}

module "network" {
  source = "../../modules/network"
  name   = local.name
  azs    = ["us-east-1a", "us-east-1b"]
}

resource "aws_s3_bucket" "backups" {
  bucket = "${local.name}-backups"
}

resource "aws_s3_bucket" "assets" {
  bucket = "${local.name}-assets"
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name = "${local.name}/db-password"
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = random_password.db.result
}

resource "aws_cloudwatch_log_group" "platform" {
  name              = "/ecs/${local.name}/platform"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "storefront" {
  name              = "/ecs/${local.name}/storefront"
  retention_in_days = 14
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid       = "ReadOwnSecretOnly"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
  statement {
    sid       = "AssetsBucketRW"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.platform.arn}:*", "${aws_cloudwatch_log_group.storefront.arn}:*"]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "least-privilege"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"
}

output "backup_bucket" { value = aws_s3_bucket.backups.bucket }
output "cluster_arn" { value = aws_ecs_cluster.this.arn }
output "vpc_id" { value = module.network.vpc_id }
output "task_role_arn" { value = aws_iam_role.task.arn }
