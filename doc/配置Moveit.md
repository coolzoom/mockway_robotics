## 测试环境

Ubuntu24.04(WSL2)

ROS2 Jazzy

### Windows 一键安装（推荐）

在仓库根目录双击或以管理员运行：

```bat
tools\setup_wsl_moveit.bat
```

脚本将自动：启用 WSL2、安装 Ubuntu 24.04、在 WSL 内安装 ROS2 Jazzy + MoveIt2、编译 `mockway_ws`、安装 `usbipd-win`。

| 后续操作 | 命令 |
|----------|------|
| **仅 WSL 内装依赖**（已有 Ubuntu，无需管理员） | `tools\wsl\install_all_deps.bat` |
| 完整安装（WSL + Ubuntu + usbipd） | `tools\setup_wsl_moveit.bat`（管理员） |
| 启动 MoveIt Demo | `tools\wsl\launch_moveit_demo.bat` |
| 打开 WSL 工作 shell | `tools\wsl\mockway_wsl_shell.bat` |
| USB-CAN 透传到 WSL | `tools\wsl\attach_usb_can.bat`（管理员，需先插入适配器） |

仅重装 MoveIt（已有 Ubuntu）：`powershell -ExecutionPolicy Bypass -File tools\setup_wsl_moveit.ps1 -SkipWslInstall`

**若提示 `Ubuntu-24.04 not found`：**

1. 再次运行 `tools\setup_wsl_moveit.bat`（已重启后不应再提示重启）
2. 管理员 PowerShell 手动安装：`wsl --install -d Ubuntu-24.04`
3. 按提示创建 Ubuntu 用户名和密码
4. 再运行：`tools\setup_wsl_moveit.bat -SkipWslInstall` 或 `tools\wsl\install_all_deps.bat`

**若提示 `CPU virtualization is disabled` 或错误 `0x80370114`：**

1. **管理员运行修复脚本：** `tools\wsl\fix_wsl_hypervisor.bat`
2. 打开「启用或关闭 Windows 功能」，勾选并应用后**重启**：
   - 适用于 Linux 的 Windows 子系统
   - 虚拟机平台
   - Windows 虚拟机监控程序平台
3. 重启后管理员 PowerShell 执行：
   ```powershell
   bcdedit /set hypervisorlaunchtype Auto
   wsl --install -d Ubuntu-24.04
   ```
4. 确认 `C:\Windows\System32\vmcompute.exe` 存在；若仍缺失，在 BIOS 开启 **Intel VT-x / AMD-V**：https://aka.ms/enablevirtualization

bios启动cpu虚拟化
控制面板windows组件安装hyper-v
---

## 一、环境步骤（手动 / Linux）

1. 安装Moveit2和配置助手

```bash
sudo apt update
sudo apt install ros-jazzy-moveit ros-jazzy-moveit-setup-assistant
```
2. 创建工作空间

```bash
mkdir -p ~/mockway_ws/src
cd ~/mockway_ws/src
```
3. 克隆mockway_robotics仓库

```bash
git clone https://github.com/Jelatine/mockway_robotics.git
```
4. 编译工作空间

```bash
cd ~/mockway_ws
colcon build --symlink-install
```
5. 配置环境变量

```bash
source ~/mockway_ws/install/setup.bash
```

## 二、配置Moveit2步骤

1. 启动`moveit_setup_assistant`

```bash
ros2 launch moveit_setup_assistant setup_assistant.launch.py
```
2. Start Screen

- 1️⃣选择`Create New Moveit Configuration Package`
- 2️⃣`Browse` 打开 `mockway_robotics/mockway_description/urdf/mockway_description.urdf`文件。
- 3️⃣`Load Files`

3. Self-Collisions

- 1️⃣`Generate Collision Matrix`
  
4. Planning Groups

- 1️⃣`Add Group`
- 2️⃣`Group Name` 输入 `mockway_group`
- 3️⃣`Kinematic Solver` 选择 `KDL`
- 4️⃣`Group Default Planner` 选择 `RRT`
- 5️⃣`Add Kin. Chain` 点左下角 `Expand All`
- 6️⃣`Base Link` 选择 `base_link`
- 7️⃣`Tip Link` 选择 `link6`
- 8️⃣`Save`

5. Robot Poses

- 1️⃣`Pose Name` 输入 `home`
- 2️⃣`Add Pose`
- 3️⃣`Save`

6. ROS 2 Controllers

- 1️⃣`Auto Add JointTrajectory Controller`

7. Moveit Controllers

- 1️⃣`Auto Add FollowJointTrajectory`

8. Author Information

- 1️⃣`Name`
- 2️⃣`Email`

9. Configuration Files

- 1️⃣`Browse`
- 2️⃣转到路径 `mockway_robotics/` 新建文件夹 `moveit_mockway_config`
- 3️⃣`Generate Package`
- 4️⃣`Exit Setup Assistant`

### 检查生成内容

```bash
tree src/mockway_robotics/moveit_mockway_config/
```

### 解决生成内容的问题

#### ❌ No acceleration limit was defined for joint joint1! You have to define acceleration limits in the URDF or joint_limits.yaml

编辑`joint_limits.yaml`文件

```bash
vim ~/mockway_ws/src/mockway_robotics/moveit_mockway_config/config/joint_limits.yaml
```

将所有`has_acceleration_limits`设置为`true`

将所有整型数据改为浮点型

#### ❌ No action namespace specified for controller `mockway_group_controller` through parameter `moveit_simple_controller_manager.mockway_group_controller.action_ns`

编辑`moveit_controllers.yaml`文件

```bash
vim ~/mockway_ws/src/mockway_robotics/moveit_mockway_config/config/moveit_controllers.yaml
```

在 `type: FollowJointTrajectory` 上一行增加 `action_ns: follow_joint_trajectory`

## 四、启动Moveit2

1. 安装包依赖

删除`package.xml`中的`warehouse_ros_mongo`

```bash
vim ~/mockway_ws/src/mockway_robotics/moveit_mockway_config/package.xml
```

```bash
rosdep install --from-paths src --ignore-src -r -y
```

2. 再次编译工作空间和配置环境变量

```bash
cd ~/mockway_ws
colcon build --symlink-install
source install/setup.bash
```

3. 启动模拟器

```bash
ros2 launch moveit_mockway_config demo.launch.py
```
