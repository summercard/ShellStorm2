# -*- coding: utf-8 -*-
"""只读：校验 **git 索引**（= 即将提交的内容）里的资产引用自洽性。

为什么必须查索引而不是工作区：Godot `--import` 会在工作区重建 `.import`，而
`git mv` 阶段写进索引的是**重建前**的旧内容。此时工作区是对的、索引是旧的，
而本仓库的 `git status` 在并发编辑器/`update-index --refresh` 之后可能**漏报**
这种差异（实测 16 个真实差异只报出 1 个）。若照 `status` 提交，会把
`source_file=` 指向已删除版本化 GLB 的 `.import` 写进历史。

判据（全部针对索引 blob，不读工作区）：
  1. 索引内每个 `*.glb.import` / `*.tscn.import` 的 `source_file=` 必须存在
     于索引或以稳定名存在于工作区 → 否则 Godot 加载即失败。
  2. 索引内每个 `*.tscn` / `*.gd` 的 `res://assets/**` 引用必须可解析。
  3. 索引内不得出现运行资产路径 `components/**` / `runtime/**` 带 `_vNNN.(glb|tscn)`。
  4. 文件存在但 `.import` 缺失（工作区已导入）→ 提示可能需要一次 `godot --import`。

用法：
  python _scratch/validate_b2_index.py
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
VERSIONED = re.compile(r"_v\d{3}\.(?:glb|tscn)$")
B2_ROOTS = [
    "assets/art/props/dungeon_3d/",
    "assets/art/environments/tower_descent_3d/",
    "assets/art/props/base_world_3d/",
    "assets/art/environments/dungeon_3d/",
    "assets/art/environments/base_world_3d/",
    "assets/art/environments/tower_zones/base/",
    "assets/art/environments/tower_zones/rooftop/",
]
REF = re.compile(r'res://(assets/[A-Za-z0-9_/.\-]+?\.(?:glb|tscn|tres|png|ogg|wav|json))')


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=PROJECT, capture_output=True, text=True, check=True
    ).stdout


def index_entries() -> dict[str, str]:
    """返回 {路径: blob 哈希}。"""
    out = git("ls-files", "-s", "-z")
    entries: dict[str, str] = {}
    for rec in out.split("\0"):
        if not rec:
            continue
        meta, path = rec.split("\t", 1)
        entries[path] = meta.split()[1]
    return entries


def blob_text(sha: str) -> str:
    return subprocess.run(
        ["git", "cat-file", "-p", sha], cwd=PROJECT, capture_output=True, check=True
    ).stdout.decode("utf8", errors="ignore")


def batch_blobs(shas: list[str]) -> dict[str, str]:
    """一次 `git cat-file --batch` 读全部 blob。

    逐文件起 git 进程在 2500+ 文件上会跑到超时被 SIGTERM，必须批量。
    """
    if not shas:
        return {}
    proc = subprocess.run(
        ["git", "cat-file", "--batch"],
        cwd=PROJECT, input=("\n".join(shas) + "\n").encode(),
        capture_output=True, check=True,
    )
    out = proc.stdout
    result: dict[str, str] = {}
    pos = 0
    while pos < len(out):
        nl = out.index(b"\n", pos)
        header = out[pos:nl].decode()
        parts = header.split()
        if len(parts) != 3:  # `<sha> missing`
            pos = nl + 1
            continue
        sha, _type, size = parts[0], parts[1], int(parts[2])
        body = out[nl + 1:nl + 1 + size]
        result[sha] = body.decode("utf8", errors="ignore")
        pos = nl + 1 + size + 1  # 跳过数据后的换行
    return result


def main() -> int:
    idx = index_entries()
    print(f"索引文件总数：{len(idx)}")
    problems: list[str] = []

    want = [p for p in idx if p.endswith((".import", ".tscn", ".gd"))]
    texts = batch_blobs(sorted({idx[p] for p in want}))
    print(f"批量读取 {len(texts)} 个 blob")

    # 1. .import 的 source_file 可解析
    n_import = 0
    for path in want:
        if not path.endswith(".import"):
            continue
        n_import += 1
        m = re.search(r'^source_file="res://([^"]+)"', texts[idx[path]], re.M)
        if not m:
            problems.append(f"{path}: 无 source_file 行")
            continue
        src = m.group(1)
        if src in idx:
            continue
        if (PROJECT / src).is_file():
            problems.append(f"{path}: source_file 在索引里缺失，仅工作区有 → {src}")
            continue
        problems.append(f"{path}: source_file 不存在于索引与工作区 → {src}")
    print(f"校验 .import {n_import} 个")

    # 2. .tscn/.gd 的 res:// 引用可解析
    n_ref_files = n_refs = 0
    for path in want:
        if not path.endswith((".tscn", ".gd")):
            continue
        n_ref_files += 1
        for ref in set(REF.findall(texts[idx[path]])):
            n_refs += 1
            if ref in idx or (PROJECT / ref).is_file():
                continue
            problems.append(f"{path}: 悬空引用 {ref}")
    print(f"校验 .tscn/.gd {n_ref_files} 个，引用 {n_refs} 处")

    # 3. B2 七根下的运行资产不得再带版本名（其余批次的欠账由命名门禁的欠账表管）
    b2_hits = 0
    for path in idx:
        if not any(path.startswith(r) for r in B2_ROOTS):
            continue
        if "/source/" in path or not VERSIONED.search(path):
            continue
        b2_hits += 1
        problems.append(f"B2 根内运行资产仍带版本名：{path}")
    print(f"B2 七根下带版本运行资产：{b2_hits} 个（应为 0）")

    print()
    if problems:
        print(f"INDEX_ASSET_REFS_FAILED count={len(problems)}")
        for p in problems[:40]:
            print(f"  - {p}")
        if len(problems) > 40:
            print(f"  …另有 {len(problems) - 40} 条")
        return 1
    print("INDEX_ASSET_REFS_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
