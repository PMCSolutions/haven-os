#!/usr/bin/env bash
# Runs inside the HavenBuild WSL instance (as root), called by build-windows.ps1.
#
#   wsl-build.sh <stage> <project path on the Windows drive, e.g. /mnt/c/Users/Paul/haven-os>
#
# Copies the project into the Linux filesystem, fixes Windows line endings and
# file permissions, runs build.sh, then copies the ISO back to Windows.
set -euo pipefail

STAGE="${1:-all}"
WIN_SRC="${2:?project path required}"
BUILD_DIR="${HAVEN_WSL_BUILD_DIR:-/opt/haven-os}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

if [[ $STAGE == clean ]]; then
  rm -rf "$BUILD_DIR"
  log "Removed $BUILD_DIR"
  exit 0
fi

[[ -d $WIN_SRC ]] || { echo "Project not found at $WIN_SRC" >&2; exit 1; }

# ---------------------------------------------------------------------------
# First run: initialise pacman's keyring and install rsync
# ---------------------------------------------------------------------------
if [[ ! -s /etc/pacman.d/gnupg/trustdb.gpg ]]; then
  log "Initialising package signing keys (first run)..."
  pacman-key --init
  pacman-key --populate archlinux
fi
if ! command -v rsync >/dev/null; then
  log "Installing rsync..."
  pacman -Sy --needed --noconfirm archlinux-keyring
  pacman -S --needed --noconfirm rsync
fi

# ---------------------------------------------------------------------------
# Copy project into the Linux filesystem
# ---------------------------------------------------------------------------
log "Syncing project to $BUILD_DIR..."
mkdir -p "$BUILD_DIR"
# Windows drives report every file as executable, so reset permissions
# rather than copying them (config files must not end up mode 777).
rsync -rt --delete --no-perms --chmod=D755,F644 \
  --exclude '/work/' --exclude '/out/' --exclude '/.git/' \
  "$WIN_SRC/" "$BUILD_DIR/"

# Fix CRLF line endings that Git or Windows editors may have added
log "Normalising line endings..."
while IFS= read -r -d '' f; do
  if grep -Iq . "$f" && grep -q $'\r' "$f"; then
    sed -i 's/\r$//' "$f"
  fi
done < <(find "$BUILD_DIR" -path "$BUILD_DIR/work" -prune -o -path "$BUILD_DIR/out" -prune -o \
         -type f ! -name '*.png' ! -name '*.ps1' ! -name '*.bat' -print0)

# Restore executable bits
chmod 755 "$BUILD_DIR/build.sh" "$BUILD_DIR/kernel/fetch-kernel.sh" \
  "$BUILD_DIR"/scripts/*.sh "$BUILD_DIR"/scripts/migrations/*.sh \
  "$BUILD_DIR"/scripts/windows/*.sh "$BUILD_DIR/iso/profiledef.sh" \
  "$BUILD_DIR"/iso/airootfs/usr/local/bin/* "$BUILD_DIR"/rootfs/usr/local/bin/*

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
cd "$BUILD_DIR"
./build.sh "$STAGE"

# ---------------------------------------------------------------------------
# Copy results back to Windows
# ---------------------------------------------------------------------------
shopt -s nullglob
isos=("$BUILD_DIR"/out/*.iso)
if (( ${#isos[@]} )); then
  mkdir -p "$WIN_SRC/out"
  log "Copying ISO to Windows: $WIN_SRC/out/"
  cp -f "$BUILD_DIR"/out/*.iso "$BUILD_DIR"/out/*.sha256 "$WIN_SRC/out/"
fi
