# REAL AWS reference design - PROPOSED, NEVER APPLIED as part of this assignment.
# Applying creates PAID resources (NAT, ALB, RDS SQL Server, ElastiCache, Fargate). Requires explicit authorization.
# Not covered here (documented gap): search tier (self-managed Elasticsearch / Elastic Cloud / OpenSearch compatibility test).
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "virto-commerce", ManagedBy = "terraform" }
  }
}

module "network" {
  source = "../../modules/network"
  name   = var.name
  azs    = var.azs
}

# ---- Secrets (generated, never in code/state outputs/images)
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.name}/db-master"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id     = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({ username = "vcadmin", password = random_password.db.result })
}

# ---- Data tier: RDS for SQL Server (Multi-AZ, encrypted, private)
resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = module.network.private_data_subnet_ids
}

resource "aws_db_instance" "sql" {
  identifier                      = "${var.name}-sql"
  engine                          = "sqlserver-web"
  engine_version                  = "16.00"
  license_model                   = "license-included"
  instance_class                  = var.db_instance_class
  allocated_storage               = 100
  max_allocated_storage           = 300
  storage_encrypted               = true
  username                        = "vcadmin"
  password                        = random_password.db.result
  multi_az                        = true
  publicly_accessible             = false
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [module.network.sg_data]
  backup_retention_period         = 14
  deletion_protection             = true
  skip_final_snapshot             = false
  final_snapshot_identifier       = "${var.name}-sql-final"
  enabled_cloudwatch_logs_exports = ["error"]
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-cache"
  subnet_ids = module.network.private_data_subnet_ids
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.name}-redis"
  description                = "Virto cache"
  engine                     = "redis"
  node_type                  = "cache.t4g.small"
  num_cache_clusters         = 2
  automatic_failover_enabled = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [module.network.sg_data]
}

# ---- Storage + logs
resource "aws_s3_bucket" "assets" {
  bucket = "${var.name}-assets-${data.aws_caller_identity.me.account_id}"
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "me" {}

resource "aws_cloudwatch_log_group" "platform" {
  name              = "/ecs/${var.name}/platform"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "storefront" {
  name              = "/ecs/${var.name}/storefront"
  retention_in_days = 30
}

# ---- IAM (execution role pulls image/secrets; task role is what the app code gets)
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "exec_secrets" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_role_policy" "exec_secrets" {
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.exec_secrets.json
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "task" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.assets.arn}/*"]
  }
}

resource "aws_iam_role_policy" "task" {
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

# ---- ALB (HTTPS termination)
resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [module.network.sg_alb]
  subnets                    = module.network.public_subnet_ids
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "platform" {
  name        = "${var.name}-platform"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.network.vpc_id
  health_check {
    path    = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_target_group" "storefront" {
  name        = "${var.name}-storefront"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.network.vpc_id
  health_check {
    path    = "/"
    matcher = "200-399"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.acm_certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.storefront.arn
  }
}

resource "aws_lb_listener_rule" "admin" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.platform.arn
  }
  condition {
    path_pattern { values = ["/admin*", "/api/*", "/connect/*"] }
  }
}

# ---- ECS Fargate
resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "platform" {
  family                   = "${var.name}-platform"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 2048
  memory                   = 4096
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions = jsonencode([{
    name         = "platform"
    image        = var.platform_image
    essential    = true
    portMappings = [{ containerPort = 80 }]
    environment = [
      { name = "ASPNETCORE_URLS", value = "http://+:80" },
      { name = "Search__Provider", value = "ElasticSearch" },
    ]
    # Connection strings are assembled from the secret at startup (see docs/RUNBOOK.md section 7).
    secrets = [
      { name = "DB_SECRET_JSON", valueFrom = aws_secretsmanager_secret.db.arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.platform.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "platform"
      }
    }
  }])
}

resource "aws_ecs_service" "platform" {
  name            = "platform"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.platform.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = module.network.private_app_subnet_ids
    security_groups  = [module.network.sg_app]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.platform.arn
    container_name   = "platform"
    container_port   = 80
  }
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}

# ---- Alerting
resource "aws_sns_topic" "alerts" {
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name}-alb-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.this.arn_suffix }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name}-rds-cpu"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.sql.identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

output "alb_dns_name" { value = aws_lb.this.dns_name }
