#!/usr/bin/env bash
# ============================================================
#  Mockway - macOS 原生 ROS2 / MoveIt2 工具菜单
#  （对应 Windows 的 setup_wsl_moveit.bat）
#
#  macOS 不需要 Docker / WSL：通过 RoboStack（conda-forge 上预编译的
#  ROS2 二进制）直接把 ROS2 Jazzy + MoveIt2 装进 conda 环境，
#  RViz 以原生 macOS 窗口运行（无需 XQuartz）。
#
#  注意：dmmotor_hardware_interface 依赖 Linux 的 <linux/can.h> (SocketCAN)，
#  无法在 macOS 编译，故 macOS 上只编译 mockway_description +
#  moveit_mockway_config，并以 use_mock_hardware:=true 仿真运行。
#  接真机（USB-CAN）请使用 Linux (setup_moveit_ubuntu.sh) 或 Windows+WSL2。
#
#  用法:
#    ./tools/setup_moveit_mac.sh        # 菜单
#    ./tools/setup_moveit_mac.sh 1      # 直达选项 1
# ============================================================
set -eo pipefail

ENV_NAME="mockway_moveit"
ROS_DISTRO="jazzy"
WS_DIR="${MOCKWAY_WS_DIR:-$HOME/mockway_ws}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG="${TMPDIR:-/tmp}/mockway_moveit_mac.log"
MINICONDA_DIR="$HOME/miniconda3"
CONDA_SH=""

# macOS 上编译的包。dmmotor_hardware_interface 已做跨平台改造：
# SocketCAN(linux/can.h) 仅 Linux 编译，macOS 走 USB-CAN 串口(termios + IOSSIOSPEED)。
BUILD_PKGS="mockway_description dmmotor_hardware_interface moveit_mockway_config"

# RoboStack 频道（用完整 URL，避免被全局 ~/.condarc 的 custom_channels 重定向）
# conda-forge 默认走清华镜像，失败时自动回退官方源；robostack 只在 anaconda.org 上
CONDA_FORGE_MIRROR="${MOCKWAY_CONDA_FORGE_URL:-https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge}"
CONDA_FORGE_OFFICIAL="https://conda.anaconda.org/conda-forge"
ROBOSTACK_URL="${MOCKWAY_ROBOSTACK_URL:-https://conda.anaconda.org/robostack-${ROS_DISTRO}}"
CONDARC_TMP="${TMPDIR:-/tmp}/mockway_moveit_condarc.yaml"

# ROS2 / MoveIt2 包（RoboStack 命名: ros-<distro>-<pkg>）
ROS_PKGS=(
    "ros-${ROS_DISTRO}-desktop"
    "ros-${ROS_DISTRO}-moveit"
    "ros-${ROS_DISTRO}-moveit-setup-assistant"
    "ros-${ROS_DISTRO}-xacro"
    "ros-${ROS_DISTRO}-joint-state-publisher-gui"
    "ros-${ROS_DISTRO}-robot-state-publisher"
    "ros-${ROS_DISTRO}-ros2-control"
    "ros-${ROS_DISTRO}-ros2-controllers"
)
# colcon 编译工具链（conda-forge）
BUILD_TOOLS=(compilers cmake ninja pkg-config make colcon-common-extensions setuptools)

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "[警告] $*" >&2; }
err()  { printf '%s\n' "[错误] $*" >&2; }
pause() { read -r -p "按 Enter 返回菜单..." _ || true; }

# ------------------------------------------------------------
#  查找 conda（与 setup_mac.sh 一致）
# ------------------------------------------------------------
find_conda() {
    CONDA_SH=""
    local candidates=(
        "$HOME/miniconda3" "$HOME/anaconda3" "$HOME/miniforge3"
        "/opt/miniconda3" "/opt/anaconda3"
        "/opt/homebrew/Caskroom/miniconda/base"
    )
    local d
    for d in "${candidates[@]}"; do
        if [[ -f "$d/etc/profile.d/conda.sh" ]]; then
            CONDA_SH="$d/etc/profile.d/conda.sh"; MINICONDA_DIR="$d"; return 0
        fi
    done
    if command -v conda >/dev/null 2>&1; then
        local base; base="$(conda info --base 2>/dev/null || true)"
        if [[ -n "$base" && -f "$base/etc/profile.d/conda.sh" ]]; then
            CONDA_SH="$base/etc/profile.d/conda.sh"; MINICONDA_DIR="$base"; return 0
        fi
    fi
    return 1
}

ensure_conda() {
    if ! find_conda; then
        err "未检测到 Miniconda。请先运行 ./tools/setup_mac.sh 选 [1] 安装 Miniconda。"
        return 1
    fi
    # shellcheck disable=SC1090
    source "$CONDA_SH"
}

env_exists() { conda env list | grep -E "^$ENV_NAME[[:space:]]|/$ENV_NAME$" >/dev/null 2>&1; }

# 在 ROS 环境里执行一条命令
run_in_env() {
    bash -lc "source '$CONDA_SH' && conda activate '$ENV_NAME' && $1"
}

check_repo() {
    if [[ ! -d "$REPO_ROOT/moveit_mockway_config" ]]; then
        err "仓库无效: $REPO_ROOT (缺少 moveit_mockway_config)"
        return 1
    fi
}

# ------------------------------------------------------------
#  写隔离的 condarc（完整频道 URL + 严格优先级 + 重试），
#  通过 CONDARC 环境变量使用，绕开全局 ~/.condarc 的 custom_channels 重定向
# ------------------------------------------------------------
make_condarc() {
    local conda_forge_url="$1"
    cat > "$CONDARC_TMP" <<EOF
channels:
  - $conda_forge_url
  - $ROBOSTACK_URL
channel_priority: strict
show_channel_urls: true
remote_connect_timeout_secs: 30.0
remote_read_timeout_secs: 120.0
remote_max_retries: 5
remote_backoff_factor: 2
EOF
}

# 用隔离 condarc 运行 conda，并保留真实退出码（避免被 tee 掩盖）
conda_do() {
    CONDARC="$CONDARC_TMP" conda "$@" 2>&1 | tee -a "$LOG"
    return "${PIPESTATUS[0]}"
}

# 用给定 conda-forge 源完整安装一次（create 或 install）
_install_ros_deps_once() {
    local all=("${ROS_PKGS[@]}" "${BUILD_TOOLS[@]}")
    if env_exists; then
        say "[ros] 环境 $ENV_NAME 已存在，安装/更新 ROS + 编译工具 ..."
        conda_do install -n "$ENV_NAME" -y "${all[@]}" || return 1
    else
        say "[ros] 创建 RoboStack 环境 $ENV_NAME（ROS2 ${ROS_DISTRO} + MoveIt2 + 编译工具）..."
        conda_do create -n "$ENV_NAME" -y "${all[@]}" || return 1
    fi
    env_exists || { err "环境创建后仍不存在，可能是下载中断"; return 1; }
}

# ------------------------------------------------------------
#  安装 / 更新 RoboStack ROS 依赖（镜像源失败自动回退官方源）
# ------------------------------------------------------------
install_ros_deps() {
    say "[ros] conda-forge 源: $CONDA_FORGE_MIRROR"
    say "[ros] robostack 源:   $ROBOSTACK_URL"
    make_condarc "$CONDA_FORGE_MIRROR"
    if _install_ros_deps_once; then
        return 0
    fi
    warn "镜像源安装失败，回退官方 conda-forge 源重试 ..."
    make_condarc "$CONDA_FORGE_OFFICIAL"
    _install_ros_deps_once
}

# ------------------------------------------------------------
#  创建工作空间并 colcon 编译
# ------------------------------------------------------------
build_ws() {
    mkdir -p "$WS_DIR/src"
    # 旧版会把整个仓库 symlink 进 src，使 colcon 发现仓库内全部包（含 macOS 编不了的
    # mockway_lua_moveit 等）。这里清理掉，改为只按包逐个链接需要编译的包。
    local whole="$WS_DIR/src/mockway_robotics"
    if [[ -L "$whole" ]]; then
        rm -f "$whole"
        say "[ws] 已移除旧的整仓库链接: $whole"
    fi
    # 只把 macOS 能编译的包链接进工作空间，避免 colcon 发现/依赖 dmmotor_hardware_interface
    local pkg
    for pkg in $BUILD_PKGS; do
        local link="$WS_DIR/src/$pkg"
        if [[ ! -e "$REPO_ROOT/$pkg/package.xml" ]]; then
            err "未找到包: $REPO_ROOT/$pkg"
            return 1
        fi
        rm -f "$link" 2>/dev/null || true
        ln -s "$REPO_ROOT/$pkg" "$link"
        say "[ws] 链接包 -> $link"
        # 清理上一次（旧 src 布局）残留的 build/install，避免 CMakeCache 里的源路径失效
        rm -rf "$WS_DIR/build/$pkg" "$WS_DIR/install/$pkg" 2>/dev/null || true
    done
    say "[ws] colcon 编译: $BUILD_PKGS"
    run_in_env "cd '$WS_DIR' && colcon build --symlink-install --packages-select $BUILD_PKGS" 2>&1 | tee -a "$LOG"
    local rc=${PIPESTATUS[0]}
    if [[ $rc -ne 0 ]]; then
        err "colcon 编译失败，退出码 $rc。详见日志: $LOG"
        return 1
    fi
    say "[ws] 编译完成: $WS_DIR/install"
}

# ------------------------------------------------------------
#  [1] 完整安装
# ------------------------------------------------------------
do_full_install() {
    say ""
    say "============================================================"
    say " macOS 原生 ROS2 Jazzy + MoveIt2 (RoboStack) 完整安装"
    say " conda 环境: $ENV_NAME   日志: $LOG"
    say "============================================================"
    say ""
    ensure_conda || return 1
    check_repo || return 1
    install_ros_deps || { err "ROS 依赖安装失败"; return 1; }
    build_ws || return 1
    say ""
    say "============================================================"
    say " 安装完成。菜单 [3] 启动 MoveIt2 Demo（可选仿真 / 真机 USB-CAN）。"
    say " 手动启动: conda activate $ENV_NAME"
    say "           source $WS_DIR/install/setup.bash"
    say "           # 仿真:  ros2 launch moveit_mockway_config demo.launch.py use_mock_hardware:=true"
    say "           # 真机:  ros2 launch moveit_mockway_config demo.launch.py use_mock_hardware:=false"
    say "============================================================"
}

# ------------------------------------------------------------
#  [2] 仅安装/更新 ROS 依赖
# ------------------------------------------------------------
do_install_deps() {
    ensure_conda || return 1
    install_ros_deps && say "[完成] ROS 依赖已安装/更新。菜单 [9] 编译，[3] 启动 Demo。"
}

# ------------------------------------------------------------
#  [3] 启动 MoveIt2 Demo (RViz 原生窗口)；可选仿真 / 真机 USB-CAN
#      参数: mock(默认) | real
# ------------------------------------------------------------
do_launch_demo() {
    ensure_conda || return 1
    if ! env_exists; then err "环境 $ENV_NAME 不存在，请先选 [1] 完整安装。"; return 1; fi
    if [[ ! -f "$WS_DIR/install/setup.bash" ]]; then
        err "工作空间未编译: $WS_DIR，请先选 [1] 或 [9]。"; return 1
    fi
    local mode="${1:-}"
    if [[ -z "$mode" ]]; then
        local m
        read -r -p "硬件模式? [1] 仿真 mock(默认)  [2] 真机 USB-CAN : " m
        case "$m" in 2|real|REAL) mode="real";; *) mode="mock";; esac
    fi
    local mock="true"
    [[ "$mode" == "real" || "$mode" == "2" ]] && mock="false"

    if [[ "$mock" == "false" ]]; then
        say "[mockway] 真机模式 (use_mock_hardware:=false) — USB-CAN 串口直连"
        say "[mockway] 请确认 xacro 的 ros2_control 参数: can_type=usb_can,"
        say "          can_interface 指向 macOS 串口设备（/dev/tty.usbserial-* 或 /dev/tty.usbmodem*）"
        say "          当前已连接串口:"
        ls /dev/tty.usb* 2>/dev/null | sed 's/^/            /' || say "            (未发现 /dev/tty.usb*，请插入 USB-CAN 适配器)"
    else
        say "[mockway] 仿真模式 (use_mock_hardware:=true, mock_components/GenericSystem)"
    fi
    say "[mockway] 启动 MoveIt2 Demo (RViz 原生窗口) ..."
    run_in_env "source '$WS_DIR/install/setup.bash' && export QT_QPA_PLATFORM=cocoa && ros2 launch moveit_mockway_config demo.launch.py use_mock_hardware:=$mock"
}

# ------------------------------------------------------------
#  [4] ROS 工作 Shell
# ------------------------------------------------------------
do_shell() {
    ensure_conda || return 1
    if ! env_exists; then err "环境 $ENV_NAME 不存在，请先选 [1] 完整安装。"; return 1; fi
    say "[ros] 进入 ROS 工作 Shell (环境 $ENV_NAME) ..."
    local src_ws=""
    [[ -f "$WS_DIR/install/setup.bash" ]] && src_ws="source '$WS_DIR/install/setup.bash' 2>/dev/null;"
    bash -lc "source '$CONDA_SH' && conda activate '$ENV_NAME' && $src_ws cd '$WS_DIR' 2>/dev/null || cd '$REPO_ROOT'; export PS1='(mockway-ros) \\u@\\h:\\w\\\$ '; exec bash -i"
}

# ------------------------------------------------------------
#  [5] 环境诊断
# ------------------------------------------------------------
do_status() {
    say ""
    say "============================================================"
    say " Mockway macOS / MoveIt2 (RoboStack) 环境诊断"
    say "============================================================"
    say " 仓库:     $REPO_ROOT"
    say " 工作空间: $WS_DIR"
    say " conda 环境: $ENV_NAME"
    say " ROS:      $ROS_DISTRO"
    say " 日志:     $LOG"
    if find_conda; then
        # shellcheck disable=SC1090
        source "$CONDA_SH"
        if env_exists; then
            say "  conda 环境 $ENV_NAME: 已创建"
            if run_in_env "command -v ros2 >/dev/null 2>&1"; then
                say "  ros2:       $(run_in_env "ros2 --version 2>/dev/null" 2>/dev/null || echo 可用)"
            else
                say "  ros2:       未安装（请选 [1]/[2]）"
            fi
        else
            say "  conda 环境 $ENV_NAME: 未创建（请选 [1]）"
        fi
    else
        say "  Miniconda:  未安装（先运行 setup_mac.sh [1]）"
    fi
    if [[ -f "$WS_DIR/install/setup.bash" ]]; then
        say "  mockway_ws: 已编译"
    else
        say "  mockway_ws: 未编译"
    fi
    say ""
    ls -la /dev/tty.usb* /dev/tty.usbserial* /dev/tty.usbmodem* 2>/dev/null \
        || say "  串口: (无 /dev/tty.usb* 设备)"
    say "============================================================"
}

# ------------------------------------------------------------
#  [6] 真机 / USB-CAN 说明
# ------------------------------------------------------------
do_hw_info() {
    say ""
    say "============================================================"
    say " 真机 / USB-CAN 说明 (macOS)"
    say "============================================================"
    say " dmmotor_hardware_interface 已做跨平台改造:"
    say "   - SocketCAN (linux/can.h, can0): 仅 Linux 支持，macOS 不可用"
    say "   - USB-CAN 串口 (达妙 / 维特适配器): macOS 可用 ✔"
    say "     (termios + IOSSIOSPEED 设置 921600 波特率)"
    say ""
    say " macOS 接真机步骤:"
    say "   1. 插入 USB-CAN 适配器，确认下方出现 /dev/tty.usbserial-* 或 /dev/tty.usbmodem*"
    say "   2. 在 xacro 的 ros2_control hardware 参数中设置:"
    say "        <param name=\"can_type\">usb_can</param>"
    say "        <param name=\"can_interface\">/dev/tty.usbserial-XXXX</param>"
    say "        <param name=\"usb_can_adapter\">damiao</param>   # 或 witmotion / auto"
    say "   3. 菜单 [3] 选 [2] 真机，或运行: tools/setup_moveit_mac.sh 3 real"
    say ""
    say " 注: 若要用 can0 这种内核 SocketCAN 接口，仍需 Linux (setup_moveit_ubuntu.sh)"
    say "     或 Windows+WSL2 (setup_wsl_moveit.bat, 含 usbipd 透传)。"
    say ""
    say " 当前 macOS 已连接的串口设备:"
    ls -la /dev/tty.usb* /dev/tty.usbserial* /dev/tty.usbmodem* 2>/dev/null \
        || say "  (未发现 /dev/tty.usb* 设备，请插入 USB-CAN 适配器)"
}

# ------------------------------------------------------------
#  [9] 重新编译 mockway_ws
# ------------------------------------------------------------
do_rebuild() {
    ensure_conda || return 1
    if ! env_exists; then err "环境 $ENV_NAME 不存在，请先选 [1] 完整安装。"; return 1; fi
    check_repo || return 1
    say ""
    say "============================================================"
    say " colcon 重新编译: $BUILD_PKGS"
    say "============================================================"
    build_ws && say "[完成] 编译成功。菜单 [3] 启动 Demo。"
}

# ------------------------------------------------------------
#  菜单
# ------------------------------------------------------------
show_menu() {
    local status="未检测"
    if find_conda; then
        # shellcheck disable=SC1090
        source "$CONDA_SH" 2>/dev/null || true
        if env_exists; then
            if [[ -f "$WS_DIR/install/setup.bash" ]]; then status="已安装+已编译"
            else status="ROS 已装, 未编译"; fi
        else status="conda 就绪, 未装 ROS"; fi
    else
        status="Miniconda 未安装"
    fi
    clear
    say ""
    say "============================================================"
    say " Mockway - macOS ROS2 / MoveIt2 工具菜单 (RoboStack, 原生)"
    say "============================================================"
    say " conda 环境: $ENV_NAME ($status)"
    say " 仓库: $REPO_ROOT"
    say " 工作空间: $WS_DIR    日志: $LOG"
    say ""
    say " [1] 完整安装 (RoboStack ROS2 Jazzy + MoveIt2 + 编译 mockway_ws)"
    say " [2] 仅安装/更新 ROS 依赖 (conda-forge + robostack-jazzy)"
    say " [3] 启动 MoveIt2 Demo (RViz 原生窗口; 可选仿真 / 真机 USB-CAN)"
    say " [4] 打开 ROS 工作 Shell"
    say " [5] 环境诊断"
    say " [6] 真机 / USB-CAN 说明"
    say " [9] 重新编译 mockway_ws (colcon)"
    say " [0] 退出"
    say ""
}

dispatch() {
    local choice="$1"; shift || true
    case "$choice" in
        1) do_full_install ;;
        2) do_install_deps ;;
        3) do_launch_demo "$@" ;;
        4) do_shell ;;
        5) do_status ;;
        6) do_hw_info ;;
        9|rebuild) do_rebuild ;;
        0|q|Q) exit 0 ;;
        *) err "无效选项: $choice"; return 1 ;;
    esac
}

# 命令行直达（如: setup_moveit_mac.sh 3 real）
if [[ -n "${1:-}" ]]; then
    dispatch "$@"
    exit $?
fi

while true; do
    show_menu
    read -r -p "请选择 [0-9]: " choice
    say ""
    dispatch "$choice" || true
    say ""
    pause
done
