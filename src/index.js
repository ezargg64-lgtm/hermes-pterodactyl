import { HermesAgent } from './agent.js';

const agent = new HermesAgent();

const shutdown = async (signal) => {
  await agent.stop(signal);
  process.exit(0);
};

// Pterodactyl mengirim SIGTERM saat server di-stop/restart.
// Tanpa handler ini proses bisa terbunuh paksa sebelum sempat beres-beres.
process.on('SIGTERM', () => void shutdown('SIGTERM'));
process.on('SIGINT', () => void shutdown('SIGINT')); // Ctrl+C di console panel
process.on('SIGHUP', () => void shutdown('SIGHUP'));

process.on('uncaughtException', (error) => {
  console.error('[hermes] uncaughtException:', error);
  void shutdown('uncaughtException').then(() => process.exit(1));
});

process.on('unhandledRejection', (reason) => {
  console.error('[hermes] unhandledRejection:', reason);
});

agent.start().catch((error) => {
  console.error('[hermes] gagal start:', error);
  process.exit(1);
});
