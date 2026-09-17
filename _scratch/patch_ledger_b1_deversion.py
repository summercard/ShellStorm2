# -*- coding: utf-8 -*-
"""B1：把「3D-场景通用」表里 B1 相关行的路径就地去掉版本号（去版本化计划 §4.1 第 ⑦ 步）。

只改 C / D 两列里出现的运行资产路径，**不动 O 列的版本事实**（r86/r87=v007，r92–r96=v004）。
目标行：r86、r87（安全房入口/出口）、r92–r96（战局通用组件库五件）。

为什么按行 + 就地替换而不是整行重建：这些行的其余列（尺寸、契约、备注、状态）
本轮没有任何变化，整行重建会把上一轮写好的接入说明换成我手写的新版，属无谓改动。
按行、只替换路径串，可把差异压到最小。

为什么必须外科式 XML 补丁：台账是唯一登记源，openpyxl 整本重写会丢 styles /
mergeCells / dataValidations（项目自带校验会断言 (max_row,max_column) 不变）。

幂等：目标串已就位则不写。

用法：
  python patch_ledger_b1_deversion.py            # dry-run
  python patch_ledger_b1_deversion.py --apply    # 落盘（先备份）
"""
from __future__ import annotations

import re
import shutil
import sys
import zipfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
SHEET_MEMBER = "xl/worksheets/sheet10.xml"
BACKUP_SUFFIX = ".bak_b1_deversion"

TARGET_ROWS = [86, 87, 92, 93, 94, 95, 96]

# 只做 B1 范围内的路径去版本；顺序无关（互不重叠）
REPLACEMENTS = [
    # 版本目录段（runtime 与 components 两侧都要去，否则 C/D 两列会不一致）
    ("/entry_safe_room/v007/", "/entry_safe_room/"),
    # 版本文件名后缀
    ("_root_top3d_v007.tscn", "_root_top3d.tscn"),
    ("_visual_top3d_v007.glb", "_visual_top3d.glb"),
    ("_root_top3d_v004.tscn", "_root_top3d.tscn"),
    ("_visual_top3d_v004.glb", "_visual_top3d.glb"),
]


def row_pattern(number: int) -> re.Pattern:
    return re.compile(
        r'<(?:\w+:)?row[^>]*\br="%d"[^>]*>.*?</(?:\w+:)?row>' % number, re.S
    )


def main() -> int:
    apply = "--apply" in sys.argv
    if not LEDGER.is_file():
        raise SystemExit(f"缺少台账：{LEDGER}")

    with zipfile.ZipFile(LEDGER) as zin:
        members = zin.namelist()
        blobs = {name: zin.read(name) for name in members}

    sheet = blobs[SHEET_MEMBER].decode("utf8")
    original_sheet = sheet
    changed_rows: list[int] = []

    for number in TARGET_ROWS:
        pat = row_pattern(number)
        m = pat.search(sheet)
        if m is None:
            raise SystemExit(f"找不到 r{number}（台账结构可能已变，勿强行继续）")
        row = m.group(0)
        new_row = row
        for old, new in REPLACEMENTS:
            new_row = new_row.replace(old, new)
        if new_row != row:
            sheet = sheet[: m.start()] + new_row + sheet[m.end():]
            changed_rows.append(number)

    if sheet == original_sheet:
        print("LEDGER_B1_NO_CHANGE：目标串已全部就位（幂等）")
        return 0

    # —— 保真校验 ——
    row_count_before = len(re.findall(r"<(?:\w+:)?row\b", original_sheet))
    row_count_after = len(re.findall(r"<(?:\w+:)?row\b", sheet))
    if row_count_before != row_count_after:
        raise SystemExit(f"行数变化：{row_count_before} → {row_count_after}")
    for tag in ("dimension", "mergeCell", "dataValidation"):
        if original_sheet.count("<" + tag) != sheet.count("<" + tag):
            # dimension 可能带前缀命名空间，用宽松计数
            raise SystemExit(f"{tag} 数量变化，拒绝写入")
    for leftover in ("_root_top3d_v007.tscn", "_visual_top3d_v007.glb"):
        if leftover in sheet:
            raise SystemExit(f"目标行仍残留 {leftover}")

    print(f"将修改行：{changed_rows}")
    for number in changed_rows:
        m = row_pattern(number).search(sheet)
        vals = re.findall(r"<(?:\w+:)?(?:t|v)[^>]*>(.*?)</(?:\w+:)?(?:t|v)>", m.group(0), re.S)
        joined = " ".join(vals)
        hit = [v for v in vals if "_root_top3d.tscn" in v or "_visual_top3d.glb" in v]
        for h in hit[:3]:
            print(f"  r{number}: {h[:150]}")

    if not apply:
        print("\n（dry-run，未写盘；加 --apply 落盘）")
        return 0

    backup = LEDGER.with_name(LEDGER.name + BACKUP_SUFFIX)
    shutil.copy2(LEDGER, backup)
    out = LEDGER.with_suffix(".xlsx.tmp")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zout:
        for name in members:
            data = sheet.encode("utf8") if name == SHEET_MEMBER else blobs[name]
            zout.writestr(name, data)
    out.replace(LEDGER)

    # —— 写后复验：除目标 sheet 外逐字节一致 ——
    with zipfile.ZipFile(LEDGER) as z:
        assert z.namelist() == members, "zip 条目集合变了"
        diff = [n for n in members if z.read(n) != blobs[n]]
    if diff != [SHEET_MEMBER]:
        raise SystemExit(f"非预期差异条目：{diff}")
    print(f"LEDGER_B1_OK 已写入（备份 {backup.name}）；仅 {SHEET_MEMBER} 变化")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
