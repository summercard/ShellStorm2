#!/usr/bin/env python3
"""全关卡门位体检:对每个房间的每个门槽,找出侵入「门洞净空带」的碰撞盒。

净空带定义(房间局部): 沿墙 ±1.1m(门宽 2.2 的一半) x 高 y[0,2.5] x 垂直墙 ±1.5m。
判定在**房间局部**做 —— 远征房除 start 外根无旋转,且局部坐标直接取自 tscn,
可绕开 floor_00.json 中心不可靠的问题。

用法: python _scratch/scan_all_doors.py
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scan_door_clearance as sdc  # noqa: E402

ROOM_DIR = os.path.join(
    sdc.REPO, "assets", "art", "environments", "tower_zones", "expedition",
    "runtime", "room_instances", "expedition_01",
)

# 已有的门墙/门楣件不算侵入(它们本来就是门的一部分,净空约束由门件自身保证)
WALL_KIND_HINTS = ("wall_door", "door_lintel", "DOORWALL", "build_door")


def room_bounds(text):
    xs, zs = [], []
    for name, ntype, parent, rid, b in sdc.node_blocks(text):
        if not rid:
            continue
        rows, origin = sdc.local_transform(b)
        xs.append(origin[0])
        zs.append(origin[2])
    return min(xs), max(xs), min(zs), max(zs)


def scan_room(path, half_wall=1.5):
    text = open(path, encoding="utf-8").read()
    ext = {}
    for m in re.finditer(r'\[ext_resource type="PackedScene" path="([^"]+)" id="([^"]+)"\]', text):
        ext[m.group(2)] = m.group(1)

    offsets = dict(re.findall(r"metadata/snapshot_tower_wall_door_offset_(\w+) = ([-\d.]+)", text))
    if not offsets:
        return []
    xmin, xmax, zmin, zmax = room_bounds(text)

    findings = []
    for side, off_s in offsets.items():
        off = float(off_s)
        if side in ("east", "west"):
            wall = xmax if side == "east" else xmin
            win = (wall - half_wall, 0.0, off - 1.10, wall + half_wall, 2.50, off + 1.10)
        else:
            wall = zmin if side == "north" else zmax
            win = (off - 1.10, 0.0, wall - half_wall, off + 1.10, 2.50, wall + half_wall)
        for name, ntype, parent, rid, b in sdc.node_blocks(text):
            if not rid:
                continue
            rows, origin = sdc.local_transform(b)
            prefab = sdc.res_to_path(ext[rid])
            slug = os.path.basename(os.path.dirname(prefab))
            if any(h in slug or h in name for h in WALL_KIND_HINTS):
                continue
            for sr, so, size in sdc.collect_shapes(prefab):
                lo = [1e9] * 3
                hi = [-1e9] * 3
                for sx in (-0.5, 0.5):
                    for sy in (-0.5, 0.5):
                        for sz in (-0.5, 0.5):
                            p = sdc.xform(rows, origin, sdc.xform(sr, so, [sx * size[0], sy * size[1], sz * size[2]]))
                            for i in range(3):
                                lo[i] = min(lo[i], p[i])
                                hi[i] = max(hi[i], p[i])
                if (hi[0] > win[0] and lo[0] < win[3] and hi[1] > win[1] and lo[1] < win[4]
                        and hi[2] > win[2] and lo[2] < win[5]):
                    findings.append((side, off, name, slug, lo, hi))
    return findings


def main():
    total = 0
    for path in sorted(glob.glob(os.path.join(ROOM_DIR, "f00_*_static_layout.tscn"))):
        rid = os.path.basename(path).replace("f00_", "").replace("_static_layout.tscn", "")
        hits = scan_room(path)
        if not hits:
            continue
        print("### %s" % rid)
        for side, off, name, slug, lo, hi in hits:
            total += 1
            print("   [%s@%.1f] %-38s slug=%-30s 局部AABB[%.2f..%.2f, %.2f..%.2f, %.2f..%.2f]"
                  % (side, off, name, slug, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    print("\n侵入门洞净空的碰撞盒合计 %d 个" % total)


if __name__ == "__main__":
    main()
