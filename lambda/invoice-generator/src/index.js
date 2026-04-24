const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { SESClient, SendEmailCommand } = require('@aws-sdk/client-ses');
const PDFDocument = require('pdfkit');

const s3 = new S3Client({ region: process.env.AWS_REGION });
const ses = new SESClient({ region: process.env.AWS_REGION });

const BUCKET = process.env.INVOICES_BUCKET;
const SENDER_EMAIL = process.env.SENDER_EMAIL;

async function generatePDF(order) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 50 });
    const chunks = [];

    doc.on('data', (chunk) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    // Header
    doc.fontSize(24).font('Helvetica-Bold').text('ShopCloud', { align: 'center' });
    doc.fontSize(14).font('Helvetica').text('Invoice', { align: 'center' });
    doc.moveDown();
    doc.fontSize(10);

    // Order details
    doc.text(`Invoice #: ${order.orderId}`);
    doc.text(`Date: ${new Date(order.createdAt).toLocaleDateString()}`);
    doc.text(`Customer: ${order.customerEmail}`);
    doc.moveDown();

    // Items table header
    doc.font('Helvetica-Bold');
    doc.text('Item', 50, doc.y, { width: 200, continued: false });
    doc.moveUp();
    doc.text('Qty', 260, doc.y, { width: 60 });
    doc.moveUp();
    doc.text('Unit Price', 330, doc.y, { width: 100 });
    doc.moveUp();
    doc.text('Total', 440, doc.y, { width: 80, align: 'right' });
    doc.moveTo(50, doc.y + 5).lineTo(530, doc.y + 5).stroke();
    doc.moveDown(0.5);

    // Items
    doc.font('Helvetica');
    for (const item of order.items) {
      const lineTotal = (item.price * item.quantity).toFixed(2);
      doc.text(item.name.substring(0, 35), 50, doc.y, { width: 200, continued: false });
      doc.moveUp();
      doc.text(String(item.quantity), 260, doc.y, { width: 60 });
      doc.moveUp();
      doc.text(`$${item.price.toFixed(2)}`, 330, doc.y, { width: 100 });
      doc.moveUp();
      doc.text(`$${lineTotal}`, 440, doc.y, { width: 80, align: 'right' });
    }

    // Total
    doc.moveTo(50, doc.y + 10).lineTo(530, doc.y + 10).stroke();
    doc.moveDown();
    doc.font('Helvetica-Bold').text(`Total: $${order.total.toFixed(2)} ${order.currency}`, { align: 'right' });

    doc.end();
  });
}

async function uploadToS3(pdfBuffer, orderId) {
  const key = `invoices/${new Date().getFullYear()}/${orderId}.pdf`;
  await s3.send(new PutObjectCommand({
    Bucket: BUCKET,
    Key: key,
    Body: pdfBuffer,
    ContentType: 'application/pdf',
    ServerSideEncryption: 'aws:kms',
    Metadata: { orderId },
  }));
  return key;
}

async function sendEmail(order, s3Key) {
  const downloadLink = `https://${BUCKET}.s3.amazonaws.com/${s3Key}`;
  await ses.send(new SendEmailCommand({
    Source: SENDER_EMAIL,
    Destination: { ToAddresses: [order.customerEmail] },
    Message: {
      Subject: { Data: `Your ShopCloud Invoice - Order #${order.orderId.slice(0, 8).toUpperCase()}` },
      Body: {
        Html: {
          Data: `
            <h2>Thank you for your order!</h2>
            <p>Hi,</p>
            <p>Your order <strong>#${order.orderId.slice(0, 8).toUpperCase()}</strong> has been confirmed.</p>
            <p><strong>Total: $${order.total.toFixed(2)} ${order.currency}</strong></p>
            <p>Your invoice is ready: <a href="${downloadLink}">Download Invoice PDF</a></p>
            <p>Thank you for shopping with ShopCloud!</p>
          `,
        },
        Text: {
          Data: `Your order #${order.orderId.slice(0, 8).toUpperCase()} is confirmed. Total: $${order.total.toFixed(2)} ${order.currency}. Invoice: ${downloadLink}`,
        },
      },
    },
  }));
}

exports.handler = async (event) => {
  const results = [];

  for (const record of event.Records) {
    const order = JSON.parse(record.body);
    console.log(JSON.stringify({ msg: 'Processing invoice', orderId: order.orderId }));

    try {
      const pdfBuffer = await generatePDF(order);
      const s3Key = await uploadToS3(pdfBuffer, order.orderId);
      await sendEmail(order, s3Key);
      console.log(JSON.stringify({ msg: 'Invoice sent', orderId: order.orderId, s3Key }));
      results.push({ orderId: order.orderId, status: 'success' });
    } catch (err) {
      console.error(JSON.stringify({ msg: 'Failed to process invoice', orderId: order.orderId, error: err.message }));
      // Re-throw to allow SQS retry / DLQ routing
      throw err;
    }
  }

  return { processed: results.length, results };
};
