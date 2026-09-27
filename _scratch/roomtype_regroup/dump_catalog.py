"""只读：把指定组件库的 catalog 包清单摊平打印，供设计 component_family 映射用。"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(r"I:\工作项目\shellstrom2\ShellStorm2")


def main() -> None:
    lib = sys.argv[1]
    catalog_path = ROOT / "assets/art/environments/tower_zones/expedition/source/common_components" / lib / "component_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    packages = catalog["packages"]
    print(f"== {lib} ==")
    print("schema:", catalog.get("schema"), catalog.get("schema_version"))
    print("room_type:", catalog.get("room_type"), "packages:", len(packages))
    print("keys of package[0]:", sorted(packages[0].keys()))
    print()
    for p in packages:
        cid = p["component_id"]
        slug = p.get("slug", "")
        size = p.get("bounds_size_m")
        objs = p.get("objects", [])
        n = len(objs)
        coll = p.get("collection", "")
        print(f"{cid}\t{slug}\t{size}\t{objs}\t{coll}")
    print()
    # 统计对象名后缀模式
    print("== object name tails ==")
    tails = Counter()
    for p in packages:
        for o in p.get("objects", []):
            name = o if isinstance(o, str) else o.get("name", "")
            tail = name.rsplit("_", 1)[-1]
            tails[tail] += 1
    for t, c in tails.most_common(40):
        print(f"  {t}: {c}")


if __name__ == "__main__":
    main()
