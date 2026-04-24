# CloudWatch alarms complement Prometheus for AWS-native metrics

locals {
  sns_arn = var.alerts_sns_arn
}

# ─── ALB ─────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx_rate" {
  alarm_name          = "${var.name}-alb-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 5
  alarm_description   = "ALB 5xx error rate > 5%"
  alarm_actions       = [local.sns_arn]
  ok_actions          = [local.sns_arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "m_5xx / m_total * 100"
    label       = "5xx Rate %"
    return_data = true
  }
  metric_query {
    id = "m_5xx"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }
  metric_query {
    id = "m_total"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "alb_target_response_time" {
  alarm_name          = "${var.name}-alb-p99-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 2.0
  alarm_description   = "ALB p99 response time > 2s"
  alarm_actions       = [local.sns_arn]
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  tags                = var.tags
}

# ─── RDS ─────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.name}-rds-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU > 80%"
  alarm_actions       = [local.sns_arn]
  dimensions          = { DBInstanceIdentifier = var.rds_identifier }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "${var.name}-rds-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 400
  alarm_description   = "RDS connection count > 400"
  alarm_actions       = [local.sns_arn]
  dimensions          = { DBInstanceIdentifier = var.rds_identifier }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage" {
  alarm_name          = "${var.name}-rds-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 10737418240 # 10 GB
  alarm_description   = "RDS free storage < 10 GB"
  alarm_actions       = [local.sns_arn]
  dimensions          = { DBInstanceIdentifier = var.rds_identifier }
  tags                = var.tags
}

# ─── ElastiCache ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "redis_memory" {
  alarm_name          = "${var.name}-redis-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Redis memory > 80%"
  alarm_actions       = [local.sns_arn]
  dimensions          = { ReplicationGroupId = var.redis_replication_group_id }
  tags                = var.tags
}

# ─── Lambda ──────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.name}-lambda-invoice-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 3
  alarm_description   = "Invoice Lambda errors > 3 in 5 minutes"
  alarm_actions       = [local.sns_arn]
  dimensions          = { FunctionName = var.lambda_function_name }
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.name}-lambda-invoice-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p99"
  threshold           = 50000 # 50s (function timeout is 60s)
  alarm_description   = "Invoice Lambda p99 duration > 50s"
  alarm_actions       = [local.sns_arn]
  dimensions          = { FunctionName = var.lambda_function_name }
  tags                = var.tags
}

# ─── CloudFront ──────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx" {
  provider            = aws.us_east_1
  alarm_name          = "${var.name}-cloudfront-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 5
  alarm_description   = "CloudFront 5xx error rate > 5%"
  alarm_actions       = [local.sns_arn]
  dimensions = {
    DistributionId = var.cloudfront_distribution_id
    Region         = "Global"
  }
  tags = var.tags
}
