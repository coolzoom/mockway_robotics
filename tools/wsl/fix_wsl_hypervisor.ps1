#Requires -Version 5.1
# Fix WSL error 0x80370114 (hypervisor / vmcompute not available)
param([switch]$DiagnoseOnly)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "`n[mockway] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[mockway] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[mockway] $msg" -ForegroundColor Yellow }
function Write-Bad($msg)  { Write-Host "[mockway] $msg" -ForegroundColor Red }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    throw "Administrator required. Right-click fix_wsl_hypervisor.bat -> Run as administrator"
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Mockway - Fix WSL 0x80370114 (hypervisor / vmcompute)"
Write-Host "============================================================"

$vmcomputePath = Join-Path $env:SystemRoot "System32\vmcompute.exe"
$issues = @()

Write-Step "Diagnosis"

$features = @(
    @{ Name = "Microsoft-Windows-Subsystem-Linux"; Label = "Windows Subsystem for Linux" },
    @{ Name = "VirtualMachinePlatform"; Label = "Virtual Machine Platform" },
    @{ Name = "HypervisorPlatform"; Label = "Windows Hypervisor Platform" }
)

foreach ($f in $features) {
    $feat = Get-WindowsOptionalFeature -Online -FeatureName $f.Name -ErrorAction SilentlyContinue
    $state = if ($feat) { $feat.State } else { "Missing" }
    $ok = ($state -eq "Enabled")
    if ($ok) { Write-Ok "$($f.Label): $state" } else { Write-Bad "$($f.Label): $state"; $issues += $f.Label }
}

$bcd = cmd /c "bcdedit /enum `{current`}" 2>&1 | Out-String
if ($bcd -match '(?i)hypervisorlaunchtype\s+(\S+)') {
    $launch = $Matches[1]
    if ($launch -ieq "Auto") { Write-Ok "hypervisorlaunchtype: Auto" }
    else { Write-Bad "hypervisorlaunchtype: $launch (should be Auto)"; $issues += "hypervisorlaunchtype" }
} else {
    Write-Warn "hypervisorlaunchtype not found in bcdedit output"
}

if (Test-Path $vmcomputePath) {
    Write-Ok "vmcompute.exe: present"
    $svc = Get-Service vmcompute -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "  vmcompute service: $($svc.Status) (start: $($svc.StartType))"
        if ($svc.Status -ne "Running") { $issues += "vmcompute stopped" }
    } else {
        Write-Bad "vmcompute service: not registered"
        $issues += "vmcompute service"
    }
} else {
    Write-Bad "vmcompute.exe: MISSING (Virtual Machine Platform not installed correctly)"
    $issues += "vmcompute.exe missing"
}

if ($DiagnoseOnly) {
    Write-Host ""
    if ($issues.Count -eq 0) {
        Write-Ok "No obvious issues found. Try: wsl --install -d Ubuntu-24.04"
    } else {
        Write-Bad "Issues found: $($issues -join '; ')"
        Write-Host "Run without -DiagnoseOnly to attempt repair."
    }
    exit 0
}

Write-Step "Repair"

$rebootNeeded = $false
foreach ($f in $features) {
    $feat = Get-WindowsOptionalFeature -Online -FeatureName $f.Name -ErrorAction SilentlyContinue
    if (-not $feat -or $feat.State -ne "Enabled") {
        Write-Host "  Enabling $($f.Label) ..."
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $f.Name -All -NoRestart
        if ($result.RestartNeeded) { $rebootNeeded = $true }
    }
}

if ($bcd -notmatch '(?i)hypervisorlaunchtype\s+Auto') {
    Write-Host "  Setting hypervisorlaunchtype=Auto ..."
    cmd /c "bcdedit /set hypervisorlaunchtype Auto" | Out-Null
    $rebootNeeded = $true
}

wsl --update 2>&1 | ForEach-Object { Write-Host "  $_" }

if (Test-Path $vmcomputePath) {
    Write-Host "  Starting vmcompute service ..."
    Set-Service vmcompute -StartupType Manual -ErrorAction SilentlyContinue
    Start-Service vmcompute -ErrorAction SilentlyContinue
    Write-Ok "vmcompute is available"
} else {
    $rebootNeeded = $true
    Write-Warn "vmcompute.exe still missing after enabling features."
}

Write-Host ""
Write-Host "============================================================"
if (-not (Test-Path $vmcomputePath)) {
    Write-Bad "Virtual Machine Platform is still broken."
    Write-Host ""
    Write-Host "Manual fix (if auto-repair did not help):"
    Write-Host "  1. Open: Turn Windows features on or off"
    Write-Host "  2. UNCHECK all three, Apply, do NOT reboot"
    Write-Host "  3. CHECK all three again, Apply, reboot:"
    Write-Host "     - Windows Subsystem for Linux"
    Write-Host "     - Virtual Machine Platform"
    Write-Host "     - Windows Hypervisor Platform"
    Write-Host "  4. Enable Intel VT-x / AMD-V in BIOS if still failing"
    Write-Host "     https://aka.ms/enablevirtualization"
    Write-Host "  5. Re-run: tools\wsl\fix_wsl_hypervisor.bat"
    Write-Host "  6. Then: wsl --install -d Ubuntu-24.04"
} elseif ($rebootNeeded) {
    Write-Warn "Reboot required, then run:"
    Write-Host "  tools\setup_wsl_moveit.bat"
} else {
    Write-Ok "Repair complete. Try:"
    Write-Host "  wsl --install -d Ubuntu-24.04"
    Write-Host "  or tools\setup_wsl_moveit.bat -SkipWslInstall"
}
Write-Host "============================================================"
