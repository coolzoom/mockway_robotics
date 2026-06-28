@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

REM ============================================================
REM  Mockway Windows 开发环境管理脚本
REM  菜单: 安装环境 / 启动工具 / 工作 shell / 停止
REM ============================================================

set "ENV_NAME=mockway_dynamics"
set "PYTHON_VER=3.10"
set "PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple"
set "PIP_TRUSTED=pypi.tuna.tsinghua.edu.cn"
set "MINICONDA_DIR=%USERPROFILE%\miniconda3"
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\"
set "MOTOR_GUI_DIR=%SCRIPT_DIR%motor_gui\"
set "DYNAMICS_TEST_DIR=%SCRIPT_DIR%dynamics_test\"

set "TITLE_SHELL=Mockway-Shell"
set "TITLE_MOTOR_GUI=Mockway-motor_gui"
set "TITLE_TORQUE=Mockway-torque"
set "TITLE_INVERSE=Mockway-inverse"

set "MINICONDA_URL_TSINGHUA=https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Windows-x86_64.exe"
set "MINICONDA_URL_OFFICIAL=https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
set "MINICONDA_INSTALLER=%TEMP%\Miniconda3-latest-Windows-x86_64.exe"

if /I "%~1"=="setup" goto DoSetup
if /I "%~1"=="motor_gui" goto DoMotorGui
if /I "%~1"=="torque" goto DoTorque
if /I "%~1"=="inverse" goto DoInverse
if /I "%~1"=="shell" goto DoShell
if /I "%~1"=="start" goto DoShell
if /I "%~1"=="stop" goto DoStop

:MainMenu
cls
echo.
echo ============================================================
echo  Mockway 开发环境管理 (Windows)
echo ============================================================
echo.
call :ShowEnvStatus
echo.
echo  [1] 安装 / 更新环境 (Miniconda + Pinocchio + 依赖)
echo  [2] 启动 motor_gui (电机调试)
echo  [3] 启动 实时力矩补偿 (realtime_torque_compensation)
echo  [4] 启动 离线动力学测试 (inverse_dynamics_test)
echo  [5] 打开 Python 工作 shell
echo  [6] 停止 (关闭工具窗口)
echo  [7] WSL2 / MoveIt2 工具菜单 (Ubuntu 24.04)
echo  [0] 退出
echo.
set "MENU_CHOICE="
set /p MENU_CHOICE=请选择 [0-7]:
if "%MENU_CHOICE%"=="1" goto DoSetup
if "%MENU_CHOICE%"=="2" goto DoMotorGui
if "%MENU_CHOICE%"=="3" goto DoTorque
if "%MENU_CHOICE%"=="4" goto DoInverse
if "%MENU_CHOICE%"=="5" goto DoShell
if "%MENU_CHOICE%"=="6" goto DoStop
if "%MENU_CHOICE%"=="7" goto DoWslMoveIt
if "%MENU_CHOICE%"=="0" goto DoExit
echo 无效选择，请重试。
timeout /t 2 >nul
goto MainMenu

REM ============================================================
REM  [1] 安装环境
REM ============================================================
:DoSetup
cls
echo.
echo ============================================================
echo  安装 / 更新 %ENV_NAME% 环境
echo ============================================================
echo.

call :FindConda
if not defined CONDA_ACTIVATE (
    echo [0/8] 未检测到 Miniconda，开始自动安装 ...
    echo        安装路径: %MINICONDA_DIR%
    call :InstallMiniconda
    if errorlevel 1 goto SetupFailed
    call :FindConda
)

if not defined CONDA_ACTIVATE (
    echo [错误] 未找到 conda，请先安装 Miniconda。
    goto SetupFailed
)

echo [1/8] 初始化 conda ...
call :InitCondaBase
if errorlevel 1 goto SetupFailed

echo [2/8] 配置 conda 国内镜像（清华源）...
call :ConfigureCondaMirror
if errorlevel 1 goto SetupFailed

echo [3/8] 检查 conda 环境 "%ENV_NAME%" ...
conda env list | findstr /I /C:"%ENV_NAME%" >nul 2>&1
if errorlevel 1 (
    echo        创建新环境 Python %PYTHON_VER% ...
    call conda create -n %ENV_NAME% python=%PYTHON_VER% -y
) else (
    echo        环境已存在，跳过创建。
)
if errorlevel 1 goto SetupFailed

echo [4/8] 激活环境 ...
call conda activate %ENV_NAME%
if errorlevel 1 goto SetupFailed

echo [5/8] 安装 Pinocchio (conda-forge) ...
call conda install pinocchio -c conda-forge -y
if errorlevel 1 (
    echo        重试清华 conda-forge 镜像 ...
    call conda install pinocchio -c https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge -y
)
if errorlevel 1 goto SetupFailed

echo [6/8] 安装 pip 依赖 (numpy / matplotlib / pyserial / pyyaml) ...
python -m pip install --upgrade pip -i %PIP_INDEX% --trusted-host %PIP_TRUSTED%
python -m pip install "numpy>=1.20.0" "matplotlib>=3.3.0" "pyserial>=3.5" "pyyaml>=6.0" ^
    -i %PIP_INDEX% --trusted-host %PIP_TRUSTED%
if errorlevel 1 goto SetupFailed

echo [7/8] 验证安装 ...
python -c "import pinocchio as pin; import numpy; import matplotlib; import serial; import yaml; print('pinocchio', pin.__version__); print('numpy', numpy.__version__); print('OK')"
if errorlevel 1 goto SetupFailed

echo [8/8] 安装完成。
echo.
echo ============================================================
echo  环境 %ENV_NAME% 已就绪。
echo  返回菜单后可选 [2]~[5] 启动工具。
echo ============================================================
echo.
pause
goto MainMenu

:SetupFailed
echo.
echo [错误] 安装失败，请查看上方报错。
pause
goto MainMenu

REM ============================================================
REM  [2] motor_gui
REM ============================================================
:DoMotorGui
call :CheckEnvReady
if errorlevel 1 goto MainMenu
call :LaunchApp "%TITLE_MOTOR_GUI%" "%MOTOR_GUI_DIR%" "motor_gui.py"
if /I "%~1"=="motor_gui" exit /b 0
pause
goto MainMenu

REM ============================================================
REM  [3] 实时力矩补偿
REM ============================================================
:DoTorque
call :CheckEnvReady
if errorlevel 1 (
    if /I "%~1"=="torque" exit /b 1
    goto MainMenu
)
call :LaunchApp "%TITLE_TORQUE%" "%DYNAMICS_TEST_DIR%" "realtime_torque_compensation.py"
if /I "%~1"=="torque" exit /b 0
pause
goto MainMenu

REM ============================================================
REM  [4] 离线动力学测试
REM ============================================================
:DoInverse
call :CheckEnvReady
if errorlevel 1 (
    if /I "%~1"=="inverse" exit /b 1
    goto MainMenu
)
call :LaunchApp "%TITLE_INVERSE%" "%DYNAMICS_TEST_DIR%" "inverse_dynamics_test.py"
if /I "%~1"=="inverse" exit /b 0
pause
goto MainMenu

REM ============================================================
REM  [5] Python 工作 shell
REM ============================================================
:DoShell
call :CheckEnvReady
if errorlevel 1 (
    if /I "%~1"=="shell" exit /b 1
    if /I "%~1"=="start" exit /b 1
    goto MainMenu
)

echo [启动] 打开 Python 工作 shell ...
start "%TITLE_SHELL%" cmd /k "call "%CONDA_ACTIVATE%" && conda activate %ENV_NAME% && cd /d "%REPO_ROOT%" && echo. && echo Mockway %ENV_NAME% 工作 shell && echo 仓库根目录: %REPO_ROOT% && echo."

echo.
echo  工作 shell 已打开 (窗口标题: %TITLE_SHELL%)
echo.
if /I "%~1"=="shell" exit /b 0
if /I "%~1"=="start" exit /b 0
pause
goto MainMenu

REM ============================================================
REM  [6] 停止
REM ============================================================
:DoStop
echo [停止] 关闭 Mockway 工具窗口 ...

call :CloseWindow "%TITLE_SHELL%"
call :CloseWindow "%TITLE_MOTOR_GUI%"
call :CloseWindow "%TITLE_TORQUE%"
call :CloseWindow "%TITLE_INVERSE%"

echo.
echo  工具窗口已关闭。
echo.
if /I "%~1"=="stop" exit /b 0
pause
goto MainMenu

REM ============================================================
REM  [7] WSL2 + MoveIt2
REM ============================================================
:DoWslMoveIt
echo [启动] WSL2 Ubuntu 24.04 + MoveIt2 安装（需管理员）...
call "%SCRIPT_DIR%setup_wsl_moveit.bat"
goto MainMenu

:DoExit
exit /b 0

REM ============================================================
REM  子程序: 检查 conda 环境是否可用
REM ============================================================
:CheckEnvReady
call :FindConda
if not defined CONDA_ACTIVATE (
    echo [错误] 未找到 conda，请先选 [1] 安装环境。
    pause
    exit /b 1
)
call :InitCondaBase >nul 2>&1
conda env list | findstr /I /C:"%ENV_NAME%" >nul 2>&1
if errorlevel 1 (
    echo [错误] 环境 %ENV_NAME% 不存在，请先选 [1] 安装。
    pause
    exit /b 1
)
exit /b 0

REM ============================================================
REM  子程序: 在新窗口启动 Python 程序
REM ============================================================
:LaunchApp
set "WIN_TITLE=%~1"
set "WORK_DIR=%~2"
set "PY_SCRIPT=%~3"

if not exist "%WORK_DIR%%PY_SCRIPT%" (
    echo [错误] 未找到脚本: %WORK_DIR%%PY_SCRIPT%
    pause
    exit /b 1
)

echo [启动] %PY_SCRIPT% ...
start "%WIN_TITLE%" cmd /k "call "%CONDA_ACTIVATE%" && conda activate %ENV_NAME% && cd /d "%WORK_DIR%" && python %PY_SCRIPT%"
echo        窗口标题: %WIN_TITLE%
exit /b 0

REM ============================================================
REM  子程序: 关闭指定标题的工具窗口
REM ============================================================
:CloseWindow
set "KILL_TITLE=%~1"
taskkill /FI "WINDOWTITLE eq %KILL_TITLE%*" /T /F >nul 2>&1
if not errorlevel 1 echo        已关闭: %KILL_TITLE%
exit /b 0

REM ============================================================
REM  子程序: 初始化 conda（base）
REM ============================================================
:InitCondaBase
call "%CONDA_ACTIVATE%"
if errorlevel 1 exit /b 1
where conda >nul 2>&1
if errorlevel 1 (
    set "PATH=%MINICONDA_DIR%;%MINICONDA_DIR%\Scripts;%MINICONDA_DIR%\Library\bin;!PATH!"
)
exit /b 0

REM ============================================================
REM  子程序: 显示环境状态
REM ============================================================
:ShowEnvStatus
call :FindConda
if not defined CONDA_ACTIVATE (
    echo  状态: conda 未安装
    goto :ShowChildWindows
)
call :InitCondaBase >nul 2>&1
conda env list | findstr /I /C:"%ENV_NAME%" >nul 2>&1
if errorlevel 1 (
    echo  状态: conda 已安装，环境 %ENV_NAME% 未创建
) else (
    echo  状态: 环境 %ENV_NAME% 已安装
)
:ShowChildWindows
call :IsWindowRunning "%TITLE_SHELL%" SHELL_RUNNING
call :IsWindowRunning "%TITLE_MOTOR_GUI%" GUI_RUNNING
call :IsWindowRunning "%TITLE_TORQUE%" TORQUE_RUNNING
call :IsWindowRunning "%TITLE_INVERSE%" INVERSE_RUNNING
if "!SHELL_RUNNING!"=="1" echo  工作 shell: 【运行中】
if "!GUI_RUNNING!"=="1" echo  motor_gui: 【运行中】
if "!TORQUE_RUNNING!"=="1" echo  力矩补偿: 【运行中】
if "!INVERSE_RUNNING!"=="1" echo  离线动力学: 【运行中】
exit /b 0

REM ============================================================
REM  子程序: 检测窗口是否在运行
REM ============================================================
:IsWindowRunning
set "%~2=0"
tasklist /FI "WINDOWTITLE eq %~1*" 2>nul | findstr /I "cmd.exe" >nul 2>&1
if not errorlevel 1 set "%~2=1"
exit /b 0

REM ============================================================
REM  子程序: 查找 conda
REM ============================================================
:FindConda
set "CONDA_ACTIVATE="
if exist "%USERPROFILE%\miniconda3\Scripts\activate.bat" (
    set "CONDA_ACTIVATE=%USERPROFILE%\miniconda3\Scripts\activate.bat"
    set "MINICONDA_DIR=%USERPROFILE%\miniconda3"
    goto :FindCondaDone
)
if exist "%USERPROFILE%\anaconda3\Scripts\activate.bat" (
    set "CONDA_ACTIVATE=%USERPROFILE%\anaconda3\Scripts\activate.bat"
    goto :FindCondaDone
)
if exist "C:\ProgramData\miniconda3\Scripts\activate.bat" (
    set "CONDA_ACTIVATE=C:\ProgramData\miniconda3\Scripts\activate.bat"
    set "MINICONDA_DIR=C:\ProgramData\miniconda3"
    goto :FindCondaDone
)
if exist "C:\ProgramData\anaconda3\Scripts\activate.bat" (
    set "CONDA_ACTIVATE=C:\ProgramData\anaconda3\Scripts\activate.bat"
    goto :FindCondaDone
)
:FindCondaDone
exit /b 0

REM ============================================================
REM  子程序: 安装 Miniconda
REM ============================================================
:InstallMiniconda
if exist "%MINICONDA_DIR%\Scripts\activate.bat" exit /b 0

echo        下载 Miniconda（清华镜像）...
call :DownloadMiniconda "%MINICONDA_URL_TSINGHUA%"
if errorlevel 1 (
    echo        尝试官方源 ...
    call :DownloadMiniconda "%MINICONDA_URL_OFFICIAL%"
)
if errorlevel 1 exit /b 1
if not exist "%MINICONDA_INSTALLER%" exit /b 1

echo        静默安装 Miniconda（约 1~3 分钟）...
start /wait "" "%MINICONDA_INSTALLER%" /InstallationType=JustMe /RegisterPython=0 /AddToPath=1 /S /D=%MINICONDA_DIR%
if errorlevel 1 exit /b 1
if not exist "%MINICONDA_DIR%\Scripts\activate.bat" exit /b 1

echo        Miniconda 安装成功: %MINICONDA_DIR%
del /f /q "%MINICONDA_INSTALLER%" >nul 2>&1
exit /b 0

REM ============================================================
REM  子程序: conda 清华镜像
REM ============================================================
:ConfigureCondaMirror
set "CONDA_RC=%MINICONDA_DIR%\.condarc"
(
echo channels:
echo   - defaults
echo show_channel_urls: true
echo default_channels:
echo   - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
echo   - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
echo   - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
echo custom_channels:
echo   conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
echo   pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
) > "%CONDA_RC%"
if not exist "%CONDA_RC%" exit /b 1
call conda clean -i -y >nul 2>&1
exit /b 0

REM ============================================================
REM  子程序: 下载 Miniconda 安装包
REM ============================================================
:DownloadMiniconda
set "DL_URL=%~1"
if exist "%MINICONDA_INSTALLER%" del /f /q "%MINICONDA_INSTALLER%" >nul 2>&1

where curl >nul 2>&1
if not errorlevel 1 (
    curl -fsSL -o "%MINICONDA_INSTALLER%" "%DL_URL%"
    if not errorlevel 1 if exist "%MINICONDA_INSTALLER%" exit /b 0
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%DL_URL%' -OutFile '%MINICONDA_INSTALLER%' -UseBasicParsing; exit 0 } catch { exit 1 }"
if not errorlevel 1 if exist "%MINICONDA_INSTALLER%" exit /b 0
exit /b 1
