#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate annotated joint direction reference images for doc/组装指南.html."""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
IMG_DIR = ROOT / "doc" / "img"

# Joint callouts on cover.jpg (2000×1125) — approximate pixel centers
COVER_JOINTS = [
    {
        "id": "J1",
        "name": "基座旋转",
        "dir": "+1",
        "pos": (1210, 790),
        "arc_start": 200,
        "arc_end": 330,
        "arc_r": 72,
        "hint": "沿轴向上看 CCW→q+",
    },
    {
        "id": "J2",
        "name": "肩部",
        "dir": "+1",
        "pos": (980, 610),
        "arc_start": 250,
        "arc_end": 20,
        "arc_r": 65,
        "hint": "沿轴向外看 CCW→q+",
    },
    {
        "id": "J3",
        "name": "肘部",
        "dir": "-1",
        "pos": (760, 455),
        "arc_start": 230,
        "arc_end": 350,
        "arc_r": 58,
        "hint": "URDF q+ 与电机正转反向",
    },
    {
        "id": "J4",
        "name": "腕俯仰",
        "dir": "+1",
        "pos": (585, 340),
        "arc_start": 210,
        "arc_end": 330,
        "arc_r": 48,
        "hint": "沿轴向外看 CCW→q+",
    },
    {
        "id": "J5",
        "name": "腕滚转",
        "dir": "+1",
        "pos": (545, 295),
        "arc_start": 240,
        "arc_end": 20,
        "arc_r": 42,
        "hint": "沿轴向外看 CCW→q+",
    },
    {
        "id": "J6",
        "name": "腕偏航",
        "dir": "+1",
        "pos": (465, 235),
        "arc_start": 200,
        "arc_end": 320,
        "arc_r": 38,
        "hint": "沿轴向外看 CCW→q+",
    },
]


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in (
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/msyhbd.ttc",
        "C:/Windows/Fonts/simhei.ttf",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def draw_ccw_arc(
    draw: ImageDraw.ImageDraw,
    center: tuple[int, int],
    radius: int,
    start_deg: float,
    end_deg: float,
    color: str,
    width: int = 5,
) -> None:
    draw.arc(
        [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius],
        start=start_deg,
        end=end_deg,
        fill=color,
        width=width,
    )
    mid = math.radians((start_deg + end_deg) / 2)
    r = radius
    tip = (center[0] + r * math.cos(mid), center[1] + r * math.sin(mid))
    tangent = mid + math.pi / 2
    ah = 14
    left = (
        tip[0] - ah * math.cos(tangent - 0.45),
        tip[1] - ah * math.sin(tangent - 0.45),
    )
    right = (
        tip[0] - ah * math.cos(tangent + 0.45),
        tip[1] - ah * math.sin(tangent + 0.45),
    )
    draw.polygon([tip, left, right], fill=color)


def draw_axis_cross(draw: ImageDraw.ImageDraw, center: tuple[int, int], size: int = 10) -> None:
    x, y = center
    draw.line([(x - size, y), (x + size, y)], fill="#2056b8", width=3)
    draw.line([(x, y - size), (x, y + size)], fill="#2056b8", width=3)
    draw.ellipse([x - 4, y - 4, x + 4, y + 4], fill="#2056b8", outline="#ffffff", width=2)


def annotate_cover(src: Path, dst: Path) -> None:
    img = Image.open(src).convert("RGBA")
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    font_title = load_font(34)
    font_label = load_font(26)
    font_small = load_font(20)

    for joint in COVER_JOINTS:
        x, y = joint["pos"]
        dir_color = "#34a853" if joint["dir"] == "+1" else "#e37400"
        draw_ccw_arc(draw, (x, y), joint["arc_r"], joint["arc_start"], joint["arc_end"], "#34a853", 6)
        draw_axis_cross(draw, (x, y))
        badge = f"{joint['id']}  dir={joint['dir']}"
        tw = draw.textlength(badge, font=font_label)
        bx, by = x + 18, y - 52
        draw.rounded_rectangle(
            [bx - 8, by - 6, bx + tw + 8, by + 30],
            radius=8,
            fill=(32, 86, 184, 220),
        )
        draw.text((bx, by), badge, fill="#ffffff", font=font_label)
        draw.text((bx, by + 34), joint["name"], fill=(255, 255, 255, 240), font=font_small)

    # Legend box
    lx, ly = 60, 60
    lines = [
        "关节旋转方向标定图（Mockway 实物）",
        "绿弧：沿关节轴向外看，逆时针 CCW = q+ (rad+)",
        "蓝十字：关节旋转轴位置（示意）",
        "dir：软件 direction / ros2 dir 默认值",
    ]
    lh = 34
    box_h = lh * len(lines) + 24
    box_w = 920
    draw.rounded_rectangle(
        [lx, ly, lx + box_w, ly + box_h],
        radius=12,
        fill=(255, 255, 255, 230),
        outline="#2056b8",
        width=3,
    )
    for i, line in enumerate(lines):
        draw.text((lx + 16, ly + 12 + i * lh), line, fill="#1a2332", font=font_small if i else font_label)

    # Direction table
    tx, ty = 60, ly + box_h + 24
    draw.rounded_rectangle(
        [tx, ty, tx + 520, ty + 250],
        radius=12,
        fill=(255, 255, 255, 230),
        outline="#2056b8",
        width=2,
    )
    draw.text((tx + 16, ty + 10), "默认 direction / dir", fill="#2056b8", font=font_label)
    rows = [
        ("J1 基座", "+1"),
        ("J2 肩", "+1"),
        ("J3 肘", "-1  ← 唯一反向"),
        ("J4~J6 腕", "+1"),
    ]
    for i, (name, d) in enumerate(rows):
        yy = ty + 52 + i * 44
        color = "#e37400" if "反向" in d else "#1a2332"
        draw.text((tx + 24, yy), name, fill="#1a2332", font=font_small)
        draw.text((tx + 220, yy), d, fill=color, font=font_small)

    out = Image.alpha_composite(img, overlay).convert("RGB")
    out.save(dst, quality=92)
    print(f"Wrote {dst}")


def annotate_calibrate_guide(src: Path, dst: Path) -> None:
    """Generic CCW+ guide on joint close-up photo."""
    img = Image.open(src).convert("RGBA")
    w, h = img.size
    overlay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    font = load_font(22)
    font_b = load_font(28)

    cx, cy = w // 2, h // 2
    draw_ccw_arc(draw, (cx, cy), min(w, h) // 3, 210, 30, "#34a853", 7)
    draw_axis_cross(draw, (cx, cy), 14)

    lines = [
        "沿旋转轴正方向朝外看",
        "逆时针 CCW → q+ (rad+)",
        "顺时针 CW  → q- (rad-)",
    ]
    draw.rounded_rectangle([20, 20, w - 20, 130], radius=10, fill=(255, 255, 255, 235), outline="#2056b8", width=2)
    for i, line in enumerate(lines):
        draw.text((36, 32 + i * 32), line, fill="#1a2332", font=font if i else font_b)

    draw.text((36, h - 52), "direction=1：motor_gui 正转且 q 增大", fill="#2056b8", font=font)
    draw.text((36, h - 28), "direction=-1：正转时 q 减小（如 J3）", fill="#e37400", font=font)

    out = Image.alpha_composite(img, overlay).convert("RGB")
    out.save(dst, quality=92)
    print(f"Wrote {dst}")


def create_schematic(dst: Path) -> None:
    """Side-view schematic with all joints labeled."""
    w, h = 1200, 720
    img = Image.new("RGB", (w, h), "#f6f8fb")
    draw = ImageDraw.Draw(img)
    font = load_font(24)
    font_s = load_font(20)
    font_b = load_font(30)

    draw.text((40, 24), "Mockway 关节旋转正方向示意（侧视简图）", fill="#2056b8", font=font_b)

    # Stick arm
    base = (220, 560)
    pts = [base, (220, 460), (360, 320), (520, 220), (620, 180), (700, 160), (760, 150)]
    for a, b in zip(pts, pts[1:]):
        draw.line([a, b], fill="#3a7bd5", width=14)
    draw.rounded_rectangle([160, 560, 280, 620], radius=8, fill="#64748b")

    joint_meta = [
        ("J1", "+1", pts[0], "轴↑ 俯视 CCW→+"),
        ("J2", "+1", pts[1], "轴⊗  CCW→+"),
        ("J3", "-1", pts[2], "轴⊗  dir=-1"),
        ("J4", "+1", pts[3], "轴⊗  CCW→+"),
        ("J5", "+1", pts[4], "轴⊙  CCW→+"),
        ("J6", "+1", pts[5], "轴⊗  CCW→+"),
    ]
    for jid, dval, center, hint in joint_meta:
        draw.ellipse(
            [center[0] - 18, center[1] - 18, center[0] + 18, center[1] + 18],
            fill="#2056b8",
            outline="#ffffff",
            width=3,
        )
        draw_ccw_arc(draw, center, 42, 220, 320, "#34a853", 5)
        label = f"{jid} dir={dval}"
        color = "#e37400" if dval == "-1" else "#1a2332"
        draw.text((center[0] + 26, center[1] - 38), label, fill=color, font=font)
        draw.text((center[0] + 26, center[1] - 10), hint, fill="#5c6b7a", font=font_s)

    draw.rounded_rectangle([780, 120, 1160, 620], radius=12, fill="#ffffff", outline="#dde4ee", width=2)
    help_lines = [
        "如何标定 direction：",
        "1. motor_gui 使能该关节",
        "2. 点击「正转」",
        "3. 对照绿弧方向是否 q+",
        "4. 读数增大 → direction=1",
        "   读数减小 → direction=-1",
        "",
        "须同步修改：",
        "dynamics_test.yaml",
        "ros2_control.xacro",
    ]
    for i, line in enumerate(help_lines):
        draw.text((810, 150 + i * 38), line, fill="#1a2332", font=font_s)

    img.save(dst, quality=92)
    print(f"Wrote {dst}")


def main() -> None:
    IMG_DIR.mkdir(parents=True, exist_ok=True)
    cover = IMG_DIR / "cover.jpg"
    cal = IMG_DIR / "calibrate_joint.jpg"
    if cover.exists():
        annotate_cover(cover, IMG_DIR / "joint_direction_overview.png")
    else:
        print(f"Skip cover annotation: {cover} missing")
    if cal.exists():
        annotate_calibrate_guide(cal, IMG_DIR / "joint_direction_ccw_guide.png")
    else:
        print(f"Skip calibrate guide: {cal} missing")
    create_schematic(IMG_DIR / "joint_direction_schematic.png")


if __name__ == "__main__":
    main()
