@echo off
chcp 65001 >nul
setlocal
set "PS1=%~dp0fix_wsl_hypervisor.ps1"
title Mockway - 修复 WSL 0x80370114

net session >nul 2>&1
if errorlevel 1 (
    echo 需要管理员权限，正在请求 UAC...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs -Wait"
    exit /b %ERRORLEVEL%
)

echo.
echo ============================================================
echo  修复 WSL 错误 0x80370114
echo  ^(Hypervisor / vmcompute 未就绪^)
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%
