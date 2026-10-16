<#
.SYNOPSIS
  Build Haven OS on Windows 10/11 using WSL2 and the official Arch Linux image.

.DESCRIPTION
  1. Checks that WSL2 is installed (installs it if you run as Administrator).
  2. Creates a dedicated Arch Linux WSL instance called "HavenBuild", kept
     separate from any Linux you already use.
  3. Copies this project into the Linux filesystem (much faster than building
     on C:, and avoids Windows line-ending and permission problems).
  4. Runs ./build.sh inside it.
  5. Copies the finished ISO back to the "out" folder next to this project.

.PARAMETER Stage
  all (default) | kernel | aur | iso | clean | remove
  "remove" deletes the HavenBuild WSL instance entirely (frees its disk space).

.PARAMETER Distro
  Name of the WSL instance to use. Default: HavenBuild

.EXAMPLE
  .\scripts\windows\build-windows.ps1
  .\scripts\windows\build-windows.ps1 -Stage iso
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'kernel', 'aur', 'iso', 'clean', 'remove')]
    [string]$Stage = 'all',
    [string]$Distro = 'HavenBuild'
)

# 'Continue', not 'Stop': in Windows PowerShell 5.1, anything wsl.exe writes to
# stderr becomes an error record, and 'Stop' would abort the script on harmless
# messages like "WSL is not installed". Every wsl.exe call checks $LASTEXITCODE.
$ErrorActionPreference = 'Continue'
# Make wsl.exe print UTF-8 instead of UTF-16 so its output can be parsed
$env:WSL_UTF8 = '1'

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutDir      = Join-Path $ProjectRoot 'out'

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg) { Write-Host "==> WARNING: $msg" -ForegroundColor Yellow }
function Stop-Build([string]$msg) {
    Write-Host "==> ERROR: $msg" -ForegroundColor Red
    exit 1
}
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-WslDistros {
    $list = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $list) { return @() }
    return @($list | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
}

Write-Host ''
Write-Host '  Haven OS - Windows build' -ForegroundColor White
Write-Host "  Project: $ProjectRoot"
Write-Host ''

# ---------------------------------------------------------------------------
# 1. Windows + WSL checks
# ---------------------------------------------------------------------------
$build = [Environment]::OSVersion.Version.Build
if ($build -lt 19041) {
    Stop-Build "Windows 10 version 2004 (build 19041) or newer is required. This PC is build $build."
}

$wslExe = Get-Command wsl.exe -ErrorAction SilentlyContinue
$wslReady = $false
if ($wslExe) {
    $null = & wsl.exe --status 2>&1
    $wslReady = ($LASTEXITCODE -eq 0)
}

if (-not $wslReady) {
    Write-Warn 'WSL2 is not installed yet.'
    if (-not (Test-Admin)) {
        Stop-Build 'Right-click build-windows.bat and choose "Run as administrator" once, so WSL2 can be installed.'
    }
    Write-Step 'Installing WSL2 (this needs a restart afterwards)...'
    & wsl.exe --install --no-distribution
    if ($LASTEXITCODE -ne 0) {
        Stop-Build 'WSL install failed. Make sure virtualisation (Intel VT-x / AMD-V / SVM) is enabled in your BIOS/UEFI.'
    }
    Write-Host ''
    Write-Host 'WSL2 installed. RESTART Windows, then run build-windows.bat again.' -ForegroundColor Green
    exit 0
}

if ($Stage -eq 'remove') {
    if ((Get-WslDistros) -contains $Distro) {
        Write-Step "Deleting the $Distro WSL instance and all its build files..."
        & wsl.exe --unregister $Distro
    } else {
        Write-Step "$Distro is not installed - nothing to remove."
    }
    exit 0
}

# ---------------------------------------------------------------------------
# 2. Resources
# ---------------------------------------------------------------------------
$sysDrive = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
$freeGB = [math]::Round($sysDrive.Free / 1GB)
if ($Stage -ne 'clean' -and $freeGB -lt 50) {
    Write-Warn "Only $freeGB GB free on $($env:SystemDrive). A full build needs about 50 GB (the WSL disk lives there)."
    $answer = Read-Host 'Continue anyway? (y/N)'
    if ($answer -notmatch '^[Yy]') { exit 1 }
}

$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$wslConfig = Join-Path $env:USERPROFILE '.wslconfig'
$hasMemSetting = (Test-Path $wslConfig) -and (Select-String -Path $wslConfig -Pattern '^\s*memory\s*=' -Quiet)
if (-not $hasMemSetting -and $ramGB -lt 16) {
    Write-Warn "This PC has $ramGB GB RAM; WSL gets half by default. If the kernel build crashes with 'Killed',"
    Write-Warn "create $wslConfig containing:  [wsl2]  memory=$([math]::Max(6, $ramGB - 4))GB  swap=16GB"
}

# ---------------------------------------------------------------------------
# 3. Dedicated Arch Linux instance
# ---------------------------------------------------------------------------
function Test-NeedsRestart($output) {
    return (($output | Out-String) -match 'reboot|restart|not be effective until')
}
function Stop-ForRestart {
    Write-Host ''
    Write-Host 'Windows has just enabled the virtualisation feature WSL needs.' -ForegroundColor Green
    Write-Host 'RESTART Windows, then run build-windows.bat again to carry on.' -ForegroundColor Green
    exit 0
}

if ((Get-WslDistros) -notcontains $Distro) {
    Write-Step "Creating the '$Distro' Arch Linux WSL instance (one-time download, about 150 MB)..."
    $out = & wsl.exe --install archlinux --name $Distro --no-launch 2>&1
    $out | ForEach-Object { Write-Host $_ }
    if (Test-NeedsRestart $out) { Stop-ForRestart }
    if ($LASTEXITCODE -ne 0 -or (Get-WslDistros) -notcontains $Distro) {
        Write-Warn 'Could not create a named instance (older WSL). Trying "wsl --update" first...'
        $out = & wsl.exe --update 2>&1
        $out | ForEach-Object { Write-Host $_ }
        if (Test-NeedsRestart $out) { Stop-ForRestart }
        $out = & wsl.exe --install archlinux --name $Distro --no-launch 2>&1
        $out | ForEach-Object { Write-Host $_ }
        if (Test-NeedsRestart $out) { Stop-ForRestart }
    }
    if ((Get-WslDistros) -notcontains $Distro) {
        Stop-Build "Could not create '$Distro'. Run 'wsl --update' as administrator, restart, and try again."
    }
}

# Quick sanity check that the instance works
& wsl.exe -d $Distro -u root -- true
if ($LASTEXITCODE -ne 0) { Stop-Build "The '$Distro' WSL instance would not start." }

# ---------------------------------------------------------------------------
# 4. Run the build inside WSL
# ---------------------------------------------------------------------------
# wslpath understands C:/Users/... (forward slashes survive argument passing)
$winPath = $ProjectRoot -replace '\\', '/'
$wslSrc = (& wsl.exe -d $Distro -u root -- wslpath -a "$winPath" | Out-String).Trim()
if (-not $wslSrc) { Stop-Build "Could not translate '$ProjectRoot' to a WSL path." }

Write-Step "Building stage '$Stage' inside WSL ($Distro)..."
if ($Stage -eq 'all' -or $Stage -eq 'kernel') {
    Write-Host '    The kernel compile can take from 30 minutes to a few hours. Leave this window open.'
}
$started = Get-Date

# Strip any Windows line endings from the helper before running it
$inner = "tr -d '\r' < '$wslSrc/scripts/windows/wsl-build.sh' > /tmp/haven-wsl-build.sh && bash /tmp/haven-wsl-build.sh '$Stage' '$wslSrc'"
& wsl.exe -d $Distro -u root -- bash -c $inner
$code = $LASTEXITCODE

$mins = [math]::Round(((Get-Date) - $started).TotalMinutes)
if ($code -ne 0) {
    Stop-Build "Build failed after $mins minutes (exit code $code). Scroll up for the first error."
}

if ($Stage -eq 'clean') {
    Write-Step 'Build files inside WSL removed.'
    exit 0
}

# ---------------------------------------------------------------------------
# 5. Result
# ---------------------------------------------------------------------------
$iso = Get-ChildItem -Path $OutDir -Filter *.iso -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

Write-Host ''
Write-Host "  Done in $mins minutes." -ForegroundColor Green
if ($iso) {
    Write-Host "  ISO: $($iso.FullName)" -ForegroundColor Green
    Write-Host ''
    Write-Host '  Next steps:'
    Write-Host '   - Test it in a VM:   .\scripts\windows\test-in-hyperv.ps1   (Windows Pro/Enterprise, as admin)'
    Write-Host '   - Write it to USB:   Rufus (choose "DD Image mode") or Ventoy'
} elseif ($Stage -eq 'kernel' -or $Stage -eq 'aur') {
    Write-Host '  Packages are built inside WSL. Run build-windows.bat iso to make the ISO.'
}
