#!/usr/bin/env bash
# shellcheck disable=SC2034
# archiso profile for Haven OS. @VARS@ are filled in by build.sh.

iso_name="@OS_ID@"
iso_label="HAVEN_@OS_VERSION_LABEL@"
iso_publisher="@OS_NAME@"
iso_application="@OS_NAME@ live and installer"
iso_version="@OS_VERSION@"
install_dir="haven"
buildmodes=('iso')
# UEFI only — every gaming PC from the last decade boots this way
bootmodes=('uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--long' '-19')
file_permissions=(
  ["/usr/local/bin/haven-settings"]="0:0:755"
  ["/usr/local/bin/haven-welcome"]="0:0:755"
  ["/usr/local/bin/haven-update"]="0:0:755"
  ["/usr/local/bin/haven-run-exe"]="0:0:755"
  ["/usr/local/bin/haven-live-setup"]="0:0:755"
  ["/usr/local/bin/haven-postinstall"]="0:0:755"
)
