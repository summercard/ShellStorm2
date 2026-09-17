# -*- coding: utf-8 -*-
"""只读：打印台账 「3D-场景通用」(xl/worksheets/sheet10.xml) 的尾部原始行 XML。

用于核对上一轮 wall_door_5m 注册插入的行（94-96）到底落在哪个 sheet、现在长什么样。

用法：python probe_sheet10_tail.py [起始行 默认88] [结束行 默认100]
"""
import re
import sys
import zipfile

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
SHEET_FILE = "xl/worksheets/sheet10.xml"


def strip_ns(text: str) -> str:
    text = re.sub(r"<(/?)[a-zA-Z0-9_]+:", r"<\1", text)
    text = re.sub(r'\s+xmlns(?::[a-zA-Z0-9_]+)?="[^"]*"', "", text)
    return text


start = int(sys.argv[1]) if len(sys.argv) > 1 else 88
end = int(sys.argv[2]) if len(sys.argv) > 2 else 100

with zipfile.ZipFile(LEDGER) as z:
    names = z.namelist()
    raw = z.read(SHEET_FILE).decode("utf-8")
    xml = strip_ns(raw)

print("sheet10.xml 压缩前长度=%d" % len(raw.encode("utf-8")))
rows = re.findall(r"<row[^>]*r=\"(\d+)\"[^>]*>", xml)
print("sheet10 行号总数=%d  最小=%s 最大=%s" % (
    len(rows), min(int(r) for r in rows) if rows else "-", max(int(r) for r in rows) if rows else "-"
))
print("sheet10 行号(升序): %s" % sorted(int(r) for r in rows))

# 同时报告其它工作表条目，便于确认注册落在了哪里
print("\nworksheet 条目: %s" % [n for n in names if n.startswith("xl/worksheets/")])

for m in re.finditer(r'<row[^>]*r="(\d+)"[^>]*>.*?</row>', xml, re.S):
    n = int(m.group(1))
    if start <= n <= end:
        print("\n--- raw row %d ---" % n)
        print(m.group(0)[:3000])
