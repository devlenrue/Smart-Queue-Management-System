import { createApp, API_PREFIX } from './app';
import { config } from './config/env';
import { closeDb, connectDb } from './db';
import { logger } from './utils/logger';

async function main(): Promise<void> {
  try {
    await connectDb();
  } catch (error) {
    logger.error('Could not connect to the database. Check DATABASE_URL in your .env file.', error);
    process.exit(1);
  }

  const app = createApp();
  // 0.0.0.0 so the API is reachable from an emulator or a phone on the LAN.
  const server = app.listen(config.port, '0.0.0.0', () => {
    logger.info(`SmartQueue API listening on http://0.0.0.0:${config.port}${API_PREFIX}`);
    logger.info(`Environment: ${config.env} · timezone: ${config.timezone} · database: ${config.database.dialect}`);
  });

  const shutdown = (signal: string): void => {
    logger.info(`${signal} received, shutting down.`);
    server.close(() => {
      void closeDb().finally(() => process.exit(0));
    });
    setTimeout(() => process.exit(1), 10_000).unref();
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('unhandledRejection', (reason) => logger.error('Unhandled promise rejection', reason));
}

void main();
