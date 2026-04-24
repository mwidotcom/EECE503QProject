variable "bucket_name"     { type = string }
variable "kms_key_arn"    { type = string }
variable "lambda_role_arn" { type = string }
variable "force_destroy"  { type = bool; default = false }
variable "tags"           { type = map(string); default = {} }
