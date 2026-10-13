#!/usr/bin/env python3
"""生成远征关卡02 的 L1/L2 设计源（`data/level_plans/expedition_02/`）。

Run with:
    python scripts/build_expedition02_level_plan.py

## 为什么用 `mode = "authored"`

玩家 2026-10-12 定的是「几何写死」——26 间房、编号固定、几何已落白盒。查
`FloorPlanGenerator.generate_from_level_plan`：

    mode="constrained" → 几何由「L2 蓝图 + 运行种子」现算（远征01 走这条）
    mode="authored"    → floor_source 直接用 L2 的几何，**与种子无关**  ← 本关走这条

且 `runtime_enabled=true` 时运行时才消费设计源；为 false 会**回退到内置的 7 房硬编码房表**
（那是塔楼口径，与本关无关）。所以本关是 `mode=authored + runtime_enabled=true`。

## 几何与门位都是派生量，不手抄

* 房间矩形 ← 白盒 manifest（`asset_manifest.json` 的 `rooms`）
* 门位与端口 ← 白盒 manifest 的 `doors`（那些门已经过 `RoomDoorLane.lane_offsets()` 校验）

端口朝外法线口径（与远征01 的 L2 一致）：从房间中心穿过门、指向房外。
`axis='v'` 的门在 `x = line` 的竖墙上：西侧房 outward=(+1,0)，东侧房 outward=(−1,0)。
`axis='h'` 的门在 `y = line` 的横墙上：南侧房 outward=(0,+1)，北侧房 outward=(0,−1)。
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEVEL_ID = "expedition_02"
BLOCK_ID = "expedition"
WHITEBOX = (
    ROOT / "art_source/design/whitebox/tower_zones/expedition_02/v001"
    / "data/component_packages/hotel_floor_01/远征关卡02_白模_第1层_长廊与客房/asset_manifest.json"
)
OUT_ROOT = ROOT / "data/level_plans" / LEVEL_ID

GRID_UNIT = 5.0

# 白盒 key → 设计源 key（设计页 §4.2 的 26 间房编号）
KEY_MAP = {
    "balcony": "entry",
    "tall_hall": "room_01",
    "corridor": "room_02",
    "room_w1": "room_03", "room_w2": "room_04", "room_w3": "room_05",
    "room_w4": "room_06", "room_w5": "room_07",
    "room_e1": "room_08", "room_e2": "room_09", "room_e3": "room_10",
    "room_e4": "room_11", "room_e5": "room_12",
    "tee_cross": "room_13",
    "tee_west": "room_14", "tee_east": "room_15",
    "room_w6": "room_16", "room_w8": "room_17", "room_w10": "room_18",
    "room_w7": "room_19", "room_w9": "room_20",
    "room_e6": "room_21", "room_e8": "room_22", "room_e10": "room_23",
    "room_e7": "room_24", "room_e9": "room_25",
}

# 主路：南端入口 → 挑高前厅 → 长廊 → T字横廊 → 西支廊（东支廊作支线，见 L02-10）
MAIN_PATH = ["entry", "room_01", "room_02", "room_13", "room_14"]

# 父房关系（key → parent_key）
PARENT = {
    "room_01": "entry",
    "room_02": "room_01",
    "room_13": "room_02",
    "room_14": "room_13",
    "room_15": "room_13",          # 东支廊作支线（Boss/撤离将来挂其中一条，L02-10）
}
for i, wb in enumerate(["room_w1", "room_w2", "room_w3", "room_w4", "room_w5"]):
    PARENT[KEY_MAP[wb]] = "room_02"
for i, wb in enumerate(["room_e1", "room_e2", "room_e3", "room_e4", "room_e5"]):
    PARENT[KEY_MAP[wb]] = "room_02"
for wb in ["room_w6", "room_w8", "room_w10", "room_w7", "room_w9"]:
    PARENT[KEY_MAP[wb]] = "room_14"
for wb in ["room_e6", "room_e8", "room_e10", "room_e7", "room_e9"]:
    PARENT[KEY_MAP[wb]] = "room_15"

# 内容类型（主路内容房与大房间给战斗；客房给搜刮/存储/事件）
CONTENT_TYPE = {
    "room_01": "COMBAT", "room_02": "COMBAT", "room_13": "COMBAT",
    "room_14": "COMBAT", "room_15": "COMBAT",
}
_guest_types = ["SCAVENGE", "SCAVENGE", "STORAGE", "STORAGE", "EVENT"]
for index, wb in enumerate(
    ["room_w1", "room_w2", "room_w3", "room_w4", "room_w5",
     "room_e1", "room_e2", "room_e3", "room_e4", "room_e5",
     "room_w6", "room_w7", "room_w8", "room_w9", "room_w10",
     "room_e6", "room_e7", "room_e8", "room_e9", "room_e10"]
):
    CONTENT_TYPE[KEY_MAP[wb]] = _guest_types[index % len(_guest_types)]

ROLE = {"entry": "stair_entry"}
ROOM_TYPE = {"entry": "SAFE_ROOM"}

# 房间模板：6 档尺寸（本关自己的一套，见设计页 §3.1 的缺口登记）
TEMPLATES = [
    ("hotel_safe_15x15", "SAFE_ROOM", (15.0, 15.0), "阳台安全屋"),
    ("hotel_foyer_30x15", "COMMON_ROOM", (30.0, 15.0), "挑高前厅（横置）"),
    ("hotel_corridor_10x75", "COMMON_ROOM", (10.0, 75.0), "旅馆长廊"),
    ("hotel_guest_15x15", "COMMON_ROOM", (15.0, 15.0), "客房"),
    ("hotel_tee_60x10", "COMMON_ROOM", (60.0, 10.0), "T 字横廊"),
    ("hotel_branch_10x45", "COMMON_ROOM", (10.0, 45.0), "支廊"),
]


# 触发盒摆放（房内局部坐标，原点 = 房间中心）。
#
# 为什么必须有：`spawn_boxes_only=true` 时，`LevelPlanValidator._validate_spawn_boxes`
# 对每个「敌意房型」强制要求 `spawn_placements` 非空（判据来自
# `GameDesignConfig.ROOM_TYPES_WITH_HOSTILES` = COMBAT/ELITE/BOSS/TRAP/BASEMENT/STORAGE/SCAVENGE）。
# 缺了不是「不刷怪」而是**直接报错**；反过来 EVENT 房不在该表里，摆了盒会变成
# 「事件 + 战斗」双职房（业主裁定支持），所以 EVENT 房本版刻意不摆盒。
#
# 盒平面尺寸（`SpawnBoxCatalog`，size_m 是 (x, 高度, z)，平面取 x×z）：
#   box_corner_ambush 3×3 ／ box_room_spread 4×4 ／ box_corridor_column 2×4
BOX_SMALL = "box_corner_ambush"
BOX_ROOM = "box_room_spread"
BOX_COLUMN = "box_corridor_column"

SPAWN_PLACEMENTS = {
    # 挑高前厅 30×15：两个主盒分列东西，形成横向包夹。
    # 15m 宽 ⇒ 盒边离墙 = (15−4)/2 = 5.5 ≥ 5 ✓
    "room_01": [(-8.0, 0.0, BOX_ROOM), (8.0, 0.0, BOX_ROOM)],
}
# 🔴 走廊类房间**不能摆盒** —— 这是本关的一处硬冲突，见 NO_SPAWN_BOX_REASON。
NO_SPAWN_BOX_ROOMS = ["room_02", "room_13", "room_14", "room_15", "room_07", "room_12", "room_18", "room_23"]
NO_SPAWN_BOX_REASON = (
    "判据 H（LevelPlanValidator.spawn_placement_wall_recess_short）要求**盒体边缘**到房墙净距 "
    "≥ 5m（业主 2026-09-26 口径：最外一圈地砖不刷怪）。10m 宽的房间最大净距 = (10 − 盒深)/2 = 3m "
    "＜ 5m ⇒ **任何尺寸的合法盒都放不下**（盒最小 2×2，仍需房宽 ≥ 10 + 盒深）。"
    "所以长廊(10×75) / T字横廊(60×10) / 两条支廊(10×45) 四间主路房本版**没有刷怪盒**，"
    "敌人只能从相邻的 15×15 客房与 30×15 前厅涌出。"
    "要恢复「走廊里刷怪」需把走廊加宽到 ≥14m（配 4m 盒）或 ≥13m（配 3m 盒），见设计页 §13。"
)
# 15×15 客房：搜刮/存储房各一个主盒；EVENT 房不摆盒（保持纯事件房身份）。
# 15m 宽 ⇒ 盒边离墙 (15−4)/2 = 5.5 ≥ 5 ✓
for _k in ["room_03", "room_04", "room_05", "room_06",
           "room_08", "room_09", "room_10", "room_11",
           "room_16", "room_17", "room_19", "room_20",
           "room_21", "room_22", "room_24", "room_25"]:
    SPAWN_PLACEMENTS[_k] = [(0.0, 0.0, BOX_ROOM)]


def _spawn_placements_for(design_key):
    entries = SPAWN_PLACEMENTS.get(design_key)
    if not entries:
        return []
    out = []
    for index, (x, y, box_id) in enumerate(entries):
        out.append({
            "box": box_id,
            "center_m": [round(x, 4), round(y, 4)],
            "slot": index,
        })
    return out


# 入口安全屋的运行时房间 ID 必须是 `start` —— 这是远征的既有硬契约，
# `TowerDescent3D` 有三处按它取房（出生点 `_room_by_id.get("start")`、
# `get_first_safe_room_dimensions()` 的 `entry_id`、`_expedition_room_label` 的
# 「入口安全屋」标签）。写成别的值不会报错，只会**出生点静默失效**。
#
# `legacy_room_id` 同时决定两件事（见 FloorPlanGenerator 的 runtime_id 优先顺序）：
#   ① `_room_by_id` 的 key
#   ② 静态布局场景的路径 `f00_<legacy_room_id>_static_layout.tscn`
# 所以它必须与 room_instances 目录下的文件名一致。
def runtime_id(design_key: str) -> str:
    return "start" if design_key == "entry" else design_key


def vec2(v):
    return [round(float(v), 4) for v in v]


def template_for(design_key, size):
    """按房间语义 + 尺寸匹配模板 id。

    15×15 有两档同尺寸但语义不同（安全屋 / 客房），**不能只按尺寸取第一个** ——
    那样 20 间客房会全部被登记成安全屋模板（第一版就是这个错）。
    """
    if design_key == "entry":
        return "hotel_safe_15x15"
    w, h = size
    for tid, _rt, tsize, _zh in TEMPLATES:
        if tid == "hotel_safe_15x15":
            continue
        if abs(tsize[0] - w) < 1e-6 and abs(tsize[1] - h) < 1e-6:
            return tid
    raise SystemExit("没有匹配 %s 的房间模板" % str(size))


def main() -> int:
    wb = json.loads(WHITEBOX.read_text(encoding="utf-8"))
    rooms_wb = {r["key"]: r for r in wb["rooms"]}
    rects = {}
    for key, r in rooms_wb.items():
        cx, cy = r["center_m"]
        w, h = r["size_m"]
        rects[key] = dict(cx=cx, cy=cy, w=w, h=h,
                          x0=cx - w / 2, x1=cx + w / 2, y0=cy - h / 2, y1=cy + h / 2)

    # ---- 从门表派生端口 ----
    ports: dict[str, list] = {k: [] for k in rooms_wb}
    for door in wb["doors"]:
        axis = str(door["axis"])
        line = float(door["line_coord_m"])
        center = float(door["opening_center_m"])
        width = float(door["opening_width_m"])
        side_a, side_b = str(door["side_a"]), str(door["side_b"])
        if axis == "v":
            # 竖墙：侧 A 在西（x < line），侧 B 在东
            for side, outward in ((side_a, (1.0, 0.0)), (side_b, (-1.0, 0.0))):
                r = rects[side]
                ports[side].append(dict(
                    axis=axis, line=line, center=center, width=width,
                    local=[line - r["cx"], center - r["cy"]], outward=list(outward),
                ))
        else:
            # 横墙：侧 A 在南（y < line），侧 B 在北
            for side, outward in ((side_a, (0.0, 1.0)), (side_b, (0.0, -1.0))):
                r = rects[side]
                ports[side].append(dict(
                    axis=axis, line=line, center=center, width=width,
                    local=[center - r["cx"], line - r["cy"]], outward=list(outward),
                ))

    # ---- 组装 L2 房表 ----
    rooms_out = []
    for wb_key, design_key in sorted(KEY_MAP.items(), key=lambda kv: kv[1]):
        r = rects[wb_key]
        parent_wb = None
        for k, v in PARENT.items():
            if k == design_key:
                parent_wb = v
        parent_design = ""
        if parent_wb:
            parent_design = parent_wb  # PARENT 里存的已是设计源 key
        size = (r["w"], r["h"])
        tid = template_for(design_key, size)
        port_list = []
        for index, p in enumerate(sorted(ports[wb_key], key=lambda p: (p["axis"], p["line"], p["center"]))):
            # target：该门通向的房间（用端口位置反查相邻房间）
            target = _target_of(p, wb_key, rects, rooms_wb)
            port_list.append({
                "port_id": chr(ord("A") + index),
                "target": target,
                "position_m": vec2(p["local"]),
                "outward": vec2(p["outward"]),
                "door_axis": p["axis"],
                "door_line_m": round(p["line"], 4),
                "door_center_m": round(p["center"], 4),
                "door_width_m": round(p["width"], 4),
            })
        rooms_out.append({
            "key": design_key,
            "room_id": "f00_%s" % design_key,
            "legacy_room_id": runtime_id(design_key),
            "room_type": ROOM_TYPE.get(design_key, "COMMON_ROOM"),
            "role": ROLE.get(design_key, "main" if design_key in MAIN_PATH else "branch"),
            "parent_key": parent_design,
            "template_id": tid,
            "template_variant": "",
            "center_m": vec2((r["cx"], r["cy"])),
            "size_m": vec2(size),
            "template_rotation_deg": 0,
            "content_type": CONTENT_TYPE.get(design_key, ""),
            "connection_ports": port_list,
            "spawn_placements": _spawn_placements_for(design_key),
            # 🔴 走廊类房间放不下刷怪盒（见 NO_SPAWN_BOX_REASON），置 peaceful 让
            # 「必须有盒」的断言不再要求它们有盒。这不是说走廊不危险 —— 是**本版规则下
            # 走廊无法生成敌人**，只能靠相邻房涌出。改这条要改几何或改盒的离墙口径。
            "authored_layout_peaceful": design_key in NO_SPAWN_BOX_ROOMS,
        })

    floor = {
        "schema": "shellstorm2.battle.floor_plan_whitebox",
        "schema_version": 1,
        "level_id": LEVEL_ID,
        "mode": "authored",
        "floor_number": 0,
        "floor_index": 0,
        "sequence_index": 0,
        "entry_side": "south",
        "exit_side": "north",
        "reservations": [],
        "spawn_boxes_only": True,
        "geometry_authoritative": True,
        "rooms": rooms_out,
        "main_path": MAIN_PATH,
        "edge_policy": _edge_policy(rooms_out),
    }

    level_plan = _level_plan()
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "floors").mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "room_templates").mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "validation").mkdir(parents=True, exist_ok=True)

    _write(OUT_ROOT / "level_plan.json", level_plan)
    _write(OUT_ROOT / "floors/floor_00.json", floor)
    for tid, rt, tsize, zh in TEMPLATES:
        _write(OUT_ROOT / f"room_templates/{tid}.json", _template(tid, rt, tsize, zh))
    _write(OUT_ROOT / "validation/task_level_validation.json", {
        "schema": "shellstorm2.expedition.task_level_validation",
        "level_id": LEVEL_ID,
        "status": "PENDING",
        "note": "由 check_expedition_room_asset_status.py 与本生成器共同维护；运行时门禁以 Godot 侧校验器为准。",
    })

    print("EXPEDITION02_LEVEL_PLAN_OK rooms=%d templates=%d ports=%d"
          % (len(rooms_out), len(TEMPLATES), sum(len(r["connection_ports"]) for r in rooms_out)))
    return 0


def _target_of(port, owner_wb_key, rects, rooms_wb):
    """端口通向的房间：按门的位置找门另一侧的房间（共用该门线的相邻房）。"""
    r = rects[owner_wb_key]
    axis, line, center = port["axis"], port["line"], port["center"]
    if axis == "v":
        # 门在竖墙 x=line，沿 y=center 找跨过该线的房
        for key, o in rects.items():
            if key == owner_wb_key:
                continue
            if o["y0"] - 1e-6 <= center <= o["y1"] + 1e-6 and (
                abs(o["x1"] - line) < 1e-6 or abs(o["x0"] - line) < 1e-6
            ):
                return KEY_MAP[key]
    else:
        for key, o in rects.items():
            if key == owner_wb_key:
                continue
            if o["x0"] - 1e-6 <= center <= o["x1"] + 1e-6 and (
                abs(o["y1"] - line) < 1e-6 or abs(o["y0"] - line) < 1e-6
            ):
                return KEY_MAP[key]
    return ""


def _edge_policy(rooms_out):
    by_key = {r["key"]: r for r in rooms_out}
    edges = []
    for r in rooms_out:
        parent = r["parent_key"]
        if not parent:
            continue
        edges.append({
            "a": parent,
            "b": r["key"],
            "allow_zero_length": True,
            "note": "父房 %s → %s（%s）" % (parent, r["key"], by_key[r["key"]]["role"]),
        })
    return edges


def _template(tid, room_type, size, zh):
    return {
        "schema": "shellstorm2.battle.room_template_whitebox",
        "schema_version": 1,
        "template_id": tid,
        "room_type": room_type,
        "size_m": [size[0], size[1]],
        "grid_unit_m": GRID_UNIT,
        "wall_height_m": 3.0,
        "door_contract": {
            "width_m": 2.2, "height_m": 2.5, "clear_floor_gap_m": 0.0,
            "bottom_z_m": 0.3, "lintel_bottom_z_m": 2.8,
        },
        "openable_walls": ["north", "south", "east", "west"],
        "wall_lane_table": {},
        "slots": [],
        "variants": [],
        "asset_ids": {"room": "", "components": []},
        "note": (
            "远征关卡02 破败旅馆专用房型（%s）。尺寸不在 2026-09-25 锁定的 8 个模板集合里，"
            "按 05.2 §3.6 第 6 条属新增模板，已由设计页 §13 L02-5 登记。本关普通房墙高 3.0m，" 
            "顶盖底 4.0m（走面到顶盖底净高 3.70m；挑高前厅 11.9m 另算）。" % zh
        ),
    }


def _level_plan():
    return {
        "schema": "shellstorm2.battle.level_plan",
        "schema_version": 1,
        "level_id": LEVEL_ID,
        "level_name_zh": "远征关卡02",
        "block_id": BLOCK_ID,
        "floor_rule_version": 2,
        "grid_unit_m": GRID_UNIT,
        "wall_thickness_m": 0.3,
        "floor_height_m": 12.0,
        "visible_wall_height_m": 11.9,
        "hotel_wall_height_m": 3.0,
        "hotel_ceiling_bottom_m": 4.0,
        "site": {"size_m": [250.0, 250.0], "center_m": [2.5, 2.5]},
        "core": {"size_m": [65.0, 65.0], "center_m": [2.5, 2.5]},
        "floors": [{
            "floor_number": 0, "floor_index": 0, "sequence_index": 0,
            "rule": "normal", "plan": "floors/floor_00.json",
        }],
        "room_templates": [t[0] for t in TEMPLATES],
        "generation_policy": {
            "min_main_content_rooms": 3,
            "branch_count_range": [0, 40],
            "max_attempts": 1,
            "target_occupancy_ratio": 0.42,
            "reference_room_cost_m2": 1450.0,
            "enforce_core_exclusion": False,
            "enforce_area_budget": False,
            "content_type_pool": ["COMBAT", "SCAVENGE", "STORAGE", "EVENT"],
            "content_template_pool": [t[0] for t in TEMPLATES],
            "authored_layout_shell": False,
            "pin_content_templates": True,
            "runtime_enabled": True,
        },
        "provenance": {
            "mode": "authored",
            "extracted_from": "scripts/build_expedition02_level_plan.py",
            "note": (
                "远征关卡02「破败旅馆」设计源。**mode=authored ⇒ 几何写死、与种子无关**"
                "（对比远征01 的 mode=constrained：那条每局现算几何）。"
                "runtime_enabled=true 是让运行时消费本设计源的必要条件；为 false 时会回退到"
                "内置的 7 房硬编码房表（塔楼口径），与本关几何无关。"
                "房表由白盒 asset_manifest.json 派生 —— 房间矩形来自 rooms、门位与端口来自 doors，"
                "门位已过 RoomDoorLane.lane_offsets() 校验。26 间房：1 阳台 + 1 挑高前厅 + 1 长廊 + "
                "20 客房 + 1 T字横廊 + 2 支廊；主路 entry→room_01→room_02→room_13→room_14，"
                "东支廊 room_15 作支线（Boss/撤离将来挂其中一条，见设计页 L02-10）。"
                "房间模板 6 档均属新增（不在 2026-09-25 锁定的 8 个模板内），见设计页 §13 L02-5。"
            ),
        },
    }


def _write(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    path.write_bytes(text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))


if __name__ == "__main__":
    raise SystemExit(main())
