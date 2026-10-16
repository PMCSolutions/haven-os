# Changelog

## 0.1.4: Build on GitHub
- The GitHub Actions build now fits GitHub's free runners. It's split into `check`, `kernel` and `iso` jobs, each with its own 6-hour limit, and builds on the runner's large spare disk. The ISO is split into parts under 2 GB for the release, and the full ISO is also kept as an artifact.
- New `./build.sh check` stage: confirms every package in the ISO list exists before the long kernel build.
- New `./build.sh installer-iso` stage: builds the installer packages and the ISO from kernel packages built in an earlier job.
- The build turns on [multilib] in the build container, and the CI signing key is imported inside the container.
- Package list updated for current Arch: `p7zip` is now `7zip`, and `lib32-openal`, `lib32-sdl2-compat` and `lib32-gst-plugins-base-libs` are removed (no longer in Arch; Steam and Proton bundle them).
- Removed `game-devices-udev` from the ISO. It's AUR-only, and Steam already provides controller udev rules.
- **Kernel version:** `KERNEL_SERIES=auto` now builds the exact version CachyOS ships, so the BORE patch applies cleanly. If BORE ever doesn't apply, the build continues with the standard scheduler and shows a warning.
- **Base kernel config:** now taken from Arch's `linux-headers` package instead of GitLab, which blocks automated downloads.
- CI shows the last 40 lines of a failing build command on the run page, and kernel.org signing keys fall back to a keyserver.
- The project home is now https://github.com/PMCSolutions/haven-os, and `HAVEN_REPO_URL` points to its `repo` release.

## 0.1.3: Windows-style desktop
- **Taskbar:** a centred taskbar like Windows 11 is now the default. A classic layout with Start on the left, like Windows 10, can be chosen in Haven Welcome. Both have a Haven Start button, pinned File Explorer (Dolphin), Firefox, Steam, Discover and Settings, a tray, and a clock with the date. The far right corner shows the desktop.
- **Windows keyboard shortcuts:**
  - Win+E: files
  - Win+R: run
  - Win+I: settings
  - Win+D: show desktop
  - Win+L: lock
  - Win+Tab: task view
  - Win+Up/Down: maximise and minimise
  - Win+Shift+S: snip
  - Win+V: clipboard
  - Win+.: emoji
  - Ctrl+Shift+Esc: task manager
- **Windows programs:**
  - Double-click a `.exe`, `.msi`, `.lnk` or `.bat` file to run or install it with Wine. The first run explains what happens and recommends Steam/Proton for games.
  - Right-clicking a Windows file in Dolphin shows a **Windows program** menu.
  - The Start menu has new **Windows C: drive** and **Windows Program Settings** entries.
- Window buttons sit on the right, and dragging a window to the screen edge snaps it, like Windows.
- Existing installs: `patch.sh` adds all of this, but keeps each user's current taskbar. Open **Haven Welcome** to switch.
- **Windows build fix:** when WSL turns on the Windows virtualisation feature for the first time, `build-windows.bat` now says to restart. Before, it reported a failure.

## 0.1.2
- Fixed: `build-windows.bat` stopped with "The Windows Subsystem for Linux is not installed" instead of offering to install WSL2. This happened in Windows PowerShell 5.1, where messages from wsl.exe were treated as fatal errors.

## 0.1.1
- **Build from Windows:** `build-windows.bat` builds the full ISO on Windows 10/11 through WSL2 and a dedicated Arch Linux instance called HavenBuild.
- `scripts/windows/test-in-hyperv.ps1` boots the ISO in a Hyper-V test VM.
- `.gitattributes` keeps Linux scripts with LF line endings on Windows checkouts.
- No changes to installed systems. `patch.sh` only updates the version number.

## 0.1.0
- First release: the `linux-haven` kernel (NTSYNC, BORE, 1000Hz, hardening), KDE Plasma, Steam/Proton, privacy defaults, the Calamares installer, `install.sh` and `patch.sh`.
