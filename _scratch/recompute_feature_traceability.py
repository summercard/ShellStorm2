# -*- coding: utf-8 -*-
"""复算 check_feature_traceability 的 37 项红：验证是不是 Windows 路径分隔符口径问题。

scripts/check_feature_traceability.py 用 str(resolved.relative_to(root)) 收集 MODULE_INDEX
的设计链接，在 Windows 上产出反斜杠；而 feature_registry.json 存的是正斜杠 ⇒ 恒不匹配。
本脚本用 Path.as_posix() 归一化后重算，若为 0 则确证红项与内容无关。
"""

import json
import re
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(".").resolve()
INDEX = ROOT / "docs/v0.1/MODULE_INDEX.md"
REGISTRY = ROOT / "docs/v0.1/feature_registry.json"


def module_rows_posix():
    rows = {}
    for line in INDEX.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\| ([A-Z0-9]+(?:-[A-Z0-9]+)+) \|", line)
        if m is None:
            continue
        fid = m.group(1)
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 6:
            continue
        paths = set()
        for target in re.findall(r"\]\(([^)]+)\)", cells[2]):
            t = unquote(target.split("#", 1)[0].strip("<> "))
            if not t or re.match(r"[a-z]+://", t):
                continue
            resolved = (INDEX.parent / t).resolve()
            try:
                paths.add(resolved.relative_to(ROOT).as_posix())
            except ValueError:
                pass
        rows[fid] = paths
    return rows


def module_rows_native():
    """复刻门禁脚本原样（Windows 反斜杠）。"""
    rows = {}
    for line in INDEX.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\| ([A-Z0-9]+(?:-[A-Z0-9]+)+) \|", line)
        if m is None:
            continue
        fid = m.group(1)
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) != 6:
            continue
        paths = set()
        for target in re.findall(r"\]\(([^)]+)\)", cells[2]):
            t = unquote(target.split("#", 1)[0].strip("<> "))
            if not t or re.match(r"[a-z]+://", t):
                continue
            resolved = (INDEX.parent / t).resolve()
            try:
                paths.add(str(resolved.relative_to(ROOT)))
            except ValueError:
                pass
        rows[fid] = paths
    return rows


reg = json.loads(REGISTRY.read_text(encoding="utf-8"))
native = module_rows_native()
posix = module_rows_posix()

bad_native = []
bad_posix = []
for e in reg["features"]:
    fid = e["feature_id"]
    want = set(e.get("design_docs", []))
    if native.get(fid) != want:
        bad_native.append(fid)
    if posix.get(fid) != want:
        bad_posix.append(fid)

print("features =", len(reg["features"]))
print("原样（反斜杠）不匹配数   =", len(bad_native))
print("归一化 as_posix 后不匹配数 =", len(bad_posix))
if bad_posix:
    print("  仍不匹配:", bad_posix)
print("TOKEN_FEATURE_TRACEABILITY_RECOMPUTE_DONE")
