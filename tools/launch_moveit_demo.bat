@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
REM 非管理员启动 MoveIt Demo（默认真机 + USB-CAN）— WSLg / RViz 请勿从「管理员 CMD」运行
set "TOOLS=%~dp0"
set "WSL_DIR=%TOOLS%wsl\"
set "DISTRO=Ubuntu-24.04"
set "WSL_USER=test"
wsl -d %DISTRO% -u %WSL_USER% -- true >nul 2>&1 || set "DISTRO=Ubuntu"
wsl -d %DISTRO% -u test -- true >nul 2>&1 || set "WSL_USER=root"
set "_WSL_PATH="
set "WIN_TMP=%WSL_DIR%launch_moveit_demo.sh"
set "WIN_TMP=!WIN_TMP:\=/!"
for /f "usebackq delims=" %%P in (`wsl wslpath -u "!WIN_TMP!" 2^>nul`) do set "_WSL_PATH=%%P"
if not defined _WSL_PATH (
    echo [错误] 找不到启动脚本: %WSL_DIR%launch_moveit_demo.sh
    pause
    exit /b 1
)
echo [mockway] 启动 MoveIt Demo (%DISTRO% / %WSL_USER%) ...
wsl -d %DISTRO% -u %WSL_USER% -- bash -lc "sed 's/\r$//' '!_WSL_PATH!' | bash"
echo.
pause
