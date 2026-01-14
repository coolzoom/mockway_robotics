# Quick Start Guide - DM Motor Hardware Interface

## 1. Setup CAN Interface (One-time Setup)

```bash
# Install CAN utilities
sudo apt-get update
sudo apt-get install can-utils

# Configure CAN interface (run after each boot, or setup systemd service)
sudo ip link set can0 type can bitrate 1000000
sudo ip link set up can0

# Verify CAN interface is up
ip link show can0
```

## 2. Build the Package

```bash
cd ~/ws/mockway_robotics
colcon build --packages-select dmmotor_hardware_interface
source install/setup.bash
```

## 3. Motor Hardware Setup

1. **Power Connection**: Connect 24V power supply to motors
2. **CAN Wiring**:
   - Connect all motors to CAN bus
   - Ensure 120Ω termination resistors at both ends of CAN bus
3. **Motor IDs**: Verify motor CAN IDs match configuration:
   - Motor 1 (J1): ID=1, Type=DM-J4310-2EC
   - Motor 2 (J2): ID=2, Type=DM4340
   - Motor 3 (J3): ID=3, Type=DM4340
   - Motor 4 (J4): ID=4, Type=DM-J4310-2EC
   - Motor 5 (J5): ID=5, Type=DM-J4310-2EC
   - Motor 6 (J6): ID=6, Type=DM-J4310-2EC

## 4. Test CAN Communication

```bash
# Monitor CAN traffic (in one terminal)
candump can0

# In another terminal, enable a motor manually (for testing)
# Enable motor ID 1
cansend can0 001#FFFFFFFFFFFFFFFF FC

# You should see feedback messages on candump
```

## 5. Launch with MoveIt

```bash
# Build moveit config if not already done
cd ~/ws/mockway_robotics
colcon build --packages-select moveit_mockway_config
source install/setup.bash

# Launch MoveIt with real hardware
ros2 launch moveit_mockway_config demo.launch.py
```

## 6. Verify Operation

```bash
# Check hardware component status
ros2 control list_hardware_components

# Expected output:
# Hardware Component 0
#   name: MockwayArm
#   type: system
#   plugin name: dmmotor_hardware_interface/DMMototHardwareInterface
#   state: id=3 label=active
#   command interfaces
#     joint1/position [available] [claimed]
#     joint2/position [available] [claimed]
#     ...

# Check controllers
ros2 control list_controllers

# Monitor joint states
ros2 topic echo /joint_states
```

## 7. Control Tuning (Optional)

Edit `/moveit_mockway_config/config/mockway_description.ros2_control.xacro`:

```xml
<param name="position_kp">40.0</param>  <!-- Increase for stiffer control -->
<param name="position_kd">1.0</param>   <!-- Increase for more damping -->
```

After changing parameters:
```bash
colcon build --packages-select moveit_mockway_config
source install/setup.bash
# Restart the launch file
```

## Common Issues

### Issue: "Failed to open CAN interface"
**Solution**:
```bash
sudo ip link set can0 type can bitrate 1000000
sudo ip link set up can0
```

### Issue: "No feedback from motors"
**Check:**
1. Motor power supply is on
2. CAN wiring and termination
3. Motor IDs match configuration
4. Run `candump can0` to see if any CAN traffic

### Issue: "Motors jitter or oscillate"
**Solution**: Reduce `position_kp` or increase `position_kd`

### Issue: "Slow response"
**Solution**: Increase `position_kp` (but not too high to avoid oscillation)

## Safety Checklist

- [ ] Emergency stop button is accessible
- [ ] Workspace is clear of obstacles
- [ ] Joint limits are properly configured
- [ ] Start with low velocity scaling factor (0.1)
- [ ] Monitor motor temperatures during operation
- [ ] CAN termination resistors are installed (120Ω at both ends)

## Next Steps

- Test basic movements with MoveIt GUI
- Tune control parameters for your application
- Set up velocity/acceleration limits
- Implement safety monitoring
- Create custom motion plans

For detailed information, see [README.md](README.md)
