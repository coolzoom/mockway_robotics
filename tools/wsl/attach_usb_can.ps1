#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
  Attach USB serial / USB-CAN device to WSL2 (Ubuntu-24.04)
#>
param(
    [string]$Distro = "Ubuntu-24.04",
    [string]$BusId = "",
    [switch]$ListOnly,
    [switch]$DetachAll
)

$ErrorActionPreference = "Stop"

function Ensure-Usbipd {
    if (Get-Command usbipd -ErrorAction SilentlyContinue) { return }
    Write-Host "[usb] Installing usbipd-win..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id dorssel.usbipd-win -e --accept-source-agreements --accept-package-agreements
    } else {
        throw "usbipd not found. Run as admin: winget install dorssel.usbipd-win"
    }
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath"
}

Ensure-Usbipd

Write-Host ""
Write-Host "=== USB devices (usbipd list) ==="
usbipd list
Write-Host ""

if ($ListOnly) { exit 0 }

if ($DetachAll) {
    Write-Host "[usb] Detaching all attached devices..."
    usbipd list | Select-String "Attached" | ForEach-Object {
        if ($_ -match '(\d-\d+)') {
            $id = $Matches[1]
            Write-Host "  detach $id"
            usbipd detach --busid $id 2>$null
        }
    }
    exit 0
}

if (-not $BusId) {
    $lines = usbipd list | Out-String
    $candidates = @(
        'USB-CAN', 'CAN', 'CH340', 'CH341', 'CP210', 'FTDI', 'WCH', 'Serial',
        'USB Serial', 'USB-SERIAL', 'Silicon Labs', 'Prolific'
    )
    foreach ($line in ($lines -split "`n")) {
        if ($line -notmatch '^\s*(\d-\d+)\s') { continue }
        $id = $Matches[1]
        foreach ($kw in $candidates) {
            if ($line -match [regex]::Escape($kw)) {
                $BusId = $id
                Write-Host "[usb] Auto-selected: $BusId  ($line)"
                break
            }
        }
        if ($BusId) { break }
    }
}

if (-not $BusId) {
    Write-Host "No USB-CAN device auto-detected. Specify BusId, e.g.:"
    Write-Host "  powershell -File tools\wsl\attach_usb_can.ps1 -BusId 2-3"
    Write-Host ""
    Write-Host "List only:"
    Write-Host "  powershell -File tools\wsl\attach_usb_can.ps1 -ListOnly"
    exit 1
}

Write-Host "[usb] bind $BusId ..."
usbipd bind --busid $BusId 2>$null

Write-Host "[usb] attach to WSL ($Distro) ..."
usbipd attach --wsl --busid $BusId --distribution $Distro

Start-Sleep -Seconds 2

Write-Host ""
Write-Host "=== Serial devices in WSL ==="
wsl -d $Distro -- bash -lc "ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo '(no ttyUSB/ttyACM yet)'"

Write-Host ""
Write-Host "Real robot CAN port in xacro is usually /dev/ttyUSB0"
Write-Host "If permission denied in WSL: sudo chmod 666 /dev/ttyUSB0"
Write-Host "Or: sudo usermod -aG dialout `$USER  (restart WSL)"
