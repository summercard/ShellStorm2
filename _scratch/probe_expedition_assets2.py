# -*- coding: utf-8 -*-
"""精确检索：账本里 AssetID/路径/中文名含 expedition|远征 的行。只读。"""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
from openpyxl import load_workbook

LEDGER = Path("assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx")
wb = load_workbook(LEDGER, data_only=False)

MAIN_HDR = ["AssetID", "中文名", "大类", "子类", "逻辑ID/源键", "组件槽", "变体父ID", "视角",
            "状态/动画", "复用范围", "制作状态", "优先级", "版本", "规格(px)", "文件路径",
            "源码/策划依据", "关键词/别名", "查重键", "查重结果", "SHA-256", "负责人",
            "更新时间", "来源/许可", "源编号（Blender collection）", "备注"]

TYPE_HDR = None


def hit(rowvals):
    txt = " ".join(str(v) for v in rowvals if v is not None)
    low = txt.lower()
    return ("expedition" in low) or ("远征" in txt) or ("ENV-EXPEDITION" in txt)


for name, hdr in (("资产主表", None), ("3D-场景通用", None)):
    ws = wb[name]
    print("#" * 72)
    print("### %s  (rows=%d)" % (name, ws.max_row))
    hdr_row = 5 if name == "资产主表" else None
    if hdr_row is None:
        for r in range(1, 8):
            vals = [str(ws.cell(row=r, column=c).value or "") for c in range(1, ws.max_column + 1)]
            if any("资产ID" in v or "AssetID" in v for v in vals):
                hdr_row = r
                break
    cols = [ws.cell(row=hdr_row, column=c).value for c in range(1, ws.max_column + 1)]
    print("表头行=%s 列=%s" % (hdr_row, [str(c) for c in cols if c]))
    print()
    found = 0
    for r in range(hdr_row + 1, ws.max_row + 1):
        vals = [ws.cell(row=r, column=c).value for c in range(1, ws.max_column + 1)]
        if not hit(vals):
            continue
        found += 1
        print("--- row %d ---" % r)
        for c, v in enumerate(vals, 1):
            if v is None or not str(v).strip():
                continue
            label = str(cols[c - 1]) if c - 1 < len(cols) and cols[c - 1] else "c%d" % c
            print("   %-26s %s" % (label, str(v)[:150]))
        print()
    print("命中 %d 行" % found)
    print()
