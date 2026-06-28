from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    # 同一 spawner 按顺序加载，避免两个 spawner 并行抢 controller_manager 锁
    return LaunchDescription(
        [
            Node(
                package="controller_manager",
                executable="spawner",
                arguments=[
                    "joint_state_broadcaster",
                    "mockway_group_controller",
                    "--controller-manager-timeout",
                    "120",
                ],
                output="screen",
            ),
        ]
    )
