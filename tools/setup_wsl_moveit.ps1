#Requires -Version 5.1
<#
.SYNOPSIS
  Mockway: WSL2 Ubuntu 24.04 + ROS2 Jazzy + MoveIt2 + usbipd-win

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\setup_wsl_moveit.ps1
  powershell -ExecutionPolicy Bypass -File tools\setup_wsl_moveit.ps1 -SkipWslInstall
  powershell -ExecutionPolicy Bypass -File tools\setup_wsl_moveit.ps1 -UsbOnly
#>
param(
    [switch]$SkipWslInstall,
    [switch]$SkipMoveItSetup,
    [switch]$SkipUsbipd,
    [switch]$UsbOnly,
    [switch]$ListUsb,
    [string]$Distro = "Ubuntu-24.04"
)

$ErrorActionPreference = "Stop"
$Script:ExitRebootRequired = 301
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$WslScript = Join-Path $ScriptDir "wsl\setup_moveit_jazzy.sh"
$AttachScript = Join-Path $ScriptDir "wsl\attach_usb_can.ps1"
$LogFile = Join-Path $env:TEMP "mockway_wsl_setup.log"
Start-Transcript -Path $LogFile -Append -ErrorAction SilentlyContinue | Out-Null

function Write-Step($msg) { Write-Host "`n[mockway] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[mockway] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[mockway] $msg" -ForegroundColor Yellow }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Admin {
    if (-not (Test-Admin)) {
        throw "Administrator required. Right-click tools\setup_wsl_moveit.bat -> Run as administrator"
    }
}

function Convert-ToWslPath([string]$WinPath) {
    $full = (Resolve-Path $WinPath).Path
    if ($full -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLower()
        $rest = $Matches[2] -replace '\\', '/'
        return "/mnt/$drive/$rest"
    }
    throw "Cannot convert path to WSL: $WinPath"
}

function Invoke-WslText {
    param([string[]]$Arguments)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = ($Arguments -join ' ')
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode
    $psi.StandardErrorEncoding = [System.Text.Encoding]::Unicode
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    return @{
        ExitCode = $proc.ExitCode
        Output   = ($stdout + $stderr).Trim()
    }
}

function Get-WslDistroList {
    $result = Invoke-WslText @("-l", "-q")
    if ($result.ExitCode -ne 0) { return @() }
    $names = @()
    foreach ($line in ($result.Output -split "`r?`n")) {
        $name = ($line -replace '^\*?\s*', '').Trim()
        if ($name) { $names += $name }
    }
    return $names
}

function Test-PendingReboot {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($key in $keys) {
        if (Test-Path $key) { return $true }
    }
    return $false
}

function Test-WslReady {
    $status = Invoke-WslText @("--status")
    $out = $status.Output

    if ($out -match '(?i)enablevirtualization|aka\.ms/enablevirtualization') {
        return @{ Ready = $false; Issue = 'bios'; Detail = $out }
    }

    $ver = Invoke-WslText @("--version")
    if ($ver.ExitCode -eq 0 -and $ver.Output -match '(?i)WSL') {
        if ($out -match '(?i)no-distribution|--install --no-distribution') {
            return @{ Ready = $false; Issue = 'kernel'; Detail = $out }
        }
        return @{ Ready = $true }
    }

    if ($out -match '(?i)no-distribution|--install --no-distribution') {
        return @{ Ready = $false; Issue = 'kernel'; Detail = $out }
    }

    return @{ Ready = $false; Issue = 'unknown'; Detail = $out }
}

function Initialize-WslEngine {
    Write-Host "  Installing/updating WSL kernel..."
    $r = Invoke-WslText @("--install", "--no-distribution")
    if ($r.Output) {
        foreach ($line in ($r.Output -split "`r?`n")) {
            if ($line.Trim()) { Write-Host "  $line" }
        }
    }
    wsl --update 2>&1 | ForEach-Object { Write-Host "  $_" }
    wsl --set-default-version 2 2>$null
}

function Show-WslHypervisorHelp {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " WSL error 0x80370114: Hypervisor is not running" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " Common causes:"
    Write-Host "   - Virtual Machine Platform not installed correctly"
    Write-Host "   - vmcompute.exe / vmcompute service missing"
    Write-Host "   - CPU virtualization (VT-x/AMD-V) disabled in BIOS"
    Write-Host ""
    Write-Host " Fix (run as Administrator):"
    Write-Host "   tools\wsl\fix_wsl_hypervisor.bat"
    Write-Host ""
    Write-Host " Or manually enable in Windows Features:"
    Write-Host "   [x] Windows Subsystem for Linux"
    Write-Host "   [x] Virtual Machine Platform"
    Write-Host "   [x] Windows Hypervisor Platform"
    Write-Host " Then reboot and run:"
    Write-Host "   bcdedit /set hypervisorlaunchtype Auto"
    Write-Host "   wsl --install -d Ubuntu-24.04"
    Write-Host " BIOS virtualization: https://aka.ms/enablevirtualization"
    Write-Host "============================================================"
}

function Test-WslHypervisorStack {
    $vmcomputePath = Join-Path $env:SystemRoot "System32\vmcompute.exe"
    if (-not (Test-Path $vmcomputePath)) {
        return @{ Ok = $false; Reason = "vmcompute.exe missing" }
    }
    $svc = Get-Service vmcompute -ErrorAction SilentlyContinue
    if (-not $svc) {
        return @{ Ok = $false; Reason = "vmcompute service not registered" }
    }
    return @{ Ok = $true }
}

function Repair-WslHypervisorStack {
    $fixScript = Join-Path $ScriptDir "wsl\fix_wsl_hypervisor.ps1"
    if (Test-Path $fixScript) {
        Write-Warn "Running hypervisor repair..."
        & $fixScript
        if ($LASTEXITCODE -ne 0) { throw "Hypervisor repair failed" }
    }
    $check = Test-WslHypervisorStack
    if (-not $check.Ok) {
        Show-WslHypervisorHelp
        throw "WSL hypervisor not ready: $($check.Reason)"
    }
}

function Request-WindowsReboot {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host " WSL features are enabled. A Windows reboot is REQUIRED." -ForegroundColor Yellow
    Write-Host " Ubuntu cannot install until you reboot." -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Yellow
    Write-Host "  1. Reboot this PC"
    Write-Host "  2. Run again: tools\setup_wsl_moveit.bat"
    Write-Host ""
    $answer = Read-Host "Reboot now? [Y/N] (Y = reboot in 30 seconds)"
    if ($answer -match '^[Yy]') {
        Write-Host "Rebooting in 30 seconds... (run shutdown /a to cancel)"
        shutdown.exe /r /t 30 /c "Mockway WSL setup requires a reboot"
    }
    exit $Script:ExitRebootRequired
}

function Get-WslDistroName {
    param([string]$Preferred)
    $names = Get-WslDistroList
    if ($names.Count -eq 0) { return $null }
    foreach ($candidate in @($Preferred, "Ubuntu-24.04", "Ubuntu")) {
        foreach ($name in $names) {
            if ($name -ieq $candidate) { return $name }
        }
    }
    foreach ($name in $names) {
        if ($name -match '(?i)ubuntu') { return $name }
    }
    return $null
}

function Enable-WslFeatures {
    Write-Step "Enabling WSL and Virtual Machine Platform..."
    $needsReboot = $false
    $allEnabled = $true
    $features = @(
        "Microsoft-Windows-Subsystem-Linux",
        "VirtualMachinePlatform",
        "HypervisorPlatform"
    )
    foreach ($f in $features) {
        $feat = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction SilentlyContinue
        if (-not $feat -or $feat.State -ne "Enabled") {
            $allEnabled = $false
            Write-Host "  Enabling $f ..."
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -All
            if ($result.RestartNeeded) { $needsReboot = $true }
        }
    }

    if ($needsReboot) {
        Write-Warn "WSL features were just enabled; reboot is required."
        Request-WindowsReboot
    }

    if ($allEnabled) {
        Write-Ok "WSL features already enabled"
    }

    Initialize-WslEngine

    $hypervisor = Test-WslHypervisorStack
    if (-not $hypervisor.Ok) {
        Write-Warn "Hypervisor stack issue: $($hypervisor.Reason)"
        Repair-WslHypervisorStack
    }

    $ready = Test-WslReady
    if (-not $ready.Ready) {
        if ($ready.Issue -eq 'bios') {
            throw "CPU virtualization is disabled. Enable Intel VT-x / AMD-V in BIOS, then run this script again. See https://aka.ms/enablevirtualization"
        }
        Write-Warn "WSL engine may not be fully ready; continuing with Ubuntu install..."
        if ($ready.Detail) {
            foreach ($line in ($ready.Detail -split "`r?`n")) {
                if ($line.Trim()) { Write-Host "  $line" }
            }
        }
    } else {
        Write-Ok "WSL engine is ready"
    }

    if (Test-PendingReboot) {
        Write-Warn "Windows Update has a pending reboot (unrelated to WSL). You can ignore this if install proceeds."
    }
}

function Wait-ForWslDistro {
    param(
        [string]$Preferred,
        [int]$TimeoutSec = 900,
        [int]$IntervalSec = 10
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $lastMsg = 0
    while ((Get-Date) -lt $deadline) {
        $found = Get-WslDistroName $Preferred
        if ($found) { return $found }
        $elapsed = [int]($TimeoutSec - ($deadline - (Get-Date)).TotalSeconds)
        if ($elapsed -ge ($lastMsg + 30)) {
            Write-Host "  Still waiting for distro registration... (${elapsed}s / ${TimeoutSec}s)"
            $lastMsg = $elapsed
        }
        Start-Sleep -Seconds $IntervalSec
    }
    return $null
}

function Install-Ubuntu2404 {
    Write-Step "Installing WSL distro Ubuntu-24.04..."
    $existing = Get-WslDistroName $Distro
    if ($existing) {
        Write-Ok "Already installed: $existing"
        return $existing
    }

    $status = Invoke-WslText @("--status")
    if ($status.Output -match '(?i)enablevirtualization|aka\.ms/enablevirtualization') {
        throw "CPU virtualization is disabled. Enable Intel VT-x / AMD-V in BIOS: https://aka.ms/enablevirtualization"
    }

    Write-Host "  Updating WSL kernel..."
    wsl --update 2>&1 | ForEach-Object { Write-Host "  $_" }

    Write-Host "  Downloading Ubuntu 24.04 (may take 5-15 minutes on first run)..."
    $install = Invoke-WslText @("--install", "-d", "Ubuntu-24.04", "--no-launch")
    if ($install.Output) {
        foreach ($line in ($install.Output -split "`r?`n")) {
            if ($line.Trim()) { Write-Host "  $line" }
        }
    }

    if ($install.Output -match '80370114') {
        Show-WslHypervisorHelp
        throw "WSL hypervisor error 0x80370114"
    }

    if ($install.ExitCode -ne 0) {
        Write-Warn "wsl --install returned exit code $($install.ExitCode), trying winget..."
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id Canonical.Ubuntu.2404 -e --accept-source-agreements --accept-package-agreements
        }
    }

    $existing = Wait-ForWslDistro -Preferred $Distro -TimeoutSec 900 -IntervalSec 10
    if (-not $existing) {
        $installed = Get-WslDistroList
        if ($installed.Count -gt 0) {
            Write-Warn "Ubuntu-24.04 not found, but other distros exist: $($installed -join ', ')"
            $existing = Get-WslDistroName $Distro
        }
    }
    if (-not $existing) {
        Write-Warn "Could not detect Ubuntu-24.04."
        Write-Host "  Run manually in Admin PowerShell:"
        Write-Host "    wsl --install -d Ubuntu-24.04"
        Write-Host "  After Ubuntu user setup, run:"
        Write-Host "    tools\setup_wsl_moveit.bat -SkipWslInstall"
        throw "Ubuntu-24.04 not found after install attempt"
    }
    Write-Ok "Installed: $existing"
    return $existing
}

function Initialize-UbuntuUser {
    param([string]$Name)
    Write-Step "Checking Ubuntu first-time setup..."
    $test = wsl -d $Name -- bash -lc "echo wsl_ok" 2>&1
    if ($LASTEXITCODE -ne 0 -or $test -notmatch "wsl_ok") {
        Write-Warn "Opening Ubuntu to finish user setup (username/password)..."
        Start-Process wsl.exe -ArgumentList "-d", $Name
        Read-Host "Press Enter after Ubuntu user setup is complete"
    }
}

function Install-MoveItInsideWsl {
    param([string]$Name, [string]$RepoWsl)
    Write-Step "Installing ROS2 Jazzy + MoveIt2 inside WSL..."
    if (-not (Test-Path $WslScript)) { throw "Missing script: $WslScript" }

    $bashPath = Convert-ToWslPath $WslScript
    $envPrefix = "MOCKWAY_REPO_WSL='$RepoWsl'"
    wsl -d $Name -- bash -lc "$envPrefix bash '$bashPath'"
    if ($LASTEXITCODE -ne 0) { throw "WSL install failed. See log above." }
    Write-Ok "Workspace built: ~/mockway_ws"
}

function Install-Usbipd {
    Write-Step "Installing usbipd-win (USB passthrough to WSL)..."
    if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id dorssel.usbipd-win -e --accept-source-agreements --accept-package-agreements
            $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
            $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
            $env:Path = "$machinePath;$userPath"
        } else {
            Write-Warn "winget not found. Install manually: https://github.com/dorssel/usbipd-win"
            return
        }
    }
    Write-Ok "usbipd is ready"
}

function Invoke-UsbAttach {
    param([string]$Name)
    if (-not (Test-Path $AttachScript)) { return }
    & $AttachScript -Distro $Name
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Mockway - WSL2 Ubuntu 24.04 + MoveIt2 setup"
Write-Host " Repo: $RepoRoot"
Write-Host " Log:  $LogFile"
Write-Host "============================================================"

try {
Require-Admin

if ($UsbOnly -or $ListUsb) {
    Install-Usbipd
    if ($ListUsb) {
        & $AttachScript -ListOnly
    } else {
        $d = Get-WslDistroName $Distro
        if (-not $d) { throw "No WSL distro found. Run full install first." }
        Invoke-UsbAttach -Name $d
    }
} else {

if (-not $SkipWslInstall) {
    Enable-WslFeatures
    $Distro = Install-Ubuntu2404
} else {
    $Distro = Get-WslDistroName $Distro
    if (-not $Distro) { throw "No WSL Ubuntu found. Run without -SkipWslInstall." }
    Write-Ok "Using existing WSL: $Distro"
}

Initialize-UbuntuUser -Name $Distro

if (-not $SkipMoveItSetup) {
    $repoWsl = Convert-ToWslPath $RepoRoot
    Install-MoveItInsideWsl -Name $Distro -RepoWsl $repoWsl
}

if (-not $SkipUsbipd) {
    Install-Usbipd
    Write-Host ""
    Write-Warn "USB-CAN passthrough (after plugging adapter):"
    Write-Host "  tools\wsl\attach_usb_can.bat"
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Done"
Write-Host "============================================================"
Write-Host " MoveIt demo:     tools\wsl\launch_moveit_demo.bat"
Write-Host " WSL shell:       tools\wsl\mockway_wsl_shell.bat"
Write-Host " USB attach:      tools\wsl\attach_usb_can.bat  (admin)"
Write-Host " Manual in WSL:"
Write-Host "   source ~/mockway_ws/install/setup.bash"
Write-Host "   ros2 launch moveit_mockway_config demo.launch.py"
Write-Host " RViz needs WSLg (Win11 or Win10 22H2+)."
Write-Host "============================================================"
}

} catch {
    Write-Host ""
    Write-Host "[mockway] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    exit 1
}

Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
