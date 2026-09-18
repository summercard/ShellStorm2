#!/usr/bin/env python3
"""Split the monolithic art-asset workbook into per-domain ledgers plus a master index.

Input  : assets/registry/ShellStorm2_美术资产台账_v001.xlsx   (monolithic, 资产主表 = 唯一登记源)
Output : assets/registry/ShellStorm2_美术资产台账_v001.xlsx   (总目录: 跨域契约 + 分账本索引)
         assets/registry/ledgers/ShellStorm2_<域>账本_v001.xlsx  ×N  (可独立并行编辑)
         assets/registry/ledger_split_baseline.json             (拆分前逐格指纹, 供无损证明)

The domain map lives in assets/registry/ledger_index.json — this script never hardcodes it.

Guarantees
----------
* 资产主表 rows are partitioned by 大类: every source row lands in exactly one domain ledger,
  in source order, with every cell byte-identical.
* 域内专表 (3D-* / 角色组件 / 动画与状态 / 原型角色 / 角色中转记录) move wholesale, unmodified.
* 查重键 / 查重结果 formulas are rewritten to the new row span so each ledger is self-validating.
* 数据校验 (DV) ranges, 条件格式 (CF) ranges and the filter range are re-scoped to the new span.
* The master keeps only cross-domain contracts and becomes read-only for asset rows.

Exit codes: 0 OK, 1 failure.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import shutil
import sys
from datetime import date, datetime
from pathlib import Path
from typing import Any, Iterable

try:
    from openpyxl import load_workbook
    from openpyxl.formatting.formatting import ConditionalFormattingList
    from openpyxl.formatting.rule import Rule
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.styles.differential import DifferentialStyle
    from openpyxl.utils import get_column_letter
    from openpyxl.worksheet.datavalidation import DataValidation
except ImportError as exc:  # pragma: no cover - actionable setup failure
    raise SystemExit("openpyxl is required: pip install openpyxl") from exc

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from ledger_registry import LedgerIndex  # noqa: E402

ASSET_SHEET = "资产主表"
HEADER_ROW = 5
FIRST_DATA_ROW = 6
COLUMN_COUNT = 25
# R(18)=查重键 / S(19)=查重结果 是每行按当前行号重算的派生公式：
# 拆账本时行号必然改变，所以它们不进「内容指纹」，改由公式形状断言把关。
DERIVED_COLUMNS = (18, 19)
CONTENT_COLUMNS = tuple(c for c in range(1, COLUMN_COUNT + 1) if c not in DERIVED_COLUMNS)

# 大类 -> 允许值 (主账本历史上分了几段互不一致的 DV, 这里收敛成一份)
CATEGORY_VALUES = [
    "角色", "敌人", "武器", "道具", "场景", "场景道具", "基地资产包", "UI", "特效", "音频",
]
STATUS_VALUES = [
    "待制作", "程序占位", "已完成", "原型已接入", "弃用",
    "旧资产已从正式基地移除", "正式美术已接入", "已优化并正式接入",
    "Blender源已完成", "已导入；优化完成",
    # 历史上出现过但未被门禁枚举接纳的值: 保留在 DV 里, 以免打开文件时被标红
    "已从运行场景移除", "白盒组件",
]
PRIORITY_VALUES = ["P0", "P1", "P2", "P3"]

# 条件格式: 与源文件 dxf0/1/2 逐属性对齐
CF_REPEAT = DifferentialStyle(
    font=Font(bold=True, color="FFA61B1B"),
    fill=PatternFill(bgColor="FFFFD6D6"),
)
CF_DONE = DifferentialStyle(
    font=Font(color="FF176C4A"),
    fill=PatternFill(bgColor="FFD9F3E8"),
)
CF_TODO = DifferentialStyle(
    font=Font(color="FF8A4B08"),
    fill=PatternFill(bgColor="FFFFF0D6"),
)
DXF_DONE_VALUES = ("已完成", "原型已接入", "正式美术已接入", "已优化并正式接入", "Blender源已完成", "已导入；优化完成")


def _text(value: Any) -> str:
    return "" if value is None else str(value).strip()


def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _row_digest(values: Iterable[Any]) -> str:
    """内容指纹：只覆盖登记列（跳过派生的查重键/查重结果）。"""
    return _sha256_text(
        "\u001f".join(_text(values[c - 1]) for c in CONTENT_COLUMNS)
    )


# --------------------------------------------------------------------------- #
# 样式模板: 从源账本抓取, 使新表与既有视觉语言一致
# --------------------------------------------------------------------------- #
class Templates:
    def __init__(self, wb) -> None:
        def style(sheet: str, ref: str):
            return copy.copy(wb[sheet][ref]._style)

        self.title = style("总览", "A1")
        self.subtitle = style("总览", "A3")
        self.label = style("总览", "A5")
        self.big_number = style("总览", "A6")
        self.section = style("总览", "A9")
        self.table_header = style("资产主表", "A5")
        self.data = style("资产主表", "A6")
        self.banner = style("3D-特效", "A5")
        self.log_header = style("版本记录", "A5")
        self.log_data = style("版本记录", "A6")
        self.note_fill = PatternFill(fill_type="solid", start_color="FFFDF3D6", end_color="FFFDF3D6")
        self.note_font = Font(name="Carlito", sz=9, color="FF7A4B00")
        self.note_align = Alignment(vertical="top", wrap_text=True)


def _write(ws, row: int, col: int, value: Any, style=None):
    cell = ws.cell(row=row, column=col, value=value)
    if style is not None:
        cell._style = copy.copy(style)
    return cell


def _style_range(ws, row: int, first_col: int, last_col: int, style) -> None:
    for col in range(first_col, last_col + 1):
        ws.cell(row=row, column=col)._style = copy.copy(style)


def _set_widths(ws, widths: dict[str, float]) -> None:
    for letter, width in widths.items():
        ws.column_dimensions[letter].width = width


def _blank_row(ws, row: int, first_col: int, last_col: int, style) -> None:
    for col in range(first_col, last_col + 1):
        _write(ws, row, col, None, style)
    ws.row_dimensions[row].height = 6


# --------------------------------------------------------------------------- #
# 源账本读取
# --------------------------------------------------------------------------- #
def read_source_rows(ws) -> list[tuple[int, tuple[Any, ...]]]:
    rows: list[tuple[int, tuple[Any, ...]]] = []
    for row in range(FIRST_DATA_ROW, ws.max_row + 1):
        if not _text(ws.cell(row=row, column=1).value):
            continue
        rows.append((row, tuple(ws.cell(row=row, column=col).value for col in range(1, COLUMN_COUNT + 1))))
    return rows


def sheet_digest(ws) -> str:
    """专表逻辑指纹：合并区 + 非空单元格内容 + 非空内容的外接矩形。

    刻意不记录 ``ws.max_row`` / ``ws.max_column``：那两个值反映的是「openpyxl 内存里
    被访问过的单元格」（含只有样式的空格），同一张表被 openpyxl 往返读写一次就会变，
    与被搬运的内容无关。真正该守的是内容本身，落成 bbox（非空内容的外接矩形）——
    内容真被裁掉一列/一段时 bbox 会变，而结尾的样式空行不会。
    """
    parts: list[str] = []
    for rng in sorted(str(r) for r in ws.merged_cells.ranges):
        parts.append(f"merge:{rng}")
    cells = [
        (cell.row, cell.column, cell.coordinate, cell.value)
        for row in ws.iter_rows()
        for cell in row
        if cell.value not in (None, "")
    ]
    if cells:
        parts.append(
            f"bbox={min(c[0] for c in cells)}:{max(c[0] for c in cells)}"
            f"x{min(c[1] for c in cells)}:{max(c[1] for c in cells)}"
        )
    else:
        parts.append("bbox=empty")
    for _row, _col, coordinate, value in sorted(cells, key=lambda item: (item[0], item[1])):
        parts.append(f"{coordinate}={value!r}")
    return _sha256_text("\n".join(parts))


def col_digest(rows: list[tuple[int, tuple[Any, ...]]], col_index: int) -> str:
    """列指纹，取规范行序（AssetID 升序）。

    基线按源账本行序采集、校验按归属账本读取，两者行序必然不同；不规范化的话
    列级定位会 100% 误报「每列都漂移」。AssetID 在本账本里唯一，排序是确定性的。
    """
    ordered = sorted(rows, key=lambda item: (_text(item[1][0]), _text(item[1][col_index - 1])))
    return _sha256_text("\u001e".join(_text(item[1][col_index - 1]) for item in ordered))


# --------------------------------------------------------------------------- #
# 派生列公式（R=查重键, S=查重结果）
#
# 只在这里定义一次：rescore 时写它，门禁与无损校验断言它。之前「写入端写字符串字面量、
# 校验端另抄一份」是典型的隐形契约 —— 公式一改，校验会继续对着旧形状点头。
# --------------------------------------------------------------------------- #
def dedupe_key_formula(row: int) -> str:
    return (
        f'=LOWER(TRIM(C{row})&"|"&TRIM(D{row})&"|"&TRIM(E{row})'
        f'&"|"&TRIM(F{row})&"|"&TRIM(H{row})&"|"&TRIM(I{row}))'
    )


def dedupe_result_formula(row: int, last_row: int) -> str:
    return f'=IF(COUNTIF($R${FIRST_DATA_ROW}:$R${last_row},R{row})>1,"重复","唯一")'


def build_baseline(source_path: Path, index: LedgerIndex, rows, wb) -> dict[str, Any]:
    assets: dict[str, Any] = {}
    for _row, values in rows:
        asset_id = _text(values[0])
        record = {
            "v": _row_digest(values),
            "c": _text(values[2]),
            "d": index.domain_for_category(_text(values[2])).key,
        }
        if asset_id in assets:
            assets[asset_id]["dup"] = assets[asset_id].get("dup", 1) + 1
        else:
            assets[asset_id] = record
    return {
        "schema_version": 1,
        "source": index.master_relative_path,
        "captured_at": datetime.now().isoformat(timespec="seconds"),
        "sheet": ASSET_SHEET,
        "columns": [wb[ASSET_SHEET].cell(row=HEADER_ROW, column=c).value for c in range(1, COLUMN_COUNT + 1)],
        "derived_columns": list(DERIVED_COLUMNS),
        "derived_note": "R=查重键 / S=查重结果 为逐行派生公式，不进内容指纹；由门禁的公式形状断言把关。",
        "asset_count": len(rows),
        "assets": dict(sorted(assets.items())),
        "column_digests": {
            str(c): col_digest(rows, c) for c in CONTENT_COLUMNS
        },
        "sheet_digests": {
            name: sheet_digest(wb[name])
            for name in wb.sheetnames
            if name not in (ASSET_SHEET, "总览")
        },
        "category_counts": {
            cat: sum(1 for _r, v in rows if _text(v[2]) == cat)
            for cat in sorted({_text(v[2]) for _r, v in rows})
        },
    }


# --------------------------------------------------------------------------- #
# 分账本构建
# --------------------------------------------------------------------------- #
def filter_asset_rows(ws, keep_rows: set[int]) -> int:
    drop = [r for r in range(FIRST_DATA_ROW, ws.max_row + 1) if r not in keep_rows]
    for row in sorted(drop, reverse=True):
        ws.delete_rows(row, 1)
    return len(keep_rows)


def rescope_asset_sheet(ws, row_count: int) -> None:
    """Rewrite per-row dedupe formulas and re-scope DV / CF / filter to the new span."""
    last = HEADER_ROW + row_count
    for row in range(FIRST_DATA_ROW, last + 1):
        ws.cell(row=row, column=18).value = dedupe_key_formula(row)
        ws.cell(row=row, column=19).value = dedupe_result_formula(row, last)

    ws.data_validations.dataValidation.clear()
    for col, values in ((3, CATEGORY_VALUES), (11, STATUS_VALUES), (12, PRIORITY_VALUES)):
        dv = DataValidation(
            type="list",
            formula1='"' + ",".join(values) + '"',
            allow_blank=True,
            showDropDown=False,
            showErrorMessage=False,
        )
        ws.add_data_validation(dv)
        dv.add(f"{get_column_letter(col)}{FIRST_DATA_ROW}:{get_column_letter(col)}{last}")

    ws.conditional_formatting = ConditionalFormattingList()
    ws.conditional_formatting.add(
        f"S{FIRST_DATA_ROW}:S{last}",
        Rule(type="containsText", operator="containsText", text="重复", dxf=CF_REPEAT, priority=1),
    )
    ws.conditional_formatting.add(
        f"K{FIRST_DATA_ROW}:K{last}",
        Rule(type="containsText", operator="containsText", text="已完成", dxf=CF_DONE, priority=2),
    )
    ws.conditional_formatting.add(
        f"K{FIRST_DATA_ROW}:K{last}",
        Rule(type="containsText", operator="containsText", text="待制作", dxf=CF_TODO, priority=3),
    )
    # 原文件里 asset master 挂着 ref=A5:X115 的 Excel 表(与 429 行数据不符)。
    # 拆成 7 份后每份都得改 ref, 而表对象不一致会让 Excel 弹修复提示;
    # 因此改用等价且更稳的自动筛选范围, 保留「能筛」这个真实用途。
    ws.auto_filter.ref = f"A{HEADER_ROW}:X{last}"


def build_domain_overview(ws, domain, tpl: Templates, totals: dict[str, Any]) -> None:
    """Rewrite the (inherited) 总览 sheet in place, keeping merges and row heights."""
    cols = "ABCDEFGHIJ"
    for row in range(1, ws.max_row + 1):
        for col in range(1, 11):
            if ws.cell(row=row, column=col).value not in (None, ""):
                ws.cell(row=row, column=col).value = None

    _write(ws, 1, 1, f"SHELLSTORM 2 · {domain.name}美术账本 v0.1", tpl.title)
    _write(
        ws, 3, 1,
        f"归属域={domain.name}｜覆盖大类={' / '.join(domain.categories)}｜"
        f"AssetID 前缀={' / '.join(domain.id_prefixes)}｜"
        f"主账本（总目录）={domain.index.master_relative_path}；本账本可独立并行编辑，跨域契约见主账本",
        tpl.subtitle,
    )
    _write(ws, 5, 1, "资产总数", tpl.label)
    _write(ws, 5, 3, "已完成/已接入", tpl.label)
    _write(ws, 5, 5, "待制作/程序占位", tpl.label)
    _write(ws, 5, 7, "重复警报", tpl.label)
    _write(ws, 5, 9, "域内专表 / 3D Prefab 分页", tpl.label)
    n = totals["row_count"]
    last = HEADER_ROW + n
    _write(ws, 6, 1, f"=COUNTA('{ASSET_SHEET}'!$A${FIRST_DATA_ROW}:$A${last})", tpl.big_number)
    _write(
        ws, 6, 3,
        "=" + "+".join(f"COUNTIF('{ASSET_SHEET}'!$K${FIRST_DATA_ROW}:$K${last},\"{v}\")" for v in DXF_DONE_VALUES),
        tpl.big_number,
    )
    _write(
        ws, 6, 5,
        f"=COUNTIF('{ASSET_SHEET}'!$K${FIRST_DATA_ROW}:$K${last},\"待制作\")"
        f"+COUNTIF('{ASSET_SHEET}'!$K${FIRST_DATA_ROW}:$K${last},\"程序占位\")",
        tpl.big_number,
    )
    _write(ws, 6, 7, f"=COUNTIF('{ASSET_SHEET}'!$S${FIRST_DATA_ROW}:$S${last},\"重复\")", tpl.big_number)
    _write(
        ws, 6, 9,
        f"域内专表：{' / '.join(domain.sheet_scope) or '无'}　|　3D Prefab 分页：{' / '.join(domain.prefab_pages) or '无'}",
        tpl.label,
    )

    _write(ws, 9, 1, "大类", tpl.section)
    _write(ws, 9, 2, "资产数", tpl.section)
    _write(ws, 9, 3, "完成/接入", tpl.section)
    _write(ws, 9, 4, None, tpl.section)
    _write(
        ws, 9, 5,
        "本账本只登记上列大类；跨域搬运资产须同步主账本《分类与编码》并重跑门禁",
        tpl.label,
    )
    row = 10
    for category in domain.categories:
        count = totals["category_counts"].get(category, 0)
        _write(ws, row, 1, category, tpl.data)
        _write(ws, row, 2, f"=COUNTIF('{ASSET_SHEET}'!$C${FIRST_DATA_ROW}:$C${last},A{row})", tpl.data)
        _write(
            ws, row, 3,
            "=SUMPRODUCT(('" + ASSET_SHEET + f"'!$C${FIRST_DATA_ROW}:$C${last}=A{row})*("
            + "+".join(f"('{ASSET_SHEET}'!$K${FIRST_DATA_ROW}:$K${last}=\"{v}\")" for v in DXF_DONE_VALUES)
            + "))",
            tpl.data,
        )
        for col in range(4, 11):
            _write(ws, row, col, None, tpl.data)
        ws.row_dimensions[row].height = 22
        row += 1
    _write(ws, row, 1, "合计", tpl.section)
    _write(ws, row, 2, f"=SUM(B10:B{row - 1})", tpl.section)
    _write(ws, row, 3, f"=SUM(C10:C{row - 1})", tpl.section)
    _style_range(ws, row, 4, 10, tpl.section)
    row += 2

    if domain.prefab_pages:
        _write(ws, row, 1, "域内 3D Prefab 分页统计（快照口径与本账本分页一致；权威清单在各分页表）", tpl.banner)
        _style_range(ws, row, 2, 10, tpl.banner)
        ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=10)
        row += 1
        for label, col in (("分页", 1), ("Prefab 数", 2), ("直接引用 GLB", 3), ("有功能脚本", 4), ("碰撞开启", 5)):
            _write(ws, row, col, label, tpl.label)
        _write(ws, row, 6, "说明", tpl.label)
        first_page_row = row + 1
        for page in domain.prefab_pages:
            row += 1
            if page not in totals["page_shape"]:
                continue
            shape = totals["page_shape"][page]
            aid_col, glb_col, script_col, collide_col = shape
            _write(ws, row, 1, page, tpl.data)
            _write(ws, row, 2, f'=COUNTA(\'{page}\'!${aid_col}${FIRST_DATA_ROW - 1}:${aid_col}$204)', tpl.data)
            _write(ws, row, 3, f'=COUNTIF(\'{page}\'!${glb_col}${FIRST_DATA_ROW - 1}:${glb_col}$204,"<>")', tpl.data)
            _write(ws, row, 4, f'=COUNTIF(\'{page}\'!${script_col}${FIRST_DATA_ROW - 1}:${script_col}$204,"<>")', tpl.data)
            _write(ws, row, 5, f'=COUNTIF(\'{page}\'!${collide_col}${FIRST_DATA_ROW - 1}:${collide_col}$204,"开")', tpl.data)
            _write(ws, row, 6, "一行 = 一个实际存在的 Godot PackedScene", tpl.data)
            for col in range(7, 11):
                _write(ws, row, col, None, tpl.data)
        _write(ws, row + 1, 1, "合计", tpl.section)
        _write(ws, row + 1, 2, f"=SUM(B{first_page_row}:B{row})", tpl.section)
        _write(ws, row + 1, 3, f"=SUM(C{first_page_row}:C{row})", tpl.section)
        _write(ws, row + 1, 4, f"=SUM(D{first_page_row}:D{row})", tpl.section)
        _write(ws, row + 1, 5, f"=SUM(E{first_page_row}:E{row})", tpl.section)
        _style_range(ws, row + 1, 6, 10, tpl.section)

    _set_widths(ws, {"A": 18, "B": 14, "C": 14, "D": 3, "E": 8, "F": 30, "G": 42, "H": 3, "I": 21, "J": 21})
    ws.sheet_view.showGridLines = False


def build_ledger_note(wb, domain, tpl: Templates, stamp: str):
    ws = wb.create_sheet("账本说明")
    ws.sheet_view.showGridLines = False
    _set_widths(ws, {"A": 22, "B": 62, "C": 34, "D": 24, "E": 24, "F": 24})
    _write(ws, 1, 1, f"本账本说明 · {domain.name}", tpl.title)
    ws.merge_cells("A1:F2")
    _write(ws, 3, 1, "本表是分账本自描述；机器可读真源为 assets/registry/ledger_index.json，二者不一致时以 JSON 为准", tpl.subtitle)
    ws.merge_cells("A3:F3")
    rows: list[tuple[str, str]] = [
        ("账本归属域", domain.name),
        ("分账本文件", domain.relative_path),
        ("覆盖大类", " / ".join(domain.categories)),
        ("AssetID 前缀", " / ".join(domain.id_prefixes)),
        ("域内专表", " / ".join(domain.sheet_scope) or "无"),
        ("3D Prefab 分页", " / ".join(domain.prefab_pages) or "无"),
        ("动画登记表", " / ".join(domain.animation_sheets) or "无"),
        ("主账本（总目录）", domain.index.master_relative_path),
        ("跨域契约", "分类与编码 / 命名与查重 / 版本记录 / Skill 清单 / 3D Prefab 总控 —— 全部只在主账本维护"),
        ("首选制作 Skill", domain.primary_skill),
        ("协作 Skill", " / ".join(domain.supporting_skills) or "无"),
        ("负责人", domain.owner),
        ("登记范围", domain.scope_note),
        (
            "编辑边界",
            "只在本账本内增删改资产行。把资产从一个域搬到另一个域，属于跨域变更："
            "必须同时改主账本《分类与编码》与 ledger_index.json，并重跑门禁。",
        ),
        (
            "登记口径",
            "资产条目以《资产主表》一行为准；一行只能有一个大类，且必须落在本账本声明的大类内。"
            "Prefab 详情按分页登记到对应的 3D-* 表，一行 = 一个实际存在的 Godot PackedScene。",
        ),
        (
            "门禁",
            "python3 scripts/check_asset_registry.py --scope structure"
            "（需 venv python + openpyxl，且在 /tmp 下跑）",
        ),
        ("无损基线", "assets/registry/ledger_split_baseline.json；"
                     "python3 tools/asset_pipeline/verify_ledger_split.py 断言并集与拆分前逐格一致"),
        ("快照日期", stamp),
    ]
    _write(ws, 5, 1, "项", tpl.log_header)
    _write(ws, 5, 2, "值", tpl.log_header)
    for col in range(3, 7):
        _write(ws, 5, col, None, tpl.log_header)
    for offset, (key, value) in enumerate(rows, start=6):
        _write(ws, offset, 1, key, tpl.log_data)
        _write(ws, offset, 2, value, tpl.log_data)
        for col in range(3, 7):
            _write(ws, offset, col, None, tpl.log_data)
        ws.row_dimensions[offset].height = 30
    return ws


def build_ledger_changelog(wb, domain, tpl: Templates, stamp: str):
    ws = wb.create_sheet("域变更日志")
    ws.sheet_view.showGridLines = False
    _set_widths(ws, {"A": 14, "B": 13, "C": 24, "D": 28, "E": 70, "F": 48, "G": 12})
    _write(ws, 1, 1, f"{domain.name}账本变更日志", tpl.title)
    ws.merge_cells("A1:G2")
    _write(ws, 3, 1, "只记录本账本的域内变更；跨域与全局变更记录在主账本《版本记录》", tpl.subtitle)
    ws.merge_cells("A3:G3")
    headers = ["台账版本", "日期", "变更类型", "范围", "说明", "兼容性", "负责人"]
    for offset, header in enumerate(headers, start=1):
        _write(ws, 5, offset, header, tpl.log_header)
    seed = [
        "v0.1.0",
        stamp,
        "分账本建立",
        domain.name,
        f"由单体账本《{Path(domain.index.master_relative_path).name}》按大类拆分而来；"
        f"本账本接管大类={' / '.join(domain.categories)}，条目内容逐格不变，仅登记位置变化。",
        "资产条目、AssetID、路径与哈希全部不变；只换文件。旧引用可用 scripts/ledger_registry.py 解析。",
        "摩斯拉",
    ]
    for offset, value in enumerate(seed, start=1):
        _write(ws, 6, offset, value, tpl.log_data)
    ws.row_dimensions[6].height = 46
    return ws


def build_enemy_animation_sheet(wb, domain, tpl: Templates, context: dict[str, Any]):
    """建《敌人动画与状态》: 源账本没有这张表, 但敌域要求动画随怪物同账本。

    状态 ID 逐字取自 src/enemy3d/Enemy3D.gd 的 VALID_STATES(12 态), 不是编的;
    无法从代码确证的关系列一律标「待登记」, 由域负责人补齐。
    """
    ws = wb.create_sheet("敌人动画与状态")
    ws.sheet_view.showGridLines = False
    _set_widths(ws, {"A": 6, "B": 24, "C": 14, "D": 34, "E": 26, "F": 8, "G": 26, "H": 18, "I": 46})
    _write(ws, 1, 1, "敌人动画与状态 · 状态机 × 表现职责", tpl.title)
    ws.merge_cells("A1:I2")
    _write(
        ws, 3, 1,
        "状态ID 逐字取自 src/enemy3d/Enemy3D.gd 的 VALID_STATES（12 态）；敌人当前为程序驱动，尚无 Blender 动作母版。"
        "动作库接入后必须在「动作来源」列改为 Blender，并登记动作母版路径与 SHA-256。",
        tpl.subtitle,
    )
    ws.merge_cells("A3:I3")

    headers = ["序号", "状态ID", "中文名", "表现职责", "动作来源", "循环", "挂点/特效挂钩", "首版实现", "备注"]
    for offset, header in enumerate(headers, start=1):
        _write(ws, 5, offset, header, tpl.table_header)
    ws.row_dimensions[5].height = 32

    states = [
        ("dormant", "休眠", "未激活前不表现；不消耗视觉预算"),
        ("idle", "待机", "呼吸/轻微起伏；程序驱动"),
        ("patrol", "巡逻", "沿巡逻点位移；朝向跟随路径"),
        ("alert", "警觉", "锁定可疑目标；身体抬升/视线上抬"),
        ("chase", "追击", "朝玩家追击；步频随速度切换"),
        ("search", "搜寻", "丢失目标后在最后已知位置环视"),
        ("return", "归位", "脱离战斗归巡逻点"),
        ("telegraph", "预警", "出手前的蓄力前摇，必须可读"),
        ("attack", "攻击", "判定生效帧与挥击/发射表现对齐"),
        ("recovery", "收招", "攻击后的硬直表现"),
        ("stagger", "踉跄", "受击打断；闪白 + 位移"),
        ("dead", "死亡", "倒地/瓦解；播放结束即回收"),
    ]
    row = 6
    for number, (state_id, cn, duty) in enumerate(states, start=1):
        _write(ws, row, 1, number, tpl.data)
        _write(ws, row, 2, state_id, tpl.data)
        _write(ws, row, 3, cn, tpl.data)
        _write(ws, row, 4, duty, tpl.data)
        for col, value in ((5, "程序驱动（EnemyAvatar3D 仅记录 ai_state）"), (6, "待登记"),
                           (7, "待登记"), (8, "待登记"),
                           (9, "状态转移表见 src/enemy3d/Enemy3D.gd transition_to()，尚未逐条登记")):
            _write(ws, row, col, value, tpl.data)
        ws.row_dimensions[row].height = 26
        row += 1

    row += 1
    _write(ws, row, 1, "敌人条目 × 状态机对照（本账本《资产主表》的每条敌人资产都走同一套 12 态状态机）", tpl.banner)
    _style_range(ws, row, 2, 9, tpl.banner)
    ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=9)
    row += 1
    for offset, header in enumerate(["序号", "敌人ID(AssetID)", "中文名", "骨架/动作库", "状态机", "表现层级", "独立动作母版", "首版实现", "备注"], start=1):
        _write(ws, row, offset, header, tpl.label)
    first = row + 1
    for number, (asset_id, name) in enumerate(context["domain_rows"], start=1):
        row += 1
        _write(ws, row, 1, number, tpl.data)
        _write(ws, row, 2, asset_id, tpl.data)
        _write(ws, row, 3, name, tpl.data)
        _write(ws, row, 4, "无 Blender 动作母版（程序驱动）", tpl.data)
        _write(ws, row, 5, "ENEMY_AI_12_STATES", tpl.data)
        _write(ws, row, 6, "程序 Mesh / Prefab", tpl.data)
        _write(ws, row, 7, "无", tpl.data)
        _write(ws, row, 8, "待登记", tpl.data)
        _write(ws, row, 9, None, tpl.data)
    if row >= first:
        _write(ws, row + 1, 1, "合计", tpl.section)
        _write(ws, row + 1, 2, f"=COUNTA(B{first}:B{row})", tpl.section)
        _style_range(ws, row + 1, 3, 9, tpl.section)
    return ws


AUTO_SHEETS = {"敌人动画与状态": build_enemy_animation_sheet}


def build_domain_ledger(source: Path, index: LedgerIndex, domain, tpl: Templates, dest: Path,
                        keep_rows: list[int], category_counts: dict[str, int], stamp: str,
                        page_shape: dict[str, Any], domain_rows: list[tuple[str, str]]) -> dict[str, Any]:
    wb = load_workbook(source)
    ws_asset = wb[ASSET_SHEET]
    row_count = filter_asset_rows(ws_asset, set(keep_rows))
    rescope_asset_sheet(ws_asset, row_count)

    keep_sheets = {"总览", ASSET_SHEET, *domain.sheet_scope}
    for name in list(wb.sheetnames):
        if name not in keep_sheets and name not in AUTO_SHEETS:
            del wb[name]
    for sheet in domain.sheet_scope:
        if sheet in wb.sheetnames:
            continue
        factory = AUTO_SHEETS.get(sheet)
        if factory is None:
            raise SystemExit(f"[{domain.key}] ledger_index.json 声明了不存在的专表: {sheet!r}")
        factory(wb, domain, tpl, {"domain_rows": domain_rows, "stamp": stamp})

    totals = {
        "row_count": row_count,
        "category_counts": dict(category_counts),
        "page_shape": page_shape,
    }

    build_domain_overview(wb["总览"], domain, tpl, totals)
    build_ledger_note(wb, domain, tpl, stamp)
    build_ledger_changelog(wb, domain, tpl, stamp)

    order = ["总览", "账本说明", ASSET_SHEET, *domain.sheet_scope, "域变更日志"]
    wb._sheets = [wb[name] for name in order if name in wb.sheetnames]
    dest.parent.mkdir(parents=True, exist_ok=True)
    wb.save(dest)
    return {"row_count": row_count, "sheets": order}


# --------------------------------------------------------------------------- #
# 总目录构建
# --------------------------------------------------------------------------- #
INDEX_HEADERS = [
    "序号", "域", "账本文件", "覆盖大类", "大类数", "AssetID 前缀",
    "资产条数(快照)", "3D Prefab 分页数", "Prefab 分页", "动画登记表",
    "首选制作 Skill", "协作 Skill", "负责人", "状态",
]
INDEX_WIDTHS = {"A": 6, "B": 14, "C": 40, "D": 30, "E": 8, "F": 18, "G": 15, "H": 15,
                "I": 40, "J": 22, "K": 34, "L": 34, "M": 10, "N": 10}


def build_index_sheet(wb, index: LedgerIndex, tpl: Templates, counts: dict[str, int], pages: dict[str, int], stamp: str):
    ws = wb.create_sheet("分账本索引")
    ws.sheet_view.showGridLines = False
    _set_widths(ws, INDEX_WIDTHS)
    _write(ws, 1, 1, "SHELLSTORM 2 · 分账本索引（总目录核心）", tpl.title)
    ws.merge_cells("A1:N2")
    _write(
        ws, 3, 1,
        "本表定义「域 → 账本文件 → 覆盖大类 → AssetID 前缀」的唯一映射；"
        "机器可读副本为 assets/registry/ledger_index.json，两者不一致时以 JSON 为准并立即修本表",
        tpl.subtitle,
    )
    ws.merge_cells("A3:N3")
    for offset, header in enumerate(INDEX_HEADERS, start=1):
        _write(ws, 5, offset, header, tpl.table_header)
    ws.row_dimensions[5].height = 32
    row = 6
    for number, domain in enumerate(index.domains, start=1):
        values = [
            number,
            domain.name,
            domain.relative_path,
            " / ".join(domain.categories),
            len(domain.categories),
            " / ".join(domain.id_prefixes),
            counts.get(domain.key, 0),
            len(domain.prefab_pages),
            " / ".join(domain.prefab_pages) or "无",
            " / ".join(domain.animation_sheets) or "无",
            domain.primary_skill,
            " / ".join(domain.supporting_skills) or "无",
            domain.owner,
            "启用",
        ]
        for offset, value in enumerate(values, start=1):
            _write(ws, row, offset, value, tpl.data)
        ws.row_dimensions[row].height = 34
        row += 1
    _write(ws, row, 1, "合计", tpl.section)
    _write(ws, row, 2, None, tpl.section)
    _write(ws, row, 3, f"{len(index.domains)} 个分账本", tpl.section)
    _write(ws, row, 4, f"=COUNTA(D6:D{row - 1})", tpl.section)
    _write(ws, row, 5, f"=SUM(E6:E{row - 1})", tpl.section)
    _write(ws, row, 6, None, tpl.section)
    _write(ws, row, 7, f"=SUM(G6:G{row - 1})", tpl.section)
    _write(ws, row, 8, f"=SUM(H6:H{row - 1})", tpl.section)
    for col in range(9, 15):
        _write(ws, row, col, None, tpl.section)
    row += 2
    _write(
        ws, row, 1,
        f"快照日期 {stamp}；条数为拆分时点快照，权威数量在各分账本《总览》。"
        "新增资产先在本表确认归属域，再进对应分账本登记。",
        tpl.banner,
    )
    _style_range(ws, row, 2, 14, tpl.banner)
    ws.merge_cells(start_row=row, start_column=1, end_row=row, end_column=14)
    return ws


def build_master_overview(ws, index: LedgerIndex, tpl: Templates, counts: dict[str, int],
                          cat_counts: dict[str, int], stamp: str) -> None:
    for row in range(1, ws.max_row + 1):
        for col in range(1, 11):
            if ws.cell(row=row, column=col).value not in (None, ""):
                ws.cell(row=row, column=col).value = None
    _write(ws, 1, 1, "SHELLSTORM 2 · 美术资产总目录 v0.1", tpl.title)
    _write(
        ws, 3, 1,
        "本表是唯一总目录：只登记跨域契约（分类与编码 / 命名与查重 / 版本记录 / Skill 清单 / 3D Prefab 总控）"
        "与分账本索引；资产条目一律落在 assets/registry/ledgers/ 下的分账本，各账本可独立并行编辑",
        tpl.subtitle,
    )
    _write(ws, 5, 1, "分账本数", tpl.label)
    _write(ws, 5, 3, "覆盖大类数", tpl.label)
    _write(ws, 5, 5, "资产总数(快照)", tpl.label)
    _write(ws, 5, 7, "Prefab 分页数", tpl.label)
    last_index_row = 5 + len(index.domains)
    _write(ws, 6, 1, f"=COUNTA('分账本索引'!$B$6:$B${last_index_row})", tpl.big_number)
    _write(ws, 6, 3, f"=SUM('分账本索引'!$E$6:$E${last_index_row})", tpl.big_number)
    _write(ws, 6, 5, f"=SUM('分账本索引'!$G$6:$G${last_index_row})", tpl.big_number)
    _write(ws, 6, 7, f"=SUM('分账本索引'!$H$6:$H${last_index_row})", tpl.big_number)
    _write(ws, 6, 9, f"快照 {stamp}｜查重 → 归类 → 领取 AssetID → 组件制作 → 游戏内验收 → 回填哈希", tpl.label)

    _write(ws, 9, 1, "大类", tpl.section)
    _write(ws, 9, 2, "归属域", tpl.section)
    _write(ws, 9, 3, "账本文件", tpl.section)
    _write(ws, 9, 4, "条数", tpl.section)
    _write(ws, 9, 5, "AssetID 必须落在归属域的账本里；跨域搬运属跨域变更，须同步本表与 ledger_index.json", tpl.label)
    row = 10
    for category in sorted(index.all_categories()):
        domain = index.domain_for_category(category)
        _write(ws, row, 1, category, tpl.data)
        _write(ws, row, 2, domain.name, tpl.data)
        _write(ws, row, 3, domain.relative_path, tpl.data)
        # 逐大类条数：早先这里错写成「所属域的合计」，三个场景大类会各显示 235。
        _write(ws, row, 4, cat_counts.get(category, 0), tpl.data)
        for col in range(5, 11):
            _write(ws, row, col, None, tpl.data)
        row += 1
    _set_widths(ws, {"A": 14, "B": 14, "C": 46, "D": 10, "E": 8, "F": 30, "G": 42, "H": 3, "I": 30, "J": 30})
    ws.sheet_view.showGridLines = False


def build_master(source: Path, index: LedgerIndex, tpl: Templates, counts: dict[str, int],
                 cat_counts: dict[str, int], pages: dict[str, int],
                 pagemap: dict[str, dict[str, int]], stamp: str, dest: Path) -> None:
    wb = load_workbook(source)
    keep = set(index.raw["master"]["sheets"]) | {"分账本索引"}
    for name in list(wb.sheetnames):
        if name not in keep:
            del wb[name]

    build_master_overview(wb["总览"], index, tpl, counts, cat_counts, stamp)
    build_index_sheet(wb, index, tpl, counts, pages, stamp)

    # 3D Prefab 总控: 公式改为快照值 + 新增「归属账本」列, 并把错位的数据校验挪回「分类」列
    ws = wb["3D Prefab总控"]
    _write(ws, 4, 8, "归属账本", ws.cell(row=4, column=7)._style)
    _write(ws, 14, 8, None, tpl.section)
    for row in range(FIRST_DATA_ROW - 1, ws.max_row + 1):
        page = _text(ws.cell(row=row, column=2).value)
        owner = index.domain_for_sheet(page) if page else None
        if owner is None:
            continue
        _write(ws, row, 8, owner.relative_path, tpl.data)
        shape = pagemap.get(page)
        if shape is None:
            continue
        for col, value in zip((3, 4, 5, 6), shape):
            ws.cell(row=row, column=col).value = value
    ws.data_validations.dataValidation.clear()
    dv = DataValidation(type="list", formula1='"' + ",".join(
        ["场景通用组件", "设施组件", "道具", "角色", "敌人", "武器", "物品", "特效", "其他"]
    ) + '"', allow_blank=True, showDropDown=False, showErrorMessage=False)
    ws.add_data_validation(dv)
    dv.add("A5:A200")
    _set_widths(ws, {"H": 44})

    # 版本记录: 追加一条全局变更
    ws = wb["版本记录"]
    row = ws.max_row + 1
    while ws.cell(row=row - 1, column=1).value in (None, "") and row > FIRST_DATA_ROW:
        row -= 1
    row += 1
    entry = [
        "v0.2.0",
        stamp,
        "账本分册化",
        "全项目资产登记结构",
        "单体账本按大类拆为 7 个分账本（角色/敌人/场景/道具/武器/特效/表现资源），"
        "总目录只保留跨域契约与分账本索引；资产条目逐格不变。",
        "路径变更：资产条目移至 assets/registry/ledgers/。旧引用（含 asset_manifest.json 的 asset_ledger 字段）"
        "可用 scripts/ledger_registry.py 解析；门禁扩展为逐账本 + 跨文件契约。",
        "摩斯拉",
    ]
    for offset, value in enumerate(entry, start=1):
        _write(ws, row, offset, value, tpl.log_data)
    ws.row_dimensions[row].height = 46

    order = index.raw["master"]["sheets"]
    wb._sheets = [wb[name] for name in order if name in wb.sheetnames]
    wb.save(dest)


# --------------------------------------------------------------------------- #
def resolve_page_shape(wb, page: str) -> tuple[str, str, str, str]:
    """Return the (AssetID, GLB, 功能脚本, 碰撞开关) column letters of a 3D-* page."""
    ws = wb[page]
    header_row = FIRST_DATA_ROW - 1
    letters = {}
    for col in range(1, ws.max_column + 1):
        letters[_text(ws.cell(row=header_row, column=col).value)] = get_column_letter(col)
    return (
        letters.get("AssetID", "A"),
        letters.get("GLB模型路径", "D"),
        letters.get("功能脚本路径", "G"),
        letters.get("碰撞开关", "H"),
    )


def evaluate_countif(values: list[Any], criteria: str) -> int:
    if criteria == "<>":
        return sum(1 for v in values if _text(v) != "")
    return sum(1 for v in values if _text(v) == criteria)


def snapshot_page_shape(wb, page: str) -> list[int]:
    ws = wb[page]
    aid, glb, script, collide = resolve_page_shape(wb, page)
    def span(letter: str) -> list[Any]:
        col = ord(letter) - 64
        return [ws.cell(row=r, column=col).value for r in range(FIRST_DATA_ROW - 1, 205)]
    return [
        sum(1 for v in span(aid) if _text(v) != ""),
        evaluate_countif(span(glb), "<>"),
        evaluate_countif(span(script), "<>"),
        evaluate_countif(span(collide), "开"),
    ]


def loadable(path: Path) -> tuple[Path, Path | None]:
    """openpyxl 按扩展名判格式，.bak_* 之类的备份需要先改回 .xlsx 才能读。"""
    if path.suffix.lower() in (".xlsx", ".xlsm", ".xltx", ".xltm"):
        return path, None
    import tempfile

    tmp_dir = Path(tempfile.mkdtemp(prefix="ledger_source_"))
    tmp = tmp_dir / (path.name.split(".xlsx")[0] + ".xlsx")
    shutil.copy2(path, tmp)
    return tmp, tmp_dir


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--project-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--plan", action="store_true", help="只打印拆分计划，不落盘")
    parser.add_argument("--no-baseline", action="store_true", help="不刷新无损基线（基线已存在时使用）")
    parser.add_argument("--baseline-only", action="store_true",
                        help="只重建无损基线，不拆分（配合 --source 从 git 或 .bak 里的单体账本重建）")
    parser.add_argument("--source", type=Path, help="覆盖源账本路径（默认取 ledger_index.json 的 master.path）")
    args = parser.parse_args()

    root = args.project_root.resolve()
    index = LedgerIndex.load(root)
    source = (args.source or index.master_path)
    if not source.is_absolute():
        source = root / source
    source = source.resolve()
    if not source.is_file():
        raise SystemExit(f"source ledger missing: {source}")
    stamp = date.today().isoformat()

    read_path, cleanup = loadable(source)
    try:
        return _run(args, root, index, source, read_path, stamp)
    finally:
        if cleanup is not None:
            shutil.rmtree(cleanup, ignore_errors=True)


def _run(args, root: Path, index: LedgerIndex, source: Path, read_path: Path, stamp: str) -> int:
    wb = load_workbook(read_path)
    if args.baseline_only:
        if ASSET_SHEET not in wb.sheetnames:
            raise SystemExit(f"{source.name} 没有《{ASSET_SHEET}》表，无法作为基线来源")
        rows = read_source_rows(wb[ASSET_SHEET])
        baseline = build_baseline(source, index, rows, wb)
        baseline["source"] = str(source.relative_to(root)) if source.is_relative_to(root) else str(source)
        baseline_path = root / "assets/registry/ledger_split_baseline.json"
        baseline_path.write_text(json.dumps(baseline, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print(f"无损基线重建: {baseline_path.relative_to(root)}  assets={baseline['asset_count']}  from={baseline['source']}")
        print("REBUILD_BASELINE_OK")
        return 0

    if ASSET_SHEET not in wb.sheetnames:
        raise SystemExit(
            f"{source.name} 已经没有《{ASSET_SHEET}》表 —— 它看起来已经是总目录。"
            "要重新拆分请先从 git 恢复单体版本，或 --source 指向 .bak_pre_ledger_split。"
        )
    ws_asset = wb[ASSET_SHEET]
    rows = read_source_rows(ws_asset)
    if not rows:
        raise SystemExit("资产主表没有任何资产行")
    tpl = Templates(wb)

    by_domain: dict[str, list[int]] = {d.key: [] for d in index.domains}
    category_counts: dict[str, dict[str, int]] = {d.key: {} for d in index.domains}
    domain_rows: dict[str, list[tuple[str, str]]] = {d.key: [] for d in index.domains}
    for source_row, values in rows:
        category = _text(values[2])
        domain = index.domain_for_category(category)
        by_domain[domain.key].append(source_row)
        category_counts[domain.key][category] = category_counts[domain.key].get(category, 0) + 1
        domain_rows[domain.key].append((_text(values[0]), _text(values[1])))

    page_shape = {
        page: resolve_page_shape(wb, page)
        for domain in index.domains
        for page in domain.prefab_pages
        if page in wb.sheetnames
    }
    pages = {d.key: len(d.prefab_pages) for d in index.domains}
    counts = {d.key: len(by_domain[d.key]) for d in index.domains}
    pagemap = {
        page: snapshot_page_shape(wb, page)
        for page in page_shape
    }

    print("== 拆分为划 ==")
    print(f"源账本    : {index.master_relative_path}")
    print(f"资产行数  : {len(rows)}")
    for domain in index.domains:
        cats = " / ".join(domain.categories)
        print(f"  {domain.name:<6} n={counts[domain.key]:<4} 大类={cats:<24} -> {domain.relative_path}")
    print(f"合计      : {sum(counts.values())}")
    if args.plan:
        print("\n--plan 模式：未写入任何文件。")
        return 0

    if not args.no_baseline:
        baseline = build_baseline(source, index, rows, wb)
        baseline_path = root / "assets/registry/ledger_split_baseline.json"
        baseline_path.write_text(
            json.dumps(baseline, ensure_ascii=False, indent=1) + "\n", encoding="utf-8"
        )
        print(f"\n无损基线  : {baseline_path.relative_to(root)}  assets={baseline['asset_count']}")

    # 单体账本快照：备份这次真正读到的那份（read_path），文件名挂在 master 路径上，
    # 避免用 --source 指到备份时生成 xxx.bak_pre_ledger_split.bak_pre_ledger_split 这种双后缀垃圾。
    master_path = index.master_path
    backup = master_path.with_suffix(master_path.suffix + ".bak_pre_ledger_split")
    if not backup.exists():
        shutil.copy2(read_path, backup)
        print(f"单体账本快照: {backup.name}")

    for domain in index.domains:
        dest = domain.path
        info = build_domain_ledger(
            read_path, index, domain, tpl, dest, by_domain[domain.key],
            category_counts[domain.key], stamp, page_shape, domain_rows[domain.key],
        )
        print(f"  写出 {dest.relative_to(root)}  rows={info['row_count']} sheets={len(info['sheets'])}")

    # 总目录必须落在 master 路径上；dest 绝不能取 source，
    # 否则 `--source 某备份` 会把总目录写回那份备份，把单体账本就地覆盖掉。
    cat_counts = {cat: n for per_domain in category_counts.values() for cat, n in per_domain.items()}
    build_master(read_path, index, tpl, counts, cat_counts, pages, pagemap, stamp, master_path)
    print(f"  改写 {index.master_relative_path}  -> 总目录（跨域契约 + 分账本索引）")
    print("\nSPLIT_ASSET_LEDGER_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
