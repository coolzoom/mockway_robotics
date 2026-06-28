#!/usr/bin/env bash
# WSLg 下启动 MoveIt Demo（设置 GUI 环境变量，避免 RViz 空白/最小化）
set -eo pipefail

export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

# WSLg 图形栈（未设置时补默认值）
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}"
export PULSE_SERVER="${PULSE_SERVER:-unix:/mnt/wslg/PulseServer}"

# Qt6 / OGRE 在 Jazzy + WSLg 下须走 X11 (xcb)，Wayland 会触发 GLX parentWindowHandle 错误
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export GDK_BACKEND="${GDK_BACKEND:-x11}"

ROS_DISTRO="${MOCKWAY_ROS_DISTRO:-jazzy}"
WS_DIR="${MOCKWAY_WS_DIR:-$HOME/mockway_ws}"

# shellcheck disable=SC1091
source "/opt/ros/${ROS_DISTRO}/setup.bash"
# shellcheck disable=SC1091
source "${WS_DIR}/install/setup.bash"

echo "[mockway] QT_QPA_PLATFORM=$QT_QPA_PLATFORM DISPLAY=$DISPLAY"
echo "[mockway] 启动 MoveIt Demo (mock 硬件，无需 USB-CAN) ..."
exec ros2 launch moveit_mockway_config demo.launch.py use_mock_hardware:=true "$@"
