# -*- coding: utf-8 -*-
"""补丁：把 L 型走廊组件包对共享库的过期引用改到 shared 库现有 id。

shared 库（tower_zones/shared/source/common_components/v001/component_catalog.json）
已把这批共用件从 battle 命名空间抽出，component_id 改用 ENV-SHARED-GENERIC-*，
旧的 ENV-BATTLE-COMMON-* 只作为 source_package_id 历史来源保留。
"""

from pathlib import Path

DST = Path(r"I:\工作项目\shellstrom2\ShellStorm2"
           r"\assets\art\environments\tower_zones\expedition\source\room_types\l_corridor")

SUBS = [
    (b"ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01", b"ENV-SHARED-GENERIC-FLOOR-TILE-R01-C01"),
    (b"ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02", b"ENV-SHARED-GENERIC-FLOOR-TILE-R01-C02"),
    (b"ENV-BATTLE-COMMON-WALL-STANDARD-5M", b"ENV-SHARED-GENERIC-WALL-STANDARD-5M"),
    (b"ENV-BATTLE-COMMON-WALL-DOOR-5M", b"ENV-SHARED-GENERIC-WALL-DOOR-5M"),
    (b"ENV-BATTLE-COMMON-DOOR-5M", b"ENV-SHARED-GENERIC-DOOR-5M"),
]

files = 0
hits = 0
for path in sorted(DST.rglob("*.json")):
    raw = path.read_bytes()
    new = raw
    n = 0
    for old, rep in SUBS:
        c = new.count(old)
        if c:
            new = new.replace(old, rep)
            n += c
    if n:
        path.write_bytes(new)
        files += 1
        hits += n

print("files_rewritten =", files)
print("hits =", hits)
print("TOKEN_LCORRIDOR_SHARED_ID_PATCH_DONE")
