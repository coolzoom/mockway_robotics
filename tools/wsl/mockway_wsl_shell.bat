@echo off
chcp 65001 >nul
set "DISTRO=Ubuntu-24.04"
wsl -l -v 2>nul | findstr /I "Ubuntu-24.04" >nul || set "DISTRO=Ubuntu"
start "Mockway-WSL" wsl -d %DISTRO% -- bash -lc "source ~/.bashrc 2>/dev/null; cd ~/mockway_ws 2>/dev/null; exec bash"
