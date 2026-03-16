# mockway_lua_moveit

使用 [sol2](https://github.com/ThePhD/sol2) 将 MoveIt 和 MoveIt Servo 封装为 Lua 全局函数，通过执行 Lua 脚本控制机械臂。

## 单位约定

> 所有 Lua API 输入/输出统一使用以下单位：
>
> | 量 | 单位 |
> |---|---|
> | 位置（x, y, z） | **mm**（毫米） |
> | 角度（关节、RPY、旋转增量） | **deg**（度） |
> | 线速度（Servo） | **mm/s** |
> | 角速度（Servo） | **deg/s** |
> | 暂停时间（Sleep） | **ms**（毫秒） |
> | 插值步长（直线运动） | **mm**，默认 10 |

## 前置条件

运行前需启动以下节点之一：

| 场景 | 启动命令 |
|---|---|
| 仅 MoveIt（PTP / 直线运动） | `ros2 launch moveit_mockway_config demo.launch.py` |
| 仅 Servo（手动点动） | `ros2 launch mockway_moveit_servo servo.launch.py` |
| MoveIt + Servo | `ros2 launch mockway_bringup mockway.launch.py` |

## 快速启动

```bash
# 使用内置演示脚本（脚本名不含 .lua）
ros2 launch mockway_lua_moveit lua_moveit.launch.py script:=demo_ptp
ros2 launch mockway_lua_moveit lua_moveit.launch.py script:=demo_linear
ros2 launch mockway_lua_moveit lua_moveit.launch.py script:=demo_joint_servo
ros2 launch mockway_lua_moveit lua_moveit.launch.py script:=demo_cartesian_servo

# 使用自定义脚本
ros2 launch mockway_lua_moveit lua_moveit.launch.py script_path:=/path/to/my_script.lua
```

### launch 参数

| 参数 | 默认值 | 说明 |
|---|---|---|
| `script` | `demo_joint_servo` | 内置 `lua/` 目录下的脚本名（不含 `.lua`） |
| `script_path` | `""` | 脚本绝对路径，优先级高于 `script` |
| `planning_group` | `mockway_group` | MoveIt 规划组 |
| `ee_frame` | `link6` | 末端执行器坐标系 |
| `base_frame` | `base_link` | 基坐标系 |
| `launch_servo` | `false` | 是否同时启动 servo_node |

---

## curl 调用（HTTP API）

节点启动后会内置 HTTP 服务器，可通过 `POST /api/lua` 接口从命令行直接发送 Lua 脚本，无需重启节点。

### 基本用法

```bash
# 执行单行脚本
curl -s -X POST http://localhost:8080/api/lua \
  -H "Content-Type: application/json" \
  -d '{"script":"Log(\"hello\")"}'

# 响应示例
# {"success":true,"message":"Script executed successfully","output":""}
```

### 执行多行脚本

```bash
curl -s -X POST http://localhost:8080/api/lua \
  -H "Content-Type: application/json" \
  -d '{
    "script": "SetVelScale(0.3)\nMoveNamed(\"home\")"
  }'
```

### 从 .lua 文件执行

```bash
# 需要安装 jq（sudo apt install jq）
curl -s -X POST http://localhost:8080/api/lua \
  -H "Content-Type: application/json" \
  -d "$(jq -n --rawfile s /path/to/my_script.lua '{script:$s}')"
```

### 定义 Shell 快捷函数

在 `~/.bashrc` 中添加以下函数，之后可直接调用：

```bash
lua_exec() {
  curl -s -X POST http://localhost:8080/api/lua \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg s "$1" '{script:$s}')" | jq .
}

lua_file() {
  curl -s -X POST http://localhost:8080/api/lua \
    -H "Content-Type: application/json" \
    -d "$(jq -n --rawfile s "$1" '{script:$s}')" | jq .
}
```

使用示例：

```bash
lua_exec 'MoveNamed("home")'
lua_exec 'local j = GetJoints(); print(j[1], j[2], j[3], j[4], j[5], j[6])'
lua_file /path/to/my_script.lua
```

---

## Lua API 参考

所有接口均为**全局函数**，直接调用，无需 `robot.` 前缀。

### 一、Servo 手动点动

> 需要 servo_node 运行。发布消息后立即返回（非阻塞）。

#### `ServoMode(mode)` → bool

切换 Servo 命令类型。

| 参数 | 类型 | 说明 |
|---|---|---|
| `mode` | string | `"joint_jog"` 或 `"twist"` |

```lua
ServoMode("joint_jog")
ServoMode("twist")
```

#### `ServoJoint(index, velocity)`

单关节速度点动。

| 参数 | 类型 | 说明 |
|---|---|---|
| `index` | string \| int | 关节名 `"joint1"`～`"joint6"` 或索引 `1`～`6` |
| `velocity` | number | 目标速度，单位 **deg/s** |

```lua
ServoJoint(1, 20.0)           -- joint1 以 20 deg/s 点动
ServoJoint("joint3", -15.0)   -- joint3 反向点动
```

#### `ServoJoints(velocities)`

六轴同时速度点动。

| 参数 | 类型 | 说明 |
|---|---|---|
| `velocities` | table | `{v1, v2, v3, v4, v5, v6}`，单位 **deg/s** |

```lua
ServoJoints({0.0, 0.0, 0.0, 20.0, 20.0, 0.0})
```

#### `ServoCart(vx, vy, vz, rx, ry, rz [, frame_id])`

笛卡尔空间速度点动（Twist）。

| 参数 | 类型 | 说明 |
|---|---|---|
| `vx/vy/vz` | number | 线速度，单位 **mm/s** |
| `rx/ry/rz` | number | 角速度，单位 **deg/s** |
| `frame_id` | string | 参考坐标系，默认 `"base_link"` |

```lua
ServoCart(100, 0, 0,  0, 0, 0)                  -- 沿基坐标系 X 轴前进
ServoCart(0, 0, 100,  0, 0, 0,  "link6")         -- 沿末端 Z 轴移动
```

#### `ServoStop()`

向两个 topic 发布零速，停止 Servo 运动。

```lua
ServoStop()
```

---

### 二、MoveIt 点到点运动（PTP）

> 需要 move_group 运行。阻塞直到运动完成，返回 bool。

#### `MoveNamed(name)` → bool

运动到 SRDF 中定义的命名状态。

```lua
MoveNamed("home")
MoveNamed("ready")
```

#### `MoveJ(positions)` → bool

按关节角度做 PTP 运动。

| 参数 | 类型 | 说明 |
|---|---|---|
| `positions` | table | `{j1, j2, j3, j4, j5, j6}`，单位 **deg** |

```lua
MoveJ({0, -45, -90, 60, 90, 0})
```

#### `MovePose(x, y, z, roll, pitch, yaw)` → bool

按末端位姿做 PTP 运动（RPY 欧拉角）。x/y/z 单位 **mm**，角度单位 **deg**。

```lua
MovePose(250, 100, 300,  180, 0, 0)
MovePose(250, -100, 300, 180, 0, 30)   -- yaw 偏转 30°
```

---

### 三、MoveIt 直线运动（Linear）

> 需要 move_group 运行。通过 `computeCartesianPath` 实现，阻塞直到运动完成，返回 bool。
> 规划成功率 < 90% 时取消执行并返回 false。

#### `MoveL(x, y, z, roll, pitch, yaw [, step])` → bool

绝对位姿直线运动。x/y/z 单位 **mm**，角度 **deg**，step 单位 **mm** 默认 10。

```lua
MoveL(300, 0, 400,  180, 0, 0)
MoveL(300, 0, 400,  180, 0, 0,  5)   -- 精细步长 5mm
```

#### `MoveLRel(dx, dy, dz, drx, dry, drz [, step])` → bool

相对当前末端位置的增量直线运动（增量在**基坐标系**下表达）。

| 参数 | 类型 | 说明 |
|---|---|---|
| `dx/dy/dz` | number | 位置偏移，单位 **mm** |
| `drx/dry/drz` | number | 姿态偏移（RPY 增量），单位 **deg** |

```lua
MoveLRel(0.0,  0.0, 50.0,  0.0, 0.0,  0.0)   -- 沿基坐标系 Z 轴上升 50mm
MoveLRel(30.0, 0.0, 0.0,   0.0, 0.0, 10.0)   -- X 前移 30mm + 绕 Z 轴转 10°
```

#### `MoveLRelTool(dx, dy, dz, drx, dry, drz [, step])` → bool

相对当前末端位置的增量直线运动（增量在**工具坐标系**下表达）。

平移量先由工具姿态旋转至基坐标系再叠加；旋转量在工具坐标系下施加（`q_new = q_cur * q_delta`）。

```lua
MoveLRelTool(0.0, 0.0, 50.0,  0.0, 0.0, 0.0)    -- 沿工具 Z 轴（进给方向）前进 50mm
MoveLRelTool(20.0, 0.0, 0.0,  0.0, 0.0, 15.0)   -- 沿工具 X 轴平移 + 绕工具 Z 轴转 15°
```

---

### 四、规划参数

> 需要 move_group 运行。设置后对后续所有规划生效。

#### `SetVelScale(factor)`

设置最大速度缩放系数，范围 `[0.01, 1.0]`。

```lua
SetVelScale(0.3)   -- 30% 最大速度
```

#### `SetAccScale(factor)`

设置最大加速度缩放系数，范围 `[0.01, 1.0]`。

```lua
SetAccScale(0.1)
```

#### `SetPlanTime(seconds)`

设置规划超时时间。

```lua
SetPlanTime(5.0)
```

#### `SetPlanner(planner_id)`

切换运动规划器。

```lua
SetPlanner("RRTConnect")
SetPlanner("LIN")   -- Pilz 直线规划器
```

---

### 五、状态查询

> 需要 move_group 运行。

#### `GetJoints()` → table

返回当前关节角度 `{j1..j6}`，单位 **deg**。

```lua
local j = GetJoints()
-- j[1]~j[6]，单位 deg
print(j[1])
```

#### `GetPose()` → table

返回当前末端位姿 `{x, y, z, roll, pitch, yaw}`，x/y/z 单位 **mm**，角度单位 **deg**。

```lua
local p = GetPose()
-- p[1]=x  p[2]=y  p[3]=z     （mm）
-- p[4]=roll  p[5]=pitch  p[6]=yaw  （deg）
print(string.format("x=%.1f  y=%.1f  z=%.1f mm", p[1], p[2], p[3]))
```

---

### 六、工具函数

#### `Sleep(ms)`

暂停执行，单位**毫秒**。

```lua
Sleep(500)    -- 暂停 500ms
Sleep(1000)   -- 暂停 1s
```

#### `Log(msg)` / `LogWarn(msg)` / `LogError(msg)`

输出 ROS 日志。

```lua
Log("运动完成")
LogWarn("速度过高")
LogError("规划失败")
```

#### `Ok()` → bool

返回 ROS 节点是否仍在运行，可用于循环退出条件。

```lua
while Ok() do
  ServoJoint(1, 20.0)
  Sleep(20)
end
```

#### `DegRad(deg)` / `RadDeg(rad)`

角度与弧度互转。

```lua
DegRad(90)    -- → 1.5708
RadDeg(1.57)  -- → 89.95
```

---

## 内置演示脚本

| 脚本 | 功能 | 所需节点 |
|---|---|---|
| `demo_joint_servo.lua` | 逐轴 / 多轴关节点动演示（deg/s） | servo_node |
| `demo_cartesian_servo.lua` | 笛卡尔平移（mm/s）/ 旋转（deg/s）/ 组合点动 | servo_node |
| `demo_ptp.lua` | PTP 命名状态 / 关节角（deg）/ 位姿目标（mm）/ 速度缩放 | move_group |
| `demo_linear.lua` | 绝对 / 相对（基坐标系 & 工具坐标系）/ 多航点直线运动 | move_group |

---

## 编写自定义脚本

```lua
-- my_script.lua

-- 初始参数
SetVelScale(0.3)
SetAccScale(0.1)

-- 回 home
assert(MoveNamed("home"), "回 home 失败")

-- 直线上升 50mm（基坐标系 Z 轴）
MoveLRel(0, 0, 50,  0, 0, 0)

-- 打印当前状态
local p = GetPose()
print(string.format("到达: x=%.1f  y=%.1f  z=%.1f mm", p[1], p[2], p[3]))
```

启动：

```bash
ros2 launch mockway_lua_moveit lua_moveit.launch.py \
  script_path:=/path/to/my_script.lua
```
