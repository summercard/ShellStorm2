# -*- coding: utf-8 -*-
"""只读：在台账所有 sheet 中按关键字搜单元格，打印所在行全部单元格。

用法：python search_ledger.py ENV-TOWER-WALL-SOLID-5M [更多关键字...]
"""
import html
import re
import sys
import zipfile

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"


def strip_ns(text: str) -> str:
    text = re.sub(r"<(/?)[a-zA-Z0-9_]+:", r"<\1", text)
    text = re.sub(r'\s+xmlns(?::[a-zA-Z0-9_]+)?="[^"]*"', "", text)
    return text


def col_name(ci: int) -> str:
    name = ""
    n = ci + 1
    while n > 0:
        n, rem = divmod(n - 1, 26)
        name = chr(65 + rem) + name
    return name


def col_index(ref: str) -> int:
    idx = 0
    for ch in re.match(r"([A-Z]+)", ref).group(1):
        idx = idx * 26 + (ord(ch) - 64)
    return idx - 1


keywords = sys.argv[1:] or ["ENV-TOWER-WALL-SOLID-5M"]

with zipfile.ZipFile(LEDGER) as z:
    shared = []
    if "xl/sharedStrings.xml" in z.namelist():
        ss = strip_ns(z.read("xl/sharedStrings.xml").decode("utf-8"))
        for si in re.findall(r"<si>(.*?)</si>", ss, re.S):
            shared.append(html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S))))

    wb = strip_ns(z.read("xl/workbook.xml").decode("utf-8"))
    rels = strip_ns(z.read("xl/_rels/workbook.xml.rels").decode("utf-8"))
    rel_map = {}
    for rm in re.finditer(r"<Relationship\b[^>]*/>", rels):
        attrs = dict(re.findall(r'(\w+)="([^"]*)"', rm.group(0)))
        if "Id" in attrs and "Target" in attrs:
            rel_map[attrs["Id"]] = attrs["Target"]
    sheets = re.findall(r'<sheet name="([^"]*)"[^>]*r:id="([^"]*)"', wb)

    def cell_value(attrs, body):
        t = attrs.get("t", "")
        if t == "inlineStr":
            return html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", body, re.S)))
        if t == "s":
            v = re.search(r"<v>(.*?)</v>", body, re.S)
            return shared[int(v.group(1))] if v else ""
        # t="str"（公式/字面字符串结果）文本同样落在 <v> 里，不是 <t>；
        # 之前的实现只找 <t>，导致这批单元格一律读成空串。
        if t == "str":
            v = re.search(r"<v>(.*?)</v>", body, re.S)
            if v:
                return html.unescape(v.group(1))
            return html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", body, re.S)))
        v = re.search(r"<v>(.*?)</v>", body, re.S)
        return v.group(1) if v else ""

    for name, rid in sheets:
        target = rel_map.get(rid)
        if not target:
            continue
        path = target.lstrip("/") if target.startswith("/") else "xl/" + target
        if path not in z.namelist():
            continue
        xml = strip_ns(z.read(path).decode("utf-8"))
        for row_m in re.finditer(r'<row[^>]*r="(\d+)"[^>]*>(.*?)</row>', xml, re.S):
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
            hay = " ".join(cells.values())
            if any(k in hay for k in keywords):
                print("\n### sheet=%s  row=%s" % (name, row_m.group(1)))
                for ci in sorted(cells):
                    print("   %-3s %s" % (col_name(ci), cells[ci].replace("\n", " | ")))
