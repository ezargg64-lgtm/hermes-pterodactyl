# hermes-pterodactyl

Skeleton **Hermes agent** berjalan di atas **Node.js 24**, siap dipasang di server
[Pterodactyl](https://pterodactyl.io/) sebagai customer (memakai egg generic Node.js 24
yang sudah disediakan host, tidak perlu akses admin/import egg).

## Struktur project

```
.
├── package.json        # scripts.start -> node (otomatis pakai --env-file=.env bila ada)
├── start.sh            # wrapper opsional: git pull -> npm install -> npm start
├── .env.example        # contoh environment variable
├── src/
│   ├── index.js        # entry point + graceful shutdown (SIGTERM/SIGINT)
│   ├── agent.js        # class HermesAgent, loop tick — logika agent ditaruh di sini
│   └── config.js       # pembacaan env (HERMES_NAME, HERMES_TICK_INTERVAL_MS)
└── README.md
```

Proses berjalan di **foreground** (wajib di Pterodactyl) dan menangani sinyal
`SIGTERM` supaya berhenti bersih saat tombol Stop/Restart ditekan.

## 1. Deploy kode ke server

### Opsi A — git clone (paling gampang untuk update)

Buka **Console** server di panel, pastikan working directory kosong
(biasanya `/home/container`), lalu:

```bash
git clone https://github.com/ezargg64-lgtm/hermes-pterodactyl.git .
```

### Opsi B — upload zip

1. Download ZIP project dari GitHub (branch yang dipakai).
2. Di panel: **File Manager → Upload**, lalu extract isinya langsung di `/home/container`
   (pastikan `package.json` berada di root container, bukan di dalam subfolder).

## 2. Startup Command (yang ditanyakan)

Di panel buka tab **Startup**. Kalau kolom startup command bisa diedit, isi salah satu:

**Versi lengkap (recommended) — auto git pull + auto npm install:**

```bash
if [ -d .git ]; then git pull || true; fi; if [ ! -d node_modules ]; then npm install --no-audit --no-fund; fi; npm start
```

**Versi minimal (tanpa git, untuk hasil upload zip):**

```bash
if [ ! -d node_modules ]; then npm install --no-audit --no-fund; fi; npm start
```

**Versi paling singkat** — sama persis dengan versi lengkap, karena logikanya
sudah dibungkus di `start.sh`:

```bash
bash start.sh
```

Catatan:

- Kalau log memunculkan `npm: command not found`, ganti setiap `npm` dengan path
  penuh `/usr/local/bin/npm` (image yolks Node.js 24 menyediakan binary di sana).
- Kalau kolom startup **terkunci** (tidak bisa diedit customer), biarkan command
  bawaan egg — selama command itu akhirnya menjalankan `npm start`, project ini
  langsung jalan karena `scripts.start` di `package.json` sudah benar.
- Docker image yang dipakai host umumnya `ghcr.io/parkervcp/yolks:nodejs_24`.
  Tidak perlu diubah.

## 3. Environment variable

Set di **Startup → Environment Variables** (cara utama di Pterodactyl), atau
salin `.env.example` menjadi `.env` lewat File Manager:

| Variable                    | Default        | Keterangan                              |
| --------------------------- | -------------- | --------------------------------------- |
| `HERMES_NAME`               | `hermes-agent` | Nama agent yang tampil di log           |
| `HERMES_TICK_INTERVAL_MS`   | `60000`        | Jarak antar tick dalam milidetik        |
| `NODE_ENV`                  | `production`   | Environment aplikasi                    |

## 4. Menjalankan & mengecek

1. Tekan **Restart** di panel.
2. Di tab **Console** harus muncul log:

   ```
   [hermes] hermes-agent starting (env=production, tick=60000ms, pid=...)
   [hermes] tick #1 at 2026-...
   [hermes] tick #2 at 2026-...
   ```

3. Tekan **Stop** — harus muncul `sinyal SIGTERM diterima...` lalu
   `berhenti dengan bersih`, artinya graceful shutdown bekerja.

## 5. Mengisi logika agent

Semua pekerjaan ditaruh di `src/agent.js`, tepatnya method `tick()`.
Method ini dipanggil sekali saat start lalu diulang setiap
`HERMES_TICK_INTERVAL_MS`. Tambahkan dependency dengan `npm install <paket>`
lalu import di file tersebut (ESM, gunakan `import ... from ...`).

## Troubleshooting

| Gejala di console                         | Solusi                                                                 |
| ----------------------------------------- | ---------------------------------------------------------------------- |
| `npm: command not found`                  | Pakai `/usr/local/bin/npm` di startup command                          |
| `Cannot find module ...`                  | Jalan ulang `npm install` di Console, atau hapus folder `node_modules` |
| Server langsung exit / crash loop         | Cek log merah di Console; pastikan `package.json` ada di root container |
| `git pull` gagal & server tidak update    | Command memakai `|| true` jadi tetap lanjut; cek perubahan lokal via `git status` |
| Log tick tidak muncul                     | Pastikan `HERMES_TICK_INTERVAL_MS` berupa angka positif (milidetik)    |
