from moveit_configs_utils import MoveItConfigsBuilder
from moveit_configs_utils.launches import generate_move_group_launch
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch.substitutions import LaunchConfiguration


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
    return generate_move_group_launch(moveit_config).entities


def generate_launch_description():
    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "use_mock_hardware",
                default_value="false",
                description="使用 mock_components/GenericSystem 替代真实硬件（dmmotor_hardware_interface/DMMototHardwareInterface）",
            ),
            OpaqueFunction(function=launch_setup),
        ]
    )
