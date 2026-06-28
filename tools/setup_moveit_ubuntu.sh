#!/usr/bin/env bash
# Mockway — Ubuntu 24.04 原生环境统一入口（对应 Windows 的 setup_wsl_moveit.bat）
# 用法:
#   ./tools/setup_moveit_ubuntu.sh          # 菜单
#   ./tools/setup_moveit_ubuntu.sh 3        # 直达选项 3
set -eo pipefail

ROS_DISTRO="${MOCKWAY_ROS_DISTRO:-jazzy}"
WS_DIR="${MOCKWAY_WS_DIR:-$HOME/mockway_ws}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_SCRIPT="$SCRIPT_DIR/wsl/setup_moveit_jazzy.sh"
LOG_FILE="${MOCKWAY_LOG:-/tmp/mockway_ubuntu_setup.log}"

log()  { echo "[mockway] $*"; }
warn() { echo "[mockway][警告] $*" >&2; }
die()  { echo "[mockway][错误] $*" >&2; exit 1; }

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
    [[ -f "/opt/ros/${ROS_DISTRO}/setup.bash" ]] || die "未安装 ROS2 ${ROS_DISTRO}，请先选 [1] 完整安装"
    source "/opt/ros/${ROS_DISTRO}/setup.bash"
    if [[ -f "$WS_DIR/install/setup.bash" ]]; then
        # shellcheck disable=SC1091
        source "$WS_DIR/install/setup.bash"
    else
        die "工作空间未编译: $WS_DIR (请先选 [1] 或 [6])"
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

# ------------------------------------------------------------
# [1] 完整安装
# ------------------------------------------------------------
cmd_full_install() {
    resolve_repo
    log "完整安装 -> 日志: $LOG_FILE"
    export MOCKWAY_REPO_WSL MOCKWAY_WS_DIR
    bash "$INSTALL_SCRIPT" 2>&1 | tee -a "$LOG_FILE"
}

# ------------------------------------------------------------
# [2] 启动 MoveIt Demo
# ------------------------------------------------------------
cmd_launch_demo() {
    resolve_repo
    if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
        warn "未检测到 DISPLAY/WAYLAND_DISPLAY，RViz 需要图形桌面"
    fi
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    export DISPLAY="${DISPLAY:-:0}"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}"
    export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
    export GDK_BACKEND="${GDK_BACKEND:-x11}"
    log "启动 MoveIt2 Demo ..."
    source_mockway_env
    exec ros2 launch moveit_mockway_config demo.launch.py use_mock_hardware:=true "$@"
}

# ------------------------------------------------------------
# [3] 工作 Shell
# ------------------------------------------------------------
cmd_work_shell() {
    resolve_repo
    log "进入工作 Shell: $WS_DIR"
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

# ------------------------------------------------------------
# [4] USB-CAN 串口检测与权限
# ------------------------------------------------------------
cmd_usb_serial() {
    resolve_repo
    echo ""
    echo "============================================================"
    echo " USB-CAN 串口 (原生 Linux，无需 usbipd)"
    echo " 插入 USB-CAN 适配器后检测 /dev/ttyUSB* / /dev/ttyACM*"
    echo "============================================================"
    echo ""

    as_root apt-get install -y -qq usbutils 2>/dev/null || true
    as_root modprobe cdc_acm 2>/dev/null || true
    as_root modprobe usbserial 2>/dev/null || true
    as_root modprobe ch341 2>/dev/null || true
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

# ------------------------------------------------------------
# [5] 仅重新编译工作空间
# ------------------------------------------------------------
cmd_rebuild_ws() {
    resolve_repo
    export MOCKWAY_REPO_WSL MOCKWAY_WS_DIR
    mkdir -p "$WS_DIR/src"
    LINK="$WS_DIR/src/mockway_robotics"
    if [[ ! -e "$LINK" ]]; then
        ln -sf "$MOCKWAY_REPO_WSL" "$LINK"
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

# ------------------------------------------------------------
# [6] 环境与诊断
# ------------------------------------------------------------
cmd_status() {
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

# ------------------------------------------------------------
# 菜单
# ------------------------------------------------------------
show_menu() {
    check_ubuntu
    local repo="${MOCKWAY_REPO_WSL:-$REPO_ROOT}"
    local repo_hint=""
    if [[ ! -d "$repo/moveit_mockway_config" ]]; then
        repo_hint="(无效)"
    fi
    echo ""
    echo "============================================================"
    echo " Mockway - Ubuntu / MoveIt2 工具菜单"
    echo "============================================================"
    echo "  仓库:     $repo $repo_hint"
    echo "  工作空间: $WS_DIR"
    echo "  日志:     $LOG_FILE"
    echo ""
    echo "  [1] 完整安装 (ROS2 Jazzy + MoveIt2 + mockway_ws)  [需 sudo]"
    echo "  [2] 启动 MoveIt2 Demo (RViz)"
    echo "  [3] 打开工作 Shell"
    echo "  [4] USB-CAN 串口检测与权限"
    echo "  [5] 仅重新编译工作空间"
    echo "  [6] 环境与诊断信息"
    echo "  [0] 退出"
    echo ""
}

dispatch() {
    local choice="${1:-}"
    case "$choice" in
        1) cmd_full_install ;;
        2) cmd_launch_demo ;;
        3) cmd_work_shell ;;
        4) cmd_usb_serial ;;
        5) cmd_rebuild_ws ;;
        6) cmd_status ;;
        0|q|Q) exit 0 ;;
        *)
            die "无效选项: $choice (可用 0-6)"
            ;;
    esac
}

main_menu() {
    while true; do
        show_menu
        read -r -p "请选择 [0-6]: " choice
        echo ""
        dispatch "$choice" || true
        echo ""
        read -r -p "按 Enter 返回菜单..." _
    done
}

# 非交互: setup_moveit_ubuntu.sh install | demo | shell | usb | rebuild | status
if [[ "${1:-}" == "install" ]]; then cmd_full_install; exit 0; fi
if [[ "${1:-}" == "demo" ]]; then cmd_launch_demo; exit 0; fi
if [[ "${1:-}" == "shell" ]]; then cmd_work_shell; exit 0; fi
if [[ "${1:-}" == "usb" ]]; then cmd_usb_serial; exit 0; fi
if [[ "${1:-}" == "rebuild" ]]; then cmd_rebuild_ws; exit 0; fi
if [[ "${1:-}" == "status" ]]; then cmd_status; exit 0; fi

if [[ -n "${1:-}" ]]; then
    dispatch "$1"
    exit 0
fi

main_menu
