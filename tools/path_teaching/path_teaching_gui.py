#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright (c) 2025. Li Jianbin. All rights reserved.
# MIT License

"""
Mockway 路径示教界面

- 同时连接所有关节（复用 dynamics_test 重力补偿）
- 重力补偿模式下手动拖动示教并录制路径
- 保存/加载路径文件（时间 + 关节位置）
- 回放时对相邻点位进行直线与圆弧（拐角混合）插补
"""

from __future__ import annotations

import sys
import threading
import time
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

import numpy as np
import serial.tools.list_ports
import yaml

# dynamics_test / motor_gui 模块路径
_TOOLS_DIR = Path(__file__).resolve().parent.parent
_THIS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(_THIS_DIR))
sys.path.insert(0, str(_TOOLS_DIR / "motor_gui"))
sys.path.insert(0, str(_TOOLS_DIR / "dynamics_test"))

from config_loader import load_config  # noqa: E402
from path_interpolation import (  # noqa: E402
    PathPoint,
    generate_playback_with_velocity,
    load_path_file,
    save_path_file,
)
from path_homing import is_at_target, run_homing_motion  # noqa: E402
from realtime_torque_compensation import RealtimeTorqueController  # noqa: E402

DEFAULT_CONFIG = Path(__file__).parent / "path_teaching.yaml"


def load_playback_settings(config_path: Path) -> dict:
    with open(config_path, "r", encoding="utf-8") as f:
        raw = yaml.safe_load(f) or {}
    playback = raw.get("playback", {})
    recording = raw.get("recording", {})
    homing = raw.get("homing", {})
    target = homing.get("target", [0.0] * 6)
    return {
        "playback_rate": int(playback.get("rate", 200)),
        "playback_kp": float(playback.get("kp", 40.0)),
        "playback_kd": float(playback.get("kd", 1.0)),
        "speed_scale": float(playback.get("speed_scale", 1.0)),
        "corner_angle_deg": float(playback.get("corner_angle_deg", 12.0)),
        "blend_time_ratio": float(playback.get("blend_time_ratio", 0.35)),
        "record_min_interval_s": float(recording.get("min_interval_s", 0.005)),
        "homing_enabled": bool(homing.get("enabled", True)),
        "homing_rate": int(homing.get("rate", 200)),
        "homing_kp": float(homing.get("kp", 25.0)),
        "homing_kd": float(homing.get("kd", 1.2)),
        "homing_max_velocity": float(homing.get("max_velocity", 0.20)),
        "homing_min_duration_s": float(homing.get("min_duration_s", 4.0)),
        "homing_tolerance_rad": float(homing.get("position_tolerance_rad", 0.01)),
        "homing_settle_hold_s": float(homing.get("settle_hold_s", 0.5)),
        "homing_target": np.asarray(target, dtype=float),
    }


class PathTeachingController:
    """Wraps RealtimeTorqueController with recording and playback."""

    def __init__(self, config_path: Path):
        self.config_path = Path(config_path)
        self.settings = load_playback_settings(self.config_path)
        self.config = load_config(str(self.config_path))
        self.rt: RealtimeTorqueController | None = None

        self._record_lock = threading.Lock()
        self._recorded_points: list[PathPoint] = []
        self._recording = False
        self._record_thread: threading.Thread | None = None
        self._record_start_time = 0.0
        self._last_record_time = 0.0

        self._playback_thread: threading.Thread | None = None
        self._playback_running = False
        self._playback_stop = threading.Event()
        self._playback_finished_callback = None
        self._loaded_path: list[PathPoint] | None = None

        self._homing_thread: threading.Thread | None = None
        self._homing_running = False
        self._homing_stop = threading.Event()
        self._homing_progress_callback = None
        self._homing_finished_callback = None
        self._homing_then_gravity = False
        self._homing_joint_indices: list[int] | None = None

        self.connected = False
        self.gravity_active = False

    @property
    def num_joints(self) -> int:
        return len(self.config.motors)

    def setup_and_connect(self) -> None:
        if self.connected:
            return
        self.rt = RealtimeTorqueController(self.config)
        self.rt.setup()
        self.rt.enable_motors()
        self.connected = True

    def disconnect(self) -> None:
        self.stop_homing()
        self.stop_playback()
        self.stop_recording()
        self.stop_gravity()
        if self.rt:
            self.rt.shutdown()
            self.rt = None
        self.connected = False

    def _ensure_idle_for_motor_ops(self) -> None:
        if self.gravity_active:
            raise RuntimeError("请先停止重力补偿")
        if self._homing_running:
            raise RuntimeError("归零进行中")
        if self._playback_running:
            raise RuntimeError("播放进行中")
        if self._recording:
            raise RuntimeError("录制进行中")

    def get_motor_enabled_states(self) -> list[bool]:
        if not self.rt:
            return []
        return [motor.is_enabled() for motor in self.rt.motors]

    def enable_motor(self, index: int) -> None:
        if not self.rt or not self.connected:
            raise RuntimeError("未连接")
        self._ensure_idle_for_motor_ops()
        if index < 0 or index >= self.num_joints:
            raise IndexError(f"关节索引越界: {index}")
        self.rt.motors[index].enable()
        time.sleep(0.05)

    def disable_motor(self, index: int) -> None:
        if not self.rt or not self.connected:
            raise RuntimeError("未连接")
        self._ensure_idle_for_motor_ops()
        if index < 0 or index >= self.num_joints:
            raise IndexError(f"关节索引越界: {index}")
        self.rt.motors[index].disable()
        time.sleep(0.05)

    def enable_all_motors(self) -> None:
        if not self.rt or not self.connected:
            raise RuntimeError("未连接")
        self._ensure_idle_for_motor_ops()
        for motor in self.rt.motors:
            motor.enable()
            time.sleep(0.05)

    def disable_all_motors(self) -> None:
        if not self.rt or not self.connected:
            raise RuntimeError("未连接")
        self._ensure_idle_for_motor_ops()
        for motor in self.rt.motors:
            motor.disable()
            time.sleep(0.05)

    def start_gravity(self) -> None:
        if not self.rt or not self.connected:
            raise RuntimeError("未连接")
        if self.gravity_active:
            return
        self.rt.compensation_enabled[:] = True
        self.rt.hold_inactive_joints = False
        self.rt.start_control(mode="gravity")
        self.gravity_active = True

    def _get_homing_target(self) -> np.ndarray:
        target = self.settings.get("homing_target")
        if target is None:
            return np.zeros(self.num_joints)
        target = np.asarray(target, dtype=float)
        if target.shape[0] != self.num_joints:
            raise ValueError(
                f"homing.target 长度 {target.shape[0]} 与关节数 {self.num_joints} 不一致"
            )
        return target

    def _send_position_command(self, q_cmd: np.ndarray, v_cmd: np.ndarray, kp: float, kd: float) -> None:
        motors = self.rt.motors
        directions = self.rt.motor_directions
        for j, motor in enumerate(motors):
            if not motor.is_enabled():
                continue
            motor.control_mit(
                p_des=q_cmd[j] * directions[j],
                v_des=v_cmd[j] * directions[j],
                kp=kp,
                kd=kd,
                t_ff=0.0,
            )

    def _build_homing_plan(
        self,
        joint_indices: list[int] | None,
    ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        q_start, _ = self.rt.get_current_state()
        full_target = self._get_homing_target()
        if joint_indices is None:
            active_mask = np.ones(self.num_joints, dtype=bool)
            return q_start, full_target.copy(), active_mask

        active_mask = np.zeros(self.num_joints, dtype=bool)
        for idx in joint_indices:
            if idx < 0 or idx >= self.num_joints:
                raise IndexError(f"关节索引越界: {idx}")
            active_mask[idx] = True

        target = full_target.copy()
        for i in range(self.num_joints):
            if not active_mask[i]:
                target[i] = q_start[i]
        return q_start, target, active_mask

    def slow_home(
        self,
        joint_indices: list[int] | None = None,
        progress_callback=None,
    ) -> None:
        """Slowly move selected joints (or all) toward zero."""
        if not self.rt or not self.connected:
            raise RuntimeError("未连接")
        if self.gravity_active:
            raise RuntimeError("请先停止重力补偿再归零")

        q_start, target, active_mask = self._build_homing_plan(joint_indices)
        tol = self.settings["homing_tolerance_rad"]

        if is_at_target(q_start, target, tol, active_mask):
            return

        kp = self.settings["homing_kp"]
        kd = self.settings["homing_kd"]

        def send(q_cmd, v_cmd):
            self._send_position_command(q_cmd, v_cmd, kp, kd)

        run_homing_motion(
            q_start=q_start,
            target=target,
            send_command=send,
            rate_hz=self.settings["homing_rate"],
            max_velocity=self.settings["homing_max_velocity"],
            min_duration_s=self.settings["homing_min_duration_s"],
            tolerance_rad=tol,
            should_stop=self._homing_stop.is_set,
            progress_callback=progress_callback,
            settle_hold_s=self.settings["homing_settle_hold_s"],
            active_mask=active_mask,
        )

        q_final, _ = self.rt.get_current_state()
        if not is_at_target(q_final, target, tol * 2, active_mask):
            raise RuntimeError(
                "归零未到位，请检查障碍或调低 homing.max_velocity / 增大 min_duration_s"
            )

    def slow_home_to_zero(self, progress_callback=None) -> None:
        """Slowly move all joints to zero before teaching."""
        self.slow_home(joint_indices=None, progress_callback=progress_callback)

    def set_homing_progress_callback(self, callback) -> None:
        self._homing_progress_callback = callback

    def set_homing_finished_callback(self, callback) -> None:
        self._homing_finished_callback = callback

    def start_gravity_with_homing(self) -> None:
        """Home slowly (if needed) then enable gravity compensation."""
        self.start_homing(joint_indices=None, then_gravity=True)

    def start_homing(
        self,
        joint_indices: list[int] | None = None,
        then_gravity: bool = False,
    ) -> None:
        if not self.rt or not self.connected:
            raise RuntimeError("未连接")
        if self._homing_running:
            return
        if then_gravity and self.gravity_active:
            return
        if self.gravity_active and not then_gravity:
            raise RuntimeError("请先停止重力补偿再归零")

        self._homing_then_gravity = then_gravity
        self._homing_joint_indices = joint_indices

        if then_gravity and not self.settings["homing_enabled"]:
            need_homing = False
        else:
            q_start, target, active_mask = self._build_homing_plan(joint_indices)
            need_homing = not is_at_target(
                q_start,
                target,
                self.settings["homing_tolerance_rad"],
                active_mask,
            )

        if not need_homing:
            if then_gravity:
                self.start_gravity()
            if self._homing_finished_callback:
                self._homing_finished_callback(None)
            return

        self._homing_stop.clear()
        self._homing_running = True
        self._homing_thread = threading.Thread(
            target=self._homing_worker_loop,
            daemon=True,
        )
        self._homing_thread.start()

    def stop_homing(self) -> None:
        if not self._homing_running:
            return
        self._homing_stop.set()
        if self._homing_thread and self._homing_thread.is_alive():
            self._homing_thread.join(timeout=10.0)
        self._homing_running = False
        self._homing_thread = None

    def _homing_worker_loop(self) -> None:
        error = None
        try:
            self.slow_home(
                joint_indices=self._homing_joint_indices,
                progress_callback=self._homing_progress_callback,
            )
            if self._homing_then_gravity:
                self.start_gravity()
        except Exception as exc:
            error = exc
        finally:
            self._homing_running = False
            if self._homing_finished_callback:
                self._homing_finished_callback(error)

    def stop_gravity(self) -> None:
        if self.rt and self.gravity_active:
            self.rt.stop_control()
            self.gravity_active = False

    def start_recording(self) -> None:
        if not self.gravity_active:
            raise RuntimeError("请先启动重力补偿")
        if self._recording:
            return
        with self._record_lock:
            self._recorded_points = []
        self._record_start_time = time.time()
        self._last_record_time = 0.0
        self._recording = True
        self._record_thread = threading.Thread(target=self._record_loop, daemon=True)
        self._record_thread.start()

    def stop_recording(self) -> None:
        self._recording = False
        if self._record_thread and self._record_thread.is_alive():
            self._record_thread.join(timeout=1.0)
        self._record_thread = None

    def _record_loop(self) -> None:
        min_dt = self.settings["record_min_interval_s"]
        while self._recording and self.rt:
            loop_start = time.time()
            q, _ = self.rt.get_current_state()
            t = loop_start - self._record_start_time
            with self._record_lock:
                should_append = (
                    not self._recorded_points
                    or (t - self._last_record_time) >= min_dt
                )
                if should_append:
                    self._recorded_points.append(PathPoint(t, q.copy()))
                    self._last_record_time = t
            elapsed = time.time() - loop_start
            sleep_time = min_dt - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    def get_recorded_points(self) -> list[PathPoint]:
        with self._record_lock:
            return list(self._recorded_points)

    def get_record_count(self) -> int:
        with self._record_lock:
            return len(self._recorded_points)

    def clear_recorded_points(self) -> None:
        with self._record_lock:
            self._recorded_points = []

    def save_recorded_path(self, file_path: Path) -> int:
        points = self.get_recorded_points()
        if len(points) < 2:
            raise ValueError("至少需要 2 个路径点才能保存")
        descriptions = [m.description for m in self.config.motors]
        save_path_file(
            file_path,
            points,
            descriptions=descriptions,
            sample_interval_hint_s=self.settings["record_min_interval_s"],
        )
        return len(points)

    def load_path(self, file_path: Path) -> int:
        points, _ = load_path_file(file_path)
        if points[0].q.shape[0] != self.num_joints:
            raise ValueError(
                f"路径关节数 {points[0].q.shape[0]} 与当前配置 {self.num_joints} 不一致"
            )
        self._loaded_path = points
        return len(points)

    def get_loaded_path(self) -> list[PathPoint] | None:
        return self._loaded_path

    def set_speed_scale(self, scale: float) -> None:
        if scale <= 0:
            raise ValueError("速度倍率必须大于 0")
        self.settings["speed_scale"] = scale

    def set_playback_finished_callback(self, callback) -> None:
        self._playback_finished_callback = callback

    def start_playback(self, points: list[PathPoint] | None = None) -> None:
        if not self.rt or not self.connected:
            raise RuntimeError("未连接")
        if self._playback_running:
            return
        if self._recording:
            raise RuntimeError("录制中无法播放")

        path = points or self._loaded_path
        if not path or len(path) < 2:
            raise ValueError("没有可播放的路径（至少 2 个点）")

        self.stop_gravity()
        self._playback_stop.clear()
        self._playback_running = True
        self._playback_thread = threading.Thread(
            target=self._playback_loop,
            args=(path,),
            daemon=True,
        )
        self._playback_thread.start()

    def stop_playback(self) -> None:
        if not self._playback_running:
            return
        self._playback_stop.set()
        if self._playback_thread and self._playback_thread.is_alive():
            self._playback_thread.join(timeout=3.0)
        self._playback_running = False
        self._playback_thread = None

    def _playback_loop(self, points: list[PathPoint]) -> None:
        rate = self.settings["playback_rate"]
        dt = 1.0 / rate
        kp = self.settings["playback_kp"]
        kd = self.settings["playback_kd"]
        speed_scale = self.settings["speed_scale"]

        _, positions, velocities = generate_playback_with_velocity(
            points,
            output_dt=dt,
            speed_scale=speed_scale,
            corner_angle_deg=self.settings["corner_angle_deg"],
            blend_time_ratio=self.settings["blend_time_ratio"],
        )

        motors = self.rt.motors
        directions = self.rt.motor_directions

        for i in range(len(positions)):
            if self._playback_stop.is_set():
                break

            loop_start = time.time()
            q_cmd = positions[i]
            v_cmd = velocities[i]

            for j, motor in enumerate(motors):
                p_motor = q_cmd[j] * directions[j]
                v_motor = v_cmd[j] * directions[j]
                motor.control_mit(
                    p_des=p_motor,
                    v_des=v_motor,
                    kp=kp,
                    kd=kd,
                    t_ff=0.0,
                )

            elapsed = time.time() - loop_start
            sleep_time = dt - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

        self._playback_running = False
        if self._playback_finished_callback:
            self._playback_finished_callback()

    def get_joint_state(self) -> tuple[np.ndarray, np.ndarray]:
        if not self.rt:
            return np.zeros(self.num_joints), np.zeros(self.num_joints)
        return self.rt.get_current_state()


class PathTeachingGUI:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("Mockway 路径示教 — 重力补偿拖动录制 / 插补回放")
        self.root.geometry("1100x820")

        self.config_path = tk.StringVar(value=str(DEFAULT_CONFIG))
        self.port_var = tk.StringVar()
        self.speed_scale_var = tk.StringVar(value="1.0")
        self.status_var = tk.StringVar(value="未连接")
        self.record_info_var = tk.StringVar(value="路径点: 0")
        self.mode_var = tk.StringVar(value="模式: 空闲")

        self.homing_progress_var = tk.StringVar(value="")

        self.joint_checkbox_vars: list[tk.BooleanVar] = []
        self.joint_checkbuttons: list[ttk.Checkbutton] = []

        self.controller: PathTeachingController | None = None
        self._ui_running = True
        self._status_thread = threading.Thread(target=self._status_loop, daemon=True)
        self._status_thread.start()

        self._build_ui()
        self.refresh_ports()

    def _build_ui(self) -> None:
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(4, weight=1)

        conn = ttk.LabelFrame(self.root, text="连接配置", padding=10)
        conn.grid(row=0, column=0, sticky="ew", padx=10, pady=5)
        conn.columnconfigure(1, weight=1)

        ttk.Label(conn, text="COM口:").grid(row=0, column=0, sticky="w")
        self.port_combo = ttk.Combobox(conn, textvariable=self.port_var, state="readonly", width=40)
        self.port_combo.grid(row=0, column=1, padx=5, sticky="ew")
        ttk.Button(conn, text="刷新", command=self.refresh_ports, width=8).grid(row=0, column=2, padx=5)

        ttk.Label(conn, text="配置文件:").grid(row=1, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(conn, textvariable=self.config_path, width=50).grid(
            row=1, column=1, padx=5, pady=(8, 0), sticky="ew"
        )
        ttk.Button(conn, text="浏览...", command=self._browse_config).grid(
            row=1, column=2, padx=5, pady=(8, 0)
        )

        btn_row = ttk.Frame(conn)
        btn_row.grid(row=2, column=0, columnspan=3, pady=(10, 0), sticky="w")
        self.connect_btn = ttk.Button(btn_row, text="连接所有轴", command=self.toggle_connect, width=14)
        self.connect_btn.pack(side="left", padx=(0, 8))
        self.gravity_btn = ttk.Button(
            btn_row, text="启动重力补偿", command=self.toggle_gravity, state="disabled", width=14
        )
        self.gravity_btn.pack(side="left", padx=8)
        ttk.Label(btn_row, textvariable=self.homing_progress_var, foreground="orange").pack(
            side="left", padx=12
        )

        motor = ttk.LabelFrame(self.root, text="电机使能与归零", padding=10)
        motor.grid(row=1, column=0, sticky="ew", padx=10, pady=5)

        global_row = ttk.Frame(motor)
        global_row.pack(fill="x", pady=(0, 8))
        self.enable_all_btn = ttk.Button(
            global_row, text="全部使能", command=self.enable_all_motors, state="disabled", width=12
        )
        self.enable_all_btn.pack(side="left", padx=5)
        self.disable_all_btn = ttk.Button(
            global_row, text="全部失能", command=self.disable_all_motors, state="disabled", width=12
        )
        self.disable_all_btn.pack(side="left", padx=5)
        self.home_all_btn = ttk.Button(
            global_row, text="全部归零", command=self.home_all_joints, state="disabled", width=12
        )
        self.home_all_btn.pack(side="left", padx=5)

        single_row = ttk.Frame(motor)
        single_row.pack(fill="x")
        ttk.Label(single_row, text="选择轴:").pack(side="left", padx=(5, 2))
        self.joint_checkbox_frame = ttk.Frame(single_row)
        self.joint_checkbox_frame.pack(side="left", padx=5)
        self.enable_joint_btn = ttk.Button(
            single_row, text="使能", command=self.enable_selected_joints, state="disabled", width=8
        )
        self.enable_joint_btn.pack(side="left", padx=(12, 5))
        self.disable_joint_btn = ttk.Button(
            single_row, text="失能", command=self.disable_selected_joints, state="disabled", width=8
        )
        self.disable_joint_btn.pack(side="left", padx=5)
        self.home_joint_btn = ttk.Button(
            single_row, text="归零", command=self.home_selected_joints, state="disabled", width=8
        )
        self.home_joint_btn.pack(side="left", padx=5)

        teach = ttk.LabelFrame(self.root, text="路径录制（启动重力补偿前将自动缓慢归零）", padding=10)
        teach.grid(row=2, column=0, sticky="ew", padx=10, pady=5)

        self.record_start_btn = ttk.Button(
            teach, text="录制开始", command=self.start_record, state="disabled", width=12
        )
        self.record_start_btn.grid(row=0, column=0, padx=5)
        self.record_stop_btn = ttk.Button(
            teach, text="录制结束", command=self.stop_record, state="disabled", width=12
        )
        self.record_stop_btn.grid(row=0, column=1, padx=5)
        self.save_btn = ttk.Button(
            teach, text="保存路径文件", command=self.save_path, state="disabled", width=14
        )
        self.save_btn.grid(row=0, column=2, padx=5)
        self.load_btn = ttk.Button(
            teach, text="加载路径文件", command=self.load_path, state="disabled", width=14
        )
        self.load_btn.grid(row=0, column=3, padx=5)

        ttk.Label(teach, textvariable=self.record_info_var).grid(row=0, column=4, padx=20)

        play = ttk.LabelFrame(self.root, text="路径回放（直线 + 拐角圆弧插补）", padding=10)
        play.grid(row=3, column=0, sticky="ew", padx=10, pady=5)

        ttk.Label(play, text="速度倍率:").grid(row=0, column=0, sticky="w")
        ttk.Entry(play, textvariable=self.speed_scale_var, width=8).grid(row=0, column=1, padx=5)
        self.play_btn = ttk.Button(play, text="播放路径", command=self.play_path, state="disabled", width=12)
        self.play_btn.grid(row=0, column=2, padx=10)
        self.stop_play_btn = ttk.Button(
            play, text="停止播放", command=self.stop_playback, state="disabled", width=12
        )
        self.stop_play_btn.grid(row=0, column=3, padx=5)

        status_bar = ttk.Frame(self.root, padding=(10, 0))
        status_bar.grid(row=5, column=0, sticky="ew")
        ttk.Label(status_bar, textvariable=self.status_var, foreground="blue").pack(side="left")
        ttk.Label(status_bar, textvariable=self.mode_var).pack(side="right")

        joint_frame = ttk.LabelFrame(self.root, text="关节状态 (rad)", padding=10)
        joint_frame.grid(row=4, column=0, sticky="nsew", padx=10, pady=5)
        joint_frame.columnconfigure(0, weight=1)
        joint_frame.rowconfigure(0, weight=1)

        columns = ("joint", "position", "velocity", "enabled")
        self.joint_tree = ttk.Treeview(joint_frame, columns=columns, show="headings", height=8)
        self.joint_tree.heading("joint", text="关节")
        self.joint_tree.heading("position", text="位置 (rad)")
        self.joint_tree.heading("velocity", text="速度 (rad/s)")
        self.joint_tree.heading("enabled", text="使能")
        self.joint_tree.column("joint", width=120)
        self.joint_tree.column("position", width=140)
        self.joint_tree.column("velocity", width=140)
        self.joint_tree.column("enabled", width=70)
        self.joint_tree.grid(row=0, column=0, sticky="nsew")
        scroll = ttk.Scrollbar(joint_frame, orient="vertical", command=self.joint_tree.yview)
        scroll.grid(row=0, column=1, sticky="ns")
        self.joint_tree.configure(yscrollcommand=scroll.set)

        self._joint_row_ids: list[str] = []

    def refresh_ports(self) -> None:
        ports = []
        for port in serial.tools.list_ports.comports():
            if port.description:
                ports.append(f"{port.device} - {port.description}")
            else:
                ports.append(port.device)
        self.port_combo["values"] = ports
        if ports and not self.port_var.get():
            self.port_var.set(ports[0])

    def _browse_config(self) -> None:
        path = filedialog.askopenfilename(
            title="选择配置文件",
            filetypes=[("YAML", "*.yaml"), ("YAML", "*.yml"), ("All", "*.*")],
            initialdir=str(Path(__file__).parent),
        )
        if path:
            self.config_path.set(path)

    def _parse_port(self) -> str:
        port_str = self.port_var.get()
        if " - " in port_str:
            return port_str.split(" - ")[0]
        return port_str

    def _apply_port_to_config(self) -> Path:
        config_path = Path(self.config_path.get())
        if not config_path.exists():
            raise FileNotFoundError(f"配置文件不存在: {config_path}")

        with open(config_path, "r", encoding="utf-8") as f:
            raw = yaml.safe_load(f) or {}
        raw.setdefault("can", {})["port"] = self._parse_port()

        runtime_config = Path(__file__).parent / ".runtime_path_teaching.yaml"
        with open(runtime_config, "w", encoding="utf-8") as f:
            yaml.dump(raw, f, allow_unicode=True, default_flow_style=False)
        return runtime_config

    def toggle_connect(self) -> None:
        if self.controller and self.controller.connected:
            try:
                self.controller.disconnect()
            except Exception as exc:
                messagebox.showerror("错误", f"断开失败: {exc}")
            self.controller = None
            self._set_connected_ui(False)
            self.status_var.set("已断开")
            return

        try:
            runtime_config = self._apply_port_to_config()
            self.controller = PathTeachingController(runtime_config)
            self.controller.set_playback_finished_callback(
                lambda: self.root.after(0, self._on_playback_finished)
            )
            self.controller.set_homing_progress_callback(
                lambda progress, _q: self.root.after(
                    0, self._on_homing_progress, progress
                )
            )
            self.controller.set_homing_finished_callback(
                lambda err: self.root.after(0, self._on_homing_finished, err)
            )
            self.controller.setup_and_connect()
            self._init_joint_rows()
            self._set_connected_ui(True)
            self.status_var.set(f"已连接 {self.controller.num_joints} 个关节")
            messagebox.showinfo("成功", f"已连接 {self.controller.num_joints} 个关节")
        except Exception as exc:
            self.controller = None
            messagebox.showerror("连接失败", str(exc))

    def _init_joint_rows(self) -> None:
        for row_id in self._joint_row_ids:
            self.joint_tree.delete(row_id)
        self._joint_row_ids = []
        if not self.controller:
            return
        for i, motor_cfg in enumerate(self.controller.config.motors):
            name = motor_cfg.description or f"Joint {i + 1}"
            row_id = self.joint_tree.insert("", "end", values=(name, "--", "--", "--"))
            self._joint_row_ids.append(row_id)

        self._rebuild_joint_checkboxes()

    def _rebuild_joint_checkboxes(self) -> None:
        for cb in self.joint_checkbuttons:
            cb.destroy()
        self.joint_checkbox_vars.clear()
        self.joint_checkbuttons.clear()

        if not self.controller:
            return

        for i in range(self.controller.num_joints):
            var = tk.BooleanVar(value=False)
            cb = ttk.Checkbutton(
                self.joint_checkbox_frame,
                text=f"J{i + 1}",
                variable=var,
                state="disabled",
            )
            cb.pack(side="left", padx=4)
            self.joint_checkbox_vars.append(var)
            self.joint_checkbuttons.append(cb)

    def _motor_control_widgets(self) -> tuple:
        return (
            self.enable_all_btn,
            self.disable_all_btn,
            self.home_all_btn,
            self.enable_joint_btn,
            self.disable_joint_btn,
            self.home_joint_btn,
            *self.joint_checkbuttons,
        )

    def _get_checked_joint_indices(self) -> list[int]:
        indices = [i for i, var in enumerate(self.joint_checkbox_vars) if var.get()]
        if not indices:
            raise ValueError("请至少勾选一个关节")
        return indices

    def _format_joint_labels(self, indices: list[int]) -> str:
        return ", ".join(f"J{i + 1}" for i in indices)

    def enable_all_motors(self) -> None:
        if not self.controller:
            return
        try:
            self.controller.enable_all_motors()
            self.status_var.set("已全部使能")
        except Exception as exc:
            messagebox.showerror("错误", str(exc))

    def disable_all_motors(self) -> None:
        if not self.controller:
            return
        try:
            self.controller.disable_all_motors()
            self.status_var.set("已全部失能")
        except Exception as exc:
            messagebox.showerror("错误", str(exc))

    def enable_selected_joints(self) -> None:
        if not self.controller:
            return
        try:
            indices = self._get_checked_joint_indices()
            for idx in indices:
                self.controller.enable_motor(idx)
            self.status_var.set(f"{self._format_joint_labels(indices)} 已使能")
        except Exception as exc:
            messagebox.showerror("错误", str(exc))

    def disable_selected_joints(self) -> None:
        if not self.controller:
            return
        try:
            indices = self._get_checked_joint_indices()
            for idx in indices:
                self.controller.disable_motor(idx)
            self.status_var.set(f"{self._format_joint_labels(indices)} 已失能")
        except Exception as exc:
            messagebox.showerror("错误", str(exc))

    def home_all_joints(self) -> None:
        self._start_manual_homing(joint_indices=None, label="全部关节")

    def home_selected_joints(self) -> None:
        if not self.controller:
            return
        try:
            indices = self._get_checked_joint_indices()
            label = self._format_joint_labels(indices)
            self._start_manual_homing(joint_indices=indices, label=label)
        except Exception as exc:
            messagebox.showerror("错误", str(exc))

    def _start_manual_homing(self, joint_indices: list[int] | None, label: str) -> None:
        if not self.controller:
            return
        if self.controller._homing_running:
            self.controller.stop_homing()
            return
        try:
            self._begin_homing_ui(f"{label}缓慢归零中...")
            self.controller.start_homing(joint_indices=joint_indices, then_gravity=False)
        except Exception as exc:
            self._end_homing_ui()
            messagebox.showerror("错误", str(exc))

    def cancel_homing(self) -> None:
        if self.controller and self.controller._homing_running:
            self.controller.stop_homing()

    def _begin_homing_ui(self, status_text: str) -> None:
        self._set_busy_ui(True)
        self.mode_var.set("模式: 缓慢归零中...")
        self.homing_progress_var.set(status_text)
        self.home_all_btn.config(text="中断归零", command=self.cancel_homing)
        self.gravity_btn.config(text="中断归零", command=self.cancel_homing)

    def _end_homing_ui(self) -> None:
        self.home_all_btn.config(text="全部归零", command=self.home_all_joints)
        if self.controller and self.controller.gravity_active:
            self.gravity_btn.config(text="停止重力补偿", command=self.toggle_gravity)
        else:
            self.gravity_btn.config(text="启动重力补偿", command=self.toggle_gravity)
        self.homing_progress_var.set("")
        self._set_busy_ui(False)

    def _set_connected_ui(self, connected: bool) -> None:
        state = "normal" if connected else "disabled"
        self.connect_btn.config(text="断开连接" if connected else "连接所有轴")
        self.gravity_btn.config(state=state)
        self.load_btn.config(state=state)
        self.play_btn.config(state=state)
        self.stop_play_btn.config(state=state if connected else "disabled")
        self.record_start_btn.config(state="disabled")
        self.record_stop_btn.config(state="disabled")
        self.save_btn.config(state="disabled")
        for widget in self._motor_control_widgets():
            widget.config(state=state)
        if connected:
            self.gravity_btn.config(text="启动重力补偿", command=self.toggle_gravity)
            self.home_all_btn.config(text="全部归零", command=self.home_all_joints)

    def _set_busy_ui(self, busy: bool) -> None:
        """Disable most controls during homing; interrupt buttons stay enabled."""
        if busy:
            for widget in (
                self.connect_btn,
                self.load_btn,
                self.play_btn,
                self.stop_play_btn,
                self.record_start_btn,
                self.record_stop_btn,
                self.save_btn,
                self.enable_all_btn,
                self.disable_all_btn,
                self.enable_joint_btn,
                self.disable_joint_btn,
                self.home_joint_btn,
                *self.joint_checkbuttons,
            ):
                widget.config(state="disabled")
            self.home_all_btn.config(state="normal")
            self.gravity_btn.config(state="normal")
            return

        connected = bool(self.controller and self.controller.connected)
        conn_state = "normal" if connected else "disabled"
        self.connect_btn.config(state=conn_state, text="断开连接" if connected else "连接所有轴")
        self.gravity_btn.config(state=conn_state)
        self.load_btn.config(state=conn_state)
        self.play_btn.config(state=conn_state)
        self.stop_play_btn.config(state=conn_state)
        self.record_start_btn.config(state="disabled")
        self.record_stop_btn.config(state="disabled")
        self.save_btn.config(state="disabled")
        for widget in self._motor_control_widgets():
            widget.config(state=conn_state)
        if connected:
            self.gravity_btn.config(
                text="停止重力补偿" if self.controller.gravity_active else "启动重力补偿"
            )

    def toggle_gravity(self) -> None:
        if not self.controller:
            return
        try:
            if self.controller._homing_running:
                self.controller.stop_homing()
                return

            if self.controller.gravity_active:
                self.controller.stop_gravity()
                self.gravity_btn.config(text="启动重力补偿")
                self.record_start_btn.config(state="disabled")
                self.record_stop_btn.config(state="disabled")
                self.homing_progress_var.set("")
                self.mode_var.set("模式: 空闲")
            else:
                if self.controller._playback_running:
                    messagebox.showwarning("提示", "请先停止播放")
                    return
                self._begin_homing_ui("全部关节缓慢归零中...")
                self.controller.start_gravity_with_homing()
        except Exception as exc:
            self._end_homing_ui()
            messagebox.showerror("错误", str(exc))

    def _on_homing_progress(self, progress: float) -> None:
        pct = int(progress * 100)
        self.homing_progress_var.set(f"归零进度: {pct}%")
        self.status_var.set(f"正在缓慢归零至零位 ({pct}%)，请勿靠近机械臂")

    def _on_homing_finished(self, error: Exception | None) -> None:
        then_gravity = bool(self.controller and self.controller._homing_then_gravity)
        self._end_homing_ui()

        if error:
            self.mode_var.set("模式: 空闲")
            self.status_var.set("归零失败" if "中断" not in str(error) else "归零已中断")
            if "中断" not in str(error):
                messagebox.showerror("归零失败", str(error))
            return

        if then_gravity:
            self.gravity_btn.config(text="停止重力补偿", command=self.toggle_gravity)
            self.record_start_btn.config(state="normal")
            self.record_stop_btn.config(state="disabled")
            self.mode_var.set("模式: 重力补偿")
            self.status_var.set("已归零，重力补偿已启动，可开始拖动示教")
        else:
            self.mode_var.set("模式: 空闲")
            self.status_var.set("归零完成")

    def start_record(self) -> None:
        if not self.controller:
            return
        try:
            self.controller.start_recording()
            self.record_start_btn.config(state="disabled")
            self.record_stop_btn.config(state="normal")
            self.play_btn.config(state="disabled")
            self.mode_var.set("模式: 录制中")
        except Exception as exc:
            messagebox.showerror("错误", str(exc))

    def stop_record(self) -> None:
        if not self.controller:
            return
        self.controller.stop_recording()
        count = self.controller.get_record_count()
        self.record_start_btn.config(state="normal")
        self.record_stop_btn.config(state="disabled")
        self.play_btn.config(state="normal")
        self.save_btn.config(state="normal" if count >= 2 else "disabled")
        self.record_info_var.set(f"路径点: {count}")
        self.mode_var.set("模式: 重力补偿")
        if count < 2:
            messagebox.showwarning("提示", "录制点过少，请重新录制（至少 2 个点）")

    def save_path(self) -> None:
        if not self.controller:
            return
        file_path = filedialog.asksaveasfilename(
            title="保存路径文件",
            defaultextension=".json",
            filetypes=[("JSON path", "*.json"), ("All", "*.*")],
            initialdir=str(Path(__file__).parent),
        )
        if not file_path:
            return
        try:
            count = self.controller.save_recorded_path(Path(file_path))
            self.record_info_var.set(f"路径点: {count} (已保存)")
            messagebox.showinfo("成功", f"已保存 {count} 个路径点到\n{file_path}")
        except Exception as exc:
            messagebox.showerror("保存失败", str(exc))

    def load_path(self) -> None:
        if not self.controller:
            return
        file_path = filedialog.askopenfilename(
            title="加载路径文件",
            filetypes=[("JSON path", "*.json"), ("All", "*.*")],
            initialdir=str(Path(__file__).parent),
        )
        if not file_path:
            return
        try:
            count = self.controller.load_path(Path(file_path))
            self.record_info_var.set(f"已加载路径点: {count}")
            self.play_btn.config(state="normal")
            messagebox.showinfo("成功", f"已加载 {count} 个路径点")
        except Exception as exc:
            messagebox.showerror("加载失败", str(exc))

    def play_path(self) -> None:
        if not self.controller:
            return
        try:
            scale = float(self.speed_scale_var.get())
            self.controller.set_speed_scale(scale)
        except ValueError:
            messagebox.showerror("错误", "速度倍率无效")
            return

        points = self.controller.get_loaded_path()
        if not points:
            points = self.controller.get_recorded_points()
        if len(points) < 2:
            messagebox.showwarning("提示", "请先录制或加载路径")
            return

        try:
            self.controller.start_playback(points)
            self.play_btn.config(state="disabled")
            self.stop_play_btn.config(state="normal")
            self.gravity_btn.config(state="disabled")
            self.record_start_btn.config(state="disabled")
            self.mode_var.set("模式: 播放中")
        except Exception as exc:
            messagebox.showerror("播放失败", str(exc))

    def stop_playback(self) -> None:
        if not self.controller:
            return
        self.controller.stop_playback()
        self._on_playback_finished()

    def _on_playback_finished(self) -> None:
        if not self.controller:
            return
        self.play_btn.config(state="normal")
        self.stop_play_btn.config(state="normal")
        self.gravity_btn.config(state="normal")
        if self.controller.gravity_active:
            self.record_start_btn.config(state="normal")
        self.mode_var.set("模式: 重力补偿" if self.controller.gravity_active else "模式: 空闲")

    def _status_loop(self) -> None:
        while self._ui_running:
            if self.controller and self.controller.connected:
                try:
                    q, v = self.controller.get_joint_state()
                    enabled = self.controller.get_motor_enabled_states()
                    count = self.controller.get_record_count()
                    self.root.after(0, self._update_joint_display, q, v, enabled, count)
                except Exception:
                    pass
            time.sleep(0.1)

    def _update_joint_display(
        self,
        q: np.ndarray,
        v: np.ndarray,
        enabled: list[bool],
        count: int,
    ) -> None:
        for i, row_id in enumerate(self._joint_row_ids):
            if i >= len(q):
                break
            vals = self.joint_tree.item(row_id, "values")
            name = vals[0] if vals else f"J{i + 1}"
            en_text = "是" if (i < len(enabled) and enabled[i]) else "否"
            self.joint_tree.item(
                row_id,
                values=(name, f"{q[i]:.4f}", f"{v[i]:.4f}", en_text),
            )
        if self.controller and self.controller._recording:
            self.record_info_var.set(f"路径点: {count} (录制中...)")
        elif count > 0 and "已加载" not in self.record_info_var.get():
            self.record_info_var.set(f"路径点: {count}")

    def on_close(self) -> None:
        self._ui_running = False
        if self.controller:
            try:
                self.controller.stop_homing()
                self.controller.disconnect()
            except Exception:
                pass
        self.root.destroy()


def main() -> None:
    root = tk.Tk()
    app = PathTeachingGUI(root)
    root.protocol("WM_DELETE_WINDOW", app.on_close)
    root.mainloop()


if __name__ == "__main__":
    main()
