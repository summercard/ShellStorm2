"""把隐藏门（secret door）两件组件登记进场景分账本。

    python scripts/register_secret_door_ledger.py            # 写入
    python scripts/register_secret_door_ledger.py --dry-run  # 只报告

写三处（逐格写值 + 按模板行复制样式，不重写既有单元格）：
  * 《资产主表》    — 2 行
  * 《3D-场景通用》 — 2 行 prefab 页
  * 《域变更日志》  — 1 条

幂等：若 AssetID 已存在则跳过该行，不重复登记。
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from datetime import date
from pathlib import Path

from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
VERSION = "v001"
LIBRARY_ID = "ENV-EXPEDITION-SECRET-DOOR-LIBRARY"
FIRST_DATA_ROW = 6
GLB_ROOT = "assets/art/environments/tower_zones/expedition/components/common_components"
TSCN_ROOT = "assets/art/environments/tower_zones/expedition/runtime/common_components"
PKG_ROOT = Path(
    "art_source/environments/tower_zones/expedition/source/secret_door/v001"
    "/component_packages_v001/facilities"
)

COMPONENTS = (
    {
        "slug": "secret_door_leaf",
        "asset_id": "ENV-EXPEDITION-SECRET-DOOR-LEAF",
        "name_zh": "隐藏门叶 2.48×2.64m（门腔 1.70m，单扇半掩 45°，腔内自发光）",
        "root_object": "secret_door_leaf_主体",
        "usage": "远征关卡01 传送支线四个隐藏位点：木板被打掉后露出的那扇门；常驻不可破坏",
        "tags": "远征关卡01;传送支线;隐藏门;门叶;半掩门;自发光;场景组件",
        "collision_policy": "none",
        "collision_owner": "none",
        "bounds": "2.48×2.64m（含门腔 1.82m 深）",
        "origin": "底面中心；Y=0 为房间侧墙面",
        "usage_site": "远征关卡01 f00_room_03/06/07/10 四处隐藏位点",
        "note": (
            "门框 2.2×2.5 洞口对齐 office_room/door_wall 实测门洞；门腔 1.70m 深，"
            "因为单扇门开 45° 需要 2.14×sin45°≈1.51m 行程，0.85m 会让门叶穿出腔体。"
            "本件不参与碰撞：洞口由房间墙件与木板层负责阻挡。"
        ),
        "destructible": False,
    },
    {
        "slug": "secret_door_boards",
        "asset_id": "ENV-EXPEDITION-SECRET-DOOR-BOARDS",
        "name_zh": "隐藏门木板封堵 2.38×2.51m（5 横板 + 2 斜撑 + 19 钉，可打掉）",
        "root_object": "secret_door_boards_主体",
        "usage": "远征关卡01 传送支线四个隐藏位点：从房间侧钉死门洞的木板层，受击打掉",
        "tags": "远征关卡01;传送支线;隐藏门;木板封堵;可破坏;场景组件",
        "collision_policy": "component_owned",
        "collision_owner": "secret_door_host",
        "bounds": "2.38×2.51×0.14m",
        "origin": "底面中心；与门叶同一装配系（Y=0 为房间侧墙面）",
        "usage_site": "远征关卡01 f00_room_03/06/07/10 四处隐藏位点",
        "note": (
            "板间留 0.10–0.14m 缝，缝高与门腔内自发光条对齐 —— 光是物理透过板缝出来的，"
            "不是贴一张发光面。碰撞由 SecretDoor3D 的 BoardsShape 持有，打掉时只关那一层。"
        ),
        "destructible": True,
    },
)


def copy_style(source_cell, target_cell) -> None:
    target_cell._style = copy.copy(source_cell._style)


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def dedupe_key(row: int) -> str:
    return (
        f'=LOWER(TRIM(C{row})&"|"&TRIM(D{row})&"|"&TRIM(E{row})'
        f'&"|"&TRIM(F{row})&"|"&TRIM(H{row})&"|"&TRIM(I{row}))'
    )


def dedupe_result(row: int, last_row: int) -> str:
    return f'=IF(COUNTIF($R${FIRST_DATA_ROW}:$R${last_row},R{row})>1,"重复","唯一")'


def load_manifest(slug: str) -> dict:
    path = ROOT / PKG_ROOT / slug / "asset_manifest.json"
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    prepared = []
    for component in COMPONENTS:
        slug = component["slug"]
        glb_rel = f"{GLB_ROOT}/{slug}/{slug}_visual_top3d.glb"
        tscn_rel = f"{TSCN_ROOT}/{slug}/{slug}_root_top3d.tscn"
        glb_path = ROOT / glb_rel
        tscn_path = ROOT / tscn_rel
        for required in (glb_path, tscn_path):
            if not required.exists():
                raise SystemExit(f"missing required file: {required}")
        prepared.append(dict(
            component,
            manifest=load_manifest(slug),
            glb_rel=glb_rel,
            tscn_rel=tscn_rel,
            # 列 15 放的是运行时入口（tscn），哈希必须对**同一个文件**算。
            # 先写成 GLB 哈希会被 check_asset_registry 判为 hash_mismatch。
            link_rel=tscn_rel,
            link_sha256=sha256_of(tscn_path),
        ))

    wb = load_workbook(LEDGER)
    report: dict[str, object] = {"dry_run": args.dry_run}

    # ---------------- 1. 《资产主表》 ----------------
    main_sheet = wb["资产主表"]
    existing_rows: dict[str, int] = {}
    for row in range(FIRST_DATA_ROW, main_sheet.max_row + 1):
        value = main_sheet.cell(row=row, column=1).value
        if value:
            existing_rows[str(value).strip()] = row

    # 已存在的行只刷新哈希（幂等），其余列不动。
    refreshed: list[str] = []
    for item in prepared:
        row = existing_rows.get(item["asset_id"])
        if row is None:
            continue
        cell = main_sheet.cell(row=row, column=20)
        if str(cell.value or "") != item["link_sha256"]:
            if not args.dry_run:
                cell.value = item["link_sha256"]
            refreshed.append("%s@%d" % (item["asset_id"], row))
    report["hash_refreshed"] = refreshed
    template_row = main_sheet.max_row
    pending = [item for item in prepared if item["asset_id"] not in existing_rows]
    skipped = [item["asset_id"] for item in prepared if item["asset_id"] in existing_rows]
    first_new = template_row + 1
    main_rows = {}

    for offset, item in enumerate(pending):
        row = first_new + offset
        values = {
            1: item["asset_id"],
            2: item["name_zh"],
            3: "场景",
            4: "common_component_3d",
            5: item["slug"],
            6: "root_3d",
            7: None,
            8: "Top3D / local -Z 正面",
            9: "default / prefab",
            10: item["usage"],
            11: "正式美术已接入",
            12: "P1",
            13: VERSION,
            14: "结构 %s" % item["manifest"]["bounds_size_m"],
            15: item["link_rel"],
            16: "docs/v0.1/design/支线秘密房间设计.md",
            17: item["tags"],
            20: item["link_sha256"],
            21: "摩斯拉",
            22: date.today().isoformat(),
            23: "用户设计（Blender 手工建两件组件；门洞尺寸对齐 office_room/door_wall 实测 2.2×2.5）",
            24: item["slug"],
            25: "%s ｜ 库 %s ｜ 源 %s" % (
                item["note"], LIBRARY_ID, item["manifest"]["source_blend"]),
        }
        if args.dry_run:
            main_rows[item["slug"]] = row
            continue
        for column, value in values.items():
            cell = main_sheet.cell(row=row, column=column)
            cell.value = value
            copy_style(main_sheet.cell(row=template_row, column=column), cell)
        main_sheet.cell(row=row, column=18).value = dedupe_key(row)
        main_sheet.cell(row=row, column=19).value = dedupe_result(
            row, first_new + len(pending) - 1)
        copy_style(main_sheet.cell(row=template_row, column=18),
                   main_sheet.cell(row=row, column=18))
        copy_style(main_sheet.cell(row=template_row, column=19),
                   main_sheet.cell(row=row, column=19))
        if main_sheet.row_dimensions[template_row].height:
            main_sheet.row_dimensions[row].height = \
                main_sheet.row_dimensions[template_row].height
        main_rows[item["slug"]] = row

    last_row = first_new + len(pending) - 1 if pending else template_row
    if pending and not args.dry_run:
        for row in range(FIRST_DATA_ROW, last_row + 1):
            expected = dedupe_result(row, last_row)
            cell = main_sheet.cell(row=row, column=19)
            if cell.value != expected:
                cell.value = expected

    report["main_sheet"] = {
        "rows": main_rows, "skipped_existing": skipped, "last_row": last_row}

    # ---------------- 2. 《总览》扩范围 ----------------
    extended: list[str] = []
    if pending and not args.dry_run:
        overview = wb["总览"]
        for row in overview.iter_rows():
            for cell in row:
                value = cell.value
                if isinstance(value, str) and "资产主表" in value:
                    marker_old = "$%d" % template_row
                    marker_new = "$%d" % last_row
                    if marker_old in value and marker_new not in value:
                        cell.value = value.replace(marker_old, marker_new)
                        extended.append(cell.coordinate)
    report["overview_extended_cells"] = extended

    # ---------------- 3. 《3D-场景通用》 ----------------
    prefab_sheet = wb["3D-场景通用"]
    existing_prefab = {
        str(prefab_sheet.cell(row=row, column=1).value).strip()
        for row in range(2, prefab_sheet.max_row + 1)
        if prefab_sheet.cell(row=row, column=1).value
    }
    prefab_template = prefab_sheet.max_row
    prefab_rows = {}
    for offset, item in enumerate(pending):
        if item["asset_id"] in existing_prefab:
            continue
        row = prefab_template + 1 + offset
        values = {
            1: item["asset_id"],
            2: item["name_zh"],
            3: item["tscn_rel"],
            4: item["glb_rel"],
            5: item["manifest"]["source_blend"],
            6: item["usage"],
            7: "",
            8: "无" if not item["destructible"] else "有",
            9: item["collision_owner"],
            10: item["collision_policy"],
            11: item["bounds"],
            12: item["origin"],
            13: item["usage_site"],
            14: "正式美术已接入",
            15: VERSION,
            16: item["note"],
        }
        if not args.dry_run:
            for column, value in values.items():
                cell = prefab_sheet.cell(row=row, column=column)
                cell.value = value
                copy_style(prefab_sheet.cell(row=prefab_template, column=column), cell)
            if prefab_sheet.row_dimensions[prefab_template].height:
                prefab_sheet.row_dimensions[row].height = \
                    prefab_sheet.row_dimensions[prefab_template].height
        prefab_rows[item["slug"]] = row
    report["prefab_sheet"] = {"rows": prefab_rows}

    # ---------------- 4. 《域变更日志》 ----------------
    if pending and not args.dry_run:
        changelog = wb["域变更日志"]
        changelog_template = changelog.max_row
        changelog_row = changelog_template + 1
        previous_version = str(
            changelog.cell(row=changelog_template, column=1).value or "v0.1.0")
        try:
            bumped = "v0.1.%d" % (int(previous_version.rsplit(".", 1)[-1]) + 1)
        except ValueError:
            bumped = previous_version + "+1"
        changelog_values = {
            1: bumped,
            2: date.today().isoformat(),
            3: "新增条目",
            4: "关卡场景 / 远征关卡01 传送支线",
            5: (
                "新增隐藏门两件组件：门叶（门框 + 1.70m 门腔 + 单扇半掩门 + 腔内自发光）"
                "与木板封堵（5 横板 + 2 斜撑 + 19 钉，可打掉）。这是支线秘密房间的"
                "第一个正式美术资产，替换原先的程序化不透明板。"
            ),
            6: (
                "同批登记《资产主表》第 %d-%d 行、《3D-场景通用》第 %d-%d 行；"
                "不改动既有 AssetID / 路径 / 哈希，未改任何既存组件。"
                % (first_new, last_row,
                   prefab_template + 1, prefab_template + len(prefab_rows))
            ),
            7: "摩斯拉",
        }
        for column, value in changelog_values.items():
            cell = changelog.cell(row=changelog_row, column=column)
            cell.value = value
            copy_style(changelog.cell(row=changelog_template, column=column), cell)
        report["changelog"] = {"row": changelog_row, "version": bumped,
                               "previous": previous_version}
    else:
        report["changelog"] = {"skipped": True}

    if not args.dry_run and (pending or refreshed):
        wb.save(LEDGER)
    report["saved"] = bool(pending or refreshed) and not args.dry_run
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
