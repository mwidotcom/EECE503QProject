resource "aws_db_subnet_group" "main" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids
  tags       = merge(var.tags, { Name = "${var.identifier}-subnet-group" })
}

resource "aws_security_group" "rds" {
  name        = "${var.identifier}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
  }

  tags = merge(var.tags, { Name = "${var.identifier}-rds-sg" })
}

resource "aws_db_parameter_group" "main" {
  name   = "${var.identifier}-pg15"
  family = "postgres15"

  parameter {
    name  = "log_connections"
    value = "1"
  }
  parameter {
    name  = "log_disconnections"
    value = "1"
  }
  parameter {
    name  = "log_duration"
    value = "1"
  }
  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # log slow queries > 1s
  }
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = var.tags
}

resource "aws_db_instance" "main" {
  identifier              = var.identifier
  engine                  = "postgres"
  engine_version          = "15.4"
  instance_class          = var.instance_class
  allocated_storage       = var.allocated_storage
  max_allocated_storage   = var.max_allocated_storage
  storage_type            = "gp3"
  storage_encrypted       = true
  kms_key_id              = var.kms_key_arn

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  multi_az               = var.multi_az
  publicly_accessible    = false
  deletion_protection    = var.deletion_protection

  backup_retention_period   = var.backup_retention_period
  backup_window             = "03:00-04:00"
  maintenance_window        = "Mon:04:00-Mon:05:00"
  copy_tags_to_snapshot     = true
  delete_automated_backups  = false

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = 7

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  auto_minor_version_upgrade = true
  apply_immediately          = false

  tags = merge(var.tags, { Name = var.identifier })
}

# Cross-region read replica for DR
resource "aws_db_instance" "replica" {
  count = var.create_replica ? 1 : 0

  provider                = aws.dr
  identifier              = "${var.identifier}-replica"
  replicate_source_db     = aws_db_instance.main.arn
  instance_class          = var.replica_instance_class
  publicly_accessible     = false
  auto_minor_version_upgrade = true
  storage_encrypted       = true
  kms_key_id              = var.replica_kms_key_arn

  performance_insights_enabled = true

  tags = merge(var.tags, { Name = "${var.identifier}-replica" })
}
