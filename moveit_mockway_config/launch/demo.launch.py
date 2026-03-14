from moveit_configs_utils import MoveItConfigsBuilder
from moveit_configs_utils.launches import generate_demo_launch
from launch.actions import DeclareLaunchArgument


def generate_launch_description():
    moveit_config = MoveItConfigsBuilder("mockway_description", package_name="moveit_mockway_config").to_moveit_configs()
    ld = generate_demo_launch(moveit_config)
    ld.add_action(
        DeclareLaunchArgument(
            "use_mock_hardware",
            default_value="false",
            description="使用 mock_components/GenericSystem 替代真实硬件（dmmotor_hardware_interface/DMMototHardwareInterface）",
        )
    )
    return ld
