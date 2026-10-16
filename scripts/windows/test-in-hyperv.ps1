<#
.SYNOPSIS
  Boot the newest Haven OS ISO in a Hyper-V test VM.

.DESCRIPTION
  Creates (or recreates) a Generation 2 UEFI VM called "Haven-Test" with the
  ISO attached and Secure Boot off, then opens its console window.
  Needs Windows 10/11 Pro, Enterprise or Education with Hyper-V enabled,
  and must be run as Administrator.

  Note: games won't be fast in Hyper-V (no GPU passthrough). Use the VM to
  check that Haven boots, installs and that the desktop works.

.PARAMETER Iso
  Path to the ISO. Default: newest .iso in the project's out folder.

.PARAMETER Remove
  Delete the test VM and its virtual disk.

.EXAMPLE
  .\scripts\windows\test-in-hyperv.ps1
  .\scripts\windows\test-in-hyperv.ps1 -Remove
#>
[CmdletBinding()]
param(
    [string]$Iso,
    [string]$VMName = 'Haven-Test',
    [int]$MemoryGB = 8,
    [int]$Cpus = 4,
    [int]$DiskGB = 64,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Stop-Script([string]$msg) { Write-Host "==> ERROR: $msg" -ForegroundColor Red; exit 1 }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Stop-Script 'Run PowerShell as Administrator.' }

if (-not (Get-Command New-VM -ErrorAction SilentlyContinue)) {
    Stop-Script ('Hyper-V is not enabled. Enable it with (then restart):' + [Environment]::NewLine +
        '  Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All' + [Environment]::NewLine +
        'Windows Home does not include Hyper-V - use VirtualBox instead (enable EFI in the VM settings).')
}

$vmDir = Join-Path $ProjectRoot 'out\vm'
$vhd   = Join-Path $vmDir "$VMName.vhdx"

# Remove any previous test VM
$existing = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Step "Removing previous $VMName VM..."
    if ($existing.State -ne 'Off') { Stop-VM -Name $VMName -TurnOff -Force }
    Remove-VM -Name $VMName -Force
}
if (Test-Path $vhd) { Remove-Item $vhd -Force }

if ($Remove) {
    Write-Step "$VMName removed."
    exit 0
}

if (-not $Iso) {
    $latest = Get-ChildItem -Path (Join-Path $ProjectRoot 'out') -Filter *.iso -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { Stop-Script 'No ISO found in the out folder. Run build-windows.bat first.' }
    $Iso = $latest.FullName
}
if (-not (Test-Path $Iso)) { Stop-Script "ISO not found: $Iso" }

# Prefer the built-in "Default Switch" (NAT, works on Wi-Fi), else any switch
$switch = Get-VMSwitch -Name 'Default Switch' -ErrorAction SilentlyContinue
if (-not $switch) { $switch = Get-VMSwitch | Select-Object -First 1 }

Write-Step "Creating $VMName ($MemoryGB GB RAM, $Cpus CPUs, $DiskGB GB disk)..."
New-Item -ItemType Directory -Path $vmDir -Force | Out-Null

$vmArgs = @{
    Name               = $VMName
    Generation         = 2
    MemoryStartupBytes = [int64]$MemoryGB * 1GB
    NewVHDPath         = $vhd
    NewVHDSizeBytes    = [int64]$DiskGB * 1GB
    Path               = $vmDir
}
if ($switch) { $vmArgs.SwitchName = $switch.Name }
New-VM @vmArgs | Out-Null

Set-VM -Name $VMName -ProcessorCount $Cpus -StaticMemory -CheckpointType Disabled -AutomaticStopAction TurnOff
$dvd = Add-VMDvdDrive -VMName $VMName -Path $Iso -Passthru
# Haven's kernel is not Secure Boot signed (yet)
Set-VMFirmware -VMName $VMName -EnableSecureBoot Off -FirstBootDevice $dvd
# Higher console resolution than the 1024x768 default
Set-VMVideo -VMName $VMName -HorizontalResolution 1920 -VerticalResolution 1080 -ResolutionType Single -ErrorAction SilentlyContinue

Write-Step 'Starting VM...'
Start-VM -Name $VMName
Start-Process vmconnect.exe -ArgumentList 'localhost', $VMName

Write-Host ''
Write-Host "  $VMName is booting from $([IO.Path]::GetFileName($Iso))" -ForegroundColor Green
Write-Host '  - Choose "Haven OS (safe graphics)" from the boot menu if the screen stays black.'
Write-Host '  - Remove it later with:  .\scripts\windows\test-in-hyperv.ps1 -Remove'
