/* CLI: npm run db:migrate */
import { closeDb, connectDb } from '../index';
import { runMigrations } from '../migrate';
import { logger } from '../../utils/logger';

async function main(): Promise<void> {
  await connectDb();
  await runMigrations();
  await closeDb();
}

main().catch(async (error) => {
  logger.error('Migration failed', error instanceof Error ? error.message : error);
  await closeDb().catch(() => undefined);
  process.exit(1);
});
