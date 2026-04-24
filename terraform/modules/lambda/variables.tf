variable "name"                  { type = string }
variable "vpc_id"                { type = string }
variable "subnet_ids"            { type = list(string) }
variable "sqs_queue_arn"         { type = string }
variable "invoices_bucket_arn"   { type = string }
variable "invoices_bucket_name"  { type = string }
variable "kms_key_arn"           { type = string }
variable "sender_email"          { type = string }
variable "aws_region"            { type = string }
variable "lambda_zip_path"       { type = string }
variable "log_level"             { type = string; default = "info" }
variable "tags"                  { type = map(string); default = {} }
