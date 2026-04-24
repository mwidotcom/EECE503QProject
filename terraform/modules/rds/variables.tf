variable "identifier"                { type = string }
variable "vpc_id"                    { type = string }
variable "subnet_ids"                { type = list(string) }
variable "allowed_security_group_ids" { type = list(string) }
variable "kms_key_arn"               { type = string }
variable "instance_class"            { type = string; default = "db.t4g.medium" }
variable "allocated_storage"         { type = number; default = 100 }
variable "max_allocated_storage"     { type = number; default = 1000 }
variable "db_name"                   { type = string; default = "shopcloud" }
variable "db_username"               { type = string }
variable "db_password"               { type = string; sensitive = true }
variable "multi_az"                  { type = bool; default = true }
variable "deletion_protection"       { type = bool; default = true }
variable "backup_retention_period"   { type = number; default = 7 }
variable "create_replica"            { type = bool; default = false }
variable "replica_instance_class"    { type = string; default = "db.t4g.medium" }
variable "replica_kms_key_arn"       { type = string; default = "" }
variable "tags"                      { type = map(string); default = {} }
