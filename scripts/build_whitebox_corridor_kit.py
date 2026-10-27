#!/usr/bin/env python3
"""远征03 通道（走廊）白盒套件。

## 挺进地牢的技术方案

走廊**不是**一种特殊的连接件，它就是一间**很窄的房间**：

> `CONNECTOR` = "long, thin rooms, so picking one with a sensible orientation is vital"

而且它在生成顺序里排在最后 —— 别的房间都摆完之后，用寻路造出来填缝。
这意味着走廊与房间**同契约**：同样的 5m 格、同样的门洞、同样的端口。
所以本脚本产出的 `cr_*` 与 `rt_*` 用同一套坐标约定与同一份门契约，只有宽深不同。

## 产出

| 壳 | 净宽 | 净长 | 端口 | 用在哪 |
|---|---:|---:|---:|---|
| `cr_straight_05` | 5 | 5 | 2 | 相邻两房中间隔一格 |
| `cr_straight_10` | 5 | 10 | 2 | 隔两格 |
| `cr_straight_15` | 5 | 15 | 2 | 隔三格 |
| `cr_straight_20` | 5 | 20 | 2 | 隔四格 |
| `cr_straight_30` | 5 | 30 | 2 | 远距离主路 |
| `cr_straight_45` | 5 | 45 | 2 | 跨整条边（最长档） |
| `cr_corner_05` | 5 | 5 | 2 | 直角拐角（L 形，一格见方） |
| `cr_t_junction_05` | 5 | 5 | 3 | T 字口 |
| `cr_cross_05` | 5 | 5 | 4 | 十字口 |

## 为什么宽 5m 而不是更窄

`RoomDoorLane.GRID_UNIT_M = 5.0`，且门洞本身 2.2m 宽要落在 5m 槽位中央。
通道做到 5m 时，两侧各留 1.4m 墙肩，门洞与房间侧的槽位**逐米对齐**；
做到 3m 或 4m，通道的门位就不在 5m 格线上，接房间时要额外偏移，
这正是 `RoomDoorLane` 类头注释里记的历史病根（白盒门槽与运行时门槽静默分叉）。

运行：
    python3 scripts/build_whitebox_corridor_kit.py
    python3 scripts/build_whitebox_corridor_kit.py --preview
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = (
    ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03"
)
CATALOG = ROOT / "data/level_plans/expedition_03/corridor_catalog.json"
PREVIEW_DIR = ROOT / "docs/art/expedition03_corridor_kit"

GRID = 5.0
WALK_Y = 0.08
FLOOR_THICKNESS = 0.10
WALL_THICKNESS = 0.30
WALL_HEIGHT = 11.9      # 与 room_templates 的 wall_height_m 一致
DOOR_W = 2.2
DOOR_CLEAR_H = 2.5

# (壳名, 净宽, 净长, 端口[(side, lane)])
# 直廊：两端各一口，lane 恒为 0（5m 宽的墙只有一个 0 槽，与 lane_offsets(5.0) 一致）。
CORRIDORS: list[tuple[str, float, float, list[tuple[str, float]]]] = [
    ("cr_straight_05", 5.0, 5.0, [("north", 0.0), ("south", 0.0)]),
    ("cr_straight_10", 5.0, 10.0, [("north", 0.0), ("south", 0.0)]),
    ("cr_straight_15", 5.0, 15.0, [("north", 0.0), ("south", 0.0)]),
    ("cr_straight_20", 5.0, 20.0, [("north", 0.0), ("south", 0.0)]),
    ("cr_straight_30", 5.0, 30.0, [("north", 0.0), ("south", 0.0)]),
    ("cr_straight_45", 5.0, 45.0, [("north", 0.0), ("south", 0.0)]),
    # 拐角 / 三通 / 十字：一格见方的节点，端口在相邻面上
    ("cr_corner_05", 5.0, 5.0, [("north", 0.0), ("east", 0.0)]),
    ("cr_t_junction_05", 5.0, 5.0, [("north", 0.0), ("south", 0.0), ("east", 0.0)]),
    ("cr_cross_05", 5.0, 5.0,
     [("north", 0.0), ("south", 0.0), ("east", 0.0), ("west", 0.0)]),
]


def build(name: str, width: float, depth: float,
          ports: list[tuple[str, float]]) -> tuple[str, dict]:
    half_w, half_d = width / 2.0, depth / 2.0
    subs: list[str] = []
    nodes: list[str] = []
    count = 0

    subs.append(
        '[sub_resource type="BoxMesh" id="BoxMesh_floor"]\n'
        f"size = Vector3({GRID:g}, {FLOOR_THICKNESS:g}, {GRID:g})\n"
    )
    subs.append(
        '[sub_resource type="StandardMaterial3D" id="Mat_whitebox"]\n'
        "albedo_color = Color(0.72, 0.75, 0.79, 1)\nroughness = 0.9\n"
    )
    subs.append(
        '[sub_resource type="StandardMaterial3D" id="Mat_whitebox_wall"]\n'
        "albedo_color = Color(0.46, 0.50, 0.56, 1)\nroughness = 0.9\n"
    )

    cols = int(round(width / GRID))
    rows = int(round(depth / GRID))
    if abs(cols * GRID - width) > 1e-6 or abs(rows * GRID - depth) > 1e-6:
        raise SystemExit(f"{name}: {width}×{depth} 不是 {GRID}m 整数倍")

    for r in range(rows):
        for c in range(cols):
            x = -half_w + GRID * (c + 0.5)
            z = -half_d + GRID * (r + 0.5)
            nodes.append(
                f'[node name="Floor_R{r:02d}_C{c:02d}" type="MeshInstance3D" parent="."]\n'
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:g}, "
                f"{WALK_Y - FLOOR_THICKNESS / 2:g}, {z:g})\n"
                'mesh = SubResource("BoxMesh_floor")\n'
                'material_override = SubResource("Mat_whitebox")\n'
                f"metadata/walk_plane_snap_y = {WALK_Y:g}\n"
            )
            count += 1

    sides = {
        "north": {"length": width, "axis": "x", "fixed": -half_d, "dir": -1.0},
        "south": {"length": width, "axis": "x", "fixed": +half_d, "dir": +1.0},
        "west": {"length": depth, "axis": "z", "fixed": -half_w, "dir": -1.0},
        "east": {"length": depth, "axis": "z", "fixed": +half_w, "dir": +1.0},
    }
    for side, geo in sides.items():
        length = geo["length"]
        lanes = [lane for s, lane in ports if s == side]
        gaps: list[tuple[float, float]] = []
        for lane in lanes:
            if abs(lane) > 1e-6:
                raise SystemExit(f"{name}: {side} 墙长 {length}m 只允许 lane=0，收到 {lane}")
            center = length / 2.0
            gaps.append((center - DOOR_W / 2.0, center + DOOR_W / 2.0))
        spans = [(0.0, length)]
        for g0, g1 in gaps:
            nxt: list[tuple[float, float]] = []
            for a, b in spans:
                if g1 <= a or g0 >= b:
                    nxt.append((a, b))
                    continue
                if g0 > a:
                    nxt.append((a, g0))
                if g1 < b:
                    nxt.append((g1, b))
            spans = nxt
        for i, (a, b) in enumerate(spans):
            seg = b - a
            if seg <= 0.001:
                continue
            center_local = (a + b) / 2.0 - length / 2.0
            mesh_id = f"BoxMesh_wall_{side}_{i}"
            if geo["axis"] == "x":
                size = (seg, WALL_HEIGHT, WALL_THICKNESS)
                pos = (center_local, WALL_HEIGHT / 2.0,
                       geo["fixed"] + geo["dir"] * WALL_THICKNESS / 2.0)
            else:
                size = (WALL_THICKNESS, WALL_HEIGHT, seg)
                pos = (geo["fixed"] + geo["dir"] * WALL_THICKNESS / 2.0,
                       WALL_HEIGHT / 2.0, center_local)
            subs.append(
                f'[sub_resource type="BoxMesh" id="{mesh_id}"]\n'
                f"size = Vector3({size[0]:g}, {size[1]:g}, {size[2]:g})\n"
            )
            nodes.append(
                f'[node name="Wall_{side.capitalize()}_{i:02d}" type="MeshInstance3D" parent="."]\n'
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]:g}, {pos[1]:g}, {pos[2]:g})\n"
                f'mesh = SubResource("{mesh_id}")\n'
                'material_override = SubResource("Mat_whitebox_wall")\n'
                f'metadata/tower_wall_direction = "{side}"\n'
                f"metadata/grid_unit_m = {GRID:g}\n"
            )
            count += 1
        # 门洞过梁
        lintel_h = WALL_HEIGHT - DOOR_CLEAR_H
        for i, (g0, g1) in enumerate(gaps):
            center_local = (g0 + g1) / 2.0 - length / 2.0
            mesh_id = f"BoxMesh_lintel_{side}_{i}"
            if geo["axis"] == "x":
                size = (DOOR_W, lintel_h, WALL_THICKNESS)
                pos = (center_local, DOOR_CLEAR_H + lintel_h / 2.0,
                       geo["fixed"] + geo["dir"] * WALL_THICKNESS / 2.0)
            else:
                size = (WALL_THICKNESS, lintel_h, DOOR_W)
                pos = (geo["fixed"] + geo["dir"] * WALL_THICKNESS / 2.0,
                       DOOR_CLEAR_H + lintel_h / 2.0, center_local)
            subs.append(
                f'[sub_resource type="BoxMesh" id="{mesh_id}"]\n'
                f"size = Vector3({size[0]:g}, {size[1]:g}, {size[2]:g})\n"
            )
            nodes.append(
                f'[node name="Lintel_{side.capitalize()}_{i:02d}" type="MeshInstance3D" parent="."]\n'
                f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {pos[0]:g}, {pos[1]:g}, {pos[2]:g})\n"
                f'mesh = SubResource("{mesh_id}")\n'
                'material_override = SubResource("Mat_whitebox_wall")\n'
            )
            count += 1

    port_basis = {
        "north": "-1, 0, 0, 0, 1, 0, 0, 0, -1",
        "south": "1, 0, 0, 0, 1, 0, 0, 0, 1",
        "west": "0, 0, 1, 0, 1, 0, -1, 0, 0",
        "east": "0, 0, -1, 0, 1, 0, 1, 0, 0",
    }
    outward = {"north": "(0, -1)", "south": "(0, 1)", "west": "(-1, 0)", "east": "(1, 0)"}
    port_lines = [
        '[node name="ConnectionPorts" type="Node3D" parent="."]\n'
        f"metadata/connection_port_count = {len(ports)}\n"
    ]
    for i, (side, lane) in enumerate(ports):
        if side in ("north", "south"):
            px, pz = lane, (-half_d if side == "north" else half_d)
        else:
            px, pz = (-half_w if side == "west" else half_w), lane
        port_lines.append(
            f'[node name="Port_{chr(ord("A") + i)}" type="Marker3D" parent="ConnectionPorts"]\n'
            f"transform = Transform3D({port_basis[side]}, {px:g}, 0, {pz:g})\n"
            f'metadata/port_id = "{chr(ord("A") + i)}"\n'
            f'metadata/side = "{side}"\n'
            f"metadata/lane_m = {lane:g}\n"
            f"metadata/outward = Vector2{outward[side]}\n"
            "metadata/connected = false\n"
            f'metadata/door_opening_m = [{DOOR_W:g}, {DOOR_CLEAR_H:g}]\n'
        )

    nav: list[list[list[float]]] = [[
        [-half_w, WALK_Y, -half_d], [half_w, WALK_Y, -half_d],
        [half_w, WALK_Y, half_d], [-half_w, WALK_Y, half_d],
    ]]
    for side, lane in ports:
        h = DOOR_W / 2.0
        if side in ("north", "south"):
            z0 = -half_d - 0.6 if side == "north" else half_d - 0.6
            nav.append([[lane - h, WALK_Y, z0], [lane + h, WALK_Y, z0],
                        [lane + h, WALK_Y, z0 + 1.2], [lane - h, WALK_Y, z0 + 1.2]])
        else:
            x0 = -half_w - 0.6 if side == "west" else half_w - 0.6
            nav.append([[x0, WALK_Y, lane - h], [x0 + 1.2, WALK_Y, lane - h],
                        [x0 + 1.2, WALK_Y, lane + h], [x0, WALK_Y, lane + h]])

    shape = "straight" if len(ports) == 2 and ports[0][0] != ports[1][0] else \
        "corner" if len(ports) == 2 else f"junction_{len(ports)}"
    header = (
        '[node name="ExpeditionCorridorStaticLayout" type="Node3D"]\n'
        'metadata/schema = "shellstorm2.expedition.corridor_whitebox.v001"\n'
        f'metadata/shell_id = "{name}"\n'
        f'metadata/corridor_shape = "{shape}"\n'
        f"metadata/size_m = [{width:g}, {depth:g}]\n"
        f"metadata/grid_unit_m = {GRID:g}\n"
        f"metadata/wall_height_m = {WALL_HEIGHT:g}\n"
        f"metadata/door_width_m = {DOOR_W:g}\n"
        f"metadata/door_clear_height_m = {DOOR_CLEAR_H:g}\n"
        f"metadata/layout_instance_total = {count}\n"
        f"metadata/connection_port_count = {len(ports)}\n"
        "metadata/whitebox = true\n"
        'metadata/is_narrow_room = true\n'
        'metadata/whitebox_excludes = ["floor_art","wall_art","props","lights","doors"]\n'
        f"metadata/walkable_navigation_polygons = {json.dumps(nav)}\n"
        'metadata/source = "scripts/build_whitebox_corridor_kit.py"\n'
        '\n[node name="RoomCeilingLight" type="Node3D" parent="."]\n'
        f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {WALL_HEIGHT - 1.5:g}, 0)\n"
        'metadata/pending = "whitebox 不含灯；建美术时替换为 WastelandLight3D"\n'
        '\n[node name="RoomLightSwitch3D" type="Area3D" parent="."]\n'
        'metadata/pending = "whitebox 不含开关；建美术时替换为 RoomLightSwitch3D"\n'
    )
    text = '[gd_scene format=3]\n\n' + "\n".join(subs) + "\n" + header + "\n".join(nodes) \
        + "\n" + "\n".join(port_lines)
    return text, {"shell_id": name, "size_m": [width, depth], "ports": ports,
                  "shape": shape, "instances": count}


def preview(meta: dict, out: Path) -> None:
    from PIL import Image, ImageDraw
    S = 12
    pad = 34
    w, d = meta["size_m"]
    W, H = int(w * S) + pad * 2, int(d * S) + pad * 2
    im = Image.new("RGB", (W, H), (243, 245, 247))
    dr = ImageDraw.Draw(im)

    def X(x): return pad + (x + w / 2) * S
    def Y(z): return pad + (z + d / 2) * S

    dr.rectangle([X(-w / 2), Y(-d / 2), X(w / 2), Y(d / 2)],
                 fill=(198, 203, 210), outline=(88, 94, 100))
    for i in range(1, int(w // GRID)):
        dr.line([X(-w / 2 + i * GRID), Y(-d / 2), X(-w / 2 + i * GRID), Y(d / 2)],
                fill=(176, 182, 189))
    for i in range(1, int(d // GRID)):
        dr.line([X(-w / 2), Y(-d / 2 + i * GRID), X(w / 2), Y(-d / 2 + i * GRID)],
                fill=(176, 182, 189))
    h = DOOR_W / 2
    for side, lane in meta["ports"]:
        if side in ("north", "south"):
            z = -d / 2 if side == "north" else d / 2
            dr.rectangle([X(lane - h), Y(z) - 4, X(lane + h), Y(z) + 4], fill=(230, 168, 40))
        else:
            x = -w / 2 if side == "west" else w / 2
            dr.rectangle([X(x) - 4, Y(lane - h), X(x) + 4, Y(lane + h)], fill=(230, 168, 40))
    dr.text((pad, 10), f"{meta['shell_id']}  {w:g}x{d:g}m  ports={len(meta['ports'])}  {meta['shape']}",
            fill=(36, 40, 44))
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)


def main(argv: list[str]) -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    want_preview = "--preview" in argv
    written: list[dict] = []
    for name, width, depth, ports in CORRIDORS:
        text, meta = build(name, width, depth, ports)
        (OUT_DIR / f"{name}_static_layout.tscn").write_text(text + "\n", encoding="utf-8")
        written.append(meta)
        print(f"written {name + '_static_layout.tscn':40s} {width:g}x{depth:g}m "
              f"ports={len(ports)} instances={meta['instances']}")
        if want_preview:
            preview(meta, PREVIEW_DIR / f"{name}.png")

    catalog = {
        "schema": "shellstorm2.expedition.corridor_catalog.v001",
        "schema_version": 1,
        "level_id": "expedition_03",
        "design_rule": (
            "走廊就是一间很窄的房间，与房间同契约（5m 格、2.2m 门洞、同一套 lane 槽），"
            "不是独立的连接件类型；生成顺序上它排在最后，用来补已摆好房间之间的缝。"
        ),
        "grid_unit_m": GRID,
        "net_width_m": 5.0,
        "note_width": (
            "净宽取 5m 而非更窄：门洞 2.2m 必须居中落在 5m 槽位上，两侧各留 1.4m 墙肩，"
            "才能与房间侧槽位逐米对齐。3~4m 宽的通道会让门位脱离 5m 格线。"
        ),
        "shells": [
            {
                "shell_id": m["shell_id"],
                "size_m": m["size_m"],
                "shape": m["shape"],
                "ports": [{"side": s, "lane_m": lane} for s, lane in m["ports"]],
                "scene": "res://assets/art/environments/tower_zones/expedition/runtime/"
                         f"room_instances/expedition_03/{m['shell_id']}_static_layout.tscn",
            }
            for m in written
        ],
    }
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"\n{len(written)} 份通道 -> {OUT_DIR.relative_to(ROOT)}")
    print(f"清单 -> {CATALOG.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
