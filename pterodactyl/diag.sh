#!/bin/sh
# Diagnostik kelayakan Hermes Agent resmi (NousResearch) di container Pterodactyl.
# Jalankan dari Console panel:  sh pterodactyl/diag.sh
# Script ini READ-ONLY: tidak mengubah apa pun.

section() { printf '\n===== %s =====\n' "$1"; }
ok() { printf '  [OK]   %s\n' "$1"; }
no() { printf '  [TIDAK ADA] %s\n' "$1"; }
info() { printf '  %s\n' "$1"; }

section "Sistem dasar"
printf 'waktu      : %s\n' "$(date 2>/dev/null || true)"
printf 'user       : %s\n' "$(id 2>/dev/null || true)"
printf 'uname      : %s\n' "$(uname -a 2>/dev/null || true)"
if [ -r /etc/os-release ]; then
  . /etc/os-release 2>/dev/null || true
  printf 'distro     : %s %s (ID=%s)\n' "${NAME:-?}" "${VERSION:-?}" "${ID:-?}"
fi

# Deteksi musl (Alpine) vs glibc
MUSL=0
if ls /lib/ld-musl-* >/dev/null 2>&1 || ldd --version 2>&1 | grep -qi musl; then
  MUSL=1
  printf 'libc       : musl (Alpine-style) — PM Hermes punya artifact -musl resmi\n'
else
  printf 'libc       : glibc (Debian-style)\n'
fi

case "$(uname -m 2>/dev/null)" in
  x86_64|amd64) ARCH=x64 ;;
  arm64|aarch64) ARCH=arm64 ;;
  *) ARCH="$(uname -m 2>/dev/null)" ;;
esac
printf 'arsitektur: %s -> target PM: linux-%s%s\n' "$(uname -m 2>/dev/null)" "$ARCH" \
  "$([ "$MUSL" = 1 ] && printf -- '-musl')"

section "Shell & perintah yang tersedia"
have() { if command -v "$1" >/dev/null 2>&1; then ok "$1 -> $(command -v "$1")"; else no "$1"; fi; }
have sh
have ash
have bash
have node
have npm
have git
have curl
have tar
have sha256sum
have awk
have ffmpeg
have python3
have rg
have docker

section "Docker (kemungkinan besar tidak tersedia)"
if [ -S /var/run/docker.sock ]; then
  info "DAERAH: /var/run/docker.sock ADA (jarang sekali di Pterodactyl shared)"
else
  info "/var/run/docker.sock tidak ada — docker-in-docker tidak bisa (normal untuk Pterodactyl)"
fi

section "Versi"
node -v 2>/dev/null | sed 's/^/node  : /' || no "node"
npm -v 2>/dev/null | sed 's/^/npm   : /' || no "npm"
git --version 2>/dev/null | sed 's/^/git   : /' || no "git"
ffmpeg -version 2>/dev/null | head -1 | sed 's/^/ffmpeg: /' || no "ffmpeg"

section "Resource"
printf 'folder home: %s\n' "$HOME"
df -h "$HOME" 2>/dev/null || info "df tidak tersedia"
printf '\n'
if command -v free >/dev/null 2>&1; then free -m 2>/dev/null || true; else info "free tidak tersedia"; fi
printf 'cpu core : %s\n' "$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo '?')"

section "Jaringan ( outbound yang dibutuhkan PM )"
netcheck() {
  url=$1
  code=$(curl -m 12 -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || printf 'GAGAL')
  case "$code" in
    2*|3*) ok "$url -> HTTP $code" ;;
    *) no "$url -> $code" ;;
  esac
}
netcheck https://github.com
netcheck https://codeload.github.com
netcheck https://objects.githubusercontent.com
netcheck https://pypi.org
netcheck https://files.pythonhosted.org
netcheck https://nodejs.org

section "Ringkasan"
info "Kebutuhan minimum jalur resmi (lewat PM user-space, tanpa root):"
info "  - node, git, curl, tar, sha256sum, awk (image yolks Node.js umumnya lengkap)"
info "  - disk kosong disarankan >= 3 GB (repo shallow + store ~/.hermes)"
info "  - RAM disarankan >= 1 GB (2 GB lebih nyaman)"
info "  - akses ke github.com + objects.githubusercontent.com + pypi.org"
info "Kalau diag ini lolos, lanjut: sh pterodactyl/install-hermes.sh"
