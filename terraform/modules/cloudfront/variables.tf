variable "name"                   { type = string }
variable "alb_dns_name"           { type = string }
variable "domain_names"           { type = list(string) }
variable "acm_certificate_arn"    { type = string }
variable "origin_verify_secret"   { type = string; sensitive = true }
variable "logs_bucket_domain"     { type = string }
variable "enable_shield_advanced" { type = bool; default = false }
variable "tags"                   { type = map(string); default = {} }
