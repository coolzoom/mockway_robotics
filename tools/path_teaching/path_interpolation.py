#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright (c) 2025. Li Jianbin. All rights reserved.
# MIT License

"""Joint-space path interpolation with linear segments and arc blending at corners."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

import numpy as np

PATH_FORMAT = "mockway_path_v1"


@dataclass
class PathPoint:
    t: float
    q: np.ndarray

    def to_dict(self) -> dict:
        return {"t": self.t, "q": self.q.tolist()}


def points_from_arrays(times: Sequence[float], positions: np.ndarray) -> List[PathPoint]:
    """Build path points from time vector and (N, num_joints) position matrix."""
    positions = np.asarray(positions, dtype=float)
    if positions.ndim != 2:
        raise ValueError("positions must be 2-D (num_points, num_joints)")
    if len(times) != positions.shape[0]:
        raise ValueError("times length must match number of position rows")
    return [PathPoint(float(t), positions[i].copy()) for i, t in enumerate(times)]


def save_path_file(
    path: Path,
    points: List[PathPoint],
    descriptions: Optional[Sequence[str]] = None,
    sample_interval_hint_s: Optional[float] = None,
) -> None:
    if not points:
        raise ValueError("cannot save empty path")
    num_joints = points[0].q.shape[0]
    if sample_interval_hint_s is None and len(points) > 1:
        intervals = [points[i + 1].t - points[i].t for i in range(len(points) - 1)]
        sample_interval_hint_s = float(np.median(intervals))

    payload = {
        "format": PATH_FORMAT,
        "num_joints": num_joints,
        "descriptions": list(descriptions) if descriptions else [],
        "sample_interval_hint_s": sample_interval_hint_s,
        "duration_s": points[-1].t - points[0].t,
        "num_points": len(points),
        "points": [p.to_dict() for p in points],
    }
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)


def load_path_file(path: Path) -> Tuple[List[PathPoint], dict]:
    with open(path, "r", encoding="utf-8") as f:
        payload = json.load(f)

    fmt = payload.get("format", "")
    if fmt != PATH_FORMAT:
        raise ValueError(f"unsupported path format: {fmt!r}")

    points = []
    for item in payload["points"]:
        points.append(PathPoint(float(item["t"]), np.asarray(item["q"], dtype=float)))

    if len(points) < 2:
        raise ValueError("path must contain at least 2 points")

    for i in range(1, len(points)):
        if points[i].t < points[i - 1].t:
            raise ValueError(f"path time not monotonic at index {i}")

    return points, payload


def _segment_velocity(q0: np.ndarray, q1: np.ndarray, dt: float) -> np.ndarray:
    if dt <= 1e-9:
        return np.zeros_like(q0)
    return (q1 - q0) / dt


def _velocity_angle_rad(v0: np.ndarray, v1: np.ndarray) -> float:
    n0 = np.linalg.norm(v0)
    n1 = np.linalg.norm(v1)
    if n0 < 1e-9 or n1 < 1e-9:
        return 0.0
    cos_angle = np.dot(v0, v1) / (n0 * n1)
    cos_angle = float(np.clip(cos_angle, -1.0, 1.0))
    return float(np.arccos(cos_angle))


def _linear_interp(q0: np.ndarray, q1: np.ndarray, alpha: float) -> np.ndarray:
    alpha = float(np.clip(alpha, 0.0, 1.0))
    return q0 + alpha * (q1 - q0)


def _arc_blend_interp(
    q_in: np.ndarray,
    q_corner: np.ndarray,
    q_out: np.ndarray,
    u: float,
) -> np.ndarray:
    """Quadratic Bezier through corner — smooth arc-like joint-space blend."""
    u = float(np.clip(u, 0.0, 1.0))
    return (1.0 - u) ** 2 * q_in + 2.0 * (1.0 - u) * u * q_corner + u**2 * q_out


@dataclass
class _BlendZone:
    index: int
    t_start: float
    t_end: float
    q_in: np.ndarray
    q_corner: np.ndarray
    q_out: np.ndarray


def build_blend_zones(
    points: List[PathPoint],
    corner_angle_deg: float = 12.0,
    blend_time_ratio: float = 0.35,
    min_blend_s: float = 0.02,
    max_blend_s: float = 0.15,
) -> List[_BlendZone]:
    """Detect corners and build arc blend zones at interior waypoints."""
    if len(points) < 3:
        return []

    threshold = np.deg2rad(corner_angle_deg)
    zones: List[_BlendZone] = []

    for i in range(1, len(points) - 1):
        dt_in = points[i].t - points[i - 1].t
        dt_out = points[i + 1].t - points[i].t
        if dt_in <= 1e-9 or dt_out <= 1e-9:
            continue

        v_in = _segment_velocity(points[i - 1].q, points[i].q, dt_in)
        v_out = _segment_velocity(points[i].q, points[i + 1].q, dt_out)
        angle = _velocity_angle_rad(v_in, v_out)
        if angle < threshold:
            continue

        blend_half = min(dt_in, dt_out) * blend_time_ratio
        blend_half = float(np.clip(blend_half, min_blend_s * 0.5, max_blend_s * 0.5))

        t_start = points[i].t - blend_half
        t_end = points[i].t + blend_half
        t_start = max(t_start, points[i - 1].t + 1e-6)
        t_end = min(t_end, points[i + 1].t - 1e-6)
        if t_end <= t_start:
            continue

        zones.append(
            _BlendZone(
                index=i,
                t_start=t_start,
                t_end=t_end,
                q_in=_linear_interp(points[i - 1].q, points[i].q, (t_start - points[i - 1].t) / dt_in),
                q_corner=points[i].q.copy(),
                q_out=_linear_interp(points[i].q, points[i + 1].q, (t_end - points[i].t) / dt_out),
            )
        )

    return zones


def interpolate_at_time(
    points: List[PathPoint],
    t: float,
    blend_zones: Optional[List[_BlendZone]] = None,
    corner_angle_deg: float = 12.0,
    blend_time_ratio: float = 0.35,
) -> np.ndarray:
    """
    Interpolate joint positions at time t.

    Uses linear interpolation along segments; at detected corners, applies
    arc (quadratic Bezier) blending for smooth motion through the waypoint.
    """
    if not points:
        raise ValueError("empty path")
    if t <= points[0].t:
        return points[0].q.copy()
    if t >= points[-1].t:
        return points[-1].q.copy()

    if blend_zones is None:
        blend_zones = build_blend_zones(
            points,
            corner_angle_deg=corner_angle_deg,
            blend_time_ratio=blend_time_ratio,
        )

    for zone in blend_zones:
        if zone.t_start <= t <= zone.t_end:
            u = (t - zone.t_start) / (zone.t_end - zone.t_start)
            return _arc_blend_interp(zone.q_in, zone.q_corner, zone.q_out, u)

    for i in range(len(points) - 1):
        t0, t1 = points[i].t, points[i + 1].t
        if t0 <= t <= t1:
            alpha = (t - t0) / (t1 - t0)
            return _linear_interp(points[i].q, points[i + 1].q, alpha)

    return points[-1].q.copy()


def interpolate_with_velocity(
    points: List[PathPoint],
    t: float,
    blend_zones: Optional[List[_BlendZone]] = None,
    vel_dt: float = 1e-3,
) -> Tuple[np.ndarray, np.ndarray]:
    """Return position and numerical joint velocity at time t."""
    q = interpolate_at_time(points, t, blend_zones=blend_zones)
    t_next = min(t + vel_dt, points[-1].t)
    if t_next <= t:
        return q, np.zeros_like(q)
    q_next = interpolate_at_time(points, t_next, blend_zones=blend_zones)
    return q, (q_next - q) / (t_next - t)


def generate_playback_samples(
    points: List[PathPoint],
    output_dt: float,
    speed_scale: float = 1.0,
    corner_angle_deg: float = 12.0,
    blend_time_ratio: float = 0.35,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Resample path for playback.

    Returns:
        times: (M,) playback clock
        positions: (M, num_joints)
    """
    if speed_scale <= 0:
        raise ValueError("speed_scale must be positive")

    t0 = points[0].t
    t1 = points[-1].t
    duration = (t1 - t0) / speed_scale
    if duration <= 0:
        q = points[0].q.reshape(1, -1)
        return np.array([0.0]), q

    blend_zones = build_blend_zones(
        points,
        corner_angle_deg=corner_angle_deg,
        blend_time_ratio=blend_time_ratio,
    )

    num_samples = max(2, int(np.ceil(duration / output_dt)) + 1)
    times = np.linspace(0.0, duration, num_samples)
    positions = np.zeros((num_samples, points[0].q.shape[0]))

    for i, t_play in enumerate(times):
        t_src = t0 + t_play * speed_scale
        positions[i] = interpolate_at_time(
            points,
            t_src,
            blend_zones=blend_zones,
        )

    return times, positions


def generate_playback_with_velocity(
    points: List[PathPoint],
    output_dt: float,
    speed_scale: float = 1.0,
    corner_angle_deg: float = 12.0,
    blend_time_ratio: float = 0.35,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Dense playback trajectory with joint velocities."""
    if speed_scale <= 0:
        raise ValueError("speed_scale must be positive")

    t0 = points[0].t
    t1 = points[-1].t
    duration = (t1 - t0) / speed_scale
    blend_zones = build_blend_zones(
        points,
        corner_angle_deg=corner_angle_deg,
        blend_time_ratio=blend_time_ratio,
    )

    num_samples = max(2, int(np.ceil(duration / output_dt)) + 1)
    times = np.linspace(0.0, duration, num_samples)
    positions = np.zeros((num_samples, points[0].q.shape[0]))
    velocities = np.zeros_like(positions)

    for i, t_play in enumerate(times):
        t_src = t0 + t_play * speed_scale
        q, v = interpolate_with_velocity(points, t_src, blend_zones=blend_zones)
        positions[i] = q
        velocities[i] = v / speed_scale

    return times, positions, velocities
