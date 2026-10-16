#!/usr/bin/env bash
# Shared helpers for build.sh, install.sh and patch.sh
# shellcheck disable=SC2034

HAVEN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../haven.conf
source "$HAVEN_ROOT/haven.conf"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==> WARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m==> ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Services every Haven install runs
HAVEN_SERVICES=(
  NetworkManager.service
  systemd-resolved.service
  firewalld.service
  apparmor.service
  bluetooth.service
  power-profiles-daemon.service
  systemd-timesyncd.service
  fstrim.timer
)

# write_os_release <target-root>
write_os_release() {
  local root="$1"
  install -d "$root/etc"
  rm -f "$root/etc/os-release"
  cat > "$root/etc/os-release" <<EOF
NAME="$OS_NAME"
PRETTY_NAME="$OS_NAME $OS_VERSION ($OS_CODENAME)"
ID=$OS_ID
ID_LIKE=arch
VERSION="$OS_VERSION ($OS_CODENAME)"
VERSION_ID=$OS_VERSION
BUILD_ID=rolling
ANSI_COLOR="38;2;31;111;235"
HOME_URL="https://github.com/PMCSolutions/haven-os"
SUPPORT_URL="https://github.com/PMCSolutions/haven-os/issues"
LOGO=distributor-logo
EOF
  cat > "$root/etc/haven-release" <<EOF
VERSION=$OS_VERSION
CODENAME=$OS_CODENAME
EOF
}

# write_pacman_conf <target-file> <server-url> [siglevel]
write_pacman_conf() {
  local target="$1" server="$2" siglevel="${3:-}"
  if [[ -z $siglevel ]]; then
    if [[ -n $GPG_SIGN_KEY ]]; then siglevel="Required"; else siglevel="Optional TrustAll"; fi
  fi
  local repo_block
  if [[ -n $server ]]; then
    repo_block="[haven]
SigLevel = $siglevel
Server = $server"
  else
    repo_block="# [haven]  — set HAVEN_REPO_URL in haven.conf to receive kernel updates
# SigLevel = $siglevel
# Server = https://github.com/<you>/haven-os/releases/download/repo"
  fi
  cat > "$target" <<EOF
# Haven OS pacman configuration
[options]
HoldPkg     = pacman glibc
Architecture = auto
ParallelDownloads = 5
Color
ILoveCandy
CheckSpace
SigLevel    = Required DatabaseOptional
LocalFileSigLevel = Optional

# Haven repo comes first so linux-haven updates take priority
$repo_block

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
}

# sync_rootfs <target-root> [backup-dir]
# Copies the Haven overlay onto a system, backing up any file it changes.
sync_rootfs() {
  local root="$1" backup="${2:-}"
  local src="$HAVEN_ROOT/rootfs"
  local f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    if [[ -n $backup && -e $root/$rel ]] && ! cmp -s "$f" "$root/$rel"; then
      install -D -m644 "$root/$rel" "$backup/$rel"
    fi
    install -D -m "$(stat -c %a "$f")" "$f" "$root/$rel"
  done < <(find "$src" -type f -print0)
}

# Lines from the ISO package list that make sense on an installed system
installed_packages() {
  grep -vE '^\s*(#|$)' "$HAVEN_ROOT/iso/packages.x86_64" \
    | grep -vxE 'mkinitcpio-archiso|calamares|ckbcomp'
}

version_gt() {  # version_gt A B  -> true if A > B
  [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1) == "$1" ]]
}
