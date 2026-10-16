#!/usr/bin/env bash
# Haven OS installer script — turns an existing Arch Linux install into Haven OS.
#
# Most people should install from the Haven ISO instead (graphical installer,
# disk encryption). This script is for:
#   - testing Haven on a machine/VM that already runs Arch
#   - users who installed Arch themselves and want the Haven experience
#
# Usage (as root, from the project folder):
#   sudo ./scripts/install.sh                 # use HAVEN_REPO_URL from haven.conf
#   sudo ./scripts/install.sh --local-repo    # use packages built in out/repo
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"
[[ -f /etc/arch-release ]] || die "This script needs an existing Arch Linux system."
[[ -d /sys/firmware/efi ]] || warn "Legacy BIOS boot detected — Haven is tested on UEFI only."

server="$HAVEN_REPO_URL"
if [[ ${1:-} == --local-repo ]]; then
  [[ -f $HAVEN_ROOT/out/repo/haven.db.tar.gz ]] || die "No local repo — run ./build.sh kernel first."
  server="file://$HAVEN_ROOT/out/repo"
fi
[[ -n $server ]] || die "No package source: set HAVEN_REPO_URL in haven.conf or use --local-repo."

if [[ -f /etc/haven-release ]]; then
  die "Haven OS is already installed. Use scripts/patch.sh to update."
fi

backup="/var/backups/haven/install-$(date +%Y%m%d-%H%M%S)"
log "Backups of changed files go to $backup"
mkdir -p "$backup"

# ---------------------------------------------------------------------------
log "1/7  Configuring package repositories (Haven + multilib)..."
cp /etc/pacman.conf "$backup/pacman.conf"
write_pacman_conf /etc/pacman.conf "$server"
if [[ -n $GPG_SIGN_KEY && -f $HAVEN_ROOT/haven-signing.asc ]]; then
  pacman-key --add "$HAVEN_ROOT/haven-signing.asc"
  pacman-key --lsign-key "$GPG_SIGN_KEY"
fi

# ---------------------------------------------------------------------------
log "2/7  Installing the Haven kernel, desktop, drivers and gaming stack..."
mapfile -t pkgs < <(installed_packages)
if ! lspci | grep -qi nvidia; then
  mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | grep -vE '^(nvidia-open-dkms|nvidia-utils|lib32-nvidia-utils)$')
fi
pacman -Syu --needed --noconfirm "${pkgs[@]}"

# ---------------------------------------------------------------------------
log "3/7  Applying Haven system configuration..."
sync_rootfs / "$backup"
write_os_release /
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
if lspci | grep -qi nvidia; then
  echo "options nvidia_drm modeset=1 fbdev=1" > /etc/modprobe.d/haven-nvidia.conf
fi

# ---------------------------------------------------------------------------
log "4/7  Enabling services..."
systemctl enable "${HAVEN_SERVICES[@]}"
# Switch display manager to SDDM only if none is configured
if [[ ! -e /etc/systemd/system/display-manager.service ]]; then
  systemctl enable sddm.service
else
  warn "A display manager is already enabled; leaving it alone."
fi

# ---------------------------------------------------------------------------
log "5/7  Adding users to gaming groups..."
while IFS=: read -r name _ uid _; do
  if (( uid >= 1000 && uid < 60000 )); then
    usermod -aG gamemode,video,input "$name" || true
  fi
done < /etc/passwd

# ---------------------------------------------------------------------------
log "6/7  Adding a boot entry for the Haven kernel..."
if bootctl is-installed &>/dev/null; then
  esp="$(bootctl --print-esp-path)"
  root_opts="$(sed -E 's/(^| )(BOOT_IMAGE|initrd)=[^ ]*//g' /proc/cmdline)"
  ucode=""
  [[ -f $esp/intel-ucode.img ]] && ucode+="initrd  /intel-ucode.img"$'\n'
  [[ -f $esp/amd-ucode.img ]]   && ucode+="initrd  /amd-ucode.img"$'\n'
  cat > "$esp/loader/entries/haven.conf" <<EOF
title   $OS_NAME
linux   /vmlinuz-linux-haven
${ucode}initrd  /initramfs-linux-haven.img
options $root_opts lsm=landlock,lockdown,yama,integrity,apparmor,bpf nvidia_drm.modeset=1
EOF
  bootctl set-default haven.conf || true
  log "systemd-boot entry written to $esp/loader/entries/haven.conf"
elif command -v grub-mkconfig &>/dev/null; then
  if ! grep -q 'apparmor' /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="/&lsm=landlock,lockdown,yama,integrity,apparmor,bpf /' /etc/default/grub
  fi
  grub-mkconfig -o /boot/grub/grub.cfg
else
  warn "Unknown bootloader — add /boot/vmlinuz-linux-haven to your boot menu manually."
fi

# ---------------------------------------------------------------------------
log "7/7  Saving default Haven settings..."
install -Dm644 /dev/stdin /etc/haven/settings.conf <<EOF
DNS=$DEFAULT_DNS
REMOTE_PLAY=off
MAX_SECURITY=off
EOF
haven-settings dns "$DEFAULT_DNS" || true

# Keep a copy of the project so patch.sh can be run locally later
install -d /usr/share/haven/project
cp -a "$HAVEN_ROOT/scripts" "$HAVEN_ROOT/rootfs" "$HAVEN_ROOT/haven.conf" /usr/share/haven/project/
install -Dm644 "$HAVEN_ROOT/iso/packages.x86_64" /usr/share/haven/project/iso/packages.x86_64

log "Haven OS $OS_VERSION installed. Reboot and pick '$OS_NAME' in the boot menu."
log "Backups of replaced files: $backup"
