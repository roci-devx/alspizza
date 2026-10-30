import type { Order } from '@prisma/client';
import { config } from '../../config.js';

/** PayPal Orders v2: create → shopper approves on paypal.com → capture on return. */

let cached: { token: string; expires: number } | null = null;

async function accessToken(): Promise<string> {
  if (cached && cached.expires > Date.now() + 60_000) return cached.token;
  const res = await fetch(`${config.paypal.baseUrl}/v1/oauth2/token`, {
    method: 'POST',
    headers: {
      Authorization: `Basic ${Buffer.from(`${config.paypal.clientId}:${config.paypal.clientSecret}`).toString('base64')}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: 'grant_type=client_credentials',
  });
  const data = (await res.json()) as { access_token?: string; expires_in?: number; error_description?: string };
  if (!res.ok || !data.access_token) throw new Error(`PayPal auth failed: ${data.error_description ?? res.status}`);
  cached = { token: data.access_token, expires: Date.now() + (data.expires_in ?? 3000) * 1000 };
  return cached.token;
}

async function call<T>(path: string, body: unknown, requestId?: string): Promise<T> {
  const res = await fetch(`${config.paypal.baseUrl}${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${await accessToken()}`,
      'Content-Type': 'application/json',
      ...(requestId ? { 'PayPal-Request-Id': requestId } : {}),
    },
    body: JSON.stringify(body ?? {}),
  });
  const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) throw new Error(`PayPal ${path} → ${res.status}: ${(data.message as string) ?? JSON.stringify(data)}`);
  return data as T;
}

export async function createPaypalOrder(order: Order): Promise<{ id: string; approvalUrl: string }> {
  const returnUrl = `${config.publicApiUrl}/api/payments/paypal/return?orderId=${order.id}`;
  const cancelUrl = `${config.publicApiUrl}/api/payments/paypal/cancel?orderId=${order.id}`;
  const created = await call<{ id: string; links: { rel: string; href: string }[] }>(
    '/v2/checkout/orders',
    {
      intent: 'CAPTURE',
      purchase_units: [
        {
          reference_id: order.id,
          custom_id: order.id,
          description: `Al's Pizza order #${order.number}`,
          amount: { currency_code: 'USD', value: (order.totalCents / 100).toFixed(2) },
        },
      ],
      payment_source: {
        paypal: {
          experience_context: {
            brand_name: "Al's Pizza",
            user_action: 'PAY_NOW',
            shipping_preference: 'NO_SHIPPING',
            return_url: returnUrl,
            cancel_url: cancelUrl,
          },
        },
      },
    },
    `create-${order.id}-${order.totalCents}`,
  );
  const link = created.links.find((l) => l.rel === 'payer-action' || l.rel === 'approve');
  if (!link) throw new Error('PayPal did not return an approval link');
  return { id: created.id, approvalUrl: link.href };
}

export async function capturePaypalOrder(paypalOrderId: string) {
  const res = await call<{
    status: string;
    purchase_units?: { payments?: { captures?: { id: string; status: string }[] } }[];
  }>(`/v2/checkout/orders/${encodeURIComponent(paypalOrderId)}/capture`, {}, `capture-${paypalOrderId}`);
  const capture = res.purchase_units?.[0]?.payments?.captures?.[0];
  return { completed: res.status === 'COMPLETED', captureId: capture?.id ?? paypalOrderId };
}

export async function refundPaypalCapture(captureId: string) {
  return call(`/v2/payments/captures/${encodeURIComponent(captureId)}/refund`, {});
}
