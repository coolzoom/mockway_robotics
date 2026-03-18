import os
import launch
import launch_ros
from ament_index_python.packages import get_package_share_directory
from launch.conditions import IfCondition, UnlessCondition
from launch.substitutions import LaunchConfiguration
from launch_param_builder import ParameterBuilder
from moveit_configs_utils import MoveItConfigsBuilder
from launch_ros.actions import Node
from launch.actions import DeclareLaunchArgument


def generate_launch_description():
    # --- Launch Arguments ---
    use_mock_hardware_arg = DeclareLaunchArgument(
        "use_mock_hardware",
        default_value="false",
        description="使用 mock_components/GenericSystem 替代真实硬件（dmmotor_hardware_interface/DMMototHardwareInterface）",
    )
    use_lua_arg = DeclareLaunchArgument(
        "with_lua", default_value="true", description="是否启动 lua_moveit_node（HTTP Lua 脚本执行节点）"
    )
    use_rviz_arg = DeclareLaunchArgument(
        "with_rviz", default_value="false", description="是否启动 RViz2 可视化界面"
    )
    launch_as_standalone_node_arg = DeclareLaunchArgument(
        "launch_as_standalone_node", default_value="false",
        description="以独立节点方式启动 Servo（而非 component，适用于跨机器部署）",
    )

    # --- MoveIt Config ---
    moveit_config = (
        MoveItConfigsBuilder("mockway_description", package_name="moveit_mockway_config")
        .robot_description(mappings={"use_mock_hardware": LaunchConfiguration("use_mock_hardware")})
        .to_moveit_configs()
    )

    # --- Servo Parameters (shared between standalone node and component) ---
    servo_node_params = [
        {"moveit_servo": ParameterBuilder("mockway_moveit_servo").yaml("config/servo_config.yaml").to_dict()},
        {"update_period": 0.01},
        {"planning_group_name": "mockway_group"},
        moveit_config.robot_description,
        moveit_config.robot_description_semantic,
        moveit_config.robot_description_kinematics,
        moveit_config.joint_limits,
    ]

    # --- Nodes ---
    move_group_node = Node(
        package="moveit_ros_move_group",
        executable="move_group",
        output="screen",
        parameters=[moveit_config.to_dict()],
        arguments=["--ros-args", "--log-level", "info"],
    )

    lua_moveit_node = Node(
        package="mockway_lua_moveit",
        executable="lua_moveit_node",
        name="lua_moveit_node",
        output="screen",
        parameters=[
            moveit_config.robot_description,
            moveit_config.robot_description_semantic,
            moveit_config.robot_description_kinematics,
            moveit_config.joint_limits,
            {
                "script_path":    "",
                "planning_group": "mockway_group",
                "ee_frame":       "link6",
                "base_frame":     "base_link",
            },
        ],
        condition=IfCondition(LaunchConfiguration("with_lua")),
    )

    rviz_node = Node(
        package="rviz2",
        executable="rviz2",
        name="rviz2",
        output="log",
        arguments=["-d", os.path.join(get_package_share_directory("mockway_moveit_servo"), "config", "moveit_servo.rviz")],
        parameters=[
            moveit_config.robot_description,
            moveit_config.robot_description_semantic,
        ],
        condition=IfCondition(LaunchConfiguration("with_rviz")),
    )

    ros2_control_node = Node(
        package="controller_manager",
        executable="ros2_control_node",
        parameters=[os.path.join(get_package_share_directory("moveit_mockway_config"), "config", "ros2_controllers.yaml")],
        remappings=[("/controller_manager/robot_description", "/robot_description")],
        output="screen",
    )

    joint_state_broadcaster_spawner = Node(
        package="controller_manager",
        executable="spawner",
        arguments=[
            "joint_state_broadcaster",
            "--controller-manager-timeout", "300",
            "--controller-manager", "/controller_manager",
        ],
    )

    mockway_group_controller_spawner = Node(
        package="controller_manager",
        executable="spawner",
        arguments=["mockway_group_controller", "-c", "/controller_manager"],
    )

    # Servo as component container (better latency via intraprocess communication)
    container = launch_ros.actions.ComposableNodeContainer(
        name="moveit_servo_demo_container",
        namespace="/",
        package="rclcpp_components",
        executable="component_container_mt",
        composable_node_descriptions=[
            launch_ros.descriptions.ComposableNode(
                package="moveit_servo",
                plugin="moveit_servo::ServoNode",
                name="servo_node",
                parameters=servo_node_params,
                condition=UnlessCondition(LaunchConfiguration("launch_as_standalone_node")),
            ),
            launch_ros.descriptions.ComposableNode(
                package="robot_state_publisher",
                plugin="robot_state_publisher::RobotStatePublisher",
                name="robot_state_publisher",
                parameters=[moveit_config.robot_description],
            ),
            launch_ros.descriptions.ComposableNode(
                package="tf2_ros",
                plugin="tf2_ros::StaticTransformBroadcasterNode",
                name="static_tf2_broadcaster",
                parameters=[{"child_frame_id": "/base_link", "frame_id": "/world"}],
            ),
        ],
        output="screen",
    )

    # Servo as standalone node (for cross-machine deployment)
    servo_node = Node(
        package="moveit_servo",
        executable="servo_node",
        name="servo_node",
        parameters=servo_node_params,
        output="screen",
        condition=IfCondition(LaunchConfiguration("launch_as_standalone_node")),
    )

    return launch.LaunchDescription(
        [
            use_mock_hardware_arg,
            use_lua_arg,
            use_rviz_arg,
            launch_as_standalone_node_arg,
            move_group_node,
            lua_moveit_node,
            rviz_node,
            ros2_control_node,
            joint_state_broadcaster_spawner,
            mockway_group_controller_spawner,
            servo_node,
            container,
        ]
    )
