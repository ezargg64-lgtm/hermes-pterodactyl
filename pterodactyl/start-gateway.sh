#!/bin/sh
# Startup foreground untuk Hermes Agent gateway di Pterodactyl.
# Set Startup Command panel menjadi:  sh pterodactyl/start-gateway.sh
#
# Knob:
#   HERMES_SKIP_INSTALL=1   jangan auto-jalankan installer walau launcher hilang
#   HERMES_REPO_DIR         checkout official repo (default: ~/hermes-agent)
set -u

REPO_DIR="${HERMES_REPO_DIR:-$HOME/hermes-agent}"
HERMES_BIN="$HOME/.local/bin/hermes"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

say() { printf '\033[1;36m->\033[0m %s\n' "$1"; }
die() { printf '\033[1;31mX\033[0m %s\n' "$1" >&2; exit 1; }

if [ ! -x "$HERMES_BIN" ]; then
  if [ "${HERMES_SKIP_INSTALL:-0}" = 1 ]; then
    die "launcher $HERMES_BIN tidak ada dan HERMES_SKIP_INSTALL=1. Jalankan: sh pterodactyl/install-hermes.sh"
  fi
  say "launcher hermes belum ada — menjalankan installer dulu (boot pertama)..."
  sh "$SCRIPT_DIR/install-hermes.sh" || die "installer gagal; lihat $HOME/hermes-install.log"
fi

[ -x "$HERMES_BIN" ] || die "launcher $HERMES_BIN tetap tidak tersedia setelah install"

# .env resmi hidup di root checkout; env panel juga sudah otomatis tersedia
# sebagai environment variable proses, jadi key yang diisi via panel tetap kebaca.
cd "$REPO_DIR" 2>/dev/null || die "checkout $REPO_DIR tidak ditemukan"
export PATH="$HOME/.local/bin:$PATH"

say "memulai Hermes gateway (foreground, Ctrl+C/SIGTERM akan diteruskan)..."
# exec -> proses node/python gateway menggantikan shell jadi PID penerima sinyal
exec "$HERMES_BIN" gateway start "$@"
