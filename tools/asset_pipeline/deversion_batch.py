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
            "（zone 场景、非 <slug> 粒度）→ 已转 B2",
            "assets/art/environments/tower_zones/rooftop/runtime/zone_rooftop_v021.tscn → 已转 B2",
        ],
    },
    # B2 横跨 7 个根（其中 tower_zones/base + rooftop 收的是 B1 残留的 2 个 zone 场景）。
    "b2": {
        "label": "dungeon_3d + tower_descent_3d + base_world_3d（+ B1 残留 zone 场景）",
        "roots": [
            {"root": "assets/art/props/dungeon_3d", "rules": {"": {"mode": "collapse"}}},
            {
                "root": "assets/art/environments/tower_descent_3d",
                "rules": {
                    "components": {"mode": "collapse"},
                    "runtime": {"mode": "collapse"},
                },
            },
            {"root": "assets/art/props/base_world_3d", "rules": {"": {"mode": "collapse"}}},
            {"root": "assets/art/environments/dungeon_3d", "rules": {"": {"mode": "collapse"}}},
            {"root": "assets/art/environments/base_world_3d", "rules": {"": {"mode": "collapse"}}},
            # B1 残留：这两个 zone 场景是 <slug> 粒度之上的整关包，B1 因「引用方
            # TowerDescent3D.gd 正被并行会话改动」而排除；B2 已一并改引用，故收进来。
            {"root": "assets/art/environments/tower_zones/base", "rules": {"runtime": {"mode": "collapse"}}},
            {"root": "assets/art/environments/tower_zones/rooftop", "rules": {"runtime": {"mode": "collapse"}}},
        ],
        # 跨目录取代：这两份是「同一逻辑资产」的两版，却分处不同目录，
        # 按 stable_path 分组看不出来（稳定路径不同 → 会被各自改名、双双留下）。
        # 依据 floor_tile_5m/asset_manifest_v002.json 的 replacement 字段：
        # 「v001 registry pointed to GLB but actual runtime was BoxMesh; v002 now
        #  explicitly imports the authored mesh」→ 扁平的 v001 是废弃版，删；
        #  floor_tile_5m/ 下的 v002 是正式版，改名保留。
        "superseded": {
            "assets/art/environments/tower_descent_3d/components/env_tower_floor_tile_5m_top3d_v001.glb":
                "assets/art/environments/tower_descent_3d/components/floor_tile_5m/env_tower_floor_tile_5m_top3d_v002.glb",
        },
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


def batch_roots(batch: dict) -> list[tuple[str, dict]]:
    """归一化批次的根列表：老写法 `root` + `rules`，新写法 `roots: [{root, rules}]`。"""
    if "roots" in batch:
        return [(entry["root"], entry["rules"]) for entry in batch["roots"]]
    return [(batch["root"], batch["rules"])]


def superseded_paths(batch: dict) -> list[str]:
    """跨目录「废弃版」及其旁文件（.import/.uid）：这些是删除项，不是改名项。"""
    out: list[str] = []
    for doomed in batch.get("superseded", {}):
        out.append(doomed)
        for suffix in (".import", ".uid"):
            if (PROJECT / (doomed + suffix)).is_file():
                out.append(doomed + suffix)
    return out


def batch_applied(batch: dict) -> list[str]:
    """判定批次已落地：`superseded` 的废弃版与其正式版都不在磁盘，但正式版的稳定路径在。

    这是一次性迁移脚本的**正常终态**，必须与「文件被误删」区分开 —— 否则在已应用
    的批次上重跑 `--plan` 会报「废弃版不存在」，读起来像丢了文件，会诱导操作者去
    「恢复」一个按设计本就该删掉的旧版。
    """
    hit: list[str] = []
    for doomed, canonical in batch.get("superseded", {}).items():
        if (PROJECT / doomed).is_file():
            continue
        if not (PROJECT / canonical).is_file() and (PROJECT / stable_path(canonical)).is_file():
            hit.append(doomed)
    return hit


def collect_leftovers(batch: dict) -> list[str]:
    """第二步（重命名之后）的删除清单：批根下**仍然带版本**的运行资产。

    与 collect() 分开是必要的：重命名之后，`<slug>_v003.glb` 的稳定名已被上一步
    的 `<slug>_v004.glb` 占据；若还用「保留最高版本」的逻辑重算，会把 `v003` 当成
    更高版本、反过来删掉刚改名成功的文件。

    第二步只认三条：
      A. 稳定名已存在 → 删带版本的那个（同资产多版本的旧版）
      B. 落在非保留版本的整树目录里（`<套件>/vNNN/...` 且 vNNN ≠ 规则保留版本）→ 整树删
      C. 命中 `superseded` 声明的废弃版（跨目录同名资产的旧版）→ 删
    """
    deletes: list[str] = []
    doomed_set = set(superseded_paths(batch))
    for root_rel, rules in batch_roots(batch):
        root = PROJECT / root_rel
        # 整树删除范围：keep_version 规则子树 <path>，保留版本 <version>
        tree_rules = [
            (sub, rule["version"])
            for sub, rule in rules.items()
            if rule["mode"] == "keep_version"
        ]
        for p in sorted(root.rglob("*")):
            if not p.is_file():
                continue
            rel = p.relative_to(PROJECT).as_posix()
            if rel in doomed_set:
                deletes.append(rel)
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
                prefix = f"{root_rel}/{sub}/" if sub else f"{root_rel}/"
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
    renames: list[tuple[str, str]] = []
    deletes: list[str] = []

    for root_rel, rules in batch_roots(batch):
        root = PROJECT / root_rel
        for sub, rule in rules.items():
            base = root / sub if sub else root
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

    # 跨目录取代：废弃版（含其 .import/.uid 旁文件）删除，正式版按常规改名保留。
    # 旁文件必须一起删：只删 .glb 会把 `<slug>_v001.glb.import` 改名成稳定的
    # `<slug>.glb.import`，与正式版改名后的同类旁文件并存、留下无主残留。
    superseded: dict[str, str] = batch.get("superseded", {})
    for doomed, canonical in superseded.items():
        if not (PROJECT / doomed).is_file():
            raise SystemExit(
                f"superseded 声明要删的废弃版不存在：{doomed}\n"
                f"  若本批已应用，正式版的稳定路径应当存在：{stable_path(canonical)}"
                f"（现在{'存在' if (PROJECT / stable_path(canonical)).is_file() else '也不存在'}）"
            )
        if not (PROJECT / canonical).is_file():
            raise SystemExit(f"superseded 声明要保留的正式版不存在：{canonical}")
    doomed_all = set(superseded_paths(batch))
    renames = [(o, n) for (o, n) in renames if o not in doomed_all]
    deletes.extend(sorted(doomed_all))

    # 备份残留：只清运行资产侧的，`source/` 的备份不属于本批（源侧历史另议）
    for root_rel, _rules in batch_roots(batch):
        root = PROJECT / root_rel
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
    for root_rel, _rules in batch_roots(batch):
        root = PROJECT / root_rel
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


CODE_REF = re.compile(r"res://(assets/[A-Za-z0-9_/.\-]*?_v\d{3}\.(?:glb|tscn))")


def fix_code_refs(batch: dict) -> list[tuple[str, int, list[str]]]:
    """把全仓 `res://..._vNNN.glb|tscn` 引用改写到稳定路径。

    判据（三条同时成立才改，故自限定作用域、幂等）：
      1. 稳定路径与带版本路径不同；
      2. 带版本路径**已不存在**（说明本批或更早已把它改走）；
      3. 稳定路径**存在**。
    未处理的批次（如 weapons/base_facility 的 `_v001`）带版本文件仍在 → 跳过。
    只扫 `.gd` / `.tscn`：`.py` 批次配置与历史导入脚本不在改写范围（门禁亦只管
    `src/**/*.gd` 与 `*.tscn`）。
    """
    files: list[Path] = []
    for folder in ("src", "scenes", "tests", "tools"):
        base = PROJECT / folder
        if base.is_dir():
            files += [f for f in base.rglob("*") if f.suffix in (".gd", ".tscn")]
    for suffix in ("*.gd", "*.tscn"):
        files += list((PROJECT / "assets" / "art").rglob(suffix))

    changed: list[tuple[str, int, list[str]]] = []
    for f in sorted(set(files)):
        text = f.read_text(encoding="utf8")
        repl: dict[str, str] = {}
        for old in set(CODE_REF.findall(text)):
            stable = stable_path(old)
            if stable == old:
                continue
            if (PROJECT / old).exists():
                continue  # 仍带版本 → 属后续批次，不越界
            if not (PROJECT / stable).is_file():
                continue  # 稳定目标不存在（如被取代的旧版）→ 不能改
            repl[old] = stable
        if not repl:
            continue
        updated = text
        for o, n in repl.items():
            updated = updated.replace(f"res://{o}", f"res://{n}")
        if updated != text:
            f.write_text(updated, encoding="utf8")
            changed.append((f.relative_to(PROJECT).as_posix(), len(repl), sorted(repl)))
    return changed


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
    ap.add_argument("--fix-code-refs", action="store_true")
    args = ap.parse_args()

    batch = BATCHES[args.batch]
    excluded = list(batch.get("excluded", []))

    if args.fix_code_refs:
        print(f"=== {args.batch} 全仓代码/场景引用改写（.gd/.tscn） ===")
        changed = fix_code_refs(batch)
        for rel, n, refs in changed:
            print(f"  {rel}  ({n})")
            for r in refs:
                print(f"      -> res://{stable_path(r)}")
        print(f"共改写 {len(changed)} 个文件")
        return 0

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

    applied = batch_applied(batch)
    if applied and len(applied) == len(batch.get("superseded", {})):
        print(f"=== {args.batch} {batch['label']} ===")
        print(f"本批已应用：superseded 声明的废弃版已删除、正式版已去版本化（{len(applied)} 项）。")
        print(f"  例：{applied[0]}")
        print("  复核：python _scratch/verify_ledger_b2_deversion.py"
              " && python scripts/check_asset_runtime_naming.py")
        print("（无需重复执行；这条不是错误，是正常终态）")
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
