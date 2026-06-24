@echo off
chcp 65001 >nul
title Mockway-mockway_dynamics

set "ENV_NAME=mockway_dynamics"
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\..\"

set "CONDA_ACTIVATE="
if exist "%USERPROFILE%\miniconda3\Scripts\activate.bat" set "CONDA_ACTIVATE=%USERPROFILE%\miniconda3\Scripts\activate.bat"
if not defined CONDA_ACTIVATE if exist "%USERPROFILE%\anaconda3\Scripts\activate.bat" set "CONDA_ACTIVATE=%USERPROFILE%\anaconda3\Scripts\activate.bat"
if not defined CONDA_ACTIVATE if exist "C:\ProgramData\miniconda3\Scripts\activate.bat" set "CONDA_ACTIVATE=C:\ProgramData\miniconda3\Scripts\activate.bat"

if not defined CONDA_ACTIVATE (
    echo [错误] 未找到 conda，请先运行 setup_win.bat 选 [1] 安装环境。
    pause
    exit /b 1
)

call "%CONDA_ACTIVATE%"
call conda activate %ENV_NAME%
if errorlevel 1 (
    echo [错误] 无法激活 %ENV_NAME%，请先运行 setup_win.bat 选 [1] 安装。
    pause
    exit /b 1
)

cd /d "%SCRIPT_DIR%"

echo.
echo ============================================================
echo  Mockway %ENV_NAME% 工作窗口
echo ============================================================
echo  当前目录: %CD%
echo  力矩补偿: python realtime_torque_compensation.py
echo  motor_gui: cd %REPO_ROOT%tools\motor_gui ^&^& python motor_gui.py
echo  关闭本窗口即结束工作会话
echo ============================================================
echo.

cmd /k
