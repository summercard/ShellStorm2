#!/usr/bin/env python3
"""生成 Boss房02 的**一体地面碰撞**（平台 + 东西两条走道 + 楼梯 + 高位平台）。

## 为什么需要它（2026-10-13 业主现场反馈）

业主原话：「boss房的楼梯的阻挡 从下往上走因为台阶高度会卡人，还有两边走道到台子也会卡人，
把台阶，平台、两个走道用一个一体的地面的阻挡模型，更加不容易卡人。阻挡模型要一个网格，整块的。」

`scripts/probe_boss_room02_walk_surface.gd` 实测（房间局部 y，"coll" = 现存碰撞面，"vis" = 可见网格面）：

| 段 | 现存碰撞 | 可见面 | 症状 |
|---|---|---|---|
| 平台（deck_armor） | `0.0000` 平 | ≈ `0` | 正常 |
| 东西走道（bridge_deck） | `-0.1815` 平 | ≈ `-0.0315` | 到平台处 **0.18 m 竖面** ⇒ 卡人 |
| 楼梯（stair_flight） | 每 5 m 一段 0.216 坡，**段间跳 0.12 m** | 一条直线坡 `y = 0.24·z + 2.505` | 每 5 m 一道 **0.12 m 竖面** ⇒ 卡人 |
| 梯脚（z=-10） | 从 0 跳到 `0.1205` | `0.105` | 进梯第一脚 0.12 m 竖面 |
| 高台（stair_landing） | `11.965` 平 | ≈ `11.965` | 梯顶 12.105 → 11.965 的 **0.14 m 竖面** |

根因两条：
  1. 走道的碰撞代理只取了「桥面底盘」子件（0.26 m 高、顶 `-0.1815`），**没到格栅可见面**；
  2. 楼梯的碰撞是「每 5 m 一段的 convex 坡」，每段自身只升 1.08 m 但摆放间距 1.2 m
     ⇒ 段与段之间必然留 0.12 m 落差。可见坡面是 0.24 斜率（0.12 踏高 / 0.5 m 踏面 × 100 踏），
     碰撞的 0.216 斜率本身就填不平它。

## 做法

把「地面」收归**房间**自持：一个 `ArrayMesh` 级别的单一三角面网格（一个 `ConcavePolygonShape3D`，
一个 `CollisionShape3D`，一个 `StaticBody3D`），顶面处处连续、**没有一处竖直面**：

| 区 | x | z | y |
|---|---|---|---|
| 平台 ×3 片（让出梯脚过渡） | `[-12.5,12.5]` | `[-35,-10]` | `0` |
| 梯脚过渡 | `[-2.5,2.5]` | `[-10.44,-10]` | `0 → 0.105` |
| 楼梯坡 | `[-2.5,2.5]` | `[-10,40]` | `0.24·z + 2.505`（== 可见坡面） |
| 梯顶过渡 | `[-2.5,2.5]` | `[40,41]` | `12.105 → 11.965` |
| 高位平台 | `[-2.5,2.5]` | `[41,50]` | `11.965` |
| 西/东走道 | `[-40,-12.5]` / `[12.5,40]` | `[-25,-20]` | `0`（**抬到与平台齐平**） |

三处取舍（明说，不是顺手）：
  · **走道抬到 0**：可见格栅面是 `-0.0315`，抬到 0 后脚下只浮 3 cm（看不出来），
    换来与平台**零台阶**。若改成追随可见面，就必须在接缝造一个 0.18 m 竖向台阶 —— 正是病根。
  · **楼梯坡对齐可见面**（不是对齐旧碰撞）：脚下与画面对齐，全程 50 m 无一竖面。
  · **梯脚 0 → 0.105 过渡**：可见坡在 `z=-10` 处已是 0.105，直接接平台会留 0.105 m 竖面；
    在平台侧花 0.44 m 把它抹平（浮空 ≤ 10.5 cm，比「陷进甲板」轻得多）。

## 用法

    python scripts/build_boss_room02_walk_surface.py            # 只生成，不落盘
    python scripts/build_boss_room02_walk_surface.py --write    # 写文件

产物：`assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/
boss_room_02_walk_surface.tscn`（由房间 TSCN 实例化）。

## 🔴 配套改动（缺一不可）

本网格是**唯一**地面。走面组件自身的承重形状必须停用，否则旧竖面仍在（且会出现两套碰撞）：
`deck_armor_5m` / `deck_emblem_5m` / `bridge_deck_5m` / `bridge_threshold` 的承重盒，
`stair_flight_5m` 的 convex 坡（**保留两条扶手**），`stair_landing_5m` 的底板（**保留栏杆柱/扶手**）。
停用是 `CollisionShape3D.disabled = true`（节点仍在 ⇒ `metadata/collision_shape_count` 不变，
`verify_boss_room02_runtime.gd` 的「碰撞形状数 == spec.collisions」照旧通过）。

生成本文件的真源同链条：`scripts/prepare_boss_room02_import.py`（标 `room_owned_walk_surface`）
→ `scripts/build_boss_room02_runtime.gd`（落 `disabled` 与本场景节点）。
手改后**必须同步那两处**，否则重跑导入会把手改冲掉。
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = (
    ROOT
    / "assets/art/environments/tower_zones/expedition/runtime/room_instances"
    / "expedition_01/boss_room_02_walk_surface.tscn"
)

# ── 实测基准（scripts/probe_boss_room02_walk_surface.gd 的读数）────────────────
PLATFORM_TOP_Y = 0.0
BRIDGE_TOP_Y = 0.0
STAIR_SLOPE = 0.24
STAIR_INTERCEPT = 2.505          # 可见坡面 y = 0.24·z + 2.505
STAIR_FOOT_Z = -10.0
STAIR_HEAD_Z = 40.0
STAIR_FOOT_Y = STAIR_SLOPE * STAIR_FOOT_Z + STAIR_INTERCEPT   # 0.105
STAIR_HEAD_Y = STAIR_SLOPE * STAIR_HEAD_Z + STAIR_INTERCEPT   # 12.105
LANDING_TOP_Y = 11.965
HEAD_BLEND_Z = 41.0
FOOT_BLEND_Z = -10.44
# 走面足迹
PLATFORM_X = (-12.5, 12.5)
PLATFORM_Z = (-35.0, -10.0)
STAIR_X = (-2.5, 2.5)
LANDING_Z = (HEAD_BLEND_Z, 50.0)
BRIDGE_Z = (-25.0, -20.0)
BRIDGE_X_WEST = (-40.0, -12.5)
BRIDGE_X_EAST = (12.5, 40.0)
# 网格细分：平台/走道/高台按 5 m 分格（与组件摆放网格一致，便于对照），坡面按 5 m 分 10 段
CELL = 5.0

UP = (0.0, 1.0, 0.0)


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _blend(z: float) -> float:
    """梯脚 0 → 0.105 的线性过渡。"""
    t = (z - FOOT_BLEND_Z) / (STAIR_FOOT_Z - FOOT_BLEND_Z)
    return _lerp(PLATFORM_TOP_Y, STAIR_FOOT_Y, t)


def _head_blend(z: float) -> float:
    """梯顶 12.105 → 11.965 的线性过渡。"""
    t = (z - STAIR_HEAD_Z) / (HEAD_BLEND_Z - STAIR_HEAD_Z)
    return _lerp(STAIR_HEAD_Y, LANDING_TOP_Y, t)


def _height(x: float, z: float) -> float:
    if STAIR_X[0] <= x <= STAIR_X[1]:
        if STAIR_FOOT_Z <= z <= STAIR_HEAD_Z:
            return STAIR_SLOPE * z + STAIR_INTERCEPT
        if STAIR_HEAD_Z <= z <= HEAD_BLEND_Z:
            return _head_blend(z)
        if HEAD_BLEND_Z <= z <= LANDING_Z[1]:
            return LANDING_TOP_Y
        if FOOT_BLEND_Z <= z <= STAIR_FOOT_Z:
            return _blend(z)
    if BRIDGE_Z[0] <= z <= BRIDGE_Z[1] and (
        BRIDGE_X_WEST[0] <= x <= BRIDGE_X_WEST[1]
        or BRIDGE_X_EAST[0] <= x <= BRIDGE_X_EAST[1]
    ):
        return BRIDGE_TOP_Y
    if PLATFORM_X[0] <= x <= PLATFORM_X[1] and PLATFORM_Z[0] <= z <= PLATFORM_Z[1]:
        return PLATFORM_TOP_Y
    raise ValueError(f"({x}, {z}) 不在任何走面区上")


def _cells(lo: float, hi: float) -> list[tuple[float, float]]:
    """把一个区间按 CELL 切成若干段；不整除时最后一段收口。"""
    out: list[tuple[float, float]] = []
    cur = lo
    while cur < hi - 1e-9:
        nxt = min(cur + CELL, hi)
        out.append((cur, nxt))
        cur = nxt
    return out


def _regions() -> list[tuple[float, float, float, float]]:
    """顶面矩形集合（x0, x1, z0, z1）。互不重叠、共享边即相接。"""
    px0, px1 = PLATFORM_X
    pz0, pz1 = PLATFORM_Z
    sx0, sx1 = STAIR_X
    return [
        # 平台被楼梯通道切成三片，最后一行让给梯脚过渡（避免与过渡面重叠）
        (px0, sx0, pz0, pz1),
        (sx0, sx1, pz0, FOOT_BLEND_Z),
        (sx1, px1, pz0, pz1),
        (sx0, sx1, FOOT_BLEND_Z, STAIR_FOOT_Z),     # 梯脚过渡
        (sx0, sx1, STAIR_FOOT_Z, STAIR_HEAD_Z),     # 楼梯坡
        (sx0, sx1, STAIR_HEAD_Z, HEAD_BLEND_Z),     # 梯顶过渡
        (sx0, sx1, HEAD_BLEND_Z, LANDING_Z[1]),     # 高位平台
        (BRIDGE_X_WEST[0], BRIDGE_X_WEST[1], BRIDGE_Z[0], BRIDGE_Z[1]),
        (BRIDGE_X_EAST[0], BRIDGE_X_EAST[1], BRIDGE_Z[0], BRIDGE_Z[1]),
    ]


def _sub(a, b):
    return (b[0] - a[0], b[1] - a[1], b[2] - a[2])


def _cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def build_faces() -> list[tuple[tuple[float, float, float], ...]]:
    faces: list[tuple[tuple[float, float, float], ...]] = []
    for x0, x1, z0, z1 in _regions():
        for cx0, cx1 in _cells(x0, x1):
            for cz0, cz1 in _cells(z0, z1):
                corners = [
                    (cx0, _height(cx0, cz0), cz0),
                    (cx0, _height(cx0, cz1), cz1),
                    (cx1, _height(cx1, cz1), cz1),
                    (cx1, _height(cx1, cz0), cz0),
                ]
                # 拆两个三角；法线强制朝上（Godot 正面绕序敏感，这里按几何反推绕序）
                for tri in ((corners[0], corners[1], corners[2]),
                            (corners[0], corners[2], corners[3])):
                    n = _cross(_sub(tri[0], tri[1]), _sub(tri[0], tri[2]))
                    if n[1] < 0.0:
                        tri = (tri[0], tri[2], tri[1])
                        n = _cross(_sub(tri[0], tri[1]), _sub(tri[0], tri[2]))
                    assert n[1] > 0.0, f"三角法线未朝上: {tri}"
                    faces.append(tri)
    return faces


def _num(v: float) -> str:
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("", "-0") else s


def scene_text(faces) -> str:
    floats: list[str] = []
    for tri in faces:
        for vertex in tri:
            floats.extend(_num(c) for c in vertex)
    body = ", ".join(floats)
    # 按 12 个分量（4 个顶点）折行，纯为可读；数据本身与折行无关。
    parts = body.split(", ")
    lines = []
    for i in range(0, len(parts), 12):
        lines.append(", ".join(parts[i:i + 12]))
    data = ",\n".join(lines)
    tri_count = len(faces)
    ys = [v[1] for tri in faces for v in tri]
    header = f"""\
[gd_scene load_steps=2 format=3]

; Boss房02 一体地面碰撞 —— 平台 + 东西走道 + 楼梯 + 高位平台，**一个网格**。
; 由 `scripts/build_boss_room02_walk_surface.py` 生成，禁止手改；改参数请改脚本后重跑。
; 实测基准见该脚本头注释（probe: scripts/probe_boss_room02_walk_surface.gd）。
; 顶面处处连续、无竖直面：平台/走道 y=0；楼梯 y=0.24z+2.505（对齐可见坡面）；
; 梯脚 0.44 m 过渡 0→0.105；梯顶 1 m 过渡 12.105→11.965；高台 11.965。
; 三角面 {tri_count}，y 范围 {_num(min(ys))} .. {_num(max(ys))}。

[sub_resource type="ConcavePolygonShape3D" id="ConcavePolygonShape3D_bossroom02_walk"]
backface_collision = true
data = PackedVector3Array({data})

[node name="WalkSurfaceCollision" type="Node3D"]
metadata/schema = "shellstorm2.expedition.walk_surface_collision.v001"
metadata/room_id = "boss_room_02"
metadata/generated_by = "scripts/build_boss_room02_walk_surface.py"
metadata/surface_owner = "room"
metadata/covers = "platform;bridge_west;bridge_east;stair;landing"
metadata/triangle_count = {tri_count}
metadata/contiguous_top_surface = true
metadata/no_vertical_face = true
metadata/measured_by = "scripts/probe_boss_room02_walk_surface.gd"

[node name="BossRoom02WalkSurface" type="StaticBody3D" parent="."]
collision_layer = 1
collision_mask = 0

[node name="Shape_00" type="CollisionShape3D" parent="BossRoom02WalkSurface"]
shape = SubResource("ConcavePolygonShape3D_bossroom02_walk")
"""
    return header


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help="写盘（默认只打印摘要）")
    args = parser.parse_args()
    faces = build_faces()
    text = scene_text(faces)
    ys = [v[1] for tri in faces for v in tri]
    print(f"WALK_SURFACE faces={len(faces)} y=[{min(ys):.4f}, {max(ys):.4f}] "
          f"chars={len(text)}")
    if args.write:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(text, encoding="utf8", newline="\r\n")
        print("WROTE", OUT.relative_to(ROOT).as_posix())


if __name__ == "__main__":
    main()
