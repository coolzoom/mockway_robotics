# DM Motor Hardware Interface for ROS2 Control

ROS2 Control hardware interface plugin for DM motors (DM-J4310-2EC and DM4340) using SocketCAN.

## Features

- Support for DM-J4310-2EC and DM4340 motors
- MIT control mode for smooth position/velocity control
- SocketCAN interface for CAN communication
- Real-time motor state feedback (position, velocity, torque, temperature)
- Configurable per-joint motor parameters

## Motor Configuration

### Joint Assignment
- Joint 1 (J1): DM-J4310-2EC
- Joint 2 (J2): DM4340
- Joint 3 (J3): DM4340
- Joint 4 (J4): DM-J4310-2EC
- Joint 5 (J5): DM-J4310-2EC
- Joint 6 (J6): DM-J4310-2EC

### Motor Parameters

**DM-J4310-2EC:**
- Max Position: ±12.5 rad
- Max Velocity: 30.0 rad/s
- Max Torque: 10.0 Nm

**DM4340:**
- Max Position: ±12.5 rad
- Max Velocity: 8.0 rad/s
- Max Torque: 28.0 Nm

## Prerequisites

### 1. Install SocketCAN utilities

```bash
sudo apt-get update
sudo apt-get install can-utils
```

### 2. Configure CAN Interface

Create a script to configure the CAN interface (e.g., `/etc/systemd/system/can-setup.sh`):

```bash
#!/bin/bash
# Setup CAN interface
sudo ip link set can0 type can bitrate 1000000
sudo ip link set up can0
```

Make it executable:
```bash
chmod +x /etc/systemd/system/can-setup.sh
```

To automatically setup CAN on boot, create a systemd service (`/etc/systemd/system/can-setup.service`):

```ini
[Unit]
Description=Setup CAN interface
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/systemd/system/can-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Enable the service:
```bash
sudo systemctl daemon-reload
sudo systemctl enable can-setup.service
sudo systemctl start can-setup.service
```

### 3. Verify CAN Interface

```bash
# Check if CAN interface is up
ip link show can0

# Monitor CAN traffic
candump can0

# Send test frame
cansend can0 123#DEADBEEF
```

## Building

```bash
cd ~/ws/mockway_robotics
colcon build --packages-select dmmotor_hardware_interface
source install/setup.bash
```

## Configuration

The hardware interface is configured in the URDF/xacro file (`moveit_mockway_config/config/mockway_description.ros2_control.xacro`).

### Hardware Parameters

```xml
<hardware>
    <plugin>dmmotor_hardware_interface/DMMototHardwareInterface</plugin>
    <param name="can_port">can0</param>
    <param name="can_baudrate">1000000</param>
    <param name="position_kp">40.0</param>
    <param name="position_kd">1.0</param>
</hardware>
```

### Joint Parameters

For each joint, specify:
- `motor_id`: CAN ID of the motor (1-127)
- `master_id`: CAN ID for receiving feedback (typically 0)
- `motor_type`: Either `DM_J4310_2EC` or `DM4340`

Example:
```xml
<joint name="joint1">
    <command_interface name="position"/>
    <state_interface name="position"/>
    <state_interface name="velocity"/>
    <param name="motor_id">1</param>
    <param name="master_id">0</param>
    <param name="motor_type">DM_J4310_2EC</param>
</joint>
```

## Usage

### Starting the Hardware Interface

The hardware interface is automatically loaded by ros2_control when you launch MoveIt:

```bash
ros2 launch moveit_mockway_config demo.launch.py
```

### Motor Control Modes

The hardware interface uses **MIT control mode** for position control:

```
torque = kp * (p_cmd - p_actual) + kd * (v_cmd - v_actual)
```

Control parameters (`position_kp` and `position_kd`) can be tuned in the xacro file.

### Monitoring Motor Status

```bash
# Check joint states
ros2 topic echo /joint_states

# Monitor controller status
ros2 control list_controllers

# View hardware component status
ros2 control list_hardware_components
```

## Troubleshooting

### CAN Interface Issues

**Problem:** `Failed to open CAN interface can0`

**Solutions:**
1. Check if CAN interface exists: `ip link show can0`
2. Bring up the interface: `sudo ip link set up can0`
3. Verify bitrate: `ip -details link show can0`
4. Check permissions: Add user to `dialout` group if needed

**Problem:** `No feedback from motors`

**Solutions:**
1. Check CAN wiring and termination resistors (120Ω at both ends)
2. Verify motor power supply
3. Monitor CAN bus: `candump can0`
4. Check motor IDs match configuration
5. Ensure motors are properly enabled

**Problem:** `Motors not responding to commands`

**Solutions:**
1. Verify motors are enabled (check error codes)
2. Check motor ID configuration
3. Ensure CAN baudrate matches (1 Mbps)
4. Verify MIT control parameters are reasonable

### Error Codes

Motor error codes are reported in feedback:
- `0x0`: Disabled
- `0x1`: Enabled (normal operation)
- `0x8`: Over-voltage
- `0x9`: Under-voltage
- `0xA`: Over-current
- `0xB`: MOS over-temperature
- `0xC`: Coil over-temperature
- `0xD`: Communication loss
- `0xE`: Overload

## Safety Notes

1. **Emergency Stop**: Always have an emergency stop mechanism
2. **Workspace Limits**: Ensure joint limits are properly configured
3. **Temperature Monitoring**: Monitor motor temperatures during operation
4. **Power Supply**: Use appropriate power supply (check motor specifications)
5. **Initial Testing**: Test with low velocities and accelerations initially

## Development and Debugging

### Enable Debug Logging

```bash
ros2 launch moveit_mockway_config demo.launch.py --ros-args --log-level dmmotor_hardware_interface:=debug
```

### Test Individual Motors

Use the Python driver for testing:

```bash
cd ~/ws/mockway_robotics/tools/motor_gui
python3 dm_motor_driver.py
```

## References

- [ROS2 Control Documentation](https://control.ros.org/)
- [SocketCAN Documentation](https://www.kernel.org/doc/Documentation/networking/can.txt)
- DM Motor Manual (refer to manufacturer documentation)

## License

MIT License - Copyright (c) 2025 Mockway Robotics
