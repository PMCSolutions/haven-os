# Haven OS

A desktop operating system with three priorities:

1. **Windows game compatibility.** Steam and Proton come preinstalled, and the custom kernel includes NTSYNC.
2. **Easy to use.** It has a graphical installer, a KDE Plasma desktop that feels familiar to Windows users, and a one-minute welcome wizard.
3. **Privacy.** There is no telemetry, DNS is encrypted, a firewall is on, MAC addresses are randomised, and full-disk encryption is offered at install.

Haven is built on Arch Linux with its own kernel, `linux-haven`.

---

## The Haven kernel

`kernel/` builds `linux-haven` from the official kernel.org source. It is verified with the kernel.org PGP signatures and has these changes:

| Change | Why |
|---|---|
| **NTSYNC** (`/dev/ntsync`) | Kernel implementation of Windows NT synchronisation objects. Wine/Proton use it instead of emulating them, which lowers CPU overhead and reduces stutter in many Windows games. |
| **BORE scheduler** (CachyOS patch) | Prioritises bursty, interactive tasks such as games and input over background work. |
| **1000Hz timer, full preemption** | Lower input latency and steadier frame pacing. |
| **sched-ext** | Lets you swap in BPF schedulers at runtime to experiment. |
| **Hardening** | AppArmor, Landlock, Lockdown, zeroed allocations, randomised kernel stack, restricted dmesg, and legacy attack surface removed. |
| **Controller drivers** | Xbox, PlayStation, Switch and Steam controllers are built in. |

`KERNEL_SERIES="auto"` in `haven.conf` picks the newest stable kernel that has a matching BORE patch. Set a series such as `"6.18"` to pin to a longterm kernel.

## Feels like Windows

- **Taskbar:** the default is a centred taskbar like Windows 11. Haven Welcome can switch to a classic layout with Start on the left, like Windows 10, at any time. Both layouts are in System Settings > Global Theme as "Haven - centred taskbar" and "Haven - classic taskbar".
- **Windows programs:** double-click any `.exe`, `.msi`, `.lnk` or `.bat` to run or install it with Wine. Installed programs appear in the Start menu.
  - **Windows C: drive** in the Start menu opens the programs' files.
  - **Windows Program Settings** changes the Windows version, drives or audio.
  - Right-click a Windows file in Dolphin and choose **Windows program** for more options.
- **Games:** Steam with Proton is the better way to run them. In Steam, choose Games > Add a Non-Steam Game and pick the `.exe`.

| Shortcut | Does |
|---|---|
| Win | Start menu |
| Win+E | File Explorer (Dolphin) |
| Win+R | Run (KRunner) |
| Win+I | Settings |
| Win+D | Show desktop |
| Win+L | Lock |
| Win+Tab | Task view |
| Win+Left/Right | Snap window |
| Win+Up / Win+Down | Maximise / minimise |
| Win+Shift+S | Snip a region |
| Print Screen | Screenshot |
| Win+V | Clipboard history |
| Win+. | Emoji |
| Ctrl+Shift+Esc | Task manager (System Monitor) |
| Alt+Tab / Alt+F4 | Switch / close windows |

## Privacy defaults

| Area | Default |
|---|---|
| Telemetry | None. Firefox telemetry, studies and sponsored content are switched off by policy. KDE feedback is opt-in, and no crash reporter is installed. |
| DNS | DNS-over-TLS through Quad9, with no fallback to Google. Changeable in Haven Welcome. |
| Wi-Fi/Ethernet | Each network sees a different MAC address. The hostname isn't sent to DHCP servers, and IPv6 privacy addresses are on. |
| Connectivity checks | Off. |
| Firewall | firewalld blocks all incoming connections. Steam Remote Play is opt-in. |
| Disk | The installer offers LUKS2 full-disk encryption. |
| Logs | Crash dumps are never stored. System logs are deleted after two weeks. |
| Max security mode | Optional kernel lockdown. NVIDIA's driver can't load in this mode, and Haven Welcome warns about it. |

**Being honest about Steam:** Steam and most game launchers are proprietary and have their own data collection. Haven can't change that. It keeps the rest of the system clean and leaves you in control.

## What you need

- **To use it:** a 64-bit UEFI PC, 4 GB RAM (8+ recommended), 40 GB disk.
- **GPUs:** AMD and Intel work out of the box. NVIDIA GTX 16xx / RTX 20 series and newer use the open NVIDIA driver; older NVIDIA cards fall back to nouveau.
- **To build it:** about 40 GB free disk, 16 GB RAM recommended, plus Arch Linux or any Linux/WSL2 with Docker or Podman.

---

## Building

```bash
./build.sh            # kernel + installer packages + ISO   → out/haven-*.iso
./build.sh kernel     # just the kernel packages            → out/repo/
./build.sh iso        # rebuild the ISO from existing packages
./build.sh clean
```

On a machine that isn't running Arch, `build.sh` automatically runs inside an Arch container. Compiling the kernel takes from about 30 minutes to a few hours, depending on the CPU.

### Building on Windows 10/11

Double-click **`build-windows.bat`**. The finished ISO appears in the `out` folder.

Behind the scenes, it uses WSL2 with the official Arch Linux image:

1. **First time only:** if WSL2 isn't installed, it asks you to run the `.bat` as administrator, installs WSL2, then asks you to restart.
2. It creates a separate Arch instance called **HavenBuild**, so it won't touch any Linux you already have.
3. It copies the project into Linux, fixes Windows line endings and file permissions, then runs `build.sh`.
4. It copies the ISO back to `out\`.

Other stages: `build-windows.bat iso`, `build-windows.bat kernel` and `build-windows.bat clean`. To delete the whole build instance and free its disk space, run `scripts\windows\build-windows.ps1 -Stage remove`.

**Needs:** Windows 10 2004+ or Windows 11, virtualisation enabled in the BIOS, about 50 GB free on C:, and 16 GB RAM recommended. With less RAM, the script tells you what to put in `%USERPROFILE%\.wslconfig`.

**Testing on Windows:** run `scripts\windows\test-in-hyperv.ps1` from an administrator PowerShell. It makes a UEFI Hyper-V VM with Secure Boot off and boots the newest ISO. On Windows Home, use VirtualBox with EFI enabled. Write the ISO to USB with Rufus (DD image mode) or Ventoy.

> If you clone the project with Git on Windows, the included `.gitattributes` keeps Linux files with LF endings. The build fixes them anyway if an editor changes them.

Write the ISO to a USB stick with Ventoy, balenaEtcher or Rufus (DD mode), then boot from it.

### Building on GitHub (no local setup needed)

The repository lives at https://github.com/PMCSolutions/haven-os. A build starts in either of two ways:

- **To release a version:** bump `OS_VERSION` in `haven.conf`, commit, then run `git tag v0.1.4 && git push --tags`.
- **To test without releasing:** go to the **Actions** tab, choose **Build Haven OS**, then **Run workflow**.

The workflow runs three jobs:

| Job | Time | What it does |
|---|---|---|
| `check` | ~5 min | Confirms every ISO package exists in Arch, so mistakes fail fast |
| `kernel` | ~2-3 h | Compiles `linux-haven` on the runner's large spare disk |
| `iso` | ~1 h | Builds the installer and the ISO |

**Getting the ISO:**
- **Tagged builds** create a **Release** with the ISO split into parts under 2 GB (GitHub's file limit). The release notes give the exact command to join them on Windows (`copy /b …`) or Linux.
- **Every build** also attaches the whole ISO as an **artifact** on the run's page, kept for 30 days. You need to be signed in to GitHub to download it.

Tagged builds also publish the `repo` release. Installed systems get kernel updates from it, using the address set in `HAVEN_REPO_URL`.

### Signing (do this before giving Haven to anyone else)

Until you set up signing, installed systems accept unsigned kernel updates from the repo release. That's fine for testing, but not for anyone else's PC.

1. `gpg --full-generate-key` creates a signing key.
2. Put the key ID in `GPG_SIGN_KEY` in `haven.conf`.
3. For CI, add `GPG_PRIVATE_KEY` (from `gpg --armor --export-secret-keys`) and `GPG_SIGN_KEY` as repository secrets.

Installed systems then refuse kernel updates that aren't signed by you.

---

## Installing

**From the ISO (recommended):** boot the USB and try the live desktop. When you're ready, click **Install Haven OS**. Tick **Encrypt system** on the disk page.

**Onto an existing Arch install:**
```bash
sudo ./scripts/install.sh               # uses HAVEN_REPO_URL
sudo ./scripts/install.sh --local-repo  # uses packages you built in out/repo
```
This backs up every file it changes to `/var/backups/haven/`.

## Updating

Day-to-day updates come through **Discover** or `haven-update`. That runs pacman, updates Flatpak apps and the Haven kernel, and re-applies your settings.

For a new Haven release, such as new config defaults or packages, extract the new project zip and run:
```bash
sudo ./scripts/patch.sh --dry-run   # see what will change
sudo ./scripts/patch.sh             # apply it
```
`patch.sh` backs up changed files, installs new packages, syncs config and runs any migrations in `scripts/migrations/`. It then re-applies your DNS, firewall and security choices.

### Releasing an update (for you as maintainer)
1. Bump `OS_VERSION` in `haven.conf`.
2. Make your changes in `rootfs/`, `iso/packages.x86_64` or `kernel/`.
3. If existing installs need a one-off change, add `scripts/migrations/<version>.sh`.
4. Tag and push. CI builds the new kernel/repo and ISO, and users run `patch.sh` or `haven-update`.

---

## Project layout

```
haven.conf                 name, version, kernel series, repo URL, signing key
build.sh                   builds everything (Linux)
build-windows.bat          builds everything from Windows (WSL2)
kernel/
  PKGBUILD                 linux-haven + linux-haven-headers packages
  haven.config             kernel config changes (NTSYNC, BORE, hardening…)
  fetch-kernel.sh          picks the kernel version + BORE patch
rootfs/                    Haven system files, shared by ISO, install.sh and patch.sh
  etc/…                    privacy, firewall, DNS, sysctl, NTSYNC, zram
  usr/local/bin/
    haven-welcome          first-login wizard
    haven-settings         applies DNS / firewall / security choices
    haven-update           one-command system update
    haven-run-exe          runs .exe/.msi files with Wine (double-click handler)
  usr/share/plasma/look-and-feel/   Windows 11 / Windows 10-style taskbar layouts
  etc/xdg/kglobalshortcutsrc        Windows keyboard shortcuts
iso/                       archiso profile: packages, boot menu, live session,
  airootfs/etc/calamares/  graphical installer config + branding
scripts/
  install.sh               installer script (existing Arch → Haven)
  patch.sh                 patch script (apply a new Haven release)
  lib.sh                   shared helpers
  migrations/              per-version one-off changes
  windows/
    build-windows.ps1      WSL2 setup + build driver
    wsl-build.sh           runs inside WSL: sync, fix line endings, build
    test-in-hyperv.ps1     boots the ISO in a Hyper-V test VM
.github/workflows/build.yml
```

## Useful commands on an installed system

```bash
haven-settings status                  # DNS, firewall, kernel, NTSYNC check
sudo haven-settings dns mullvad        # quad9 | mullvad | cloudflare | network
sudo haven-settings remote-play on     # allow Steam Remote Play / LAN transfers
sudo haven-settings max-security on    # kernel lockdown (not with NVIDIA)
haven-update                           # update everything
```

## Known limitations

- Games whose anti-cheat blocks Linux (for example Valorant, Fortnite, some Call of Duty titles) won't run on any Linux system. Check https://areweanticheatyet.com before switching.
- The kernel has not been tested on real hardware until you build it. The first build is the real test, so try the ISO in a VM (UEFI mode) before a real PC.
- Secure Boot needs extra setup with `sbctl`. Disable Secure Boot for now, or see the Arch wiki's Secure Boot page.
