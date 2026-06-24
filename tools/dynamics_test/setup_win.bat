@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion

REM ============================================================
REM  Mockway 力矩补偿环境 - Windows 安装脚本
REM  自动安装 Miniconda + Pinocchio 环境（避免 pip 编译卡死）
REM ============================================================

set "ENV_NAME=mockway_dynamics"
set "PYTHON_VER=3.10"
set "PIP_INDEX=https://pypi.tuna.tsinghua.edu.cn/simple"
set "PIP_TRUSTED=pypi.tuna.tsinghua.edu.cn"
set "MINICONDA_DIR=%USERPROFILE%\miniconda3"
set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\..\"

REM Miniconda 安装包下载地址（优先清华镜像，失败则回退官方源）
set "MINICONDA_URL_TSINGHUA=https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Windows-x86_64.exe"
set "MINICONDA_URL_OFFICIAL=https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe"
set "MINICONDA_INSTALLER=%TEMP%\Miniconda3-latest-Windows-x86_64.exe"

echo.
echo ============================================================
echo  Mockway dynamics_test 环境安装 (Windows)
echo ============================================================
echo.

REM ---------- 定位 conda，若无则自动安装 Miniconda ----------
call :FindConda
if not defined CONDA_ACTIVATE (
    echo [0/8] 未检测到 Miniconda / Anaconda，开始自动安装 Miniconda ...
    echo        安装路径: %MINICONDA_DIR%
    call :InstallMiniconda
    if errorlevel 1 (
        echo [错误] Miniconda 自动安装失败。
        pause
        exit /b 1
    )
    call :FindConda
)

if not defined CONDA_ACTIVATE (
    echo [错误] 安装后仍未找到 conda，请手动安装 Miniconda 后重试。
    echo        https://docs.conda.io/en/latest/miniconda.html
    pause
    exit /b 1
)

echo [1/8] 初始化 conda ...
call "%CONDA_ACTIVATE%"
if errorlevel 1 (
    echo [错误] conda 初始化失败。
    pause
    exit /b 1
)

where conda >nul 2>&1
if errorlevel 1 (
    echo [提示] conda 暂不在 PATH 中，使用 Miniconda 内置路径继续 ...
    set "PATH=%MINICONDA_DIR%;%MINICONDA_DIR%\Scripts;%MINICONDA_DIR%\Library\bin;!PATH!"
)

echo [2/8] 配置 conda 国内镜像（清华源，避免 repo.anaconda.com 403）...
call :ConfigureCondaMirror
if errorlevel 1 (
    echo [错误] conda 镜像配置失败。
    pause
    exit /b 1
)

REM ---------- 创建/更新虚拟环境 ----------
echo [3/8] 检查 conda 环境 "%ENV_NAME%" ...
conda env list | findstr /I /C:"%ENV_NAME%" >nul 2>&1
if errorlevel 1 (
    echo        创建新环境 Python %PYTHON_VER% ...
    call conda create -n %ENV_NAME% python=%PYTHON_VER% -y
) else (
    echo        环境已存在，跳过创建。
)
if errorlevel 1 (
    echo [错误] conda 环境创建失败。
    pause
    exit /b 1
)

echo [4/8] 激活环境 ...
call conda activate %ENV_NAME%
if errorlevel 1 (
    echo [错误] 无法激活环境 %ENV_NAME%。
    pause
    exit /b 1
)

REM ---------- 安装 Pinocchio (conda-forge) ----------
echo [5/8] 安装 Pinocchio (conda-forge 清华镜像) ...
call conda install pinocchio -c conda-forge -y
if errorlevel 1 (
    echo        重试: 指定清华 conda-forge 地址 ...
    call conda install pinocchio -c https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge -y
)
if errorlevel 1 (
    echo [错误] Pinocchio 安装失败。
    pause
    exit /b 1
)

REM ---------- pip 安装其余依赖（排除 pin） ----------
echo [6/8] 安装 numpy / matplotlib / pyserial / pyyaml (清华源) ...
python -m pip install --upgrade pip -i %PIP_INDEX% --trusted-host %PIP_TRUSTED%
python -m pip install "numpy>=1.20.0" "matplotlib>=3.3.0" "pyserial>=3.5" "pyyaml>=6.0" ^
    -i %PIP_INDEX% --trusted-host %PIP_TRUSTED%
if errorlevel 1 (
    echo [错误] pip 依赖安装失败。
    pause
    exit /b 1
)

REM ---------- 验证 ----------
echo [7/8] 验证安装 ...
python -c "import pinocchio as pin; import numpy; import matplotlib; import serial; import yaml; print('pinocchio', pin.__version__); print('numpy', numpy.__version__); print('OK')"
if errorlevel 1 (
    echo [错误] 导入测试失败，请检查上方报错。
    pause
    exit /b 1
)

echo [8/8] 全部完成。
echo.
echo ============================================================
echo  安装完成!
echo ============================================================
echo.
echo  每次使用前执行（CMD 或 Anaconda Prompt）:
echo    %MINICONDA_DIR%\Scripts\activate.bat
echo    conda activate %ENV_NAME%
echo.
echo  编辑 CAN 配置:
echo    %SCRIPT_DIR%dynamics_test.yaml
echo.
echo  运行力矩补偿:
echo    cd /d %SCRIPT_DIR%
echo    python realtime_torque_compensation.py
echo.
echo  运行 motor_gui (同一环境也可):
echo    cd /d %REPO_ROOT%tools\motor_gui
echo    python motor_gui.py
echo.
pause
exit /b 0

REM ============================================================
REM  子程序: 查找已有 conda / anaconda 安装
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
REM  子程序: 下载并静默安装 Miniconda
REM ============================================================
:InstallMiniconda
if exist "%MINICONDA_DIR%\Scripts\activate.bat" (
    echo        检测到 %MINICONDA_DIR% 已存在，跳过安装。
    exit /b 0
)

echo        下载 Miniconda 安装包（清华镜像）...
call :DownloadMiniconda "%MINICONDA_URL_TSINGHUA%"
if errorlevel 1 (
    echo        清华镜像失败，尝试官方源 ...
    call :DownloadMiniconda "%MINICONDA_URL_OFFICIAL%"
)
if errorlevel 1 (
    echo [错误] 无法下载 Miniconda 安装包，请检查网络或手动下载:
    echo        %MINICONDA_URL_TSINGHUA%
    exit /b 1
)

if not exist "%MINICONDA_INSTALLER%" (
    echo [错误] 安装包不存在: %MINICONDA_INSTALLER%
    exit /b 1
)

echo        静默安装 Miniconda（约 1~3 分钟）...
start /wait "" "%MINICONDA_INSTALLER%" /InstallationType=JustMe /RegisterPython=0 /AddToPath=1 /S /D=%MINICONDA_DIR%
if errorlevel 1 (
    echo [错误] Miniconda 安装程序返回错误。
    exit /b 1
)

if not exist "%MINICONDA_DIR%\Scripts\activate.bat" (
    echo [错误] 安装完成但未找到 %MINICONDA_DIR%\Scripts\activate.bat
    exit /b 1
)

echo        Miniconda 安装成功: %MINICONDA_DIR%
del /f /q "%MINICONDA_INSTALLER%" >nul 2>&1
exit /b 0

REM ============================================================
REM  子程序: 配置 conda 清华镜像（解决 HTTP 403 Forbidden）
REM ============================================================
:ConfigureCondaMirror
set "CONDA_RC=%MINICONDA_DIR%\.condarc"
echo        写入 %CONDA_RC%
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
echo        镜像已配置，索引已刷新。
exit /b 0

REM ============================================================
REM  子程序: 下载文件 (curl 优先，PowerShell 备用)
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
