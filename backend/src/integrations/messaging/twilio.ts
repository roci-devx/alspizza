import crypto from 'node:crypto';
import { config, integrations } from '../../config.js';

/**
 * Driver chat relay. When Twilio is configured our Twilio number is given to the
 * courier network as the drop-off phone, so courier texts land here and are shown
 * in the app; customer messages from the app are texted to the courier's masked
 * number. Courier calls to the Twilio number are forwarded to the customer.
 */

export async function sendSms(to: string, body: string): Promise<void> {
  if (!integrations.twilio) throw new Error('Twilio is not configured');
  const { accountSid, authToken, fromNumber } = config.twilio;
  const res = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${Buffer.from(`${accountSid}:${authToken}`).toString('base64')}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({ To: to, From: fromNumber, Body: body.slice(0, 1500) }).toString(),
  });
  if (!res.ok) throw new Error(`Twilio SMS failed (${res.status}): ${await res.text()}`);
}

/** https://www.twilio.com/docs/usage/security#validating-requests */
export function isValidTwilioRequest(url: string, params: Record<string, string>, signature: string | undefined): boolean {
  if (!config.twilio.authToken) return !config.isProd;
  if (!signature) return false;
  const data = url + Object.keys(params).sort().map((k) => k + params[k]).join('');
  const expected = crypto.createHmac('sha1', config.twilio.authToken).update(data).digest('base64');
  const a = Buffer.from(expected);
  const b = Buffer.from(signature);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

export const twiml = (inner = '') => `<?xml version="1.0" encoding="UTF-8"?><Response>${inner}</Response>`;

export const escapeXml = (s: string) => s.replace(/[<>&'"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;' })[c]!);
