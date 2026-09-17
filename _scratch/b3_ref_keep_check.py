#!/usr/bin/env python3
"""B3 开批评据扫描（权威版，已过滤自引用）。

问：对本批每个稳定路径组，**工具保留的版本**是否就是**存活文件所指的版本**？
「存活文件」= 不在删除清单里的文件（被改名的文件仍存活，只是换了路径）。

被删文件指向被删文件（同代一起走）属正常，必须排除，否则 74 个假阳性会把真问题淹掉。

用法：python _scratch/b3_ref_keep_check.py [--all]
"""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]

spec = importlib.util.spec_from_file_location(
    "deversion_batch", PROJECT / "tools" / "asset_pipeline" / "deversion_batch.py"
)
db = importlib.util.module_from_spec(spec)
spec.loader.exec_module(db)

BATCH_NAME = "b3"
db.STRIP_DIR_VERSION = True

ROOT = PROJECT / "assets" / "art" / "environments" / "base_facility_3d"
REF = re.compile(r"res://(assets/[A-Za-z0-9_/.\-]*?_v\d{3}\.(?:glb|tscn))")
SCAN_DIRS = ["src", "tests", "tools", "scenes", "scripts"]
SCAN_SUFFIX = {".gd", ".tscn", ".py"}


def collect_refs() -> dict[str, list[tuple[str, int]]]:
    hits: dict[str, list[tuple[str, int]]] = {}
    files: list[Path] = []
    for d in SCAN_DIRS:
        base = PROJECT / d
        if base.is_dir():
            files += [
                f for f in base.rglob("*") if f.is_file() and f.suffix in SCAN_SUFFIX
            ]
    art = PROJECT / "assets" / "art"
    files += [f for f in art.rglob("*") if f.is_file() and f.suffix in (".gd", ".tscn")]
    for f in files:
        rel = f.relative_to(PROJECT).as_posix()
        if "/source/" in rel or rel == "scripts/asset_runtime_naming_debt.json":
            continue
        for i, line in enumerate(
            f.read_text(encoding="utf8", errors="replace").splitlines(), 1
        ):
            for m in REF.findall(line):
                hits.setdefault(m, []).append((rel, i))
    return hits


def main() -> int:
    batch = db.BATCHES[BATCH_NAME]
    db.STRIP_DIR_VERSION = bool(batch.get("strip_dir_version", False))
    db.PINNED = dict(batch.get("pinned", {}))
    renames, deletes = db.collect(batch)
    delete_set = set(deletes)
    rename_old = {o for o, _ in renames}

    refs_all = collect_refs()
    # 只保留「引用方本身存活」的引用
    refs: dict[str, list[tuple[str, int]]] = {}
    dropped_self = 0
    for target, sites in refs_all.items():
        live = [(f, ln) for (f, ln) in sites if f not in delete_set]
        dropped_self += len(sites) - len(live)
        if live:
            refs[target] = live

    print(f"批次 {BATCH_NAME}：重命名 {len(renames)} / 删除 {len(deletes)}")
    print(f"引用点 {sum(len(v) for v in refs_all.values())} 处，"
          f"其中来自「将被删除文件」的自引用 {dropped_self} 处已剔除，"
          f"存活引用 {sum(len(v) for v in refs.values())} 处\n")

    groups: dict[str, list[str]] = {}
    for p in sorted(ROOT.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(PROJECT).as_posix()
        if "/source/" in rel or db.BACKUP.search(p.name):
            continue
        if not db.RUN_ASSET.search(p.name):
            continue
        groups.setdefault(db.stable_path(rel), []).append(rel)

    multi = {k: v for k, v in groups.items() if len(v) > 1}
    problems = []
    for stable, members in sorted(multi.items()):
        ordered = sorted(members, key=lambda m: db.version_of(m), reverse=True)
        keep = ordered[0]
        live_refs = [m for m in members if m in refs]
        lower = [m for m in live_refs if m != keep and m in delete_set]
        if lower:
            detail: list[tuple[str, int]] = []
            for m in lower:
                detail += refs[m]
            problems.append((stable, keep, lower, detail))

    if not problems:
        print("✔ 没有「保留代 ≠ 存活引用所指代」的组。")
        return 0

    print(f"⚠️ 真风险组 {len(problems)} 个（保留代会被存活引用绕过 / 引用会静默换内容）：\n")
    for stable, keep, low, detail in problems:
        print(f"--- {stable.split('base_facility_3d/')[-1]}")
        print(f"    保留(最高代) : {keep.split('/')[-1]}  [{db.version_of(keep)}]")
        print(f"    存活引用指向 : {sorted(db.version_of(m) for m in low)}  ← 这些将被删除")
        for f, ln in sorted(set(detail)):
            print(f"        {f}:{ln}")
        print()

    if "--all" in sys.argv:
        print("\n=== 全部多成员组（含被引用的）===")
        for stable, members in sorted(multi.items()):
            if not any(m in refs for m in members):
                continue
            ordered = sorted(members, key=lambda m: db.version_of(m), reverse=True)
            print(f"  {stable.split('base_facility_3d/')[-1]}")
            for m in ordered:
                tag = "REF " if m in refs else "    "
                dead = "DEL" if m in delete_set else "KEEP"
                print(f"      {tag}{dead} {db.version_of(m):6s} {m.split('/')[-1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
