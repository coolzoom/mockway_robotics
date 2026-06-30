from moveit_configs_utils import MoveItConfigsBuilder
from moveit_configs_utils.launches import generate_move_group_launch
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch.substitutions import LaunchConfiguration


def launch_setup(context, *args, **kwargs):
    use_mock_hardware = LaunchConfiguration("use_mock_hardware").perform(context)
    can_interface = LaunchConfiguration("can_interface").perform(context)
    collision_mode = LaunchConfiguration("collision_mode").perform(context)

    moveit_config = (
        MoveItConfigsBuilder("mockway_description", package_name="moveit_mockway_config")
        .robot_description(
            file_path="config/mockway_description.urdf.xacro",
            mappings={
                "use_mock_hardware": use_mock_hardware,
                "can_interface": can_interface,
                "collision_mode": collision_mode,
            },
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
            DeclareLaunchArgument(
                "can_interface",
                default_value="/dev/ttyACM0",
                description="USB-CAN 串口设备：WSL/Linux 默认 /dev/ttyACM0；macOS 用 /dev/cu.usbmodem*",
            ),
            DeclareLaunchArgument(
                "collision_mode",
                default_value="mesh",
                description="碰撞几何: mesh(默认, Linux/WSL) | primitive(macOS 包围盒, 规避 FCL 崩溃)",
            ),
            OpaqueFunction(function=launch_setup),
        ]
    )
