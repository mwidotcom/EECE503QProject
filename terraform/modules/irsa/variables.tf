variable "name"              { type = string }
variable "oidc_issuer_url"   { type = string }
variable "oidc_provider_arn" { type = string }
variable "namespace"         { type = string }
variable "service_account"   { type = string }
variable "policy_arns"       { type = list(string); default = [] }
variable "inline_policy"     { type = string; default = "" }
variable "tags"              { type = map(string); default = {} }
