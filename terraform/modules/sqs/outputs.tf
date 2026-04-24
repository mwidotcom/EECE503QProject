output "invoice_queue_url"  { value = aws_sqs_queue.invoice.id }
output "invoice_queue_arn"  { value = aws_sqs_queue.invoice.arn }
output "invoice_dlq_arn"    { value = aws_sqs_queue.invoice_dlq.arn }
