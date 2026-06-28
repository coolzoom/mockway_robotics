from moveit_configs_utils import MoveItConfigsBuilder
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def launch_setup(context, *args, **kwargs):
    use_mock_hardware = LaunchConfiguration("use_mock_hardware").perform(context)

    moveit_config = (
        MoveItConfigsBuilder("mockway_description", package_name="moveit_mockway_config")
        .robot_description(
            file_path="config/mockway_description.urdf.xacro",
            mappings={"use_mock_hardware": use_mock_hardware},
        )
        .to_moveit_configs()
    )

    rsp_node = Node(
        package="robot_state_publisher",
        executable="robot_state_publisher",
        respawn=True,
        output="screen",
        parameters=[
            moveit_config.robot_description,
            {"publish_frequency": LaunchConfiguration("publish_frequency")},
        ],
    )
    return [rsp_node]


def generate_launch_description():
    return LaunchDescription(
        [
            DeclareLaunchArgument("publish_frequency", default_value="15.0"),
            DeclareLaunchArgument(
                "use_mock_hardware",
                default_value="true",
                description="使用 mock_components/GenericSystem 替代真实硬件（dmmotor_hardware_interface/DMMototHardwareInterface）",
            ),
            OpaqueFunction(function=launch_setup),
        ]
    )
