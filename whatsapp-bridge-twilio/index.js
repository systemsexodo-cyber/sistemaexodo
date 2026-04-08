require('dotenv').config();
const express = require('express');
const twilio = require('twilio');
const cors = require('cors');

const app = express();
const port = process.env.PORT || 3000;

// Security token to prevent unauthorized access to your bridge
const API_SECRET = process.env.BRIDGE_API_SECRET || 'changeme_123';

app.use(cors());
app.use(express.json());

// Initialize Twilio
const client = twilio(
  process.env.TWILIO_ACCOUNT_SID,
  process.env.TWILIO_AUTH_TOKEN
);

// Health check
app.get('/', (req, res) => {
  res.json({ status: 'ok', message: 'Twilio WhatsApp Bridge is running' });
});

// Middleware to check API key
const authorize = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  if (!apiKey || apiKey !== API_SECRET) {
    return res.status(401).json({ error: 'Unauthorized: Invalid API key' });
  }
  next();
};

/**
 * Send WhatsApp Message
 * Body: { "to": "5511999999999", "message": "My message here" }
 */
app.post('/send-message', authorize, async (req, res) => {
  const { to, message } = req.body;

  if (!to || !message) {
    return res.status(400).json({ error: 'Missing "to" or "message" in body' });
  }

  // Format number: Twilio requires "whatsapp:+CountryCodeNumber"
  let formattedNumber = to.replace(/\D/g, ''); // Remove non-digits
  if (!formattedNumber.startsWith('55')) {
     // Default Br
     formattedNumber = '55' + formattedNumber;
  }
  
  const recipient = `whatsapp:+${formattedNumber}`;
  const sender = `whatsapp:${process.env.TWILIO_PHONE_NUMBER}`;

  console.log(`>>> Sending message from ${sender} to ${recipient}`);

  try {
    const result = await client.messages.create({
      from: sender,
      to: recipient,
      body: message
    });

    console.log(`>>> Message sent! SID: ${result.sid}`);
    res.json({
      success: true,
      sid: result.sid,
      status: result.status
    });
  } catch (error) {
    console.error('>>> Error sending message:', error);
    res.status(500).json({
      success: false,
      error: error.message,
      code: error.code
    });
  }
});

app.listen(port, () => {
  console.log(`>>> Bridge listening at http://localhost:${port}`);
  console.log('>>> IMPORTANT: Configure your ENV variables on Render!');
});
