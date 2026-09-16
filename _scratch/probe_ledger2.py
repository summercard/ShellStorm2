# -*- coding: utf-8 -*-
import re
import zipfile

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
with zipfile.ZipFile(LEDGER) as z:
    print("=== namelist (worksheets) ===")
    for n in z.namelist():
        if "worksheet" in n or n.endswith("workbook.xml") or "rels" in n:
            print(" ", n)
    wb = z.read("xl/workbook.xml").decode("utf-8")
    print("\n=== workbook.xml (first 3000) ===")
    print(wb[:3000])
    print("\n=== workbook.xml.rels ===")
    print(z.read("xl/_rels/workbook.xml.rels").decode("utf-8")[:2000])
