#!/usr/bin/env bash
# Resolve which kernel version to build and stamp it into the PKGBUILD.
#
#  KERNEL_SERIES=auto  -> the exact version CachyOS currently ships in linux-cachyos.
#                         Its BORE scheduler patch is made against that version, so
#                         it applies cleanly. Falls back to the newest kernel.org
#                         stable release that has a BORE patch.
#  KERNEL_SERIES=6.18  -> that series: CachyOS's LTS version if it matches,
#                         otherwise the newest kernel.org release in the series.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../haven.conf
source "$here/../haven.conf"

CACHY_RAW="https://raw.githubusercontent.com/CachyOS"

bore_exists() {
  curl -fsIL -o /dev/null "$CACHY_RAW/kernel-patches/master/$1/sched/0001-bore-cachy.patch"
}

# Print the version a CachyOS kernel PKGBUILD builds, e.g. 7.2.9 (or 7.3 for a .0 release)
cachy_version() {
  local pb major minor
  pb="$(curl -fsSL "$CACHY_RAW/linux-cachyos/master/$1/PKGBUILD")" || return 1
  major="$(sed -n 's/^_major=\([0-9]\+\.[0-9]\+\).*/\1/p' <<<"$pb" | head -n1)"
  minor="$(sed -n 's/^_minor=\([0-9]\+\).*/\1/p' <<<"$pb" | head -n1)"
  [[ -n $major && -n $minor ]] || return 1
  if [[ $minor == 0 ]]; then echo "$major"; else echo "$major.$minor"; fi
}

chosen=""
source_note=""

# 1. Ask CachyOS which version its BORE patches currently target
for pkg in linux-cachyos linux-cachyos-lts; do
  ver="$(cachy_version "$pkg" || true)"
  [[ -n $ver ]] || continue
  series="$(cut -d. -f1-2 <<<"$ver")"
  if [[ $KERNEL_SERIES != auto && $series != "$KERNEL_SERIES" ]]; then
    continue
  fi
  if bore_exists "$series"; then
    chosen="$ver"
    source_note="matches CachyOS $pkg"
    break
  fi
done

# 2. Fallback: newest kernel.org release with a BORE patch for its series
if [[ -z $chosen ]]; then
  releases_json="$(curl -fsSL https://www.kernel.org/releases.json)"
  mapfile -t candidates < <(
    jq -r '.releases[]
           | select(.moniker == "stable" or .moniker == "longterm")
           | select(.iseol | not)
           | .version' <<<"$releases_json"
  )
  for ver in "${candidates[@]}"; do
    series="$(cut -d. -f1-2 <<<"$ver")"
    if [[ $KERNEL_SERIES != auto && $series != "$KERNEL_SERIES" ]]; then
      continue
    fi
    if bore_exists "$series"; then
      chosen="$ver"
      source_note="newest kernel.org release (BORE patch may need the fallback)"
      break
    fi
    echo "Skipping $ver: no BORE patch published for $series yet"
  done
fi

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

echo "Kernel: linux $chosen (series $series) with BORE - $source_note"
