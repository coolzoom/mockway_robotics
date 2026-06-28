@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
REM Mockway - WSL2 / MoveIt2 统一入口（菜单 + 命令行快捷方式）

set "LOG=%TEMP%\mockway_wsl_setup.log"
set "SCRIPT_DIR=%~dp0"
set "WSL_DIR=%SCRIPT_DIR%wsl\"
set "REPO_ROOT=%SCRIPT_DIR%.."
set "DISTRO=Ubuntu-24.04"
set "WSL_USER=test"
title Mockway WSL2 / MoveIt2

if /I "%~1"=="admin" goto AdminRunner
if not "%~1"=="" (
    set "MENU_CHOICE=%~1"
    goto Dispatch
)
goto MainMenu

REM ============================================================
REM  菜单
REM ============================================================
:MainMenu
cls
echo.
echo ============================================================
echo  Mockway - WSL2 / MoveIt2 工具菜单
echo ============================================================
call :ResolveDistro
call :ResolveWslUser
echo  发行版: %DISTRO%    用户: %WSL_USER%
echo  日志:   %LOG%
echo.
echo  [1] 完整安装 (WSL2 + Ubuntu + MoveIt2 + usbipd)  ^[需管理员^]
echo  [2] 仅装 WSL 内依赖 (ROS2 Jazzy + MoveIt2 + mockway_ws)
echo  [3] 启动 MoveIt2 Demo (RViz)
echo  [4] 打开 WSL 工作 Shell
echo  [5] 修复 WSL 0x80370114 (Hypervisor / vmcompute)  ^[需管理员^]
echo  [6] USB-CAN 透传到 WSL  ^[需管理员^]
echo  [7] 跳过 WSL 安装，仅配置 MoveIt/usbipd  ^[需管理员^]
echo  [0] 退出
echo.
set "MENU_CHOICE="
set /p MENU_CHOICE=请选择 [0-7]:
if "%MENU_CHOICE%"=="1" goto DoFullInstall
if "%MENU_CHOICE%"=="2" goto DoInstallDeps
if "%MENU_CHOICE%"=="3" goto DoLaunchDemo
if "%MENU_CHOICE%"=="4" goto DoWslShell
if "%MENU_CHOICE%"=="5" goto DoFixHypervisor
if "%MENU_CHOICE%"=="6" goto DoUsbAttach
if "%MENU_CHOICE%"=="7" goto DoSkipWslInstall
if "%MENU_CHOICE%"=="0" exit /b 0
echo 无效选择，请重试。
timeout /t 2 >nul
goto MainMenu

:Dispatch
if "%MENU_CHOICE%"=="1" goto DoFullInstall
if "%MENU_CHOICE%"=="2" goto DoInstallDeps
if "%MENU_CHOICE%"=="3" goto DoLaunchDemo
if "%MENU_CHOICE%"=="4" goto DoWslShell
if "%MENU_CHOICE%"=="5" goto DoFixHypervisor
if "%MENU_CHOICE%"=="6" goto DoUsbAttach
if "%MENU_CHOICE%"=="7" goto DoSkipWslInstall
echo [错误] 无效选项: %MENU_CHOICE%
exit /b 1

REM ============================================================
REM  [1] 完整安装
REM ============================================================
:DoFullInstall
call :RunAdminPs1 ""
set "RC=!ERRORLEVEL!"
goto AfterAction

REM ============================================================
REM  [2] 仅 WSL 内依赖
REM ============================================================
:DoInstallDeps
call :ResolveDistro
if errorlevel 1 goto AfterAction
call :ResolveWslUser
echo.
echo ============================================================
echo  WSL 内安装 Mockway 依赖 (ROS2 Jazzy + MoveIt2)
echo  发行版: %DISTRO%    用户: %WSL_USER%
echo ============================================================
echo.
if /I "%WSL_USER%"=="test" (
    wsl -d %DISTRO% -u root -- bash -lc "echo 'test ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-mockway-test && chmod 440 /etc/sudoers.d/99-mockway-test" 2>nul
)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Console]::OutputEncoding=[Text.Encoding]::UTF8; $OutputEncoding=[Text.Encoding]::UTF8; $repo=(Resolve-Path '%REPO_ROOT%').Path; if($repo -match '^([A-Za-z]):\\(.*)$'){ $wsl='/mnt/'+$matches[1].ToLower()+'/'+$matches[2].Replace('\','/') } else { throw 'bad repo path' }; $sh=$wsl+'/tools/wsl/setup_moveit_jazzy.sh'; wsl -d %DISTRO% -u %WSL_USER% -- env ('MOCKWAY_REPO_WSL='+$wsl) LANG=C.UTF-8 LC_ALL=C.UTF-8 bash $sh; exit $LASTEXITCODE"
set "RC=!ERRORLEVEL!"
if "!RC!"=="0" (
    echo [完成] 依赖已安装。菜单选 [3] 启动 MoveIt Demo。
) else (
    echo [错误] 安装失败，退出码 !RC!
)
goto AfterAction

REM ============================================================
REM  [3] MoveIt Demo
REM ============================================================
:DoLaunchDemo
call :ResolveDistro
if errorlevel 1 goto AfterAction
call :ResolveWslUser
echo [mockway] 启动 MoveIt2 Demo (WSL: %DISTRO%, user: %WSL_USER%) ...
if /I not "%WSL_USER%"=="root" (
    wsl -d %DISTRO% -u %WSL_USER% -- bash -lc "source /opt/ros/jazzy/setup.bash && source ~/mockway_ws/install/setup.bash && ros2 launch moveit_mockway_config demo.launch.py"
) else (
    wsl -d %DISTRO% -- bash -lc "source /opt/ros/jazzy/setup.bash && source ~/mockway_ws/install/setup.bash && ros2 launch moveit_mockway_config demo.launch.py"
)
set "RC=!ERRORLEVEL!"
goto AfterAction

REM ============================================================
REM  [4] WSL Shell
REM ============================================================
:DoWslShell
call :ResolveDistro
if errorlevel 1 goto AfterAction
call :ResolveWslUser
if /I not "%WSL_USER%"=="root" (
    start "Mockway-WSL" wsl -d %DISTRO% -u %WSL_USER% -- bash -lc "source ~/.bashrc 2>/dev/null; cd ~/mockway_ws 2>/dev/null; exec bash"
) else (
    start "Mockway-WSL" wsl -d %DISTRO% -- bash -lc "source ~/.bashrc 2>/dev/null; cd ~/mockway_ws 2>/dev/null; exec bash"
)
set "RC=0"
goto AfterAction

REM ============================================================
REM  [5] 修复 Hypervisor
REM ============================================================
:DoFixHypervisor
call :RunAdminPs1 "fix_hypervisor"
set "RC=!ERRORLEVEL!"
goto AfterAction

REM ============================================================
REM  [6] USB 透传
REM ============================================================
:DoUsbAttach
echo.
echo ============================================================
echo  USB-CAN 透传到 WSL2 (需管理员)
echo  请先插入 USB-CAN 适配器
echo ============================================================
echo.
call :RunAdminPs1 "usb"
set "RC=!ERRORLEVEL!"
goto AfterAction

REM ============================================================
REM  [7] 跳过 WSL，仅 MoveIt 配置
REM ============================================================
:DoSkipWslInstall
call :RunAdminPs1 "skip_wsl"
set "RC=!ERRORLEVEL!"
goto AfterAction

REM ============================================================
REM  管理员运行内嵌 PowerShell
REM ============================================================
:RunAdminPs1
set "ADMIN_MODE=%~1"
set "RC=1"
net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo [提示] 需要管理员权限，即将弹出 UAC ...
    if "%ADMIN_MODE%"=="" set "ADMIN_MODE=full"
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$p=Start-Process -FilePath '%~f0' -ArgumentList @('admin','%ADMIN_MODE%') -Verb RunAs -PassThru -Wait; if($null -eq $p){exit 1}; exit $p.ExitCode"
    set "RC=!ERRORLEVEL!"
    exit /b !RC!
)
cd /d "%SCRIPT_DIR%"
if "%ADMIN_MODE%"=="" set "ADMIN_MODE=full"
if /I "%ADMIN_MODE%"=="fix_hypervisor" (
    echo.
    echo ============================================================
    echo  修复 WSL 错误 0x80370114
    echo ============================================================
    echo.
)
if /I "%ADMIN_MODE%"=="full" (
    echo.
    echo ============================================================
    echo  Mockway - WSL2 Ubuntu 24.04 + MoveIt2 完整安装
    echo  日志: %LOG%
    echo ============================================================
    echo.
)
set "MOCKWAY_PS_MODE=%ADMIN_MODE%"
set "MOCKWAY_TOOLS_DIR=%SCRIPT_DIR%"
call :RunEmbeddedPs
set "RC=!ERRORLEVEL!"
if /I "%ADMIN_MODE%"=="full" call :ShowPs1Result !RC!
if /I "%ADMIN_MODE%"=="skip_wsl" call :ShowPs1Result !RC!
exit /b !RC!

:RunEmbeddedPs
powershell -NoProfile -ExecutionPolicy Bypass -Command "& {$bat='%~f0';$t=[IO.File]::ReadAllText($bat,[Text.UTF8Encoding]::new($false));$m='::#MOCKWAY_PS1';$i=$t.LastIndexOf($m);if($i -lt 0){Write-Error 'Embedded PS marker missing';exit 1};$s=$t.Substring($i+$m.Length).TrimStart([char]13,[char]10);$f=Join-Path $env:TEMP ('mockway_wsl_'+[guid]::NewGuid().ToString('n')+'.ps1');[IO.File]::WriteAllText($f,$s,(New-Object Text.UTF8Encoding $false));& powershell -NoProfile -ExecutionPolicy Bypass -File $f; $c=$LASTEXITCODE; Remove-Item $f -Force -ErrorAction SilentlyContinue; exit $c}"
exit /b %ERRORLEVEL%

:AdminRunner
set "ADMIN_MODE=%~2"
if "%ADMIN_MODE%"=="" set "ADMIN_MODE=full"
call :RunAdminPs1 "%ADMIN_MODE%"
exit /b !ERRORLEVEL!

:ShowPs1Result
set "_RC=%~1"
echo.
echo ============================================================
if "!_RC!"=="301" (
    echo [下一步] WSL 已启用，请先重启 Windows，再运行本菜单 [1] 或 [2]
) else if not "!_RC!"=="0" (
    echo [错误] 安装失败，退出码 !_RC!
    echo 请查看日志: %LOG%
) else (
    echo [完成] 安装成功
    echo  菜单 [3] 启动 MoveIt Demo
    echo  菜单 [4] 打开 WSL Shell
)
echo ============================================================
exit /b 0

REM ============================================================
REM  解析 WSL 发行版 / 用户
REM ============================================================
:ResolveDistro
set "DISTRO=Ubuntu-24.04"
wsl -d Ubuntu-24.04 -- true >nul 2>&1
if not errorlevel 1 exit /b 0
set "DISTRO=Ubuntu"
wsl -d Ubuntu -- true >nul 2>&1
if not errorlevel 1 exit /b 0
echo [错误] 未找到 WSL Ubuntu。请先选 [1] 完整安装。
exit /b 1

:ResolveWslUser
set "WSL_USER=test"
wsl -d %DISTRO% -u test -- true >nul 2>&1 && exit /b 0
set "WSL_USER=root"
exit /b 0

REM ============================================================
REM  操作结束
REM ============================================================
:AfterAction
if not defined RC set "RC=0"
echo.
pause
if "%~1"=="" goto MainMenu
exit /b %RC%

goto :EOF
::#MOCKWAY_PS1
#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$Mode = if ($env:MOCKWAY_PS_MODE) { $env:MOCKWAY_PS_MODE } else { "full" }
$ScriptDir = $env:MOCKWAY_TOOLS_DIR
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$WslScript = Join-Path $ScriptDir "wsl\setup_moveit_jazzy.sh"
$LogFile = Join-Path $env:TEMP "mockway_wsl_setup.log"
$Script:ExitRebootRequired = 301
$Distro = "Ubuntu-24.04"

Start-Transcript -Path $LogFile -Append -ErrorAction SilentlyContinue | Out-Null

try {
    [Console]::InputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

function Write-WslLines {
    param(
        [string]$Text,
        [string]$Prefix = '  '
    )
    if (-not $Text) { return }
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line.Trim()) { Write-Host "$Prefix$line" }
    }
}

function Invoke-Wsl {
    param(
        [string[]]$Arguments,
        [switch]$Quiet
    )
    $result = Invoke-WslText $Arguments
    if (-not $Quiet -and $result.Output) {
        Write-WslLines $result.Output
    }
    $global:LASTEXITCODE = $result.ExitCode
    return $result
}

function Write-Step($msg) { Write-Host "`n[mockway] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[mockway] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[mockway] $msg" -ForegroundColor Yellow }
function Write-Bad($msg)  { Write-Host "[mockway] $msg" -ForegroundColor Red }

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
    Invoke-Wsl @("--install", "--no-distribution") | Out-Null
    Invoke-Wsl @("--update") | Out-Null
    Invoke-Wsl @("--set-default-version", "2") -Quiet | Out-Null
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
    Write-Host "   tools\setup_wsl_moveit.bat menu [5]"
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

function Repair-Hypervisor {
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
        Write-Host "  5. Re-run: tools\setup_wsl_moveit.bat menu [5]"
        Write-Host "  6. Then: wsl --install -d Ubuntu-24.04"
        throw "Hypervisor repair incomplete: vmcompute.exe still missing"
    } elseif ($rebootNeeded) {
        Write-Warn "Reboot required, then run:"
        Write-Host "  tools\setup_wsl_moveit.bat"
    } else {
        Write-Ok "Repair complete. Try:"
        Write-Host "  wsl --install -d Ubuntu-24.04"
        Write-Host "  or tools\setup_wsl_moveit.bat menu [7]"
    }
    Write-Host "============================================================"
}

function Repair-WslHypervisorStack {
    Write-Warn "Running hypervisor repair..."
    Repair-Hypervisor
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
            Write-WslLines $ready.Detail
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
    Invoke-Wsl @("--update") | Out-Null

    Write-Host "  Downloading Ubuntu 24.04 (may take 5-15 minutes on first run)..."
    $install = Invoke-WslText @("--install", "-d", "Ubuntu-24.04", "--no-launch")
    if ($install.Output) {
        Write-WslLines $install.Output
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
        Write-Host "    tools\setup_wsl_moveit.bat menu [7]"
        throw "Ubuntu-24.04 not found after install attempt"
    }
    Write-Ok "Installed: $existing"
    return $existing
}

function Test-WslNormalUser {
    param([string]$Distro)
    return (Get-WslDefaultUser $Distro) -ne "root"
}

function Initialize-UbuntuUser {
    param([string]$Name)
    Write-Step "Checking Ubuntu first-time setup..."
    $test = wsl -d $Name -- bash -lc "echo wsl_ok" 2>&1
    if ($LASTEXITCODE -ne 0 -or $test -notmatch "wsl_ok") {
        Write-Warn "Opening Ubuntu to finish user setup (username/password)..."
        Start-Process wsl.exe -ArgumentList "-d", $Name
        Read-Host "Press Enter after Ubuntu user setup is complete"
        return
    }
    if (-not (Test-WslNormalUser $Name)) {
        Write-Warn "WSL has no regular user yet (only root)."
        Write-Host "  Recommended: open 'Ubuntu 24.04' from Start menu and create a username."
        Write-Host "  Install will continue as root -> /root/mockway_ws"
        Write-Host ""
    }
}

function Test-WslUserExists {
    param([string]$Distro, [string]$User)
    & wsl.exe -d $Distro -u $User -- true 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Get-WslDefaultUser {
    param([string]$Distro)
    $preferred = if ($env:MOCKWAY_WSL_USER) { $env:MOCKWAY_WSL_USER } else { "test" }
    if (Test-WslUserExists $Distro $preferred) { return $preferred }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = "-d $Distro -u root -- getent passwd"
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($psi)
    $out = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    foreach ($line in ($out -split "`r?`n")) {
        if ($line -match '^([^:]+):x:(\d+):') {
            $uid = [int]$Matches[2]
            if ($uid -ge 1000 -and $uid -lt 65534) { return $Matches[1] }
        }
    }
    return "root"
}

function Enable-WslPasswordlessSudo {
    param([string]$Distro, [string]$User)
    if (-not (Test-WslUserExists $Distro $User)) { return }
    Write-Host "  Configuring passwordless sudo for ${User} (WSL install only)..."
    $line = "${User} ALL=(ALL) NOPASSWD:ALL"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($line))
    & wsl.exe -d $Distro -u root -- bash -lc "echo $b64 | base64 -d > /etc/sudoers.d/99-mockway-$User && chmod 440 /etc/sudoers.d/99-mockway-$User"
}

function Set-WslDefaultUser {
    param([string]$Distro, [string]$User)
    if (-not (Test-WslUserExists $Distro $User)) { return }
    Write-Host "  Setting WSL default user: $User"
    $conf = @"
[user]
default=$User
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($conf))
    $cmd = "echo $b64 | base64 -d | sudo tee /etc/wsl.conf > /dev/null"
    & wsl.exe -d $Distro -u root -- bash -lc $cmd
    & wsl.exe --shutdown 2>$null
    Start-Sleep -Seconds 2
}

function Install-MoveItInsideWsl {
    param([string]$Name, [string]$RepoWsl)
    Write-Step "Installing ROS2 Jazzy + MoveIt2 inside WSL..."
    if (-not (Test-Path $WslScript)) { throw "Missing script: $WslScript" }

    $bashPath = Convert-ToWslPath $WslScript
    $wslUser = Get-WslDefaultUser $Name
    if ($wslUser -eq "root" -and (Test-WslUserExists $Name "test")) {
        $wslUser = "test"
    }
    Enable-WslPasswordlessSudo -Distro $Name -User $wslUser
    if ($wslUser -eq "test") {
        Set-WslDefaultUser -Distro $Name -User "test"
    }
    Write-Host "  WSL user:   $wslUser"
    Write-Host "  Workspace:  /home/$wslUser/mockway_ws (or ~/mockway_ws)"
    Write-Host "  Repo (WSL): $RepoWsl"
    Write-Host "  Script:     $bashPath"
    & wsl.exe -d $Name -u $wslUser -- env "MOCKWAY_REPO_WSL=$RepoWsl" LANG=C.UTF-8 LC_ALL=C.UTF-8 bash "$bashPath"
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Host ""
        Write-Warn "WSL install exited with code $exitCode"
        Write-Host "  Try manually in WSL:"
        Write-Host "  env MOCKWAY_REPO_WSL=$RepoWsl bash $bashPath"
        throw "WSL install failed (exit $exitCode). See log: $LogFile"
    }
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

function Invoke-UsbAttachCore {
    param(
        [string]$Distro = "Ubuntu-24.04",
        [string]$BusId = "",
        [switch]$ListOnly,
        [switch]$DetachAll
    )

    if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
        throw "usbipd not found. Run tools\setup_wsl_moveit.bat menu [6] as administrator"
    }

    Write-Host ""
    Write-Host "=== USB devices (usbipd list) ==="
    usbipd list
    Write-Host ""

    if ($ListOnly) { return }

    if ($DetachAll) {
        Write-Host "[usb] Detaching all attached devices..."
        usbipd list | Select-String "Attached" | ForEach-Object {
            if ($_ -match '(\d-\d+)') {
                $id = $Matches[1]
                Write-Host "  detach $id"
                usbipd detach --busid $id 2>$null
            }
        }
        return
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
        Write-Host "No USB-CAN device auto-detected. Plug in adapter and run:"
        Write-Host "  tools\setup_wsl_moveit.bat menu [6]"
        throw "No USB-CAN device auto-detected"
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
}

function Invoke-UsbAttach {
    param([string]$Name)
    Invoke-UsbAttachCore -Distro $Name
}

if ($Mode -eq 'fix_hypervisor') {
    try {
        Require-Admin
        Write-Host ""
        Write-Host "============================================================"
        Write-Host " Mockway - Fix WSL 0x80370114 (hypervisor / vmcompute)"
        Write-Host "============================================================"
        Repair-Hypervisor
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 0
    } catch {
        Write-Host ""
        Write-Host "[mockway] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ScriptStackTrace) {
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
        }
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }
}

if ($Mode -eq 'usb') {
    try {
        Require-Admin
        Write-Host ""
        Write-Host "============================================================"
        Write-Host " USB-CAN passthrough to WSL2 (usbipd)"
        Write-Host " Plug in USB-CAN adapter before continuing"
        Write-Host "============================================================"
        Install-Usbipd
        $d = Get-WslDistroName $Distro
        if (-not $d) { throw "No WSL distro found. Run full install first (menu [1])." }
        Invoke-UsbAttachCore -Distro $d
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 0
    } catch {
        Write-Host ""
        Write-Host "[mockway] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ScriptStackTrace) {
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
        }
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
        exit 1
    }
}

Write-Host ""
Write-Host "============================================================"
Write-Host " Mockway - WSL2 Ubuntu 24.04 + MoveIt2 setup"
Write-Host " Repo: $RepoRoot"
Write-Host " Log:  $LogFile"
Write-Host "============================================================"

try {
    Require-Admin

    $SkipWslInstall = ($Mode -eq 'skip_wsl')

    if (-not $SkipWslInstall) {
        Enable-WslFeatures
        $Distro = Install-Ubuntu2404
    } else {
        $Distro = Get-WslDistroName $Distro
        if (-not $Distro) { throw "No WSL Ubuntu found. Run menu [1] full install first." }
        Write-Ok "Using existing WSL: $Distro"
    }

    Initialize-UbuntuUser -Name $Distro
    if (Test-WslUserExists $Distro "test") {
        Set-WslDefaultUser -Distro $Distro -User "test"
    }

    $repoWsl = Convert-ToWslPath $RepoRoot
    Install-MoveItInsideWsl -Name $Distro -RepoWsl $repoWsl

    Install-Usbipd
    Write-Host ""
    Write-Warn "USB-CAN passthrough (after plugging adapter):"
    Write-Host "  tools\setup_wsl_moveit.bat menu [6]"

    Write-Host ""
    Write-Host "============================================================"
    Write-Host " Done"
    Write-Host "============================================================"
    Write-Host " MoveIt demo:     tools\setup_wsl_moveit.bat menu [3]"
    Write-Host " WSL shell:       tools\setup_wsl_moveit.bat menu [4]"
    Write-Host " USB attach:      tools\setup_wsl_moveit.bat menu [6]"
    Write-Host " Manual in WSL:"
    Write-Host "   source ~/mockway_ws/install/setup.bash"
    Write-Host "   ros2 launch moveit_mockway_config demo.launch.py"
    Write-Host " RViz needs WSLg (Win11 or Win10 22H2+)."
    Write-Host "============================================================"

} catch {
    Write-Host ""
    Write-Host "[mockway] ERROR: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ScriptStackTrace) {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    exit 1
}

Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
