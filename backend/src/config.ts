import fs from 'node:fs';
import path from 'node:path';

const envFile = path.resolve(process.cwd(), '.env');
if (fs.existsSync(envFile)) process.loadEnvFile(envFile);

const str = (key: string, fallback = '') => (process.env[key] ?? fallback).trim();
const num = (key: string, fallback: number) => {
  const raw = process.env[key];
  if (raw == null || raw.trim() === '') return fallback;
  const n = Number(raw);
  return Number.isFinite(n) ? n : fallback;
};
const bool = (key: string, fallback: boolean) => {
  const raw = process.env[key];
  if (raw == null || raw.trim() === '') return fallback;
  return ['1', 'true', 'yes', 'on'].includes(raw.trim().toLowerCase());
};

const isProd = str('NODE_ENV', 'development') === 'production';
const stripeSecret = str('STRIPE_SECRET_KEY');

export const config = {
  isProd,
  port: num('PORT', 4000),
  jwtSecret: str('JWT_SECRET', 'dev-only-secret-change-me'),
  publicApiUrl: str('API_PUBLIC_URL', 'http://localhost:4000').replace(/\/$/, ''),
  webAppUrl: str('WEB_APP_URL', 'http://localhost:5000').replace(/\/$/, ''),
  corsOrigins: str('CORS_ORIGINS').split(',').map((s) => s.trim()).filter(Boolean),
  enforceStoreHours: bool('ENFORCE_STORE_HOURS', isProd),
  merchantName: "Al's Pizza",
  reportsDir: path.resolve(process.cwd(), str('REPORTS_DIR', 'reports')),

  demo: {
    payments: bool('ALLOW_DEMO_PAYMENTS', !stripeSecret && !isProd),
    autoKitchen: bool('DEMO_AUTO_KITCHEN', !isProd),
    simulateDelivery: bool('DELIVERY_SIMULATION', !isProd),
    simSpeed: Math.max(0.1, num('DELIVERY_SIM_SPEED', 1)),
    // One-tap demo logins on the sign-in screens (never enable on a real store).
    accounts: bool('DEMO_ACCOUNTS', !isProd),
  },

  stripe: {
    secretKey: stripeSecret,
    publishableKey: str('STRIPE_PUBLISHABLE_KEY'),
    webhookSecret: str('STRIPE_WEBHOOK_SECRET'),
    appleMerchantId: str('STRIPE_APPLE_MERCHANT_ID', 'merchant.com.alspizza.app'),
  },
  paypal: {
    clientId: str('PAYPAL_CLIENT_ID'),
    clientSecret: str('PAYPAL_CLIENT_SECRET'),
    baseUrl: str('PAYPAL_ENV', 'sandbox') === 'live' ? 'https://api-m.paypal.com' : 'https://api-m.sandbox.paypal.com',
  },
  doordash: {
    developerId: str('DOORDASH_DEVELOPER_ID'),
    keyId: str('DOORDASH_KEY_ID'),
    signingSecret: str('DOORDASH_SIGNING_SECRET'),
    webhookAuth: str('DOORDASH_WEBHOOK_AUTH'),
    pollSeconds: Math.max(5, num('DOORDASH_POLL_SECONDS', 20)),
  },
  uber: {
    clientId: str('UBER_CLIENT_ID'),
    clientSecret: str('UBER_CLIENT_SECRET'),
    customerId: str('UBER_CUSTOMER_ID'),
    webhookSigningKey: str('UBER_WEBHOOK_SIGNING_KEY'),
  },
  twilio: {
    accountSid: str('TWILIO_ACCOUNT_SID'),
    authToken: str('TWILIO_AUTH_TOKEN'),
    fromNumber: str('TWILIO_FROM_NUMBER'),
  },
  square: {
    accessToken: str('SQUARE_ACCESS_TOKEN'),
    baseUrl: str('SQUARE_ENV', 'sandbox') === 'production' ? 'https://connect.squareup.com' : 'https://connect.squareupsandbox.com',
    version: str('SQUARE_VERSION', '2025-01-23'),
    webhookSignatureKey: str('SQUARE_WEBHOOK_SIGNATURE_KEY'),
  },
  clover: {
    accessToken: str('CLOVER_ACCESS_TOKEN'),
    merchantId: str('CLOVER_MERCHANT_ID'),
    baseUrl: str('CLOVER_ENV', 'sandbox') === 'production' ? 'https://api.clover.com' : 'https://apisandbox.dev.clover.com',
  },
  toast: {
    clientId: str('TOAST_CLIENT_ID'),
    clientSecret: str('TOAST_CLIENT_SECRET'),
    restaurantGuid: str('TOAST_RESTAURANT_GUID'),
    host: str('TOAST_HOST', 'https://ws-sandbox-api.eng.toasttab.com').replace(/\/$/, ''),
    takeoutDiningOptionGuid: str('TOAST_DINING_OPTION_TAKEOUT_GUID'),
    deliveryDiningOptionGuid: str('TOAST_DINING_OPTION_DELIVERY_GUID'),
  },
  google: { mapsKey: str('GOOGLE_MAPS_API_KEY') },
  nominatimEmail: str('NOMINATIM_CONTACT_EMAIL'),
  smtp: { url: str('SMTP_URL'), from: str('REPORT_EMAIL_FROM', "Al's Pizza Reports <reports@alspizza.com>") },
};

export const DEMO_ACCOUNTS = {
  customer: { email: 'demo@alspizza.com', password: 'pizza1234', name: 'Jordan Rivera' },
  owner: { email: 'demo.owner@alspizza.com', password: 'demo1234', name: 'Demo Owner' },
};

export const integrations = {
  stripe: Boolean(config.stripe.secretKey && config.stripe.publishableKey),
  paypal: Boolean(config.paypal.clientId && config.paypal.clientSecret),
  doordash: Boolean(config.doordash.developerId && config.doordash.keyId && config.doordash.signingSecret),
  uber: Boolean(config.uber.clientId && config.uber.clientSecret && config.uber.customerId),
  twilio: Boolean(config.twilio.accountSid && config.twilio.authToken && config.twilio.fromNumber),
  square: Boolean(config.square.accessToken),
  clover: Boolean(config.clover.accessToken && config.clover.merchantId),
  toast: Boolean(config.toast.clientId && config.toast.clientSecret && config.toast.restaurantGuid),
  googleMaps: Boolean(config.google.mapsKey),
  smtp: Boolean(config.smtp.url),
};

if (config.isProd && config.jwtSecret.startsWith('dev-only')) {
  throw new Error('JWT_SECRET must be set in production');
}
