# Dead-letter queue
resource "aws_sqs_queue" "invoice_dlq" {
  name                      = "${var.name}-invoice-dlq.fifo"
  fifo_queue                = true
  content_based_deduplication = true
  kms_master_key_id         = var.kms_key_id
  message_retention_seconds = 1209600 # 14 days
  tags                      = merge(var.tags, { Name = "${var.name}-invoice-dlq" })
}

# Main invoice queue
resource "aws_sqs_queue" "invoice" {
  name                        = "${var.name}-invoice.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  kms_master_key_id           = var.kms_key_id
  visibility_timeout_seconds  = 300
  message_retention_seconds   = 86400
  receive_wait_time_seconds   = 20 # long-polling

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.invoice_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(var.tags, { Name = "${var.name}-invoice" })
}

resource "aws_sqs_queue_policy" "invoice" {
  queue_url = aws_sqs_queue.invoice.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCheckoutServicePublish"
        Effect = "Allow"
        Principal = { AWS = var.checkout_service_role_arn }
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.invoice.arn
      },
      {
        Sid    = "AllowLambdaConsume"
        Effect = "Allow"
        Principal = { AWS = var.lambda_role_arn }
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.invoice.arn
      }
    ]
  })
}

# CloudWatch alarm on DLQ depth
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.name}-invoice-dlq-depth"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages in invoice DLQ — invoice generation failures"
  alarm_actions       = var.alarm_sns_arns
  ok_actions          = var.alarm_sns_arns

  dimensions = { QueueName = aws_sqs_queue.invoice_dlq.name }
  tags       = var.tags
}
