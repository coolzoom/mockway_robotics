#!/usr/bin/env python3
"""根据 mockway_description.urdf 生成 macOS 用的"包围盒碰撞" URDF。

背景：RoboStack(macOS/arm64, Eigen 5) 的 MoveIt+FCL 在用网格(STL)构建碰撞 BVH 时
会段错误(move_group SIGSEGV)。用 primitive(box) 碰撞可绕开该上游 bug。
本脚本仅替换 <collision> 里的 <mesh> 为按 STL 顶点算出的包围盒 <box>，
visual 网格保持不变；输出 mockway_description.primitive_collision.urdf。

Linux/WSL 不使用本文件（仍用原始网格碰撞），互不影响。

用法:
    python3 tools/gen_macos_collision_urdf.py [--repo <repo_root>]
"""
import argparse
import os
import re
import struct
import sys


def parse_stl_aabb(path):
    """返回 (minx,miny,minz,maxx,maxy,maxz)（米）。支持二进制/ASCII STL。"""
    with open(path, "rb") as f:
        data = f.read()
    verts = []
    head = data[:5].lower()
    is_ascii = head == b"solid" and b"facet" in data[:2048].lower()
    if is_ascii:
        for line in data.decode("ascii", "ignore").splitlines():
            s = line.strip().split()
            if len(s) >= 4 and s[0].lower() == "vertex":
                verts.append((float(s[1]), float(s[2]), float(s[3])))
    else:
        if len(data) < 84:
            raise ValueError(f"STL 太小: {path}")
        n = struct.unpack("<I", data[80:84])[0]
        off = 84
        for _ in range(n):
            base = off + 12  # 跳过法向量
            for v in range(3):
                x, y, z = struct.unpack("<fff", data[base + v * 12: base + v * 12 + 12])
                verts.append((x, y, z))
            off += 50
    if not verts:
        raise ValueError(f"STL 无顶点: {path}")
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    return (min(xs), min(ys), min(zs), max(xs), max(ys), max(zs))


def fmt(v):
    return f"{v:.6g}"


def make_box_collision(indent, mesh_basename, meshes_dir, orig_origin):
    stl = os.path.join(meshes_dir, mesh_basename)
    minx, miny, minz, maxx, maxy, maxz = parse_stl_aabb(stl)
    # 包围盒尺寸（设最小厚度，避免退化为 0）
    sx = max(maxx - minx, 0.005)
    sy = max(maxy - miny, 0.005)
    sz = max(maxz - minz, 0.005)
    # 盒心（link 坐标系）
    cx = (maxx + minx) / 2.0
    cy = (maxy + miny) / 2.0
    cz = (maxz + minz) / 2.0
    # 叠加原 collision <origin> 的平移（本模型均为 0，rpy 旋转忽略，足够用）
    ox, oy, oz, orr, opp, oyy = orig_origin
    cx += ox
    cy += oy
    cz += oz
    return (
        f"{indent}<collision>\n"
        f"{indent}  <origin xyz=\"{fmt(cx)} {fmt(cy)} {fmt(cz)}\" rpy=\"{fmt(orr)} {fmt(opp)} {fmt(oyy)}\"/>\n"
        f"{indent}  <geometry>\n"
        f"{indent}    <box size=\"{fmt(sx)} {fmt(sy)} {fmt(sz)}\"/>\n"
        f"{indent}  </geometry>\n"
        f"{indent}</collision>"
    )


def parse_origin(block):
    m = re.search(r"<origin\b[^>]*\bxyz=\"([^\"]*)\"[^>]*\brpy=\"([^\"]*)\"", block)
    if not m:
        return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    xyz = [float(x) for x in m.group(1).split()]
    rpy = [float(x) for x in m.group(2).split()]
    while len(xyz) < 3:
        xyz.append(0.0)
    while len(rpy) < 3:
        rpy.append(0.0)
    return (xyz[0], xyz[1], xyz[2], rpy[0], rpy[1], rpy[2])


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    default_repo = os.path.abspath(os.path.join(here, ".."))
    ap.add_argument("--repo", default=default_repo, help="仓库根目录")
    args = ap.parse_args()

    desc = os.path.join(args.repo, "mockway_description")
    src = os.path.join(desc, "urdf", "mockway_description.urdf")
    out = os.path.join(desc, "urdf", "mockway_description.primitive_collision.urdf")
    meshes_dir = os.path.join(desc, "meshes")

    if not os.path.isfile(src):
        print(f"[错误] 找不到原始 URDF: {src}", file=sys.stderr)
        return 1

    text = open(src).read()

    count = {"n": 0}

    def repl(m):
        block = m.group(0)
        indent = m.group(1)
        mesh = re.search(r"<mesh\b[^>]*filename=\"[^\"]*/([^\"/]+\.stl)\"", block)
        if not mesh:
            return block  # 该 collision 不是网格，保持原样
        origin = parse_origin(block)
        count["n"] += 1
        return make_box_collision(indent, mesh.group(1), meshes_dir, origin)

    new_text = re.sub(r"([ \t]*)<collision>.*?</collision>", repl, text, flags=re.S)

    header = (
        "<!-- 自动生成(请勿手改): tools/gen_macos_collision_urdf.py\n"
        "     仅供 macOS(RoboStack) 使用 box 碰撞，规避 FCL 网格 BVH 在 Eigen5 下的崩溃。\n"
        "     Linux/WSL 仍使用 mockway_description.urdf 的网格碰撞。 -->\n"
    )
    new_text = re.sub(r"(<robot\b[^>]*>)", r"\1\n" + header, new_text, count=1)

    with open(out, "w") as f:
        f.write(new_text)
    print(f"[ok] 已生成 {out}（替换 {count['n']} 处网格碰撞为包围盒）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
