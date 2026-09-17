# -*- coding: utf-8 -*-
"""B4 权威盘点：environments/rooftop_shelter_3d 的全部带版本运行资产分组 + 引用归属。"""
from __future__ import annotations

import collections
import json
import os
import re
import subprocess

R = "assets/art/environments/rooftop_shelter_3d/"
ROOT = "assets/art/environments/rooftop_shelter_3d"
VER = re.compile(r"_v(\d{3})")


def strip(n: str) -> str:
    m = VER.search(n)
    return n[: m.start()] + n[m.end():] if m else n


def ver(n: str) -> str:
    m = VER.search(n)
    return m.group(1) if m else "----"


def main() -> None:
    d = json.load(open("scripts/asset_runtime_naming_debt.json", encoding="utf-8"))
    fs = sorted(f for f in d["versioned_files"] if f.startswith(R))
    out = subprocess.run(["git", "ls-files", "-z", "--", R], capture_output=True).stdout
    tracked = {x for x in out.decode("utf-8").split("\0") if x}

    print("总债务文件 =", len(fs))
    print("tracked =", sum(1 for f in fs if f in tracked), " untracked =", sum(1 for f in fs if f not in tracked))
    print("\n=== 未跟踪（gitignore 白名单未覆盖）===")
    for f in fs:
        if f not in tracked:
            print("   ", f)

    print("\n=== 按 (目录, 剥版本后基名) 分组 ===")
    groups: dict[str, list[str]] = collections.OrderedDict()
    for f in fs:
        n = os.path.basename(f)
        key = os.path.dirname(f) + " ## " + strip(n.replace(".import", ""))
        groups.setdefault(key, []).append(f)
    for k, v in groups.items():
        vs = sorted({ver(os.path.basename(x)) for x in v})
        tag = "MULTI" if len(vs) > 1 else "one  "
        print(f"  [{tag}] {k}  -> {vs}  ({len(v)})")

    print("\n=== 版本目录统计 ===")
    print("债务快照 versioned_dirs =", d.get("versioned_dirs"))
    vd = []
    for dp, dns, _ in os.walk(ROOT):
        for dn in dns:
            if re.fullmatch(r"v\d{3}", dn):
                vd.append(os.path.join(dp, dn).replace(os.sep, "/"))
    print("实扫 ^vNNN$ 目录 =", vd)

    print("\n=== 全仓引用（排除本根 + 债务快照 + .gitignore）===")
    names = sorted({os.path.basename(f) for f in fs if not f.endswith(".import")})
    pat = "|".join(re.escape(n) for n in names)
    res = subprocess.run(["git", "grep", "-n", "-E", pat], capture_output=True, text=True,
                         encoding="utf-8", errors="replace").stdout
    ext = collections.defaultdict(list)
    for line in res.splitlines():
        m = re.match(r"([^:]+):(\d+):(.*)", line)
        if not m:
            continue
        f, ln, txt = m.groups()
        if f.startswith(R) or f.endswith("asset_runtime_naming_debt.json") or f == ".gitignore":
            continue
        for n in names:
            if n in txt:
                ext[n].append((f, ln))
    for n in sorted(ext):
        print(f"  {n}")
        for f, ln in ext[n][:8]:
            print(f"      {f}:{ln}")
    print("\n无任何外部引用的目标数 =", sum(1 for n in names if n not in ext))


if __name__ == "__main__":
    main()
