import { config } from './config.js';

export class HermesAgent {
  constructor() {
    this.timer = null;
    this.ticks = 0;
    this.running = false;
  }

  async start() {
    if (this.running) return;
    this.running = true;

    console.log(
      `[hermes] ${config.name} starting ` +
        `(env=${config.env}, tick=${config.tickIntervalMs}ms, pid=${process.pid})`,
    );

    // Tick pertama langsung dijalankan, sisanya sesuai interval
    await this.tick();
    this.timer = setInterval(() => {
      void this.tick();
    }, config.tickIntervalMs);
  }

  async tick() {
    this.ticks += 1;

    // TODO: ganti isi method ini dengan logika agent-mu
    // (polling API, kirim notifikasi, proses antrian, dsb.)
    console.log(`[hermes] tick #${this.ticks} at ${new Date().toISOString()}`);
  }

  async stop(signal) {
    if (!this.running) return;

    console.log(`[hermes] sinyal ${signal} diterima, memberhentikan agent...`);
    this.running = false;

    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }

    // TODO: tutup koneksi database / API / worker di sini sebelum exit
    console.log('[hermes] berhenti dengan bersih. sampai jumpa!');
  }
}
