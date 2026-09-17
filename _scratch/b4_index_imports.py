# -*- coding: utf-8 -*-
"""B4 暂存完整性：逐个 `.import` 核对「暂存索引内容 == 工作树内容」，
并断言其 `source_file=` 指向的文件真实存在（防 B2 缺陷 1：--import 重建后
未 git add，暂存区仍是旧内容、source_file 指向已删的 _vNNN 文件）。

只读暂存区与工作树。用法：python _scratch/b4_index_imports.py

⚠️ 踩坑记录（B3/B4 各踩一次）：`git cat-file --batch` **不接受 `:path`**，
必须先 `git ls-files -s` 取 SHA。且 blob 内容用 `--batch` 解析时 size 是**字节数**
不是行数，按行 join 会错位。故此处改用「索引 SHA vs `git hash-object <path>`」直比，
`.import` 已在 `.gitattributes` 钉 `text eol=lf`，工作树即 LF，hash 可比。
"""
from __future__ import annotations
import re
import subprocess
from pathlib import Path

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
ROOT = "assets/art/environments/rooftop_shelter_3d/"


def git(*args, inp=None):
    return subprocess.run(["git", "-C", str(PROJECT), *args],
                          capture_output=True, input=inp,
                          text=True, encoding="utf-8", errors="replace")


def main() -> int:
    out = git("ls-files", "-s", "-z", "--", ROOT).stdout
    idx = {}
    for e in [x for x in out.split("\0") if x]:
        meta, path = e.split("\t", 1)
        idx[path] = meta.split()[1]

    imports = sorted(p for p in idx if p.endswith(".import"))
    print(f"B4 根内暂存 .import 数 = {len(imports)}")

    # 工作树批量取 hash（一次调用，避免逐文件 fork）
    rel = [p for p in imports if (PROJECT / p).is_file()]
    r = git("hash-object", "--stdin-paths", inp="\n".join(rel) + "\n")
    disk_sha = dict(zip(rel, r.stdout.splitlines()))

    stale, vanished, missing, noref = [], [], [], []
    for p in imports:
        if p not in disk_sha:
            vanished.append(p)
            continue
        if disk_sha[p] != idx[p]:
            stale.append(p)
        txt = (PROJECT / p).read_text(encoding="utf-8", errors="replace")
        m = re.search(r'source_file="res://([^"]+)"', txt)
        if not m:
            noref.append((p, "无 source_file"))
            continue
        tgt = m.group(1)
        if not (PROJECT / tgt).is_file():
            missing.append((p, tgt))

    print(f"\n[1] 工作树缺失（索引有、磁盘无） = {len(vanished)}")
    for p in vanished:
        print("   ", p)
    print(f"\n[2] 暂存内容 != 工作树（陈旧暂存） = {len(stale)}")
    for p in stale:
        print("   ", p)
    print(f"\n[3] source_file 指向不存在文件 = {len(missing)}")
    for p, t in missing:
        print(f"    {p}\n        -> {t}")
    print(f"\n[4] 无 source_file 段 = {len(noref)}")
    for p, why in noref:
        print(f"    {p}  ({why})")

    ok = not (vanished or stale or missing or noref)
    print("\nB4_IMPORT_INDEX_OK" if ok else "\nB4_IMPORT_INDEX_FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
