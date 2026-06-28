import os

from launch import LaunchDescription
from launch.actions import (
    DeclareLaunchArgument,
    IncludeLaunchDescription,
    OpaqueFunction,
)
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

from moveit_configs_utils import MoveItConfigsBuilder
from moveit_configs_utils.launch_utils import DeclareBooleanLaunchArg


def _launch_setup(context, *args, **kwargs):
    use_mock = LaunchConfiguration("use_mock_hardware").perform(context)

    moveit_config = (
        MoveItConfigsBuilder("mockway_description", package_name="moveit_mockway_config")
        .robot_description(mappings={"use_mock_hardware": use_mock})
        .to_moveit_configs()
    )
    pkg_path = moveit_config.package_path
    actions = []

    actions.append(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(str(pkg_path / "launch/static_virtual_joint_tfs.launch.py")),
        )
    )

    actions.append(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(str(pkg_path / "launch/rsp.launch.py")),
            launch_arguments={"use_mock_hardware": use_mock}.items(),
        )
    )

    actions.append(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(str(pkg_path / "launch/move_group.launch.py")),
        )
    )

    actions.append(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(str(pkg_path / "launch/moveit_rviz.launch.py")),
            condition=IfCondition(LaunchConfiguration("use_rviz")),
        )
    )

    actions.append(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(str(pkg_path / "launch/warehouse_db.launch.py")),
            condition=IfCondition(LaunchConfiguration("db")),
        )
    )

    # Pass robot_description as parameter (not only via topic) for ros2_control on Jazzy
    actions.append(
        Node(
            package="controller_manager",
            executable="ros2_control_node",
            parameters=[
                str(pkg_path / "config/ros2_controllers.yaml"),
                moveit_config.robot_description,
            ],
            remappings=[
                ("/controller_manager/robot_description", "/robot_description"),
            ],
            output="screen",
        )
    )

    actions.append(
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(str(pkg_path / "launch/spawn_controllers.launch.py")),
        )
    )

    return actions


def generate_launch_description():
    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "use_mock_hardware",
                default_value="true",
                description="Demo 默认 mock 硬件；接真机时设为 false",
            ),
            DeclareBooleanLaunchArg(
                "db",
                default_value=False,
                description="By default, we do not start a database (it can be large)",
            ),
            DeclareBooleanLaunchArg(
                "debug",
                default_value=False,
                description="By default, we are not in debug mode",
            ),
            DeclareBooleanLaunchArg("use_rviz", default_value=True),
            OpaqueFunction(function=_launch_setup),
        ]
    )
