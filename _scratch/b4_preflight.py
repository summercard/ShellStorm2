# -*- coding: utf-8 -*-
"""B4 删除安全预检：确认「删除清单」里的每一条都不被任何存活文件引用。

判据：
  - 把删除清单（165 项）作为「将消失」集合；
  - 全仓扫所有文本文件的 res:// 引用；
  - 命中删除集合、且引用方**不在**删除集合内 = 真·悬空（必须为 0）；
  - 引用方也在删除集合内 = 自洽死岛（可删）。
另附 .gitignore 白名单对齐清单。
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

PROJECT = Path(".").resolve()
R = "assets/art/environments/rooftop_shelter_3d/"

# 删除清单 = obsolete_globs 展开（与 deversion_batch.py 的 b4 定义一致）
OBSOLETE_GLOBS = [
    R + "runtime/env_rooftop_shelter_50m_game_v*",
    R + "runtime/env_rooftop_shelter_90x80m_game_v*",
    R + "runtime/env_rooftop_shelter_90x80m_root_top3d_v*",
    R + "runtime/layout_v016/**/*",
]

doomed: set[str] = set()
for pat in OBSOLETE_GLOBS:
    for p in PROJECT.glob(pat):
        if p.is_file():
            doomed.add(p.relative_to(PROJECT).as_posix())

print(f"删除清单 = {len(doomed)} 项")

# ---- 1) 全仓文本扫描 res:// 引用 ----
out = subprocess.run(
    ["git", "grep", "-n", "-I", "-E", r"res://[A-Za-z0-9_/.\-]+"],
    capture_output=True, text=True, encoding="utf-8", errors="replace",
).stdout

REF = re.compile(r"res://([A-Za-z0-9_/.\-]+)")
hits: dict[str, list[tuple[str, int]]] = {}
for line in out.splitlines():
    m = re.match(r"([^:]+):(\d+):(.*)", line)
    if not m:
        continue
    f, ln, txt = m.group(1), int(m.group(2)), m.group(3)
    for target in REF.findall(txt):
        if target in doomed:
            hits.setdefault(target, []).append((f, ln))

print(f"\n=== 删除项被引用的（按引用方是否也在删除清单内分类）===")
dangling: list[tuple[str, str, int]] = []
self_consistent: list[tuple[str, str, int]] = []
for target, refs in sorted(hits.items()):
    for f, ln in refs:
        (self_consistent if f in doomed else dangling).append((target, f, ln))

print(f"\n[A] 真·悬空（引用方存活 → 必须为 0）：{len(dangling)}")
for t, f, ln in dangling[:40]:
    print(f"    {f}:{ln}\n        -> res://{t}")

print(f"\n[B] 自洽死岛（引用方也在删除清单内）：{len(self_consistent)}")
by_file: dict[str, int] = {}
for t, f, ln in self_consistent:
    by_file[f] = by_file.get(f, 0) + 1
for f, n in sorted(by_file.items()):
    print(f"    {f}  ({n} 处)")

# ---- 2) 删除项中无人引用者 ----
never = sorted(doomed - set(hits))
print(f"\n[C] 完全无人引用的删除项：{len(never)}")
for t in never[:10]:
    print(f"    {t}")
if len(never) > 10:
    print(f"    ...（共 {len(never)}）")

# ---- 3) .gitignore 白名单对齐 ----
gi = (PROJECT / ".gitignore").read_text(encoding="utf-8").splitlines()
print(f"\n=== .gitignore rooftop 白名单逐行判定 ===")
for i, line in enumerate(gi, 1):
    if "rooftop" not in line:
        continue
    s = line.strip()
    if not s.startswith("!"):
        continue
    pat = s[1:]
    if pat.endswith("/**/*.glb.import"):
        base = pat[: -len("/**/*.glb.import")]
        alive = [
            p for p in PROJECT.glob(base + "/**/*.glb.import")
            if p.is_file()
        ]
        verdict = f"目录存活（{len(alive)} 个 .import）→ 保留（B4 会随目录改名）"
    else:
        tgt = PROJECT / pat
        alive = tgt.is_file()
        verdict = "目标在盘 → 改动/改名" if alive else "目标将删 → 删该行"
    print(f"  L{i:<4} {pat}\n         {verdict}")

print(f"\nRESULT: 真悬空={len(dangling)}  （必须为 0 才可安全删除）")
