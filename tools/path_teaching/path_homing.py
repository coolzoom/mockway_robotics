#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright (c) 2025. Li Jianbin. All rights reserved.
# MIT License

"""Slow synchronized homing to joint zero with smooth start/stop."""

from __future__ import annotations

import time
from typing import Callable, Optional, Tuple

import numpy as np


def is_at_target(
    q: np.ndarray,
    target: np.ndarray,
    tolerance_rad: float,
    active_mask: np.ndarray | None = None,
) -> bool:
    diff = np.abs(q - target)
    if active_mask is not None:
        diff = diff[active_mask]
    if diff.size == 0:
        return True
    return bool(np.all(diff < tolerance_rad))


def compute_homing_duration(
    q_start: np.ndarray,
    target: np.ndarray,
    max_velocity: float,
    min_duration_s: float,
    active_mask: np.ndarray | None = None,
) -> float:
    """Duration so the farthest active joint does not exceed max_velocity (cosine ease)."""
    delta = np.abs(target - q_start)
    if active_mask is not None:
        delta = delta[active_mask]
    displacement = float(np.max(delta)) if delta.size else 0.0
    if displacement < 1e-9:
        return 0.0
    # Cosine ease peak velocity = pi/2 * displacement / T
    duration = (np.pi / 2.0) * displacement / max_velocity
    return float(max(min_duration_s, duration))


def cosine_ease_sample(
    q_start: np.ndarray,
    target: np.ndarray,
    t: float,
    duration: float,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Smooth homing profile: zero velocity at start and end.

    s(t) = 0.5 * (1 - cos(pi * t / T)),  q(t) = q0 + s * (q1 - q0)
    """
    if duration <= 1e-9:
        return target.copy(), np.zeros_like(target)

    t = float(np.clip(t, 0.0, duration))
    phase = np.pi * t / duration
    s = 0.5 * (1.0 - np.cos(phase))
    ds_dt = 0.5 * (np.pi / duration) * np.sin(phase)

    delta = target - q_start
    q = q_start + s * delta
    v = ds_dt * delta
    return q, v


def generate_homing_trajectory(
    q_start: np.ndarray,
    target: np.ndarray,
    output_dt: float,
    max_velocity: float,
    min_duration_s: float,
    active_mask: np.ndarray | None = None,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Return times, positions, velocities for slow homing."""
    duration = compute_homing_duration(
        q_start, target, max_velocity, min_duration_s, active_mask
    )
    if duration <= 0:
        return np.array([0.0]), target.reshape(1, -1), np.zeros((1, target.shape[0]))

    num_samples = max(2, int(np.ceil(duration / output_dt)) + 1)
    times = np.linspace(0.0, duration, num_samples)
    positions = np.zeros((num_samples, q_start.shape[0]))
    velocities = np.zeros_like(positions)

    for i, t in enumerate(times):
        positions[i], velocities[i] = cosine_ease_sample(q_start, target, t, duration)

    positions[-1] = target
    velocities[-1] = 0.0
    return times, positions, velocities


def run_homing_motion(
    q_start: np.ndarray,
    target: np.ndarray,
    send_command: Callable[[np.ndarray, np.ndarray], None],
    rate_hz: float,
    max_velocity: float,
    min_duration_s: float,
    tolerance_rad: float,
    should_stop: Callable[[], bool],
    progress_callback: Optional[Callable[[float, np.ndarray], None]] = None,
    settle_hold_s: float = 0.4,
    active_mask: np.ndarray | None = None,
) -> np.ndarray:
    """
    Execute slow homing. Returns final measured/command position.

    Raises RuntimeError if stopped early.
    """
    if is_at_target(q_start, target, tolerance_rad, active_mask):
        return q_start.copy()

    dt = 1.0 / rate_hz
    _, positions, velocities = generate_homing_trajectory(
        q_start, target, dt, max_velocity, min_duration_s, active_mask
    )

    for i in range(len(positions)):
        if should_stop():
            raise RuntimeError("归零已中断")

        loop_start = time.time()
        q_cmd = positions[i]
        v_cmd = velocities[i]
        send_command(q_cmd, v_cmd)

        if progress_callback:
            progress_callback(min(1.0, (i + 1) / len(positions)), q_cmd)

        elapsed = time.time() - loop_start
        sleep_time = dt - elapsed
        if sleep_time > 0:
            time.sleep(sleep_time)

    hold_steps = max(1, int(settle_hold_s / dt))
    for _ in range(hold_steps):
        if should_stop():
            raise RuntimeError("归零已中断")
        send_command(target, np.zeros_like(target))
        time.sleep(dt)

    return target.copy()
