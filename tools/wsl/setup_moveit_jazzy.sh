#!/usr/bin/env bash
# Mockway — Ubuntu 24.04 (WSL2) 内安装 ROS2 Jazzy + MoveIt2 并编译工作空间
set -euo pipefail

ROS_DISTRO="jazzy"
WS_DIR="${MOCKWAY_WS_DIR:-$HOME/mockway_ws}"
REPO_WSL="${MOCKWAY_REPO_WSL:-}"

log() { echo "[mockway-wsl] $*"; }
die() { echo "[mockway-wsl][错误] $*" >&2; exit 1; }

if [[ -z "$REPO_WSL" ]]; then
    die "未设置 MOCKWAY_REPO_WSL。请由 Windows 安装脚本传入仓库 WSL 路径。"
fi

if [[ ! -d "$REPO_WSL/moveit_mockway_config" ]]; then
    die "仓库路径无效: $REPO_WSL"
fi

export DEBIAN_FRONTEND=noninteractive
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

log "更新 apt ..."
sudo apt-get update -y

log "配置 locale 与 universe 仓库 ..."
sudo apt-get install -y locales software-properties-common
sudo locale-gen en_US en_US.UTF-8 2>/dev/null || true
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 2>/dev/null || true
sudo add-apt-repository -y universe 2>/dev/null || true
sudo apt-get update -y

log "安装基础工具 ..."
sudo apt-get install -y \
    curl gnupg lsb-release \
    build-essential git wget \
    python3-pip \
    liblua5.4-dev

if [[ ! -f /etc/apt/sources.list.d/ros2.list ]]; then
    log "添加 ROS2 ${ROS_DISTRO} apt 源 ..."
    sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
        | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
    sudo apt-get update -y
else
    log "ROS2 apt 源已存在，跳过。"
    sudo apt-get update -y
fi

log "安装 colcon / rosdep / vcstool ..."
if ! sudo apt-get install -y \
    python3-colcon-common-extensions \
    python3-rosdep \
    python3-vcstool; then
    log "尝试通过 ros-dev-tools 安装构建工具 ..."
    sudo apt-get install -y ros-dev-tools
fi

log "安装 ROS2 ${ROS_DISTRO} 与 MoveIt2 ..."
sudo apt-get install -y \
    "ros-${ROS_DISTRO}-ros-base" \
    "ros-${ROS_DISTRO}-moveit" \
    "ros-${ROS_DISTRO}-moveit-setup-assistant" \
    "ros-${ROS_DISTRO}-moveit-ros-visualization" \
    "ros-${ROS_DISTRO}-rviz2" \
    "ros-${ROS_DISTRO}-xacro" \
    "ros-${ROS_DISTRO}-joint-state-publisher-gui" \
    "ros-${ROS_DISTRO}-robot-state-publisher" \
    "ros-${ROS_DISTRO}-controller-manager"

if ! rosdep --version >/dev/null 2>&1; then
    log "初始化 rosdep ..."
    sudo rosdep init 2>/dev/null || true
fi
rosdep update || true

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

log "colcon 编译 mockway_description + moveit_mockway_config ..."
colcon build --symlink-install \
    --packages-select mockway_description moveit_mockway_config

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
ros2 pkg list | grep -q moveit_mockway_config || die "moveit_mockway_config 未找到"

log "=========================================="
log "安装完成。"
log "启动 MoveIt Demo:"
log "  source ~/mockway_ws/install/setup.bash"
log "  ros2 launch moveit_mockway_config demo.launch.py"
log "或在 Windows 运行: tools\\wsl\\launch_moveit_demo.bat"
log "=========================================="
