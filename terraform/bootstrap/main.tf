# Bootstrap — creates the S3 state buckets and DynamoDB lock table that all
# other Terraform environments depend on.
#
# Run this ONCE from a fresh AWS account before running any other environment:
#
#   cd terraform/bootstrap
#   terraform init          # uses local state — intentional
#   terraform apply
#
# After apply, commit the generated terraform.tfstate here (or store it safely).
# Do NOT run this again unless you are recreating the entire account.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
  }
  # Intentionally uses local state — this is the bootstrap, it cannot use remote state yet.
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Project = "ShopCloud"; ManagedBy = "Terraform-Bootstrap" }
  }
}

provider "aws" {
  alias  = "eu"
  region = "eu-west-1"
  default_tags {
    tags = { Project = "ShopCloud"; ManagedBy = "Terraform-Bootstrap" }
  }
}

# ─── DynamoDB lock table (shared across all environments) ────────────────────

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "shopcloud-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery { enabled = true }

  server_side_encryption { enabled = true }

  tags = { Name = "shopcloud-terraform-locks" }
}

# ─── State bucket — dev (us-east-1) ─────────────────────────────────────────

resource "aws_s3_bucket" "state_dev" {
  bucket = "shopcloud-terraform-state-dev"
  tags   = { Name = "shopcloud-terraform-state-dev"; Environment = "dev" }
}

resource "aws_s3_bucket_versioning" "state_dev" {
  bucket = aws_s3_bucket.state_dev.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_dev" {
  bucket = aws_s3_bucket.state_dev.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state_dev" {
  bucket                  = aws_s3_bucket.state_dev.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── State bucket — prod (us-east-1) ─────────────────────────────────────────

resource "aws_s3_bucket" "state_prod" {
  bucket = "shopcloud-terraform-state-prod"
  tags   = { Name = "shopcloud-terraform-state-prod"; Environment = "prod" }
}

resource "aws_s3_bucket_versioning" "state_prod" {
  bucket = aws_s3_bucket.state_prod.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_prod" {
  bucket = aws_s3_bucket.state_prod.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state_prod" {
  bucket                  = aws_s3_bucket.state_prod.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── State bucket — prod-eu (eu-west-1) ──────────────────────────────────────

resource "aws_s3_bucket" "state_prod_eu" {
  provider = aws.eu
  bucket   = "shopcloud-terraform-state-prod-eu"
  tags     = { Name = "shopcloud-terraform-state-prod-eu"; Environment = "prod-eu" }
}

resource "aws_s3_bucket_versioning" "state_prod_eu" {
  provider = aws.eu
  bucket   = aws_s3_bucket.state_prod_eu.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_prod_eu" {
  provider = aws.eu
  bucket   = aws_s3_bucket.state_prod_eu.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "state_prod_eu" {
  provider                = aws.eu
  bucket                  = aws_s3_bucket.state_prod_eu.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "next_steps" {
  value = <<-EOT
    Bootstrap complete. Run these in order:
      1. cd ../environments/dev   && terraform init && terraform apply
      2. cd ../environments/prod  && terraform init && terraform apply
      3. cd ../environments/prod-eu && terraform init && terraform apply
  EOT
}
