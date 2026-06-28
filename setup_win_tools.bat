@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

REM ============================================================
REM  Mockway Windows + WSL 统一环境管理
REM  Ubuntu 对应: setup_ubuntu.sh
REM ============================================================

set "ENV_NAME=mockway_dynamics"
set "PYTHON_VER=3.10"
set "PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple"
set "PIP_TRUSTED=pypi.tuna.tsinghua.edu.cn"
set "MINICONDA_DIR=%USERPROFILE%\miniconda3"
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%"
set "MOTOR_GUI_DIR=%SCRIPT_DIR%tools\motor_gui\"
set "DYNAMICS_TEST_DIR=%SCRIPT_DIR%tools\dynamics_test\"
set "LOG=%TEMP%\mockway_wsl_setup.log"
set "DISTRO=Ubuntu-24.04"
set "WSL_USER=test"

set "TITLE_SHELL=Mockway-Shell"
set "TITLE_MOTOR_GUI=Mockway-motor_gui"
set "TITLE_TORQUE=Mockway-torque"
set "TITLE_INVERSE=Mockway-inverse"

set "MINICONDA_URL_TSINGHUA=https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Windows-x86_64.exe"
set "MINICONDA_URL_OFFICIAL=https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
set "MINICONDA_INSTALLER=%TEMP%\Miniconda3-latest-Windows-x86_64.exe"

title Mockway Windows + WSL

if /I "%~1"=="admin" goto AdminRunner
if /I "%~1"=="demo" (
    set "MOCKWAY_NO_MENU=1"
    set "MENU_CHOICE=3"
    goto WslDispatch
)
if /I "%~1"=="moveit-demo" (
    set "MOCKWAY_NO_MENU=1"
    set "MENU_CHOICE=3"
    goto WslDispatch
)
if /I "%~1"=="desktop" (
    set "MOCKWAY_NO_MENU=1"
    set "MENU_CHOICE=9"
    goto WslDispatch
)
if /I "%~1"=="wsl" (
    set "MENU_CHOICE=%~2"
    goto WslDispatch
)
if "%~1"=="11" goto DoFullInstall
if "%~1"=="12" goto DoInstallDeps
if "%~1"=="13" goto DoLaunchDemo
if "%~1"=="14" goto DoWslShell
if "%~1"=="15" goto DoFixHypervisor
if "%~1"=="16" goto DoUsbAttach
if "%~1"=="17" goto DoSkipWslInstall
if "%~1"=="18" goto DoUsbDetach
if "%~1"=="19" goto DoUbuntuDesktop
if "%~1"=="20" goto DoWslMotorGui
if /I "%~1"=="setup" goto DoSetup
if /I "%~1"=="motor_gui" goto DoMotorGui
if /I "%~1"=="motor_gui-wsl" goto DoWslMotorGui
if /I "%~1"=="wsl-motor_gui" goto DoWslMotorGui
if /I "%~1"=="torque" goto DoTorque
if /I "%~1"=="inverse" goto DoInverse
if /I "%~1"=="shell" goto DoShell
if /I "%~1"=="start" goto DoShell
if /I "%~1"=="stop" goto DoStop
goto MainMenu

:MainMenu
cls
echo.
echo ============================================================
echo  Mockway 开发环境管理 — Windows + WSL
echo ============================================================
echo.
call :ShowEnvStatus
echo.
echo  --- Windows Python 工具 ---
echo  [1] 安装 / 更新环境 — Miniconda + Pinocchio + 依赖
echo  [2] 启动 motor_gui — 电机调试
echo  [3] 启动 实时力矩补偿 — realtime_torque_compensation
echo  [4] 启动 离线动力学测试 — inverse_dynamics_test
echo  [5] 打开 Python 工作 shell
echo  [6] 停止 — 关闭工具窗口
echo.
echo  --- WSL2 / MoveIt2 ---
call :ResolveDistro >nul 2>&1
call :ResolveWslUser >nul 2>&1
echo  发行版: %DISTRO%    用户: %WSL_USER%    日志: %LOG%
echo  [11] 完整安装 — WSL2 + Ubuntu + MoveIt2 + usbipd  [需管理员]
echo  [12] 仅装 WSL 内依赖 — ROS2 Jazzy + MoveIt2 + mockway_ws
echo  [13] 启动 MoveIt2 Demo — RViz
echo  [14] 打开 WSL 工作 Shell
echo  [15] 修复 WSL 0x80370114 — Hypervisor / vmcompute  [需管理员]
echo  [16] USB-CAN 透传到 WSL  [需管理员]
echo  [17] 跳过 WSL 安装，仅配置 MoveIt/usbipd  [需管理员]
echo  [18] 断开 USB 透传 — COM 归还 Windows  [需管理员]
echo  [19] 启动 Ubuntu 图形桌面 — XFCE / WSLg
echo  [20] 启动 motor_gui — WSLg 图形界面  [需 WSL setup + USB 透传]
echo.
echo  [0] 退出
echo.
set "MENU_CHOICE="
set /p MENU_CHOICE=请选择 [0-20]:
if "%MENU_CHOICE%"=="1" goto DoSetup
if "%MENU_CHOICE%"=="2" goto DoMotorGui
if "%MENU_CHOICE%"=="3" goto DoTorque
if "%MENU_CHOICE%"=="4" goto DoInverse
if "%MENU_CHOICE%"=="5" goto DoShell
if "%MENU_CHOICE%"=="6" goto DoStop
if "%MENU_CHOICE%"=="11" goto DoFullInstall
if "%MENU_CHOICE%"=="12" goto DoInstallDeps
if "%MENU_CHOICE%"=="13" goto DoLaunchDemo
if "%MENU_CHOICE%"=="14" goto DoWslShell
if "%MENU_CHOICE%"=="15" goto DoFixHypervisor
if "%MENU_CHOICE%"=="16" goto DoUsbAttach
if "%MENU_CHOICE%"=="17" goto DoSkipWslInstall
if "%MENU_CHOICE%"=="18" goto DoUsbDetach
if "%MENU_CHOICE%"=="19" goto DoUbuntuDesktop
if "%MENU_CHOICE%"=="20" goto DoWslMotorGui
if "%MENU_CHOICE%"=="0" goto DoExit
echo 无效选择，请重试。
timeout /t 2 >nul
goto MainMenu

:WslDispatch
if /I "%MENU_CHOICE%"=="demo" goto DoLaunchDemo
if /I "%MENU_CHOICE%"=="moveit-demo" goto DoLaunchDemo
if /I "%MENU_CHOICE%"=="desktop" goto DoUbuntuDesktop
if "%MENU_CHOICE%"=="1" goto DoFullInstall
if "%MENU_CHOICE%"=="2" goto DoInstallDeps
if "%MENU_CHOICE%"=="3" goto DoLaunchDemo
if "%MENU_CHOICE%"=="4" goto DoWslShell
if "%MENU_CHOICE%"=="5" goto DoFixHypervisor
if "%MENU_CHOICE%"=="6" goto DoUsbAttach
if "%MENU_CHOICE%"=="7" goto DoSkipWslInstall
if "%MENU_CHOICE%"=="8" goto DoUsbDetach
if "%MENU_CHOICE%"=="9" goto DoUbuntuDesktop
echo [错误] 无效 WSL 选项: %MENU_CHOICE%
exit /b 1

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

echo [5/8] 安装 Pinocchio — conda-forge ...
call conda install pinocchio -c conda-forge -y
if errorlevel 1 (
    echo        重试清华 conda-forge 镜像 ...
    call conda install pinocchio -c https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge -y
)
if errorlevel 1 goto SetupFailed

echo [6/8] 安装 pip 依赖 — numpy / matplotlib / pyserial / pyyaml ...
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
echo  工作 shell 已打开 — 窗口标题: %TITLE_SHELL%
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

:DoExit
exit /b 0

:CheckEnvReady
call :FindConda
if not defined CONDA_ACTIVATE (
    echo [错误] 未找到 conda，请先选 [11] 安装环境。
    pause
    exit /b 1
)
call :InitCondaBase >nul 2>&1
conda env list | findstr /I /C:"%ENV_NAME%" >nul 2>&1
if errorlevel 1 (
    echo [错误] 环境 %ENV_NAME% 不存在，请先选 [11] 安装。
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
if not errorlevel 1 (
    echo        已关闭 — %KILL_TITLE%
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
if "!SHELL_RUNNING!"=="1" (
    echo  工作 shell — 运行中
)
if "!GUI_RUNNING!"=="1" (
    echo  motor_gui — 运行中
)
if "!TORQUE_RUNNING!"=="1" (
    echo  力矩补偿 — 运行中
)
if "!INVERSE_RUNNING!"=="1" (
    echo  离线动力学 — 运行中
)
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
echo  WSL 内安装 Mockway 依赖 — ROS2 Jazzy + MoveIt2
echo  发行版: %DISTRO%    用户: %WSL_USER%
echo ============================================================
echo.
if /I "%WSL_USER%"=="test" (
    wsl -d %DISTRO% -u root -- bash -lc "echo 'test ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-mockway-test && chmod 440 /etc/sudoers.d/99-mockway-test" 2>nul
)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "[Console]::OutputEncoding=[Text.Encoding]::UTF8; $OutputEncoding=[Text.Encoding]::UTF8; $repo=(Resolve-Path '%REPO_ROOT%').Path; if($repo -match '^([A-Za-z]):\\(.*)$'){ $wsl='/mnt/'+$matches[1].ToLower()+'/'+$matches[2].Replace('\','/') } else { throw 'bad repo path' }; $sh=$wsl+'/setup_ubuntu.sh'; wsl -d %DISTRO% -u %WSL_USER% -- env ('MOCKWAY_REPO_WSL='+$wsl) LANG=C.UTF-8 LC_ALL=C.UTF-8 bash $sh moveit-install; exit $LASTEXITCODE"
set "RC=!ERRORLEVEL!"
if "!RC!"=="0" (
    echo [完成] 依赖已安装。菜单选 [13] 启动 MoveIt Demo。
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
echo.
net session >nul 2>&1
if not errorlevel 1 (
    echo [警告] 当前是管理员命令行 — WSLg 图形窗口常会空白或无法显示。
    echo 请改用以下任一方式启动 RViz:
    echo   1. 普通 CMD: setup_win_tools.bat demo
    echo   2. 普通 CMD: setup_win_tools.bat 13
    echo.
    echo 正在尝试通过 explorer 以普通权限启动 ...
    explorer.exe "%~f0" demo
    set "RC=0"
    goto AfterAction
)
echo [mockway] 启动 MoveIt2 Demo — 真机 + USB-CAN，请先运行菜单 [16] 透传 USB ...
call :WinToWslPath "%SCRIPT_DIR%setup_ubuntu.sh"
if errorlevel 1 (
    set "RC=1"
    goto AfterAction
)
if /I not "%WSL_USER%"=="root" (
    wsl -d %DISTRO% -u %WSL_USER% -- bash -lc "sed 's/\r$//' '!_WSL_PATH!' | bash -s moveit-demo"
) else (
    wsl -d %DISTRO% -- bash -lc "sed 's/\r$//' '!_WSL_PATH!' | bash -s moveit-demo"
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
echo  USB-CAN 透传到 WSL2 — 需管理员
echo  请先插入 USB-CAN 适配器
if not "%~2"=="" (
    echo  指定 BusId: %~2
    set "MOCKWAY_USB_BUSID=%~2"
) else (
    set "MOCKWAY_USB_BUSID="
)
echo  也可: setup_win_tools.bat 16 5-1
echo ============================================================
echo.
call :RunAdminPs1 "usb"
set "RC=!ERRORLEVEL!"
set "MOCKWAY_USB_BUSID="
goto AfterAction

REM ============================================================
REM  [8] 断开 USB 透传
REM ============================================================
:DoUsbDetach
echo.
echo ============================================================
echo  断开 USB 透传 — WSL 到 Windows
if not "%~2"=="" (
    echo  指定 BusId: %~2
    set "MOCKWAY_USB_BUSID=%~2"
) else (
    set "MOCKWAY_USB_BUSID="
)
if /I "%~3"=="unbind" set "MOCKWAY_USB_UNBIND=1"
echo  用法: setup_win_tools.bat 18 [BusId] [unbind]
echo ============================================================
echo.
call :RunAdminPs1 "usb_detach"
set "RC=!ERRORLEVEL!"
set "MOCKWAY_USB_BUSID="
set "MOCKWAY_USB_UNBIND="
goto AfterAction

REM ============================================================
REM  [9] Ubuntu 图形桌面 (XFCE + WSLg)
REM ============================================================
:DoUbuntuDesktop
call :ResolveDistro
if errorlevel 1 goto AfterAction
call :ResolveWslUser
echo.
net session >nul 2>&1
if not errorlevel 1 (
    echo [警告] 管理员 CMD 下 WSLg 桌面常无法显示。
    echo 请用普通 CMD 运行: setup_win_tools.bat desktop
    echo 正在通过 explorer 以普通权限启动 ...
    explorer.exe "%~f0" desktop
    set "RC=0"
    goto AfterAction
)
echo [mockway] 启动 Ubuntu 图形桌面 XFCE — WSL: %DISTRO%, user: %WSL_USER% ...
call :WinToWslPath "%SCRIPT_DIR%setup_ubuntu.sh"
if errorlevel 1 (
    set "RC=1"
    goto AfterAction
)
if /I not "%WSL_USER%"=="root" (
    wsl -d %DISTRO% -u %WSL_USER% -- bash -lc "sed 's/\r$//' '!_WSL_PATH!' | bash -s desktop"
) else (
    wsl -d %DISTRO% -- bash -lc "sed 's/\r$//' '!_WSL_PATH!' | bash -s desktop"
)
set "RC=!ERRORLEVEL!"
if defined MOCKWAY_NO_MENU (
    echo.
    echo 若任务栏出现 XFCE 面板/桌面即成功。在桌面终端中可运行 ./setup_ubuntu.sh
)
goto AfterAction

REM ============================================================
REM  [20] WSLg 下启动 motor_gui
REM ============================================================
:DoWslMotorGui
call :ResolveDistro
if errorlevel 1 goto AfterAction
call :ResolveWslUser
echo.
net session >nul 2>&1
if not errorlevel 1 (
    echo [警告] 管理员 CMD 下 WSLg 图形窗口常无法显示。
    echo 请用普通 CMD 运行: setup_win_tools.bat 20
    echo 正在通过 explorer 以普通权限启动 ...
    explorer.exe "%~f0" 20
    set "RC=0"
    goto AfterAction
)
echo [mockway] 在 WSLg 中启动 motor_gui — WSL: %DISTRO%, user: %WSL_USER%
echo           请先 [16] 透传 USB-CAN；WSL 内需已运行 ./setup_ubuntu.sh setup
call :WinToWslPath "%SCRIPT_DIR%setup_ubuntu.sh"
if errorlevel 1 (
    set "RC=1"
    goto AfterAction
)
if /I not "%WSL_USER%"=="root" (
    wsl -d %DISTRO% -u %WSL_USER% -- bash -lc "sed 's/\r$//' '!_WSL_PATH!' | bash -s motor_gui-wslg"
) else (
    wsl -d %DISTRO% -- bash -lc "sed 's/\r$//' '!_WSL_PATH!' | bash -s motor_gui-wslg"
)
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
    echo [下一步] WSL 已启用，请先重启 Windows，再运行本菜单 [11] 或 [12]
) else if not "!_RC!"=="0" (
    echo [错误] 安装失败，退出码 !_RC!
    echo 请查看日志: %LOG%
) else (
    echo [完成] 安装成功
    echo  菜单 [13] 启动 MoveIt Demo
    echo  菜单 [14] 打开 WSL Shell
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
echo [错误] 未找到 WSL Ubuntu。请先选 [11] 完整安装。
exit /b 1

:ResolveWslUser
set "WSL_USER=test"
wsl -d %DISTRO% -u test -- true >nul 2>&1 && exit /b 0
set "WSL_USER=root"
exit /b 0

:WinToWslPath
set "_WSL_PATH="
set "WIN_TMP=%~1"
set "WIN_TMP=!WIN_TMP:\=/!"
for /f "usebackq delims=" %%P in (`wsl wslpath -u "!WIN_TMP!" 2^>nul`) do set "_WSL_PATH=%%P"
if not defined _WSL_PATH (
    echo [错误] 无法转换 WSL 路径: %~1
    exit /b 1
)
exit /b 0

REM ============================================================
REM  操作结束
REM ============================================================
:AfterAction
if not defined RC set "RC=0"
echo.
pause
if defined MOCKWAY_NO_MENU exit /b %RC%
if "%~1"=="" goto MainMenu
exit /b %RC%

goto :EOF

::#MOCKWAY_PS1
#Requires -Version 5.1
$ErrorActionPreference = "Stop"
$Mode = if ($env:MOCKWAY_PS_MODE) { $env:MOCKWAY_PS_MODE } else { "full" }
$ScriptDir = $env:MOCKWAY_TOOLS_DIR
$RepoRoot = (Resolve-Path $ScriptDir).Path
$WslScript = Join-Path $ScriptDir "setup_ubuntu.sh"
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
        throw "Administrator required. Right-click tools\setup_win_tools.bat -> Run as administrator"
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
    Write-Host "   tools\setup_win_tools.bat menu [5]"
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
        Write-Host "  5. Re-run: tools\setup_win_tools.bat menu [5]"
        Write-Host "  6. Then: wsl --install -d Ubuntu-24.04"
        throw "Hypervisor repair incomplete: vmcompute.exe still missing"
    } elseif ($rebootNeeded) {
        Write-Warn "Reboot required, then run:"
        Write-Host "  tools\setup_win_tools.bat"
    } else {
        Write-Ok "Repair complete. Try:"
        Write-Host "  wsl --install -d Ubuntu-24.04"
        Write-Host "  or tools\setup_win_tools.bat menu [7]"
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
    Write-Host "  2. Run again: tools\setup_win_tools.bat"
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
        Write-Host "    tools\setup_win_tools.bat menu [7]"
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
    & wsl.exe -d $Name -u $wslUser -- env "MOCKWAY_REPO_WSL=$RepoWsl" LANG=C.UTF-8 LC_ALL=C.UTF-8 bash "$bashPath" moveit-install
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Host ""
        Write-Warn "WSL install exited with code $exitCode"
        Write-Host "  Try manually in WSL:"
        Write-Host "  env MOCKWAY_REPO_WSL=$RepoWsl bash $bashPath moveit-install"
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

function Get-UsbipdDeviceRows {
    $rows = @()
    $section = ""
    foreach ($line in ((usbipd list | Out-String) -split "`r?`n")) {
        if ($line -match '(?i)^Connected:\s*$') { $section = "Connected"; continue }
        if ($line -match '(?i)^Persisted:\s*$') { $section = "Persisted"; continue }
        if ($line -match '(?i)^BUSID\s') { continue }
        if ($line -match '(?i)^GUID\s') { continue }
        if ($line -match '^\s*(\d+-\d+)\s+([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\s+(.+?)\s{2,}(Not shared|Attached|Shared)\s*$') {
            $rows += [PSCustomObject]@{
                BusId   = $Matches[1]
                VidPid  = $Matches[2]
                Device  = $Matches[3].Trim()
                State   = $Matches[4]
                Section = $section
            }
        }
    }
    return $rows
}

function Get-UsbipdDeviceState {
    param([string]$BusId)
    $row = Get-UsbipdDeviceRows | Where-Object { $_.BusId -eq $BusId } | Select-Object -First 1
    if ($row) { return $row.State }
    return $null
}

function Invoke-UsbipdCli {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgs)
    $argLine = 'usbipd ' + ($CliArgs -join ' ')
    $out = @(cmd /c "$argLine 2>&1")
    @{ Output = ($out -join "`n").Trim(); ExitCode = $LASTEXITCODE }
}

function Invoke-UsbipdBindSafe {
    param([string]$BusId)

    $state = Get-UsbipdDeviceState $BusId
    if ($state -match '^(Shared|Attached)$') {
        Write-Host "[usb] Device $BusId already $state, skipping bind"
        return
    }

    Write-Host "[usb] bind $BusId ..."
    $bind = Invoke-UsbipdCli 'bind', '--busid', $BusId
    if ($bind.Output) { Write-Host "  $($bind.Output)" }
    if ($bind.ExitCode -ne 0) {
        if ($bind.Output -match 'already shared') {
            Write-Warn "Device already shared, continuing ..."
            return
        }
        throw "usbipd bind failed: $($bind.Output)"
    }
}

function Invoke-UsbipdAttachSafe {
    param(
        [string]$BusId,
        [string]$Distro
    )

    $state = Get-UsbipdDeviceState $BusId
    if ($state -eq 'Attached') {
        Write-Host "[usb] Device $BusId already Attached to WSL, skipping attach"
        return
    }

    Write-Host "[usb] Waking WSL ($Distro) ..."
    wsl -d $Distro -- true 2>$null | Out-Null

    Write-Host "[usb] attach to WSL ..."
    $attempts = @(
        @('attach', '-w', '-b', $BusId),
        @('attach', '--wsl', '--busid', $BusId),
        @('attach', '--wsl', $Distro, '--busid', $BusId),
        @('attach', '--wsl', '--busid', $BusId, '--distribution', $Distro)
    )

    $attachOk = $false
    $lastOut = ""
    foreach ($tryArgs in $attempts) {
        $result = Invoke-UsbipdCli @tryArgs
        if ($result.Output) {
            Write-Host ($result.Output -split "`n" | ForEach-Object { "  $_" })
        }
        $lastOut = $result.Output
        if ($result.ExitCode -eq 0 -or $lastOut -match 'already attached|Using WSL distribution|Loading vhci_hcd') {
            $attachOk = $true
            break
        }
    }

    Start-Sleep -Seconds 2
    $state = Get-UsbipdDeviceState $BusId
    if ($state -eq 'Attached') {
        Write-Ok "usbipd state: Attached"
    } elseif (-not $attachOk) {
        throw "usbipd attach failed: $lastOut"
    } else {
        Write-Warn "attach finished but usbipd state is: $state (expected Attached)"
    }
}

function Show-WslUsbSerialDevices {
    param([string]$Distro)

    $checkScript = Join-Path $ScriptDir "setup_ubuntu.sh"
    if (-not (Test-Path $checkScript)) {
        Write-Warn "Missing script: $checkScript"
        return
    }
    $winPath = ($checkScript -replace '\\', '/')
    $wslPath = (cmd /c "wsl wslpath -u `"$winPath`"" 2>&1 | Out-String).Trim()
    if (-not $wslPath) {
        Write-Warn "Could not resolve WSL path for setup_ubuntu.sh"
        return
    }
    wsl -d $Distro -u test -- bash -lc "sed 's/\r$//' '$wslPath' | bash -s usb-check"
}

function Select-UsbCanBusId {
    param([string]$PreferredBusId = "")

    if ($PreferredBusId -match '^\s*(\d+-\d+)\s*$') {
        return $Matches[1]
    }

    $exclude = @('Webcam', 'Camera', 'Bluetooth', 'Keyboard', 'Mouse', 'HID', 'DFU', 'RZ608', '输入设备', '输入')
    $highKw = @(
        'USB-CAN', 'USBCAN', 'CH340', 'CH341', 'CH342', 'CH343',
        'CP210', 'FTDI', 'WCH', '2e88', '1a86', '10c4',
        'Damiao', 'WitMotion', 'Enhanced-SERIAL', 'SERIAL CH'
    )
    $medKw = @('Serial', 'SERIAL', '串行', '串口', 'COM')

    $scored = @()
    foreach ($row in (Get-UsbipdDeviceRows | Where-Object { $_.Section -eq "Connected" })) {
        $skip = $false
        foreach ($ex in $exclude) {
            if ($row.Device -like "*$ex*") { $skip = $true; break }
        }
        if ($skip) { continue }

        $score = 0
        $text = "$($row.Device) $($row.VidPid)"
        foreach ($kw in $highKw) {
            if ($text -match [regex]::Escape($kw)) { $score += 10 }
        }
        foreach ($kw in $medKw) {
            if ($text -match [regex]::Escape($kw)) { $score += 5 }
        }
        if ($row.Device -match '\(COM\d+\)') { $score += 3 }

        if ($score -gt 0) {
            $scored += [PSCustomObject]@{
                BusId  = $row.BusId
                Device = $row.Device
                VidPid = $row.VidPid
                Score  = $score
            }
        }
    }

    if ($scored.Count -eq 0) { return $null }

    $best = $scored | Sort-Object Score -Descending | Select-Object -First 1
    Write-Host "[usb] Auto-selected: $($best.BusId)  $($best.Device)  ($($best.VidPid), score $($best.Score))"
    return $best.BusId
}

function Invoke-UsbAttachCore {
    param(
        [string]$Distro = "Ubuntu-24.04",
        [string]$BusId = "",
        [switch]$ListOnly
    )

    if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
        throw "usbipd not found. Run tools\setup_win_tools.bat menu [6] as administrator"
    }

    Write-Host ""
    Write-Host "=== USB devices (usbipd list) ==="
    usbipd list
    Write-Host ""

    if ($ListOnly) { return }

    if (-not $BusId -and $env:MOCKWAY_USB_BUSID) {
        $BusId = $env:MOCKWAY_USB_BUSID.Trim()
    }

    if (-not $BusId) {
        $BusId = Select-UsbCanBusId
    }

    if (-not $BusId) {
        Write-Host ""
        Write-Host "No USB-CAN auto-detected. Pick BusId from Connected list above."
        Write-Host "Example for USB serial / CAN adapter on COM5: 5-1"
        Write-Host "Or run: tools\setup_win_tools.bat 6 5-1"
        $manual = Read-Host "Enter BusId (blank to cancel)"
        if ($manual -match '^\s*(\d+-\d+)\s*$') {
            $BusId = $Matches[1]
        }
    }

    if (-not $BusId) {
        throw "No USB-CAN device selected"
    }

    Invoke-UsbipdBindSafe -BusId $BusId
    Invoke-UsbipdAttachSafe -BusId $BusId -Distro $Distro

    Write-Host ""
    Write-Host "=== Serial devices in WSL ==="
    Show-WslUsbSerialDevices -Distro $Distro

    Write-Host ""
    Write-Host "Real robot CAN port in xacro is usually /dev/ttyUSB0 or /dev/ttyACM0"
    Write-Host "If no device node: close Windows apps using COM5, re-run menu [6]"
    Write-Host "To release COM back to Windows: menu [8] or tools\setup_win_tools.bat 8"
    Write-Host "If permission denied in WSL: sudo chmod 666 /dev/ttyUSB0"
    Write-Host "Or: sudo usermod -aG dialout `$USER  (restart WSL)"
}

function Invoke-UsbAttach {
    param([string]$Name)
    Invoke-UsbAttachCore -Distro $Name
}

function Invoke-UsbDetachCore {
    param([string]$BusId = "")

    if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
        throw "usbipd not found. Run tools\setup_win_tools.bat menu [8] as administrator"
    }

    Write-Host ""
    Write-Host "=== USB devices (usbipd list) ==="
    usbipd list
    Write-Host ""

    if (-not $BusId -and $env:MOCKWAY_USB_BUSID) {
        $BusId = $env:MOCKWAY_USB_BUSID.Trim()
    }

    $targets = @()
    if ($BusId) {
        $targets = @($BusId)
    } else {
        $attached = Get-UsbipdDeviceRows | Where-Object {
            $_.Section -eq 'Connected' -and $_.State -eq 'Attached'
        }
        if ($attached.Count -eq 0) {
            Write-Warn "No Attached devices. Nothing to detach."
            return
        }
        foreach ($row in $attached) {
            Write-Host "[usb] Found Attached: $($row.BusId)  $($row.Device)"
            $targets += $row.BusId
        }
        $targets = $targets | Select-Object -Unique
    }

    $doUnbind = ($env:MOCKWAY_USB_UNBIND -eq '1')
    if (-not $doUnbind -and -not $BusId -and -not $env:MOCKWAY_USB_BUSID) {
        $ans = Read-Host "Also unbind (release COM port to Windows)? [y/N]"
        if ($ans -match '^[Yy]') { $doUnbind = $true }
    }

    foreach ($id in $targets) {
        $state = Get-UsbipdDeviceState $id
        if ($state -eq 'Attached') {
            Write-Host "[usb] detach $id ..."
            $r = Invoke-UsbipdCli 'detach', '--busid', $id
            if ($r.Output) { Write-Host "  $($r.Output)" }
            if ($r.ExitCode -ne 0 -and $r.Output -notmatch 'not attached|already detached') {
                Write-Warn "detach $id returned exit $($r.ExitCode)"
            }
        } else {
            Write-Warn "Device $id state is '$state', skip detach"
        }

        if ($doUnbind) {
            $state = Get-UsbipdDeviceState $id
            if ($state -match '^(Shared|Attached)$') {
                Write-Host "[usb] unbind $id (release to Windows) ..."
                $r = Invoke-UsbipdCli 'unbind', '--busid', $id
                if ($r.Output) { Write-Host "  $($r.Output)" }
                if ($r.ExitCode -ne 0 -and $r.Output -notmatch 'not shared|already unbound') {
                    Write-Warn "unbind $id returned exit $($r.ExitCode)"
                }
            }
        }
    }

    Write-Host ""
    Write-Host "=== USB devices after detach ==="
    usbipd list
    Write-Host ""
    Write-Ok "Done. Windows COM port should be available if unbind was selected."
    Write-Host "Re-attach to WSL: tools\setup_win_tools.bat 6 [BusId]"
}

function Invoke-UsbDetach {
    Invoke-UsbDetachCore
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

if ($Mode -eq 'usb_detach') {
    try {
        Require-Admin
        Write-Host ""
        Write-Host "============================================================"
        Write-Host " Detach USB from WSL (return to Windows)"
        Write-Host "============================================================"
        Invoke-UsbDetach
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
    Write-Host "  tools\setup_win_tools.bat menu [6]"

    Write-Host ""
    Write-Host "============================================================"
    Write-Host " Done"
    Write-Host "============================================================"
    Write-Host " MoveIt demo:     tools\setup_win_tools.bat menu [3]  (real robot; run [6] USB attach first)"
    Write-Host " WSL shell:       tools\setup_win_tools.bat menu [4]"
    Write-Host " USB attach:      tools\setup_win_tools.bat menu [6]"
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
