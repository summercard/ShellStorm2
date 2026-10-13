#!/usr/bin/env python3
"""生成远征关卡02 的 26 个房间静态布局场景（`f00_<room>_static_layout.tscn`）。

Run with:
    python scripts/build_expedition02_room_scenes.py

## 几何真源 = 白盒 manifest

每个房间的实例坐标直接取自白盒 `asset_manifest.json`（`components` 数组里每件对象都有
`room_key` 与 `bounds_world_m`）。**不重新推算、不缩放**：白盒的 5m 网格几何就是运行时几何。

## 坐标与旋转

白盒是设计平面坐标（`x` 东西、`y` 南北、`z` 高度）。房间实例用**房间局部** Godot 坐标：

    Godot.x = 世界 x − 房心 x
    Godot.y = 世界 z（高度）
    Godot.z = 世界 y − 房心 y      （平面 +y = 世界 +z = 南）

墙件默认长轴在 Godot `X`、厚度在 `Z`。白盒里长轴沿世界 y 的墙需要绕 Y 转 90°，
基向量写作 `(0,0,-1, 0,1,0, 1,0,0)`（与远征01 房间场景同写法）。

## 门墙的归属

一条门边只生成**一套**门墙。归属规则：门表的 `side_a` 侧房间拥有它，另一侧不重复放
（那一侧的实墙本就不覆盖该槽 —— 白盒的门槽是整格让出来的）。这与设计页 §4.7
「一条边只生成一套门墙」一致。

## 封顶

除阳台安全屋（`entry`）与挑高前厅（`room_01`）外，其余 24 间房全部铺 `ceiling_deck_5m`，底面高度 **4.0 m**
（2026-10-12 业主裁定：普通房净高 4.0 m；走面到顶盖底净高 3.70 m，墙顶上方保留 1.0 m 管线空腔）。
挑高前厅（11.9 m）**不封顶** —— 它是通高空间，封了就毁掉 11.9 m 的第一印象。
"""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEVEL_ID = "expedition_02"
WHITEBOX = (
    ROOT / "art_source/design/whitebox/tower_zones/expedition_02/v001"
    / "data/component_packages/hotel_floor_01/远征关卡02_白模_第1层_长廊与客房/asset_manifest.json"
)
OUT_DIR = (
    ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_02"
)
# 运行时房间 ID 的唯一真源：L2 层的 legacy_room_id（`FloorPlanGenerator` 优先采它）。
# 文件名必须与它一致 —— `TowerDescent3D` 按 `f00_<legacy_room_id>_static_layout.tscn` 拼路径。
LEVEL_PLAN = ROOT / "data/level_plans/expedition_02/floors/floor_00.json"
PREFAB_ROOT = "res://assets/art/environments/tower_zones/expedition/runtime/common_components"

GRID = 5.0
CEILING_BOTTOM_Y = 4.0          # 顶盖底面标高；距 0.30m 走面的净高为 3.70m
CEILING_THICK = 0.26
FLOOR_BASE_TOP = 0.26
TILE_THICK = 0.04

# 不封顶的房间：阳台安全屋按业主要求不封；挑高前厅是通高空间，封了就毁掉 11.9m 的对比
NO_CEILING = {"entry", "room_01"}

def load_runtime_ids() -> dict:
    """design_key -> 运行时房间 ID。取自 L2，不在这里另拍一套。"""
    if not LEVEL_PLAN.is_file():
        raise SystemExit("先跑 build_expedition02_level_plan.py 生成 L2：%s" % LEVEL_PLAN)
    plan = json.loads(LEVEL_PLAN.read_text(encoding="utf-8"))
    out = {}
    for room in plan["rooms"]:
        key = str(room.get("key", ""))
        rid = str(room.get("legacy_room_id", "")) or str(room.get("room_id", ""))
        if key and rid:
            out[key] = rid
    if not out:
        raise SystemExit("L2 里没读到任何 legacy_room_id")
    return out


ROOM_KEY_MAP = {
    "balcony": "entry",
    "tall_hall": "room_01", "corridor": "room_02",
    "room_w1": "room_03", "room_w2": "room_04", "room_w3": "room_05",
    "room_w4": "room_06", "room_w5": "room_07",
    "room_e1": "room_08", "room_e2": "room_09", "room_e3": "room_10",
    "room_e4": "room_11", "room_e5": "room_12",
    "tee_cross": "room_13", "tee_west": "room_14", "tee_east": "room_15",
    "room_w6": "room_16", "room_w8": "room_17", "room_w10": "room_18",
    "room_w7": "room_19", "room_w9": "room_20",
    "room_e6": "room_21", "room_e8": "room_22", "room_e10": "room_23",
    "room_e7": "room_24", "room_e9": "room_25",
}
SLUG_TO_PREFAB = {
    "wall_standard_5m_h3": "wall_standard_5m_h3",
    "wall_standard_5m_h12": "wall_standard_5m_h12",
    "wall_door_5m_h3": "wall_door_5m_h3",
    "wall_door_5m_h12": "wall_door_5m_h12",
    "wall_collapse_5m_h12": "wall_collapse_5m_h12",
    "floor_base_5m": "floor_base_5m",
    "floor_tile_5m": "floor_tile_5m",
    "ceiling_deck_5m": "ceiling_deck_5m",
}

# 房间类型（供 metadata；与设计源一致）
ROOM_TYPE = {"entry": "SAFE_ROOM"}

ROT_ZERO = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
ROT_Y90 = (0.0, 0.0, -1.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0)


def fmt(value: float) -> str:
    if abs(value) < 1e-9:
        return "0"
    if abs(value - round(value)) < 1e-9:
        return "%d" % round(value)
    return "%g" % round(value, 6)


def transform(basis, origin) -> str:
    return "Transform3D(%s, %s)" % (
        ", ".join(fmt(v) for v in basis),
        ", ".join(fmt(v) for v in origin),
    )


def main() -> int:
    wb = json.loads(WHITEBOX.read_text(encoding="utf-8"))
    rooms = {r["key"]: r for r in wb["rooms"]}
    centers = {k: (r["center_m"][0], r["center_m"][1]) for k, r in rooms.items()}
    rects = {}
    for k, r in rooms.items():
        cx, cy = centers[k]
        w, d = r["size_m"]
        rects[k] = (cx - w / 2, cx + w / 2, cy - d / 2, cy + d / 2)

    # ---- 墙归属：**每面墙全局只出现一次** ----
    # 白盒的 wall 对象建在全局网格线上、不带 room_key（它们由相邻两房共享）。
    # 归属规则（确定性）：取墙线**负侧**那间房；负侧无房（外墙）时取正侧。
    # 竖向墙 x=line，段 y∈[a,b]：负侧 = 西，正侧 = 东
    # 横向墙 y=line，段 x∈[a,b]：负侧 = 南，正侧 = 北
    wall_home: dict[str, str] = {}
    for obj in wb["components"]:
        if obj["kind"] != "wall":
            continue
        lo = obj["bounds_world_m"]["min"]
        hi = obj["bounds_world_m"]["max"]
        wcx, wcy = (lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0
        dims = obj["dimensions_m"]
        along_y = dims[1] > dims[0]                 # 长轴沿世界 y ⇒ 竖向墙
        if along_y:
            line_x = (lo[0] + hi[0]) / 2.0
            home = _room_at(line_x - 1.0, wcy, rects) or _room_at(line_x + 1.0, wcy, rects)
        else:
            line_y = (lo[1] + hi[1]) / 2.0
            home = _room_at(wcx, line_y - 1.0, rects) or _room_at(wcx, line_y + 1.0, rects)
        if home:
            wall_home[obj["name"]] = home

    # ---- 门墙：一个门槽**一件**组件（白盒里是左右门垛 + 门楣三块），owner = side_a ----
    door_owner = {str(d["door_key"]): str(d["side_a"]) for d in wb["doors"]}

    runtime_ids = load_runtime_ids()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # 先清掉上一轮的产物：改名（如 `f00_entry` → `f00_start`）后旧文件会残留，
    # 而残留的 tscn 仍能被 `ResourceLoader.exists()` 找到 —— 看起来"有布局"，
    # 实际指向的是旧的房间 ID，属于最难查的那种脏。
    expected_names = {
        "f00_%s_static_layout.tscn" % rid for rid in runtime_ids.values()
    }
    for stale in sorted(OUT_DIR.glob("f00_*_static_layout.tscn")):
        if stale.name not in expected_names:
            stale.unlink()
            print("  清除旧产物 %s" % stale.name)
    written = []
    for wb_key, design_key in sorted(ROOM_KEY_MAP.items(), key=lambda kv: kv[1]):
        cx, cy = centers[wb_key]
        r = rooms[wb_key]
        half_w, half_d = r["size_m"][0] / 2.0, r["size_m"][1] / 2.0
        entries = []

        # ---- 1. 地板底层 + 地砖（按房内 5m 格铺满）----
        for ix in range(int(round(r["size_m"][0] / GRID))):
            for iy in range(int(round(r["size_m"][1] / GRID))):
                lx = -half_w + GRID * (ix + 0.5)
                ly = -half_d + GRID * (iy + 0.5)
                entries.append(("floor_base_5m", ROT_ZERO, (lx, 0.0, ly), "地板底层"))
                entries.append(("floor_tile_5m", ROT_ZERO, (lx, FLOOR_BASE_TOP, ly), "地砖"))

        # ---- 2. 实墙：只放「归属本房」的那些 ----
        for obj in sorted(wb["components"], key=lambda o: o["name"]):
            if obj["kind"] != "wall" or wall_home.get(obj["name"]) != wb_key:
                continue
            dims = obj["dimensions_m"]
            lo = obj["bounds_world_m"]["min"]
            hi = obj["bounds_world_m"]["max"]
            wcx, wcy = (lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0
            height = dims[2]
            # 长轴沿世界 y ⇒ 绕 Y 转 90°，把组件长轴（Godot X）对到 Godot Z
            basis = ROT_Y90 if dims[1] > dims[0] else ROT_ZERO
            prefab = "wall_standard_5m_h12" if height > 6.0 else "wall_standard_5m_h3"
            entries.append((prefab, basis, (wcx - cx, lo[2], wcy - cy), obj["name"]))

        # ---- 3. 门墙：一个门槽一件，owner = side_a ----
        for door in wb["doors"]:
            if door_owner.get(str(door["door_key"])) != wb_key:
                continue
            axis = str(door["axis"])
            line = float(door["line_coord_m"])
            at = float(door["opening_center_m"])
            kind = str(door["kind"])
            # 🔴 `open`（通洞）**不生成任何件**。白盒里它就是纯开口，没有任何墙对象。
            # 这里曾经漏了这条分支 ⇒ open 落进下面的 else 被当成门槽，生出 6 个
            # `wall_door_5m_h3` 把 T 字路口整段砌死（走廊 → 横廊 → 两条支廊全走不通，
            # 而**不报任何错**：数量守恒按「28 门 = 28 实例」自洽，静态看也对得上）。
            if kind == "open":
                continue
            if kind == "collapse":
                prefab = "wall_collapse_5m_h12"
            else:
                height = _door_slot_height(wb, str(door["door_key"]))
                prefab = "wall_door_5m_h12" if height > 6.0 else "wall_door_5m_h3"
            if axis == "v":
                origin = (line - cx, 0.0, at - cy)
                basis = ROT_Y90                      # 门在竖墙上 ⇒ 组件转 90°
            else:
                origin = (at - cx, 0.0, line - cy)
                basis = ROT_ZERO
            entries.append((prefab, basis, origin, "门墙 %s" % str(door.get("name_zh", door["door_key"]))))

        # ---- 4. 封顶 ----
        ceiling_tiles = 0
        if design_key not in NO_CEILING:
            for ix in range(int(round(r["size_m"][0] / GRID))):
                for iy in range(int(round(r["size_m"][1] / GRID))):
                    lx = -half_w + GRID * (ix + 0.5)
                    ly = -half_d + GRID * (iy + 0.5)
                    entries.append(("ceiling_deck_5m", ROT_ZERO, (lx, CEILING_BOTTOM_Y, ly), "封顶"))
                    ceiling_tiles += 1

        counts = defaultdict(int)
        for slug, _b, _o, _n in entries:
            counts[slug] += 1

        runtime_key = runtime_ids.get(design_key, "")
        if not runtime_key:
            raise SystemExit("L2 里没有 %s 的 legacy_room_id" % design_key)
        text = _tscn(design_key, runtime_key, r, entries)
        out = OUT_DIR / f"f00_{runtime_key}_static_layout.tscn"
        out.write_bytes(text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
        written.append((out, counts, ceiling_tiles))

    # ---- 全局守恒断言：每面实墙、每个门槽都恰好出现一次 ----
    placed_walls = defaultdict(int)
    placed_doors = defaultdict(int)
    for obj in wb["components"]:
        if obj["kind"] == "wall":
            placed_walls[wall_home.get(obj["name"], "<未归属>")] += 1
    total_solid = sum(1 for o in wb["components"] if o["kind"] == "wall")
    unassigned = placed_walls.get("<未归属>", 0)
    if unassigned:
        raise SystemExit("有 %d 面实墙没有归属房间" % unassigned)
    placed_doors = defaultdict(int)
    for door in wb["doors"]:
        placed_doors[door_owner.get(str(door["door_key"]), "<未归属>")] += 1

    # ---- 门型守恒：白盒门型分布 → 实际生成的件数 ----
    # `open`（通洞）必须 **0 件** —— 它就是纯开口，白盒里没有任何墙对象。
    # 这条断言是事后补的：漏掉 open 分支时那 6 个通洞被生成成实体门墙，
    # 把 T 字路口整段砌死，而下面「门槽 28/28 已落位」照样报绿（它把自己也数进去了）。
    produced = defaultdict(int)
    for _out, counts, _tiles in written:
        for slug, n in counts.items():
            produced[slug] += n
    n_kind = Counter(str(d["kind"]) for d in wb["doors"])
    got_collapse = produced.get("wall_collapse_5m_h12", 0)
    got_door = produced.get("wall_door_5m_h3", 0) + produced.get("wall_door_5m_h12", 0)
    if got_collapse != n_kind["collapse"]:
        raise SystemExit("坍塌门洞件数 %d，白盒 %d" % (got_collapse, n_kind["collapse"]))
    if got_door != n_kind["door"]:
        raise SystemExit(
            "门墙件数 %d，白盒非 open 门 %d —— 差额通常就是「把 open 通洞也生成了墙」"
            % (got_door, n_kind["door"])
        )
    open_holes = n_kind["open"]

    print("EXPEDITION02_ROOM_SCENES_OK rooms=%d" % len(written))
    total = defaultdict(int)
    for out, counts, ceiling_tiles in written:
        for k, v in counts.items():
            total[k] += v
        print("  %-44s 实例=%-4d 封顶=%-3d %s" % (
            out.name, sum(counts.values()), ceiling_tiles,
            " ".join("%s×%d" % (k, v) for k, v in sorted(counts.items()))))
    print("合计: %s" % " ".join("%s=%d" % (k, v) for k, v in sorted(total.items())))
    print("总实例数: %d" % sum(total.values()))
    print("守恒: 实墙 %d/%d 已落位；门槽 %d/%d 已落位；通洞 %d 处（应 0 件墙）" % (
        total_solid - unassigned, total_solid,
        len(wb["doors"]) - placed_doors.get("<未归属>", 0), len(wb["doors"]), open_holes))
    print("门型守恒: door=%d collapse=%d open=%d ⇒ 门墙件 %d + 坍塌件 %d" % (
        n_kind["door"], n_kind["collapse"], open_holes, got_door, got_collapse))
    return 0


def _door_slot_height(wb, door_key):
    """该门槽的墙高（取该门任一 door_wall 件的 z 尺寸）。"""
    for obj in wb["components"]:
        if obj["kind"] == "door_wall" and str(obj.get("door_key", "")) == door_key:
            return obj["dimensions_m"][2]
    return 3.0


def _room_at(px, py, rects):
    for key, (x0, x1, y0, y1) in rects.items():
        if x0 - 1e-6 <= px <= x1 + 1e-6 and y0 - 1e-6 <= py <= y1 + 1e-6:
            return key
    return None


def _tscn(design_key, runtime_key, room, entries) -> str:
    """design_key = L2 的 key（如 `entry`）；runtime_key = 运行时房间 ID（如 `start`）。

    两者必须分开传：`NO_CEILING` 按设计 key 判（`entry` 这个房间本身不封顶），
    而写进 tscn 的 id 必须是 **runtime key** —— 它同时是 `_room_by_id` 的 key
    与文件名，写成设计 key 会让出生点静默失效。
    `metadata/room_id` 口径对齐远征01：裸 id，不带 `f00_` 前缀。
    """
    prefabs = sorted({e[0] for e in entries})
    res_index = {slug: i + 1 for i, slug in enumerate(prefabs)}
    lines = []
    lines.append("[gd_scene load_steps=%d format=3]" % (len(prefabs) + 1))
    lines.append("")
    for slug in prefabs:
        lines.append(
            '[ext_resource type="PackedScene" path="%s/%s/%s_root_top3d.tscn" id="%d_%s"]'
            % (PREFAB_ROOT, slug, slug, res_index[slug], slug)
        )
    lines.append("")
    lines.append('[node name="ExpeditionRoomStaticLayout" type="Node3D"]')
    lines.append('metadata/schema = "shellstorm2.expedition.room_static_layout.v001"')
    lines.append('metadata/room_id = "%s"' % runtime_key)
    lines.append('metadata/runtime_room_id = "%s"' % runtime_key)
    lines.append('metadata/room_key = "%s"' % design_key)
    lines.append('metadata/level_id = "%s"' % LEVEL_ID)
    lines.append('metadata/room_type = "%s"' % ROOM_TYPE.get(design_key, "COMMON_ROOM"))
    lines.append('metadata/source_mode = "whitebox_manifest_direct_extract"')
    lines.append("metadata/static_layout_only = true")
    lines.append('metadata/dynamic_runtime_owned = ["RoomDoor3D", "RoomTrigger", "RuntimeDetail", "NavigationRegion3D"]')
    lines.append("metadata/layout_instance_total = %d" % len(entries))
    lines.append("metadata/authoring_geometry_source = \"art_source/design/whitebox/tower_zones/expedition_02/v001\"")
    lines.append("metadata/authoring_generator = \"scripts/build_expedition02_room_scenes.py\"")
    lines.append("metadata/room_size_m = Vector2(%s, %s)" % (fmt(room["size_m"][0]), fmt(room["size_m"][1])))
    lines.append("metadata/ceiling_bottom_y_m = %s" % (
        "null" if design_key in NO_CEILING else fmt(CEILING_BOTTOM_Y)))
    if design_key in NO_CEILING:
        lines.append('metadata/ceiling_note = "本房不封顶（阳台安全屋按业主要求；挑高前厅是通高空间）。"')
    lines.append("")
    for index, (slug, basis, origin, note) in enumerate(entries):
        name = "%s_%03d" % (slug.upper(), index)
        lines.append(
            '[node name="%s" parent="." instance=ExtResource("%d_%s")]' % (name, res_index[slug], slug)
        )
        lines.append("transform = %s" % transform(basis, origin))
        lines.append('metadata/placement_note = "%s"' % note)
        lines.append("")
    return "\n".join(lines).rstrip("\n") + "\n"


if __name__ == "__main__":
    raise SystemExit(main())
