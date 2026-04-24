output "distribution_id"        { value = aws_cloudfront_distribution.main.id }
output "distribution_domain"    { value = aws_cloudfront_distribution.main.domain_name }
output "distribution_arn"       { value = aws_cloudfront_distribution.main.arn }
output "waf_acl_arn"            { value = aws_wafv2_web_acl.main.arn }
