## TODO

以下功能在新 Lua API（LUA.md）中暂无对应接口，Blockly 中未实现：

- **弧线运动** — 原 `Circ` / `CircJ` 块，新 API 无对应
- **正逆运动学** — 原 `FK` / `IK` 块，新 API 无对应
- **运动控制** — 原 `Stop` / `Pause` / `Resume`，新 API 无对应
- **错误处理** — 原 `CleanError` / `GetErrorID`，新 API 无对应
- **队列管理** — 原 `IsQueueEmpty` / `WaitQueueEmpty`，新 API 无对应
- **位姿四元数输入** — `robot.move_to_pose(x,y,z,qx,qy,qz,qw)` 和 `robot.move_linear(...)` 未做 block
- **可选参数暴露** — `move_linear_rpy` / `move_linear_relative` 的 `step`、`min_fraction` 参数未在 block 中提供
- **ServoCartesian frame_id** — `robot.servo_cartesian` 的可选 `frame_id` 参数未暴露
