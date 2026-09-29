/* CLI: npm run db:seed */
import { closeDb, connectDb } from '../index';
import { runMigrations } from '../migrate';
import { runSeed } from '../seed';
import { logger } from '../../utils/logger';

async function main(): Promise<void> {
  await connectDb();
  await runMigrations();
  await runSeed();
  await closeDb();
}

main().catch(async (error) => {
  logger.error('Seeding failed', error instanceof Error ? error.message : error);
  await closeDb().catch(() => undefined);
  process.exit(1);
});
