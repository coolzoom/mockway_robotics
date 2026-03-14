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
#include "mockway_lua_moveit/http_server.hpp"

#include <rclcpp/executors/single_threaded_executor.hpp>
#include <chrono>
#include <thread>

int main(int argc, char** argv)
{
  rclcpp::init(argc, argv);

  auto node = std::make_shared<LuaMoveItNode>();

  // 后台 executor：MoveGroupInterface / Service 调用需要 spin
  rclcpp::executors::SingleThreadedExecutor executor;
  executor.add_node(node);
  std::thread spin_thread([&executor]() { executor.spin(); });

  // HTTP 服务器（端口由 ROS 参数 http_port 控制，默认 8080）
  if (!node->has_parameter("http_port"))
    node->declare_parameter("http_port", 8080);
  const int http_port = node->get_parameter("http_port").as_int();

  HttpServer http_server(node, http_port);
  http_server.start();

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
    // 未指定脚本 — HTTP 服务器模式：保持运行直到 Ctrl+C
    RCLCPP_INFO(node->get_logger(),
      "HTTP 服务器模式（端口 %d）：未指定脚本，等待前端请求...", http_port);
    while (rclcpp::ok()) {
      std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
  }

  http_server.stop();
  executor.cancel();
  spin_thread.join();
  rclcpp::shutdown();
  return ret;
}
