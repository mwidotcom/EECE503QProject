#!/bin/bash
# LocalStack initialization — creates local AWS resources for development

set -e

echo "Initializing LocalStack resources..."

# SQS FIFO queues
awslocal sqs create-queue \
  --queue-name shopcloud-dev-invoice-dlq.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=true

awslocal sqs create-queue \
  --queue-name shopcloud-dev-invoice.fifo \
  --attributes "FifoQueue=true,ContentBasedDeduplication=true,RedrivePolicy={\"deadLetterTargetArn\":\"arn:aws:sqs:us-east-1:000000000000:shopcloud-dev-invoice-dlq.fifo\",\"maxReceiveCount\":\"3\"}"

# S3 bucket for invoices
awslocal s3 mb s3://shopcloud-dev-invoices-local

# Secrets Manager entries
awslocal secretsmanager create-secret \
  --name shopcloud/dev/catalog/db \
  --secret-string '{"host":"postgres","username":"shopcloud_dev","password":"devpassword123"}'

awslocal secretsmanager create-secret \
  --name shopcloud/dev/redis/auth \
  --secret-string '{"password":"devredispassword"}'

# SES — verify sender email in sandbox
awslocal ses verify-email-identity \
  --email-address dev-noreply@shopcloud.local

echo "LocalStack initialization complete."
