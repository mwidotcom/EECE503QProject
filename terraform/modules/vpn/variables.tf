variable "name"                       { type = string }
variable "vpc_id"                      { type = string }
variable "vpc_cidr"                    { type = string }
variable "private_subnet_ids"          { type = list(string) }
variable "kms_key_arn"                 { type = string }
variable "server_certificate_arn"      { type = string }
variable "client_root_certificate_arn" { type = string }
variable "saml_provider_arn"           { type = string }
variable "client_cidr_block"           { type = string; default = "10.8.0.0/22" }
variable "tags"                        { type = map(string); default = {} }
