/**
 * lua_moveit_node.cpp
 *
 * LuaMoveItNode 类实现。
 * 将 MoveIt 和 MoveIt Servo 封装为全局 Lua API（驼峰命名，无 robot 表），支持：
 *   - 关节/笛卡尔手动点动 (Servo)
 *   - 点到点规划执行 (PTP: MoveJ / MovePose)
 *   - 直线运动 (MoveL / MoveLRel / MoveLRelTool)
 *
 * Lua 全局 API 速查：
 *   ServoMode(mode)                           切换 Servo 模式 "joint_jog"|"twist"
 *   ServoJoint(idx, vel)                      单关节点动 deg/s
 *   ServoJoints({v1..v6})                     六轴点动 deg/s
 *   ServoCart(vx,vy,vz,rx,ry,rz[,frame])      笛卡尔点动 mm/s, deg/s
 *   ServoStop()                               停止点动
 *   MoveNamed(name)                           PTP → SRDF 命名状态
 *   MoveJ({j1..j6})                           PTP → 关节角 deg
 *   MovePose(x,y,z,roll,pitch,yaw)            PTP → 末端位姿 mm, deg
 *   MoveL(x,y,z,roll,pitch,yaw[,step])        直线 → 绝对位姿 mm, deg
 *   MoveLRel(dx,dy,dz,drx,dry,drz[,step])     直线 → 相对基坐标系增量 mm, deg
 *   MoveLRelTool(dx,dy,dz,drx,dry,drz[,step]) 直线 → 相对工具坐标系增量 mm, deg
 *   SetVelScale(f)                            速度比例 [0.01, 1.0]
 *   SetAccScale(f)                            加速度比例 [0.01, 1.0]
 *   SetPlanTime(t)                            规划超时 s
 *   SetPlanner(id)                            切换规划器
 *   GetJoints()  → {j1..j6} deg              获取关节角
 *   GetPose()    → {x,y,z,roll,pitch,yaw}     获取末端位姿 mm, deg
 *   Sleep(ms)                                 暂停 ms 毫秒
 *   Log(msg) / LogWarn(msg) / LogError(msg)   ROS 日志
 *   Ok()                                      节点运行中返回 true
 *   DegRad(d) / RadDeg(r)                     角度转换
 */

#include "mockway_lua_moveit/lua_moveit_node.hpp"

#include <moveit/planning_scene_interface/planning_scene_interface.hpp>
#include <geometry_msgs/msg/pose.hpp>
#include <geometry_msgs/msg/transform_stamped.hpp>
#include <tf2_geometry_msgs/tf2_geometry_msgs.hpp>
#include <tf2_eigen/tf2_eigen.hpp>
#include <tf2/exceptions.h>
#include <Eigen/Geometry>

#include <chrono>
#include <filesystem>
#include <future>
#include <sstream>
#include <thread>

using namespace std::chrono_literals;

// ─────────────────────────── 常量 ────────────────────────────────────────────
namespace defaults {
  const std::string PLANNING_GROUP = "mockway_group";
  const std::string EE_FRAME       = "link6";
  const std::string BASE_FRAME     = "base_link";
  const std::string TWIST_TOPIC    = "/servo_node/delta_twist_cmds";
  const std::string JOINT_TOPIC    = "/servo_node/delta_joint_cmds";
  const std::vector<std::string> JOINT_NAMES = {
    "joint1","joint2","joint3","joint4","joint5","joint6"
  };
}

// ─────────────────────────── 构造 ────────────────────────────────────────────
LuaMoveItNode::LuaMoveItNode()
: Node("lua_moveit_node",
       rclcpp::NodeOptions().automatically_declare_parameters_from_overrides(true))
{
  planning_group_ = declare_or_get("planning_group", defaults::PLANNING_GROUP);
  ee_frame_       = declare_or_get("ee_frame",       defaults::EE_FRAME);
  base_frame_     = declare_or_get("base_frame",     defaults::BASE_FRAME);

  twist_pub_ = create_publisher<geometry_msgs::msg::TwistStamped>(
    defaults::TWIST_TOPIC, rclcpp::QoS(10));
  joint_pub_ = create_publisher<control_msgs::msg::JointJog>(
    defaults::JOINT_TOPIC, rclcpp::QoS(10));

  servo_mode_client_ = create_client<moveit_msgs::srv::ServoCommandType>(
    "/servo_node/switch_command_type");

  // ── 订阅关节状态 ──────────────────────────────────────────────────────────
  joint_state_sub_ = create_subscription<sensor_msgs::msg::JointState>(
    "/joint_states", rclcpp::SensorDataQoS(),
    [this](const sensor_msgs::msg::JointState::SharedPtr msg) {
      std::lock_guard<std::mutex> lk(joint_cache_mutex_);
      cached_joint_names_     = msg->name;
      cached_joint_positions_ = msg->position;
    });

  // ── TF2 缓冲区（用于末端位姿查询） ──────────────────────────────────────
  tf_buffer_   = std::make_shared<tf2_ros::Buffer>(get_clock());
  tf_listener_ = std::make_shared<tf2_ros::TransformListener>(*tf_buffer_, this);

  RCLCPP_INFO(get_logger(), "LuaMoveItNode 初始化完成，planning_group=%s",
              planning_group_.c_str());
}

// ─────────────────────────── 公开方法 ────────────────────────────────────────
bool LuaMoveItNode::init_move_group()
{
  std::lock_guard<std::mutex> lk(mg_mutex_);
  if (move_group_) return true;
  if (mg_failed_)  return false;

  try {
    move_group_ = std::make_shared<moveit::planning_interface::MoveGroupInterface>(
      shared_from_this(), planning_group_);
    move_group_->setMaxVelocityScalingFactor(0.3);
    move_group_->setMaxAccelerationScalingFactor(0.1);
    move_group_->setPlanningTime(5.0);
    RCLCPP_INFO(get_logger(), "MoveGroupInterface 就绪，规划参考系: %s",
                move_group_->getPlanningFrame().c_str());
    return true;
  } catch (const std::exception& e) {
    RCLCPP_ERROR(get_logger(),
      "MoveGroupInterface 初始化失败（move_group 未运行？）: %s", e.what());
    move_group_ = nullptr;
    mg_failed_  = true;
    return false;
  }
}

int LuaMoveItNode::run_script(const std::string& script_path)
{
  if (!std::filesystem::exists(script_path)) {
    RCLCPP_ERROR(get_logger(), "Lua 脚本不存在: %s", script_path.c_str());
    return -1;
  }

  std::lock_guard<std::mutex> lua_lk(lua_mutex_);
  setup_lua_api();

  std::filesystem::path p(script_path);
  std::string dir = p.parent_path().string();
  lua_.script("package.path = package.path .. ';' .. '" + dir + "/?.lua'");

  RCLCPP_INFO(get_logger(), "执行 Lua 脚本: %s", script_path.c_str());
  try {
    lua_.script_file(script_path);
  } catch (const sol::error& e) {
    RCLCPP_ERROR(get_logger(), "Lua 错误: %s", e.what());
    return -1;
  }
  return 0;
}

int LuaMoveItNode::run_string(const std::string& code)
{
  if (code.empty()) {
    RCLCPP_ERROR(get_logger(), "Lua 代码字符串为空");
    return -1;
  }

  std::lock_guard<std::mutex> lua_lk(lua_mutex_);
  setup_lua_api();

  RCLCPP_INFO(get_logger(), "执行 Lua 字符串（%zu 字节）", code.size());
  try {
    lua_.script(code);
  } catch (const sol::error& e) {
    RCLCPP_ERROR(get_logger(), "Lua 错误: %s", e.what());
    return -1;
  }
  return 0;
}

std::pair<bool, std::string> LuaMoveItNode::run_string_captured(const std::string& code)
{
  if (code.empty()) return {false, "Empty script"};

  std::lock_guard<std::mutex> lua_lk(lua_mutex_);
  setup_lua_api();

  // 重定向 print 到字符串缓冲区
  std::string captured;
  lua_["print"] = [&captured](sol::variadic_args va) {
    std::ostringstream oss;
    bool first = true;
    for (const auto& v : va) {
      if (!first) oss << "\t";
      first = false;
      switch (v.get_type()) {
        case sol::type::number:
          if (v.is<int64_t>()) oss << v.as<int64_t>();
          else                 oss << v.as<double>();
          break;
        case sol::type::boolean: oss << (v.as<bool>() ? "true" : "false"); break;
        case sol::type::string:  oss << v.as<std::string>();                break;
        case sol::type::nil:     oss << "nil";                              break;
        default: oss << "[" << sol::type_name(v.lua_state(), v.get_type()) << "]";
      }
    }
    oss << "\n";
    captured += oss.str();
  };
  RCLCPP_INFO(get_logger(), "HTTP 执行 Lua 字符串\n%s", code.c_str());
  try {
    lua_.script(code);
    return {true, captured};
  } catch (const sol::error& e) {
    RCLCPP_ERROR(get_logger(), "Lua 错误: %s", e.what());
    return {false, std::string(e.what())};
  }
}

std::vector<double> LuaMoveItNode::get_joint_positions_raw()
{
  std::lock_guard<std::mutex> lk(joint_cache_mutex_);
  if (cached_joint_positions_.empty()) return {};

  // 按 joint1..joint6 顺序返回
  std::vector<double> result(defaults::JOINT_NAMES.size(), 0.0);
  for (size_t i = 0; i < defaults::JOINT_NAMES.size(); ++i) {
    for (size_t j = 0; j < cached_joint_names_.size(); ++j) {
      if (cached_joint_names_[j] == defaults::JOINT_NAMES[i]) {
        result[i] = cached_joint_positions_[j];
        break;
      }
    }
  }
  return result;
}

std::vector<double> LuaMoveItNode::get_end_pose_rpy_raw()
{
  try {
    auto tf = tf_buffer_->lookupTransform(base_frame_, ee_frame_, tf2::TimePointZero);
    Eigen::Quaterniond q(
      tf.transform.rotation.w,
      tf.transform.rotation.x,
      tf.transform.rotation.y,
      tf.transform.rotation.z);
    auto euler = q.toRotationMatrix().eulerAngles(2, 1, 0); // ZYX -> yaw, pitch, roll
    return {
      tf.transform.translation.x * 1000.0,
      tf.transform.translation.y * 1000.0,
      tf.transform.translation.z * 1000.0,
      euler[2] * 180.0 / M_PI,
      euler[1] * 180.0 / M_PI,
      euler[0] * 180.0 / M_PI
    };
  } catch (const tf2::TransformException& e) {
    RCLCPP_WARN_THROTTLE(get_logger(), *get_clock(), 5000,
      "TF 查询失败 (%s -> %s): %s", base_frame_.c_str(), ee_frame_.c_str(), e.what());
    return {};
  }
}

// ─────────────────────────── 私有方法 ────────────────────────────────────────
std::string LuaMoveItNode::declare_or_get(const std::string& name,
                                           const std::string& default_val)
{
  if (!has_parameter(name)) declare_parameter(name, default_val);
  return get_parameter(name).as_string();
}

void LuaMoveItNode::setup_lua_api()
{
  lua_.open_libraries(
    sol::lib::base, sol::lib::string, sol::lib::table,
    sol::lib::math,  sol::lib::io,     sol::lib::os,
    sol::lib::coroutine, sol::lib::package);

  // ══════════════════════════════════════════════════════════════════════════
  // 一、MoveIt Servo — 点动
  // ══════════════════════════════════════════════════════════════════════════

  // ServoMode(mode)  "joint_jog" | "twist"，返回 bool
  lua_.set_function("ServoMode", [this](const std::string& mode) -> bool {
    return switch_servo_mode(mode);
  });

  // ServoJoint(idx, vel)  idx: 1~6 或关节名，vel: deg/s
  lua_.set_function("ServoJoint", [this](sol::object name_or_idx, double vel) {
    std::vector<double> v(6, 0.0);
    if (name_or_idx.is<int>()) {
      int idx = name_or_idx.as<int>();
      if (idx >= 1 && idx <= 6) v[idx - 1] = vel * (M_PI / 180.0);
    } else if (name_or_idx.is<std::string>()) {
      auto nm = name_or_idx.as<std::string>();
      for (int i = 0; i < 6; ++i)
        if (defaults::JOINT_NAMES[i] == nm) { v[i] = vel * (M_PI / 180.0); break; }
    }
    publish_joint_jog(v);
  });

  // ServoJoints({v1..v6})  deg/s
  lua_.set_function("ServoJoints", [this](sol::table vels) {
    std::vector<double> v(6, 0.0);
    for (int i = 1; i <= 6; ++i)
      if (vels[i].valid()) v[i - 1] = vels[i].get<double>() * (M_PI / 180.0);
    publish_joint_jog(v);
  });

  // ServoCart(vx,vy,vz,rx,ry,rz [,frame])  mm/s, deg/s
  lua_.set_function("ServoCart",
    [this](double vx, double vy, double vz,
           double rx, double ry, double rz,
           sol::optional<std::string> frame_opt)
    {
      publish_twist(vx/1000.0, vy/1000.0, vz/1000.0,
                    rx*(M_PI/180.0), ry*(M_PI/180.0), rz*(M_PI/180.0),
                    frame_opt.value_or(base_frame_));
    });

  // ServoStop()
  lua_.set_function("ServoStop", [this]() {
    publish_twist(0, 0, 0, 0, 0, 0, base_frame_);
    publish_joint_jog(std::vector<double>(6, 0.0));
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 二、MoveIt — 点到点规划 (PTP)
  // ══════════════════════════════════════════════════════════════════════════

  // MoveNamed(name)  返回 bool
  lua_.set_function("MoveNamed", [this](const std::string& name) -> bool {
    if (!init_move_group()) return false;
    std::lock_guard<std::mutex> lk(mg_mutex_);
    move_group_->setNamedTarget(name);
    auto ret = move_group_->move();
    bool ok = (ret == moveit::core::MoveItErrorCode::SUCCESS);
    RCLCPP_INFO(get_logger(), "MoveNamed('%s') -> %s", name.c_str(), ok ? "成功" : "失败");
    return ok;
  });

  // MoveJ({j1..j6})  deg，返回 bool
  lua_.set_function("MoveJ", [this](sol::table pos) -> bool {
    if (!init_move_group()) return false;
    std::vector<double> target(6, 0.0);
    for (int i = 1; i <= 6; ++i)
      if (pos[i].valid()) target[i - 1] = pos[i].get<double>() * (M_PI / 180.0);
    std::lock_guard<std::mutex> lk(mg_mutex_);
    move_group_->setJointValueTarget(target);
    auto ret = move_group_->move();
    bool ok = (ret == moveit::core::MoveItErrorCode::SUCCESS);
    RCLCPP_INFO(get_logger(), "MoveJ -> %s", ok ? "成功" : "失败");
    return ok;
  });

  // MovePose(x,y,z,roll,pitch,yaw)  mm, deg，返回 bool
  lua_.set_function("MovePose",
    [this](double x, double y, double z,
           double roll, double pitch, double yaw) -> bool
    {
      if (!init_move_group()) return false;
      Eigen::Quaterniond q =
        Eigen::AngleAxisd(yaw   * (M_PI/180.0), Eigen::Vector3d::UnitZ()) *
        Eigen::AngleAxisd(pitch * (M_PI/180.0), Eigen::Vector3d::UnitY()) *
        Eigen::AngleAxisd(roll  * (M_PI/180.0), Eigen::Vector3d::UnitX());
      geometry_msgs::msg::Pose p;
      p.position.x = x/1000.0; p.position.y = y/1000.0; p.position.z = z/1000.0;
      p.orientation = tf2::toMsg(q);
      std::lock_guard<std::mutex> lk(mg_mutex_);
      move_group_->setPoseTarget(p);
      auto ret = move_group_->move();
      bool ok = (ret == moveit::core::MoveItErrorCode::SUCCESS);
      RCLCPP_INFO(get_logger(), "MovePose -> %s", ok ? "成功" : "失败");
      return ok;
    });

  // ══════════════════════════════════════════════════════════════════════════
  // 三、MoveIt — 直线运动 (Linear)
  // ══════════════════════════════════════════════════════════════════════════

  // MoveL(x,y,z,roll,pitch,yaw [,step])  mm, deg，step mm 默认 10，返回 bool
  lua_.set_function("MoveL",
    [this](double x, double y, double z,
           double roll, double pitch, double yaw,
           sol::optional<double> step_opt) -> bool
    {
      if (!init_move_group()) return false;
      Eigen::Quaterniond q =
        Eigen::AngleAxisd(yaw   * (M_PI/180.0), Eigen::Vector3d::UnitZ()) *
        Eigen::AngleAxisd(pitch * (M_PI/180.0), Eigen::Vector3d::UnitY()) *
        Eigen::AngleAxisd(roll  * (M_PI/180.0), Eigen::Vector3d::UnitX());
      geometry_msgs::msg::Pose target;
      target.position.x = x/1000.0; target.position.y = y/1000.0; target.position.z = z/1000.0;
      target.orientation = tf2::toMsg(q);
      double step = step_opt.value_or(10.0) / 1000.0;
      std::vector<geometry_msgs::msg::Pose> waypoints = {target};
      moveit_msgs::msg::RobotTrajectory trajectory;
      std::lock_guard<std::mutex> lk(mg_mutex_);
      double fraction = move_group_->computeCartesianPath(waypoints, step, trajectory);
      RCLCPP_INFO(get_logger(), "MoveL 规划完成率: %.1f%%", fraction * 100.0);
      if (fraction < 0.9) {
        RCLCPP_WARN(get_logger(), "MoveL 规划完成率过低，取消执行");
        return false;
      }
      moveit::planning_interface::MoveGroupInterface::Plan plan;
      plan.trajectory = trajectory;
      auto ret = move_group_->execute(plan);
      bool ok = (ret == moveit::core::MoveItErrorCode::SUCCESS);
      RCLCPP_INFO(get_logger(), "MoveL -> %s", ok ? "成功" : "失败");
      return ok;
    });

  // MoveLRel(dx,dy,dz,drx,dry,drz [,step])
  //   增量在基坐标系下表达，mm, deg，step mm 默认 10，返回 bool
  lua_.set_function("MoveLRel",
    [this](double dx, double dy, double dz,
           double drx, double dry, double drz,
           sol::optional<double> step_opt) -> bool
    {
      if (!init_move_group()) return false;
      double step = step_opt.value_or(10.0) / 1000.0;
      geometry_msgs::msg::PoseStamped cur;
      {
        std::lock_guard<std::mutex> lk(mg_mutex_);
        cur = move_group_->getCurrentPose();
      }
      geometry_msgs::msg::Pose target = cur.pose;
      target.position.x += dx/1000.0;
      target.position.y += dy/1000.0;
      target.position.z += dz/1000.0;
      Eigen::Quaterniond q_cur;
      tf2::fromMsg(cur.pose.orientation, q_cur);
      Eigen::Quaterniond q_delta =
        Eigen::AngleAxisd(drz * (M_PI/180.0), Eigen::Vector3d::UnitZ()) *
        Eigen::AngleAxisd(dry * (M_PI/180.0), Eigen::Vector3d::UnitY()) *
        Eigen::AngleAxisd(drx * (M_PI/180.0), Eigen::Vector3d::UnitX());
      target.orientation = tf2::toMsg(q_delta * q_cur);
      std::vector<geometry_msgs::msg::Pose> waypoints = {target};
      moveit_msgs::msg::RobotTrajectory trajectory;
      std::lock_guard<std::mutex> lk(mg_mutex_);
      double fraction = move_group_->computeCartesianPath(waypoints, step, trajectory);
      if (fraction < 0.9) {
        RCLCPP_WARN(get_logger(), "MoveLRel 规划完成率过低: %.1f%%", fraction * 100.0);
        return false;
      }
      moveit::planning_interface::MoveGroupInterface::Plan plan;
      plan.trajectory = trajectory;
      auto ret = move_group_->execute(plan);
      bool ok = (ret == moveit::core::MoveItErrorCode::SUCCESS);
      RCLCPP_INFO(get_logger(), "MoveLRel -> %s", ok ? "成功" : "失败");
      return ok;
    });

  // MoveLRelTool(dx,dy,dz,drx,dry,drz [,step])
  //   增量在工具坐标系下表达：平移旋转至基坐标系后叠加，旋转 q_new = q_cur * q_delta
  //   mm, deg，step mm 默认 10，返回 bool
  lua_.set_function("MoveLRelTool",
    [this](double dx, double dy, double dz,
           double drx, double dry, double drz,
           sol::optional<double> step_opt) -> bool
    {
      if (!init_move_group()) return false;
      double step = step_opt.value_or(10.0) / 1000.0;
      geometry_msgs::msg::PoseStamped cur;
      {
        std::lock_guard<std::mutex> lk(mg_mutex_);
        cur = move_group_->getCurrentPose();
      }
      Eigen::Quaterniond q_cur;
      tf2::fromMsg(cur.pose.orientation, q_cur);
      Eigen::Vector3d delta_base = q_cur * Eigen::Vector3d(dx/1000.0, dy/1000.0, dz/1000.0);
      geometry_msgs::msg::Pose target = cur.pose;
      target.position.x += delta_base.x();
      target.position.y += delta_base.y();
      target.position.z += delta_base.z();
      Eigen::Quaterniond q_delta =
        Eigen::AngleAxisd(drz * (M_PI/180.0), Eigen::Vector3d::UnitZ()) *
        Eigen::AngleAxisd(dry * (M_PI/180.0), Eigen::Vector3d::UnitY()) *
        Eigen::AngleAxisd(drx * (M_PI/180.0), Eigen::Vector3d::UnitX());
      target.orientation = tf2::toMsg(q_cur * q_delta);
      std::vector<geometry_msgs::msg::Pose> waypoints = {target};
      moveit_msgs::msg::RobotTrajectory trajectory;
      std::lock_guard<std::mutex> lk(mg_mutex_);
      double fraction = move_group_->computeCartesianPath(waypoints, step, trajectory);
      if (fraction < 0.9) {
        RCLCPP_WARN(get_logger(), "MoveLRelTool 规划完成率过低: %.1f%%", fraction * 100.0);
        return false;
      }
      moveit::planning_interface::MoveGroupInterface::Plan plan;
      plan.trajectory = trajectory;
      auto ret = move_group_->execute(plan);
      bool ok = (ret == moveit::core::MoveItErrorCode::SUCCESS);
      RCLCPP_INFO(get_logger(), "MoveLRelTool -> %s", ok ? "成功" : "失败");
      return ok;
    });

  // ══════════════════════════════════════════════════════════════════════════
  // 四、规划参数设置
  // ══════════════════════════════════════════════════════════════════════════

  // SetVelScale(f)  [0.01, 1.0]
  lua_.set_function("SetVelScale", [this](double f) {
    const double clamped = std::clamp(f, 0.01, 1.0);
    global_ratio_.store(clamped * 100.0);
    if (!init_move_group()) return;
    std::lock_guard<std::mutex> lk(mg_mutex_);
    move_group_->setMaxVelocityScalingFactor(clamped);
  });

  // SetAccScale(f)  [0.01, 1.0]
  lua_.set_function("SetAccScale", [this](double f) {
    if (!init_move_group()) return;
    std::lock_guard<std::mutex> lk(mg_mutex_);
    move_group_->setMaxAccelerationScalingFactor(std::clamp(f, 0.01, 1.0));
  });

  // SetPlanTime(t)  seconds
  lua_.set_function("SetPlanTime", [this](double t) {
    if (!init_move_group()) return;
    std::lock_guard<std::mutex> lk(mg_mutex_);
    move_group_->setPlanningTime(t);
  });

  // SetPlanner(id)
  lua_.set_function("SetPlanner", [this](const std::string& planner_id) {
    if (!init_move_group()) return;
    std::lock_guard<std::mutex> lk(mg_mutex_);
    move_group_->setPlannerId(planner_id);
    RCLCPP_INFO(get_logger(), "规划器切换为: %s", planner_id.c_str());
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 五、状态查询
  // ══════════════════════════════════════════════════════════════════════════

  // GetJoints() → {j1..j6} deg
  lua_.set_function("GetJoints", [this]() -> sol::table {
    if (!init_move_group()) return lua_.create_table();
    std::lock_guard<std::mutex> lk(mg_mutex_);
    auto vals = move_group_->getCurrentJointValues();
    sol::table t = lua_.create_table();
    for (size_t i = 0; i < vals.size(); ++i) t[i + 1] = vals[i] * (180.0 / M_PI);
    return t;
  });

  // GetPose() → {x, y, z, roll, pitch, yaw}  mm, deg
  lua_.set_function("GetPose", [this]() -> sol::table {
    if (!init_move_group()) return lua_.create_table();
    std::lock_guard<std::mutex> lk(mg_mutex_);
    auto ps = move_group_->getCurrentPose();
    Eigen::Quaterniond q;
    tf2::fromMsg(ps.pose.orientation, q);
    auto euler = q.toRotationMatrix().eulerAngles(2, 1, 0); // ZYX → yaw, pitch, roll
    sol::table t = lua_.create_table();
    t[1] = ps.pose.position.x * 1000.0;
    t[2] = ps.pose.position.y * 1000.0;
    t[3] = ps.pose.position.z * 1000.0;
    t[4] = euler[2] * (180.0 / M_PI);  // roll
    t[5] = euler[1] * (180.0 / M_PI);  // pitch
    t[6] = euler[0] * (180.0 / M_PI);  // yaw
    return t;
  });

  // ══════════════════════════════════════════════════════════════════════════
  // 六、实用工具
  // ══════════════════════════════════════════════════════════════════════════

  // Sleep(ms)
  lua_.set_function("Sleep", [](double ms) {
    rclcpp::sleep_for(std::chrono::duration_cast<std::chrono::nanoseconds>(
      std::chrono::duration<double>(ms / 1000.0)));
  });

  lua_.set_function("Log",      [this](const std::string& m) {
    RCLCPP_INFO (get_logger(), "[Lua] %s", m.c_str()); });
  lua_.set_function("LogWarn",  [this](const std::string& m) {
    RCLCPP_WARN (get_logger(), "[Lua] %s", m.c_str()); });
  lua_.set_function("LogError", [this](const std::string& m) {
    RCLCPP_ERROR(get_logger(), "[Lua] %s", m.c_str()); });

  // Ok()
  lua_.set_function("Ok", []() -> bool { return rclcpp::ok(); });

  lua_.script(R"(
    function DegRad(d) return d * math.pi / 180.0 end
    function RadDeg(r) return r * 180.0 / math.pi end
  )");
}

void LuaMoveItNode::publish_joint_jog(const std::vector<double>& vels)
{
  auto msg = std::make_unique<control_msgs::msg::JointJog>();
  msg->header.stamp    = now();
  msg->header.frame_id = base_frame_;
  msg->joint_names     = defaults::JOINT_NAMES;
  msg->velocities      = vels;
  msg->duration        = 0.5;
  joint_pub_->publish(std::move(msg));
}

void LuaMoveItNode::publish_twist(double vx, double vy, double vz,
                                   double rx, double ry, double rz,
                                   const std::string& frame_id)
{
  auto msg = std::make_unique<geometry_msgs::msg::TwistStamped>();
  msg->header.stamp    = now();
  msg->header.frame_id = frame_id;
  msg->twist.linear.x  = vx; msg->twist.linear.y  = vy; msg->twist.linear.z  = vz;
  msg->twist.angular.x = rx; msg->twist.angular.y = ry; msg->twist.angular.z = rz;
  twist_pub_->publish(std::move(msg));
}

bool LuaMoveItNode::switch_servo_mode(const std::string& mode)
{
  if (!servo_mode_client_->wait_for_service(2s)) {
    RCLCPP_WARN(get_logger(), "Servo 模式切换服务不可用");
    return false;
  }
  auto req = std::make_shared<moveit_msgs::srv::ServoCommandType::Request>();
  if      (mode == "joint_jog") req->command_type = moveit_msgs::srv::ServoCommandType::Request::JOINT_JOG;
  else if (mode == "twist")     req->command_type = moveit_msgs::srv::ServoCommandType::Request::TWIST;
  else {
    RCLCPP_WARN(get_logger(), "未知 Servo 模式: %s（应为 joint_jog 或 twist）", mode.c_str());
    return false;
  }
  auto future = servo_mode_client_->async_send_request(req);
  if (future.wait_for(3s) == std::future_status::ready) {
    bool ok = future.get()->success;
    RCLCPP_INFO(get_logger(), "切换 Servo 模式 '%s' -> %s",
                mode.c_str(), ok ? "成功" : "失败");
    return ok;
  }
  RCLCPP_WARN(get_logger(), "切换 Servo 模式超时");
  return false;
}
