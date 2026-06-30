import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from moveit_configs_utils.launch_utils import DeclareBooleanLaunchArg


def generate_launch_description():
    pkg_path = get_package_share_directory("moveit_mockway_config")

    ld = LaunchDescription()
    ld.add_action(
        DeclareBooleanLaunchArg(
            "db",
            default_value=False,
            description="By default, we do not start a database (it can be large)",
        )
    )
    ld.add_action(
        DeclareBooleanLaunchArg(
            "debug",
            default_value=False,
            description="By default, we are not in debug mode",
        )
    )
    ld.add_action(DeclareBooleanLaunchArg("use_rviz", default_value=True))
    ld.add_action(
        DeclareLaunchArgument(
            "use_mock_hardware",
            default_value="false",
            description="使用 mock_components/GenericSystem 替代真实硬件（dmmotor_hardware_interface/DMMototHardwareInterface）",
        )
    )
    ld.add_action(
        DeclareLaunchArgument(
            "can_interface",
            default_value="/dev/ttyACM0",
            description="USB-CAN 串口设备：WSL/Linux 默认 /dev/ttyACM0；macOS 用 /dev/cu.usbmodem*",
        )
    )
    ld.add_action(
        DeclareLaunchArgument(
            "collision_mode",
            default_value="mesh",
            description="碰撞几何: mesh(默认, Linux/WSL) | primitive(macOS 包围盒, 规避 FCL 崩溃)",
        )
    )

    launch_args = {
        "use_mock_hardware": LaunchConfiguration("use_mock_hardware"),
        "can_interface": LaunchConfiguration("can_interface"),
        "collision_mode": LaunchConfiguration("collision_mode"),
    }

    virtual_joints_launch = os.path.join(pkg_path, "launch", "static_virtual_joint_tfs.launch.py")
    if os.path.exists(virtual_joints_launch):
        ld.add_action(
            IncludeLaunchDescription(
                PythonLaunchDescriptionSource(virtual_joints_launch),
            )
        )

    ld.add_action(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(pkg_path, "launch", "rsp.launch.py")),
            launch_arguments=launch_args.items(),
        )
    )
    ld.add_action(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(pkg_path, "launch", "move_group.launch.py")),
            launch_arguments=launch_args.items(),
        )
    )
    ld.add_action(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(pkg_path, "launch", "moveit_rviz.launch.py")),
            condition=IfCondition(LaunchConfiguration("use_rviz")),
        )
    )
    ld.add_action(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(pkg_path, "launch", "warehouse_db.launch.py")),
            condition=IfCondition(LaunchConfiguration("db")),
        )
    )

    # Jazzy: controller_manager 订阅 /robot_description，由 robot_state_publisher 发布（勿用旧版 remapping）
    ld.add_action(
        Node(
            package="controller_manager",
            executable="ros2_control_node",
            parameters=[os.path.join(pkg_path, "config", "ros2_controllers.yaml")],
            output="screen",
        )
    )
    ld.add_action(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(os.path.join(pkg_path, "launch", "spawn_controllers.launch.py")),
        )
    )

    return ld
