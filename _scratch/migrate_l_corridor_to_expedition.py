# -*- coding: utf-8 -*-
"""把 L 型走廊从 battle 区块归属迁移到远征01。

A. 目录迁移   battle/source/room_types/l_corridor  ->  expedition/source/room_types/l_corridor
B. 结构统一   component_packages_vNNN -> component_packages ; facility -> facilities ; 散放 png -> renders/
C. 源重命名   l_corridor_room_type_vNNN.blend -> L型走廊种类_数据连廊_<尺寸>m_vNNN.blend
D. 内容改写   归属字段(block_id / room_asset_id / floor_range / 包 id 前缀) + 全部路径引用
E. 清理       删除过期 .import（改由 Godot 重新导入生成）

幂等：重复执行不会二次改名或二次替换。
所有文本改写均为字节级替换，保持 CRLF 行尾不被破坏。
"""

import json
import os
import shutil
import sys
from pathlib import Path

PROJ = Path(r"I:\工作项目\shellstrom2\ShellStorm2")
SRC = PROJ / "assets/art/environments/tower_zones/battle/source/room_types/l_corridor"
DST = PROJ / "assets/art/environments/tower_zones/expedition/source/room_types/l_corridor"

# version -> (旧 blend 名, 新 blend 名)   v001/v002 走廊宽 10m(外包络 45x35)，v003 宽 15m(45x40)
VERSIONS = {
    "v001": ("l_corridor_room_type_v001.blend", "L型走廊种类_数据连廊_45x35m_v001.blend"),
    "v002": ("l_corridor_room_type_v002.blend", "L型走廊种类_数据连廊_45x35m_v002.blend"),
    "v003": ("l_corridor_room_type_v003.blend", "L型走廊种类_数据连廊_45x40m_v003.blend"),
}

OLD_BLOCK = "tower_zones/battle/source/room_types/l_corridor"
NEW_BLOCK = "tower_zones/expedition/source/room_types/l_corridor"

ROOT_EXPR = (
    "os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "
    "*(['..'] * 9)))"
)

TEXT_EXT = {".json", ".py", ".txt"}

report = {"moved": None, "renamed_blend": [], "renamed_dir": [], "png_moved": 0,
          "import_deleted": 0, "files_rewritten": 0, "replace_hits": {}}


def log(*a):
    print(*a)


# ---------------------------------------------------------------- A. 目录迁移
if SRC.exists() and not DST.exists():
    DST.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(SRC), str(DST))
    report["moved"] = f"{SRC} -> {DST}"
    log("[A] moved", OLD_BLOCK, "->", NEW_BLOCK)
elif DST.exists():
    log("[A] already at expedition (skip)")
else:
    log("[A] !! source missing:", SRC)
    sys.exit(2)

# ------------------------------------------------- B/C. 结构统一 + 源重命名
for ver, (old_blend, new_blend) in VERSIONS.items():
    vdir = DST / ver
    if not vdir.is_dir():
        log("[!] missing version dir", vdir)
        continue

    # B1. component_packages_vNNN -> component_packages
    old_pkg = vdir / f"component_packages_{ver}"
    new_pkg = vdir / "component_packages"
    if old_pkg.is_dir() and not new_pkg.exists():
        old_pkg.rename(new_pkg)
        report["renamed_dir"].append(f"{ver}/component_packages_{ver} -> component_packages")
    pkg = new_pkg if new_pkg.is_dir() else old_pkg

    # B2. facility -> facilities
    old_fac = pkg / "facility"
    new_fac = pkg / "facilities"
    if old_fac.is_dir() and not new_fac.exists():
        old_fac.rename(new_fac)
        report["renamed_dir"].append(f"{ver}/component_packages/facility -> facilities")

    # B3. 散放 png -> renders/
    renders = vdir / "renders"
    pngs = sorted([p for p in vdir.glob("*.png")] + [p for p in vdir.glob("*.png.import")])
    if pngs:
        renders.mkdir(exist_ok=True)
        for p in pngs:
            p.rename(renders / p.name)
            if p.suffix == ".png":
                report["png_moved"] += 1

    # C. blend 重命名
    if (vdir / old_blend).exists():
        (vdir / old_blend).rename(vdir / new_blend)
        report["renamed_blend"].append(f"{ver}: {old_blend} -> {new_blend}")
    # 旧 blend 的 .import 一并清掉
    for stale in list(vdir.glob(old_blend + ".import")):
        stale.unlink()
        report["import_deleted"] += 1

    # E. 删除全部过期 .import（源路径已变，交给 Godot 重新生成）
    for imp in list(vdir.rglob("*.import")):
        imp.unlink()
        report["import_deleted"] += 1

# ------------------------------------------------------- D. 文本内容改写
SUBS = [
    # 1) 区块归属路径
    (OLD_BLOCK.encode(), NEW_BLOCK.encode()),
    # 2) 去掉原作者 macOS 绝对前缀，剩余路径即仓库相对路径
    (b"/Users/summercards/ShellStorm2/", b""),
    # 3) blend 文件名
    *[(o.encode(), n.encode("utf-8")) for o, n in VERSIONS.values()],
    # 4) 资产 id
    (b"ENV-BATTLE-LCORRIDOR-", b"ENV-EXPEDITION-L-CORRIDOR-"),
    (b"ENV-BATTLE-L-CORRIDOR-TYPE", b"ENV-EXPEDITION-L01-L-CORRIDOR"),
    # 5) 归属字段
    (b'"block_id": "battle"', b'"block_id": "expedition"'),
    (b"'block_id':'battle'", b"'block_id':'expedition'"),
    (b'"floor_range": "battle level 01 / unassigned instance"',
     b'"floor_range": "expedition 01 / unassigned instance"'),
    (b"'floor_range':'battle level 01 / unassigned instance'",
     b"'floor_range':'expedition 01 / unassigned instance'"),
    # 6) 组件包目录去版本后缀
    (b"component_packages_v001", b"component_packages"),
    (b"component_packages_v002", b"component_packages"),
    (b"component_packages_v003", b"component_packages"),
    (b"COMPONENT_PACKAGES_V001", b"component_packages"),
    (b"COMPONENT_PACKAGES_V002", b"component_packages"),
    (b"COMPONENT_PACKAGES_V003", b"component_packages"),
    # 7) 分类口径统一到远征范式（Boss 房用 facilities 复数）
    (b"/facility/", b"/facilities/"),
    # 8) 重建脚本里的 png 目标目录
    (b"V1+'/'+name", b"V1+'/renders/'+name"),
    (b"V2+'/'+name", b"V2+'/renders/'+name"),
    (b"OUT+'/'+name", b"OUT+'/renders/'+name"),
]

# 脚本 ROOT 改为按文件位置上溯 9 级，不再绑定原作者机器
import re
ROOT_RE = re.compile(rb"ROOT\s*=\s*'/Users/summercards/ShellStorm2'")


def rewrite_bytes(data: bytes) -> tuple[bytes, int]:
    hits = 0
    for old, new in SUBS:
        n = data.count(old)
        if n:
            data = data.replace(old, new)
            hits += n
    data2, k = ROOT_RE.subn(("ROOT = " + ROOT_EXPR).encode(), data)
    if k:
        data = data2
        hits += k
    return data, hits


for path in sorted(DST.rglob("*")):
    if not path.is_file() or path.suffix.lower() not in TEXT_EXT:
        continue
    raw = path.read_bytes()
    new_raw, hits = rewrite_bytes(raw)
    if hits:
        path.write_bytes(new_raw)
        report["files_rewritten"] += 1
        report["replace_hits"][str(path.relative_to(PROJ))] = hits

log()
log("=== 迁移报告 ===")
log(json.dumps(report, ensure_ascii=False, indent=2))
log()
log("TOKEN_LCORRIDOR_MIGRATE_DONE")
