#!/bin/sh
# ============================================================================
# Installer Hermes Agent resmi (NousResearch/hermes-agent) untuk Pterodactyl.
# Murni POSIX sh — jalan di ash (Alpine/yolks) maupun dash/bash. TANPA root:
# semua tool (uv, Python 3.14, Node, ripgrep, dll.) dipasang PM ke ~/.hermes.
#
# Jalankan sekali (atau kapan pun untuk repair/update) dari Console panel:
#     sh pterodactyl/install-hermes.sh
#
# Knob lewat Environment Variables panel:
#   HERMES_REPO_DIR        folder checkout  (default: ~/hermes-agent)
#   HERMES_REPO_REF        branch/tag opsional saat clone
#   HERMES_RUNTIME_DIR     store PM         (default: ~/.hermes)
#   HERMES_MIN_DISK_MB     ambang disk MB   (default: 3072)
#   HERMES_PM_INSTALL_ARGS argumen pm.cli   (default: --trust-recorded)
#   HERMES_DRY_RUN=1       cek lingkungan & pin saja, tidak mengunduh
# ============================================================================
set -eu

REPO_URL="${HERMES_REPO_URL:-https://github.com/NousResearch/hermes-agent.git}"
REPO_DIR="${HERMES_REPO_DIR:-$HOME/hermes-agent}"
RUNTIME_DIR="${HERMES_RUNTIME_DIR:-$HOME/.hermes}"
MIN_DISK_MB="${HERMES_MIN_DISK_MB:-3072}"
PM_ARGS="${HERMES_PM_INSTALL_ARGS:---trust-recorded}"
LOG="$HOME/hermes-install.log"
STATUS_FILE="$RUNTIME_DIR/.install-status"

say() { printf '\033[1;36m->\033[0m %s\n' "$1"; }
good() { printf '\033[1;32m[OK]\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$1"; }
die() { printf '\033[1;31mX\033[0m %s\n' "$1" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "perintah '$1' tidak ditemukan — image ini tidak cocok."; }

# --- baca pm/lock.json pakai node (sudah pasti ada di egg Node.js) ----------
read_lock() {
  HERMES_LOCK="$REPO_DIR/pm/lock.json" node -e '
    const fs = require("fs");
    const [pkg, field, target] = process.argv.slice(1);
    const lock = JSON.parse(fs.readFileSync(process.env.HERMES_LOCK, "utf8"));
    const p = lock.packages[pkg];
    if (!p) process.exit(2);
    if (field === "version") process.stdout.write(String(p.version));
    else process.stdout.write(String(p.artifacts[target][field]));
  ' "$1" "$2" "${3:-}"
}

main() {
  trap 'echo FAILED > "$STATUS_FILE"' EXIT
  mkdir -p "$RUNTIME_DIR"

  say "Hermes Agent installer untuk Pterodactyl (log: $LOG)"
  require node; require git; require curl; require tar
  require sha256sum; require awk; require sed

  # --- identitas target ------------------------------------------------------
  case "$(uname -s)" in
    Linux) OS=linux ;;
    *) die "OS tidak didukung: $(uname -s)" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) ARCH=x64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    *) die "arsitektur tidak didukung: $(uname -m)" ;;
  esac
  TARGET="$OS-$ARCH"
  if ls /lib/ld-musl-* >/dev/null 2>&1 || ldd --version 2>&1 | grep -qi musl; then
    TARGET="$TARGET-musl"
    say "terdeteksi musl (Alpine) -> artifact $TARGET"
  fi

  # --- preflight disk --------------------------------------------------------
  AVAIL_MB=$(df -Pk "$HOME" | awk 'NR==2 {printf "%d", $4/1024}')
  if [ -n "$AVAIL_MB" ] && [ "$AVAIL_MB" -lt "$MIN_DISK_MB" ]; then
    warn "disk kosong cuma ${AVAIL_MB}MB (rekomendasi >= ${MIN_DISK_MB}MB)."
    warn "Lanjut bisa gagal di tengah. Hentikan & upgrade disk, atau set HERMES_MIN_DISK_MB lebih kecil."
  else
    good "disk kosong ${AVAIL_MB:-?}MB"
  fi

  # --- preflight jaringan ----------------------------------------------------
  for host in https://github.com https://objects.githubusercontent.com https://pypi.org; do
    code=$(curl -m 12 -sS -o /dev/null -w '%{http_code}' "$host" 2>/dev/null || printf 'GAGAL')
    case "$code" in 2*|3*) good "akses $host ($code)" ;; *) die "tidak bisa akses $host (HTTP $code)" ;; esac
  done

  # --- clone / update repo resmi ---------------------------------------------
  if [ -d "$REPO_DIR/.git" ]; then
    say "repo sudah ada di $REPO_DIR — git pull --ff-only"
    # Non-fatal: checkout lama yang valid tetap bisa dipakai walau update gagal.
    git -C "$REPO_DIR" pull --ff-only || warn "git pull gagal (offline/perubahan lokal?) — lanjut memakai checkout yang ada"
  else
    if [ "${HERMES_DRY_RUN:-0}" = 1 ]; then die "DRY RUN: $REPO_DIR belum ada; clone dilewati."; fi
    say "clone shallow official repo -> $REPO_DIR"
    if [ -n "${HERMES_REPO_REF:-}" ]; then
      git clone --depth 1 -b "$HERMES_REPO_REF" "$REPO_URL" "$REPO_DIR"
    else
      git clone --depth 1 "$REPO_URL" "$REPO_DIR"
    fi
  fi
  [ -f "$REPO_DIR/pm/lock.json" ] || die "pm/lock.json tidak ditemukan di checkout — clone bermasalah?"

  # --- pin dari lock.json ----------------------------------------------------
  UV_VERSION=$(read_lock uv version)
  UV_URL=$(read_lock uv url "$TARGET")
  UV_SHA=$(read_lock uv sha256 "$TARGET")
  PY_RAW=$(read_lock python version)
  PY_VER=$(printf '%s' "$PY_RAW" | sed 's/+.*//' | cut -d. -f1,2)
  good "pin: uv $UV_VERSION, Python $PY_VER ($TARGET)"

  if [ "${HERMES_DRY_RUN:-0}" = 1 ]; then
    say "DRY RUN selesai. Pin terverifikasi, tidak ada yang diunduh."
    echo OK > "$STATUS_FILE"; trap - EXIT; exit 0
  fi

  # --- stage uv (persis pola setup-hermes.sh resmi) --------------------------
  STORE="$RUNTIME_DIR/tools"
  ENTRY="$STORE/uv-$UV_VERSION-$TARGET"
  UV="$ENTRY/uv"
  if [ -x "$UV" ]; then
    good "uv pinned sudah ada: $("$UV" --version)"
  else
    say "mengunduh uv $UV_VERSION ke store..."
    mkdir -p "$STORE"
    TMP_DIR=$(mktemp -d "$STORE/.bootstrap-XXXXXX")
    ARCHIVE="$TMP_DIR/uv.tar.gz"
    curl -fSL --retry 3 -o "$ARCHIVE" "$UV_URL"
    GOT=$(sha256sum "$ARCHIVE" | cut -d' ' -f1)
    [ "$GOT" = "$UV_SHA" ] || die "sha256 uv tidak cocok (got $GOT, want $UV_SHA)"
    mkdir -p "$TMP_DIR/tree"
    tar -xzf "$ARCHIVE" -C "$TMP_DIR/tree"
    # ratakan satu folder pembungkus (uv-<triple>/uv)
    INNER=$(find "$TMP_DIR/tree" -mindepth 1 -maxdepth 1 -type d | head -1)
    rm -rf "$ENTRY"
    mv "$INNER" "$ENTRY"
    rm -rf "$TMP_DIR"
    [ -x "$UV" ] || die "binary uv tidak ditemukan setelah ekstrak"
    good "uv terpasang: $("$UV" --version)"
  fi

  # --- Python terkelola + PM install (pintu resmi setup-hermes.sh) ----------
  say "uv python install $PY_VER (managed, tanpa root)..."
  "$UV" python install --no-bin --no-registry "$PY_VER"
  BOOT_PY=$("$UV" python find --managed-python "$PY_VER" | tr -d '\r')
  [ -x "$BOOT_PY" ] || die "interpreter bootstrap tidak ketemu: $BOOT_PY"
  good "python: $("$BOOT_PY" --version 2>&1)"

  say "pm.cli install $PM_ARGS — bisa 1-10 menit pada run pertama..."
  cd "$REPO_DIR"
  # shellcheck disable=SC2086
  "$BOOT_PY" -m pm.cli install $PM_ARGS

  # --- .env ------------------------------------------------------------------
  if [ ! -f "$REPO_DIR/.env" ] && [ -f "$REPO_DIR/.env.example" ]; then
    cp "$REPO_DIR/.env.example" "$REPO_DIR/.env"
    chmod 600 "$REPO_DIR/.env" 2>/dev/null || true
    good ".env dibuat dari template (isi API key-mu di file itu)"
  fi

  # --- launcher hermes (wrapper #!/bin/sh, cocok ash) ------------------------
  mkdir -p "$HOME/.local/bin"
  say "menerbitkan launcher ke ~/.local/bin"
  "$BOOT_PY" -I -X utf8 hermes_cli/_launchers.py "$HOME/.local/bin"
  [ -x "$HOME/.local/bin/hermes" ] || die "launcher hermes tidak terbit"

  # --- skills ----------------------------------------------------------------
  SKILLS_DIR="$RUNTIME_DIR/skills"
  mkdir -p "$SKILLS_DIR"
  "$BOOT_PY" -m tools.skills_sync 2>/dev/null || cp -rn "$REPO_DIR/skills/"* "$SKILLS_DIR/" 2>/dev/null || true
  good "skills tersinkron ke $SKILLS_DIR"

  good "INSTALASI SELESAI."
  printf 'Langkah berikut:\n'
  printf '  1. isi %s/.env (API key LLM + token gateway), atau lewat: hermes setup\n' "$REPO_DIR"
  printf '  2. set Startup Command panel: sh pterodactyl/start-gateway.sh\n'
  echo OK > "$STATUS_FILE"
  trap - EXIT
}

main "$@" 2>&1 | tee -a "$LOG"
[ "$(cat "$STATUS_FILE" 2>/dev/null || true)" = OK ] || exit 1
