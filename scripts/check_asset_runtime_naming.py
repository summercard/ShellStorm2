#!/usr/bin/env python3
"""门禁：Godot 运行资产不得带版本号（去版本化执行计划 P4）。

规则（assets/art/3D模型资产目录与命名规范.md §坐标与替换契约）
  - `components/`、`runtime/` 下的运行资产文件名与目录名不含 `_vNNN` 与 `vNNN/`。
  - `source/**` 是 Blender 源，版本历史属于它，整体豁免。
  - `src/**/*.gd` 与场景 `.tscn` 不得引用带版本号的资产路径。

存量未清完前用**精确快照**（`asset_runtime_naming_debt.json`）记账，语义是
「磁盘现状必须与快照逐项一致」：

  * 出现快照之外的带版本文件/目录      → 退出 1（新违规）
  * 引用计数高于快照                   → 退出 1（新违规）
  * 快照里的条目已从磁盘消失 / 计数下降 → 退出 2（快照陈旧，需 `--update-debt`）
  * 完全一致                           → 退出 0（打印剩余欠账规模）

退出 2 是刻意的：每完成一批原子批就必须缩表，否则这张表会重新变成谎言。

用法：
  python3 scripts/check_asset_runtime_naming.py            # 检查
  python3 scripts/check_asset_runtime_naming.py --update-debt   # 按现状重写快照
  python3 scripts/check_asset_runtime_naming.py --json      # 机器可读
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
ART_ROOT = PROJECT / "assets" / "art"
SRC_ROOT = PROJECT / "src"
DEBT_PATH = Path(__file__).resolve().parent / "asset_runtime_naming_debt.json"

# 运行资产与其 Godot 旁文件（.import / .uid）
RUN_ASSET_SUFFIX = re.compile(r"_v\d{3}\.(?:glb|tscn)(?:\.(?:import|uid))?$")
VERSIONED_DIR = re.compile(r"^v\d{3}$")
BACKUP_RESIDUE = re.compile(r"\.bak_")

GD_ASSET_REF = re.compile(r'"res://(assets/[^"]+?_v\d{3}\.(?:glb|tscn))"')
TSCN_ASSET_REF = re.compile(r'path="res://(assets/[^"]+?_v\d{3}\.(?:glb|tscn))"')


def rel(path: Path) -> str:
    return path.relative_to(PROJECT).as_posix()


def is_exempt(path: Path) -> bool:
    """`source/` 是 Blender 源，版本历史属于它。"""
    return "source" in path.relative_to(ART_ROOT).parts


def scan_art() -> tuple[list[str], list[str], list[str]]:
    versioned_files: list[str] = []
    versioned_dirs: list[str] = []
    backup_residue: list[str] = []
    for path in sorted(ART_ROOT.rglob("*")):
        if is_exempt(path):
            continue
        if path.is_dir():
            if VERSIONED_DIR.match(path.name):
                versioned_dirs.append(rel(path))
            continue
        if RUN_ASSET_SUFFIX.search(path.name):
            versioned_files.append(rel(path))
        if BACKUP_RESIDUE.search(path.name):
            backup_residue.append(rel(path))
    return versioned_files, versioned_dirs, backup_residue


def count_references() -> tuple[int, int, list[str]]:
    """统计 src 代码与场景里对带版本资产路径的引用，并给出样例位置。"""
    gd_refs = 0
    tscn_refs = 0
    samples: list[str] = []

    for gd in sorted(SRC_ROOT.rglob("*.gd")):
        text = gd.read_text(encoding="utf8", errors="ignore")
        hits = GD_ASSET_REF.findall(text)
        gd_refs += len(hits)
        if hits:
            samples.append(f"{rel(gd)} ({len(hits)})")

    scene_roots = (ART_ROOT, PROJECT / "scenes", PROJECT / "tests", PROJECT / "src")
    seen: set[Path] = set()
    for root in scene_roots:
        if not root.is_dir():
            continue
        for tscn in sorted(root.rglob("*.tscn")):
            if tscn in seen:
                continue
            seen.add(tscn)
            text = tscn.read_text(encoding="utf8", errors="ignore")
            tscn_refs += len(TSCN_ASSET_REF.findall(text))
    return gd_refs, tscn_refs, samples


def current_state() -> dict:
    versioned_files, versioned_dirs, backup_residue = scan_art()
    gd_refs, tscn_refs, samples = count_references()
    return {
        "versioned_files": versioned_files,
        "versioned_dirs": versioned_dirs,
        "backup_residue": backup_residue,
        "reference_counts": {"gd": gd_refs, "tscn": tscn_refs},
        "_reference_samples": samples,
    }


def load_debt() -> dict | None:
    if not DEBT_PATH.is_file():
        return None
    return json.loads(DEBT_PATH.read_text(encoding="utf8"))


def write_debt(state: dict) -> None:
    payload = {
        "note": "存量欠账快照。每完成一批去版本化必须重跑 --update-debt 缩表；"
                "本文件只允许缩小，不允许为了过门禁而无脑重写。",
        "rule": "assets/art/** 下（source/ 豁免）运行资产文件名/目录名不得含 _vNNN；"
                "src/**/*.gd 与 *.tscn 不得引用带版本资产路径。",
        "update_command": "python3 scripts/check_asset_runtime_naming.py --update-debt",
        "versioned_files": sorted(state["versioned_files"]),
        "versioned_dirs": sorted(state["versioned_dirs"]),
        "backup_residue": sorted(state["backup_residue"]),
        "reference_counts": state["reference_counts"],
    }
    DEBT_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf8"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Godot 运行资产命名门禁")
    parser.add_argument("--update-debt", action="store_true", help="按磁盘现状重写欠账快照")
    parser.add_argument("--json", action="store_true", help="输出机器可读结果")
    parser.add_argument("--quiet", action="store_true", help="只输出一行结论")
    args = parser.parse_args()

    state = current_state()
    if args.update_debt:
        write_debt(state)
        print(
            f"DEBT_UPDATED {rel(DEBT_PATH)} "
            f"files={len(state['versioned_files'])} dirs={len(state['versioned_dirs'])} "
            f"backup={len(state['backup_residue'])} "
            f"refs(gd={state['reference_counts']['gd']} tscn={state['reference_counts']['tscn']})"
        )
        return 0

    debt = load_debt()
    if debt is None:
        print(f"缺少欠账快照 {rel(DEBT_PATH)}；先跑 --update-debt 建立基线。", file=sys.stderr)
        return 1

    new_files = sorted(set(state["versioned_files"]) - set(debt["versioned_files"]))
    new_dirs = sorted(set(state["versioned_dirs"]) - set(debt["versioned_dirs"]))
    new_backup = sorted(set(state["backup_residue"]) - set(debt["backup_residue"]))
    gone_files = sorted(set(debt["versioned_files"]) - set(state["versioned_files"]))
    gone_dirs = sorted(set(debt["versioned_dirs"]) - set(state["versioned_dirs"]))
    gone_backup = sorted(set(debt["backup_residue"]) - set(state["backup_residue"]))

    now_counts = state["reference_counts"]
    was_counts = debt["reference_counts"]
    ref_up = {k: (was_counts.get(k, 0), now_counts[k]) for k in now_counts if now_counts[k] > was_counts.get(k, 0)}
    ref_down = {k: (was_counts.get(k, 0), now_counts[k]) for k in now_counts if now_counts[k] < was_counts.get(k, 0)}

    violations = bool(new_files or new_dirs or new_backup or ref_up)
    stale = bool(gone_files or gone_dirs or gone_backup or ref_down)

    if args.json:
        print(json.dumps({
            "violations": violations,
            "stale_debt": stale,
            "new_versioned_files": new_files,
            "new_versioned_dirs": new_dirs,
            "new_backup_residue": new_backup,
            "reference_count_increase": ref_up,
            "debt_paid_files": gone_files,
            "debt_paid_dirs": gone_dirs,
            "debt_paid_backup": gone_backup,
            "reference_count_decrease": ref_down,
            "remaining": {
                "versioned_files": len(state["versioned_files"]),
                "versioned_dirs": len(state["versioned_dirs"]),
                "backup_residue": len(state["backup_residue"]),
                "references": now_counts,
            },
        }, ensure_ascii=False, indent=2))
        # --json 只输出 JSON：必须在这里结束，否则尾部的人话会污染机器可读输出。
        if violations:
            return 1
        return 2 if stale else 0

    def show(title: str, items: list[str], limit: int = 10) -> None:
        if not items:
            return
        print(f"\n{title}（{len(items)}）")
        for item in items[:limit]:
            print(f"  {item}")
        if len(items) > limit:
            print(f"  … 另有 {len(items) - limit} 项")

    if violations:
        show("新增带版本运行资产文件", new_files)
        show("新增带版本目录", new_dirs)
        show("新增备份残留", new_backup)
        for key, (was, now) in ref_up.items():
            print(f"\n带版本引用计数上升：{key} {was} → {now}")
        show("引用样例（gd 文件，括号内为引用数）", state["_reference_samples"])
        print(
            "\n新增带版本资产被拒绝：运行资产路径必须恒定、不含版本号，"
            "替换一律覆盖同路径同名文件（见 assets/art/3D模型资产目录与命名规范.md）。",
            file=sys.stderr,
        )
        return 1

    if stale:
        show("快照里已消失的文件（欠账已还）", gone_files)
        show("快照里已消失的目录", gone_dirs)
        show("快照里已消失的备份残留", gone_backup)
        for key, (was, now) in ref_down.items():
            print(f"\n带版本引用计数下降：{key} {was} → {now}")
        print(
            f"\n欠账快照陈旧：请跑 `python3 scripts/check_asset_runtime_naming.py --update-debt` 缩表"
            f"（{rel(DEBT_PATH)}）。不收窄的表等于假账。",
            file=sys.stderr,
        )
        return 2

    summary = (
        f"ASSET_RUNTIME_NAMING_OK 剩余欠账："
        f"文件 {len(state['versioned_files'])} / 目录 {len(state['versioned_dirs'])} / "
        f"备份 {len(state['backup_residue'])}；"
        f"带版本引用 gd={now_counts['gd']} tscn={now_counts['tscn']}"
    )
    if args.quiet:
        print(summary)
    else:
        print(summary)
        print(f"（快照 {rel(DEBT_PATH)}；欠账未清零前本门禁只拦新增，清零后删除快照与豁免）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
