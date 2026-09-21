#!/usr/bin/env python3
"""Validate the split art-asset ledgers: the master catalog plus one workbook per domain.

Structure mode is the AST-01 gate. It checks every ledger for AssetID shape, enum
columns, per-row dedupe-formula shape and a self-consistent overview span, and then
asserts the *cross-file* contracts that make the split safe:

* every declared ledger file exists and holds exactly its declared categories;
* one AssetID appears in exactly one ledger (the old single-file check is now a
  cross-file check — splitting filed the rows apart, it must not duplicate them);
* the master holds no asset rows and only its declared contract sheets;
* master《分账本索引》matches ``assets/registry/ledger_index.json`` cell by cell, so the
  human-readable index and the machine-readable one cannot drift apart;
* master《3D Prefab总控》points each prefab page at the ledger that owns it.

Full mode also reports path, SHA and production-filename debt for AST-02/03.

The checker never updates a ledger: every drift still requires classification and QA.

Exit codes: 0 clean, 1 issues found.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

try:
    from openpyxl import load_workbook
except ImportError as exc:  # pragma: no cover - actionable setup failure
    raise SystemExit("openpyxl is required to check the asset registry: pip install openpyxl") from exc

SCRIPTS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS_DIR))
sys.path.insert(0, str(SCRIPTS_DIR.parent / "tools" / "asset_pipeline"))

from ledger_registry import LedgerIndex  # noqa: E402
from split_asset_ledger import (  # noqa: E402
    ASSET_SHEET,
    CATEGORY_VALUES,
    COLUMN_COUNT,
    FIRST_DATA_ROW,
    HEADER_ROW,
    PRIORITY_VALUES,
    STATUS_VALUES,
    dedupe_key_formula,
    dedupe_result_formula,
)

# 门禁「接纳」的枚举。DV 下拉列表（split_asset_ledger 里的 *_VALUES）刻意更宽，
# 免得打开账本时历史值被标红；两者必须满足 接纳集 ⊆ 下拉集，见 _enum_contract()。
ACCEPTED_STATUSES = {
    "待制作", "程序占位", "已完成", "原型已接入", "弃用",
    "旧资产已从正式基地移除", "正式美术已接入", "已优化并正式接入",
    "Blender源已完成", "已导入；优化完成",
}
ARTIFACT_STATUSES = ACCEPTED_STATUSES - {"待制作", "程序占位", "弃用"}
ACCEPTED_PRIORITIES = {"P0", "P1", "P2"}
ASSET_ID_PATTERN = re.compile(r"^[A-Z0-9]+(?:-[A-Z0-9]+)+$")
# `_vNNN` 可选。运行资产已被去版本化门禁（scripts/check_asset_runtime_naming.py）
# 要求「路径恒定、不含版本号」，而 source/** 下的源文件仍按版本命名；本标记必须同时
# 放行两种，否则「已完成」的行一旦换成去版本化的 runtime 路径就会被误判为不合规。
# 保留的含义是「小写下划线命名 + 受管后缀」，版本号不再是必需项。
PRODUCTION_NAME_PATTERN = re.compile(
    r"^[a-z0-9]+(?:_[a-z0-9]+)*(_v[0-9]{3})?\.(?:png|webp|svg|wav|ogg|glb|gltf|tres|tscn|blend)$"
)
PATH_SPLIT_PATTERN = re.compile(r"[;；\n]+")
CANONICAL_FILENAME_EXCEPTIONS = {
    "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png",
}
LEDGER_SHEETS = ("总览", ASSET_SHEET, "账本说明", "域变更日志")


def _text(value: Any) -> str:
    return "" if value is None else str(value).strip()


def _dedupe_key(row: tuple[Any, ...]) -> str:
    return "|".join(_text(row[index]).lower() for index in (2, 3, 4, 5, 7, 8))


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _registry_paths(raw: str, project_root: Path) -> list[Path]:
    paths: list[Path] = []
    for token in PATH_SPLIT_PATTERN.split(raw):
        token = token.strip()
        if not token or token.startswith("res://"):
            token = token.removeprefix("res://")
        if not token or any(marker in token for marker in ("待", "无", "N/A")):
            continue
        candidate = Path(token)
        if not candidate.is_absolute():
            candidate = project_root / candidate
        paths.append(candidate)
    return paths


def _read_asset_rows(ws) -> list[tuple[int, tuple[Any, ...]]]:
    rows: list[tuple[int, tuple[Any, ...]]] = []
    for row in range(FIRST_DATA_ROW, ws.max_row + 1):
        if not _text(ws.cell(row=row, column=1).value):
            continue
        rows.append((row, tuple(ws.cell(row=row, column=col).value for col in range(1, COLUMN_COUNT + 1))))
    return rows


def _enum_contract(index: LedgerIndex, issues: dict[str, list[dict[str, Any]]]) -> None:
    """下拉列表与门禁接纳集、账本声明的大类集合必须三方一致。"""
    declared = index.all_categories()
    dv_categories = set(CATEGORY_VALUES)
    if declared != dv_categories:
        issues["category_universe_mismatch"].append({
            "only_in_index": sorted(declared - dv_categories),
            "only_in_dv": sorted(dv_categories - declared),
        })
    if not ACCEPTED_STATUSES <= set(STATUS_VALUES):
        issues["status_universe_mismatch"].append({
            "accepted_not_in_dv": sorted(ACCEPTED_STATUSES - set(STATUS_VALUES)),
        })
    if not ACCEPTED_PRIORITIES <= set(PRIORITY_VALUES):
        issues["priority_universe_mismatch"].append({
            "accepted_not_in_dv": sorted(ACCEPTED_PRIORITIES - set(PRIORITY_VALUES)),
        })


def scan_workbook(
    wb,
    label: str,
    domain,
    index: LedgerIndex,
    project_root: Path,
    scope: str,
    issues: dict[str, list[dict[str, Any]]],
) -> int:
    """逐行/逐表检查一个工作簿，把问题写进 issues，返回资产行数。"""
    def note(kind: str, **payload: Any) -> None:
        issues[kind].append({"ledger": label, **payload})

    for required in LEDGER_SHEETS:
        if required not in wb.sheetnames:
            note("ledger_sheet_missing", sheet=required)
    if ASSET_SHEET not in wb.sheetnames:
        return 0

    sheet_scope = tuple(domain.sheet_scope) if domain is not None else ()
    allowed_sheets = set(LEDGER_SHEETS) | set(sheet_scope)
    if domain is not None:
        for sheet in sheet_scope:
            if sheet not in wb.sheetnames:
                note("domain_sheet_missing", sheet=sheet)
    for name in wb.sheetnames:
        if name not in allowed_sheets:
            note("ledger_sheet_undeclared", sheet=name)

    main = wb[ASSET_SHEET]
    rows = _read_asset_rows(main)
    dedupe_rows: dict[str, list[int]] = defaultdict(list)
    seen_here: Counter[str] = Counter()

    for row_number, row in rows:
        asset_id = _text(row[0])
        category = _text(row[2])
        status = _text(row[10])
        priority = _text(row[11])
        seen_here[asset_id] += 1
        dedupe_rows[_dedupe_key(row)].append(row_number)

        if not ASSET_ID_PATTERN.fullmatch(asset_id):
            note("invalid_asset_id", row=row_number, asset_id=asset_id)
        if category not in index.all_categories():
            note("invalid_category", row=row_number, asset_id=asset_id, value=category)
        if domain is not None and category not in domain.categories:
            note("category_outside_ledger", row=row_number, asset_id=asset_id,
                 category=category, domain=domain.key)
        if domain is not None and asset_id:
            prefix = asset_id.split("-", 1)[0]
            if (prefix, category) not in index.prefix_pairs():
                note("asset_id_prefix_mismatch", row=row_number, asset_id=asset_id,
                     prefix=prefix, category=category, domain=domain.key)
        if status not in ACCEPTED_STATUSES:
            note("invalid_status", row=row_number, asset_id=asset_id, value=status)
        if priority not in ACCEPTED_PRIORITIES:
            note("invalid_priority", row=row_number, asset_id=asset_id, value=priority)

        # 派生列：内容是逐行重算的，所以只断言形状（行号自指 + 范围覆盖本账本全表）
        last = HEADER_ROW + len(rows)
        actual_key = _text(main.cell(row=row_number, column=18).value)
        actual_result = _text(main.cell(row=row_number, column=19).value)
        if actual_key != dedupe_key_formula(row_number):
            note("dedupe_key_formula_wrong", row=row_number, asset_id=asset_id,
                 column="R", actual=actual_key[:120])
        if actual_result != dedupe_result_formula(row_number, last):
            note("dedupe_result_formula_wrong", row=row_number, asset_id=asset_id,
                 column="S", actual=actual_result[:120])

        if scope != "full":
            continue
        _check_artifact_row(row, row_number, asset_id, status, project_root, note)

    for asset_id, count in sorted(seen_here.items()):
        if asset_id and count > 1:
            note("duplicate_asset_id", asset_id=asset_id, count=count)
    for key, row_numbers in sorted(dedupe_rows.items()):
        if key and len(row_numbers) > 1:
            note("duplicate_dedupe_key", key=key, rows=row_numbers)

    # 总览公式范围必须等于本账本自己的行数
    expected_end = HEADER_ROW + len(rows)
    if "总览" in wb.sheetnames:
        overview = wb["总览"]
        for cell_ref in ("A6", "C6", "E6", "G6"):
            formula = _text(overview[cell_ref].value)
            if not formula.startswith("=") or f"${expected_end}" not in formula:
                note("stale_overview_formula", cell=cell_ref, formula=formula[:120],
                     expected_end=expected_end)
        if domain is not None:
            for offset, _category in enumerate(domain.categories):
                for column in ("B", "C"):
                    cell_ref = f"{column}{10 + offset}"
                    formula = _text(overview[cell_ref].value)
                    if not formula.startswith("=") or f"${expected_end}" not in formula:
                        note("stale_overview_formula", cell=cell_ref, formula=formula[:120],
                             expected_end=expected_end)
    else:
        note("missing_overview")

    return len(rows)


def _check_artifact_row(row, row_number: int, asset_id: str, status: str,
                        project_root: Path, note) -> None:
    if status not in ARTIFACT_STATUSES:
        return
    raw_path = _text(row[14])
    raw_sha = _text(row[19]).lower()
    paths = _registry_paths(raw_path, project_root)
    if status != "弃用":
        for path in paths:
            try:
                relative_path = path.relative_to(project_root)
            except ValueError:
                relative_path = path
            if (
                path.is_file()
                and str(relative_path).startswith("assets/art/")
                and relative_path.as_posix() not in CANONICAL_FILENAME_EXCEPTIONS
                and not PRODUCTION_NAME_PATTERN.fullmatch(path.name)
            ):
                note("noncanonical_filename", row=row_number, asset_id=asset_id, path=str(relative_path))
    if not raw_path:
        note("missing_path", row=row_number, asset_id=asset_id)
    if not raw_sha:
        note("missing_sha", row=row_number, asset_id=asset_id)
    existing_paths = [path for path in paths if path.is_file()]
    for path in paths:
        if not path.exists():
            note("path_not_found", row=row_number, asset_id=asset_id, path=str(path))
    if len(existing_paths) == 1 and raw_sha and re.fullmatch(r"[0-9a-f]{64}", raw_sha):
        actual_sha = _sha256(existing_paths[0])
        if actual_sha != raw_sha:
            note("sha_mismatch", row=row_number, asset_id=asset_id,
                 path=str(existing_paths[0]), recorded=raw_sha, actual=actual_sha)


def check_master(index: LedgerIndex, scope: str,
                 issues: dict[str, list[dict[str, Any]]]) -> dict[str, Any]:
    """总目录：不得持有资产行，且三张跨域契约表必须与 ledger_index.json 一致。"""
    label = "master"

    def note(kind: str, **payload: Any) -> None:
        issues[kind].append({"ledger": label, **payload})

    if not index.master_path.is_file():
        note("master_missing", path=index.master_relative_path)
        return {"exists": False}
    wb = load_workbook(index.master_path)
    declared = tuple(index.raw["master"]["sheets"])
    if ASSET_SHEET in wb.sheetnames:
        rows = _read_asset_rows(wb[ASSET_SHEET])
        if rows:
            note("master_still_holds_asset_rows", rows=len(rows))
    for sheet in declared:
        if sheet not in wb.sheetnames:
            note("master_sheet_missing", sheet=sheet)
    for sheet in wb.sheetnames:
        if sheet not in declared:
            note("master_sheet_undeclared", sheet=sheet)

    summary: dict[str, Any] = {"exists": True, "sheets": list(wb.sheetnames)}

    # ---- 分账本索引 == ledger_index.json ----------------------------------
    ws = wb["分账本索引"] if "分账本索引" in wb.sheetnames else None
    if ws is None:
        note("master_sheet_missing", sheet="分账本索引")
    else:
        for offset, domain in enumerate(index.domains):
            row = FIRST_DATA_ROW + offset
            expected = [
                domain.name,
                domain.relative_path,
                " / ".join(domain.categories),
                len(domain.categories),
                " / ".join(domain.id_prefixes),
                len(domain.prefab_pages),
                " / ".join(domain.animation_sheets) or "无",
                domain.primary_skill,
            ]
            actual = [_text(ws.cell(row=row, column=col).value) for col in (2, 3, 4, 5, 6, 8, 10, 11)]
            for column, want, got in zip((2, 3, 4, 5, 6, 8, 10, 11), expected, actual):
                want_text = _text(want)
                if got != want_text:
                    note("index_row_mismatch", row=row, column=column,
                         expected=want_text, actual=got)
            pages = _text(ws.cell(row=row, column=9).value)
            for page in domain.prefab_pages:
                if page not in pages:
                    note("index_row_mismatch", row=row, column=9, expected=page, actual=pages)
            if not _text(ws.cell(row=row, column=1).value):
                note("index_row_missing_number", row=row)
        stray = FIRST_DATA_ROW + len(index.domains)
        for row in range(stray, stray + 5):
            cell = _text(ws.cell(row=row, column=2).value)
            if cell and cell != "合计":
                note("index_has_extra_rows", row=row, value=cell)
        summary["index_rows"] = len(index.domains)

    # ---- 总览聚合公式必须覆盖整张索引 --------------------------------------
    ws = wb["总览"] if "总览" in wb.sheetnames else None
    if ws is not None:
        last_index_row = HEADER_ROW + len(index.domains)
        for cell_ref in ("A6", "C6", "E6", "G6"):
            formula = _text(ws[cell_ref].value)
            if not formula.startswith("=") or f"${last_index_row}" not in formula:
                note("master_overview_formula_wrong", cell=cell_ref,
                     formula=formula[:120], expected_end=last_index_row)

    # ---- 3D Prefab总控 的「归属账本」必须指向真正拥有该分页的账本 ------------
    if "3D Prefab总控" in wb.sheetnames:
        ws = wb["3D Prefab总控"]
        pages_checked = 0
        for row in range(FIRST_DATA_ROW - 1, ws.max_row + 1):
            page = _text(ws.cell(row=row, column=2).value)
            if not page or page == "合计":
                continue
            owner = index.domain_for_sheet(page)
            if owner is None:
                continue
            pages_checked += 1
            recorded = _text(ws.cell(row=row, column=8).value)
            if recorded != owner.relative_path:
                note("prefab_owner_mismatch", row=row, page=page,
                     owner=owner.relative_path, recorded=recorded)
        summary["prefab_pages"] = pages_checked

    return summary


def check_registry(project_root: Path, scope: str, ledger: str | None = None,
                   workbook: Path | None = None) -> dict[str, Any]:
    issues: dict[str, list[dict[str, Any]]] = defaultdict(list)
    result: dict[str, Any] = {"project_root": str(project_root), "scope": scope}
    totals: dict[str, int] = {}
    labels: dict[str, str] = {}
    global_ids: dict[str, str] = {}
    duplicates: list[dict[str, Any]] = []

    if workbook is not None:
        wb = load_workbook(workbook)
        totals["legacy"] = scan_workbook(wb, "legacy", None, LedgerIndex.load(project_root),
                                         project_root, scope, issues)
        labels["legacy"] = str(workbook)
        result["master"] = {"exists": False}
    else:
        index = LedgerIndex.load(project_root)
        _enum_contract(index, issues)
        targets = list(index.domains)
        if ledger:
            targets = [index.domain_for_key(ledger)]
        for domain in targets:
            label = domain.key
            labels[label] = domain.relative_path
            if not domain.path.is_file():
                issues["ledger_missing"].append({"ledger": label, "path": domain.relative_path})
                continue
            wb = load_workbook(domain.path)
            totals[label] = scan_workbook(wb, label, domain, index, project_root, scope, issues)
            for row_number, row in _read_asset_rows(wb[ASSET_SHEET]):
                asset_id = _text(row[0])
                if not asset_id:
                    continue
                if asset_id in global_ids and global_ids[asset_id] != label:
                    duplicates.append({"asset_id": asset_id,
                                       "ledgers": sorted({global_ids[asset_id], label})})
                global_ids.setdefault(asset_id, label)
        for entry in duplicates:
            issues["asset_id_in_multiple_ledgers"].append(entry)
        result["master"] = check_master(index, scope, issues)
        result["ledger_index"] = {
            "domains": [d.key for d in index.domains],
            "categories": sorted(index.all_categories()),
            "prefix_pairs": sorted(f"{p}/{c}" for p, c in index.prefix_pairs()),
        }

    total_issues = {kind: len(value) for kind, value in sorted(issues.items())}
    result.update({
        "ledgers": labels,
        "ledger_totals": totals,
        "asset_count": sum(totals.values()),
        "issue_counts": total_issues,
        "issues": {kind: value[:40] for kind, value in sorted(issues.items())},
    })
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--scope", choices=("structure", "full"), default="full")
    parser.add_argument("--ledger", help="只检查某一个域（角色/敌人/关卡场景/道具/武器/特效/表现资源 或其 key）")
    parser.add_argument("--workbook", type=Path,
                        help="只检查单个工作簿（历史单体账本 / 备份），不做跨文件契约断言")
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()

    project_root = args.project_root.resolve()
    result = check_registry(project_root, args.scope, args.ledger, args.workbook)
    encoded = json.dumps(result, ensure_ascii=False, indent=2, default=dict)
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)

    issue_count = sum(result["issue_counts"].values())
    if issue_count:
        print(f"ASSET_REGISTRY_CHECK_FAILED scope={args.scope} issues={issue_count}", file=sys.stderr)
        return 1
    print(f"ASSET_REGISTRY_CHECK_OK scope={args.scope} assets={result['asset_count']} "
          f"ledgers={len(result['ledger_totals'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
