resource "aws_iam_role" "lambda" {
  name = "${var.name}-invoice-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = var.sqs_queue_arn
      },
      {
        Sid    = "S3Upload"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject"]
        Resource = "${var.invoices_bucket_arn}/*"
      },
      {
        Sid    = "SESSend"
        Effect = "Allow"
        Action = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = var.kms_key_arn
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "VPCAccess"
        Effect = "Allow"
        Action = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "lambda" {
  name        = "${var.name}-lambda-sg"
  description = "Security group for invoice Lambda"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS to AWS services"
  }

  tags = merge(var.tags, { Name = "${var.name}-lambda-sg" })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name}-invoice-generator"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_lambda_function" "invoice_generator" {
  function_name = "${var.name}-invoice-generator"
  role          = aws_iam_role.lambda.arn
  handler       = "src/index.handler"
  runtime       = "nodejs20.x"
  timeout       = 60
  memory_size   = 512

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      AWS_REGION       = var.aws_region
      INVOICES_BUCKET  = var.invoices_bucket_name
      SENDER_EMAIL     = var.sender_email
      LOG_LEVEL        = var.log_level
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  tracing_config { mode = "Active" }

  depends_on = [aws_cloudwatch_log_group.lambda]
  tags       = var.tags
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.invoice_generator.arn
  batch_size       = 10
  enabled          = true

  function_response_types = ["ReportBatchItemFailures"]
}

resource "aws_lambda_function_event_invoke_config" "invoice_generator" {
  function_name          = aws_lambda_function.invoice_generator.function_name
  maximum_retry_attempts = 0 # SQS handles retries via visibility timeout
}
