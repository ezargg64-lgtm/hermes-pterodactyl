// Konfigurasi agent dibaca dari environment variable Pterodactyl (tab Startup)
// atau dari file .env (opsional, di-load otomatis oleh npm start).

const toPositiveInt = (value, fallback) => {
  const parsed = Number.parseInt(value ?? '', 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};

export const config = {
  // Nama agent, dipakai di semua baris log
  name: process.env.HERMES_NAME || 'hermes-agent',
  // Jarak antar tick / loop pekerjaan dalam milidetik
  tickIntervalMs: toPositiveInt(process.env.HERMES_TICK_INTERVAL_MS, 60_000),
  env: process.env.NODE_ENV || 'production',
};
