@echo off
chcp 65001 >nul
REM USB-CAN passthrough to WSL2 (Administrator required)
echo.
echo ============================================================
echo  USB-CAN 透传到 WSL2 (需管理员)
echo  请先插入 USB-CAN 适配器
echo ============================================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0attach_usb_can.ps1" %*
pause
