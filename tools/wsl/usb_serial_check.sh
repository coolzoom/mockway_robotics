#!/usr/bin/env bash
# USB 透传后在 WSL 内检测串口设备
set -eo pipefail

export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null; then
  sudo -n apt-get install -y -qq usbutils 2>/dev/null || sudo apt-get install -y -qq usbutils || true
fi
sudo modprobe cdc_acm 2>/dev/null || true
sudo modprobe usbserial 2>/dev/null || true
sudo modprobe ch341 2>/dev/null || true
for id in "2e88 4603" "1a86 5523" "1a86 7523" "1a86 55d3"; do
  echo "$id" | sudo tee /sys/bus/usb-serial/drivers/ch341/new_id >/dev/null 2>&1 || true
done
sleep 3
echo "=== lsusb ==="
lsusb 2>/dev/null || echo "lsusb not found: sudo apt install usbutils"
echo "=== serial devices ==="
shopt -s nullglob
serial_devs=(/dev/ttyUSB* /dev/ttyACM* /dev/ttyCH343USB*)
if ((${#serial_devs[@]} > 0)); then
  ls -la "${serial_devs[@]}"
  ls -la /dev/serial/by-id/* 2>/dev/null || true
  for dev in "${serial_devs[@]}"; do
    sudo chmod 666 "$dev" 2>/dev/null || true
  done
  if ! groups "$USER" | grep -q '\bdialout\b'; then
    sudo usermod -aG dialout "$USER" 2>/dev/null || true
    echo "提示: 已将 $USER 加入 dialout，重新登录 WSL 后免 sudo 访问"
  fi
  echo "OK: 达妙 USB-CAN 已挂载，串口: ${serial_devs[*]}"
  echo "注意: 达妙 USB-CAN 在 WSL 下通常为 /dev/ttyACM0（已写入 xacro）"
else
  echo "未发现 ttyUSB/ttyACM，请确认 usbipd 状态为 Attached"
fi
echo "=== dmesg usb ==="
dmesg 2>/dev/null | grep -iE 'usb|ch34|cdc|tty|serial|2e88' | tail -25 || true
