#!/usr/bin/env python3
"""生成远征关卡03 的设计源数据（flow 骨架 + 兜底样例楼层 + 关卡定义）。

本脚本只写 `data/level_plans/expedition_03/`，不触碰任何运行时代码。
房型配额与《挺进地牢》第一层 Castle 的 6 张 flow 逐张一一对照，
配额断言由 `scripts/check_expedition03_flow_quotas.py` 独立复核。

运行：python3 scripts/build_expedition03_level_plan.py
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data/level_plans/expedition_03"
SRC_TEMPLATES = ROOT / "data/level_plans/expedition_01/room_templates"

# —— 房型 → 模板 / 尺寸 ——
KIND_SPEC = {
    "ENTRANCE":   {"template_id": "safe_15x15",       "size": [15.0, 15.0], "content_type": "STAIR_LOBBY", "role": "stair_entry", "room_type": "SAFE_ROOM"},
    "EXIT":       {"template_id": "extraction_25x25", "size": [25.0, 25.0], "content_type": "EXTRACTION",  "role": "extraction",   "room_type": "EXTRACTION_ROOM"},
    "BOSS":       {"template_id": "boss_50x40",       "size": [50.0, 40.0], "content_type": "BOSS",       "role": "boss",         "room_type": "BOSS_ROOM"},
    "BOSS_FOYER": {"template_id": "std_25x25",        "size": [25.0, 25.0], "content_type": "EVENT",      "role": "boss_prep",    "room_type": "COMMON_ROOM"},
    "REWARD":     {"template_id": "db_70x50",         "size": [40.0, 30.0], "content_type": "STORAGE",    "role": "main",         "room_type": "COMMON_ROOM"},
    "SHOP":       {"template_id": "office_60x70",     "size": [30.0, 40.0], "content_type": "EVENT",      "role": "main",         "room_type": "COMMON_ROOM"},
    "NORMAL":     {"template_id": "std_25x25",        "size": [25.0, 25.0], "content_type": "COMBAT",     "role": "main",         "room_type": "COMMON_ROOM"},
    "HUB":        {"template_id": "corridor_45x40",   "size": [45.0, 40.0], "content_type": "COMBAT",     "role": "main",         "room_type": "COMMON_ROOM"},
    "CONNECTOR":  {"template_id": "std_25x25",        "size": [25.0, 25.0], "content_type": "TRAP",       "role": "main",         "room_type": "COMMON_ROOM"},
}

# 《挺进地牢》第一层 Castle 的 6 张 flow 实测配额（本机解包 10A_flow清单.csv）。
# 键 = Gungeon 原始标签；值 = 本关房型 kind 的数量。
GUNGEON_QUOTA = {
    "flow_01": {"NORMAL": 7, "HUB": 2, "REWARD": 2, "CONNECTOR": 0, "SHOP": 1,
                "BOSS_FOYER": 1, "BOSS": 1, "ENTRANCE": 1, "EXIT": 1},
    "flow_02": {"NORMAL": 8, "HUB": 1, "REWARD": 2, "CONNECTOR": 1, "SHOP": 1,
                "BOSS_FOYER": 1, "BOSS": 1, "ENTRANCE": 1, "EXIT": 1},
    "flow_03": {"NORMAL": 7, "HUB": 2, "REWARD": 2, "CONNECTOR": 1, "SHOP": 1,
                "BOSS_FOYER": 1, "BOSS": 1, "ENTRANCE": 1, "EXIT": 1},
    "flow_04": {"NORMAL": 8, "HUB": 2, "REWARD": 2, "CONNECTOR": 0, "SHOP": 1,
                "BOSS_FOYER": 1, "BOSS": 1, "ENTRANCE": 1, "EXIT": 1},
    "flow_05": {"NORMAL": 7, "HUB": 1, "REWARD": 2, "CONNECTOR": 2, "SHOP": 1,
                "BOSS_FOYER": 1, "BOSS": 1, "ENTRANCE": 1, "EXIT": 1},
    "flow_06": {"NORMAL": 8, "HUB": 2, "REWARD": 2, "CONNECTOR": 1, "SHOP": 1,
                "BOSS_FOYER": 1, "BOSS": 1, "ENTRANCE": 1, "EXIT": 1},
}

FLOW_META = {
    "flow_01": ("基础版", "StandardVariant 之前的原型：中心双路环 + 宝箱汇聚点"),
    "flow_02": ("双翼", "单个枢纽扇出两条长翼，中段用一条回连边闭合成环"),
    "flow_03": ("双路通 Boss", "中段分叉后两条路线都通向 Boss 前厅"),
    "flow_04": ("四小翼", "单个枢纽扇出四条短支路，只有一条真正通往 Boss"),
    "flow_05": ("快 Boss", "主线极短，Boss 提前；两间危险连接房挂成支链"),
    "flow_06": ("标准变体", "两路汇聚型，带一间危险连接房与一条回连边"),
}

# —— 每张 flow 的节点与边 ——
# tree 边写 (parent, child)；loop 边写 (from, to)，只做声明、不改树拓扑。
FLOWS = {
    "flow_01": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("hub_01", "HUB"),
            ("n02", "NORMAL"), ("reward_01", "REWARD"), ("n03", "NORMAL"),
            ("n04", "NORMAL"), ("n05", "NORMAL"), ("n06", "NORMAL"),
            ("reward_02", "REWARD"), ("hub_02", "HUB"), ("n07", "NORMAL"),
            ("shop", "SHOP"), ("boss_foyer", "BOSS_FOYER"), ("boss", "BOSS"),
            ("exit", "EXIT"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "hub_01"), ("hub_01", "n02"), ("n02", "reward_01"),
            ("hub_01", "n03"), ("n03", "n04"), ("n04", "reward_02"),
            ("hub_01", "n05"), ("n05", "n06"),
            ("reward_02", "hub_02"), ("hub_02", "n07"), ("n07", "shop"),
            ("shop", "boss_foyer"), ("boss_foyer", "boss"), ("boss", "exit"),
        ],
        "loop": [("n06", "reward_02")],
        "note": "宝箱房 reward_02 是一条单向环的汇聚点：两条路都走得到，但只能绕一圈。",
    },
    "flow_02": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("hub_01", "HUB"),
            ("n02", "NORMAL"), ("n03", "NORMAL"), ("reward_01", "REWARD"),
            ("n04", "NORMAL"), ("n05", "NORMAL"), ("reward_02", "REWARD"),
            ("conn_01", "CONNECTOR"), ("n06", "NORMAL"), ("n07", "NORMAL"),
            ("n08", "NORMAL"), ("shop", "SHOP"), ("boss_foyer", "BOSS_FOYER"),
            ("boss", "BOSS"), ("exit", "EXIT"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "hub_01"), ("hub_01", "n02"), ("n02", "n03"),
            ("n03", "reward_01"), ("hub_01", "n04"), ("n04", "n05"), ("n05", "reward_02"),
            ("n04", "conn_01"), ("hub_01", "n06"), ("n06", "n07"), ("n07", "n08"),
            ("n08", "shop"), ("shop", "boss_foyer"), ("boss_foyer", "boss"), ("boss", "exit"),
        ],
        "loop": [("n03", "n07")],
        "note": "两翼在中段由一条回连边闭合成环；危险连接房挂在其一翼的尾端。",
    },
    "flow_03": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("hub_01", "HUB"),
            ("n02", "NORMAL"), ("reward_01", "REWARD"), ("n03", "NORMAL"),
            ("n04", "NORMAL"), ("hub_02", "HUB"), ("n05", "NORMAL"),
            ("n06", "NORMAL"), ("shop", "SHOP"), ("n07", "NORMAL"),
            ("boss_foyer", "BOSS_FOYER"), ("boss", "BOSS"), ("exit", "EXIT"),
            ("conn_01", "CONNECTOR"), ("reward_02", "REWARD"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "hub_01"), ("hub_01", "n02"), ("n02", "reward_01"),
            ("hub_01", "n03"), ("n03", "n04"), ("n04", "hub_02"),
            ("hub_01", "n05"), ("n05", "n06"),
            ("hub_02", "shop"), ("shop", "n07"), ("n07", "boss_foyer"),
            ("hub_02", "conn_01"), ("conn_01", "reward_02"),
            ("boss_foyer", "boss"), ("boss", "exit"),
        ],
        "loop": [("n06", "hub_02")],
        "note": "两条路在 hub_02 汇聚；宝箱藏在危险连接房之后的死路里。",
    },
    "flow_04": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("hub_01", "HUB"),
            ("n02", "NORMAL"), ("reward_01", "REWARD"), ("n03", "NORMAL"),
            ("n04", "NORMAL"), ("n05", "NORMAL"), ("reward_02", "REWARD"),
            ("n06", "NORMAL"), ("n07", "NORMAL"), ("hub_02", "HUB"),
            ("n08", "NORMAL"), ("shop", "SHOP"), ("boss_foyer", "BOSS_FOYER"),
            ("boss", "BOSS"), ("exit", "EXIT"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "hub_01"),
            ("hub_01", "n02"), ("n02", "reward_01"),
            ("hub_01", "n03"), ("n03", "n04"),
            ("hub_01", "n05"), ("n05", "reward_02"),
            # n06 挂在 n03 上而不是 hub_01 上：hub_01 的门数上限是 4
            # （corridor_45x40 四面墙各一扇）。挂到 hub_01 会变成 5 门，房型承载不了。
            ("n03", "n06"), ("n06", "n07"), ("n07", "hub_02"),
            ("hub_02", "n08"), ("n08", "shop"), ("shop", "boss_foyer"),
            ("boss_foyer", "boss"), ("boss", "exit"),
        ],
        "loop": [("n04", "hub_02")],
        "note": "四条短翼扇出，只有第三条经回连边汇入 hub_02 才能推进。",
    },
    "flow_05": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("hub_01", "HUB"),
            ("conn_01", "CONNECTOR"), ("n02", "NORMAL"), ("reward_01", "REWARD"),
            ("n03", "NORMAL"), ("n04", "NORMAL"), ("conn_02", "CONNECTOR"),
            ("n05", "NORMAL"), ("reward_02", "REWARD"), ("n06", "NORMAL"),
            ("shop", "SHOP"), ("n07", "NORMAL"), ("boss_foyer", "BOSS_FOYER"),
            ("boss", "BOSS"), ("exit", "EXIT"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "hub_01"),
            ("hub_01", "conn_01"), ("conn_01", "n02"), ("n02", "reward_01"),
            ("hub_01", "n03"), ("n03", "n04"),
            ("hub_01", "conn_02"), ("conn_02", "n05"), ("n05", "reward_02"),
            ("n04", "n06"), ("n06", "shop"), ("shop", "n07"),
            ("n07", "boss_foyer"), ("boss_foyer", "boss"), ("boss", "exit"),
        ],
        "loop": [("n05", "n06")],
        "note": "主线极短、Boss 提前；两间危险连接房各领一条宝箱支链。",
    },
    "flow_06": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("hub_01", "HUB"),
            ("n02", "NORMAL"), ("reward_01", "REWARD"), ("n03", "NORMAL"),
            ("n04", "NORMAL"), ("conn_01", "CONNECTOR"), ("n05", "NORMAL"),
            ("n06", "NORMAL"), ("hub_02", "HUB"), ("n07", "NORMAL"),
            ("n08", "NORMAL"), ("shop", "SHOP"), ("reward_02", "REWARD"),
            ("boss_foyer", "BOSS_FOYER"), ("boss", "BOSS"), ("exit", "EXIT"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "hub_01"), ("hub_01", "n02"), ("n02", "reward_01"),
            ("hub_01", "n03"), ("n03", "n04"), ("n04", "conn_01"),
            ("hub_01", "n05"), ("n05", "n06"), ("n06", "hub_02"),
            ("hub_02", "n07"), ("n07", "n08"), ("n08", "shop"),
            ("shop", "reward_02"), ("reward_02", "boss_foyer"),
            ("boss_foyer", "boss"), ("boss", "exit"),
        ],
        "loop": [("n04", "n06")],
        "note": "两路汇聚型；危险连接房是一条死路，回连边让另一路汇入。",
    },
}

TEMPLATE_POOL_NORMAL = ["corridor_45x40", "db_70x50", "office_60x70", "std_25x25"]

# 每类房型能承载的**最大门数**。按四面墙算：一个门占一面墙的一个 lane，
# 本关不出现同面墙开两门的房（那是走廊式布局，不在本关设计里）。
# 超出即数据错误 —— 房间承载不了，装配期会出现「门开在实墙上」或门洞互相重叠。
MAX_DOORS_BY_KIND = {
    "ENTRANCE": 2,     # 前门 + 弃局门
    "EXIT": 1,
    "BOSS": 2,
    "BOSS_FOYER": 2,
    "REWARD": 3,       # db_70x50 四面墙，最多 3 门（其中一面留给墙饰）
    "SHOP": 2,
    "NORMAL": 3,       # std_25x25 四面墙，最多 3 门
    "HUB": 4,          # corridor_45x40 是 L 形，四面墙各一扇 —— 硬上限 4
    "CONNECTOR": 2,
}

# —— 注入规则（Gungeon 口径）——
INJECTIONS = [
    {
        "inject_id": "inj_secret_room",
        "kind": "SECRET_ROOM",
        "anchor_policy": "dead_end_first",
        "anchor_fallback_policy": "any_room",
        "anchor_fallback_probability": 0.2,
        "probability": 0.9,
        "scope": "shared",
        "condition": {},
        "note": "普通隐藏房。90% 出现；优先挂死胡同，1/5 概率挂到任意房间。",
    },
    {
        "inject_id": "inj_npc_secret_room",
        "kind": "NPC_SECRET_ROOM",
        "anchor_policy": "run_level_preroll",
        "probability": 0.2,
        "scope": "run",
        "condition": {},
        "note": "NPC 隐藏房。**开局抽一次**并预留给将来某一层，EMPTY 权重 0.8；与普通隐藏房互不占用。",
    },
    {
        "inject_id": "inj_fireplace",
        "kind": "FIREPLACE_ROOM",
        "anchor_policy": "dead_end_first",
        "probability": 1.0,
        "scope": "shared",
        "condition": {},
        "note": "壁炉房（藏层入口）。每层 1 间，优先死胡同。",
    },
]


def validate_flow(flow_id: str, spec: dict) -> None:
    nodes = [n for n, _ in spec["nodes"]]
    keys = set(nodes)
    assert len(nodes) == len(keys), f"{flow_id}: 节点 key 重复"
    kind_count: dict[str, int] = {}
    for _, kind in spec["nodes"]:
        kind_count[kind] = kind_count.get(kind, 0) + 1
    want = GUNGEON_QUOTA[flow_id]
    for kind, count in want.items():
        got = kind_count.get(kind, 0)
        assert got == count, f"{flow_id}: {kind} 期望 {count} 实得 {got}"
    assert not (set(kind_count) - set(want)), f"{flow_id}: 出现未登记房型 {set(kind_count) - set(want)}"
    tree = spec["tree"]
    assert len(tree) == len(nodes) - 1, f"{flow_id}: 树边 {len(tree)} != 节点数-1 {len(nodes) - 1}"
    parents: dict[str, str] = {}
    for parent, child in tree:
        assert parent in keys and child in keys, f"{flow_id}: 树边引用了不存在的节点"
        assert child not in parents, f"{flow_id}: 节点 {child} 有多个父房"
        parents[child] = parent
    roots = [n for n in nodes if n not in parents]
    assert roots == ["entry"], f"{flow_id}: 根节点必须是唯一的 entry，实得 {roots}"
    for parent, child in spec["loop"]:
        assert parent in keys and child in keys, f"{flow_id}: 回连边引用了不存在的节点"
        assert child in parents, f"{flow_id}: 回连边的终点 {child} 必须已有树父房"

    # —— 门数上限：每类房型的四面墙容量 ———
    degree: dict[str, int] = {}
    for parent, child in list(spec["tree"]) + list(spec["loop"]):
        degree[parent] = degree.get(parent, 0) + 1
        degree[child] = degree.get(child, 0) + 1
    kind_of = dict(spec["nodes"])
    for key, doors in degree.items():
        limit = MAX_DOORS_BY_KIND[kind_of[key]]
        assert doors <= limit, (
            f"{flow_id}: {key}({kind_of[key]}) 有 {doors} 门，超过房型上限 {limit}"
        )


def build_flow_file(flow_id: str) -> dict:
    spec = FLOWS[flow_id]
    validate_flow(flow_id, spec)
    zh, feature = FLOW_META[flow_id]
    parents = {child: parent for parent, child in spec["tree"]}
    nodes = []
    for key, kind in spec["nodes"]:
        entry = {
            "node_id": key,
            "kind": kind,
            "template_id": KIND_SPEC[kind]["template_id"],
            "size_m": KIND_SPEC[kind]["size"],
            "parent_node_id": parents.get(key, ""),
        }
        if kind == "NORMAL":
            entry["template_pool"] = TEMPLATE_POOL_NORMAL
            entry["template_id"] = ""
        nodes.append(entry)
    return {
        "schema": "shellstorm2.battle.dungeon_flow",
        "schema_version": 1,
        "level_id": "expedition_03",
        "flow_id": flow_id,
        "flow_name_zh": zh,
        "design_feature": feature,
        "node_count": len(nodes),
        "room_quota": dict(sorted(GUNGEON_QUOTA[flow_id].items())),
        "nodes": nodes,
        "tree_edges": [{"from": a, "to": b, "kind": "tree"} for a, b in spec["tree"]],
        "loop_edges": [{"from": a, "to": b, "kind": "loop"} for a, b in spec["loop"]],
        "injections": INJECTIONS,
        "design_note": spec["note"],
    }


def pack_geometry(flow: dict) -> list[dict]:
    """把 flow_01 的树摆成不重叠的墙贴墙版图（兜底样例用，确定性）。

    贪心：BFS 展开，子房依次尝试东/南/西/北四个方向贴着父房摆放，
    命中第一个不与已摆房间相交、且中心落在 5m 相位的槽位。
    """
    by_id = {n["node_id"]: n for n in flow["nodes"]}
    parent_of = {e["to"]: e["from"] for e in flow["tree_edges"]}
    children: dict[str, list[str]] = {}
    for child, parent in parent_of.items():
        children.setdefault(parent, []).append(child)

    placed: dict[str, dict] = {}
    entry = by_id["entry"]
    placed["entry"] = {
        "center": (2.5, 2.5), "size": tuple(entry["size_m"]), "node": entry,
    }
    dirs = [("east", (1, 0)), ("south", (0, 1)), ("west", (-1, 0)), ("north", (0, -1))]

    def overlaps(cx, cy, w, h) -> bool:
        for item in placed.values():
            ox, oy = item["center"]
            ow, oh = item["size"]
            if abs(cx - ox) < (w + ow) / 2 - 1e-6 and abs(cy - oy) < (h + oh) / 2 - 1e-6:
                return True
        return False

    def phase_ok(value: float, size: float) -> bool:
        return abs(((value - size / 2.0) / 5.0) - round((value - size / 2.0) / 5.0)) < 1e-6

    queue = ["entry"]
    while queue:
        current = queue.pop(0)
        for child in children.get(current, []):
            node = by_id[child]
            w, h = node["size_m"]
            parent = placed[current]
            px, py = parent["center"]
            pw, ph = parent["size"]
            slot = None
            for _, (dx, dy) in dirs:
                if dx:
                    cx = px + dx * (pw / 2 + w / 2)
                    for shift in (0.0, 2.5, -2.5, 5.0, -5.0, 7.5, -7.5):
                        cy = py + shift
                        if phase_ok(cx, w) and phase_ok(cy, h) and not overlaps(cx, cy, w, h):
                            slot = (cx, cy)
                            break
                else:
                    cy = py + dy * (ph / 2 + h / 2)
                    for shift in (0.0, 2.5, -2.5, 5.0, -5.0, 7.5, -7.5):
                        cx = px + shift
                        if phase_ok(cx, w) and phase_ok(cy, h) and not overlaps(cx, cy, w, h):
                            slot = (cx, cy)
                            break
                if slot:
                    break
            if not slot:
                raise RuntimeError(f"兜底样例摆不下：{child} 无可用槽位")
            placed[child] = {"center": slot, "size": (w, h), "node": node}
            queue.append(child)
    return placed


def longest_path(flow: dict) -> list[str]:
    """入口到出口的最长树路径 —— 即"主路"。分支天然不在其中。"""
    parent_of = {e["to"]: e["from"] for e in flow["tree_edges"]}
    children: dict[str, list[str]] = {}
    for child, parent in parent_of.items():
        children.setdefault(parent, []).append(child)
    best: list[str] = []

    def walk(node: str, trail: list[str]) -> None:
        nonlocal best
        trail = trail + [node]
        if node == "exit":
            if len(trail) > len(best):
                best = trail
            return
        if not children.get(node):
            return
        for child in children[node]:
            walk(child, trail)

    walk("entry", [])
    return best


def build_floor_file(flow: dict) -> dict:
    placed = pack_geometry(flow)
    parent_of = {e["to"]: e["from"] for e in flow["tree_edges"]}
    rooms = []
    for node in flow["nodes"]:
        key = node["node_id"]
        spec = KIND_SPEC[node["kind"]]
        cx, cy = placed[key]["center"]
        room = {
            "key": key,
            "room_id": key,
            "legacy_room_id": key,
            "room_type": spec["room_type"],
            "role": spec["role"],
            "parent_key": parent_of.get(key, ""),
            "template_id": spec["template_id"],
            "center_m": [round(cx, 2), round(cy, 2)],
            "size_m": spec["size"],
            "template_rotation_deg": 0,
            "content_type": spec["content_type"],
        }
        rooms.append(room)
    return {
        "schema": "shellstorm2.battle.floor_plan",
        "schema_version": 1,
        "level_id": "expedition_03",
        "mode": "flow",
        "floor_number": 0,
        "floor_index": 0,
        "sequence_index": 0,
        "entry_side": "east",
        "exit_side": "west",
        "reservations": [],
        "rooms": rooms,
        "main_path": longest_path(flow),
        "edge_policy": [
            {"a": a, "b": b, "allow_zero_length": True, "note": "flow_01 兜底样例：墙贴墙"}
            for a, b in [(e["from"], e["to"]) for e in flow["tree_edges"]]
        ],
        "provenance": {
            "mode": "flow_fallback_sample",
            "generated_by": "scripts/build_expedition03_level_plan.py",
            "note": "本文件是 flow_01 的展开兜底样例，仅用于生成器失败回退与文档对照；实跑版图由 flow 骨架按种子现算。",
        },
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "flows").mkdir(exist_ok=True)
    (OUT / "floors").mkdir(exist_ok=True)
    (OUT / "room_templates").mkdir(exist_ok=True)

    for flow_id in sorted(FLOWS):
        data = build_flow_file(flow_id)
        (OUT / "flows" / f"{flow_id}.json").write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    fallback = build_floor_file(build_flow_file("flow_01"))
    (OUT / "floors" / "floor_00.json").write_text(
        json.dumps(fallback, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    for name in [
        "safe_15x15", "extraction_25x25", "boss_50x40", "std_25x25",
        "db_70x50", "office_60x70", "corridor_45x40", "bridge_60x50",
    ]:
        shutil.copyfile(SRC_TEMPLATES / f"{name}.json", OUT / "room_templates" / f"{name}.json")

    level_plan = {
        "schema": "shellstorm2.battle.level_plan",
        "schema_version": 1,
        "level_id": "expedition_03",
        "level_name_zh": "远征关卡03",
        "block_id": "expedition",
        "floor_rule_version": 3,
        "grid_unit_m": 5.0,
        "wall_thickness_m": 0.3,
        "floor_height_m": 12.0,
        "visible_wall_height_m": 11.9,
        "site": {"size_m": [250.0, 250.0], "center_m": [2.5, 2.5]},
        "core": {"size_m": [65.0, 65.0], "center_m": [2.5, 2.5]},
        "floors": [
            {"floor_number": 0, "floor_index": 0, "sequence_index": 0,
             "rule": "normal", "plan": "floors/floor_00.json"}
        ],
        "flow_plans": [
            {"flow_id": f"flow_0{i}", "path": f"flows/flow_0{i}.json",
             "room_count": len(FLOWS[f"flow_0{i}"]["nodes"])}
            for i in range(1, 7)
        ],
        "room_templates": [
            "safe_15x15", "extraction_25x25", "boss_50x40", "std_25x25",
            "db_70x50", "office_60x70", "corridor_45x40", "bridge_60x50",
        ],
        "generation_policy": {
            "mode": "flow",
            "min_main_content_rooms": 8,
            "branch_count_range": [0, 6],
            "max_attempts": 12,
            "target_occupancy_ratio": 0.42,
            "reference_room_cost_m2": 1450.0,
            "enforce_core_exclusion": False,
            "enforce_area_budget": False,
            "content_type_pool": ["COMBAT", "TRAP", "STORAGE", "SCAVENGE", "EVENT"],
            "content_template_pool": ["corridor_45x40", "db_70x50", "office_60x70", "std_25x25"],
            "authored_layout_shell": False,
            "pin_content_templates": False,
            "randomize_room_templates": True,
            "flow_pick": "seeded_uniform",
            "runtime_enabled": False,
        },
        "provenance": {
            "mode": "flow",
            "extracted_from": "scripts/build_expedition03_level_plan.py",
            "note": "远征关卡03「骨架随机」设计源。**mode=flow ⇒ 每局先按种子抽一张 flow 骨架，再走注入与复合对象拼装**；floors/floor_00.json 只是 flow_01 的展开兜底样例。runtime_enabled=false：flow 模式生成器与关卡场景尚未施工，本关卡暂不可从选关菜单进入。房型配额逐张对照《挺进地牢》第一层 Castle 的 6 张 flow，断言见 scripts/check_expedition03_flow_quotas.py。",
        },
    }
    (OUT / "level_plan.json").write_text(
        json.dumps(level_plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote {OUT}")
    for flow_id in sorted(FLOWS):
        print(f"  {flow_id}: {len(FLOWS[flow_id]['nodes'])} rooms, "
              f"{len(FLOWS[flow_id]['tree'])} tree edges, {len(FLOWS[flow_id]['loop'])} loop edges")


if __name__ == "__main__":
    main()
