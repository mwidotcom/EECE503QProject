variable "aws_region"                      { type = string; default = "eu-west-1" }
variable "vpc_cidr"                         { type = string; default = "10.1.0.0/16" }
variable "db_username"                      { type = string }
variable "db_password"                      { type = string; sensitive = true }
variable "redis_auth_token"                 { type = string; sensitive = true }
variable "sender_email"                     { type = string }
variable "domain_names"                     { type = list(string) }
variable "acm_certificate_arn"              { type = string }
variable "origin_verify_secret"             { type = string; sensitive = true }
variable "public_alb_dns_name"              { type = string }
variable "route53_zone_id"                  { type = string }
variable "enable_shield_advanced"           { type = bool; default = true }
variable "alert_emails"                     { type = list(string); default = [] }
variable "vpn_server_certificate_arn"       { type = string }
variable "vpn_client_root_certificate_arn"  { type = string }
variable "vpn_saml_provider_arn"            { type = string }
