#!/bin/bash
# Startup script Hermes agent untuk Pterodactyl (Node.js 24).
# Di panel cukup isi Startup Command dengan: bash start.sh
set -euo pipefail
cd "$(dirname "$0")"

# Opsional: tarik update terbaru bila project di-clone lewat git.
# Tidak membuat server crash kalau git pull gagal (mis. ada perubahan lokal).
if [ -d .git ]; then
  git pull || echo "[start] git pull dilewati (perubahan lokal / repo tidak bisa diakses)"
fi

# Install dependency hanya bila node_modules belum ada
if [ ! -d node_modules ]; then
  echo "[start] node_modules belum ada, menjalankan npm install..."
  npm install --no-audit --no-fund
fi

# exec menggantikan shell supaya node jadi proses utama (menerima SIGTERM langsung)
exec npm start
