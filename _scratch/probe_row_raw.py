# -*- coding: utf-8 -*-
"""只读：打印 sheet10 指定行的原始 XML 片段（前 N 字符），用于确认样式与行高。

用法：python probe_row_raw.py 86 87
"""
import re
import sys
import zipfile

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
SHEET = "xl/worksheets/sheet10.xml"

with zipfile.ZipFile(LEDGER) as z:
    xml = z.read(SHEET).decode("utf-8")

targets = [int(a) for a in sys.argv[1:]] or [86, 87]
for row in targets:
    m = re.search(r'<x:row r="%d"[^>]*>.*?</x:row>' % row, xml, re.S)
    if not m:
        print("row %d 未找到" % row)
        continue
    block = m.group(0)
    print("--- row %d  raw len=%d ---" % (row, len(block)))
    print("  row tag:", re.match(r'<x:row [^>]*>', block).group(0))
    for cm in re.finditer(r'<x:c r="([A-Z]+)%d"([^>]*?)(/>|>(.*?)</x:c>)' % row, block, re.S):
        print("   %-3s attrs=%s body=%s" % (
            cm.group(1), cm.group(2).strip(),
            (cm.group(4) or "")[:70].replace("\n", " ")))
