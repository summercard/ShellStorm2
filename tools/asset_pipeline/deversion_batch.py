#!/usr/bin/env python3
"""去版本化批次迁移：把 Godot 运行资产收成稳定路径（执行计划 §4.1 的批次工具）。

规则：`components/`、`runtime/` 下的运行资产文件名与目录名不含版本号。
- 同名资产多版本并存（后缀式版本）      → 保留最高版本，其余删除
- 带版本目录整树（如 `entry_safe_room/v007/<slug>/`） → 只保留指定版本，其余整树删除
- 稳定化 = 去掉文件名里的 `_vNNN`、去掉路径里的 `vNNN/` 段
- `.glb` 与其 `.import` 同步改名；改名后的 `.tscn` 内部 `res://` 引用同步改写

默认 `--plan` 只打印计划，不做任何改动。`--apply-renames` / `--apply-deletes` 才动手，
两者都走 `git mv` / `git rm`，历史由 git 承担。

用法：
  python3 tools/asset_pipeline/deversion_batch.py b1 --plan
  python3 tools/asset_pipeline/deversion_batch.py b1 --apply-renames
  python3 tools/asset_pipeline/deversion_batch.py b1 --apply-deletes
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
ART = PROJECT / "assets" / "art"

VERSION_SUFFIX = re.compile(r"_v(\d{3})(?=\.)")
VERSION_DIR = re.compile(r"^v(\d{3})$")
RUN_ASSET = re.compile(r"_v\d{3}\.(?:glb|tscn)(?:\.(?:import|uid))?$")
BACKUP = re.compile(r"\.bak_")

BATCHES: dict[str, dict] = {
    "b1": {
        "label": "战局区块 battle（common_components + entry_safe_room）",
        "root": "assets/art/environments/tower_zones/battle",
        # 子树 → 策略
        "rules": {
            "components/common_components": {"mode": "collapse"},
            "runtime/common_components": {"mode": "collapse"},
            "components/entry_safe_room": {"mode": "keep_version", "version": "v007"},
            "runtime/entry_safe_room": {"mode": "keep_version", "version": "v007"},
        },
        "excluded": [
            "assets/art/environments/tower_zones/base/runtime/zone_base_v002.tscn"
            "（zone 场景、非 <slug> 粒度；引用方 TowerDescent3D.gd 正在被併行会话改动）→ 转 B2",
            "assets/art/environments/tower_zones/rooftop/runtime/zone_rooftop_v021.tscn → 转 B2",
        ],
    },
}


def stable_name(name: str) -> str:
    return VERSION_SUFFIX.sub("", name, count=1)


def stable_path(rel: str) -> str:
    parts = [p for p in rel.split("/") if not VERSION_DIR.match(p)]
    parts[-1] = stable_name(parts[-1])
    return "/".join(parts)


def version_of(rel: str) -> str:
    m = VERSION_SUFFIX.search(Path(rel).name)
    if m:
        return "v" + m.group(1)
    for part in rel.split("/"):
        if VERSION_DIR.match(part):
            return part
    return ""


def collect_leftovers(batch: dict) -> list[str]:
    """第二步（重命名之后）的删除清单：批根下**仍然带版本**的运行资产。

    与 collect() 分开是必要的：重命名之后，`<slug>_v003.glb` 的稳定名已被上一步
    的 `<slug>_v004.glb` 占据；若还用「保留最高版本」的逻辑重算，会把 `v003` 当成
    更高版本、反过来删掉刚改名成功的文件。

    第二步只认两条：
      A. 稳定名已存在 → 删带版本的那个（同资产多版本的旧版）
      B. 落在非保留版本的整树目录里（`<套件>/vNNN/...` 且 vNNN ≠ 规则保留版本）→ 整树删
    """
    root = PROJECT / batch["root"]
    # 整树删除范围：keep_version 规则子树 <path>，保留版本 <version>
    tree_rules = [
        (sub, rule["version"])
        for sub, rule in batch["rules"].items()
        if rule["mode"] == "keep_version"
    ]
    deletes: list[str] = []
    for p in sorted(root.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(PROJECT).as_posix()
        if rel in batch.get("excluded", []):
            continue
        if BACKUP.search(p.name):
            if "/source/" not in rel:
                deletes.append(rel)
            continue
        if not RUN_ASSET.search(p.name):
            continue

        # B：整树目录（非保留版本）
        version_dir_hit = False
        for sub, keep in tree_rules:
            prefix = f"{batch['root']}/{sub}/"
            if not rel.startswith(prefix):
                continue
            head = rel[len(prefix):].split("/")[0]
            if VERSION_DIR.match(head) and head != keep:
                version_dir_hit = True
        if version_dir_hit:
            deletes.append(rel)
            continue

        stable = stable_path(rel)
        if stable == rel:
            continue  # 已经是稳定名
        if not (PROJECT / stable).is_file():
            raise SystemExit(
                f"{rel} 仍是带版本命名，但稳定路径 {stable} 不存在，也不在整树删除范围内——"
                f"说明重命名还没做完或规则有漏，先跑 --apply-renames 并检查 BATCHES 规则。"
            )
        deletes.append(rel)
    return sorted(set(deletes))


def collect(batch: dict) -> tuple[list[tuple[str, str]], list[str]]:
    """返回 (rename_pairs, delete_relpaths)。"""
    root = PROJECT / batch["root"]
    renames: list[tuple[str, str]] = []
    deletes: list[str] = []

    for sub, rule in batch["rules"].items():
        base = root / sub
        if not base.is_dir():
            continue
        # 收集该子树下所有带版本运行资产
        owned: dict[str, list[Path]] = {}
        for p in sorted(base.rglob("*")):
            if not p.is_file():
                continue
            if BACKUP.search(p.name):
                continue
            if not RUN_ASSET.search(p.name):
                continue
            if rule["mode"] == "keep_version" and version_of(str(p.relative_to(PROJECT))) != rule["version"]:
                deletes.append(p.relative_to(PROJECT).as_posix())
                continue
            owned.setdefault(stable_path(str(p.relative_to(PROJECT)).replace("\\", "/")), []).append(p)

        for stable, group in sorted(owned.items()):
            if len(group) == 1:
                old = group[0].relative_to(PROJECT).as_posix()
                if old != stable:
                    renames.append((old, stable))
                continue
            # 多版本并存 → 保留最高版本
            group.sort(key=lambda p: version_of(p.relative_to(PROJECT).as_posix()), reverse=True)
            if len({version_of(p.relative_to(PROJECT).as_posix()) for p in group}) != len(group):
                raise SystemExit(f"{stable}: 同版本重复文件，人工确认：{[str(p) for p in group]}")
            keep = group[0].relative_to(PROJECT).as_posix()
            if keep != stable:
                renames.append((keep, stable))
            for p in group[1:]:
                deletes.append(p.relative_to(PROJECT).as_posix())

        # keep_version 模式下，被保版本以外的整树兜底（含非运行资产后缀的残件）
        if rule["mode"] == "keep_version":
            for p in sorted(base.rglob("*")):
                if p.is_file() and p.relative_to(PROJECT).as_posix() not in deletes:
                    v = version_of(p.relative_to(PROJECT).as_posix())
                    if v and v != rule["version"]:
                        deletes.append(p.relative_to(PROJECT).as_posix())

    # 备份残留：只清运行资产侧的，`source/` 的备份不属于本批（源侧历史另议）
    for p in sorted(root.rglob("*")):
        if not p.is_file() or not BACKUP.search(p.name):
            continue
        rel = p.relative_to(PROJECT).as_posix()
        if "/source/" in rel:
            continue
        deletes.append(rel)

    renames = sorted(set(renames))
    deletes = sorted(set(d for d in deletes if not any(d == r[0] for r in renames)))
    return renames, deletes


def check(renames, deletes) -> None:
    problems = []
    targets = set()
    for old, new in renames:
        op, np_ = PROJECT / old, PROJECT / new
        if not op.is_file():
            problems.append(f"源不存在: {old}")
        if np_.exists():
            problems.append(f"目标已存在（会覆盖）: {new}")
        if new in targets:
            problems.append(f"重命名目标重复: {new}")
        targets.add(new)
        if not subprocess.run(["git", "-C", str(PROJECT), "ls-files", "--error-unmatch", old],
                              capture_output=True).returncode == 0:
            problems.append(f"未被 git 跟踪（改名会丢历史）: {old}")
    for d in deletes:
        if not (PROJECT / d).is_file():
            problems.append(f"待删文件不存在: {d}")
    if problems:
        print("PLAN_BLOCKED：计划有问题，未做任何改动", file=sys.stderr)
        for p in problems[:40]:
            print("  " + p, file=sys.stderr)
        if len(problems) > 40:
            print(f"  … 另有 {len(problems) - 40} 项", file=sys.stderr)
        raise SystemExit(2)


def git(*args: str) -> None:
    r = subprocess.run(["git", "-C", str(PROJECT), *args], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} 失败：{r.stderr.strip()}")


def apply_renames(renames) -> None:
    path_map = {old: new for old, new in renames}
    for old, new in renames:
        (PROJECT / new).parent.mkdir(parents=True, exist_ok=True)
        git("mv", old, new)
    # 改名后的 .tscn 内部引用同步改写
    touched = 0
    for old, new in renames:
        if not new.endswith(".tscn"):
            continue
        f = PROJECT / new
        text = f.read_text(encoding="utf8")
        updated = text
        for o, n in path_map.items():
            updated = updated.replace(f"res://{o}", f"res://{n}")
        if updated != text:
            f.write_text(updated, encoding="utf8")
            touched += 1
    print(f"RENAMED {len(renames)} 个文件；改写内部引用的 .tscn {touched} 个")


def fix_scene_refs(batch: dict) -> int:
    """把批根下 `.tscn` 内部的 `res://..._vNNN.glb|tscn` 引用改写到稳定路径。

    只在**稳定路径已存在**时改写，因此幂等、且不会把引用改到不存在的文件上。
    独立成一步是必要的：重命名的内容改写若只留在工作区（未暂存），
    任何 `git checkout` 恢复都会把它抹掉——本批就踩过。
    """
    touched = 0
    root = PROJECT / batch["root"]
    ref = re.compile(r"res://(assets/[A-Za-z0-9_/.\-]*?_v\d{3}\.(?:glb|tscn))")
    for tscn in sorted(root.rglob("*.tscn")):
        text = tscn.read_text(encoding="utf8")
        updated = text
        for old_rel in set(ref.findall(text)):
            stable = stable_path(old_rel)
            if stable == old_rel or not (PROJECT / stable).is_file():
                continue
            updated = updated.replace(f"res://{old_rel}", f"res://{stable}")
        if updated != text:
            tscn.write_text(updated, encoding="utf8")
            touched += 1
    return touched


def apply_deletes(deletes) -> None:
    for d in deletes:
        git("rm", "-q", "--", d)
    # 清掉留空的版本目录
    for p in sorted((ART).rglob("*"), reverse=True):
        if p.is_dir() and VERSION_DIR.match(p.name):
            try:
                p.rmdir()
                print(f"RMDIR {p.relative_to(PROJECT).as_posix()}")
            except OSError:
                pass
    print(f"DELETED {len(deletes)} 个文件")


def main() -> int:
    ap = argparse.ArgumentParser(description="去版本化批次迁移")
    ap.add_argument("batch", choices=sorted(BATCHES))
    ap.add_argument("--plan", action="store_true", default=True)
    ap.add_argument("--apply-renames", action="store_true")
    ap.add_argument("--apply-deletes", action="store_true")
    ap.add_argument("--fix-scene-refs", action="store_true")
    args = ap.parse_args()

    batch = BATCHES[args.batch]
    excluded = list(batch.get("excluded", []))

    if args.fix_scene_refs:
        print(f"=== {args.batch} 场景内部引用改写 ===")
        print(f"改写 {fix_scene_refs(batch)} 个 .tscn")
        return 0

    if args.apply_deletes:
        deletes = collect_leftovers(batch)
        missing = [d for d in deletes if not (PROJECT / d).is_file()]
        if missing:
            raise SystemExit(f"待删文件不存在：{missing[:5]}")
        print(f"=== {args.batch} 第二步：删除残留 {len(deletes)} 个 ===")
        for d in deletes:
            print(f"  {d}")
        apply_deletes(deletes)
        return 0

    renames, deletes = collect(batch)
    check(renames, deletes)

    print(f"=== {args.batch} {batch['label']} ===")
    print(f"重命名 {len(renames)} 个：")
    for old, new in renames:
        print(f"  {old}\n    -> {new}")
    print(f"\n第一步之后还需删除 {len(deletes)} 个（用 --apply-deletes 执行）：")
    for d in deletes:
        print(f"  {d}")
    if excluded:
        print("\n本批排除（转其它批）：")
        for e in excluded:
            print(f"  {e}")

    if args.apply_renames:
        apply_renames(renames)
    if not args.apply_renames:
        print("\n（--plan 模式，未做任何改动）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
