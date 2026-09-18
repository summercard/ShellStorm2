#!/usr/bin/env python3
"""Prove the ledger split lost nothing, and keep proving it on every later run.

The invariant is anchored to a fingerprint frozen *before* the split
(``assets/registry/ledger_split_baseline.json``), so this is a regression guard, not a
one-off migration check: any later edit that silently drops, duplicates or mutates an
asset row is caught against the pre-split truth.

Asserted
--------
1. 每个分账本的《资产主表》行全部来自基线，逐格指纹一致（25 列全比）。
2. 所有分账本的并集 == 基线全集，每个 AssetID 恰好出现一次。
3. 每行的大类必须属于其所在账本声明的大类集合 —— 防止「资产写错账本」。
4. 随域迁移的专表（3D-* / 角色组件 / 动画与状态 / 原型角色 / 角色中转记录）逻辑内容逐字节不变。
5. 总目录不再持有任何资产行，且只保留声明的跨域契约表。
6. 总目录《分账本索引》与 assets/registry/ledger_index.json 完全一致。

Exit codes: 0 OK, 1 断言失败。
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

try:
    from openpyxl import load_workbook
except ImportError as exc:  # pragma: no cover
    raise SystemExit("openpyxl is required: pip install openpyxl") from exc

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from ledger_registry import LedgerIndex  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from split_asset_ledger import (  # noqa: E402
    ASSET_SHEET,
    CONTENT_COLUMNS,
    FIRST_DATA_ROW,
    _row_digest,
    _text,
    col_digest,
    dedupe_key_formula,
    dedupe_result_formula,
    read_source_rows,
    sheet_digest,
)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()

    root = args.project_root.resolve()
    index = LedgerIndex.load(root)
    baseline_path = root / "assets/registry/ledger_split_baseline.json"
    if not baseline_path.is_file():
        raise SystemExit(f"无损基线缺失: {baseline_path}（先跑 tools/asset_pipeline/split_asset_ledger.py）")
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    expected_assets: dict[str, Any] = baseline["assets"]

    failures: list[dict[str, Any]] = []

    def fail(kind: str, **payload) -> None:
        failures.append({"kind": kind, **payload})

    seen: dict[str, str] = {}
    collected: list[tuple[str, tuple[Any, ...]]] = []
    totals: dict[str, int] = {}

    for domain in index.domains:
        if not domain.path.is_file():
            fail("ledger_missing", domain=domain.key, path=domain.relative_path)
            continue
        wb = load_workbook(domain.path)
        if ASSET_SHEET not in wb.sheetnames:
            fail("asset_sheet_missing", domain=domain.key)
            continue
        ws = wb[ASSET_SHEET]
        rows = read_source_rows(ws)
        totals[domain.key] = len(rows)
        expected_end = FIRST_DATA_ROW - 1 + len(rows)

        for row_number, values in rows:
            asset_id = _text(values[0])
            category = _text(values[2])
            if asset_id in seen:
                fail("duplicate_asset_id", asset_id=asset_id, first=seen[asset_id], second=domain.key)
                continue
            seen[asset_id] = domain.key
            collected.append((asset_id, values))

            if category not in domain.categories:
                fail("category_outside_ledger", asset_id=asset_id, category=category, domain=domain.key)
            expected = expected_assets.get(asset_id)
            if expected is None:
                fail("asset_not_in_baseline", asset_id=asset_id, domain=domain.key)
                continue
            if expected["c"] != category:
                fail("category_mutated", asset_id=asset_id, baseline=expected["c"], actual=category)
            if expected["d"] != domain.key:
                fail("asset_in_wrong_ledger", asset_id=asset_id, expected_domain=expected["d"], actual=domain.key)
            if expected["v"] != _row_digest(values):
                fail("row_content_mutated", asset_id=asset_id, domain=domain.key,
                     row=list(_text(v) for v in values))

            # 派生列不进内容指纹，改为断言公式形状：行号自指 + 查重范围覆盖本账本全表
            dedupe_key = _text(ws.cell(row=row_number, column=18).value)
            dedupe_result = _text(ws.cell(row=row_number, column=19).value)
            if dedupe_key != dedupe_key_formula(row_number):
                fail("dedupe_key_formula_wrong", asset_id=asset_id, actual=dedupe_key[:120])
            if dedupe_result != dedupe_result_formula(row_number, expected_end):
                fail("dedupe_result_formula_wrong", asset_id=asset_id, actual=dedupe_result[:120])
            if _text(ws.cell(row=row_number, column=3).value) != category:
                fail("category_column_drift", asset_id=asset_id)

        for sheet in domain.sheet_scope:
            if sheet not in wb.sheetnames:
                fail("moved_sheet_missing", domain=domain.key, sheet=sheet)
                continue
            recorded = baseline["sheet_digests"].get(sheet)
            if recorded is None:
                continue
            actual = sheet_digest(wb[sheet])
            if actual != recorded:
                fail("moved_sheet_mutated", domain=domain.key, sheet=sheet)

        # 总览必须自洽：公式行跨度 = 本账本实际行数
        ws_ov = wb["总览"] if "总览" in wb.sheetnames else None
        if ws_ov is None:
            fail("overview_missing", domain=domain.key)
        else:
            expected_end = FIRST_DATA_ROW - 1 + len(rows)
            for cell_ref in ("A6", "C6", "E6", "G6"):
                formula = _text(ws_ov[cell_ref].value)
                if not formula.startswith("=") or f"${expected_end}" not in formula:
                    fail("overview_formula_scope_wrong", domain=domain.key, cell=cell_ref,
                         formula=formula[:120], expected_end=expected_end)

    missing = sorted(set(expected_assets) - set(seen))
    for asset_id in missing:
        fail("asset_lost", asset_id=asset_id, expected_domain=expected_assets[asset_id]["d"])
    extra = sorted(set(seen) - set(expected_assets))

    # 列级定位：并集与基线的逐列指纹，用来把「行内容变了」缩小到具体列
    collected.sort(key=lambda item: item[0])
    column_drift = [
        str(col)
        for col in CONTENT_COLUMNS
        if col_digest(collected, col) != baseline["column_digests"].get(str(col))
    ]

    # ---- 总目录 ----------------------------------------------------------
    master = load_workbook(index.master_path)
    declared = index.raw["master"]["sheets"]
    if ASSET_SHEET in master.sheetnames:
        fail("master_still_holds_asset_rows", sheet=ASSET_SHEET,
             rows=len(read_source_rows(master[ASSET_SHEET])))
    for sheet in declared:
        if sheet not in master.sheetnames:
            fail("master_sheet_missing", sheet=sheet)
    for sheet in master.sheetnames:
        if sheet not in declared:
            fail("master_sheet_undeclared", sheet=sheet)

    if "分账本索引" in master.sheetnames:
        ws = master["分账本索引"]
        for offset, domain in enumerate(index.domains):
            row = FIRST_DATA_ROW + offset
            actual = (_text(ws.cell(row=row, column=2).value), _text(ws.cell(row=row, column=3).value))
            wanted = (domain.name, domain.relative_path)
            if actual != wanted:
                fail("index_row_mismatch", row=row, expected=wanted, actual=actual)
        extra_rows = [
            row for row in range(FIRST_DATA_ROW + len(index.domains), FIRST_DATA_ROW + len(index.domains) + 5)
            if _text(ws.cell(row=row, column=2).value) and _text(ws.cell(row=row, column=2).value) != "合计"
        ]
        if extra_rows:
            fail("index_has_extra_rows", rows=extra_rows)
    else:
        fail("master_sheet_missing", sheet="分账本索引")

    result = {
        "baseline_assets": baseline["asset_count"],
        "baseline_captured_at": baseline["captured_at"],
        "ledger_totals": totals,
        "union_assets": len(seen),
        "missing_assets": missing[:20],
        "extra_assets": extra[:20],
        "column_digest_drift": column_drift,
        "failure_count": len(failures),
        "failures": failures[:40],
    }
    encoded = json.dumps(result, ensure_ascii=False, indent=2)
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)

    if failures:
        print(
            f"LEDGER_SPLIT_VERIFY_FAILED failures={len(failures)} "
            f"missing={len(missing)} extra={len(extra)}",
            file=sys.stderr,
        )
        return 1
    print(
        f"LEDGER_SPLIT_VERIFY_OK assets={len(seen)} ledgers={len(index.domains)} "
        f"baseline={baseline['captured_at']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
