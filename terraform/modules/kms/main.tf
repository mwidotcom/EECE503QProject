data "aws_caller_identity" "current" {}

resource "aws_kms_key" "main" {
  description             = "ShopCloud ${var.name} encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  multi_region            = var.multi_region

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch"
        Effect = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "*"
      },
      {
        Sid    = "Allow CloudTrail"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, { Name = "${var.name}-kms-key" })
}

resource "aws_kms_alias" "main" {
  name          = "alias/shopcloud-${var.name}"
  target_key_id = aws_kms_key.main.key_id
}
