#!/usr/bin/env bash
# Resolve which kernel version to build and stamp it into the PKGBUILD.
#
#  KERNEL_SERIES=auto  -> newest stable/longterm release that has a BORE patch
#  KERNEL_SERIES=6.18  -> newest release in that series
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../haven.conf
source "$here/../haven.conf"

releases_json="$(curl -fsSL https://www.kernel.org/releases.json)"

bore_exists() {
  curl -fsIL -o /dev/null \
    "https://raw.githubusercontent.com/CachyOS/kernel-patches/master/$1/sched/0001-bore-cachy.patch"
}

mapfile -t candidates < <(
  jq -r '.releases[]
         | select(.moniker == "stable" or .moniker == "longterm")
         | select(.iseol | not)
         | .version' <<<"$releases_json"
)

chosen=""
for ver in "${candidates[@]}"; do
  series="$(cut -d. -f1-2 <<<"$ver")"
  if [[ $KERNEL_SERIES != auto && $series != "$KERNEL_SERIES" ]]; then
    continue
  fi
  if bore_exists "$series"; then
    chosen="$ver"
    break
  fi
  echo "Skipping $ver: no BORE patch published for $series yet"
done

if [[ -z $chosen ]]; then
  echo "ERROR: no kernel release matched KERNEL_SERIES=$KERNEL_SERIES with a BORE patch" >&2
  exit 1
fi

series="$(cut -d. -f1-2 <<<"$chosen")"
# Mainline x.y releases have no patch level; makepkg needs x.y.0
pkgver="$chosen"
[[ $pkgver =~ ^[0-9]+\.[0-9]+$ ]] && pkgver="$pkgver.0"

sed -i \
  -e "s/^pkgver=.*/pkgver=$pkgver/" \
  -e "s/^_series=.*/_series=$series/" \
  "$here/PKGBUILD"

echo "Kernel: linux $chosen (series $series) with BORE"
