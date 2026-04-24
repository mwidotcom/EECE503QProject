const { SQSClient, SendMessageCommand } = require('@aws-sdk/client-sqs');
const { logger } = require('../middleware/logger');

const sqsClient = new SQSClient({ region: process.env.AWS_REGION });

async function publishInvoiceEvent(order) {
  const message = {
    orderId: order.id,
    customerId: order.customer_id,
    customerEmail: order.customer_email,
    items: order.items,
    total: order.total,
    currency: order.currency || 'USD',
    createdAt: order.created_at,
  };

  const command = new SendMessageCommand({
    QueueUrl: process.env.SQS_INVOICE_QUEUE_URL,
    MessageBody: JSON.stringify(message),
    MessageGroupId: order.customer_id,
    MessageDeduplicationId: order.id,
    MessageAttributes: {
      eventType: { DataType: 'String', StringValue: 'ORDER_COMPLETED' },
      orderId: { DataType: 'String', StringValue: order.id },
    },
  });

  const result = await sqsClient.send(command);
  logger.info({ msg: 'Invoice event published', orderId: order.id, messageId: result.MessageId });
  return result;
}

module.exports = { publishInvoiceEvent };
