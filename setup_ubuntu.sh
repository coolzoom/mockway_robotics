#!/usr/bin/env bash
# Mockway — Ubuntu / WSL 统一环境管理（conda 调试 + XFCE 桌面 + MoveIt2）
# 用法:
#   ./setup_ubuntu.sh                    # 主菜单
#   ./setup_ubuntu.sh setup              # 安装 conda 环境
#   ./setup_ubuntu.sh motor_gui          # 启动 motor_gui
#   ./setup_ubuntu.sh desktop            # 启动 XFCE 桌面
#   ./setup_ubuntu.sh moveit-install     # ROS2 Jazzy + MoveIt2 完整安装
#   ./setup_ubuntu.sh moveit-demo        # MoveIt Demo (真机, 当前终端)
#   ./setup_ubuntu.sh moveit             # MoveIt 子菜单 (兼容旧编号 1-9)
set -eo pipefail

ENV_NAME="${MOCKWAY_ENV_NAME:-mockway_dynamics}"
PYTHON_VER="${MOCKWAY_PYTHON_VER:-3.10}"
MINICONDA_DIR="${MOCKWAY_MINICONDA_DIR:-$HOME/miniconda3}"
PIP_INDEX="${MOCKWAY_PIP_INDEX:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PIP_TRUSTED="${MOCKWAY_PIP_TRUSTED:-pypi.tuna.tsinghua.edu.cn}"

ROS_DISTRO="${MOCKWAY_ROS_DISTRO:-jazzy}"
WS_DIR="${MOCKWAY_WS_DIR:-$HOME/mockway_ws}"
LOG_FILE="${MOCKWAY_LOG:-/tmp/mockway_ubuntu_setup.log}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
SELF_PATH="$SCRIPT_DIR/setup_ubuntu.sh"
MOTOR_GUI_DIR="$SCRIPT_DIR/tools/motor_gui"
DYNAMICS_TEST_DIR="$SCRIPT_DIR/tools/dynamics_test"

MINICONDA_URL_TSINGHUA="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh"
MINICONDA_URL_OFFICIAL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"

log()  { echo "[mockway] $*"; }
warn() { echo "[mockway][警告] $*" >&2; }
die()  { echo "[mockway][错误] $*" >&2; exit 1; }

# --- 图形界面 (WSLg / 原生 Ubuntu) ---

mockway_is_wsl() {
    grep -qi microsoft /proc/version 2>/dev/null
}

# WSLg 下常见误设 DISPLAY=wayland-0（须为 :0）；XFCE/RViz 等 X11 程序无法打开 wayland-0
normalize_wsl_display() {
    mockway_is_wsl || return 0
    if [[ -z "${DISPLAY:-}" || "${DISPLAY}" == wayland* || "${DISPLAY}" == "${WAYLAND_DISPLAY:-}" ]]; then
        export DISPLAY=:0
    fi
}

prepare_gui_env() {
    if mockway_is_wsl; then
        export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
        normalize_wsl_display
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}"
        export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"
        return 0
    fi
    local uid_dir="/run/user/$(id -u)"
    if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "$uid_dir" ]]; then
        export XDG_RUNTIME_DIR="$uid_dir"
    fi
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        if [[ -S /tmp/.X11-unix/X0 ]]; then
            export DISPLAY=:0
        elif [[ -S /tmp/.X11-unix/X1 ]]; then
            export DISPLAY=:1
        fi
    fi
}

prepare_moveit_gui_env() {
    prepare_gui_env
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
    export GDK_BACKEND="${GDK_BACKEND:-x11}"
}

# XFCE 须走 X11；WSLg 的 dbus 对 /mnt/wslg/runtime-dir 权限会告警，改用用户私有目录
prepare_xfce_desktop_env() {
    prepare_gui_env
    export DISPLAY=:0
    export GDK_BACKEND=x11
    export QT_QPA_PLATFORM=xcb
    export LANG="${LANG:-C.UTF-8}"
    export LC_ALL="${LC_ALL:-C.UTF-8}"
    unset WAYLAND_DISPLAY
    local uid_dir="/run/user/$(id -u)"
    if [[ -d "$uid_dir" ]]; then
        export XDG_RUNTIME_DIR="$uid_dir"
    else
        export XDG_RUNTIME_DIR="${MOCKWAY_XDG_RUNTIME_DIR:-$HOME/.cache/mockway-xdg-runtime}"
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
    fi
}

gui_env_snippet() {
    cat <<EOF
export DISPLAY="${DISPLAY:-}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-}"
export GDK_BACKEND="${GDK_BACKEND:-}"
EOF
}

check_gui_display() {
    prepare_gui_env
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        echo "[mockway][错误] 无图形显示 (DISPLAY/WAYLAND 未设置)。请在 Ubuntu 桌面终端运行。" >&2
        echo "  提示: export DISPLAY=:0  或安装 gnome-terminal 后从新窗口启动" >&2
        return 1
    fi
    return 0
}

launch_in_graphical_terminal() {
    local title="$1"
    local inner_script="$2"
    local hold="${3:-1}"

    check_gui_display || return 1

    local tail=""
    if [[ "$hold" == "1" ]]; then
        tail=$'\necho\necho "--- 程序已退出 ---"\nread -r -p "按 Enter 关闭窗口..." _'
    fi

    if command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --title="$title" -- bash -lc "${inner_script}${tail}"
    elif command -v xfce4-terminal >/dev/null 2>&1; then
        xfce4-terminal --title="$title" -e bash -lc "${inner_script}${tail}"
    elif command -v konsole >/dev/null 2>&1; then
        konsole --new-tab -p tabtitle="$title" -e bash -lc "${inner_script}${tail}"
    elif command -v x-terminal-emulator >/dev/null 2>&1; then
        x-terminal-emulator -T "$title" -e bash -lc "${inner_script}${tail}"
    elif command -v xterm >/dev/null 2>&1; then
        xterm -T "$title" -e bash -lc "${inner_script}${tail}"
    else
        echo "[mockway][警告] 未找到 gnome-terminal/xterm，在当前 shell 前台运行" >&2
        bash -lc "${inner_script}"
        return $?
    fi
    echo "[mockway] 已在新图形终端启动: ${title}"
    return 0
}

mockway_gui_diagnose() {
    echo ""
    echo "============================================================"
    echo " Ubuntu 图形环境诊断"
    echo "============================================================"
    prepare_gui_env
    echo "  会话类型:   ${XDG_SESSION_TYPE:-unknown}"
    echo "  DISPLAY:    ${DISPLAY:-(未设置)}"
    echo "  WAYLAND:    ${WAYLAND_DISPLAY:-(未设置)}"
    echo "  XDG_RUNTIME: ${XDG_RUNTIME_DIR:-(未设置)}"
    echo "  QT_QPA:     ${QT_QPA_PLATFORM:-(未设置)}"
    if mockway_is_wsl; then
        echo "  平台:       WSL2 (+ WSLg)"
    else
        echo "  平台:       原生 Linux"
    fi
    echo ""
    echo "  图形终端:"
    local t
    for t in gnome-terminal xfce4-terminal konsole xterm; do
        if command -v "$t" >/dev/null 2>&1; then
            echo "    [有] $t"
        fi
    done
    echo ""
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
        if mockway_is_wsl && [[ "${DISPLAY:-}" == wayland* ]]; then
            echo "  图形显示:   DISPLAY 误设为 ${DISPLAY} — 请用: export DISPLAY=:0"
        else
            echo "  图形显示:   可用"
        fi
    else
        echo "  图形显示:   不可用 — 请在桌面会话中运行本脚本"
    fi
    echo "============================================================"
}

# --- 通用 ---

as_root() {
    if [[ $(id -u) -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

resolve_repo() {
    export MOCKWAY_REPO_WSL="${MOCKWAY_REPO_WSL:-$REPO_ROOT}"
    if [[ ! -d "$MOCKWAY_REPO_WSL/moveit_mockway_config" ]]; then
        die "仓库无效: $MOCKWAY_REPO_WSL (缺少 moveit_mockway_config)"
    fi
}

source_mockway_env() {
    # shellcheck disable=SC1091
    [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]] || die "未安装 ROS2 ${ROS_DISTRO}，请先: $0 moveit-install"
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
    if [[ -f "$WS_DIR/install/setup.bash" ]]; then
        # shellcheck disable=SC1091
        source "$WS_DIR/install/setup.bash"
    else
        die "工作空间未编译: $WS_DIR (请先: $0 moveit-install 或 moveit-rebuild)"
    fi
}

check_ubuntu() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        if [[ "${ID:-}" != "ubuntu" ]]; then
            warn "当前系统: ${PRETTY_NAME:-unknown}，脚本针对 Ubuntu 24.04 + ROS2 Jazzy 测试"
        elif [[ "${VERSION_ID:-}" != "24.04" ]]; then
            warn "当前 Ubuntu ${VERSION_ID}，推荐 24.04 (Noble)"
        fi
    fi
}

# ============================================================
# Conda / Python 调试环境
# ============================================================

conda_sh() {
    if [[ -f "$MINICONDA_DIR/etc/profile.d/conda.sh" ]]; then
        # shellcheck disable=SC1091
        source "$MINICONDA_DIR/etc/profile.d/conda.sh"
        return 0
    fi
    if [[ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]]; then
        MINICONDA_DIR="$HOME/anaconda3"
        # shellcheck disable=SC1091
        source "$MINICONDA_DIR/etc/profile.d/conda.sh"
        return 0
    fi
    return 1
}

find_conda() {
    conda_sh 2>/dev/null
}

configure_conda_mirror() {
    local rc="$MINICONDA_DIR/.condarc"
    cat >"$rc" <<'EOF'
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
  pytorch: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
EOF
    conda clean -i -y >/dev/null 2>&1 || true
}

install_miniconda() {
    if [[ -f "$MINICONDA_DIR/bin/conda" ]]; then
        return 0
    fi
    local installer="/tmp/Miniconda3-latest-Linux-x86_64.sh"
    log "下载 Miniconda（清华镜像）..."
    if ! curl -fsSL -o "$installer" "$MINICONDA_URL_TSINGHUA"; then
        warn "清华源失败，尝试官方源..."
        curl -fsSL -o "$installer" "$MINICONDA_URL_OFFICIAL" || die "Miniconda 下载失败"
    fi
    log "安装 Miniconda -> $MINICONDA_DIR"
    bash "$installer" -b -p "$MINICONDA_DIR"
    rm -f "$installer"
    [[ -f "$MINICONDA_DIR/bin/conda" ]] || die "Miniconda 安装失败"
}

activate_env() {
    find_conda || die "未找到 conda，请先运行: $0 setup"
    conda activate "$ENV_NAME" 2>/dev/null || die "环境 $ENV_NAME 不存在，请先运行: $0 setup"
}

env_ready() {
    find_conda || return 1
    if conda env list | grep -qE "(^|[[:space:]])${ENV_NAME}([[:space:]]|$)"; then
        return 0
    fi
    return 1
}

tool_running() {
    pgrep -f "$1" >/dev/null 2>&1
}

show_status() {
    if env_ready; then
        echo "  状态: 环境 ${ENV_NAME} 已安装"
    elif find_conda; then
        echo "  状态: conda 已安装，环境 ${ENV_NAME} 未创建"
    else
        echo "  状态: conda 未安装"
    fi
    if tool_running "motor_gui.py"; then
        echo "  motor_gui: 【运行中】"
    fi
    if tool_running "realtime_torque_compensation.py"; then
        echo "  力矩补偿: 【运行中】"
    fi
    if tool_running "inverse_dynamics_test.py"; then
        echo "  离线动力学: 【运行中】"
    fi
    if pgrep -f "xfce4-session" >/dev/null 2>&1; then
        echo "  Ubuntu桌面: 【XFCE 运行中】"
    fi
    return 0
}

cmd_setup() {
    echo
    echo "============================================================"
    echo " 安装 / 更新 ${ENV_NAME} 环境 (Ubuntu)"
    echo "============================================================"
    echo

    if ! find_conda; then
        log "[0/9] 未检测到 Miniconda，开始自动安装..."
        install_miniconda
        find_conda || die "conda 初始化失败"
    fi

    log "[1/9] 配置 conda 国内镜像（清华源）..."
    configure_conda_mirror

    log "[2/9] 检查 conda 环境 ${ENV_NAME}..."
    if conda env list | grep -qE "(^|[[:space:]])${ENV_NAME}([[:space:]]|$)"; then
        log "       环境已存在，跳过创建"
    else
        conda create -n "$ENV_NAME" "python=${PYTHON_VER}" -y
    fi

    log "[3/9] 激活环境..."
    conda activate "$ENV_NAME"

    log "[4/9] 安装系统 GUI 依赖 (tkinter + 终端)..."
    if command -v apt-get >/dev/null; then
        sudo apt-get install -y -qq python3-tk libx11-6 \
            gnome-terminal xterm >/dev/null 2>&1 \
            || warn "部分 apt 包安装失败，GUI 启动可能受影响"
    fi

    log "[5/9] 安装 Pinocchio (conda-forge)..."
    if ! conda install -y pinocchio -c conda-forge; then
        warn "重试清华 conda-forge 镜像..."
        conda install -y pinocchio \
            -c "https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge"
    fi

    log "[6/9] 安装 tk (conda，GUI)..."
    conda install -y tk || warn "conda tk 安装失败"

    log "[7/9] 安装 pip 依赖..."
    python -m pip install --upgrade pip \
        -i "$PIP_INDEX" --trusted-host "$PIP_TRUSTED"
    python -m pip install \
        "numpy>=1.20.0" "matplotlib>=3.3.0" "pyserial>=3.5" "pyyaml>=6.0" \
        -i "$PIP_INDEX" --trusted-host "$PIP_TRUSTED"

    log "[8/9] 验证..."
    python -c "
import pinocchio as pin
import numpy, matplotlib, serial, yaml
print('pinocchio', pin.__version__)
print('numpy', numpy.__version__)
import tkinter as tk
r = tk.Tk()
r.withdraw()
r.destroy()
print('tkinter OK')
print('OK')
"

    log "[9/9] 安装完成"
    echo
    echo "============================================================"
    echo " 环境 ${ENV_NAME} 已就绪。"
    echo " 返回菜单后可选 [2]~[5] 启动工具。"
    echo " 激活环境: conda activate ${ENV_NAME}"
    echo "============================================================"
    echo
}

launch_tool_in_terminal() {
    local title="$1" work_dir="$2" script="$3"
    local script_path="$work_dir/$script"
    local pattern="$script"

    [[ -f "$script_path" ]] || die "未找到脚本: $script_path"
    env_ready || die "环境未就绪，请先: $0 setup"

    if tool_running "$pattern"; then
        warn "${script} 已在运行"
        return 0
    fi

    prepare_gui_env
    local inner
    inner=$(cat <<EOF
source "$MINICONDA_DIR/etc/profile.d/conda.sh"
conda activate "$ENV_NAME"
$(gui_env_snippet)
cd "$work_dir"
python "$script"
EOF
)
    launch_in_graphical_terminal "$title" "$inner" 1
}

launch_tool_foreground() {
    local work_dir="$1" script="$2"
    local script_path="$work_dir/$script"

    [[ -f "$script_path" ]] || die "未找到脚本: $script_path"
    check_gui_display || die "无图形环境，请选 [8] 检测或使用新终端启动"
    activate_env
    prepare_gui_env
    log "前台启动 ${script} (Ctrl+C 退出) ..."
    cd "$work_dir"
    exec python "$script"
}

cmd_gui_diagnose() {
    mockway_gui_diagnose
    if env_ready; then
        echo ""
        log "tkinter 测试 (conda ${ENV_NAME}) ..."
        activate_env
        if python -c "import tkinter as tk; r=tk.Tk(); r.withdraw(); r.destroy(); print('  tkinter: OK')" 2>/dev/null; then
            :
        else
            warn "  tkinter: 失败 — 请运行 [1] 安装或: sudo apt install python3-tk"
        fi
    fi
    echo ""
}

cmd_gui_foreground_menu() {
    echo ""
    echo "  图形工具 — 当前终端前台 (需已有 DISPLAY)"
    echo "  [1] motor_gui"
    echo "  [2] 实时力矩补偿"
    echo "  [3] 离线动力学测试"
    echo "  [0] 返回"
    echo ""
    read -r -p "请选择 [0-3]: " gchoice
    case "${gchoice:-}" in
        1) launch_tool_foreground "$MOTOR_GUI_DIR" motor_gui.py ;;
        2) launch_tool_foreground "$DYNAMICS_TEST_DIR" realtime_torque_compensation.py ;;
        3) launch_tool_foreground "$DYNAMICS_TEST_DIR" inverse_dynamics_test.py ;;
        0|"") return 0 ;;
        *) warn "无效选择" ;;
    esac
}

cmd_motor_gui() {
    launch_tool_in_terminal "Mockway-motor_gui" "$MOTOR_GUI_DIR" motor_gui.py
}

cmd_torque() {
    launch_tool_in_terminal "Mockway-torque" "$DYNAMICS_TEST_DIR" realtime_torque_compensation.py
}

cmd_inverse() {
    launch_tool_in_terminal "Mockway-inverse" "$DYNAMICS_TEST_DIR" inverse_dynamics_test.py
}

cmd_shell() {
    env_ready || { die "环境未就绪，请先: $0 setup"; }
    find_conda
    log "进入 Python 工作 shell (conda activate ${ENV_NAME})"
    echo
    echo "  仓库: $REPO_ROOT"
    echo "  motor_gui:    $MOTOR_GUI_DIR/motor_gui.py"
    echo "  力矩补偿:     $DYNAMICS_TEST_DIR/realtime_torque_compensation.py"
    echo "  离线动力学:   $DYNAMICS_TEST_DIR/inverse_dynamics_test.py"
    echo
    cd "$REPO_ROOT"
    exec bash --rcfile <(
        cat <<EOF
# shellcheck disable=SC1091
source "$MINICONDA_DIR/etc/profile.d/conda.sh"
conda activate "$ENV_NAME"
export PS1="(mockway:${ENV_NAME}) \\u@\\h:\\w\\\$ "
EOF
    ) -i
}

cmd_stop() {
    log "停止 Mockway 调试工具..."
    local stopped=0
    local spec
    for spec in \
        "motor_gui.py:motor_gui" \
        "realtime_torque_compensation.py:力矩补偿" \
        "inverse_dynamics_test.py:离线动力学" \
        "xfce4-session:Ubuntu桌面"; do
        local pattern="${spec%%:*}" label="${spec#*:}"
        if tool_running "$pattern"; then
            pkill -f "$pattern" 2>/dev/null || true
            sleep 0.3
            pkill -9 -f "$pattern" 2>/dev/null || true
            log "  已停止 ${label}"
            stopped=1
        fi
    done
    if [[ "$stopped" -eq 0 ]]; then
        log "  无运行中的工具进程"
    fi
}

# ============================================================
# Ubuntu XFCE 桌面
# ============================================================

cmd_install_ubuntu_desktop() {
    export DEBIAN_FRONTEND=noninteractive
    command -v apt-get >/dev/null || die "需要 apt (Ubuntu/Debian)"

    log "安装 Ubuntu 桌面组件 (XFCE + 终端 + dbus) ..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        xfce4 \
        xfce4-terminal \
        xfce4-goodies \
        dbus-x11 \
        x11-xserver-utils \
        x11-apps \
        gnome-terminal \
        menu \
        || {
            log "精简安装重试 (不含 goodies) ..."
            sudo apt-get install -y -qq xfce4 xfce4-terminal dbus-x11 x11-xserver-utils gnome-terminal
        }

    log "桌面组件安装完成。运行: $0 desktop"
}

cmd_ubuntu_desktop() {
    prepare_xfce_desktop_env

    if mockway_is_wsl 2>/dev/null; then
        log "平台: WSL2 — 需 Windows 11 / Win10 22H2+ 的 WSLg 才能显示桌面"
        log "      请勿从「管理员 CMD」启动（WSLg 图形会失败）"
        log "      XFCE 使用 DISPLAY=:0 (勿设 DISPLAY=wayland-0)"
    fi

    if [[ -n "${XDG_CURRENT_DESKTOP:-}" && -z "${MOCKWAY_FORCE_DESKTOP:-}" ]]; then
        warn "检测到已有桌面会话: ${XDG_CURRENT_DESKTOP}"
        warn "若仍要启动 XFCE 面板，请: MOCKWAY_FORCE_DESKTOP=1 $0 desktop"
        return 0
    fi

    if ! command -v startxfce4 >/dev/null 2>&1; then
        log "未安装 XFCE，正在安装 ..."
        cmd_install_ubuntu_desktop
    fi

    if pgrep -f "xfce4-session" >/dev/null 2>&1; then
        warn "XFCE 桌面已在运行 (xfce4-session)"
        warn "停止: pkill -f xfce4-session  或菜单 [6] stop"
        return 0
    fi

    if [[ -z "${DISPLAY:-}" ]]; then
        die "无 DISPLAY，无法启动桌面。WSL: 确认 WSLg 并用普通权限终端"
    fi

    log "DISPLAY=${DISPLAY} XDG_RUNTIME=${XDG_RUNTIME_DIR:-}"
    log "启动 XFCE 桌面 ..."
    log "  任务栏应出现 Ubuntu 桌面/面板；可在桌面终端中运行 ./setup_ubuntu.sh"
    log "  日志: /tmp/mockway_xfce.log"

    local xfce_cmd
    xfce_cmd='export DISPLAY=:0 GDK_BACKEND=x11 QT_QPA_PLATFORM=xcb; exec startxfce4'

    if [[ "${MOCKWAY_DESKTOP_FOREGROUND:-0}" == "1" ]]; then
        exec env DISPLAY=:0 GDK_BACKEND=x11 QT_QPA_PLATFORM=xcb \
            XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
            dbus-launch --exit-with-session bash -lc "$xfce_cmd"
    fi

    nohup env DISPLAY=:0 GDK_BACKEND=x11 QT_QPA_PLATFORM=xcb \
        XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
        dbus-launch --exit-with-session bash -lc "$xfce_cmd" \
        >/tmp/mockway_xfce.log 2>&1 &
    disown -h $! 2>/dev/null || true
    log "桌面已在后台启动 (PID $!)"
}

# ============================================================
# MoveIt / ROS2
# ============================================================

ensure_sudo_access() {
    local repo_wsl="${MOCKWAY_REPO_WSL:-$REPO_ROOT}"
    if [[ $(id -u) -eq 0 ]]; then
        if getent passwd test >/dev/null 2>&1; then
            die "检测到 root 运行，但 test 用户已存在。请用 test 安装:
  wsl -u test -- env MOCKWAY_REPO_WSL='$repo_wsl' bash '$SELF_PATH' moveit-install
或在 Linux 运行: $0 moveit-install"
        fi
        log "警告: 以 root 运行，工作空间: ${WS_DIR}"
        return 0
    fi
    if sudo -v 2>/dev/null; then
        return 0
    fi
    die "用户 $(id -un) 需要 sudo 权限。"
}

init_rosdep_sources() {
    local list="/etc/ros/rosdep/sources.list.d/20-default.list"
    local mirror="${MOCKWAY_ROSDEP_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/rosdistro}"
    if [[ -f "$list" ]]; then
        log "rosdep sources 已存在，跳过 init"
        return 0
    fi
    log "写入 rosdep 源（国内镜像，避免 GitHub 超时）..."
    as_root mkdir -p /etc/ros/rosdep/sources.list.d
    as_root tee "$list" > /dev/null <<EOF
yaml ${mirror}/rosdep/base.yaml
yaml ${mirror}/rosdep/python.yaml
yaml ${mirror}/rosdep/ruby.yaml
EOF
}

update_rosdep_with_retry() {
    local attempt
    for attempt in 1 2 3 4 5; do
        log "rosdep update (尝试 ${attempt}/5) ..."
        if rosdep update; then
            return 0
        fi
        log "rosdep update 超时/失败，${attempt} 秒后重试 ..."
        sleep "$attempt"
    done
    log "rosdep update 仍失败（网络问题）。继续编译；多数依赖已由 apt 安装。"
    return 1
}

cmd_moveit_install() {
    resolve_repo
    local repo_wsl="$MOCKWAY_REPO_WSL"

    if [[ -z "$repo_wsl" ]] || [[ ! -d "$repo_wsl/moveit_mockway_config" ]]; then
        die "仓库路径无效: ${repo_wsl:-未设置}"
    fi

    ensure_sudo_access

    export DEBIAN_FRONTEND=noninteractive
    export LANG=C.UTF-8
    export LC_ALL=C.UTF-8
    export MOCKWAY_REPO_WSL="$repo_wsl" MOCKWAY_WS_DIR="$WS_DIR"

    log "更新 apt ..."
    as_root apt-get update -y

    log "配置 locale 与 universe 仓库 ..."
    as_root apt-get install -y locales software-properties-common
    as_root locale-gen en_US en_US.UTF-8 2>/dev/null || true
    as_root update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 2>/dev/null || true
    as_root add-apt-repository -y universe 2>/dev/null || true
    as_root apt-get update -y

    log "安装基础工具 ..."
    as_root apt-get install -y \
        curl gnupg lsb-release \
        build-essential git wget \
        python3-pip \
        liblua5.4-dev \
        usbutils

    if [[ ! -f /etc/apt/sources.list.d/ros2.list ]]; then
        log "添加 ROS2 ${ROS_DISTRO} apt 源 ..."
        as_root curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
            -o /usr/share/keyrings/ros-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
            | as_root tee /etc/apt/sources.list.d/ros2.list > /dev/null
        as_root apt-get update -y
    else
        log "ROS2 apt 源已存在，跳过。"
        as_root apt-get update -y
    fi

    log "安装 colcon / rosdep / vcstool ..."
    if ! as_root apt-get install -y \
        python3-colcon-common-extensions \
        python3-rosdep \
        python3-vcstool; then
        log "尝试通过 ros-dev-tools 安装构建工具 ..."
        as_root apt-get install -y ros-dev-tools
    fi

    log "安装 ROS2 ${ROS_DISTRO} 与 MoveIt2 ..."
    as_root apt-get install -y \
        "ros-${ROS_DISTRO}-ros-base" \
        "ros-${ROS_DISTRO}-moveit" \
        "ros-${ROS_DISTRO}-moveit-setup-assistant" \
        "ros-${ROS_DISTRO}-moveit-ros-visualization" \
        "ros-${ROS_DISTRO}-rviz2" \
        "ros-${ROS_DISTRO}-xacro" \
        "ros-${ROS_DISTRO}-joint-state-publisher-gui" \
        "ros-${ROS_DISTRO}-robot-state-publisher" \
        "ros-${ROS_DISTRO}-controller-manager" \
        "ros-${ROS_DISTRO}-ros2-control" \
        "ros-${ROS_DISTRO}-ros2-controllers"

    rosdep --version >/dev/null 2>&1 || die "rosdep 未安装，请检查 apt 安装步骤"

    export ROSDISTRO_INDEX_URL="${MOCKWAY_ROSDEP_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/rosdistro}/index-v4.yaml"

    log "初始化 rosdep ..."
    init_rosdep_sources
    update_rosdep_with_retry || true

    log "创建工作空间: $WS_DIR"
    mkdir -p "$WS_DIR/src"
    local link_path="$WS_DIR/src/mockway_robotics"
    if [[ -L "$link_path" ]]; then
        log "符号链接已存在: $link_path"
    elif [[ -d "$link_path" ]]; then
        log "目录已存在: $link_path（未覆盖）"
    else
        ln -s "$repo_wsl" "$link_path"
        log "已链接仓库 -> $link_path"
    fi

    log "安装 rosdep 依赖 (moveit_mockway_config) ..."
    cd "$WS_DIR"
    # shellcheck disable=SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
    rosdep install --from-paths src/mockway_robotics/moveit_mockway_config \
        --ignore-src -r -y || log "rosdep 部分包警告（可忽略未解析项）"

    log "colcon 编译 mockway_description + dmmotor_hardware_interface + moveit_mockway_config ..."
    colcon build --symlink-install \
        --packages-select mockway_description dmmotor_hardware_interface moveit_mockway_config \
        || die "colcon 编译失败，请查看上方错误输出"

    local bashrc="$HOME/.bashrc"
    local marker="# >>> mockway ros2 ${ROS_DISTRO} >>>"
    if ! grep -qF "$marker" "$bashrc" 2>/dev/null; then
        log "写入 ~/.bashrc 环境 ..."
        cat >> "$bashrc" <<EOF

$marker
source /opt/ros/${ROS_DISTRO}/setup.bash
if [ -f ${WS_DIR}/install/setup.bash ]; then
  source ${WS_DIR}/install/setup.bash
fi
# <<< mockway ros2 ${ROS_DISTRO} <<<
EOF
    fi

    log "验证安装 ..."
    # shellcheck disable=SC1091
    source "$WS_DIR/install/setup.bash"
    ros2 pkg prefix moveit_mockway_config &>/dev/null \
        || die "moveit_mockway_config 未找到（colcon 可能失败，见上方日志）"

    log "=========================================="
    log "安装完成。"
    log "启动 MoveIt Demo:"
    log "  $0 moveit-demo"
    log "  (Demo 默认 use_mock_hardware:=false，接 USB-CAN 真机 /dev/ttyACM0)"
    log "  无硬件仿真: ros2 launch moveit_mockway_config demo.launch.py use_mock_hardware:=true"
    log "或菜单选 [21] MoveIt + RViz (真机, 新图形终端)"
    log "=========================================="
}

cmd_moveit_install_logged() {
    resolve_repo
    log "完整安装 -> 日志: $LOG_FILE"
    cmd_moveit_install 2>&1 | tee -a "$LOG_FILE"
}

build_moveit_launch_inner() {
    local use_mock="$1"
    prepare_moveit_gui_env
    cat <<EOF
$(gui_env_snippet)
source "/opt/ros/${ROS_DISTRO}/setup.bash"
source "${WS_DIR}/install/setup.bash"
echo "[mockway] DISPLAY=\${DISPLAY:-} QT_QPA_PLATFORM=\${QT_QPA_PLATFORM:-}"
echo "[mockway] 启动 MoveIt Demo (use_mock_hardware:=${use_mock}) ..."
ros2 launch moveit_mockway_config demo.launch.py use_mock_hardware:=${use_mock}
EOF
}

cmd_launch_demo() {
    local use_mock="${1:-false}"
    resolve_repo
    prepare_moveit_gui_env
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        warn "未检测到 DISPLAY，RViz 需要图形桌面"
    fi
    log "启动 MoveIt2 Demo (use_mock_hardware:=${use_mock}) ..."
    source_mockway_env
    exec ros2 launch moveit_mockway_config demo.launch.py "use_mock_hardware:=${use_mock}" "${@:2}"
}

cmd_launch_demo_gui_window() {
    local use_mock="${1:-false}"
    local title="Mockway-MoveIt"
    [[ "$use_mock" == "true" ]] && title="Mockway-MoveIt-mock"

    resolve_repo
    source_mockway_env >/dev/null 2>&1 || {
        die "ROS/MoveIt 未就绪，请先: $0 moveit-install 或 moveit-rebuild"
    }

    prepare_moveit_gui_env
    local inner
    inner="$(build_moveit_launch_inner "$use_mock")"
    launch_in_graphical_terminal "$title" "$inner" 1
}

cmd_launch_moveit_demo() {
    resolve_repo
    export LANG="${LANG:-C.UTF-8}"
    export LC_ALL="${LC_ALL:-C.UTF-8}"
    prepare_moveit_gui_env
    export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"

    source_mockway_env
    echo "[mockway] QT_QPA_PLATFORM=$QT_QPA_PLATFORM DISPLAY=$DISPLAY"
    echo "[mockway] 启动 MoveIt Demo (真机 + USB-CAN，默认 /dev/ttyACM0) ..."
    echo "[mockway] 请先: setup_win_tools.bat 16 透传 USB；无硬件仿真请加 use_mock_hardware:=true"
    cmd_usb_serial_check || true
    exec ros2 launch moveit_mockway_config demo.launch.py use_mock_hardware:=false "$@"
}

cmd_work_shell() {
    resolve_repo
    log "进入 ROS 工作 Shell: $WS_DIR"
    local rcfile
    rcfile="$(mktemp /tmp/mockway_shell.XXXXXX)"
    cat > "$rcfile" <<EOF
# shellcheck disable=SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash" 2>/dev/null || true
# shellcheck disable=SC1091
source "${WS_DIR}/install/setup.bash" 2>/dev/null || true
cd "${WS_DIR}" 2>/dev/null || cd "${REPO_ROOT}"
export PS1="(mockway) \\u@\\h:\\w\\\$ "
EOF
    exec bash --rcfile "$rcfile" -i
}

cmd_usb_serial_check() {
    export DEBIAN_FRONTEND=noninteractive
    if command -v apt-get >/dev/null; then
        sudo -n apt-get install -y -qq usbutils 2>/dev/null \
            || sudo apt-get install -y -qq usbutils || true
    fi
    sudo modprobe cdc_acm 2>/dev/null || true
    sudo modprobe usbserial 2>/dev/null || true
    sudo modprobe ch341 2>/dev/null || true
    local id
    for id in "2e88 4603" "1a86 5523" "1a86 7523" "1a86 55d3"; do
        echo "$id" | sudo tee /sys/bus/usb-serial/drivers/ch341/new_id >/dev/null 2>&1 || true
    done
    sleep 3
    echo "=== lsusb ==="
    lsusb 2>/dev/null || echo "lsusb not found: sudo apt install usbutils"
    echo "=== serial devices ==="
    shopt -s nullglob
    local serial_devs=(/dev/ttyUSB* /dev/ttyACM* /dev/ttyCH343USB*)
    if ((${#serial_devs[@]} > 0)); then
        ls -la "${serial_devs[@]}"
        ls -la /dev/serial/by-id/* 2>/dev/null || true
        local dev
        for dev in "${serial_devs[@]}"; do
            sudo chmod 666 "$dev" 2>/dev/null || true
        done
        if ! groups "$USER" | grep -q '\bdialout\b'; then
            sudo usermod -aG dialout "$USER" 2>/dev/null || true
            echo "提示: 已将 $USER 加入 dialout，重新登录 WSL 后免 sudo 访问"
        fi
        echo "OK: 达妙 USB-CAN 已挂载，串口: ${serial_devs[*]}"
        echo "注意: 达妙 USB-CAN 在 WSL 下通常为 /dev/ttyACM0（已写入 xacro）"
    else
        echo "未发现 ttyUSB/ttyACM，请确认 usbipd 状态为 Attached"
    fi
    echo "=== dmesg usb ==="
    dmesg 2>/dev/null | grep -iE 'usb|ch34|cdc|tty|serial|2e88' | tail -25 || true
}

cmd_usb_serial() {
    resolve_repo
    echo ""
    echo "============================================================"
    echo " USB-CAN 串口检测与权限"
    echo " 插入 USB-CAN 适配器后检测 /dev/ttyUSB* / /dev/ttyACM*"
    echo "============================================================"
    echo ""

    as_root apt-get install -y -qq usbutils 2>/dev/null || true
    as_root modprobe cdc_acm 2>/dev/null || true
    as_root modprobe usbserial 2>/dev/null || true
    as_root modprobe ch341 2>/dev/null || true
    local id
    for id in "2e88 4603" "1a86 5523" "1a86 7523" "1a86 55d3"; do
        echo "$id" | as_root tee /sys/bus/usb-serial/drivers/ch341/new_id >/dev/null 2>&1 || true
    done

    if ! groups "$USER" | grep -q '\bdialout\b'; then
        log "将 $USER 加入 dialout 组 (需重新登录生效) ..."
        as_root usermod -aG dialout "$USER" || true
    fi

    echo ""
    echo "=== lsusb ==="
    lsusb 2>/dev/null || warn "lsusb 不可用: sudo apt install usbutils"
    echo ""
    echo "=== 串口设备 ==="
    ls -la /dev/ttyUSB* /dev/ttyACM* /dev/ttyCH343USB* /dev/serial/by-id/* 2>/dev/null \
        || echo "(未发现 ttyUSB/ttyACM，请确认适配器已插入)"
    echo ""
    echo "=== dmesg (usb) ==="
    dmesg 2>/dev/null | grep -iE 'usb|ch34|cdc|tty|serial|2e88' | tail -20 || true
    echo ""
    log "MoveIt xacro 默认端口: /dev/ttyACM0"
    log "临时授权: sudo chmod 666 /dev/ttyACM0"
    log "永久授权: 重新登录后 dialout 组成员可直接访问"
}

cmd_rebuild_ws() {
    resolve_repo
    export MOCKWAY_REPO_WSL MOCKWAY_WS_DIR="$WS_DIR"
    mkdir -p "$WS_DIR/src"
    local link="$WS_DIR/src/mockway_robotics"
    if [[ ! -e "$link" ]]; then
        ln -sf "$MOCKWAY_REPO_WSL" "$link"
    fi
    # shellcheck disable=SC1091
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
    cd "$WS_DIR"
    log "colcon 编译 mockway_description + dmmotor_hardware_interface + moveit_mockway_config ..."
    colcon build --symlink-install \
        --packages-select mockway_description dmmotor_hardware_interface moveit_mockway_config
    source_mockway_env
    ros2 pkg prefix moveit_mockway_config >/dev/null \
        || die "编译后仍未找到 moveit_mockway_config"
    log "编译完成。"
}

cmd_moveit_status() {
    resolve_repo
    echo ""
    echo "============================================================"
    echo " Mockway Ubuntu 环境诊断"
    echo "============================================================"
    echo " 用户:       $(id -un) (uid $(id -u))"
    echo " 仓库:       $MOCKWAY_REPO_WSL"
    echo " 工作空间:   $WS_DIR"
    echo " ROS:        ${ROS_DISTRO}"
    echo " 日志:       $LOG_FILE"
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo " 系统:       ${PRETTY_NAME:-unknown}"
    fi
    echo " DISPLAY:    ${DISPLAY:-(未设置)}"
    echo ""
    if [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]]; then
        echo "  ROS2 ${ROS_DISTRO}: 已安装"
    else
        echo "  ROS2 ${ROS_DISTRO}: 未安装"
    fi
    if [[ -f "$WS_DIR/install/setup.bash" ]]; then
        # shellcheck disable=SC1091
        source "/opt/ros/${ROS_DISTRO}/setup.bash" 2>/dev/null || true
        # shellcheck disable=SC1091
        source "$WS_DIR/install/setup.bash"
        echo "  mockway_ws:  已编译"
        echo "  moveit_mockway_config: $(ros2 pkg prefix moveit_mockway_config 2>/dev/null || echo 未找到)"
    else
        echo "  mockway_ws:  未编译"
    fi
    echo ""
    ls -la /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "  串口: (无 ttyUSB/ttyACM)"
    echo "============================================================"
}

moveit_dispatch() {
    local choice="${1:-}"
    case "$choice" in
        1) cmd_moveit_install_logged ;;
        2) cmd_launch_demo_gui_window false ;;
        3) cmd_work_shell ;;
        4) cmd_usb_serial ;;
        5) cmd_rebuild_ws ;;
        6) cmd_moveit_status ;;
        7) cmd_launch_demo_gui_window true ;;
        8) cmd_launch_demo false ;;
        9) cmd_gui_diagnose ;;
        0|q|Q) return 0 ;;
        *) die "无效 MoveIt 选项: $choice (可用 0-9)" ;;
    esac
}

moveit_menu() {
    while true; do
        check_ubuntu
        local repo="${MOCKWAY_REPO_WSL:-$REPO_ROOT}"
        local repo_hint=""
        [[ -d "$repo/moveit_mockway_config" ]] || repo_hint="(无效)"
        echo ""
        echo "============================================================"
        echo " Mockway - MoveIt2 工具菜单"
        echo "============================================================"
        echo "  仓库:     $repo $repo_hint"
        echo "  工作空间: $WS_DIR"
        echo "  日志:     $LOG_FILE"
        echo ""
        echo "  [1] 完整安装 (ROS2 Jazzy + MoveIt2 + mockway_ws)  [需 sudo]"
        echo "  --- 图形界面 (RViz) ---"
        echo "  [2] MoveIt + RViz (真机, 新图形终端)"
        echo "  [7] MoveIt + RViz (仿真 mock, 新图形终端)"
        echo "  [8] MoveIt + RViz (真机, 当前终端前台)"
        echo "  [9] 图形环境检测 (DISPLAY / Qt)"
        echo "  ---"
        echo "  [3] 打开 ROS 工作 Shell"
        echo "  [4] USB-CAN 串口检测与权限"
        echo "  [5] 仅重新编译工作空间"
        echo "  [6] 环境与诊断信息"
        echo "  [0] 返回"
        echo ""
        read -r -p "请选择 [0-9]: " choice
        echo ""
        moveit_dispatch "$choice" || true
        [[ "$choice" == "3" || "$choice" == "8" ]] && break
        echo ""
        read -r -p "按 Enter 返回菜单..." _
    done
}

# ============================================================
# 主菜单
# ============================================================

show_menu() {
    clear
    echo
    echo "============================================================"
    echo " Mockway 开发环境管理 (Ubuntu / WSL)"
    echo "============================================================"
    echo
    show_status
    echo
    echo "  [1] 安装 / 更新 conda 环境 (Miniconda + Pinocchio)"
    echo "  --- Ubuntu 图形桌面 (XFCE) ---"
    echo "  [10] 安装桌面组件 (XFCE, 首次)"
    echo "  [11] 启动 Ubuntu 桌面 (WSLg / 原生图形)"
    echo "  --- Python 调试工具 ---"
    echo "  [2] motor_gui (新终端窗口)"
    echo "  [3] 实时力矩补偿 (新终端窗口)"
    echo "  [4] 离线动力学测试 (新终端窗口)"
    echo "  [8] 图形环境检测"
    echo "  [9] 调试工具 — 当前终端前台"
    echo "  [5] 打开 Python 工作 shell"
    echo "  [6] 停止 (工具 + 桌面)"
    echo "  --- MoveIt / ROS2 ---"
    echo "  [20] 完整安装 ROS2 Jazzy + MoveIt2 + mockway_ws"
    echo "  [21] MoveIt + RViz 真机 (新图形终端)"
    echo "  [22] MoveIt + RViz 仿真 mock (新图形终端)"
    echo "  [23] MoveIt + RViz 真机 (当前终端)"
    echo "  [24] ROS 工作 Shell"
    echo "  [25] USB-CAN 串口检测"
    echo "  [26] 重新编译 mockway_ws"
    echo "  [27] MoveIt 环境诊断"
    echo "  [0] 退出"
    echo
}

main_menu() {
    while true; do
        show_menu
        read -r -p "请选择 [0-11,20-27]: " choice
        case "${choice:-}" in
            1) cmd_setup; read -r -p "按 Enter 继续..." _ ;;
            2) cmd_motor_gui; read -r -p "按 Enter 继续..." _ ;;
            3) cmd_torque; read -r -p "按 Enter 继续..." _ ;;
            4) cmd_inverse; read -r -p "按 Enter 继续..." _ ;;
            5) cmd_shell ;;
            6) cmd_stop; read -r -p "按 Enter 继续..." _ ;;
            8) cmd_gui_diagnose; read -r -p "按 Enter 继续..." _ ;;
            9) cmd_gui_foreground_menu; read -r -p "按 Enter 继续..." _ ;;
            10) cmd_install_ubuntu_desktop; read -r -p "按 Enter 继续..." _ ;;
            11) cmd_ubuntu_desktop; read -r -p "按 Enter 继续..." _ ;;
            20) cmd_moveit_install_logged; read -r -p "按 Enter 继续..." _ ;;
            21) cmd_launch_demo_gui_window false; read -r -p "按 Enter 继续..." _ ;;
            22) cmd_launch_demo_gui_window true; read -r -p "按 Enter 继续..." _ ;;
            23) cmd_launch_demo false ;;
            24) cmd_work_shell ;;
            25) cmd_usb_serial; read -r -p "按 Enter 继续..." _ ;;
            26) cmd_rebuild_ws; read -r -p "按 Enter 继续..." _ ;;
            27) cmd_moveit_status; read -r -p "按 Enter 继续..." _ ;;
            0|q|Q) exit 0 ;;
            *) warn "无效选择"; sleep 1 ;;
        esac
    done
}

moveit_cli() {
    case "${1:-}" in
        install|moveit-install) cmd_moveit_install_logged ;;
        demo|moveit-demo) shift; cmd_launch_moveit_demo "$@" ;;
        demo-gui|moveit-demo-gui) cmd_launch_demo_gui_window false ;;
        demo-mock|moveit-demo-mock) cmd_launch_demo_gui_window true ;;
        demo-fg|moveit-demo-fg) shift; cmd_launch_demo false "$@" ;;
        shell|ros-shell|moveit-shell) cmd_work_shell ;;
        usb|usb-serial|moveit-usb) cmd_usb_serial ;;
        usb-check) cmd_usb_serial_check ;;
        rebuild|moveit-rebuild) cmd_rebuild_ws ;;
        status|moveit-status) cmd_moveit_status ;;
        gui) cmd_gui_diagnose ;;
        "") moveit_menu ;;
        [0-9]) moveit_dispatch "$1" ;;
        *) die "未知 MoveIt 命令: $1" ;;
    esac
}

# ============================================================
# CLI
# ============================================================

case "${1:-}" in
    setup|install|1)              cmd_setup ;;
    motor_gui|gui|2)              cmd_motor_gui ;;
    torque|3)                     cmd_torque ;;
    inverse|4)                    cmd_inverse ;;
    shell|start|5)                cmd_shell ;;
    stop|6)                       cmd_stop ;;
    gui|8)                        cmd_gui_diagnose ;;
    gui-fg|foreground|9)          cmd_gui_foreground_menu ;;
    desktop-install|10)           cmd_install_ubuntu_desktop ;;
    desktop|11)                   cmd_ubuntu_desktop ;;
    moveit-install|install-moveit|20)
        cmd_moveit_install_logged
        ;;
    moveit-demo|demo|21)
        shift
        cmd_launch_moveit_demo "$@"
        ;;
    moveit-demo-gui|demo-gui|22)
        cmd_launch_demo_gui_window false
        ;;
    moveit-demo-mock|demo-mock)
        cmd_launch_demo_gui_window true
        ;;
    moveit-demo-fg|demo-fg|23)
        shift
        cmd_launch_demo false "$@"
        ;;
    ros-shell|moveit-shell|24)    cmd_work_shell ;;
    usb|usb-serial|moveit-usb|25) cmd_usb_serial ;;
    usb-check)                    cmd_usb_serial_check ;;
    moveit-rebuild|rebuild|26)    cmd_rebuild_ws ;;
    moveit-status|status|27)      cmd_moveit_status ;;
    moveit|7)                     shift; moveit_cli "${1:-}" ;;
    ""|menu)                      main_menu ;;
    -h|--help)
        cat <<EOF
用法: $0 [命令]

Python 调试:
  setup              安装 conda 环境
  motor_gui|2        motor_gui (新终端)
  torque|3           力矩补偿
  inverse|4          离线动力学
  shell|5            Python 工作 shell
  stop|6             停止工具/桌面
  gui|8              图形环境检测
  gui-fg|9           当前终端前台调试工具

Ubuntu 桌面:
  desktop-install|10 安装 XFCE
  desktop|11         启动 XFCE 桌面

MoveIt / ROS2:
  moveit-install|20  完整安装 ROS2 + MoveIt2
  moveit-demo|demo|21  MoveIt Demo 真机 (当前终端, 含 USB 检测)
  moveit-demo-gui|22 MoveIt Demo 真机 (新图形终端)
  moveit-demo-mock   MoveIt Demo 仿真 (新图形终端)
  ros-shell|24       ROS 工作 shell
  usb|25             USB-CAN 串口检测
  usb-check          WSL USB 透传后快速检测
  moveit-rebuild|26  重新编译工作空间
  moveit-status|27   环境诊断
  moveit             MoveIt 子菜单 (兼容旧编号 1-9)

  menu               交互主菜单 (默认)
EOF
        ;;
    *)
        die "未知命令: $1 (运行 $0 --help 查看)"
        ;;
esac
