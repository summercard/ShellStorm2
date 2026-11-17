#!/usr/bin/env python3
"""Register the independent STORY_SAFE extraction beacon in the scenes ledger."""
from __future__ import annotations

import copy
import hashlib
import json
import re
import sys
from collections import Counter
from datetime import date
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.formatting.rule import Rule
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = Path(__file__).resolve().parents[2]
PYTHON_PATH = ROOT / "scripts"
if str(PYTHON_PATH) not in sys.path:
    sys.path.insert(0, str(PYTHON_PATH))
from ledger_registry import LedgerIndex  # noqa: E402

PIPELINE_PATH = Path(__file__).resolve().parent
if str(PIPELINE_PATH) not in sys.path:
    sys.path.insert(0, str(PIPELINE_PATH))
from split_asset_ledger import (  # noqa: E402
    ASSET_SHEET,
    CONTENT_COLUMNS,
    FIRST_DATA_ROW,
    HEADER_ROW,
    _row_digest,
    col_digest,
    dedupe_key_formula,
    dedupe_result_formula,
    read_source_rows,
    sheet_digest,
)

ASSET_ID = "PRP-EXTRACTION-SAFE-BEACON-3D"
OLD_ASSET_ID = "PRP-EXTRACTION-BEACON-3D"
CATEGORY = "场景道具"
DOMAIN = "scenes"
STATUS = "Blender源已完成"
VERSION = "v001"
TODAY = date(2026, 11, 18)
WRAPPER = "assets/art/props/dungeon_3d/prp_extraction_safe_beacon_root_top3d.tscn"
GLB = "assets/art/props/dungeon_3d/components/prp_extraction_safe_beacon/prp_extraction_safe_beacon_visual_top3d.glb"
SOURCE = "art_source/props/extraction_safe_beacon/prp_extraction_safe_beacon_v001.blend"
MANIFEST = "art_source/props/extraction_safe_beacon/asset_manifest.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def copy_row_style(ws, source_row: int, target_row: int, columns: int) -> None:
    for col in range(1, columns + 1):
        ws.cell(target_row, col)._style = copy.copy(ws.cell(source_row, col)._style)
    ws.row_dimensions[target_row].height = ws.row_dimensions[source_row].height


def actual_rows(ws, first_col: int = 1) -> list[int]:
    return [row for row in range(1, ws.max_row + 1) if ws.cell(row, first_col).value not in (None, "")]


def rebuild_data_validations(ws, old_last: int, new_last: int) -> None:
    rebuilt: list[DataValidation] = []
    for dv in list(ws.data_validations.dataValidation):
        ndv = DataValidation(
            type=dv.type,
            formula1=dv.formula1,
            formula2=dv.formula2,
            allow_blank=dv.allow_blank,
            showDropDown=dv.showDropDown,
            showInputMessage=dv.showInputMessage,
            showErrorMessage=dv.showErrorMessage,
            errorTitle=dv.errorTitle,
            error=dv.error,
            promptTitle=dv.promptTitle,
            prompt=dv.prompt,
            errorStyle=dv.errorStyle,
            imeMode=dv.imeMode,
            operator=dv.operator,
        )
        ranges = []
        for cell_range in dv.sqref.ranges:
            current = copy.copy(cell_range)
            if current.min_row == FIRST_DATA_ROW and current.max_row <= old_last:
                current.max_row = new_last
            ranges.append(str(current))
        ndv.sqref = " ".join(ranges)
        rebuilt.append(ndv)
    ws.data_validations.dataValidation = []
    for dv in rebuilt:
        ws.add_data_validation(dv)


def rebuild_conditional_formatting(ws, old_last: int, new_last: int) -> None:
    entries = []
    for cf in list(ws.conditional_formatting):
        rules = list(ws.conditional_formatting[cf])
        ranges = []
        for cell_range in cf.sqref.ranges:
            current = copy.copy(cell_range)
            if current.min_row == FIRST_DATA_ROW and current.max_row <= old_last:
                current.max_row = new_last
            ranges.append(str(current))
        entries.append((" ".join(ranges), rules))
    ws.conditional_formatting = type(ws.conditional_formatting)()
    for range_string, rules in entries:
        for rule in rules:
            ws.conditional_formatting.add(range_string, rule)


def update_overview(ws, old_last: int, new_last: int) -> None:
    cells = ["A6", "C6", "E6", "G6"]
    cells += [f"{column}{row}" for row in (10, 11, 12) for column in ("B", "C")]
    for cell_ref in cells:
        formula = ws[cell_ref].value
        if isinstance(formula, str) and formula.startswith("="):
            ws[cell_ref] = re.sub(rf"\${old_last}\b", f"${new_last}", formula)


def update_source_index(index_path: Path) -> None:
    data = json.loads(index_path.read_text(encoding="utf-8"))
    sources = data["sources"]
    if any(item.get("path") == SOURCE for item in sources):
        raise AssertionError(f"source index already contains {SOURCE}")
    source_path = ROOT / SOURCE
    sources.append(
        {
            "path": SOURCE,
            "bytes": source_path.stat().st_size,
            "family": "art_source/props/extraction_safe_beacon/prp_extraction_safe_beacon_v_VERSION.blend",
            "version": [1],
            "sha256": sha256(source_path),
        }
    )
    index_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def update_baseline(baseline_path: Path, index: LedgerIndex, new_asset_values: tuple) -> None:
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    if ASSET_ID in baseline["assets"]:
        raise AssertionError(f"baseline already contains {ASSET_ID}")
    baseline["assets"][ASSET_ID] = {"v": _row_digest(new_asset_values), "c": CATEGORY, "d": DOMAIN}
    baseline["asset_count"] = len(baseline["assets"])

    all_rows = []
    for domain in index.domains:
        workbook = load_workbook(domain.path, data_only=False)
        all_rows.extend(read_source_rows(workbook[ASSET_SHEET]))
    baseline["column_digests"] = {
        str(column): col_digest(all_rows, column) for column in CONTENT_COLUMNS
    }
    baseline["category_counts"] = dict(sorted(Counter(values[2] for _, values in all_rows).items()))
    scene_workbook = load_workbook(index.domain_for_key(DOMAIN).path, data_only=False)
    baseline["sheet_digests"]["3D-设施"] = sheet_digest(scene_workbook["3D-设施"])
    baseline_path.write_text(json.dumps(baseline, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def main() -> None:
    index = LedgerIndex.load(ROOT)
    domain = index.domain_for_key(DOMAIN)
    ledger_path = domain.path
    master_path = index.master_path
    baseline_path = ROOT / "assets/registry/ledger_split_baseline.json"
    source_index_path = ROOT / "assets/registry/current_source_index.json"
    backup_dir = ROOT.parent / "ShellStorm2-backup/2026-11-18_safe_beacon_ledger/before_edits"

    for relative in (WRAPPER, GLB, SOURCE, MANIFEST):
        assert (ROOT / relative).is_file(), relative
    assert backup_dir.is_dir(), f"missing required pre-edit backup: {backup_dir}"
    for path in (ledger_path, master_path, baseline_path, source_index_path):
        candidates = (
            backup_dir / path.name,
            backup_dir / "registry" / path.name,
            backup_dir / "registry" / "ledgers" / path.name,
        )
        assert any(candidate.is_file() for candidate in candidates), f"missing backup copy: {candidates}"

    manifest = json.loads((ROOT / MANIFEST).read_text(encoding="utf-8"))
    assert manifest["asset_id"] == ASSET_ID
    assert manifest["category"] == CATEGORY
    assert manifest["package"]["runtime_wrapper"] == WRAPPER
    assert manifest["package"]["stable_glb"] == GLB
    assert manifest["package"]["source_blend"] == SOURCE

    workbook = load_workbook(ledger_path, data_only=False)
    main_sheet = workbook[ASSET_SHEET]
    main_rows = read_source_rows(main_sheet)
    existing_ids = {values[0] for _, values in main_rows}
    assert ASSET_ID not in existing_ids
    old_match = [(row, values) for row, values in main_rows if values[0] == OLD_ASSET_ID]
    assert len(old_match) == 1
    assert old_match[0][1][2] == CATEGORY
    old_last = HEADER_ROW + len(main_rows)
    new_row = old_last + 1
    copy_row_style(main_sheet, old_match[0][0], new_row, 25)

    wrapper_sha = sha256(ROOT / WRAPPER)
    main_values = [
        ASSET_ID,
        "安全撤离信标3D模块",
        CATEGORY,
        "facility",
        "extraction_safe_beacon",
        "root_3d",
        "",
        "Top3D / Godot Y-up",
        "STORY_SAFE / 8s / 99F_RETURN",
        "99F主线安全返航；独立固定设施",
        STATUS,
        "P0",
        VERSION,
        "1.659237×1.6×2.2m；3634三角；4材质；主体/自发光分离",
        WRAPPER,
        f"{MANIFEST}; {SOURCE}",
        "安全撤离;STORY_SAFE;8秒;99F返航;不刷防守怪;通讯完成;0.6秒落地",
        None,
        None,
        wrapper_sha,
        "CodeBuddy",
        TODAY,
        "项目原创（manifest未声明外部来源）",
        "01_制作组件_已统一材质;02_游戏输出_独立资产包",
        "独立安全撤离信标；wrapper=STORY_SAFE、duration=8.0、defense_encounter_enabled=false；仅通讯完整结束后投放，0.6秒落地后可用；Blender源与GLB QA通过，Godot Forward+待验；不替换普通PRP-EXTRACTION-BEACON-3D。",
    ]
    for column, value in enumerate(main_values, 1):
        main_sheet.cell(new_row, column).value = value
    new_last = new_row
    for row in range(FIRST_DATA_ROW, new_last + 1):
        main_sheet.cell(row, 18).value = dedupe_key_formula(row)
        main_sheet.cell(row, 19).value = dedupe_result_formula(row, new_last)
    main_sheet.auto_filter.ref = f"A{HEADER_ROW}:Y{new_last}"
    rebuild_data_validations(main_sheet, old_last, new_last)
    rebuild_conditional_formatting(main_sheet, old_last, new_last)
    update_overview(workbook["总览"], old_last, new_last)

    page = workbook["3D-设施"]
    page_matches = [row for row in actual_rows(page) if page.cell(row, 1).value == OLD_ASSET_ID]
    assert len(page_matches) == 1
    page_new_row = max(actual_rows(page)) + 1
    copy_row_style(page, page_matches[0], page_new_row, 16)
    page_values = [
        ASSET_ID,
        "安全撤离信标3D模块",
        WRAPPER,
        GLB,
        SOURCE,
        "固定设施安全撤离信标；通讯完成后由运行时投放，0.6秒落地可用；STORY_SAFE不刷防守怪",
        "src/world3d/ExtractionBeacon3D.gd",
        "关",
        "无",
        "无",
        "1.659237×1.6×2.2m；3634三角；4材质",
        "底面Y=0；前向+Y；Godot Y-up",
        "99F主线安全返航；独立安全撤离点",
        STATUS,
        VERSION,
        "Blender源与GLB QA通过；Godot Forward+待验；manifest=art_source/props/extraction_safe_beacon/asset_manifest.json；不刷防守怪；仅通讯完整结束投放。",
    ]
    for column, value in enumerate(page_values, 1):
        page.cell(page_new_row, column).value = value
    if page.auto_filter.ref:
        match = re.search(r":P(\d+)$", page.auto_filter.ref)
        if match and int(match.group(1)) < page_new_row:
            page.auto_filter.ref = re.sub(r":P\d+$", f":P{page_new_row}", page.auto_filter.ref)

    log = workbook["域变更日志"]
    last_log_version = str(log.cell(log.max_row, 1).value)
    version_match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", last_log_version)
    assert version_match, last_log_version
    next_log_version = f"v{version_match.group(1)}.{version_match.group(2)}.{int(version_match.group(3)) + 1}"
    log.append([
        next_log_version,
        TODAY,
        "独立安全撤离信标登记",
        ASSET_ID,
        "新增主表与3D-设施分页行；Blender源和GLB QA通过；Godot Forward+待验。STORY_SAFE主动8秒返99F，不刷防守怪；仅通讯完整结束投放，0.6秒落地后可用。",
        "不改普通PRP-EXTRACTION-BEACON-3D；不改src/data/runtime/docs；内容数据库既有item_beacon为可拾取消耗品schema，本事务不追加。",
        "CodeBuddy",
    ])
    workbook.save(ledger_path)

    update_source_index(source_index_path)

    # The master is an index, not an asset-row ledger; update only its scene counts.
    master = load_workbook(master_path, data_only=False)
    index_sheet = master["分账本索引"]
    index_row = next(row for row in range(FIRST_DATA_ROW, index_sheet.max_row + 1) if index_sheet.cell(row, 2).value == domain.name)
    index_sheet.cell(index_row, 7).value = new_last - FIRST_DATA_ROW + 1
    prefab_control = master["3D Prefab总控"]
    page_asset_rows = [
        row for row in range(1, page.max_row + 1)
        if isinstance(page.cell(row, 1).value, str) and re.fullmatch(r"[A-Z0-9]+(?:-[A-Z0-9]+)+", page.cell(row, 1).value)
    ]
    control_row = next(row for row in range(1, prefab_control.max_row + 1) if prefab_control.cell(row, 2).value == "3D-设施")
    prefab_control.cell(control_row, 3).value = int(prefab_control.cell(control_row, 3).value or 0) + 1
    prefab_control.cell(control_row, 4).value = int(prefab_control.cell(control_row, 4).value or 0) + 1
    prefab_control.cell(control_row, 5).value = int(prefab_control.cell(control_row, 5).value or 0) + 1
    prefab_control.cell(control_row, 6).value = int(prefab_control.cell(control_row, 6).value or 0)
    master.save(master_path)

    # Add only the new asset and refresh aggregate digests; preserve every prior asset v.
    updated_workbook = load_workbook(ledger_path, data_only=False)
    updated_values = tuple(updated_workbook[ASSET_SHEET].cell(new_row, column).value for column in range(1, 26))
    update_baseline(baseline_path, index, updated_values)

    print(json.dumps({
        "asset_id": ASSET_ID,
        "ledger": str(ledger_path),
        "main_row": new_row,
        "prefab_sheet": "3D-设施",
        "prefab_row": page_new_row,
        "status": STATUS,
        "version": VERSION,
        "wrapper_sha256": wrapper_sha,
        "updated_files": [
            str(ledger_path),
            str(master_path),
            str(baseline_path),
            str(source_index_path),
            str(Path(__file__).resolve()),
        ],
        "content_database": "unchanged: existing item_beacon is consumable-item schema, not fixed-facility schema",
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
