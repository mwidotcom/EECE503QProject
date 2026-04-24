output "function_arn"  { value = aws_lambda_function.invoice_generator.arn }
output "function_name" { value = aws_lambda_function.invoice_generator.function_name }
output "role_arn"      { value = aws_iam_role.lambda.arn }
