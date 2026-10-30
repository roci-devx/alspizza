import http from 'node:http';
import { createApp } from './app.js';
import { config, integrations } from './config.js';
import { prisma } from './db.js';
import { attachRealtime } from './realtime/hub.js';
import { startDeliveryWorkers } from './services/delivery.service.js';
import { startReportScheduler } from './services/report.service.js';

const server = http.createServer(createApp());
attachRealtime(server);

server.listen(config.port, () => {
  const on = Object.entries(integrations)
    .filter(([, v]) => v)
    .map(([k]) => k);
  console.log(`\n🍕  Al's Pizza API  →  http://localhost:${config.port}`);
  console.log(`    realtime         →  ws://localhost:${config.port}/ws`);
  console.log(`    integrations     →  ${on.length ? on.join(', ') : 'none (demo mode)'}`);
  if (config.demo.payments) console.log('    demo payments    →  ON (no card is charged)');
  if (config.demo.simulateDelivery && !integrations.doordash && !integrations.uber) console.log('    delivery         →  simulated courier');
  startDeliveryWorkers();
  startReportScheduler();
});

const shutdown = async () => {
  server.close();
  await prisma.$disconnect();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
