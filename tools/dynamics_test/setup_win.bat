@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

REM ============================================================
REM  Mockway 力矩补偿环境 - Windows 管理脚本
REM  菜单: 1 安装环境  2 启动环境  3 停止环境
REM ============================================================

set "ENV_NAME=mockway_dynamics"
set "ENV_WINDOW_TITLE=Mockway-%ENV_NAME%"
set "PYTHON_VER=3.10"
set "PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple"
set "PIP_TRUSTED=pypi.tuna.tsinghua.edu.cn"
set "MINICONDA_DIR=%USERPROFILE%\miniconda3"
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\..\"

set "MINICONDA_URL_TSINGHUA=https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Windows-x86_64.exe"
set "MINICONDA_URL_OFFICIAL=https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
set "MINICONDA_INSTALLER=%TEMP%\Miniconda3-latest-Windows-x86_64.exe"

REM 首次运行且无参数时进入菜单；支持 setup / start / stop 命令行参数
if /I "%~1"=="setup" goto DoSetup
if /I "%~1"=="start" goto DoStart
if /I "%~1"=="stop" goto DoStop

:MainMenu
cls
echo.
echo ============================================================
echo  Mockway dynamics_test 环境管理 (Windows)
echo ============================================================
echo.
call :ShowEnvStatus
echo.
echo  [1] 安装 / 更新环境 (Miniconda + Pinocchio + 依赖)
echo  [2] 启动环境 (conda activate %ENV_NAME%)
echo  [3] 停止环境 (conda deactivate + 关闭工作窗口)
echo  [0] 退出
echo.
set "MENU_CHOICE="
set /p MENU_CHOICE=请选择 [0-3]:
if "%MENU_CHOICE%"=="1" goto DoSetup
if "%MENU_CHOICE%"=="2" goto DoStart
if "%MENU_CHOICE%"=="3" goto DoStop
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
echo  [1/1] 安装 / 更新 %ENV_NAME% 环境
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
set "MOCKWAY_ENV_ACTIVE=1"
echo.
echo ============================================================
echo  环境 %ENV_NAME% 已就绪，当前窗口已激活该环境。
echo ============================================================
echo.
echo  配置文件: %SCRIPT_DIR%dynamics_test.yaml
echo  力矩补偿: python realtime_torque_compensation.py
echo  motor_gui: cd %REPO_ROOT%tools\motor_gui ^&^& python motor_gui.py
echo.
echo  提示: 菜单选 [2] 可另开工作窗口；选 [3] 可停止环境。
echo.
pause
goto MainMenu

:SetupFailed
echo.
echo [错误] 安装失败，请查看上方报错。
pause
goto MainMenu

REM ============================================================
REM  [2] 启动环境
REM ============================================================
:DoStart
call :FindConda
if not defined CONDA_ACTIVATE (
    echo [错误] 未找到 conda，请先选 [1] 安装环境。
    pause
    if /I not "%~1"=="start" goto MainMenu
    exit /b 1
)

call :InitCondaBase
if errorlevel 1 (
    pause
    if /I not "%~1"=="start" goto MainMenu
    exit /b 1
)

conda env list | findstr /I /C:"%ENV_NAME%" >nul 2>&1
if errorlevel 1 (
    echo [错误] 环境 %ENV_NAME% 不存在，请先选 [1] 安装。
    pause
    if /I not "%~1"=="start" goto MainMenu
    exit /b 1
)

echo [启动] 激活 conda 环境 %ENV_NAME% ...
call conda activate %ENV_NAME%
if errorlevel 1 (
    echo [错误] 无法激活环境。
    pause
    if /I not "%~1"=="start" goto MainMenu
    exit /b 1
)
set "MOCKWAY_ENV_ACTIVE=1"

echo [启动] 打开独立工作窗口 ...
start "%ENV_WINDOW_TITLE%" /D "%SCRIPT_DIR%" cmd /c open_env_shell.bat

echo.
echo  环境已启动:
echo    - 本管理窗口: conda 环境 %ENV_NAME% 已激活
echo    - 新工作窗口: 标题 "%ENV_WINDOW_TITLE%"
echo.
if /I "%~1"=="start" exit /b 0
pause
goto MainMenu

REM ============================================================
REM  [3] 停止环境
REM ============================================================
:DoStop
echo [停止] 正在停用环境 ...

if defined MOCKWAY_ENV_ACTIVE (
    call conda deactivate >nul 2>&1
    set "MOCKWAY_ENV_ACTIVE="
    echo        本窗口: conda deactivate 完成
) else (
    echo        本窗口: 当前未标记为已激活
)

REM 尝试关闭由 [2] 打开的工作窗口
taskkill /FI "WINDOWTITLE eq %ENV_WINDOW_TITLE%*" /T /F >nul 2>&1
if not errorlevel 1 (
    echo        工作窗口 "%ENV_WINDOW_TITLE%" 已关闭
) else (
    echo        未找到运行中的工作窗口（可能已手动关闭）
)

echo.
echo  环境 %ENV_NAME% 已停止。
echo.
if /I "%~1"=="stop" exit /b 0
pause
goto MainMenu

:DoExit
if defined MOCKWAY_ENV_ACTIVE (
    echo 正在退出并停用环境 ...
    call :DoStop
)
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
    exit /b 0
)
call :InitCondaBase >nul 2>&1
conda env list | findstr /I /C:"%ENV_NAME%" >nul 2>&1
if errorlevel 1 (
    echo  状态: conda 已安装，环境 %ENV_NAME% 未创建
) else (
    if defined MOCKWAY_ENV_ACTIVE (
        echo  状态: 环境 %ENV_NAME% 存在，本窗口【已激活】
    ) else (
        echo  状态: 环境 %ENV_NAME% 存在，本窗口【未激活】
    )
)
tasklist /FI "WINDOWTITLE eq %ENV_WINDOW_TITLE%*" 2>nul | findstr /I "cmd.exe" >nul 2>&1
if not errorlevel 1 (
    echo  工作窗口: 【运行中】 %ENV_WINDOW_TITLE%
) else (
    echo  工作窗口: 【未运行】
)
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
