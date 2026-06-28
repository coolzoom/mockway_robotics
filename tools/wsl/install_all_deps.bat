@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
REM 在已有 WSL Ubuntu 内安装 ROS2 Jazzy + MoveIt2 及 mockway_ws 依赖（无需管理员）
set "TOOLS_DIR=%~dp0"
set "REPO_ROOT=%TOOLS_DIR%..\..\"
set "DISTRO=Ubuntu-24.04"

wsl -l -v 2>nul | findstr /I "Ubuntu-24.04" >nul || set "DISTRO=Ubuntu"
wsl -l -v 2>nul | findstr /I "%DISTRO%" >nul || (
    echo [错误] 未找到 WSL Ubuntu。请先以管理员运行: tools\setup_wsl_moveit.bat
    exit /b 1
)

echo.
echo ============================================================
echo  WSL 内安装 Mockway 依赖 (ROS2 Jazzy + MoveIt2)
echo  发行版: %DISTRO%
echo ============================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$repo=(Resolve-Path '%REPO_ROOT%').Path; if($repo -match '^([A-Za-z]):\\(.*)$'){ $wsl='/mnt/'+$matches[1].ToLower()+'/'+$matches[2].Replace('\','/') } else { throw 'bad path' }; $sh=$wsl+'/tools/wsl/setup_moveit_jazzy.sh'; wsl -d %DISTRO% -- bash -lc \"MOCKWAY_REPO_WSL='$wsl' bash '$sh'\""
set "RC=%ERRORLEVEL%"
echo.
if "%RC%"=="0" (
    echo [完成] 依赖已安装。启动 MoveIt: tools\wsl\launch_moveit_demo.bat
) else (
    echo [错误] 安装失败，退出码 %RC%
)
exit /b %RC%
