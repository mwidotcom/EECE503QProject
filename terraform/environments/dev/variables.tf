variable "aws_region"        { type = string; default = "us-east-1" }
variable "db_username"       { type = string; default = "shopcloud_dev" }
variable "db_password"       { type = string; sensitive = true }
variable "redis_auth_token"  { type = string; sensitive = true }
variable "sender_email"      { type = string; default = "dev-noreply@shopcloud.example.com" }
variable "allowed_cidrs"     { type = list(string); description = "CIDRs allowed to reach the EKS API (office/VPN)" }
