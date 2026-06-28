@echo off
chcp 65001 >nul
set "DISTRO=Ubuntu-24.04"
wsl -l -v 2>nul | findstr /I "Ubuntu-24.04" >nul || set "DISTRO=Ubuntu"
echo [mockway] 启动 MoveIt2 Demo (WSL: %DISTRO%) ...
wsl -d %DISTRO% -- bash -lc "source /opt/ros/jazzy/setup.bash && source ~/mockway_ws/install/setup.bash && ros2 launch moveit_mockway_config demo.launch.py"
pause
