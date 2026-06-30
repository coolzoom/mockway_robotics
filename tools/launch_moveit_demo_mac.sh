#!/usr/bin/env bash
# ============================================================
#  Mockway - macOS 一键启动 MoveIt2 Demo
#  （对应 Windows 的 launch_moveit_demo.bat）
#
#  通过 RoboStack（conda 原生 ROS2 Jazzy）启动 RViz，
#  RViz 以原生 macOS 窗口运行，无需 Docker / XQuartz。
#  默认 use_mock_hardware:=true（macOS 仅仿真，真机请用 Linux/WSL2）。
#
#  首次使用请先运行: tools/setup_moveit_mac.sh 1  (完整安装)
# ============================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/setup_moveit_mac.sh" ]]; then
    echo "[错误] 找不到 $SCRIPT_DIR/setup_moveit_mac.sh" >&2
    exit 1
fi

echo "[mockway] 启动 MoveIt2 Demo (RoboStack / RViz 原生窗口) ..."
exec bash "$SCRIPT_DIR/setup_moveit_mac.sh" 3
