# hermes-pterodactyl

Harness untuk menjalankan **Hermes Agent resmi ([NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent))**
di server **Pterodactyl** yang egg-nya terkunci **Node.js 24** — tanpa akses admin,
tanpa root, dan tanpa Docker-in-Docker.

> Repo ini **bukan** codebase Hermes Agent. Repo resmi berbahasa Python 3.14 dan
> berukuran ±1,3 GB; repo ini hanya berisi installer & startup wrapper POSIX `sh`
> yang menarik repo resmi pada saat instalasi di server kamu. Skeleton Node.js di
> root repo adalah jalur cadangan (lihat [Track B](#track-b-fallback-nodejs-api-client)).

## Kenapa pendekatan ini bisa bekerja

Image egg Node.js yolks (umumnya berbasis Alpine/musl) sudah berisi `node git curl
ffmpeg tar sqlite`. Hermes memiliki package manager sendiri (**PM**) yang mengunduh
seluruh toolchain-nya ke folder user (tanpa root):

| Kebutuhan Hermes | Cara penuhin di Pterodactyl |
| --- | --- |
| Python 3.14 | `uv python install` — build standalone resmi, termasuk varian **musl** |
| uv / Node 26 / ripgrep / dll. | Diunduh PM ke `~/.hermes/tools` (artifact `-musl` tersedia di `pm/lock.json`) |
| ffmpeg, git, sqlite | Sudah ada di image yolks |
| Docker | **Tidak dipakai** — terminal tool di-set `TERMINAL_ENV=local` |
| Port publik | **Tidak perlu** — Telegram long-polling & Slack socket mode hanya butuh outbound |

Yang **tidak** tersedia dan memang tidak bisa diakali: Docker-in-Docker (tidak ada
`/var/run/docker.sock`, container non-privileged) dan `apk install` (tanpa root).

---

## Track A — Hermes Agent resmi (tujuan utama)

### Prasyarat

- Egg Node.js (24 atau berapapun — Node sistem hanya dipakai untuk membaca pin),
  Startup Command bisa diedit.
- Disk kosong **≥ 3 GB** (repo shallow ±500 MB + store `~/.hermes` ±1,5–2,5 GB).
- RAM **≥ 1 GB**, makin nyaman di 2 GB saat instalasi dependency.
- Outbound ke `github.com`, `objects.githubusercontent.com`, `pypi.org`,
  `files.pythonhosted.org`, `nodejs.org` (mayoritas host Pterodactyl mengizinkan).

### Langkah 1 — Siapkan kode harness di container

Kalau folder `/home/container` masih kosong, clone repo ini lewat **Console** panel:

```bash
git clone -b arena/e81e7527-hermes-pterodactyl https://github.com/ezargg64-lgtm/hermes-pterodactyl.git .
```

(atau upload ZIP branch ini lalu extract di root container).

### Langkah 2 — Diagnostik (read-only, wajib dulu)

```bash
sh pterodactyl/diag.sh
```

Output memberi tahu: distro/musl, arsitektur, tool yang tersedia, sisa disk/RAM,
hasil cek jaringan, dan konfirmasi bahwa Docker tidak ada (normal). **Tempel output-nya
ke chat kalau ada baris `[TIDAK ADA]` atau `GAGAL`.**

### Langkah 3 — Instalasi satu kali

```bash
sh pterodactyl/install-hermes.sh
```

Script ini (murni POSIX `sh`, lolos uji di dash & busybox ash):

1. Cek disk & jaringan.
2. `git clone --depth 1` repo resmi ke `~/hermes-agent` (bisa di-override `HERMES_REPO_DIR`).
3. Baca pin terverifikasi dari `pm/lock.json` pakai `node`, unduh **uv** dengan
   verifikasi sha256 ke `~/.hermes/tools`.
4. `uv python install 3.14` lalu `python -m pm.cli install --trust-recorded`
   (semua dependency ter-hash via `uv.lock`; run pertama 1–10 menit).
5. Membuat `.env` dari template, menerbitkan launcher `~/.local/bin/hermes`
   (wrapper `#!/bin/sh` — jalan di ash), dan sinkronisasi skills.

Aman diulang (idempoten). Log tersimpan di `~/hermes-install.log`.
Mode uji coba tanpa unduhan: `HERMES_DRY_RUN=1 sh pterodactyl/install-hermes.sh`.

### Langkah 4 — Konfigurasi

Opsi termudah lewat Console panel (terminal web-nya interaktif):

```bash
export PATH="$HOME/.local/bin:$PATH"
hermes setup            # wizard: provider LLM, API key, model
hermes gateway setup    # wizard: pilih Telegram/Discord/Slack/WhatsApp + token
```

Atau konfigurasi non-interaktif — isi Environment Variables di tab **Startup**
(panel otomatis mengekspornya), acuannya di [`pterodactyl/hermes.env.example`](pterodactyl/hermes.env.example).
Variabel minimum:

| Variabel | Fungsi |
| --- | --- |
| `OPENROUTER_API_KEY` | Key LLM (satu key untuk banyak model, termasuk Hermes) |
| `TELEGRAM_BOT_TOKEN` + `TELEGRAM_ALLOWED_USERS` | Gateway Telegram (long-polling, tanpa port) |
| `DISCORD_BOT_TOKEN` + `DISCORD_ALLOWED_USERS` | Gateway Discord (aktifkan *Message Content Intent*) |
| `SLACK_BOT_TOKEN` + `SLACK_APP_TOKEN` | Gateway Slack (socket mode) |
| `GATEWAY_ALLOW_ALL_USERS` | Biarkan `false` — jangan buka gateway untuk publik |
| `TERMINAL_ENV=local` | **Wajib di Pterodactyl** — mematikan backend docker |

Daftar lengkap variabel ada di `~/hermes-agent/.env.example` (500+ baris, semua provider).

### Langkah 5 — Startup Command

Di tab **Startup**, ganti menjadi:

```bash
sh pterodactyl/start-gateway.sh
```

Script ini memastikan launcher ada (auto-jalankan installer pada boot pertama bila
perlu), pindah ke folder checkout, lalu `exec hermes gateway start` secara
**foreground** — sinyal Stop/Restart panel (SIGTERM) diteruskan dengan benar.

Tekan **Restart**, dan di Console harus muncul log gateway yang connect ke platform
messaging. Kirim pesan ke bot untuk verifikasi.

### Perawatan

| Tujuan | Perintah (di Console) |
| --- | --- |
| Update Hermes | `sh pterodactyl/install-hermes.sh` (pull + pm install ulang, cache dipakai ulang) |
| Cek kesehatan | `~/.local/bin/hermes doctor` |
| Ganti model | `~/.local/bin/hermes model` |
| Lihat status gateway | `~/.local/bin/hermes gateway status` |
| Log instalasi | `cat ~/hermes-install.log` |
| Hapus total | `rm -rf ~/hermes-agent ~/.hermes ~/.local/bin/hermes ~/hermes-install.log` |

### Troubleshooting

| Gejala | Penyebab / solusi |
| --- | --- |
| `tidak bisa akses ... (HTTP GAGAL)` di diag | Host mem-whitelist domain. Minta provider mengizinkan github.com, objects.githubusercontent.com, pypi.org, files.pythonhosted.org, nodejs.org |
| `pm.cli install` mati di tengah (Killed) | OOM saat build. Naikkan RAM ke ≥2 GB, lalu jalankan ulang installer (cache tersimpan, retry lebih ringan) |
| `No space left on device` | Disk paket kekecilan; butuh ≥3 GB. Bersihkan `~/.hermes/tools/.bootstrap-*` lalu ulangi |
| `sha256 ... tidak cocok` | Download korup/ter-intercept. Ulangi; bila konsisten, laporkan beserta log |
| `bash: not found` / script resmi menolak | Jangan jalankan `setup-hermes.sh`/`activate` (butuh bash). Pakai harness ini — launcher `hermes` sendiri ber-`#!/bin/sh` |
| Gateway error soal docker | Pastikan env `TERMINAL_ENV=local` ter-set |
| Bot Telegram tidak merespons | Cek `TELEGRAM_ALLOWED_USERS` berisi ID numerikmu dan `GATEWAY_ALLOW_ALL_USERS=false` |
| Startup balik ke `npm start` skeleton | Startup Command panel tersimpan default egg — set ulang ke `sh pterodactyl/start-gateway.sh` |

---

## Track B — Fallback Node.js API client

Kalau Track A ternyata tak memungkinkan (resource terlalu kecil / jaringan
dibatalkan host), skeleton Node.js di root repo ini bisa diubah menjadi agen
ringan yang **memanggil model Hermes lewat API** (OpenRouter/Nous Portal, endpoint
OpenAI-compatible) — bukan codebase resmi, tapi cukup untuk gateway chat 24/7.

Struktur skeleton:

```
package.json        # npm start -> node (auto --env-file=.env bila ada)
src/index.js        # entry point + graceful SIGTERM/SIGINT
src/agent.js        # loop tick — logika agent diisi di method tick()
src/config.js       # baca HERMES_NAME, HERMES_TICK_INTERVAL_MS
start.sh            # wrapper: npm install (bila perlu) -> npm start
```

Startup command untuk jalur ini:

```bash
if [ ! -d node_modules ]; then npm install --no-audit --no-fund; fi; npm start
```

Pengembangan Track B baru dilanjutkan kalau hasil `diag.sh` menunjukkan Track A
tidak layak — dan tinggal tentukan platform (Telegram/Discord/Slack) + provider API.

## Isi folder

```
.
├── pterodactyl/
│   ├── diag.sh              # diagnostik kelayakan (read-only)
│   ├── install-hermes.sh    # installer POSIX sh untuk Hermes resmi (Track A)
│   ├── start-gateway.sh     # startup foreground `hermes gateway start`
│   └── hermes.env.example   # contoh env minimum gateway
├── src/ …                   # skeleton Node.js (Track B)
├── package.json, start.sh   # milik Track B
└── README.md
```
