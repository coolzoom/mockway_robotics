## 测试环境

Ubuntu24.04(WSL2)

ROS2 Jazzy

### Windows 一键安装（WSL2，推荐在 Windows 上使用）

运行统一菜单（双击即可，无需记多个 bat 路径）：

```bat
tools\setup_wsl_moveit.bat
```

### Ubuntu 原生安装（物理机 / 虚拟机 / 双系统）

在 Ubuntu 24.04 终端中：

```bash
chmod +x tools/setup_moveit_ubuntu.sh
./tools/setup_moveit_ubuntu.sh
```

| 选项 | 功能 |
|------|------|
| **1** | 完整安装：ROS2 Jazzy + MoveIt2 + mockway_ws（需 sudo） |
| **2** | 启动 MoveIt2 Demo (RViz) |
| **3** | 打开工作 Shell |
| **4** | USB-CAN 串口检测与 dialout 权限 |
| **5** | 仅重新编译工作空间 |
| **6** | 环境与诊断信息 |

命令行快捷方式：`./tools/setup_moveit_ubuntu.sh 2` 或 `demo` / `install` / `usb` 等

---

### Windows WSL 菜单对照

```bat
tools\setup_wsl_moveit.bat
```

| 选项 | 功能 |
|------|------|
| **1** | 完整安装：WSL2 + Ubuntu + MoveIt2 + usbipd（需管理员） |
| **2** | 仅 WSL 内依赖：ROS2 Jazzy + MoveIt2 + mockway_ws |
| **3** | 启动 MoveIt2 Demo (RViz)，**默认真机 + USB-CAN**（启动前先 **[6]** 透传 USB） |
| **4** | 打开 WSL 工作 Shell |
| **5** | 修复 WSL 0x80370114（需管理员） |
| **6** | USB-CAN 透传到 WSL（需管理员） |
| **7** | 跳过 WSL 安装，仅配置 MoveIt/usbipd（需管理员） |
| **8** | 断开 USB 透传，COM 口归还 Windows（需管理员） |

也可命令行直达：`tools\setup_wsl_moveit.bat 2`（数字 1–8 同菜单）

USB 透传：`tools\setup_wsl_moveit.bat 6 5-1`  
断开透传：`tools\setup_wsl_moveit.bat 8 5-1 unbind`（`unbind` 可选，完全释放 COM 给 Windows）

仅重装 MoveIt（已有 Ubuntu）：菜单 **[7]** 或 `tools\setup_wsl_moveit.bat 7`

**若 RViz 窗口空白、一闪而过或报 `Invalid parentWindowHandle` / `GLXWindow`：**

1. **不要从「管理员: 命令提示符」启动 [3]** — WSLg 在提权终端下常无法显示 GUI
2. 双击运行：`tools\launch_moveit_demo.bat`（普通权限，已自动设置 `QT_QPA_PLATFORM=xcb`）
3. 或在 WSL 终端：`bash tools/wsl/launch_moveit_demo.sh`
4. 仍失败时可试：`export LIBGL_ALWAYS_SOFTWARE=1` 后再启动（软件渲染，较慢）
5. 任务栏有图标但空白：Alt+Tab 选中后按 **Win+Shift+←/→** 移到当前屏幕；或删除 WSL 内 `~/.rviz2` 后重试
6. 重新编译以更新窗口配置：`colcon build --packages-select moveit_mockway_config --symlink-install`

**若 MoveIt Demo 报 `Waiting for data on robot_description`：**

1. **Demo 默认接真机**（`use_mock_hardware:=false`），须先编译硬件插件并挂载 USB-CAN：
   ```bash
   colcon build --packages-select dmmotor_hardware_interface moveit_mockway_config --symlink-install
   tools\setup_wsl_moveit.bat 6          # Windows 管理员：USB 透传
   ls /dev/ttyACM0                         # WSL 确认串口
   ros2 launch moveit_mockway_config demo.launch.py
   ```
2. **无硬件仅仿真**时显式加 mock：
   ```bash
   ros2 launch moveit_mockway_config demo.launch.py use_mock_hardware:=true
   ```
   或双击 `tools\launch_moveit_demo.bat` 并传入参数（见脚本说明）
3. 若日志出现 `DMMototHardwareInterface ... does not exist`，说明未编译 `dmmotor_hardware_interface`
4. 若硬件初始化失败（如 `/dev/ttyACM0` 打不开），controller_manager 也会反复等待 `robot_description`，需先修复串口权限或改回 mock

**若提示 `Ubuntu-24.04 not found`：**

1. 再次运行 `tools\setup_wsl_moveit.bat`（已重启后不应再提示重启）
2. 管理员 PowerShell 手动安装：`wsl --install -d Ubuntu-24.04`
3. 按提示创建 Ubuntu 用户名和密码
4. 再运行：`tools\setup_wsl_moveit.bat` 选 **[2]** 或 **[7]**

**若提示 `CPU virtualization is disabled` 或错误 `0x80370114`：**

1. **管理员运行菜单 [5]：** `tools\setup_wsl_moveit.bat 5`
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
