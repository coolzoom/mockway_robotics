#!/usr/bin/env bash
# ============================================================
#  Mockway macOS 开发环境管理脚本（对应 Windows 的 setup_win.bat）
#  菜单: 安装环境 / 启动工具 / 工作 shell / 停止
#  用法:
#    ./tools/setup_mac.sh                # 交互菜单
#    ./tools/setup_mac.sh setup          # 安装/更新 conda 环境
#    ./tools/setup_mac.sh motor_gui      # 启动电机调试 GUI
#    ./tools/setup_mac.sh torque         # 实时力矩补偿
#    ./tools/setup_mac.sh inverse        # 离线动力学测试
#    ./tools/setup_mac.sh path_teaching  # 路径示教
#    ./tools/setup_mac.sh shell          # 打开 Python 工作 shell
#    ./tools/setup_mac.sh stop           # 停止工具
# ============================================================
set -eo pipefail

ENV_NAME="mockway_dynamics"
PYTHON_VER="3.10"
PIP_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
PIP_TRUSTED="pypi.tuna.tsinghua.edu.cn"
MINICONDA_DIR="$HOME/miniconda3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MOTOR_GUI_DIR="$SCRIPT_DIR/motor_gui"
DYNAMICS_TEST_DIR="$SCRIPT_DIR/dynamics_test"
PATH_TEACHING_DIR="$SCRIPT_DIR/path_teaching"

TITLE_SHELL="Mockway-Shell"
TITLE_MOTOR_GUI="Mockway-motor_gui"
TITLE_TORQUE="Mockway-torque"
TITLE_INVERSE="Mockway-inverse"
TITLE_PATH_TEACHING="Mockway-path_teaching"

ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
    MINICONDA_FILE="Miniconda3-latest-MacOSX-arm64.sh"
else
    MINICONDA_FILE="Miniconda3-latest-MacOSX-x86_64.sh"
fi
MINICONDA_URL_TSINGHUA="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/${MINICONDA_FILE}"
MINICONDA_URL_OFFICIAL="https://repo.anaconda.com/miniconda/${MINICONDA_FILE}"
MINICONDA_INSTALLER="${TMPDIR:-/tmp}/${MINICONDA_FILE}"

CONDA_SH=""

# ------------------------------------------------------------
#  通用日志
# ------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
err()  { printf '%s\n' "$*" >&2; }
pause() { read -r -p "按 Enter 继续..." _ || true; }

# ------------------------------------------------------------
#  查找 conda
# ------------------------------------------------------------
find_conda() {
    CONDA_SH=""
    local candidates=(
        "$HOME/miniconda3"
        "$HOME/anaconda3"
        "$HOME/miniforge3"
        "/opt/miniconda3"
        "/opt/anaconda3"
        "/opt/homebrew/Caskroom/miniconda/base"
    )
    local d
    for d in "${candidates[@]}"; do
        if [[ -f "$d/etc/profile.d/conda.sh" ]]; then
            CONDA_SH="$d/etc/profile.d/conda.sh"
            MINICONDA_DIR="$d"
            return 0
        fi
    done
    # 退而求其次：PATH 里已有 conda
    if command -v conda >/dev/null 2>&1; then
        local base
        base="$(conda info --base 2>/dev/null || true)"
        if [[ -n "$base" && -f "$base/etc/profile.d/conda.sh" ]]; then
            CONDA_SH="$base/etc/profile.d/conda.sh"
            MINICONDA_DIR="$base"
            return 0
        fi
    fi
    return 1
}

init_conda_base() {
    [[ -n "$CONDA_SH" ]] || return 1
    # shellcheck disable=SC1090
    source "$CONDA_SH"
}

# ------------------------------------------------------------
#  下载并安装 Miniconda
# ------------------------------------------------------------
download_miniconda() {
    local url="$1"
    rm -f "$MINICONDA_INSTALLER" 2>/dev/null || true
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$MINICONDA_INSTALLER" "$url" && [[ -s "$MINICONDA_INSTALLER" ]] && return 0
    fi
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$MINICONDA_INSTALLER" "$url" && [[ -s "$MINICONDA_INSTALLER" ]] && return 0
    fi
    return 1
}

install_miniconda() {
    if [[ -f "$MINICONDA_DIR/etc/profile.d/conda.sh" ]]; then
        return 0
    fi
    say "        下载 Miniconda（清华镜像, ${ARCH}）..."
    if ! download_miniconda "$MINICONDA_URL_TSINGHUA"; then
        say "        尝试官方源 ..."
        download_miniconda "$MINICONDA_URL_OFFICIAL" || { err "[错误] Miniconda 下载失败"; return 1; }
    fi
    [[ -s "$MINICONDA_INSTALLER" ]] || { err "[错误] 安装包为空"; return 1; }

    say "        静默安装 Miniconda 到 $MINICONDA_DIR（约 1~3 分钟）..."
    bash "$MINICONDA_INSTALLER" -b -p "$MINICONDA_DIR" || { err "[错误] Miniconda 安装失败"; return 1; }
    [[ -f "$MINICONDA_DIR/etc/profile.d/conda.sh" ]] || { err "[错误] 安装后未找到 conda.sh"; return 1; }
    say "        Miniconda 安装成功: $MINICONDA_DIR"
    rm -f "$MINICONDA_INSTALLER" 2>/dev/null || true
}

# ------------------------------------------------------------
#  配置 conda 清华镜像
# ------------------------------------------------------------
configure_conda_mirror() {
    local rc="$HOME/.condarc"
    cat > "$rc" <<'EOF'
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
EOF
    conda clean -i -y >/dev/null 2>&1 || true
}

# ------------------------------------------------------------
#  [1] 安装 / 更新环境
# ------------------------------------------------------------
do_setup() {
    clear
    say ""
    say "============================================================"
    say " 安装 / 更新 $ENV_NAME 环境 (macOS / $ARCH)"
    say "============================================================"
    say ""

    if ! find_conda; then
        say "[0/8] 未检测到 Miniconda，开始自动安装 ..."
        say "        安装路径: $MINICONDA_DIR"
        install_miniconda || { setup_failed; return 1; }
        find_conda || { err "[错误] 安装后仍未找到 conda"; setup_failed; return 1; }
    fi

    say "[1/8] 初始化 conda ..."
    init_conda_base || { setup_failed; return 1; }

    say "[2/8] 配置 conda 国内镜像（清华源）..."
    configure_conda_mirror

    say "[3/8] 检查 conda 环境 \"$ENV_NAME\" ..."
    if conda env list | grep -E "^$ENV_NAME[[:space:]]|/$ENV_NAME$" >/dev/null 2>&1; then
        say "        环境已存在，跳过创建。"
    else
        say "        创建新环境 Python $PYTHON_VER ..."
        conda create -n "$ENV_NAME" "python=$PYTHON_VER" -y || { setup_failed; return 1; }
    fi

    say "[4/8] 激活环境 ..."
    conda activate "$ENV_NAME" || { setup_failed; return 1; }

    say "[5/8] 安装 Pinocchio (conda-forge) ..."
    if ! conda install pinocchio -c conda-forge -y; then
        say "        重试清华 conda-forge 镜像 ..."
        conda install pinocchio -c https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge -y || { setup_failed; return 1; }
    fi

    say "[6/8] 安装 pip 依赖 (numpy / matplotlib / pyserial / pyyaml) ..."
    python -m pip install --upgrade pip -i "$PIP_INDEX" --trusted-host "$PIP_TRUSTED"
    python -m pip install "numpy>=1.20.0" "matplotlib>=3.3.0" "pyserial>=3.5" "pyyaml>=6.0" \
        -i "$PIP_INDEX" --trusted-host "$PIP_TRUSTED" || { setup_failed; return 1; }

    say "[7/8] 验证安装 ..."
    python -c "import pinocchio as pin; import numpy; import matplotlib; import serial; import yaml; print('pinocchio', pin.__version__); print('numpy', numpy.__version__); print('OK')" || { setup_failed; return 1; }

    say "[8/8] 安装完成。"
    say ""
    say "============================================================"
    say " 环境 $ENV_NAME 已就绪。"
    say " 返回菜单后可选 [2]~[6] 启动工具。"
    say "============================================================"
    say ""
}

setup_failed() {
    say ""
    err "[错误] 安装失败，请查看上方报错。"
}

# ------------------------------------------------------------
#  检查 conda 环境是否可用
# ------------------------------------------------------------
check_env_ready() {
    if ! find_conda; then
        err "[错误] 未找到 conda，请先选 [1] 安装环境。"
        return 1
    fi
    init_conda_base >/dev/null 2>&1 || true
    if ! conda env list | grep -E "^$ENV_NAME[[:space:]]|/$ENV_NAME$" >/dev/null 2>&1; then
        err "[错误] 环境 $ENV_NAME 不存在，请先选 [1] 安装。"
        return 1
    fi
    return 0
}

# ------------------------------------------------------------
#  在新的 Terminal.app 窗口里执行命令（带标题）
# ------------------------------------------------------------
open_terminal() {
    local title="$1"
    local bashcmd="$2"
    local esc
    # 转义 AppleScript 字符串里的反斜杠与双引号
    esc=$(printf '%s' "$bashcmd" | sed 's/\\/\\\\/g; s/"/\\"/g')
    osascript \
        -e 'tell application "Terminal"' \
        -e '    activate' \
        -e "    set newWin to do script \"$esc\"" \
        -e '    delay 0.3' \
        -e '    try' \
        -e "        set custom title of front window to \"$title\"" \
        -e '    end try' \
        -e 'end tell' >/dev/null 2>&1
}

# ------------------------------------------------------------
#  在新窗口启动 Python 程序
# ------------------------------------------------------------
launch_app() {
    local title="$1" workdir="$2" script="$3"
    if [[ ! -f "$workdir/$script" ]]; then
        err "[错误] 未找到脚本: $workdir/$script"
        return 1
    fi
    say "[启动] $script ..."
    local cmd
    cmd="cd '$workdir' && source '$CONDA_SH' && conda activate $ENV_NAME && python '$workdir/$script'"
    open_terminal "$title" "$cmd"
    say "        窗口标题: $title"
}

do_motor_gui()     { check_env_ready || return 1; launch_app "$TITLE_MOTOR_GUI" "$MOTOR_GUI_DIR" "motor_gui.py"; }
do_torque()        { check_env_ready || return 1; launch_app "$TITLE_TORQUE" "$DYNAMICS_TEST_DIR" "realtime_torque_compensation.py"; }
do_inverse()       { check_env_ready || return 1; launch_app "$TITLE_INVERSE" "$DYNAMICS_TEST_DIR" "inverse_dynamics_test.py"; }
do_path_teaching() { check_env_ready || return 1; launch_app "$TITLE_PATH_TEACHING" "$PATH_TEACHING_DIR" "path_teaching_gui.py"; }

# ------------------------------------------------------------
#  [6] Python 工作 shell
# ------------------------------------------------------------
do_shell() {
    check_env_ready || return 1
    say "[启动] 打开 Python 工作 shell ..."
    local cmd
    cmd="source '$CONDA_SH' && conda activate $ENV_NAME && cd '$REPO_ROOT' && clear && echo && echo 'Mockway $ENV_NAME 工作 shell' && echo '仓库根目录: $REPO_ROOT' && echo && exec \$SHELL -i"
    open_terminal "$TITLE_SHELL" "$cmd"
    say ""
    say "  工作 shell 已打开 (窗口标题: $TITLE_SHELL)"
    say ""
}

# ------------------------------------------------------------
#  [7] 停止（结束已启动的工具进程）
# ------------------------------------------------------------
kill_script() {
    local label="$1" pattern="$2"
    if pgrep -f "$pattern" >/dev/null 2>&1; then
        pkill -f "$pattern" >/dev/null 2>&1 || true
        say "        已停止: $label"
    fi
}

do_stop() {
    say "[停止] 结束 Mockway 工具进程 ..."
    kill_script "$TITLE_MOTOR_GUI"     "$MOTOR_GUI_DIR/motor_gui.py"
    kill_script "$TITLE_TORQUE"        "$DYNAMICS_TEST_DIR/realtime_torque_compensation.py"
    kill_script "$TITLE_INVERSE"       "$DYNAMICS_TEST_DIR/inverse_dynamics_test.py"
    kill_script "$TITLE_PATH_TEACHING" "$PATH_TEACHING_DIR/path_teaching_gui.py"
    say ""
    say "  工具进程已结束（对应 Terminal 窗口可手动关闭）。"
    say ""
}

# ------------------------------------------------------------
#  [8] Docker / MoveIt2 工具菜单
# ------------------------------------------------------------
do_moveit() {
    if [[ -f "$SCRIPT_DIR/setup_moveit_mac.sh" ]]; then
        bash "$SCRIPT_DIR/setup_moveit_mac.sh"
    else
        err "[错误] 未找到 $SCRIPT_DIR/setup_moveit_mac.sh"
    fi
}

# ------------------------------------------------------------
#  环境状态显示
# ------------------------------------------------------------
is_running() { pgrep -f "$1" >/dev/null 2>&1; }

show_env_status() {
    if ! find_conda; then
        say " 状态: conda 未安装"
    else
        init_conda_base >/dev/null 2>&1 || true
        if conda env list | grep -E "^$ENV_NAME[[:space:]]|/$ENV_NAME$" >/dev/null 2>&1; then
            say " 状态: 环境 $ENV_NAME 已安装"
        else
            say " 状态: conda 已安装，环境 $ENV_NAME 未创建"
        fi
    fi
    is_running "$MOTOR_GUI_DIR/motor_gui.py"                     && say " motor_gui: 【运行中】"
    is_running "$DYNAMICS_TEST_DIR/realtime_torque_compensation.py" && say " 力矩补偿: 【运行中】"
    is_running "$DYNAMICS_TEST_DIR/inverse_dynamics_test.py"     && say " 离线动力学: 【运行中】"
    is_running "$PATH_TEACHING_DIR/path_teaching_gui.py"         && say " 路径示教: 【运行中】"
    return 0
}

# ------------------------------------------------------------
#  主菜单
# ------------------------------------------------------------
main_menu() {
    while true; do
        clear
        say ""
        say "============================================================"
        say " Mockway 开发环境管理 (macOS)"
        say "============================================================"
        say ""
        show_env_status
        say ""
        say " [1] 安装 / 更新环境 (Miniconda + Pinocchio + 依赖)"
        say " [2] 启动 motor_gui (电机调试)"
        say " [3] 启动 实时力矩补偿 (realtime_torque_compensation)"
        say " [4] 启动 离线动力学测试 (inverse_dynamics_test)"
        say " [5] 启动 路径示教 (path_teaching_gui)"
        say " [6] 打开 Python 工作 shell"
        say " [7] 停止 (结束工具进程)"
        say " [8] MoveIt2 工具菜单 (RoboStack 原生 ROS2 Jazzy)"
        say " [0] 退出"
        say ""
        local choice
        read -r -p "请选择 [0-8]: " choice
        case "$choice" in
            1) do_setup; pause ;;
            2) do_motor_gui || true; pause ;;
            3) do_torque || true; pause ;;
            4) do_inverse || true; pause ;;
            5) do_path_teaching || true; pause ;;
            6) do_shell || true; pause ;;
            7) do_stop; pause ;;
            8) do_moveit ;;
            0|q|Q) exit 0 ;;
            *) say "无效选择，请重试。"; sleep 1 ;;
        esac
    done
}

# ------------------------------------------------------------
#  命令行直达
# ------------------------------------------------------------
case "${1:-}" in
    setup)          do_setup ;;
    motor_gui)      do_motor_gui ;;
    torque)         do_torque ;;
    inverse)        do_inverse ;;
    path_teaching)  do_path_teaching ;;
    shell|start)    do_shell ;;
    stop)           do_stop ;;
    moveit)         do_moveit ;;
    "")             main_menu ;;
    *)              err "未知参数: $1"; exit 1 ;;
esac
