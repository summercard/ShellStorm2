# -*- coding: utf-8 -*-
"""只读：按行号 dump 台账「3D-场景通用」sheet 的指定行，正确处理 sharedStrings / inlineStr。

用法：
    python dump_ledger_rows.py 40-50 90-97
不带参数时用默认行号集合。
"""
import html
import re
import sys
import zipfile

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"
SHEET_FILE = "xl/worksheets/sheet10.xml"
SHEET_TITLE = "3D-场景通用"


def strip_ns(text: str) -> str:
    text = re.sub(r"<(/?)[a-zA-Z0-9_]+:", r"<\1", text)
    text = re.sub(r'\s+xmlns(?::[a-zA-Z0-9_]+)?="[^"]*"', "", text)
    return text


def col_index(ref: str) -> int:
    m = re.match(r"([A-Z]+)", ref)
    idx = 0
    for ch in m.group(1):
        idx = idx * 26 + (ord(ch) - 64)
    return idx - 1


def col_name(ci: int) -> str:
    name = ""
    n = ci + 1
    while n > 0:
        n, rem = divmod(n - 1, 26)
        name = chr(65 + rem) + name
    return name


def parse_targets(argv):
    rows = set()
    if not argv:
        rows.update(range(40, 51))
        rows.update(range(90, 98))
        rows.update({1, 2, 3})
        return rows
    for arg in argv:
        if "-" in arg:
            a, b = arg.split("-", 1)
            rows.update(range(int(a), int(b) + 1))
        else:
            rows.add(int(arg))
    return rows


with zipfile.ZipFile(LEDGER) as z:
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        ss = strip_ns(z.read("xl/sharedStrings.xml").decode("utf-8"))
        for si in re.findall(r"<si>(.*?)</si>", ss, re.S):
            shared.append(html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S))))

    xml = strip_ns(z.read(SHEET_FILE).decode("utf-8"))

    def cell_value(attrs, body):
        t = attrs.get("t", "")
        if t == "inlineStr":
            return html.unescape(
                "".join(re.findall(r"<t[^>]*>(.*?)</t>", body, re.S))
            )
        if t == "s":
            v = re.search(r"<v>(.*?)</v>", body, re.S)
            return shared[int(v.group(1))] if v else ""
        # t="str" 的文本落在 <v> 里；旧实现只找 <t>，会把整张 sheet 读成全空。
        if t == "str":
            v = re.search(r"<v>(.*?)</v>", body, re.S)
            if v:
                return html.unescape(v.group(1))
            return html.unescape(
                "".join(re.findall(r"<t[^>]*>(.*?)</t>", body, re.S))
            )
        v = re.search(r"<v>(.*?)</v>", body, re.S)
        return v.group(1) if v else ""

    targets = parse_targets(sys.argv[1:])
    for row_m in re.finditer(r'<row[^>]*r="(\d+)"[^>]*>(.*?)</row>', xml, re.S):
        rnum = int(row_m.group(1))
        if rnum not in targets:
            continue
        body = row_m.group(2)
        cells = {}
        for cm in re.finditer(r"<c([^>]*?)(?:/>|>(.*?)</c>)", body, re.S):
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', cm.group(1)))
            ref = attrs.get("r", "")
            if not ref:
                continue
            val = cell_value(attrs, cm.group(2) or "")
            if val != "":
                cells[col_index(ref)] = val
        print("\n--- row %d ---" % rnum)
        for ci in sorted(cells):
            print("   %-3s %s" % (col_name(ci), cells[ci].replace("\n", " | ")))
