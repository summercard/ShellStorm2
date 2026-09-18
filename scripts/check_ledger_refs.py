#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""扫描全仓对「旧单体账本路径」的引用，把「记录」和「会读写的脚本」分开。

分册化（2026-09-18）之后，`assets/registry/ShellStorm2_美术资产台账_v001.xlsx` 只剩总目录角色
（跨域契约 + 索引，**不含资产行**）。旧引用因此分两类：

1. **记录类 —— 保持原样，不要改写。**
   `asset_manifest.json`、`*_result.json`、`pending_ledger_rows_*.json`、`catalog.json`、
   `asset_guard.json`，以及 `docs/` 下的历史记录。它们描述的是**当时**的产出，
   `LedgerIndex.resolve_ref()` 会把 `总目录#分页` 解析到正确的分账本。

2. **会读写的脚本 —— 重放前必须重定向。**
   判定条件（两个都满足）：文本里出现旧单体账本文件名，**并且**文件真的打开 xlsx
   （`load_workbook` / `worksheets.getItem` / `openpyxl` / `ExcelJS`）。
   这类脚本用的是单体账本的《资产主表》行号坐标，而分账本里的行号已经平移 ——
   **不能只换路径就重放**。先用 `assets/registry/ledger_index.json` 解析目标分账本，
   再把行号重定为「按 AssetID 定位」或分账本行号，然后才可重放。

退出码：0 = 没有待处理脚本；1 = 有（打印清单）。
新批次写账本请直接走 `scripts/ledger_registry.py`，不要照抄旧批次的 qa 脚本。

用法::

    python scripts/check_ledger_refs.py
    python scripts/check_ledger_refs.py --json-output _scratch/ledger_refs.json
    python scripts/check_ledger_refs.py --allow-pending    # 仅报告，不置失败
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ledger_registry import LedgerIndex  # noqa: E402

PRUNE_DIRS = {".git", ".godot", "__pycache__", "node_modules", ".codex-tmp", ".import", "_scratch", "_b3tmp", "_conflict_check"}
EXECUTABLE_SUFFIXES = {".py", ".mjs", ".js", ".gd", ".sh"}
RECORD_SUFFIXES = {".json"}
PROSE_SUFFIXES = {".md", ".yaml", ".yml", ".txt"}
SCAN_ROOTS = ("assets", "source", "tools", "scripts", "tests", "src")

# xlsx 读写特征：两个条件都满足才算「会读写的脚本」
XLSX_TOUCH = ("load_workbook", "worksheets.getitem", "openpyxl", "exceljs", "xlsx-populate", "sheetjs", "workbook.xlsx")

# 设计上就该出现总目录路径的注册表工具（不是待处理项）
ALLOWLIST = {
    "tools/asset_pipeline/split_asset_ledger.py",   # 拆分器：总目录路径是它的输出声明
    "tools/asset_pipeline/update_v01_completion_registry.mjs",
}

RECORD_DIR_HINTS = ("docs/archive", "docs/v0.1/development", "docs/v0.1/audits/evidence", ".workbuddy/memory")


def iter_files(root: Path, suffix_set: set[str]):
    for base in SCAN_ROOTS:
        start = root / base
        if not start.is_dir():
            continue
        for path in start.rglob("*"):
            if not path.is_file():
                continue
            if any(part in PRUNE_DIRS for part in path.parts):
                continue
            if ".bak_" in path.name:
                continue
            if path.suffix.lower() in suffix_set:
                yield path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--allow-pending", action="store_true", help="存在待处理脚本时也返回 0")
    args = parser.parse_args()

    root = args.project_root.resolve()
    index = LedgerIndex.load(root)
    needle = index.master_relative_path.rsplit("/", 1)[-1]
    # 历史上出现过 v001 与 v002 两种写法（v002 那个文件从来不存在）——
    # 所以 `asset_ledger` 字段的**文件部分不可信**，只有 `#分页` 可信。
    pattern = re.compile(r"ShellStorm2_美术资产台账_v\d+\.xlsx")
    registry_dir = (root / index.master_relative_path).parent

    pending: list[str] = []
    allowed: list[str] = []
    records: list[str] = []
    prose: list[str] = []
    dangling: list[str] = []

    for path in iter_files(root, EXECUTABLE_SUFFIXES | RECORD_SUFFIXES | PROSE_SUFFIXES):
        rel = path.relative_to(root).as_posix()
        if rel.startswith("assets/registry/ledger_") or rel == "scripts/check_ledger_refs.py":
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        names = set(pattern.findall(text))
        if not names:
            continue
        suffix = path.suffix.lower()
        # 断链只在机器可读文件里算问题；散文里提到旧文件名是文档，不是断链
        if suffix in (EXECUTABLE_SUFFIXES | RECORD_SUFFIXES) and any(
            not (registry_dir / name).is_file() for name in names
        ):
            dangling.append(f"{rel}  -> {sorted(names)}")
        if needle not in text:
            continue
        if suffix in EXECUTABLE_SUFFIXES:
            touches_xlsx = any(token in text.lower() for token in XLSX_TOUCH)
            if not touches_xlsx:
                prose.append(rel)
            elif rel in ALLOWLIST:
                allowed.append(rel)
            else:
                pending.append(rel)
        elif suffix in RECORD_SUFFIXES:
            records.append(rel)
        else:
            if any(hint in rel for hint in RECORD_DIR_HINTS):
                records.append(rel)
            else:
                prose.append(rel)

    print(f"待处理脚本（会读写旧单体账本）: {len(pending)}")
    for item in sorted(pending):
        print(f"    {item}")
    print(f"\n设计允许（注册表工具）: {len(allowed)}")
    for item in sorted(allowed):
        print(f"    {item}")
    print(f"\n指向不存在的账本文件（历史遗留，文件部分不可信）: {len(dangling)}")
    for item in sorted(dangling)[:5]:
        print(f"    {item}")
    if len(dangling) > 5:
        print(f"    … 其余 {len(dangling) - 5} 条见 --json-output")
    print(f"\n历史产出记录 / 文档引用（保持原样）: {len(records)} 个 json + {len(prose)} 个文本")
    print("    （明细见 --json-output，或直接 grep）")

    payload = {
        "project_root": str(root),
        "master": index.master_relative_path,
        "counts": {
            "pending": len(pending),
            "allowed": len(allowed),
            "dangling": len(dangling),
            "records": len(records),
            "prose": len(prose),
        },
        "pending": sorted(pending),
        "allowed": sorted(allowed),
        "dangling": sorted(dangling),
        "records": sorted(records),
        "prose": sorted(prose),
    }
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    if pending and not args.allow_pending:
        print(f"\nLEDGER_REFS_NEED_REBASE pending={len(pending)}"
              f"（重放前须重定向到分账本并重定行号；见文件头说明）")
        return 1
    print(f"\nLEDGER_REFS_OK pending={len(pending)} allowed={len(allowed)} dangling={len(dangling)} records={len(records)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
