"""把「大世界 · 地下街区 编号02（v002）」登记进场景分账本。

写四处（逐格写值 + 复制模板行样式，不重写既有单元格）：
  * 《资产主表》     — 1 行（街区总套件根，AssetID ENV-OPENWORLD-UNDERGROUND-STREET-02）
  * 《总览》         — 把资产主表公式范围从 $972 扩到新末行（8 格）
  * 《域变更日志》   — 1 条
  * DataValidation   — sqref 从 C6:C966 扩到新行（重建，不 replace repr）

不写《3D-场景通用》：该页一行 = 一个真实存在的 Godot PackedScene；本资产仍是
纯 Blender 源阶段（未导出 GLB、未建 Prefab）。v001 亦同口径。

Run（不要在项目根跑，根的 inspect 模块会遮蔽 stdlib）：
    python scripts/register_underground_street_v2_ledger.py
"""

from __future__ import annotations

import copy
import hashlib
import json
from datetime import date
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.worksheet.datavalidation import DataValidation

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
ASSET_ID = "ENV-OPENWORLD-UNDERGROUND-STREET-02"
SUITE = "underground_street"
VERSION = "v002"
FIRST_DATA_ROW = 6
OUT_DIR = ROOT / "art_source/environments/open_world/source" / SUITE / VERSION
BLEND = OUT_DIR / ("env_%s_source_%s.blend" % (SUITE, VERSION))


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)).replace("\\", "/")


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


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
    template_row = main_sheet.max_row          # 972 = 天台发电机行
    row = 973
    assert template_row == 972, "账本末行已变（%d），先核对再写" % template_row

    families = plan["families"]
    values = {
        1: ASSET_ID,
        2: "大世界 地下街区 编号02 52×52m 街区场景",
        3: "场景",
        4: "openworld_street_diorama",
        5: "open_world_underground_street_02",
        6: "street_root_02",
        8: "Top3D / Blender Z-up",
        9: "default",
        10: "大世界地下街区（cavern street）第 2 段街区：路口居中、双侧满铺建筑、沿街纵深机位；可整体替换、可拆件复用",
        11: "Blender源已完成",
        12: "P1",
        13: VERSION,
        14: (
            "Blender XYZ 52.0×52.0×30.0m 总包络（含穹顶）；组件 %d 件（复用 v001 %d / 新生产 %d）/ "
            "实例 %d 个 / %d 三角面；同族最大 %d（≤3）；街区 open_world 地下区"
            % (catalog["unique_component_count"], catalog["reused_component_count"],
               catalog["new_component_count"], catalog["total_instance_count"],
               valid["polygon_count"], max(len(v) for v in families.values()))
        ),
        15: rel(BLEND),
        16: (
            "用户提供赛博朋克街区概念图（同一张图的两段街区取景）；docs/ART_SOURCE_LAYOUT.md；"
            "docs/v0.1/05.1_关卡区块设计.md；docs/v0.1/05.2_关卡版图白盒与生成规范.md；"
            "docs/v0.1/10_资产与内容规范.md；%s" % rel(OUT_DIR / "component_plan.json")
        ),
        17: (
            "地下街区;underground_street;underground_street_02;open_world;编号02;赛博朋克街区;"
            "HOTEL;藥;BAR;SECTOR07;東區;cavern street;窄谷街区;大世界地下"
        ),
        20: blend_sha,
        21: "摩斯拉",
        22: date.today().isoformat(),
        23: "项目自制；用户提供参考图，仅据图建模，未作授权推断",
        24: "underground_street_02",
        25: (
            "清单：%s；实例布局：%s；组件计划：%s；QA：%s、%s。"
            "复用 v001 组件生成器函数（同一函数体，几何零漂移，%d 件），本版新生产 4 件"
            "（蒸汽排风口 / 窄巷店面 / 悬臂信号灯杆 / 售货机柜组）。"
            "仅 Blender 源阶段：%d 个独立资产包已建但未导出 GLB/PackedScene，"
            "无碰撞/导航/LOD；不写入《3D-场景通用》（该页一行 = 一个真实 PackedScene）。"
            % (
                rel(OUT_DIR / "component_catalog.json"),
                rel(OUT_DIR / "component_instances.json"),
                rel(OUT_DIR / "component_plan.json"),
                rel(OUT_DIR / "qa/source_audit.json"),
                rel(OUT_DIR / "qa/validate_game_prop.json"),
                catalog["reused_component_count"],
                catalog["unique_component_count"],
            )
        ),
    }
    for column, value in values.items():
        cell = main_sheet.cell(row=row, column=column)
        cell.value = value
        cell._style = copy.copy(main_sheet.cell(row=template_row, column=column)._style)
    for column in (18, 19):
        cell = main_sheet.cell(row=row, column=column)
        cell._style = copy.copy(main_sheet.cell(row=template_row, column=column)._style)
    main_sheet.cell(row=row, column=18).value = dedupe_key(row)
    main_sheet.cell(row=row, column=19).value = dedupe_result(row, row)
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
            if isinstance(value, str) and "资产主表" in value and "$972" in value:
                cell.value = value.replace("$972", "$%d" % row)
                extended.append(cell.coordinate)
    report["overview_extended_cells"] = extended
    # 技能文档写的 8 格（A6/C6/E6/G6/B10/C10/B11/C11）是早期口径；本账本另有
    # 合计行 A13/B13/C13 与第 15-20 行分页统计也引用 $972 ⇒ 实际 12 格，全部同步扩。
    assert len(extended) >= 8, "总览应至少扩 8 格，实际 %d" % len(extended)

    # ---------------- 3. DataValidation 扩到新行 ----------------
    kept = []
    for dv in list(main_sheet.data_validations.dataValidation):
        ranges = list(dv.sqref.ranges)
        kept.append((dv, [str(r) for r in ranges]))
    main_sheet.data_validations.dataValidation = []
    dv_report = []
    for dv, ranges in kept:
        new_ranges = []
        for text in ranges:
            head, _, tail = text.partition(":")
            if tail and tail[1:].isdigit():
                new_ranges.append("%s:%s%d" % (head, head[0], row))
            else:
                new_ranges.append(text)
        ndv = DataValidation(
            type=dv.type, formula1=dv.formula1, formula2=dv.formula2,
            allow_blank=dv.allow_blank, showErrorMessage=dv.showErrorMessage,
        )
        ndv.sqref = " ".join(new_ranges)
        main_sheet.add_data_validation(ndv)
        dv_report.append({"old": ranges, "new": new_ranges})
    report["data_validations"] = dv_report

    # ---------------- 4. 域变更日志 ----------------
    log = wb["域变更日志"]
    ltemplate = log.max_row
    lrow = ltemplate + 1
    prev = str(log.cell(row=ltemplate, column=1).value or "v0.1.45")
    bumped = "v0.1.%d" % (int(prev.rsplit(".", 1)[-1]) + 1)
    lvalues = {
        1: bumped,
        2: date.today().isoformat(),
        3: "新增条目",
        4: "关卡场景 / 大世界 地下街区 编号02",
        5: (
            "新增 %s（大世界地下街区第 2 段，52×52m）：%d 个独立资产包 + %d 个实例，"
            "%d 三角面；复用 v001 组件 %d 件（同一生成器函数，几何零漂移），"
            "新生产 4 件（蒸汽 / 窄巷店面 / 悬臂信号灯杆 / 售货机柜组）。"
            % (ASSET_ID, catalog["unique_component_count"], catalog["total_instance_count"],
               valid["polygon_count"], catalog["reused_component_count"])
        ),
        6: (
            "同批登记《资产主表》第 %d 行；总览公式范围 $972→$%d；"
            "不改动既有 AssetID / 路径 / 哈希；未写入《3D-场景通用》（无 PackedScene）。"
            % (row, row)
        ),
    }
    for column, value in lvalues.items():
        cell = log.cell(row=lrow, column=column)
        cell.value = value
        cell._style = copy.copy(log.cell(row=ltemplate, column=column)._style)
    report["changelog"] = {"row": lrow, "version": bumped}

    wb.save(LEDGER)
    report["blend_sha256"] = blend_sha
    report["catalog"] = {
        "components": catalog["unique_component_count"],
        "instances": catalog["total_instance_count"],
        "polygons": valid["polygon_count"],
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
