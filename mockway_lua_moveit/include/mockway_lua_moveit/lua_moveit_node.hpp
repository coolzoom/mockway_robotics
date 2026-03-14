#pragma once

#define SOL_ALL_SAFETIES_ON 1
#include <sol/sol.hpp>

#include <rclcpp/rclcpp.hpp>
#include <moveit/move_group_interface/move_group_interface.hpp>
#include <moveit_msgs/srv/servo_command_type.hpp>
#include <geometry_msgs/msg/twist_stamped.hpp>
#include <control_msgs/msg/joint_jog.hpp>

#include <mutex>
#include <string>
#include <vector>

class LuaMoveItNode : public rclcpp::Node
{
public:
  explicit LuaMoveItNode();

  // 初始化 MoveGroupInterface（需要 executor 已在运行）
  // 返回 true 表示就绪，false 表示初始化失败
  bool init_move_group();

  // 运行 Lua 脚本文件，返回 0 成功，-1 失败
  int run_script(const std::string& script_path);

  // 运行 Lua 代码字符串，返回 0 成功，-1 失败
  int run_string(const std::string& code);

private:
  std::string planning_group_, ee_frame_, base_frame_;

  rclcpp::Publisher<geometry_msgs::msg::TwistStamped>::SharedPtr twist_pub_;
  rclcpp::Publisher<control_msgs::msg::JointJog>::SharedPtr      joint_pub_;
  rclcpp::Client<moveit_msgs::srv::ServoCommandType>::SharedPtr  servo_mode_client_;

  std::shared_ptr<moveit::planning_interface::MoveGroupInterface> move_group_;
  std::mutex mg_mutex_;
  bool mg_failed_ = false;

  sol::state lua_;

  std::string declare_or_get(const std::string& name, const std::string& default_val);
  void setup_lua_api();
  void publish_joint_jog(const std::vector<double>& vels);
  void publish_twist(double vx, double vy, double vz,
                     double rx, double ry, double rz,
                     const std::string& frame_id);
  bool switch_servo_mode(const std::string& mode);
};
