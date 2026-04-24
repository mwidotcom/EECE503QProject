variable "cluster_name"          { type = string }
variable "kubernetes_version"    { type = string; default = "1.29" }
variable "vpc_id"                { type = string }
variable "private_subnet_ids"    { type = list(string) }
variable "public_subnet_ids"     { type = list(string) }
variable "kms_key_arn"           { type = string }
variable "node_instance_types"   { type = list(string); default = ["m6i.xlarge"] }
variable "capacity_type"         { type = string; default = "ON_DEMAND" }
variable "node_desired"          { type = number; default = 3 }
variable "node_min"              { type = number; default = 2 }
variable "node_max"              { type = number; default = 10 }
variable "endpoint_public_access" { type = bool; default = false }
variable "public_access_cidrs"   { type = list(string); default = [] }
variable "tags"                  { type = map(string); default = {} }
