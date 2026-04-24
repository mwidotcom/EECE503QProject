resource "aws_s3_bucket" "invoices" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = merge(var.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_versioning" "invoices" {
  bucket = aws_s3_bucket.invoices.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "invoices" {
  bucket = aws_s3_bucket.invoices.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "invoices" {
  bucket                  = aws_s3_bucket.invoices.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "invoices" {
  bucket = aws_s3_bucket.invoices.id

  rule {
    id     = "archive-old-invoices"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 365
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

resource "aws_s3_bucket_policy" "invoices" {
  bucket = aws_s3_bucket.invoices.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLSRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["${aws_s3_bucket.invoices.arn}", "${aws_s3_bucket.invoices.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid    = "AllowLambdaAccess"
        Effect = "Allow"
        Principal = { AWS = var.lambda_role_arn }
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "${aws_s3_bucket.invoices.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "invoices" {
  bucket = aws_s3_bucket.invoices.id
}
