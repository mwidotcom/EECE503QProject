terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {
    bucket         = "shopcloud-terraform-state-prod-eu"
    key            = "prod-eu/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "shopcloud-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = local.common_tags }
}

# WAF for CloudFront must always be created in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags { tags = local.common_tags }
}

locals {
  common_tags = {
    Project     = "ShopCloud"
    Environment = "prod-eu"
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
  }
  name         = "shopcloud-prod-eu"
  cluster_name = "shopcloud-prod-eu"
}

data "aws_caller_identity" "current" {}

# KMS key for all encryption in EU region
module "kms" {
  source       = "../../modules/kms"
  name         = local.name
  multi_region = true
  tags         = local.common_tags
}

# VPC — separate CIDR from US (10.0.0.0/16) to allow future peering
module "vpc" {
  source       = "../../modules/vpc"
  name         = local.name
  vpc_cidr     = var.vpc_cidr
  cluster_name = local.cluster_name
  aws_region   = var.aws_region
  tags         = local.common_tags
}

# EKS cluster
module "eks" {
  source                 = "../../modules/eks"
  cluster_name           = local.cluster_name
  kubernetes_version     = "1.29"
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  public_subnet_ids      = module.vpc.public_subnet_ids
  kms_key_arn            = module.kms.key_arn
  node_instance_types    = ["m6i.xlarge"]
  node_desired           = 3
  node_min               = 2
  node_max               = 12
  endpoint_public_access = false
  tags                   = local.common_tags
}

# RDS PostgreSQL — independent primary for EU (active-active, not a replica)
module "rds" {
  source                     = "../../modules/rds"
  identifier                 = "${local.name}-postgres"
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.node_sg_id]
  kms_key_arn                = module.kms.key_arn
  instance_class             = "db.r7g.large"
  allocated_storage          = 200
  max_allocated_storage      = 2000
  db_username                = var.db_username
  db_password                = var.db_password
  multi_az                   = true
  deletion_protection        = true
  backup_retention_period    = 14
  create_replica             = false
  tags                       = local.common_tags
}

# ElastiCache Redis — Multi-AZ
module "elasticache" {
  source                     = "../../modules/elasticache"
  name                       = local.name
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.node_sg_id]
  kms_key_arn                = module.kms.key_arn
  auth_token                 = var.redis_auth_token
  node_type                  = "cache.r7g.large"
  num_cache_clusters         = 3
  tags                       = local.common_tags
}

# Cognito — regional pools for EU users
module "cognito" {
  source = "../../modules/cognito"
  name   = local.name
  tags   = local.common_tags
}

# ECR — regional repositories for faster image pulls from EU EKS nodes
module "ecr" {
  source        = "../../modules/ecr"
  kms_key_arn   = module.kms.key_arn
  node_role_arn = module.eks.node_role_arn
  tags          = local.common_tags
}

# S3 for EU invoices
module "s3_invoices" {
  source          = "../../modules/s3"
  bucket_name     = "${local.name}-invoices-${data.aws_caller_identity.current.account_id}"
  kms_key_arn     = module.kms.key_arn
  lambda_role_arn = module.lambda.role_arn
  tags            = local.common_tags
}

# SQS invoice queue
module "sqs" {
  source                    = "../../modules/sqs"
  name                      = local.name
  kms_key_id                = module.kms.key_id
  checkout_service_role_arn = module.irsa_checkout.role_arn
  lambda_role_arn           = module.lambda.role_arn
  alarm_sns_arns            = [aws_sns_topic.alerts.arn]
  tags                      = local.common_tags
}

# Lambda invoice generator
module "lambda" {
  source               = "../../modules/lambda"
  name                 = local.name
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.private_subnet_ids
  sqs_queue_arn        = module.sqs.invoice_queue_arn
  invoices_bucket_arn  = module.s3_invoices.bucket_arn
  invoices_bucket_name = module.s3_invoices.bucket_name
  kms_key_arn          = module.kms.key_arn
  sender_email         = var.sender_email
  aws_region           = var.aws_region
  lambda_zip_path      = "../../lambda/invoice-generator/function.zip"
  tags                 = local.common_tags
}

# CloudFront + WAF for EU origin (ALB in eu-west-1)
module "cloudfront" {
  source                 = "../../modules/cloudfront"
  name                   = local.name
  alb_dns_name           = var.public_alb_dns_name
  domain_names           = var.domain_names
  acm_certificate_arn    = var.acm_certificate_arn
  origin_verify_secret   = var.origin_verify_secret
  logs_bucket_domain     = aws_s3_bucket.access_logs.bucket_domain_name
  enable_shield_advanced = var.enable_shield_advanced
  tags                   = local.common_tags

}

# Route 53 EU latency record — pairs with app_us in prod/main.tf
resource "aws_route53_record" "app_eu" {
  zone_id        = var.route53_zone_id
  name           = var.domain_names[0]
  type           = "A"
  set_identifier = "eu"

  latency_routing_policy { region = "eu-west-1" }

  alias {
    name                   = module.cloudfront.distribution_domain
    zone_id                = "Z2FDTNDATAQYW2" # CloudFront hosted zone
    evaluate_target_health = false
  }
}

# Client VPN — admin access in EU
module "vpn" {
  source                      = "../../modules/vpn"
  name                        = local.name
  vpc_id                      = module.vpc.vpc_id
  vpc_cidr                    = module.vpc.vpc_cidr_block
  private_subnet_ids          = module.vpc.private_subnet_ids
  kms_key_arn                 = module.kms.key_arn
  server_certificate_arn      = var.vpn_server_certificate_arn
  client_root_certificate_arn = var.vpn_client_root_certificate_arn
  saml_provider_arn           = var.vpn_saml_provider_arn
  tags                        = local.common_tags
}

resource "aws_security_group_rule" "nodes_from_vpn" {
  type              = "ingress"
  description       = "VPN admin clients via internal ALB"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [module.vpn.client_cidr_block]
  security_group_id = module.eks.node_sg_id
}

# IRSA roles per service
module "irsa_catalog" {
  source            = "../../modules/irsa"
  name              = "${local.name}-catalog"
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = "shopcloud"
  service_account   = "catalog"
  policy_arns       = []
  inline_policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow"; Action = ["secretsmanager:GetSecretValue"]; Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:shopcloud/prod-eu/catalog*" },
      { Effect = "Allow"; Action = ["ssm:GetParameter"]; Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/shopcloud/prod-eu/*" },
      { Effect = "Allow"; Action = ["kms:Decrypt"]; Resource = module.kms.key_arn }
    ]
  })
  tags = local.common_tags
}

module "irsa_checkout" {
  source            = "../../modules/irsa"
  name              = "${local.name}-checkout"
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = "shopcloud"
  service_account   = "checkout"
  policy_arns       = []
  inline_policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow"; Action = ["sqs:SendMessage"]; Resource = module.sqs.invoice_queue_arn },
      { Effect = "Allow"; Action = ["secretsmanager:GetSecretValue"]; Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:shopcloud/prod-eu/checkout*" },
      { Effect = "Allow"; Action = ["kms:GenerateDataKey", "kms:Decrypt"]; Resource = module.kms.key_arn }
    ]
  })
  tags = local.common_tags
}

module "irsa_cart" {
  source            = "../../modules/irsa"
  name              = "${local.name}-cart"
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = "shopcloud"
  service_account   = "cart"
  policy_arns       = []
  inline_policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow"; Action = ["secretsmanager:GetSecretValue"]; Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:shopcloud/prod-eu/cart*" },
      { Effect = "Allow"; Action = ["ssm:GetParameter"]; Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/shopcloud/prod-eu/*" },
      { Effect = "Allow"; Action = ["kms:Decrypt"]; Resource = module.kms.key_arn }
    ]
  })
  tags = local.common_tags
}

module "irsa_auth" {
  source            = "../../modules/irsa"
  name              = "${local.name}-auth"
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = "shopcloud"
  service_account   = "auth"
  policy_arns       = []
  inline_policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow"; Action = ["cognito-idp:AdminGetUser", "cognito-idp:AdminListGroupsForUser", "cognito-idp:ListUsers"]; Resource = module.cognito.customer_pool_arn },
      { Effect = "Allow"; Action = ["secretsmanager:GetSecretValue"]; Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:shopcloud/prod-eu/auth*" },
      { Effect = "Allow"; Action = ["kms:Decrypt"]; Resource = module.kms.key_arn }
    ]
  })
  tags = local.common_tags
}

module "irsa_admin" {
  source            = "../../modules/irsa"
  name              = "${local.name}-admin"
  oidc_issuer_url   = module.eks.cluster_oidc_issuer_url
  oidc_provider_arn = module.eks.oidc_provider_arn
  namespace         = "shopcloud"
  service_account   = "admin"
  policy_arns       = []
  inline_policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow"; Action = ["secretsmanager:GetSecretValue"]; Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:shopcloud/prod-eu/admin*" },
      { Effect = "Allow"; Action = ["s3:GetObject", "s3:ListBucket"]; Resource = [module.s3_invoices.bucket_arn, "${module.s3_invoices.bucket_arn}/*"] },
      { Effect = "Allow"; Action = ["kms:Decrypt"]; Resource = module.kms.key_arn }
    ]
  })
  tags = local.common_tags
}

# SNS alerts
resource "aws_sns_topic" "alerts" {
  name              = "${local.name}-alerts"
  kms_master_key_id = module.kms.key_id
  tags              = local.common_tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count     = length(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_emails[count.index]
}

# S3 access logs bucket
resource "aws_s3_bucket" "access_logs" {
  bucket        = "${local.name}-access-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = false
  tags          = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
