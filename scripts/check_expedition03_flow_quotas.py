#!/usr/bin/env python3
"""远征关卡03 的 flow 骨架门禁。

盯住三件事，任一条不成立即退出 1：

1. **房型配额与《挺进地牢》第一层逐张一一对照。** 参照表 `GUNGEON_REFERENCE`
   是从游戏本体解包出的 6 张 flow 实测节点统计（见 `docs/v0.1/design/远征关卡03设计.md` §5），
   不是从本仓库数据反推的 —— 否则改数据时参照值会跟着一起漂，门禁等于空转。
2. **树结构不变式。** 树边数 = 节点数 - 1、每个节点至多一个父房、根唯一且为 `entry`。
3. **回连边端点存在且终点已有树父房。** 回连边只做声明，不得成为某个节点的唯一入口。

运行：python3 scripts/check_expedition03_flow_quotas.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FLOW_DIR = ROOT / "data/level_plans/expedition_03/flows"

# 《挺进地牢》第一层 Keep of the Lead Lord 的 6 张 flow。
# 来源：游戏 flow 数据导出的 PDF（28 张全量）逐张节点统计，2026-10-27 解包。
# 这份表**必须独立于本仓库数据**，改动前先证明游戏数据变了。
GUNGEON_REFERENCE = {
    "flow_01": {"ENTRANCE": 1, "EXIT": 1, "BOSS_FOYER": 1, "BOSS": 1, "REWARD": 2,
                "SHOP": 1, "NORMAL": 7, "HUB": 2, "CONNECTOR": 0},
    "flow_02": {"ENTRANCE": 1, "EXIT": 1, "BOSS_FOYER": 1, "BOSS": 1, "REWARD": 2,
                "SHOP": 1, "NORMAL": 8, "HUB": 1, "CONNECTOR": 1},
    "flow_03": {"ENTRANCE": 1, "EXIT": 1, "BOSS_FOYER": 1, "BOSS": 1, "REWARD": 2,
                "SHOP": 1, "NORMAL": 7, "HUB": 2, "CONNECTOR": 1},
    "flow_04": {"ENTRANCE": 1, "EXIT": 1, "BOSS_FOYER": 1, "BOSS": 1, "REWARD": 2,
                "SHOP": 1, "NORMAL": 8, "HUB": 2, "CONNECTOR": 0},
    "flow_05": {"ENTRANCE": 1, "EXIT": 1, "BOSS_FOYER": 1, "BOSS": 1, "REWARD": 2,
                "SHOP": 1, "NORMAL": 7, "HUB": 1, "CONNECTOR": 2},
    "flow_06": {"ENTRANCE": 1, "EXIT": 1, "BOSS_FOYER": 1, "BOSS": 1, "REWARD": 2,
                "SHOP": 1, "NORMAL": 8, "HUB": 2, "CONNECTOR": 1},
}

# Gungeon 六张 flow 的房间总数（实测：16/17/17/17/17/18，平均 17.0）。
GUNGEON_NODE_TOTALS = {
    "flow_01": 16, "flow_02": 17, "flow_03": 17,
    "flow_04": 17, "flow_05": 17, "flow_06": 18,
}


def check_flow(flow_id: str, data: dict) -> list[str]:
    errors: list[str] = []
    nodes = data.get("nodes", [])
    keys = [str(n.get("node_id", "")) for n in nodes]
    if len(keys) != len(set(keys)):
        errors.append(f"{flow_id}: 节点 node_id 重复")
    if len(nodes) != GUNGEON_NODE_TOTALS[flow_id]:
        errors.append(
            f"{flow_id}: 房间数 {len(nodes)} != 游戏参照 {GUNGEON_NODE_TOTALS[flow_id]}"
        )

    actual_quota: dict[str, int] = {}
    for node in nodes:
        kind = str(node.get("kind", ""))
        actual_quota[kind] = actual_quota.get(kind, 0) + 1
    reference = GUNGEON_REFERENCE[flow_id]
    for kind, expected in sorted(reference.items()):
        got = actual_quota.get(kind, 0)
        if got != expected:
            errors.append(f"{flow_id}: {kind} 实得 {got} != 游戏参照 {expected}")
    for kind in sorted(set(actual_quota) - set(reference)):
        errors.append(f"{flow_id}: 出现游戏参照里没有的房型 {kind}")

    declared = data.get("room_quota", {})
    for kind, expected in sorted(reference.items()):
        if int(declared.get(kind, -1)) != expected:
            errors.append(f"{flow_id}: 声明的 room_quota.{kind} 与游戏参照不一致")

    tree = data.get("tree_edges", [])
    if len(tree) != len(nodes) - 1:
        errors.append(f"{flow_id}: 树边 {len(tree)} != 节点数-1 {len(nodes) - 1}")
    parent_of: dict[str, str] = {}
    key_set = set(keys)
    for edge in tree:
        a, b = str(edge.get("from", "")), str(edge.get("to", ""))
        if a not in key_set or b not in key_set:
            errors.append(f"{flow_id}: 树边引用了不存在的节点 {a}->{b}")
            continue
        if b in parent_of:
            errors.append(f"{flow_id}: 节点 {b} 有多个父房")
        parent_of[b] = a
    roots = [k for k in keys if k not in parent_of]
    if roots != ["entry"]:
        errors.append(f"{flow_id}: 根节点必须唯一且为 entry，实得 {roots}")

    for edge in data.get("loop_edges", []):
        a, b = str(edge.get("from", "")), str(edge.get("to", ""))
        if a not in key_set or b not in key_set:
            errors.append(f"{flow_id}: 回连边引用了不存在的节点 {a}->{b}")
        elif b not in parent_of:
            errors.append(f"{flow_id}: 回连边终点 {b} 没有树父房（不能成为唯一入口）")

    return errors


def main() -> int:
    if not FLOW_DIR.is_dir():
        print(json.dumps({"ok": False, "issues": [f"缺少目录 {FLOW_DIR}"]}, ensure_ascii=False, indent=2))
        return 1
    issues: list[str] = []
    seen: list[str] = []
    for path in sorted(FLOW_DIR.glob("flow_*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        flow_id = str(data.get("flow_id", path.stem))
        seen.append(flow_id)
        if flow_id not in GUNGEON_REFERENCE:
            issues.append(f"{path.name}: flow_id {flow_id} 不在游戏参照表内")
            continue
        issues.extend(check_flow(flow_id, data))
    for flow_id in sorted(set(GUNGEON_REFERENCE) - set(seen)):
        issues.append(f"缺少骨架 {flow_id}.json（游戏该层共 6 张，一张不能少）")

    total = sum(GUNGEON_NODE_TOTALS[f] for f in GUNGEON_REFERENCE)
    average = total / len(GUNGEON_NODE_TOTALS)
    print(json.dumps({
        "ok": not issues,
        "flows": len(seen),
        "node_total": total,
        "node_average": round(average, 2),
        "issues": issues,
        "limit": "只盯房型配额与树结构；不校验几何、连通可达性、内容分配或运行时行为。",
    }, ensure_ascii=False, indent=2))
    return 1 if issues else 0


if __name__ == "__main__":
    raise SystemExit(main())
