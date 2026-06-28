from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    spawner_args = ["--controller-manager-timeout", "120"]

    return LaunchDescription(
        [
            Node(
                package="controller_manager",
                executable="spawner",
                arguments=["joint_state_broadcaster", *spawner_args],
                output="screen",
            ),
            Node(
                package="controller_manager",
                executable="spawner",
                arguments=["mockway_group_controller", *spawner_args],
                output="screen",
            ),
        ]
    )
