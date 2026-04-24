variable "name"                      { type = string }
variable "kms_key_id"                { type = string }
variable "checkout_service_role_arn" { type = string }
variable "lambda_role_arn"           { type = string }
variable "alarm_sns_arns"            { type = list(string); default = [] }
variable "tags"                      { type = map(string); default = {} }
