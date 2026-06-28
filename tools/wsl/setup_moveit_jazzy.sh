#!/usr/bin/env bash
# Mockway — Ubuntu 24.04 (WSL2) 内安装 ROS2 Jazzy + MoveIt2 并编译工作空间
# 不用 set -u：ROS setup.bash 会引用未定义变量 (如 AMENT_TRACE_SETUP_FILES)
set -eo pipefail

ROS_DISTRO="jazzy"
WS_DIR="${MOCKWAY_WS_DIR:-$HOME/mockway_ws}"
REPO_WSL="${MOCKWAY_REPO_WSL:-}"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "$REPO_WSL" ]]; then
    REPO_WSL="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

log() { echo "[mockway-wsl] $*"; }
die() { echo "[mockway-wsl][错误] $*" >&2; exit 1; }

# root 直接执行；普通用户需免密 sudo（由 Windows 安装脚本预先配置）
as_root() {
    if [[ $(id -u) -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

ensure_sudo_access() {
    if [[ $(id -u) -eq 0 ]]; then
        if getent passwd test >/dev/null 2>&1; then
            die "检测到 root 运行，但 test 用户已存在。请用 test 安装:
  wsl -u test -- env MOCKWAY_REPO_WSL='$REPO_WSL' bash '$SCRIPT_PATH'
或在 Linux 运行: ./tools/setup_moveit_ubuntu.sh 选 [2]"
        fi
        log "警告: 以 root 运行，工作空间: ${WS_DIR}"
        return 0
    fi
    if sudo -v 2>/dev/null; then
        return 0
    fi
    die "用户 $(id -un) 需要 sudo 权限。"
}

if [[ -z "$REPO_WSL" ]] || [[ ! -d "$REPO_WSL/moveit_mockway_config" ]]; then
    die "仓库路径无效: ${REPO_WSL:-未设置} (需要 moveit_mockway_config 目录)"
fi

ensure_sudo_access

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

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

if ! rosdep --version >/dev/null 2>&1; then
    die "rosdep 未安装，请检查 apt 安装步骤"
fi

ROSDEP_MIRROR="${MOCKWAY_ROSDEP_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/rosdistro}"
export ROSDISTRO_INDEX_URL="${ROSDEP_MIRROR}/index-v4.yaml"

init_rosdep_sources() {
    local list="/etc/ros/rosdep/sources.list.d/20-default.list"
    if [[ -f "$list" ]]; then
        log "rosdep sources 已存在，跳过 init"
        return 0
    fi
    log "写入 rosdep 源（国内镜像，避免 GitHub 超时）..."
    as_root mkdir -p /etc/ros/rosdep/sources.list.d
    as_root tee "$list" > /dev/null <<EOF
yaml ${ROSDEP_MIRROR}/rosdep/base.yaml
yaml ${ROSDEP_MIRROR}/rosdep/python.yaml
yaml ${ROSDEP_MIRROR}/rosdep/ruby.yaml
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

log "初始化 rosdep ..."
init_rosdep_sources
update_rosdep_with_retry || true

log "创建工作空间: $WS_DIR"
mkdir -p "$WS_DIR/src"
LINK_PATH="$WS_DIR/src/mockway_robotics"
if [[ -L "$LINK_PATH" ]]; then
    log "符号链接已存在: $LINK_PATH"
elif [[ -d "$LINK_PATH" ]]; then
    log "目录已存在: $LINK_PATH（未覆盖）"
else
    ln -s "$REPO_WSL" "$LINK_PATH"
    log "已链接仓库 -> $LINK_PATH"
fi

log "安装 rosdep 依赖 (moveit_mockway_config) ..."
cd "$WS_DIR"
# shellcheck disable=SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
rosdep install --from-paths src/mockway_robotics/moveit_mockway_config \
    --ignore-src -r -y || log "rosdep 部分包警告（可忽略未解析项）"

log "colcon 编译 mockway_description + dmmotor_hardware_interface + moveit_mockway_config ..."
if ! colcon build --symlink-install \
    --packages-select mockway_description dmmotor_hardware_interface moveit_mockway_config; then
    die "colcon 编译失败，请查看上方错误输出"
fi

BASHRC="$HOME/.bashrc"
MARKER="# >>> mockway ros2 ${ROS_DISTRO} >>>"
if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
    log "写入 ~/.bashrc 环境 ..."
    cat >> "$BASHRC" <<EOF

$MARKER
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
if ! ros2 pkg prefix moveit_mockway_config &>/dev/null; then
    die "moveit_mockway_config 未找到（colcon 可能失败，见上方日志）"
fi

log "=========================================="
log "安装完成。"
log "启动 MoveIt Demo:"
log "  source ~/mockway_ws/install/setup.bash"
log "  ros2 launch moveit_mockway_config demo.launch.py"
log "  (Demo 默认 use_mock_hardware:=false，接 USB-CAN 真机 /dev/ttyACM0)"
log "  无硬件仿真: ros2 launch moveit_mockway_config demo.launch.py use_mock_hardware:=true"
log "或在 Linux 运行: tools/setup_moveit_ubuntu.sh 选 [2]"
log "=========================================="
