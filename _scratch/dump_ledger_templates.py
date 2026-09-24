# -*- coding: utf-8 -*-
"""登记 L 型走廊前，dump 场景账本的相关模板行与结构。"""
import json
from pathlib import Path
from openpyxl import load_workbook

LEDGER = "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
wb = load_workbook(LEDGER)


def dump_row(ws, r, ncol=None, label=""):
    ncol = ncol or ws.max_column
    print("--- %s row %d ---" % (label or ws.title, r))
    for c in range(1, ncol + 1):
        v = ws.cell(row=r, column=c).value
        if v is not None:
            s = str(v)
            if len(s) > 220:
                s = s[:220] + " …"
            print("   %s%-3d = %s" % (ws.cell(row=r, column=c).column_letter, c, s))


ws = wb["资产主表"]
dump_row(ws, 241, label="资产主表（模板行）")
print()

p = wb["3D-场景通用"]
dump_row(p, 147, label="3D-场景通用（模板行）")
print()

ov = wb["总览"]
print("--- 总览 全表（非空单元格） ---")
for row in ov.iter_rows():
    for cell in row:
        if cell.value is not None:
            s = str(cell.value)
            if len(s) > 120:
                s = s[:120] + " …"
            print("   %-5s = %s" % (cell.coordinate, s))
print()

cl = wb["域变更日志"]
dump_row(cl, 18, label="域变更日志（模板行）")
print("   max_row =", cl.max_row, " max_col =", cl.max_column)
print()
print("   日志开头 5 行的列名：")
for c in range(1, cl.max_column + 1):
    print("      col%d = %s" % (c, cl.cell(row=1, column=c).value))
print()

# 数据校验范围
print("--- 资产主表 DataValidation ---")
for dv in ws.data_validations.dataValidation:
    print("   sqref=%s  type=%s  f1=%s" % (dv.sqref, dv.type, getattr(dv, "formula1", None)))
print()
print("--- 3D-场景通用 DataValidation ---")
for dv in p.data_validations.dataValidation:
    print("   sqref=%s  type=%s  f1=%s" % (dv.sqref, dv.type, getattr(dv, "formula1", None)))

print()
print("--- 资产主表 R/S 列示例（末行） ---")
print("   R241 =", ws.cell(row=241, column=18).value)
print("   S241 =", ws.cell(row=241, column=19).value)
print("   R6   =", ws.cell(row=6, column=18).value)
print("   S6   =", ws.cell(row=6, column=19).value)
