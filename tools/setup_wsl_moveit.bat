@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
REM Mockway - WSL2 Ubuntu 24.04 + MoveIt2 (Administrator required)

set "LOG=%TEMP%\mockway_wsl_setup.log"
set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%setup_wsl_moveit.ps1"
title Mockway WSL2 MoveIt2 安装

REM ---- Request Administrator ----
net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo ============================================================
    echo  需要管理员权限
    echo ============================================================
    echo  即将弹出 UAC，请点击「是」
    echo  安装将在「新的管理员窗口」中运行，请勿关闭该窗口
    echo  安装日志: %LOG%
    echo ============================================================
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "$p = Start-Process -FilePath '%~f0' -Verb RunAs -PassThru -Wait; if ($null -eq $p) { exit 1 }; exit $p.ExitCode"
    set "RC=!ERRORLEVEL!"
    echo.
    if "!RC!"=="0" (
        echo [完成] 管理员窗口中的安装已结束。
    ) else if "!RC!"=="301" (
        echo [下一步] 请先重启 Windows，然后再次运行本脚本。
    ) else (
        echo [提示] 安装未成功 ^(退出码 !RC!^)，或 UAC 点了「否」
        echo 请查看日志: %LOG%
        echo 也可右键本文件 -^> 以管理员身份运行
    )
    echo.
    pause
    exit /b !RC!
)

cd /d "%SCRIPT_DIR%"
echo.
echo ============================================================
echo  Mockway - WSL2 Ubuntu 24.04 + MoveIt2 安装
echo  日志: %LOG%
echo ============================================================
echo.

if not exist "%PS1%" (
    echo [错误] 找不到: %PS1%
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"

echo.
echo ============================================================
if "%RC%"=="301" (
    echo [下一步] WSL 已启用，必须先重启 Windows 才能安装 Ubuntu
    echo.
    echo  1. 重启电脑
    echo  2. 再次运行: tools\setup_wsl_moveit.bat
    echo.
    echo  这不是安装失败，重启后会继续安装 Ubuntu 和 MoveIt。
) else if not "%RC%"=="0" (
    echo [错误] 安装失败，退出码 %RC%
    echo 请查看日志: %LOG%
) else (
    echo [完成] 安装成功
    echo  启动 MoveIt: tools\wsl\launch_moveit_demo.bat
    echo  仅装依赖:   tools\wsl\install_all_deps.bat
    echo  USB 透传:   tools\wsl\attach_usb_can.bat
)
echo ============================================================
echo.
echo 按任意键关闭此窗口...
pause >nul
exit /b %RC%
