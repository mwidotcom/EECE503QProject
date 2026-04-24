variable "kms_key_arn"    { type = string }
variable "node_role_arn"  { type = string }
variable "tags"           { type = map(string); default = {} }
