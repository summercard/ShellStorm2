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
#
# ## 拓扑真源
#
# 边的连法以 `docs/v0.1/reference/挺进地牢/flows_img/F1_Castle_*.png` **原图**为准，
# 门数（度数）以 `第一层房间位清单.csv` 的逐房间位记录为准。两者互补：
# 原图给"谁连谁"，CSV 给"每间几个门"。`EXPECTED_DEGREES` 是 CSV 的抄本，
# `validate_flow()` 逐张比对 —— 抄错一位就报错，不会静默漂移。
#
# ## 旧版错在哪（2026-10-28 修）
#
# 旧拓扑是**按房型配额表凑出来的**（"NORMAL 7 个、HUB 2 个"对得上就收工），
# 边怎么连是随手画的。后果是门数分布整体偏移，其中两处是功能错误：
#
# | 问题 | 后果 |
# |---|---|
# | CONNECTOR 被接成叶子（1 门，8/28 处） | EGT 的 connector 是**穿堂**窄长房；1 门就成了一间空房间的尽头 |
# | flow_01 / flow_02 各少 1 个环 | 这两个变体叫 TwoPathsToBoss / TwoBigWings，"双路"就是它们的全部意义 |
# | SHOP 被串在 main line 上 | EGT 的 shop 是**支线末端**（多数 1 门），不是必经之路 |
# | HUB 有 2 处 2 门 | HUB 的定义就是 "larger rooms with more exits"，2 门等于普通房 |
FLOWS = {
    "flow_01": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("n02", "NORMAL"),
            ("hub_01", "HUB"), ("n03", "NORMAL"), ("n04", "NORMAL"),
            ("reward_01", "REWARD"), ("reward_02", "REWARD"),
            ("hub_02", "HUB"), ("n05", "NORMAL"), ("n06", "NORMAL"),
            ("n07", "NORMAL"), ("shop", "SHOP"), ("boss_foyer", "BOSS_FOYER"),
            ("boss", "BOSS"), ("exit", "EXIT"),
        ],
        # 主干：入口 → 三岔枢纽 → 一支直落宝箱 → 折回第二枢纽 → 两翼 → 首领
        "tree": [
            ("entry", "n01"), ("n01", "n02"), ("n02", "hub_01"),
            ("hub_01", "n03"), ("n03", "reward_01"),
            ("hub_01", "n04"), ("n04", "hub_02"), ("n04", "boss_foyer"),
            ("boss_foyer", "boss"), ("boss", "exit"),
            ("hub_02", "n05"), ("n05", "n06"), ("n06", "reward_02"),
            ("hub_02", "n07"), ("n07", "shop"),
        ],
        # 两条长回连弧：宝箱房绕回主干上游（与原图一致的两条弧）
        "loop": [("reward_01", "n01"), ("reward_02", "hub_02")],
        "note": (
            "中心双路环 + 两个宝箱汇聚点。宝箱房 reward_01 / reward_02 各有一条回连弧"
            "接回上游，绕一圈才能拿到 —— 与参考原图的两条弧位置一致。"
            "商店挂在第二枢纽的死路支上（1 门）。"
        ),
    },
    "flow_02": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("n08", "NORMAL"),
            ("n02", "NORMAL"), ("n03", "NORMAL"), ("shop", "SHOP"),
            ("n04", "NORMAL"), ("reward_01", "REWARD"), ("conn_01", "CONNECTOR"),
            ("n05", "NORMAL"), ("hub_01", "HUB"), ("n06", "NORMAL"),
            ("reward_02", "REWARD"), ("n07", "NORMAL"),
            ("boss_foyer", "BOSS_FOYER"), ("boss", "BOSS"), ("exit", "EXIT"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "n08"), ("n08", "n02"), ("n02", "n03"),
            ("n03", "shop"), ("shop", "n04"), ("n04", "reward_01"),
            ("n02", "conn_01"), ("conn_01", "n05"),
            ("n05", "hub_01"), ("hub_01", "n06"), ("n06", "reward_02"),
            ("n05", "n07"), ("n07", "boss_foyer"),
            ("boss_foyer", "boss"), ("boss", "exit"),
        ],
        "loop": [("reward_01", "n03"), ("reward_02", "hub_01")],
        "note": (
            "单个岔点扇出两条长翼，每翼各带一个闭环（2 环，与参考一致）。"
            "连接房是**穿堂**（2 门）接在右翼入口处。"
        ),
    },
    "flow_03": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("n02", "NORMAL"),
            ("conn_01", "CONNECTOR"), ("hub_01", "HUB"), ("shop", "SHOP"),
            ("n03", "NORMAL"), ("reward_01", "REWARD"), ("n04", "NORMAL"),
            ("hub_02", "HUB"), ("n05", "NORMAL"), ("n06", "NORMAL"),
            ("n07", "NORMAL"), ("reward_02", "REWARD"),
            ("boss_foyer", "BOSS_FOYER"), ("boss", "BOSS"), ("exit", "EXIT"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "n02"), ("n02", "conn_01"),
            ("conn_01", "hub_01"), ("hub_01", "shop"),
            ("n02", "n03"), ("n03", "reward_01"),
            ("n01", "n04"), ("n04", "hub_02"),
            ("hub_02", "n05"), ("n05", "n07"),
            ("n07", "boss_foyer"), ("boss_foyer", "boss"), ("boss", "exit"),
            ("hub_02", "n06"), ("n06", "reward_02"),
        ],
        # 左支枢纽回连到主干末段 —— 两条路都通 Boss 前厅
        "loop": [("hub_01", "n07")],
        "note": (
            "中段分叉后两条路线都通向 Boss 前厅。左侧经连接房进枢纽再回连，"
            "右侧直落。两侧各有一间单门宝箱房（死胡同）。"
        ),
    },
    "flow_04": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("hub_01", "HUB"),
            ("n02", "NORMAL"), ("n03", "NORMAL"), ("n04", "NORMAL"),
            ("n05", "NORMAL"), ("reward_01", "REWARD"),
            ("hub_02", "HUB"), ("boss_foyer", "BOSS_FOYER"),
            ("n06", "NORMAL"), ("reward_02", "REWARD"),
            ("n07", "NORMAL"), ("n08", "NORMAL"), ("shop", "SHOP"),
            ("boss", "BOSS"), ("exit", "EXIT"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "hub_01"),
            ("hub_01", "n02"), ("n02", "n03"), ("n03", "hub_02"),
            ("hub_01", "n04"), ("n04", "reward_01"),
            ("hub_01", "n05"),
            ("hub_02", "boss_foyer"), ("boss_foyer", "boss"), ("boss", "exit"),
            ("hub_02", "n06"), ("n06", "reward_02"),
            ("hub_02", "n07"), ("n07", "n08"), ("n08", "shop"),
        ],
        # 商店绕回第二枢纽 —— 这是全层唯一的 **5 门枢纽房**
        "loop": [("shop", "hub_02")],
        "note": (
            "四条短翼扇出。第二枢纽 `hub_02` 是**全层唯一的 5 门房**"
            "（上游 1 + 首领前厅 1 + 两翼 2 + 商店回连 1），与参考 §5.2 一致。"
            "四面墙开不出第 5 个门，所以它必须允许**同侧双门**。"
            "`n05` 是单门死胡同（参考里 4 个 1 门战斗房之一）。"
        ),
    },
    "flow_05": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("n06", "NORMAL"),
            ("n02", "NORMAL"), ("hub_01", "HUB"),
            ("boss_foyer", "BOSS_FOYER"), ("boss", "BOSS"), ("exit", "EXIT"),
            ("n03", "NORMAL"), ("shop", "SHOP"), ("conn_01", "CONNECTOR"),
            ("n04", "NORMAL"), ("reward_01", "REWARD"),
            ("n05", "NORMAL"), ("conn_02", "CONNECTOR"),
            ("n07", "NORMAL"), ("reward_02", "REWARD"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "n06"), ("n06", "n02"), ("n02", "hub_01"),
            ("hub_01", "boss_foyer"), ("boss_foyer", "boss"), ("boss", "exit"),
            ("hub_01", "n03"), ("n03", "shop"),
            ("n03", "conn_01"), ("conn_01", "n04"), ("n04", "reward_01"),
            # ⚠️ conn_02 挂在**链尾**（n05 → n07 → conn_02），不挂枢纽。
            # 两个连接房都挂枢纽时，它们会挤在枢纽同一侧（45×40 的房周围空间有限），
            # 环闭合的走廊只能从其中一个身上穿过去 —— 实测 8/120 局 `room_overlap`。
            ("hub_01", "n05"), ("n05", "n07"), ("n07", "conn_02"),
            ("conn_02", "reward_02"),
        ],
        # 两条宝箱支链在连接房之后闭合（n04 与 n05 之间一条回连）
        "loop": [("n04", "n05")],
        "note": (
            "主线极短、Boss 提前（参考里的 QuickBoss）：枢纽直接扇出首领前厅。"
            "两个连接房都是**穿堂**，各领一条宝箱支链，支链末端回到主干形成闭环。"
            "商店是单门死路，挂在左支的岔点之后。"
        ),
    },
    "flow_06": {
        "nodes": [
            ("entry", "ENTRANCE"), ("n01", "NORMAL"), ("n02", "NORMAL"),
            ("hub_01", "HUB"), ("n03", "NORMAL"), ("n04", "NORMAL"),
            ("n05", "NORMAL"), ("reward_01", "REWARD"), ("n06", "NORMAL"),
            ("hub_02", "HUB"), ("boss_foyer", "BOSS_FOYER"),
            ("n07", "NORMAL"), ("n08", "NORMAL"), ("reward_02", "REWARD"),
            ("conn_01", "CONNECTOR"), ("shop", "SHOP"),
            ("boss", "BOSS"), ("exit", "EXIT"),
        ],
        "tree": [
            ("entry", "n01"), ("n01", "n02"), ("n02", "hub_01"),
            ("hub_01", "n03"), ("n03", "n04"), ("n03", "n05"),
            ("n04", "reward_01"),
            ("hub_01", "n06"), ("n06", "hub_02"),
            ("hub_02", "boss_foyer"), ("boss_foyer", "boss"), ("boss", "exit"),
            ("hub_02", "n07"), ("n07", "n08"), ("n08", "reward_02"),
            ("hub_02", "conn_01"), ("conn_01", "shop"),
        ],
        # 右下宝箱绕回左侧第二枢纽
        "loop": [("reward_02", "n06")],
        "note": (
            "两路汇聚型。`n05` 是单门死胡同战斗房；连接房是穿堂，末端接单门商店。"
            "右侧支链的宝箱回连到左路，形成闭环。"
        ),
    },
}

# —— 权威门数序列（`第一层房间位清单.csv` 的 F1 六张逐条抄本）——
#
# 每张一个多重集：`{门数: 房间数}`。校验时按**多重集**比对而非逐序号——
# CSV 的序号只是列举顺序，不对应图的左右位置；能约束住的是"这一层有多少个
# 1 门房、多少 2 门房"，而这恰好就是房型语言的分布。
#
# 为什么必须要这条断言：旧拓扑按房型配额凑出来，房型计数全对、门数分布全错，
# 而当时**没有任何断言看门数**（只看了"房型配额"和"上限"）。分布是功能属性：
# 单门房是死胡同、2 门是穿堂、3 门以上是岔点，配错了整层的通行节奏就变了。
EXPECTED_DEGREES = {
    "flow_01": {1: 3, 2: 9, 3: 3, 4: 1},
    "flow_02": {1: 2, 2: 11, 3: 4},
    "flow_03": {1: 5, 2: 7, 3: 5},
    "flow_04": {1: 5, 2: 10, 4: 1, 5: 1},
    "flow_05": {1: 5, 2: 8, 3: 3, 4: 1},
    "flow_06": {1: 5, 2: 9, 3: 3, 4: 1},
}

# 每类房型的**门数语义区间**（硬约束，超出即数据错误）。
#
# 这些不是"墙上有几个 lane"的物理上限（那个由模板 `wall_lane_table` 决定），
# 而是**房型定义**：HUB 就是"多出口的大房"，1~2 门的 HUB 是普通房冒充；
# CONNECTOR 是**穿堂**，1 门就成了尽头（旧版 8/28 处正是这个错）。
DOOR_RANGE_BY_KIND = {
    "ENTRANCE": (1, 1),   # 链的一端
    "EXIT": (1, 1),       # 链的另一端
    "BOSS": (2, 2),       # 进、出各一
    "BOSS_FOYER": (2, 2),  # 同上
    "REWARD": (1, 2),     # 单门宝箱 = 死胡同（"绕一圈才能拿到"的载体）
    "SHOP": (1, 2),       # 支线末端，不串在主干上
    "NORMAL": (1, 3),
    "HUB": (3, 5),        # "larger rooms with more exits"
    "CONNECTOR": (2, 3),  # 穿堂；3 门允许"丁字穿堂"
    # 注入房：单门挂在死胡同（隐藏房 / 壁炉房）
    "SECRET_ROOM": (1, 1),
    "NPC_SECRET_ROOM": (1, 1),
    "FIREPLACE_ROOM": (1, 1),
}

TEMPLATE_POOL_NORMAL = ["corridor_45x40", "db_70x50", "office_60x70", "std_25x25"]
# 连接房池：同一「窄长房」的横竖两向。房间不支持运行时旋转，长轴方向只能由
# 两份模板表达，布局时按行进方向二选一。
TEMPLATE_POOL_CONNECTOR = ["connector_10x30", "connector_30x10"]

GRID = 5.0


def lane_offsets(length_m: float) -> list[float]:
    """与 `src/map/RoomDoorLane.gd::lane_offsets()` 同源。

    3 格以上的墙首尾各留一格（所以 3 格墙只有 1 个槽、2 格墙反而有 2 个）。
    这个非单调性踩过一次：按公式反解最小格数会产出"3 格墙放 2 扇门"的坏房。
    """
    count = max(1, round(length_m / GRID))
    first = 1 if count >= 3 else 0
    last = count - 2 if count >= 3 else count - 1
    return [-length_m * 0.5 + GRID * (i + 0.5) for i in range(first, last + 1)]


def _connector_template(tid: str, w: float, d: float, note: str) -> dict:
    """窄长连接房模板。门槽表由 `lane_offsets()` 直接算，不手抄数字。"""
    return {
        "schema": "shellstorm2.battle.room_template_whitebox",
        "schema_version": 1,
        "template_id": tid,
        "room_type": "COMMON_ROOM",
        "size_m": [w, d],
        "grid_unit_m": GRID,
        "wall_height_m": 2.8,
        "door_contract": {
            "width_m": 2.2,
            "height_m": 2.5,
            "clear_floor_gap_m": 0.0,
            "bottom_z_m": 0.3,
            "lintel_bottom_z_m": 2.8,
        },
        "openable_walls": ["north", "south", "east", "west"],
        "wall_lane_table": {
            "north": lane_offsets(w),
            "south": lane_offsets(w),
            "east": lane_offsets(d),
            "west": lane_offsets(d),
        },
        "slots": [],
        "variants": [],
        "asset_ids": {
            "room": "ENV-EXPEDITION-L01-ROOM-CONN-%gX%g" % (w, d),
            "components": [],
        },
        "note": note,
    }


CONNECTOR_TEMPLATES = [
    _connector_template(
        "connector_10x30", 10.0, 30.0,
        "窄长连接房 · 长轴沿南北（z）。对应《挺进地牢》CONNECTOR 房型："
        "\"often long, thin rooms, so picking one with a sensible orientation is vital\"。"
        "10×30 = 2×6 格，长宽比 3.0。南北两面各 2 个合法门槽，东西两面各 4 个。"
        "与 connector_30x10 成对：布局时按行进方向挑长轴朝向。白盒原型，未进场景账本。",
    ),
    _connector_template(
        "connector_30x10", 30.0, 10.0,
        "窄长连接房 · 长轴沿东西（x）。与 connector_10x30 同一房型的旋转变体 —— "
        "本工程房间不支持运行时旋转（尺寸轴对齐），长轴方向必须由两份模板表达。"
        "30×10 = 6×2 格，长宽比 3.0。东西两面各 2 个合法门槽，南北两面各 4 个。"
        "白盒原型，未进场景账本。",
    ),
]

# 每类房型能承载的**最大门数**。按四面墙算：一个门占一面墙的一个 lane，
# 本关不出现同面墙开两门的房（那是走廊式布局，不在本关设计里）。
# 超出即数据错误 —— 房间承载不了，装配期会出现「门开在实墙上」或门洞互相重叠。
MAX_DOORS_BY_KIND = {
    "ENTRANCE": 2,     # 前门 + 弃局门
    "EXIT": 1,
    "BOSS": 2,
    "BOSS_FOYER": 2,
    # ⚠️ 这三项旧值是 4，把 flow_04 那个 **5 门枢纽**顶掉了（参考 §5.2 全层唯一一处）。
    # 上限一度按「四面墙各一扇」算 —— 但**同一面墙可以开两扇门**：
    # `RoomShellLayoutBuilder3D` 的 `doors` 已支持每侧给数组（同侧多门），
    # 组装器的 `_commit_port()` 也是 append，所以 45m 的墙完全放得下 2 扇。
    # 现在按「房型语义」定上限（见 `DOOR_RANGE_BY_KIND`），物理可行性交给模板的 lane 表。
    "REWARD": 3,       # db_70x50 四面墙，最多 3 门（其中一面留给墙饰）
    "SHOP": 2,
    "NORMAL": 3,       # std_25x25 四面墙，最多 3 门
    "HUB": 5,          # 5 门枢纽需要同侧双门：corridor_45x40 的长墙够放 2 扇
    "CONNECTOR": 3,    # 穿堂 2 门；丁字穿堂 3 门
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
        kind = kind_of[key]
        assert doors <= MAX_DOORS_BY_KIND[kind], (
            f"{flow_id}: {key}({kind}) 有 {doors} 门，超过房型上限 {MAX_DOORS_BY_KIND[kind]}"
        )
        # 语义下界：房型定义本身就规定了门数区间，不是靠上限就够。
        # HUB 少于 3 门就不是枢纽、CONNECTOR 少于 2 门就不是穿堂 —— 这两种
        # 在上限检查里都"合法"，但都破坏玩法（旧版 8/28 个单门 connector 就是这么漏过去的）。
        low, high = DOOR_RANGE_BY_KIND[kind]
        assert low <= doors <= high, (
            f"{flow_id}: {key}({kind}) 有 {doors} 门，超出房型语义区间 [{low}, {high}]"
        )

    # —— 门数分布必须与参考 CSV 的多重集一致 ——
    # 这条是"房型语言"的整体校验：单门房是死胡同、2 门是穿堂、3 门以上是岔点。
    # 逐房间对不上无所谓（CSV 序号不对应图的左右），但**分布**必须对上。
    actual: dict[int, int] = {}
    for doors in degree.values():
        actual[doors] = actual.get(doors, 0) + 1
    expected = EXPECTED_DEGREES[flow_id]
    assert actual == expected, (
        f"{flow_id}: 门数分布 {dict(sorted(actual.items()))} 与参考 "
        f"{dict(sorted(expected.items()))} 不一致"
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
        elif kind == "CONNECTOR":
            # 连接房是**窄长房**，且**布局时才选**（长轴要沿行进方向）——
            # 《挺进地牢》原文："Nodes of type connector work differently. They have
            # their rooms picked later, while layout occurs. These are often long,
            # thin rooms, so picking one with a sensible orientation is vital."
            # 所以这里给池子而不是固定 id；选哪一个由 EgtFlowAssembler 在放置时决定。
            entry["template_id"] = ""
            entry["template_pool"] = TEMPLATE_POOL_CONNECTOR
            # size_m 由被选中的模板决定，不留副本以免过期
            entry.pop("size_m", None)
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
    # —— key 与运行时 id 是两套命名（与 FloorPlanGenerator._generate_flow_floor 同口径）——
    # 运行时按 **key** 要 `entry` + `room_01`（否则 `_build_expedition_records()` 直接拒绝启动），
    # 玩家出生点却按**运行时 id** 要 `start`（否则玩家停在原点悬空）。
    # 少任何一条，这份兜底样例都会让整层起不来 —— 而它恰恰只在"生成失败"时才被用到，
    # 属于平时验不到的那条路。
    first_main = ""
    for edge in flow["tree_edges"]:
        if edge["from"] == "entry":
            first_main = edge["to"]
            break
    key_alias = {}
    runtime_id_alias = {}
    if first_main:
        key_alias[first_main] = "room_01"
        runtime_id_alias[first_main] = "room_01"
    runtime_id_alias["entry"] = "start"
    rooms = []
    for node in flow["nodes"]:
        key = node["node_id"]
        spec = KIND_SPEC[node["kind"]]
        cx, cy = placed[key]["center"]
        room = {
            "key": key_alias.get(key, key),
            "room_id": runtime_id_alias.get(key, key),
            "legacy_room_id": "",
            "room_type": spec["room_type"],
            "role": spec["role"],
            "parent_key": key_alias.get(parent_of.get(key, ""), ""),
            "template_id": spec["template_id"],
            "center_m": [round(cx, 2), round(cy, 2)],
            "size_m": spec["size"],
            "template_rotation_deg": 0,
            "content_type": spec["content_type"],
        }
        rooms.append(room)

    # 兜底样例也必须满足运行时的两套命名约定，否则"生成失败时退回样例"这条路等于没有
    # —— 它平时不会被走到，坏了也发现不了，只有真出事那天才表现为"关卡打不开"。
    keys = {r["key"] for r in rooms}
    ids = {r["room_id"] for r in rooms}
    assert "entry" in keys, "兜底样例缺少 key=entry（运行时拒绝启动）"
    assert "room_01" in keys, "兜底样例缺少 key=room_01（运行时拒绝启动）"
    assert "start" in ids, "兜底样例缺少运行时 id=start（玩家会停在原点悬空）"
    return {
        # 与其余三个关卡一致：floor 计划的 schema 带 `_whitebox` 后缀。
        # 漏了后缀 `LevelPlanLoader.load_floor_plan()` 会直接判空（它做严格相等比较），
        # 于是这份设计源从来没有被读过一次 —— flow 模式因此一直"读不到 floor_00.json"。
        "schema": "shellstorm2.battle.floor_plan_whitebox",
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
        template = json.loads((SRC_TEMPLATES / f"{name}.json").read_text(encoding="utf-8"))
        template["wall_height_m"] = 2.8  # Expedition03 does not inherit expedition01 wall height.
        (OUT / "room_templates" / f"{name}.json").write_text(
            json.dumps(template, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    # 窄长连接房是本关**独有**的（远征01 的模板池里没有），所以由这里直接生成，
    # 而不是从 SRC_TEMPLATES 拷 —— 否则源码与数据会各说一套。
    for tpl in CONNECTOR_TEMPLATES:
        (OUT / "room_templates" / f"{tpl['template_id']}.json").write_text(
            json.dumps(tpl, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

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
        "visible_wall_height_m": 2.8,
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
            # 窄长连接房（横竖两向）。不登记的话门槽表不会被加载，运行时必红。
            "connector_10x30", "connector_30x10",
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
            # —— 两个开关都要开，缺一不可 ——
            # `runtime_enabled`：`FloorPlanGenerator.data_driven_enabled()` 读它，
            #   决定是否走 `generate_from_level_plan()`（否则回退内置房表）。
            # `flow_assembly_enabled`：`_generate_flow_floor()` 读它，
            #   决定 flow 模式是否真去抽骨架+组装（否则读 L2 里那份静态样例）。
            #
            # 打开不会破坏存档：远征03 是**新关卡**，此前没有任何一局能进入
            # （场景不存在、runtime_enabled=false），因此不存在旧 `layout_id` 需要兼容。
            # 05.2 §9 的 D4 约束的是「把既有关卡切到数据驱动」，不适用于新关卡。
            "runtime_enabled": True,
            "flow_assembly_enabled": True,
        },
        "provenance": {
            "mode": "flow",
            "extracted_from": "scripts/build_expedition03_level_plan.py",
            "note": "远征关卡03「骨架随机」设计源。**mode=flow ⇒ 每局先按种子抽一张 flow 骨架，再走注入与复合对象拼装**；floors/floor_00.json 只是兜底样例，实际几何由 EgtFlowAssembler + EgtPlanBridge 在开局时按种子算。拓扑逐条对照《挺进地牢》第一层 Castle 的 6 张 flow 原图，门数分布逐张对照 第一层房间位清单.csv（见 EXPECTED_DEGREES 断言）。",
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
