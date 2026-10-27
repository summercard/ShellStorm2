#!/usr/bin/env python3
"""《挺进地牢》全部房型白盒生成器（56 种）。

## 种类是怎么定的（不是我拍的）

`scripts/extract_egt_room_types.py` 从官方 flow 骨架图 PDF（28 张，覆盖全部 5 层、
551 个房间位）反推出每个房间的**门开在哪几面、每面几扇**。按
`(房型 kind, 门面组合)` 去重 = **56 种**。本脚本为 56 种各出一份白盒 TSCN。

> 与远征03 的 `rt_*` 的区别：`rt_*` 是 ShellStorm2 自己 8 个模板的壳（含非矩形轮廓、
> 按变体分）；本目录是**按 EGT 实测房型谱**做的原型，全部矩形（EGT 房间本身就是矩形，
> 「相邻门」不等于缺角）。

## 尺寸怎么定（规则唯一，可复核）

EGT 的真实格数不可得（截图是带透视的渲染图，反推不收敛 —— 见 CHANGELOG 2026-10-27）。
所以尺寸由**门位约束 + 房型基准**两步推出，避免我随手拍数字：

1. **硬约束**：一面墙能开的门数有上限。`RoomDoorLane.lane_offsets(L)` 的槽数是：
   格数 ≥3 时为 `格数-2`（首尾各留一格不贴角），否则等于格数。
   ⇒ 该面要开 n 扇门，墙长必须满足 `槽数(格数) >= n`。
2. **房型基准**：给每种房型一个无门时的最小尺寸档（BOSS 最大、CONNECTOR 细长、
   宝箱/商店/出口小）。这是**风格推定**，不是 EGT 实测值，逐份写进
   `metadata/size_basis` 说明来源。
3. 取二者较大值：`宽 = max(基准宽, min_cells(北门数), min_cells(南门数))`，深同理。

本脚本对第 1 条做**生成期断言**：算出来放不下就报错，不静默产出坏房。

## 坐标与契约（与 expedition_03 完全一致）

- 5m 一格；房间以包围盒中心为原点
- north = −Z，south = +Z，east = +X，west = −X
- 门洞 2.2 × 2.5m，2.8m 处补过梁；`ConnectionPorts/Port_*` 标出每扇门
- 只有地面与墙，`metadata/whitebox_excludes` 逐项声明缺什么

运行：
    python3 scripts/build_egt_room_types.py
    python3 scripts/build_egt_room_types.py --preview
"""
from __future__ import annotations

import csv
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "docs/v0.1/reference/挺进地牢/EGT房型种类.csv"
OUT_DIR = ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_instances/egt_room_types"
CATALOG = ROOT / "data/level_plans/egt_reference/room_types.json"
PREVIEW_DIR = ROOT / "docs/art/egt_room_types"

GRID = 5.0
WALK_Y = 0.08
FLOOR_THICKNESS = 0.10
WALL_THICKNESS = 0.30
WALL_HEIGHT = 11.9
DOOR_W = 2.2
DOOR_CLEAR_H = 2.5
LINTEL_H = WALL_HEIGHT - DOOR_CLEAR_H

# 房型基准尺寸（格）。EGT 原文只有定性描述：
#   HUB = "larger rooms with more exits" / CONNECTOR = "long, thin rooms" / BOSS 最大
# 所以这三档按原文给，其余按用途给最小合理值。**这是推定值，不是实测格数。**
BASE_CELLS: dict[str, tuple[int, int]] = {
    "ENTRANCE": (3, 3),
    "EXIT": (3, 3),
    "REWARD": (3, 3),
    "SHOP": (4, 3),
    "SPECIAL": (3, 3),
    "NORMAL": (5, 4),
    "BOSS_FOYER": (5, 4),
    "HUB": (6, 5),
    "CONNECTOR": (2, 4),   # 细长：窄边 2 格 = 10m
    "BOSS": (10, 8),
}

KIND_ZH = {
    "ENTRANCE": "入口", "EXIT": "出口", "BOSS": "首领", "BOSS_FOYER": "首领前厅",
    "REWARD": "宝箱房", "SHOP": "商店", "NORMAL": "战斗房", "HUB": "枢纽房",
    "CONNECTOR": "连接房", "SPECIAL": "特殊房",
}


# ── 与 RoomDoorLane.gd 同源 ─────────────────────────────────────────────────
def slot_count(cells: int) -> int:
    """一面 count 格的墙允许开几个门槽（首尾各留一格不贴角）。"""
    return cells - 2 if cells >= 3 else cells


def min_cells_for(doors: int) -> int:
    """要在这面墙开 doors 扇门，至少需要几格。

    ⚠ `slot_count` **不是单调的**：2 格有 2 槽（都不贴角），3 格却只有 1 槽
    （首尾各留一格）。所以不能用"按公式反解"，只能逐格往上找。
    """
    if doors <= 0:
        return 1
    for cells in range(1, 40):
        if slot_count(cells) >= doors:
            return cells
    raise SystemExit(f"开不下 {doors} 扇门")


def lane_offsets(length_m: float) -> list[float]:
    cells = max(1, int(round(length_m / GRID)))
    first = 1 if cells >= 3 else 0
    last = cells - 2 if cells >= 3 else cells - 1
    return [-length_m * 0.5 + GRID * (i + 0.5) for i in range(first, last + 1)]


def parse_sides(key: str) -> dict[str, int]:
    """'N1S2' -> {'N':1, 'S':2}"""
    out: dict[str, int] = {}
    i = 0
    while i < len(key):
        side = key[i]
        i += 1
        digits = ""
        while i < len(key) and key[i].isdigit():
            digits += key[i]
            i += 1
        if side not in "NSEW" or not digits:
            raise SystemExit(f"门面组合无法解析：{key}")
        out[side] = int(digits)
    return out


def size_of(kind: str, sides: dict[str, int]) -> tuple[int, int, str]:
    base_w, base_d = BASE_CELLS[kind]
    # 从基准档往上**逐格搜索**满足门位约束的最小尺寸。
    # 不能写 `max(base, min_cells_for(n))`：slot_count 非单调（2 格 2 槽、3 格 1 槽），
    # 那样会算出 3 格放 2 门的坏尺寸 —— 实测被生成期断言拦下过一次。
    w = base_w
    while slot_count(w) < max(sides.get("N", 0), sides.get("S", 0)):
        w += 1
    d = base_d
    while slot_count(d) < max(sides.get("E", 0), sides.get("W", 0)):
        d += 1
    # CONNECTOR 保持细长：若门位约束把窄边撑过了长边，交换两轴
    if kind == "CONNECTOR" and w > d:
        w, d = d, w
    basis = (f"base={base_w}x{base_d} slots(w)={slot_count(w)} slots(d)={slot_count(d)} "
             f"need=({max(sides.get('N', 0), sides.get('S', 0))},"
             f"{max(sides.get('E', 0), sides.get('W', 0))})")
    return w, d, basis


# ── 几何 ────────────────────────────────────────────────────────────────────
def solid_spans(length: float, gaps: list[tuple[float, float]]) -> list[tuple[float, float]]:
    spans = [(0.0, length)]
    for g0, g1 in sorted(gaps):
        nxt: list[tuple[float, float]] = []
        for a, b in spans:
            if g1 <= a or g0 >= b:
                nxt.append((a, b))
                continue
            if g0 > a:
                nxt.append((a, min(g0, b)))
            if g1 < b:
                nxt.append((max(g1, a), b))
        spans = nxt
    return [(a, b) for a, b in spans if b - a > 0.001]


def pick_lanes(length_m: float, count: int) -> list[float]:
    """在该面均匀取 count 个槽：优先靠近中心，且相邻槽至少隔一个门洞。"""
    slots = lane_offsets(length_m)
    if len(slots) < count:
        raise SystemExit(
            f"墙长 {length_m}m 只有 {len(slots)} 个门槽，放不下 {count} 扇门"
        )
    ordered = sorted(slots, key=abs)
    picked: list[float] = []
    for slot in ordered:
        if len(picked) >= count:
            break
        if any(abs(slot - p) < DOOR_W + 0.4 for p in picked):
            continue
        picked.append(slot)
    if len(picked) < count:
        raise SystemExit(f"墙长 {length_m}m 的 {len(slots)} 个槽无法均匀放 {count} 门")
    return sorted(picked)


def build(kind: str, sides_key: str, sides: dict[str, int],
          w_cells: int, d_cells: int, basis: str, occurrence: int,
          floors: str, flows: str) -> tuple[str, dict]:
    width, depth = w_cells * GRID, d_cells * GRID
    half_w, half_d = width / 2.0, depth / 2.0

    ports: list[tuple[str, float]] = []
    side_name = {"N": "north", "S": "south", "E": "east", "W": "west"}
    side_len = {"N": width, "S": width, "E": depth, "W": depth}
    for key in ("N", "S", "E", "W"):
        count = sides.get(key, 0)
        if not count:
            continue
        for lane in pick_lanes(side_len[key], count):
            ports.append((side_name[key], lane))

    subs: list[str] = []
    nodes: list[str] = []
    count_ = 0

    subs.append(
        '[sub_resource type="BoxMesh" id="BoxMesh_floor"]\n'
        f"size = Vector3({GRID:g}, {FLOOR_THICKNESS:g}, {GRID:g})\n"
    )
    subs.append(
        '[sub_resource type="StandardMaterial3D" id="Mat_whitebox"]\n'
        "albedo_color = Color(0.76, 0.78, 0.8, 1)\nroughness = 0.9\n"
    )
    subs.append(
        '[sub_resource type="StandardMaterial3D" id="Mat_whitebox_wall"]\n'
        "albedo_color = Color(0.52, 0.55, 0.6, 1)\nroughness = 0.9\n"
    )

    for r in range(d_cells):
        for c in range(w_cells):
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
            count_ += 1

    geo = {
        "north": (width, "x", -half_d, -1.0),
        "south": (width, "x", +half_d, +1.0),
        "west": (depth, "z", -half_w, -1.0),
        "east": (depth, "z", +half_w, +1.0),
    }
    for side, (length, axis, fixed, direction) in geo.items():
        gaps: list[tuple[float, float]] = []
        for s, lane in ports:
            if s != side:
                continue
            center = lane + length / 2.0
            gaps.append((center - DOOR_W / 2.0, center + DOOR_W / 2.0))
        for i, (a, b) in enumerate(solid_spans(length, gaps)):
            seg = b - a
            center_local = (a + b) / 2.0 - length / 2.0
            mesh_id = f"BoxMesh_wall_{side}_{i}"
            if axis == "x":
                size = (seg, WALL_HEIGHT, WALL_THICKNESS)
                pos = (center_local, WALL_HEIGHT / 2.0, fixed + direction * WALL_THICKNESS / 2.0)
            else:
                size = (WALL_THICKNESS, WALL_HEIGHT, seg)
                pos = (fixed + direction * WALL_THICKNESS / 2.0, WALL_HEIGHT / 2.0, center_local)
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
            count_ += 1
        for i, (g0, g1) in enumerate(gaps):
            center_local = (g0 + g1) / 2.0 - length / 2.0
            mesh_id = f"BoxMesh_lintel_{side}_{i}"
            if axis == "x":
                size = (DOOR_W, LINTEL_H, WALL_THICKNESS)
                pos = (center_local, DOOR_CLEAR_H + LINTEL_H / 2.0,
                       fixed + direction * WALL_THICKNESS / 2.0)
            else:
                size = (WALL_THICKNESS, LINTEL_H, DOOR_W)
                pos = (fixed + direction * WALL_THICKNESS / 2.0,
                       DOOR_CLEAR_H + LINTEL_H / 2.0, center_local)
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
            count_ += 1

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
            f'metadata/outward = Vector2{outward[side]}\n'
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

    shell_id = f"egt_{kind.lower()}_{sides_key}"
    polygon = [[0.0, 0.0], [width, 0.0], [width, depth], [0.0, depth]]
    header = (
        '[node name="EgtRoomTypeStaticLayout" type="Node3D"]\n'
        'metadata/schema = "shellstorm2.egt_room_type.whitebox.v001"\n'
        f'metadata/shell_id = "{shell_id}"\n'
        f'metadata/egt_kind = "{kind}"\n'
        f'metadata/egt_kind_zh = "{KIND_ZH[kind]}"\n'
        f'metadata/door_sides = "{sides_key}"\n'
        f"metadata/door_count = {len(ports)}\n"
        f"metadata/egt_occurrences = {occurrence}\n"
        f'metadata/egt_floors = "{floors}"\n'
        f'metadata/egt_flows = "{flows}"\n'
        f"metadata/size_m = [{width:g}, {depth:g}]\n"
        f"metadata/size_cells = [{w_cells}, {d_cells}]\n"
        f'metadata/size_basis = "{basis}"\n'
        f"metadata/grid_unit_m = {GRID:g}\n"
        f"metadata/wall_height_m = {WALL_HEIGHT:g}\n"
        f"metadata/door_width_m = {DOOR_W:g}\n"
        f"metadata/door_clear_height_m = {DOOR_CLEAR_H:g}\n"
        f"metadata/footprint_area_m2 = {width * depth:g}\n"
        "metadata/footprint_is_rect = true\n"
        f"metadata/footprint_polygon_m = {json.dumps(polygon)}\n"
        f"metadata/layout_instance_total = {count_}\n"
        f"metadata/connection_port_count = {len(ports)}\n"
        "metadata/whitebox = true\n"
        'metadata/whitebox_excludes = ["floor_art","wall_art","props","traps",'
        '"spawn_points","lights","doors"]\n'
        f"metadata/walkable_navigation_polygons = {json.dumps(nav)}\n"
        'metadata/source = "scripts/build_egt_room_types.py"\n'
        'metadata/provenance = "门面组合来自官方 flow 骨架图 PDF 实测；尺寸为推定值，非 EGT 真实格数"\n'
        '\n[node name="RoomCeilingLight" type="Node3D" parent="."]\n'
        f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, {WALL_HEIGHT - 1.5:g}, 0)\n"
        'metadata/pending = "whitebox 不含灯"\n'
        '\n[node name="RoomLightSwitch3D" type="Area3D" parent="."]\n'
        'metadata/pending = "whitebox 不含开关"\n'
    )
    text = ('[gd_scene format=3]\n\n' + "\n".join(subs) + "\n" + header
            + "\n".join(nodes) + "\n" + "\n".join(port_lines))
    meta = {
        "shell_id": shell_id, "kind": kind, "sides_key": sides_key,
        "sides": sides, "size_m": [width, depth], "size_cells": [w_cells, d_cells],
        "ports": ports, "occurrence": occurrence, "basis": basis,
        "instances": count_, "polygon": polygon,
    }
    return text, meta


def preview(meta: dict, out: Path) -> None:
    from PIL import Image, ImageDraw
    S = 11
    pad = 34
    w, d = meta["size_m"]
    W, H = int(w * S) + pad * 2, int(d * S) + pad * 2
    im = Image.new("RGB", (W, H), (246, 247, 248))
    dr = ImageDraw.Draw(im)

    def X(x): return pad + (x + w / 2) * S
    def Y(z): return pad + (z + d / 2) * S

    dr.rectangle([X(-w / 2), Y(-d / 2), X(w / 2), Y(d / 2)],
                 fill=(205, 210, 215), outline=(86, 92, 98))
    for i in range(1, int(w // GRID)):
        dr.line([X(-w / 2 + i * GRID), Y(-d / 2), X(-w / 2 + i * GRID), Y(d / 2)],
                fill=(182, 187, 193))
    for i in range(1, int(d // GRID)):
        dr.line([X(-w / 2), Y(-d / 2 + i * GRID), X(w / 2), Y(-d / 2 + i * GRID)],
                fill=(182, 187, 193))
    h = DOOR_W / 2
    for side, lane in meta["ports"]:
        if side in ("north", "south"):
            z = -d / 2 if side == "north" else d / 2
            dr.rectangle([X(lane - h), Y(z) - 4, X(lane + h), Y(z) + 4], fill=(226, 162, 36))
        else:
            x = -w / 2 if side == "west" else w / 2
            dr.rectangle([X(x) - 4, Y(lane - h), X(x) + 4, Y(lane + h)], fill=(226, 162, 36))
    dr.text((pad, 9),
            f"{KIND_ZH[meta['kind']]} {meta['sides_key']}  {w:g}x{d:g}m  x{meta['occurrence']}",
            fill=(34, 38, 42))
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)


def main(argv: list[str]) -> int:
    if not CSV_PATH.is_file():
        raise SystemExit(f"先跑 extract_egt_room_types.py 生成 {CSV_PATH.name}")
    want_preview = "--preview" in argv

    rows = list(csv.DictReader(CSV_PATH.open(encoding="utf-8-sig")))
    # (kind, sides) -> 出现次数 / 楼层集 / flow 数
    occ: dict[tuple[str, str], int] = defaultdict(int)
    floors: dict[tuple[str, str], set] = defaultdict(set)
    flows: dict[tuple[str, str], set] = defaultdict(set)
    for row in rows:
        key = (row["房型"], row["门面"])
        occ[key] += 1
        floors[key].add(row["楼层"])
        flows[key].add(row["flow"])

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    written: list[dict] = []
    for (kind, sides_key), count in sorted(occ.items(), key=lambda x: (-x[1], x[0])):
        sides = parse_sides(sides_key)
        w_cells, d_cells, basis = size_of(kind, sides)
        # 生成期断言：每面要开的门数必须放得进该面墙的槽位数
        for key, side in (("N", "north"), ("S", "south")):
            assert slot_count(w_cells) >= sides.get(key, 0), \
                f"{kind}/{sides_key}: 宽 {w_cells} 格只有 {slot_count(w_cells)} 槽，" \
                f"放不下 {side} 的 {sides.get(key, 0)} 门"
        for key, side in (("E", "east"), ("W", "west")):
            assert slot_count(d_cells) >= sides.get(key, 0), \
                f"{kind}/{sides_key}: 深 {d_cells} 格只有 {slot_count(d_cells)} 槽，" \
                f"放不下 {side} 的 {sides.get(key, 0)} 门"

        text, meta = build(
            kind, sides_key, sides, w_cells, d_cells, basis, count,
            "/".join(sorted(floors[(kind, sides_key)])),
            f"{len(flows[(kind, sides_key)])} 条骨架",
        )
        name = f"{meta['shell_id']}_static_layout.tscn"
        (OUT_DIR / name).write_text(text + "\n", encoding="utf-8")
        written.append(meta)
        if want_preview:
            preview(meta, PREVIEW_DIR / f"{meta['shell_id']}.png")

    # 清理不再需要的旧壳
    keep = {f"{m['shell_id']}_static_layout.tscn" for m in written}
    for stale in OUT_DIR.glob("egt_*_static_layout.tscn"):
        if stale.name not in keep:
            stale.unlink()
            print(f"removed stale {stale.name}")

    catalog = {
        "schema": "shellstorm2.egt_room_type.catalog.v001",
        "schema_version": 1,
        "source": "docs/v0.1/reference/挺进地牢/EGT房型种类.csv",
        "source_note": "由 scripts/extract_egt_room_types.py 从官方 flow PDF（28 张 / 5 层 / 551 房间位）反推",
        "total_room_positions": len(rows),
        "kinds": sorted({row["房型"] for row in rows}),
        "kind_count": len({row["房型"] for row in rows}),
        "type_count": len(written),
        "size_rule": (
            "宽 = max(房型基准宽, min_cells(北门数), min_cells(南门数))，深同理；"
            "min_cells(n) = 使该墙 lane 槽数 >= n 的最小格数（格数>=3 时槽数=格数-2）。"
            "CONNECTOR 额外保证窄边 <= 长边（保持细长）。"
            "⚠ 尺寸是推定值：EGT 真实格数不可从公开截图反推。"
        ),
        "types": [
            {
                "shell_id": m["shell_id"],
                "egt_kind": m["kind"],
                "egt_kind_zh": KIND_ZH[m["kind"]],
                "door_sides": m["sides_key"],
                "door_count": len(m["ports"]),
                "size_m": m["size_m"],
                "size_cells": m["size_cells"],
                "egt_occurrences": m["occurrence"],
                "size_basis": m["basis"],
                "scene": "res://assets/art/environments/tower_zones/expedition/runtime/"
                         f"room_instances/egt_room_types/{m['shell_id']}_static_layout.tscn",
            }
            for m in written
        ],
    }
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"{len(written)} 种房型 -> {OUT_DIR.relative_to(ROOT)}")
    print(f"清单 -> {CATALOG.relative_to(ROOT)}")
    print()
    by_kind: dict[str, int] = defaultdict(int)
    for m in written:
        by_kind[m["kind"]] += 1
    for kind in sorted(by_kind, key=lambda k: -by_kind[k]):
        print(f"  {KIND_ZH[kind]:6s}{kind:12s} {by_kind[kind]:2d} 种")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
