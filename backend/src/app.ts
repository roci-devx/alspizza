import cors from 'cors';
import express from 'express';
import type { IncomingMessage } from 'node:http';
import { config } from './config.js';
import { errorHandler, notFound } from './lib/http.js';
import { MEDIA_DIR, ownerMenuRoutes } from './routes/owner-menu.routes.js';
import { orderRoutes } from './routes/orders.routes.js';
import { ownerRoutes } from './routes/owner.routes.js';
import { publicRoutes } from './routes/public.routes.js';
import { webhookRoutes } from './routes/webhooks.routes.js';

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', true);
  app.use(
    cors({
      origin: config.corsOrigins.length ? config.corsOrigins : true,
      allowedHeaders: ['Content-Type', 'Authorization'],
      maxAge: 86400,
    }),
  );
  // Keep the raw bytes around for webhook signature checks (Stripe, Square, Uber).
  const jsonBody = express.json({
    limit: '1mb',
    verify: (req: IncomingMessage & { rawBody?: Buffer }, _res, buf) => {
      req.rawBody = buf;
    },
  });
  // Photo uploads parse their own (larger) body after the owner is authenticated.
  app.use((req, res, next) => (req.path === '/api/owner/media' ? next() : jsonBody(req, res, next)));

  // Stock photos (public/stock) and owner uploads (public/uploads).
  app.use('/media', express.static(MEDIA_DIR, { maxAge: '7d', index: false }));

  app.get('/', (_req, res) => {
    res.json({ name: "Al's Pizza API", status: 'ok', docs: 'See README.md → API overview' });
  });

  app.use('/api', publicRoutes);
  app.use('/api/orders', orderRoutes);
  app.use('/api', webhookRoutes);
  app.use('/api', ownerMenuRoutes);
  app.use('/api', ownerRoutes);

  app.use((_req, _res, next) => next(notFound('No such endpoint')));
  app.use(errorHandler);
  return app;
}
