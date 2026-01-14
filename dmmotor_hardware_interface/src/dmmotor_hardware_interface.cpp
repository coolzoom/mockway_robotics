// Copyright (c) 2025, Mockway Robotics
// Licensed under the MIT License

#include "dmmotor_hardware_interface/dmmotor_hardware_interface.hpp"

#include <chrono>
#include <cmath>
#include <limits>
#include <memory>
#include <vector>
#include <string>

// For SocketCAN (Linux)
#include <linux/can.h>
#include <linux/can/raw.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <unistd.h>
#include <fcntl.h>
#include <cstring>

#include "hardware_interface/types/hardware_interface_type_values.hpp"
#include "rclcpp/rclcpp.hpp"

namespace dmmotor_hardware_interface
{

//==============================================================================
// CANInterface Implementation
//==============================================================================

CANInterface::CANInterface(const std::string& port, int baudrate)
  : port_(port), baudrate_(baudrate), can_fd_(-1), running_(false)
{
}

CANInterface::~CANInterface()
{
  close();
}

bool CANInterface::open()
{
  // Create socket
  can_fd_ = socket(PF_CAN, SOCK_RAW, CAN_RAW);
  if (can_fd_ < 0) {
    RCLCPP_ERROR(rclcpp::get_logger("CANInterface"), "Failed to create CAN socket");
    return false;
  }

  // Set non-blocking mode
  int flags = fcntl(can_fd_, F_GETFL, 0);
  fcntl(can_fd_, F_SETFL, flags | O_NONBLOCK);

  // Bind to CAN interface
  struct ifreq ifr;
  std::strncpy(ifr.ifr_name, port_.c_str(), IFNAMSIZ - 1);
  ifr.ifr_name[IFNAMSIZ - 1] = '\0';

  if (ioctl(can_fd_, SIOCGIFINDEX, &ifr) < 0) {
    RCLCPP_ERROR(rclcpp::get_logger("CANInterface"),
                 "Failed to get interface %s index", port_.c_str());
    ::close(can_fd_);
    can_fd_ = -1;
    return false;
  }

  struct sockaddr_can addr;
  std::memset(&addr, 0, sizeof(addr));
  addr.can_family = AF_CAN;
  addr.can_ifindex = ifr.ifr_ifindex;

  if (bind(can_fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
    RCLCPP_ERROR(rclcpp::get_logger("CANInterface"),
                 "Failed to bind CAN socket to %s", port_.c_str());
    ::close(can_fd_);
    can_fd_ = -1;
    return false;
  }

  // Start receive thread
  running_ = true;
  rx_thread_ = std::thread(&CANInterface::receiveLoop, this);

  RCLCPP_INFO(rclcpp::get_logger("CANInterface"),
              "CAN interface opened: %s", port_.c_str());
  return true;
}

void CANInterface::close()
{
  running_ = false;
  if (rx_thread_.joinable()) {
    rx_thread_.join();
  }
  if (can_fd_ >= 0) {
    ::close(can_fd_);
    can_fd_ = -1;
  }
  RCLCPP_INFO(rclcpp::get_logger("CANInterface"), "CAN interface closed");
}

bool CANInterface::sendFrame(const CANFrame& frame)
{
  if (can_fd_ < 0) {
    return false;
  }

  struct can_frame can_frame;
  std::memset(&can_frame, 0, sizeof(can_frame));
  can_frame.can_id = frame.id;
  can_frame.can_dlc = frame.len;
  std::memcpy(can_frame.data, frame.data, frame.len);

  std::lock_guard<std::mutex> lock(mutex_);
  ssize_t nbytes = write(can_fd_, &can_frame, sizeof(can_frame));

  return nbytes == sizeof(can_frame);
}

void CANInterface::setReceiveCallback(std::function<void(const CANFrame&)> callback)
{
  std::lock_guard<std::mutex> lock(mutex_);
  rx_callback_ = callback;
}

void CANInterface::receiveLoop()
{
  struct can_frame can_frame;

  while (running_) {
    if (can_fd_ < 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      continue;
    }

    ssize_t nbytes = read(can_fd_, &can_frame, sizeof(can_frame));

    if (nbytes > 0 && nbytes == sizeof(can_frame)) {
      CANFrame frame;
      frame.id = can_frame.can_id;
      frame.len = can_frame.can_dlc;
      std::memcpy(frame.data, can_frame.data, can_frame.can_dlc);

      std::lock_guard<std::mutex> lock(mutex_);
      if (rx_callback_) {
        rx_callback_(frame);
      }
    } else {
      std::this_thread::sleep_for(std::chrono::microseconds(100));
    }
  }
}

//==============================================================================
// DMMotor Implementation
//==============================================================================

DMMotor::DMMotor(std::shared_ptr<CANInterface> can, const MotorConfig& config)
  : can_(can), config_(config)
{
  // Register CAN receive callback
  can_->setReceiveCallback([this](const CANFrame& frame) {
    this->onCANFrame(frame);
  });
}

DMMotor::~DMMotor()
{
}

bool DMMotor::enable()
{
  CANFrame frame;
  frame.id = config_.motor_id;
  frame.len = 8;
  std::memcpy(frame.data, CMD_ENABLE, 8);

  bool result = can_->sendFrame(frame);
  if (result) {
    RCLCPP_INFO(rclcpp::get_logger("DMMotor"),
                "Motor %d enable command sent", config_.motor_id);
  }
  return result;
}

bool DMMotor::disable()
{
  CANFrame frame;
  frame.id = config_.motor_id;
  frame.len = 8;
  std::memcpy(frame.data, CMD_DISABLE, 8);

  bool result = can_->sendFrame(frame);
  if (result) {
    RCLCPP_INFO(rclcpp::get_logger("DMMotor"),
                "Motor %d disable command sent", config_.motor_id);
  }
  return result;
}

bool DMMotor::clearError()
{
  CANFrame frame;
  frame.id = config_.motor_id;
  frame.len = 8;
  std::memcpy(frame.data, CMD_CLEAR_ERROR, 8);

  return can_->sendFrame(frame);
}

bool DMMotor::controlMIT(double p_des, double v_des, double kp, double kd, double t_ff)
{
  // Clamp values
  p_des = std::clamp(p_des, -config_.P_MAX, config_.P_MAX);
  v_des = std::clamp(v_des, -config_.V_MAX, config_.V_MAX);
  kp = std::clamp(kp, 0.0, config_.KP_MAX);
  kd = std::clamp(kd, 0.0, config_.KD_MAX);
  t_ff = std::clamp(t_ff, -config_.T_MAX, config_.T_MAX);

  // Convert to integers
  uint16_t p_int = floatToUint(p_des, -config_.P_MAX, config_.P_MAX, 16);
  uint16_t v_int = floatToUint(v_des, -config_.V_MAX, config_.V_MAX, 12);
  uint16_t kp_int = floatToUint(kp, 0, 500, 12);
  uint16_t kd_int = floatToUint(kd, 0, 5, 12);
  uint16_t t_int = floatToUint(t_ff, -config_.T_MAX, config_.T_MAX, 12);

  // Pack data
  CANFrame frame;
  frame.id = config_.motor_id;
  frame.len = 8;
  frame.data[0] = (p_int >> 8) & 0xFF;
  frame.data[1] = p_int & 0xFF;
  frame.data[2] = (v_int >> 4) & 0xFF;
  frame.data[3] = ((v_int & 0x0F) << 4) | ((kp_int >> 8) & 0x0F);
  frame.data[4] = kp_int & 0xFF;
  frame.data[5] = (kd_int >> 4) & 0xFF;
  frame.data[6] = ((kd_int & 0x0F) << 4) | ((t_int >> 8) & 0x0F);
  frame.data[7] = t_int & 0xFF;

  return can_->sendFrame(frame);
}

bool DMMotor::controlPositionSpeed(double position, double velocity)
{
  CANFrame frame;
  frame.id = 0x100 + config_.motor_id;
  frame.len = 8;

  // Pack as float, little-endian
  float pos_f = static_cast<float>(position);
  float vel_f = static_cast<float>(std::abs(velocity));

  std::memcpy(&frame.data[0], &pos_f, sizeof(float));
  std::memcpy(&frame.data[4], &vel_f, sizeof(float));

  return can_->sendFrame(frame);
}

bool DMMotor::controlSpeed(double velocity)
{
  CANFrame frame;
  frame.id = 0x200 + config_.motor_id;
  frame.len = 4;

  float vel_f = static_cast<float>(velocity);
  std::memcpy(&frame.data[0], &vel_f, sizeof(float));

  return can_->sendFrame(frame);
}

MotorState DMMotor::getState() const
{
  std::lock_guard<std::mutex> lock(state_mutex_);
  return state_;
}

void DMMotor::onCANFrame(const CANFrame& frame)
{
  // Check if this is feedback for this motor
  if (frame.id != static_cast<uint32_t>(config_.master_id)) {
    return;
  }

  if (frame.len < 8) {
    return;
  }

  // Parse feedback data
  uint8_t motor_id = frame.data[0] & 0x0F;
  if (motor_id != (config_.motor_id & 0x0F)) {
    return;
  }

  uint8_t error_code = (frame.data[0] >> 4) & 0x0F;

  // Parse position (16-bit)
  uint16_t pos_raw = (frame.data[1] << 8) | frame.data[2];

  // Parse velocity (12-bit)
  uint16_t vel_raw = (frame.data[3] << 4) | ((frame.data[4] >> 4) & 0x0F);

  // Parse torque (12-bit)
  uint16_t torque_raw = ((frame.data[4] & 0x0F) << 8) | frame.data[5];

  // Convert to actual values
  double position = uintToFloat(pos_raw, -config_.P_MAX, config_.P_MAX, 16);
  double velocity = uintToFloat(vel_raw, -config_.V_MAX, config_.V_MAX, 12);
  double torque = uintToFloat(torque_raw, -config_.T_MAX, config_.T_MAX, 12);

  // Temperature
  int temp_mos = frame.data[6];
  int temp_rotor = frame.data[7];

  // Update state
  std::lock_guard<std::mutex> lock(state_mutex_);
  state_.position = position;
  state_.velocity = velocity;
  state_.torque = torque;
  state_.temperature_mos = temp_mos;
  state_.temperature_rotor = temp_rotor;
  state_.enabled = (error_code == 0x1);
  state_.error_code = error_code;
}

uint16_t DMMotor::floatToUint(double x, double x_min, double x_max, int bits)
{
  x = std::clamp(x, x_min, x_max);
  double span = x_max - x_min;
  double data_norm = (x - x_min) / span;
  return static_cast<uint16_t>(data_norm * ((1 << bits) - 1));
}

double DMMotor::uintToFloat(uint16_t x, double min, double max, int bits)
{
  double span = max - min;
  double data_norm = static_cast<double>(x) / ((1 << bits) - 1);
  return data_norm * span + min;
}

//==============================================================================
// DMMototHardwareInterface Implementation
//==============================================================================

hardware_interface::CallbackReturn DMMototHardwareInterface::on_init(
  const hardware_interface::HardwareInfo & info)
{
  if (hardware_interface::SystemInterface::on_init(info) !=
      hardware_interface::CallbackReturn::SUCCESS)
  {
    return hardware_interface::CallbackReturn::ERROR;
  }

  logger_ = rclcpp::get_logger("DMMototHardwareInterface");

  // Read CAN port configuration
  can_port_ = info_.hardware_parameters["can_port"];
  can_baudrate_ = std::stoi(info_.hardware_parameters["can_baudrate"]);

  // Read control parameters
  position_kp_ = std::stod(info_.hardware_parameters["position_kp"]);
  position_kd_ = std::stod(info_.hardware_parameters["position_kd"]);

  // Read motor configurations for each joint
  motor_ids_.resize(info_.joints.size());
  master_ids_.resize(info_.joints.size());
  motor_types_.resize(info_.joints.size());

  for (size_t i = 0; i < info_.joints.size(); ++i) {
    motor_ids_[i] = std::stoi(info_.joints[i].parameters.at("motor_id"));
    master_ids_[i] = std::stoi(info_.joints[i].parameters.at("master_id"));

    std::string motor_type_str = info_.joints[i].parameters.at("motor_type");
    if (motor_type_str == "DM4340") {
      motor_types_[i] = MotorType::DM4340;
    } else {
      motor_types_[i] = MotorType::DM_J4310_2EC;
    }
  }

  // Initialize state vectors
  hw_positions_.resize(info_.joints.size(), 0.0);
  hw_velocities_.resize(info_.joints.size(), 0.0);
  hw_commands_.resize(info_.joints.size(), 0.0);

  RCLCPP_INFO(logger_, "DMMototHardwareInterface initialized with %zu joints",
              info_.joints.size());

  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::CallbackReturn DMMototHardwareInterface::on_configure(
  const rclcpp_lifecycle::State & /*previous_state*/)
{
  RCLCPP_INFO(logger_, "Configuring DMMototHardwareInterface...");

  // Create CAN interface
  can_interface_ = std::make_shared<CANInterface>(can_port_, can_baudrate_);

  if (!can_interface_->open()) {
    RCLCPP_ERROR(logger_, "Failed to open CAN interface %s", can_port_.c_str());
    return hardware_interface::CallbackReturn::ERROR;
  }

  // Create motor drivers
  motors_.clear();
  for (size_t i = 0; i < info_.joints.size(); ++i) {
    MotorConfig config;
    config.motor_id = motor_ids_[i];
    config.master_id = master_ids_[i];
    config.type = motor_types_[i];

    // Set motor parameters based on type
    if (config.type == MotorType::DM4340) {
      config.P_MAX = 12.5;
      config.V_MAX = 8.0;
      config.T_MAX = 28.0;
      config.KP_MAX = 500.0;
      config.KD_MAX = 5.0;
    } else {  // DM_J4310_2EC
      config.P_MAX = 12.5;
      config.V_MAX = 30.0;
      config.T_MAX = 10.0;
      config.KP_MAX = 500.0;
      config.KD_MAX = 5.0;
    }

    motors_.push_back(std::make_shared<DMMotor>(can_interface_, config));

    RCLCPP_INFO(logger_, "Configured motor for joint %s: ID=%d, Type=%s",
                info_.joints[i].name.c_str(), config.motor_id,
                config.type == MotorType::DM4340 ? "DM4340" : "DM-J4310-2EC");
  }

  RCLCPP_INFO(logger_, "DMMototHardwareInterface configured successfully");
  return hardware_interface::CallbackReturn::SUCCESS;
}

std::vector<hardware_interface::StateInterface>
DMMototHardwareInterface::export_state_interfaces()
{
  std::vector<hardware_interface::StateInterface> state_interfaces;

  for (size_t i = 0; i < info_.joints.size(); ++i) {
    state_interfaces.emplace_back(
      hardware_interface::StateInterface(
        info_.joints[i].name, hardware_interface::HW_IF_POSITION, &hw_positions_[i]));
    state_interfaces.emplace_back(
      hardware_interface::StateInterface(
        info_.joints[i].name, hardware_interface::HW_IF_VELOCITY, &hw_velocities_[i]));
  }

  return state_interfaces;
}

std::vector<hardware_interface::CommandInterface>
DMMototHardwareInterface::export_command_interfaces()
{
  std::vector<hardware_interface::CommandInterface> command_interfaces;

  for (size_t i = 0; i < info_.joints.size(); ++i) {
    command_interfaces.emplace_back(
      hardware_interface::CommandInterface(
        info_.joints[i].name, hardware_interface::HW_IF_POSITION, &hw_commands_[i]));
  }

  return command_interfaces;
}

hardware_interface::CallbackReturn DMMototHardwareInterface::on_activate(
  const rclcpp_lifecycle::State & /*previous_state*/)
{
  RCLCPP_INFO(logger_, "Activating DMMototHardwareInterface...");

  // Enable all motors
  for (size_t i = 0; i < motors_.size(); ++i) {
    if (!motors_[i]->enable()) {
      RCLCPP_ERROR(logger_, "Failed to enable motor %zu", i);
      return hardware_interface::CallbackReturn::ERROR;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  // Wait for initial feedback
  std::this_thread::sleep_for(std::chrono::milliseconds(200));

  // Read initial positions
  for (size_t i = 0; i < motors_.size(); ++i) {
    MotorState state = motors_[i]->getState();
    hw_positions_[i] = state.position;
    hw_velocities_[i] = state.velocity;
    hw_commands_[i] = state.position;  // Initialize command to current position

    RCLCPP_INFO(logger_, "Joint %s initial position: %.4f rad",
                info_.joints[i].name.c_str(), hw_positions_[i]);
  }

  RCLCPP_INFO(logger_, "DMMototHardwareInterface activated successfully");
  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::CallbackReturn DMMototHardwareInterface::on_deactivate(
  const rclcpp_lifecycle::State & /*previous_state*/)
{
  RCLCPP_INFO(logger_, "Deactivating DMMototHardwareInterface...");

  // Disable all motors
  for (size_t i = 0; i < motors_.size(); ++i) {
    motors_[i]->disable();
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  RCLCPP_INFO(logger_, "DMMototHardwareInterface deactivated successfully");
  return hardware_interface::CallbackReturn::SUCCESS;
}

hardware_interface::return_type DMMototHardwareInterface::read(
  const rclcpp::Time & /*time*/, const rclcpp::Duration & /*period*/)
{
  // Read motor states
  for (size_t i = 0; i < motors_.size(); ++i) {
    MotorState state = motors_[i]->getState();
    hw_positions_[i] = state.position;
    hw_velocities_[i] = state.velocity;

    // Check for errors
    if (state.error_code >= 0x8) {
      RCLCPP_WARN_THROTTLE(logger_, *rclcpp::Clock::make_shared(), 1000,
                           "Motor %zu error code: 0x%X", i, state.error_code);
    }
  }

  return hardware_interface::return_type::OK;
}

hardware_interface::return_type DMMototHardwareInterface::write(
  const rclcpp::Time & /*time*/, const rclcpp::Duration & /*period*/)
{
  // Send commands to motors using MIT mode
  for (size_t i = 0; i < motors_.size(); ++i) {
    // Use MIT control with position command
    motors_[i]->controlMIT(
      hw_commands_[i],     // target position
      0.0,                 // target velocity (let controller handle it)
      position_kp_,        // position gain
      position_kd_,        // damping gain
      0.0                  // feedforward torque
    );
  }

  return hardware_interface::return_type::OK;
}

}  // namespace dmmotor_hardware_interface

#include "pluginlib/class_list_macros.hpp"

PLUGINLIB_EXPORT_CLASS(
  dmmotor_hardware_interface::DMMototHardwareInterface,
  hardware_interface::SystemInterface)
