cmake_minimum_required(VERSION 3.16)
project(mockway_lua_moveit)

if(CMAKE_COMPILER_IS_GNUCXX OR CMAKE_CXX_COMPILER_ID MATCHES "Clang")
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()
set(CMAKE_CXX_STANDARD 17)

# ── 基础依赖 ──────────────────────────────────────────────────────────────────
find_package(ament_cmake REQUIRED)

set(THIS_PACKAGE_INCLUDE_DEPENDS
  rclcpp
  moveit_core
  moveit_ros_planning
  moveit_ros_planning_interface
  moveit_msgs
  geometry_msgs
  control_msgs
  sensor_msgs
  std_msgs
  std_srvs
  tf2_ros
  tf2_eigen
  trajectory_msgs
)
foreach(dep IN ITEMS ${THIS_PACKAGE_INCLUDE_DEPENDS})
  find_package(${dep} REQUIRED)
endforeach()

# ── Lua ──────────────────────────────────────────────────────────────────────
# 优先查找 Lua 5.4，其次 5.3
find_package(Lua 5.4 QUIET)
if(NOT LUA_FOUND)
  find_package(Lua 5.3 REQUIRED)
endif()
message(STATUS "Found Lua ${LUA_VERSION_STRING}: ${LUA_LIBRARIES}")

# ── sol2 (via ros-jazzy-sol-vendor) ──────────────────────────────────────
find_package(sol_vendor REQUIRED)

# ── 可执行目标 ───────────────────────────────────────────────────────────────
add_executable(lua_moveit_node src/lua_moveit_node.cpp)

target_include_directories(lua_moveit_node PRIVATE
  ${LUA_INCLUDE_DIR}
)

target_link_libraries(lua_moveit_node
  ${LUA_LIBRARIES}
)

ament_target_dependencies(lua_moveit_node
  ${THIS_PACKAGE_INCLUDE_DEPENDS}
  sol_vendor
)

# ── 安装 ─────────────────────────────────────────────────────────────────────
install(
  TARGETS lua_moveit_node
  RUNTIME DESTINATION lib/${PROJECT_NAME}
)

install(
  DIRECTORY lua launch
  DESTINATION share/${PROJECT_NAME}
)

ament_package()
