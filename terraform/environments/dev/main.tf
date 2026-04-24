terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
    tls = { source = "hashicorp/tls"; version = "~> 4.0" }
  }

  backend "s3" {
    bucket         = "shopcloud-terraform-state-dev"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "shopcloud-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = local.common_tags }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags { tags = local.common_tags }
}

locals {
  common_tags = {
    Project     = "ShopCloud"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
  name         = "shopcloud-dev"
  cluster_name = "shopcloud-dev"
}

module "kms" {
  source = "../../modules/kms"
  name   = local.name
  tags   = local.common_tags
}

module "vpc" {
  source       = "../../modules/vpc"
  name         = local.name
  vpc_cidr     = "10.1.0.0/16"
  cluster_name = local.cluster_name
  aws_region   = var.aws_region
  tags         = local.common_tags
}

module "eks" {
  source              = "../../modules/eks"
  cluster_name        = local.cluster_name
  kubernetes_version  = "1.29"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  kms_key_arn         = module.kms.key_arn
  node_instance_types = ["t3.large"]
  node_desired        = 2
  node_min            = 1
  node_max            = 4
  # Dev: allow public API access from office/VPN CIDRs only
  endpoint_public_access = true
  public_access_cidrs    = var.allowed_cidrs
  tags                   = local.common_tags
}

module "rds" {
  source                     = "../../modules/rds"
  identifier                 = "${local.name}-postgres"
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.node_sg_id]
  kms_key_arn                = module.kms.key_arn
  instance_class             = "db.t4g.medium"
  allocated_storage          = 50
  max_allocated_storage      = 200
  db_username                = var.db_username
  db_password                = var.db_password
  multi_az                   = false   # save cost in dev
  deletion_protection        = false
  backup_retention_period    = 3
  create_replica             = false
  tags                       = local.common_tags
}

module "elasticache" {
  source                     = "../../modules/elasticache"
  name                       = local.name
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.data_subnet_ids
  allowed_security_group_ids = [module.eks.node_sg_id]
  kms_key_arn                = module.kms.key_arn
  auth_token                 = var.redis_auth_token
  node_type                  = "cache.t4g.small"
  num_cache_clusters         = 1   # single node in dev
  tags                       = local.common_tags
}

module "cognito" {
  source = "../../modules/cognito"
  name   = local.name
  tags   = local.common_tags
}

module "ecr" {
  source        = "../../modules/ecr"
  kms_key_arn   = module.kms.key_arn
  node_role_arn = module.eks.node_role_arn
  tags          = local.common_tags
}

module "s3_invoices" {
  source          = "../../modules/s3"
  bucket_name     = "${local.name}-invoices-${data.aws_caller_identity.current.account_id}"
  kms_key_arn     = module.kms.key_arn
  lambda_role_arn = module.lambda.role_arn
  force_destroy   = true
  tags            = local.common_tags
}

module "sqs" {
  source                    = "../../modules/sqs"
  name                      = local.name
  kms_key_id                = module.kms.key_id
  checkout_service_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
  lambda_role_arn           = module.lambda.role_arn
  tags                      = local.common_tags
}

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

data "aws_caller_identity" "current" {}
