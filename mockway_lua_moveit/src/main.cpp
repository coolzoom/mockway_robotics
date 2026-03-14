/**
 * main.cpp — lua_moveit_node 入口
 *
 * 节点参数：
 *   planning_group (string, default "mockway_group")
 *   ee_frame       (string, default "link6")
 *   base_frame     (string, default "base_link")
 *
 * 执行源优先级：
 *   1. 命令行位置参数（首个非 --ros-args 参数，视为脚本路径）
 *   2. ROS 参数 script_path（Lua 脚本文件路径）
 *   3. ROS 参数 script_code（Lua 代码字符串）
 */

#include "mockway_lua_moveit/lua_moveit_node.hpp"

#include <rclcpp/executors/single_threaded_executor.hpp>
#include <thread>

int main(int argc, char** argv)
{
  rclcpp::init(argc, argv);

  auto node = std::make_shared<LuaMoveItNode>();

  // 后台 executor：MoveGroupInterface / Service 调用需要 spin
  rclcpp::executors::SingleThreadedExecutor executor;
  executor.add_node(node);
  std::thread spin_thread([&executor]() { executor.spin(); });

  // 获取执行源
  std::string script_path;
  if (argc >= 2 && argv[1][0] != '-') {
    script_path = argv[1];
  } else {
    if (!node->has_parameter("script_path"))
      node->declare_parameter("script_path", std::string(""));
    script_path = node->get_parameter("script_path").as_string();
  }

  if (!node->has_parameter("script_code"))
    node->declare_parameter("script_code", std::string(""));
  std::string script_code = node->get_parameter("script_code").as_string();

  int ret = 0;
  if (!script_path.empty()) {
    ret = node->run_script(script_path);
  } else if (!script_code.empty()) {
    ret = node->run_string(script_code);
  } else {
    RCLCPP_ERROR(node->get_logger(),
      "请通过命令行参数、ROS 参数 'script_path' 或 'script_code' 指定要执行的 Lua 内容");
    ret = -1;
  }

  executor.cancel();
  spin_thread.join();
  rclcpp::shutdown();
  return ret;
}
