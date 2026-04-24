variable "name"                        { type = string }
variable "alerts_sns_arn"              { type = string }
variable "alb_arn_suffix"              { type = string }
variable "rds_identifier"              { type = string }
variable "redis_replication_group_id"  { type = string }
variable "lambda_function_name"        { type = string }
variable "cloudfront_distribution_id"  { type = string }
variable "tags"                        { type = map(string); default = {} }
