#!/usr/bin/env bash
# Haven OS patch script — applies a new Haven release to an installed system.
#
# Download/extract the new project zip, then run (as root):
#   sudo ./scripts/patch.sh             apply the update
#   sudo ./scripts/patch.sh --dry-run   show what would change
#
# What it does:
#   1. Backs up every file it will replace (/var/backups/haven/<date>)
#   2. Updates /etc/pacman.conf repos and installs any new packages
#   3. Updates the system + Haven kernel (pacman -Syu)
#   4. Syncs Haven config files (rootfs/)
#   5. Runs version migrations in scripts/migrations/ newer than the installed version
#   6. Re-applies the user's own choices (DNS, firewall, security mode)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

DRY=0
[[ ${1:-} == --dry-run ]] && DRY=1

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"
[[ -f /etc/haven-release ]] || die "Haven OS isn't installed here (use scripts/install.sh)."

# shellcheck disable=SC1091
installed="$(source /etc/haven-release && echo "$VERSION")"
target="$OS_VERSION"

log "Installed: $installed    This patch: $target"
if ! version_gt "$target" "$installed"; then
  if [[ $target == "$installed" ]]; then
    warn "Already on $target — re-applying config and checking for package updates."
  else
    die "This patch ($target) is older than the installed version ($installed)."
  fi
fi

# Migrations newer than the installed version, in order
mapfile -t migrations < <(
  find "$HAVEN_ROOT/scripts/migrations" -maxdepth 1 -name '*.sh' -printf '%f\n' 2>/dev/null \
    | sed 's/\.sh$//' | sort -V \
    | while read -r v; do
        if version_gt "$v" "$installed" && ! version_gt "$v" "$target"; then echo "$v"; fi
      done
)

# Files that will change
changed=()
while IFS= read -r -d '' f; do
  rel="${f#"$HAVEN_ROOT/rootfs/"}"
  if [[ ! -e /$rel ]] || ! cmp -s "$f" "/$rel"; then changed+=("/$rel"); fi
done < <(find "$HAVEN_ROOT/rootfs" -type f -print0)

mapfile -t new_pkgs < <(
  installed_packages | while read -r p; do
    pacman -Qq "$p" &>/dev/null || echo "$p"
  done | grep -vE '^(nvidia-open-dkms|nvidia-utils|lib32-nvidia-utils)$' || true
)

log "Config files to update: ${#changed[@]}"
printf '      %s\n' "${changed[@]}"
log "New packages: ${#new_pkgs[@]}"
printf '      %s\n' "${new_pkgs[@]}"
log "Migrations to run: ${migrations[*]:-none}"

if (( DRY )); then
  log "Dry run — nothing changed."
  exit 0
fi

backup="/var/backups/haven/patch-${installed}-to-${target}-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
cp /etc/pacman.conf /etc/haven-release /etc/os-release "$backup/" 2>/dev/null || true
log "Backups: $backup"

# ---------------------------------------------------------------------------
log "Updating package repositories..."
current_server="$(sed -n '/^\[haven\]/,/^\[/{s/^Server *= *//p}' /etc/pacman.conf | head -n1)"
write_pacman_conf /etc/pacman.conf "${HAVEN_REPO_URL:-$current_server}"

log "Updating system and kernel..."
pacman -Syu --noconfirm
if (( ${#new_pkgs[@]} )); then
  pacman -S --needed --noconfirm "${new_pkgs[@]}"
fi

# ---------------------------------------------------------------------------
log "Updating Haven configuration..."
sync_rootfs / "$backup"
write_os_release /

# ---------------------------------------------------------------------------
for v in "${migrations[@]}"; do
  log "Running migration $v..."
  # shellcheck disable=SC1090
  ( source "$HAVEN_ROOT/scripts/migrations/$v.sh" )
done

# ---------------------------------------------------------------------------
log "Re-applying your settings..."
haven-settings reapply || warn "Could not re-apply settings; run 'sudo haven-settings reapply'."
systemctl daemon-reload
sysctl --system >/dev/null
udevadm control --reload || true

# Keep the local project copy current for next time
rm -rf /usr/share/haven/project
install -d /usr/share/haven/project/iso
cp -a "$HAVEN_ROOT/scripts" "$HAVEN_ROOT/rootfs" "$HAVEN_ROOT/haven.conf" /usr/share/haven/project/
cp "$HAVEN_ROOT/iso/packages.x86_64" /usr/share/haven/project/iso/

log "Haven OS updated to $target."
if [[ ! -d /usr/lib/modules/$(uname -r) ]]; then
  log "A new kernel was installed — please restart."
fi
log "To undo config changes, copy files back from $backup"
