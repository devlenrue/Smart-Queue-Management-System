/* CLI: npm run db:reset — drops every table, re-migrates, re-seeds. */
import { closeDb, connectDb } from '../index';
import { dropAll, runMigrations } from '../migrate';
import { runSeed } from '../seed';
import { logger } from '../../utils/logger';

async function main(): Promise<void> {
  await connectDb();
  logger.info('Dropping all tables…');
  await dropAll();
  await runMigrations();
  await runSeed();
  await closeDb();
}

main().catch(async (error) => {
  logger.error('Reset failed', error instanceof Error ? error.message : error);
  await closeDb().catch(() => undefined);
  process.exit(1);
});
