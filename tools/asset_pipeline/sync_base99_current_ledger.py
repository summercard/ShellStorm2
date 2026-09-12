"""Synchronize the authoritative Base99 rows with the current asset graph."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path

from openpyxl import load_workbook


DONE_STATUSES = (
    "已完成",
    "原型已接入",
    "正式美术已接入",
    "已优化并正式接入",
    "Blender源已完成",
    "已导入；优化完成",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rel(root: Path, path: Path) -> str:
    return str(path.relative_to(root)).replace("\\", "/")


def manifests_by_slug(root: Path) -> dict[str, tuple[int, Path, dict]]:
    result: dict[str, tuple[int, Path, dict]] = {}
    for path in (root / "source/art/blender/base_facility_layout/component_packages").rglob("asset_manifest.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        slug = str(data.get("asset_slug", "")).strip()
        if not slug:
            continue
        match = re.search(r"v(\d{3})", str(data.get("version", "")))
        version = int(match.group(1)) if match else -1
        current = result.get(slug)
        if current is None or (version, str(path)) > (current[0], str(current[1])):
            result[slug] = (version, path, data)
    return result


def set_formula(ws, row: int) -> None:
    ws.cell(row, 18).value = f'=LOWER(TRIM(C{row})&"|"&TRIM(D{row})&"|"&TRIM(E{row})&"|"&TRIM(F{row})&"|"&TRIM(H{row})&"|"&TRIM(I{row}))'
    ws.cell(row, 19).value = f'=IF(COUNTIF($R$6:$R$424,R{row})>1,"重复","唯一")'


def update_workbook(root: Path, dry_run: bool) -> dict:
    workbook_path = root / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
    workbook = load_workbook(workbook_path, data_only=False)
    main = workbook["资产主表"]
    overview = workbook["总览"]
    manifest_map = manifests_by_slug(root)
    master = "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v025.blend"
    updated = defaultdict(int)

    explicit = {
        237: (
            "assets/art/environments/base_facility_3d/runtime/env_base99_wall_door_5x9/env_base99_wall_door_5x9_root_top3d_v003.tscn",
            "v003",
            "已完成",
            master + "; source/art/blender/base_facility_layout/export/v025/base_facility_runtime_layout_hq-v025-door_wall_palette.blend; assets/art/environments/base_facility_3d/components/env_base99_wall_door_5x9/env_base99_wall_door_5x9_visual_top3d_v003.glb",
        ),
        240: (
            "assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v002.tscn",
            "v002",
            "原型已接入",
            master + "; assets/art/environments/base_facility_3d/runtime/env_base_facility_art_layout_top3d_v002.tscn",
        ),
        241: (
            "assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/env_base99_corner_l_5m_root_top3d_v003.tscn",
            "v003",
            "正式美术已接入",
            master + "; source/art/blender/base_facility_layout/component_packages/architecture/base_corner_l_5m/base_corner_l_5m_source_v024.blend; assets/art/environments/base_facility_3d/components/env_base99_corner_l_5m/env_base99_corner_l_5m_visual_top3d_v001.glb",
        ),
        417: (
            "assets/art/environments/base_facility_3d/runtime/env_base99_wall_contents_v021/env_base99_wall_contents_root_top3d_v003.tscn",
            "v003",
            "已导入；优化完成",
            master + "; assets/art/environments/base_facility_3d/source/env_base99_wall_contents_v021_manifest.json",
        ),
        418: (
            "assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021/env_base99_remaining_facilities_root_top3d_v004.tscn",
            "v004",
            "已导入；优化完成",
            master + "; assets/art/environments/base_facility_3d/source/env_base99_remaining_facilities_v021_manifest.json",
        ),
    }

    for row in range(6, main.max_row + 1):
        asset_id = str(main.cell(row, 1).value or "").strip()
        if "BASE99" not in asset_id.upper() and asset_id != "ENV-TOWER-CORNER-L-5M":
            continue

        if row == 235:
            main.cell(row, 11).value = "弃用"
            main.cell(row, 15).value = None
            main.cell(row, 16).value = "聚合目录条目，不属于独立 PackedScene；由布局与 BPK 子项登记"
            main.cell(row, 20).value = None
            updated["deprecated"] += 1
            continue

        if asset_id.startswith("BPK-BASE99-"):
            slug = asset_id.removeprefix("BPK-BASE99-").lower().replace("-", "_")
            manifest = manifest_map.get(slug)
            if manifest is None:
                raise RuntimeError(f"Missing manifest for {asset_id} ({slug})")
            _version, manifest_path, manifest_data = manifest
            main.cell(row, 15).value = rel(root, manifest_path)
            main.cell(row, 16).value = master + "; " + rel(root, manifest_path)
            main.cell(row, 13).value = str(manifest_data.get("version", main.cell(row, 13).value or "v001"))
            updated["manifest_rows"] += 1

        if row in explicit:
            path, version, status, source = explicit[row]
            main.cell(row, 15).value = path
            main.cell(row, 13).value = version
            main.cell(row, 11).value = status
            main.cell(row, 16).value = source
            updated["explicit_rows"] += 1

        path_value = str(main.cell(row, 15).value or "").strip()
        if path_value and not path_value.startswith("="):
            path = root / path_value
            if path.is_file():
                main.cell(row, 20).value = sha256(path)
                updated["sha_rows"] += 1

    for row in range(6, main.max_row + 1):
        set_formula(main, row)
    updated["formula_rows"] = main.max_row - 5

    end = main.max_row
    overview["A6"] = f"=COUNTA('资产主表'!$A$6:$A${end})"
    active_formula = "+".join(f'COUNTIF(\'资产主表\'!$K$6:$K${end},"{status}")' for status in DONE_STATUSES)
    overview["C6"] = "=" + active_formula
    overview["E6"] = f'=COUNTIF(\'资产主表\'!$K$6:$K${end},"待制作")+COUNTIF(\'资产主表\'!$K$6:$K${end},"程序占位")'
    overview["G6"] = f'=COUNTIF(\'资产主表\'!$S$6:$S${end},"重复")'
    for row in range(10, 19):
        category = overview.cell(row, 1).value
        overview.cell(row, 2).value = f"=COUNTIF('资产主表'!$C$6:$C${end},A{row})"
        status_sum = "+".join(f'(\'资产主表\'!$K$6:$K${end}="{status}")' for status in DONE_STATUSES)
        overview.cell(row, 3).value = f"=SUMPRODUCT(('资产主表'!$C$6:$C${end}=A{row})*({status_sum}))"
        if not category:
            updated["overview_incomplete"] += 1

    if not dry_run:
        workbook.save(workbook_path)
    return dict(updated)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    result = update_workbook(args.project.resolve(), args.dry_run)
    print("BASE99_LEDGER_SYNC", result, "dry_run=" + str(args.dry_run))


if __name__ == "__main__":
    main()
