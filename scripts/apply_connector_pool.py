#!/usr/bin/env python3
"""把 6 张骨架里的 CONNECTOR 节点从「固定 25×25 方房」改成「窄长房池」。

对应《挺进地牢》原文：

    Nodes of type connector work differently. They have their rooms picked later,
    while layout occurs. These are often long, thin rooms, so picking one with a
    sensible orientation is vital.

所以连接房**不能**在开局就定死一个模板：
- `template_id` 清空，改成 `template_pool = [connector_10x30, connector_30x10]`
- 由组装器在**布局时**按行进方向挑长轴朝向（这一步在 EgtFlowAssembler 里）

本脚本只改数据；组装器的"布局时选"是另一处改动，两处必须同时存在才成立。
幂等：重复跑不会叠加。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FLOW_DIR = ROOT / "data/level_plans/expedition_03/flows"
POOL = ["connector_10x30", "connector_30x10"]


def main() -> int:
    changed = 0
    touched_files = 0
    for path in sorted(FLOW_DIR.glob("flow_*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        dirty = False
        for node in data.get("nodes", []):
            if node.get("kind") != "CONNECTOR":
                continue
            if node.get("template_pool") == POOL and node.get("template_id") == "":
                continue
            node["template_id"] = ""
            node["template_pool"] = list(POOL)
            # size_m 交给组装器按选中的模板填；这里删掉，避免留一份会过期的副本
            node.pop("size_m", None)
            dirty = True
            changed += 1
        if dirty:
            path.write_text(
                json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            touched_files += 1
            print("updated", path.name)
    print(f"CONNECTOR_POOL_APPLIED nodes={changed} files={touched_files}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
