#!/usr/bin/env bash
# Build Haven OS: custom kernel -> package repo -> bootable ISO.
#
# Usage:
#   ./build.sh            full build (kernel, installer packages, ISO)
#   ./build.sh check      check the package list exists in the Arch repos (quick)
#   ./build.sh kernel     build only the linux-haven kernel packages
#   ./build.sh iso        build only the ISO (reuses packages in out/repo)
#   ./build.sh clean      remove work/ and out/
#
# Runs natively on Arch Linux. On any other Linux (or WSL2), it runs itself
# inside an Arch container with Docker or Podman automatically.
set -euo pipefail
source "$(dirname "$0")/scripts/lib.sh"

ROOT="$HAVEN_ROOT"
WORK="$ROOT/work"
OUT="$ROOT/out"
REPO="$OUT/repo"
STAGE="${1:-all}"

# ---------------------------------------------------------------------------
# Re-run inside an Arch container when not on Arch
# ---------------------------------------------------------------------------
if [[ $STAGE == clean ]]; then
  rm -rf "$WORK" "$OUT"
  log "Cleaned."
  exit 0
fi

if [[ ! -f /etc/arch-release ]]; then
  engine=""
  command -v podman >/dev/null && engine=podman
  command -v docker >/dev/null && engine=docker
  [[ -n $engine ]] || die "Not on Arch Linux and neither Docker nor Podman is installed."
  log "Not on Arch — building inside an archlinux container with $engine"
  exec "$engine" run --rm --privileged \
    -v "$ROOT":/haven -w /haven \
    -e GPG_SIGN_KEY="${GPG_SIGN_KEY}" \
    -e GPG_PRIVATE_KEY="${GPG_PRIVATE_KEY:-}" \
    -e GITHUB_ACTIONS="${GITHUB_ACTIONS:-}" \
    docker.io/archlinux/archlinux:latest \
    bash -c "/haven/build.sh $STAGE"
fi

if [[ -n ${GITHUB_ACTIONS:-} ]]; then
  set -E
  trap 'printf "::error::build.sh failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND"' ERR
fi

[[ $EUID -eq 0 ]] || die "Run as root (sudo ./build.sh) — mkarchiso needs it."

# ---------------------------------------------------------------------------
# Build host setup
# ---------------------------------------------------------------------------
setup_host() {
  # 32-bit packages (Steam, Wine) live in [multilib]; container images ship with it off
  if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >> /etc/pacman.conf
  fi

  log "Installing build tools..."
  pacman -Syu --needed --noconfirm \
    base-devel archiso git jq curl bc cpio gettext libelf pahole perl python \
    xz zstd tar sudo pacman-contrib

  # CI passes the signing key in as an environment variable
  if [[ -n ${GPG_PRIVATE_KEY:-} ]]; then
    log "Importing package signing key..."
    printf '%s\n' "$GPG_PRIVATE_KEY" | gpg --batch --import
  fi

  if ! id builder &>/dev/null; then
    useradd -m builder
    echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-builder
  fi
  mkdir -p "$WORK" "$REPO"
  chown -R builder: "$WORK"
}

# Run a command as the unprivileged build user. On failure in GitHub Actions,
# post the last 40 lines of output to the run page (logs can be hard to reach).
as_builder() {
  local logf="$WORK/.last-command.log"
  if sudo -u builder -H env GITHUB_ACTIONS="${GITHUB_ACTIONS:-}" bash -c "$*" 2>&1 | tee "$logf"; then
    return 0
  fi
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    local tail_txt cmd="$*"
    cmd="${cmd:0:80}"; cmd="${cmd//,/%2C}"; cmd="${cmd//::/%3A%3A}"
    tail_txt=$(tail -n 40 "$logf" | sed 's/%/%25/g; s/\r/%0D/g' | sed ':a;N;$!ba;s/\n/%0A/g')
    printf '::error title=Last output of: %s::%s\n' "$cmd" "$tail_txt"
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Kernel
# ---------------------------------------------------------------------------
build_kernel() {
  log "Resolving kernel version..."
  bash "$ROOT/kernel/fetch-kernel.sh"

  rm -rf "$WORK/kernel"
  cp -a "$ROOT/kernel" "$WORK/kernel"

  log "Fetching Arch's current kernel config (from the linux-headers package)..."
  pacman -Sw --noconfirm linux-headers >/dev/null
  local hdr tmp
  hdr="$(ls -t /var/cache/pacman/pkg/linux-headers-[0-9]*.pkg.tar.zst | head -n1)"
  tmp="$(mktemp -d)"
  bsdtar -xf "$hdr" -C "$tmp" 'usr/lib/modules/*/build/.config'
  install -m644 "$tmp"/usr/lib/modules/*/build/.config "$WORK/kernel/config.arch"
  rm -rf "$tmp"
  log "Base config: $(basename "$hdr")"
  chown -R builder: "$WORK/kernel"

  log "Importing kernel.org signing keys..."
  # WKD first; fall back to a public keyserver by fingerprint
  as_builder "gpg --auto-key-locate clear,wkd --locate-keys torvalds@kernel.org gregkh@kernel.org" || \
  as_builder "gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys \
      ABAF11C65A2970B130ABE3C479BE3E4300411886 647F28654894E3BD457199BE38DBBDC86092693E"

  log "Compiling linux-haven (this takes 30 minutes to a few hours)..."
  as_builder "cd '$WORK/kernel' && MAKEFLAGS='-j$(nproc)' makepkg -s --noconfirm --cleanbuild"

  cp "$WORK"/kernel/*.pkg.tar.zst "$REPO/"
  # The compiled source tree is 20+ GB; free it before the ISO stage
  rm -rf "$WORK/kernel/src" "$WORK/kernel/pkg"
}

# ---------------------------------------------------------------------------
# Quick check: every package in the ISO list exists in the Arch repos
# (fails in minutes instead of after the kernel build)
# ---------------------------------------------------------------------------
check_packages() {
  log "Checking the package list against the Arch repositories..."
  local missing=() p
  while read -r p; do
    case "$p" in linux-haven|linux-haven-headers|calamares|ckbcomp) continue ;; esac
    pacman -Si "$p" &>/dev/null || pacman -Sg "$p" &>/dev/null || missing+=("$p")
  done < <(grep -vE '^\s*(#|$)' "$ROOT/iso/packages.x86_64")
  if (( ${#missing[@]} )); then
    die "Not found in the Arch repos: ${missing[*]}"
  fi
  log "All packages found."
}

# ---------------------------------------------------------------------------
# Installer packages from the AUR
# ---------------------------------------------------------------------------
build_aur() {
  local pkg
  for pkg in ckbcomp calamares; do
    log "Building $pkg from AUR..."
    rm -rf "$WORK/aur/$pkg"
    as_builder "mkdir -p '$WORK/aur' && git clone --depth 1 https://aur.archlinux.org/$pkg.git '$WORK/aur/$pkg'"
    as_builder "cd '$WORK/aur/$pkg' && makepkg -si --noconfirm --needed"
    cp "$WORK/aur/$pkg"/*.pkg.tar.zst "$REPO/"
  done
}

# ---------------------------------------------------------------------------
# Package repository
# ---------------------------------------------------------------------------
build_repo() {
  log "Creating the haven package repository..."
  rm -f "$REPO"/haven.db* "$REPO"/haven.files* "$REPO"/*.sig
  local args=()
  if [[ -n $GPG_SIGN_KEY ]]; then
    local p
    for p in "$REPO"/*.pkg.tar.zst; do
      gpg --batch --yes --detach-sign --local-user "$GPG_SIGN_KEY" "$p"
    done
    args=(--sign --key "$GPG_SIGN_KEY")
  fi
  repo-add "${args[@]}" "$REPO/haven.db.tar.gz" "$REPO"/*.pkg.tar.zst
}

# ---------------------------------------------------------------------------
# ISO
# ---------------------------------------------------------------------------
build_iso() {
  [[ -f $REPO/haven.db.tar.gz ]] || die "No package repo found — run './build.sh' or './build.sh kernel' first."

  local profile="$WORK/profile"
  rm -rf "$profile" "$WORK/archiso"
  cp -a "$ROOT/iso" "$profile"

  log "Applying branding ($OS_NAME $OS_VERSION)..."
  local label="${OS_VERSION//./_}"
  sed -i \
    -e "s|@OS_ID@|$OS_ID|g" \
    -e "s|@OS_NAME@|$OS_NAME|g" \
    -e "s|@OS_VERSION@|$OS_VERSION|g" \
    -e "s|@OS_VERSION_LABEL@|$label|g" \
    "$profile/profiledef.sh" \
    "$profile/airootfs/etc/calamares/branding/haven/branding.desc"

  # Build-time pacman.conf: pulls Haven packages from the local repo
  sed -e "s|@HAVEN_SERVER@|file://$REPO|" \
      -e "s|@HAVEN_SIGLEVEL@|Optional TrustAll|" \
      "$profile/pacman.conf.in" > "$profile/pacman.conf"
  rm "$profile/pacman.conf.in"

  log "Overlaying Haven system files..."
  local air="$profile/airootfs"
  HAVEN_ROOT="$ROOT" sync_rootfs "$air"
  write_os_release "$air"
  write_pacman_conf "$air/etc/pacman.conf" "$HAVEN_REPO_URL"

  if [[ -n $GPG_SIGN_KEY ]]; then
    install -d "$air/usr/share/haven"
    gpg --armor --export "$GPG_SIGN_KEY" > "$air/usr/share/haven/haven-signing.asc"
    echo "$GPG_SIGN_KEY" > "$air/usr/share/haven/haven-signing.keyid"
  fi

  # Ship the patch tooling so installed systems can apply updates offline
  install -d "$air/usr/share/haven/project"
  cp -a "$ROOT/scripts" "$ROOT/rootfs" "$ROOT/haven.conf" "$air/usr/share/haven/project/"
  install -d "$air/usr/share/haven/project/iso"
  cp "$ROOT/iso/packages.x86_64" "$air/usr/share/haven/project/iso/"

  log "Enabling services in the image..."
  local sysd="$air/etc/systemd/system"
  install -d "$sysd/multi-user.target.wants" "$sysd/sysinit.target.wants" "$sysd/timers.target.wants"
  ln -sf /usr/lib/systemd/system/NetworkManager.service        "$sysd/multi-user.target.wants/"
  ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service "$sysd/dbus-org.freedesktop.nm-dispatcher.service"
  ln -sf /usr/lib/systemd/system/systemd-resolved.service      "$sysd/multi-user.target.wants/"
  ln -sf /usr/lib/systemd/system/systemd-resolved.service      "$sysd/dbus-org.freedesktop.resolve1.service"
  ln -sf /usr/lib/systemd/system/firewalld.service             "$sysd/multi-user.target.wants/"
  ln -sf /usr/lib/systemd/system/firewalld.service             "$sysd/dbus-org.fedoraproject.FirewallD1.service"
  ln -sf /usr/lib/systemd/system/bluetooth.service             "$sysd/multi-user.target.wants/"
  ln -sf /usr/lib/systemd/system/power-profiles-daemon.service "$sysd/multi-user.target.wants/"
  ln -sf /usr/lib/systemd/system/apparmor.service              "$sysd/sysinit.target.wants/"
  ln -sf /usr/lib/systemd/system/fstrim.timer                  "$sysd/timers.target.wants/"
  ln -sf /etc/systemd/system/haven-live-setup.service          "$sysd/multi-user.target.wants/"
  ln -sf /usr/lib/systemd/system/sddm.service                  "$sysd/display-manager.service"
  ln -sf /run/systemd/resolve/stub-resolv.conf "$air/etc/resolv.conf"

  log "Building the ISO (mkarchiso)..."
  mkarchiso -v -w "$WORK/archiso" -o "$OUT" "$profile"

  local iso
  iso="$(ls -t "$OUT"/*.iso | head -n1)"
  (cd "$OUT" && sha256sum "$(basename "$iso")" > "$(basename "$iso").sha256")
  log "ISO ready: $iso"
}

setup_host
case "$STAGE" in
  all)           check_packages; build_kernel; build_aur; build_repo; build_iso ;;
  check)         check_packages ;;
  kernel)        build_kernel; build_repo ;;
  aur)           build_aur; build_repo ;;
  iso)           build_iso ;;
  installer-iso) build_aur; build_repo; build_iso ;;   # used by CI after the kernel job
  *)             die "Unknown stage '$STAGE' (all | check | kernel | aur | iso | installer-iso | clean)" ;;
esac
log "Done."
