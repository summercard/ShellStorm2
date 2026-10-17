"""把「大世界 · 地下街区 v001」登记进场景分账本。

写四处（逐格写值 + 复制模板行样式，不重写既有单元格）：
  * 《资产主表》     — 1 行（街区总套件根）
  * 《3D-场景通用》  — 1 行（Blender 源阶段，未导出 GLB/Prefab）
  * 《总览》         — 把资产主表公式范围从 $961 扩到新末行
  * 《域变更日志》   — 1 条

组件级 45 件明细不进账本：它们尚未独立导入 Godot，账本只登记可独立导入/替换的
运行时边界。组件清单以 component_catalog.json 为真源，账本「备注」列写明。

Run（不要在项目根跑，根的 inspect 模块会遮蔽 stdlib）：
    python scripts/register_underground_street_ledger.py
"""

from __future__ import annotations

import copy
import hashlib
import json
from datetime import date
from pathlib import Path

from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
ASSET_ID = "ENV-OPENWORLD-UNDERGROUND-STREET"
VERSION = "v001"
SUITE = "underground_street"
OUT_DIR = ROOT / "art_source/environments/open_world/source" / SUITE / VERSION
BLEND = OUT_DIR / ("env_%s_source_%s.blend" % (SUITE, VERSION))
FIRST_DATA_ROW = 6


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)).replace("\\", "/")


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def copy_style(source_cell, target_cell) -> None:
    target_cell._style = copy.copy(source_cell._style)


def dedupe_key(row: int) -> str:
    return (
        f'=LOWER(TRIM(C{row})&"|"&TRIM(D{row})&"|"&TRIM(E{row})'
        f'&"|"&TRIM(F{row})&"|"&TRIM(H{row})&"|"&TRIM(I{row}))'
    )


def dedupe_result(row: int, last_row: int) -> str:
    return f'=IF(COUNTIF($R${FIRST_DATA_ROW}:$R${last_row},R{row})>1,"重复","唯一")'


def main() -> None:
    catalog = json.loads((OUT_DIR / "component_catalog.json").read_text(encoding="utf-8"))
    audit = json.loads((OUT_DIR / "qa/source_audit.json").read_text(encoding="utf-8"))
    valid = json.loads((OUT_DIR / "qa/validate_game_prop.json").read_text(encoding="utf-8"))
    plan = json.loads((OUT_DIR / "component_plan.json").read_text(encoding="utf-8"))
    blend_sha = sha256_of(BLEND)

    wb = load_workbook(LEDGER)
    report: dict[str, object] = {}

    # ---------------- 1. 资产主表 ----------------
    main_sheet = wb["资产主表"]
    template_row = main_sheet.max_row
    row = template_row + 1
    values = {
        1: ASSET_ID,
        2: "大世界 地下街区 52×52m 街区场景",
        3: "场景",
        4: "openworld_street_diorama",
        5: "open_world_underground_street",
        6: "street_root",
        8: "Top3D / Blender Z-up",
        9: "default",
        10: "大世界地下街区（cavern street）街区对角参照场景；可整体替换、可拆件复用",
        11: "Blender源已完成",
        12: "P1",
        13: VERSION,
        14: (
            "Blender XYZ 52.0×52.0×30.0m 总包络（含穹顶）；"
            "组件 %d 件 / 实例 %d 个 / %d 三角面；街区 open_world 地下区"
            % (catalog["unique_component_count"], catalog["total_instance_count"], valid["polygon_count"])
        ),
        15: rel(BLEND),
        16: (
            "用户提供赛博朋克街区概念图；docs/ART_SOURCE_LAYOUT.md；"
            "docs/v0.1/05.1_关卡区块设计.md；docs/v0.1/05.2_关卡版图白盒与生成规范.md；"
            "docs/v0.1/10_资产与内容规范.md；%s"
            % rel(OUT_DIR / "component_catalog.json")
        ),
        17: (
            "地下街区;underground_street;open_world;赛博朋克街区;HOTEL;藥;BAR;"
            "SECTOR07;東區;cavern street;大世界地下"
        ),
        20: blend_sha,
        21: "摩斯拉",
        22: date.today().isoformat(),
        23: "项目自制；用户提供参考图，仅据图建模，未作授权推断",
        24: "underground_street",
        25: (
            "清单：%s；实例布局：%s；组件计划：%s；QA：%s、%s。"
            "仅 Blender 源阶段：45 个独立资产包已建但未导出 GLB/PackedScene，"
            "无碰撞/导航/LOD；账本只登记可整体替换的街区总套件，组件级明细以 component_catalog.json 为真源。"
            % (
                rel(OUT_DIR / "component_catalog.json"),
                rel(OUT_DIR / "component_instances.json"),
                rel(OUT_DIR / "component_plan.json"),
                rel(OUT_DIR / "qa/source_audit.json"),
                rel(OUT_DIR / "qa/validate_game_prop.json"),
            )
        ),
    }
    for column, value in values.items():
        cell = main_sheet.cell(row=row, column=column)
        cell.value = value
        copy_style(main_sheet.cell(row=template_row, column=column), cell)
    main_sheet.cell(row=row, column=18).value = dedupe_key(row)
    main_sheet.cell(row=row, column=19).value = dedupe_result(row, row)
    copy_style(main_sheet.cell(row=template_row, column=18), main_sheet.cell(row=row, column=18))
    copy_style(main_sheet.cell(row=template_row, column=19), main_sheet.cell(row=row, column=19))
    if main_sheet.row_dimensions[template_row].height:
        main_sheet.row_dimensions[row].height = main_sheet.row_dimensions[template_row].height

    rewritten = 0
    for r in range(FIRST_DATA_ROW, row + 1):
        expected = dedupe_result(r, row)
        cell = main_sheet.cell(row=r, column=19)
        if cell.value != expected:
            cell.value = expected
            rewritten += 1
    report["main_sheet"] = {"row": row, "last_row": row, "dedupe_rows_rewritten": rewritten}

    # ---------------- 2. 总览扩范围 ----------------
    overview = wb["总览"]
    extended = []
    for cells in overview.iter_rows():
        for cell in cells:
            value = cell.value
            if isinstance(value, str) and "资产主表" in value and "$961" in value:
                cell.value = value.replace("$961", "$%d" % row)
                extended.append(cell.coordinate)
    report["overview_extended_cells"] = extended

    # ---------------- 3. 3D-场景通用 ----------------
    prefab = wb["3D-场景通用"]
    ptemplate = prefab.max_row
    prow = ptemplate + 1
    pvalues = {
        1: ASSET_ID,
        2: "大世界 地下街区 52×52m 街区场景",
        3: "未建（Blender 源阶段；街区总套件不单独出 Prefab，按组件拆件导入）",
        4: "未导出（export_image_format=NONE；组件各自导出后绑公共色盘）",
        5: rel(BLEND),
        6: "地下街区围护 / 道路 / 建筑体量 / 霓虹标识 / 跨街桥 / 街道设施 / 吊顶管线",
        7: "None",
        8: "未建",
        9: "未建",
        10: "未建",
        11: "街区 52×52m；穹顶底 28.6m；组件库 45 件",
        12: "底面中心；Blender(x,y,z)→Godot(x,z,-y)；组件局部底面 Z=0",
        13: "大世界 open_world 地下街区（cavern street）",
        14: "Blender源已完成",
        15: VERSION,
        16: (
            "组件计划：唯一组件 %d / %d，同族最大 %d；四共享材质角色 + 05 环境柔雾；"
            "PaletteUV 逐面岛 %d/%d 通过。"
            % (
                catalog["unique_component_count"], plan["component_budget"]["limit"],
                max(len(v) for v in plan["families"].values()),
                valid["valid_island_polygon_count"], valid["polygon_count"],
            )
        ),
    }
    for column, value in pvalues.items():
        cell = prefab.cell(row=prow, column=column)
        cell.value = value
        copy_style(prefab.cell(row=ptemplate, column=column), cell)
    if prefab.row_dimensions[ptemplate].height:
        prefab.row_dimensions[prow].height = prefab.row_dimensions[ptemplate].height
    report["prefab_sheet"] = {"row": prow}

    # ---------------- 4. 域变更日志 ----------------
    log = wb["域变更日志"]
    ltemplate = log.max_row
    lrow = ltemplate + 1
    prev = str(log.cell(row=ltemplate, column=1).value or "v0.1.0")
    try:
        bumped = "v0.1.%d" % (int(prev.rsplit(".", 1)[-1]) + 1)
    except ValueError:
        bumped = prev + "+1"
    lvalues = {
        1: bumped,
        2: date.today().isoformat(),
        3: "新增条目",
        4: "关卡场景 / 大世界 地下街区",
        5: (
            "新增 %s（大世界地下街区 52×52m）：45 个独立资产包 + %d 个实例，"
            "四共享材质角色 + 环境柔雾；按用户赛博朋克街区参考图还原 HOTEL/藥/BAR/"
            "SECTOR07 東區 与跨街高架。"
            % (ASSET_ID, catalog["total_instance_count"])
        ),
        6: (
            "同批登记《资产主表》第 %d 行、《3D-场景通用》第 %d 行。"
            "不改动既有 AssetID / 路径 / 哈希；未改任何既存组件，未接入 Godot，未导出 GLB。"
            % (row, prow)
        ),
    }
    for column, value in lvalues.items():
        cell = log.cell(row=lrow, column=column)
        cell.value = value
        copy_style(log.cell(row=ltemplate, column=column), cell)
    report["changelog"] = {"row": lrow, "version": bumped}

    wb.save(LEDGER)
    report["blend_sha256"] = blend_sha
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
