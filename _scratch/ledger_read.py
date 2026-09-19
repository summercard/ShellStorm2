# -*- coding: utf-8 -*-
"""只读 xlsx 工具（stdlib：zipfile + ElementTree）。

用法：
  python ledger_read.py <xlsx> sheets
  python ledger_read.py <xlsx> head <sheet> [n]
  python ledger_read.py <xlsx> rows <sheet> <r1> [r2]
  python ledger_read.py <xlsx> find <sheet> <keyword> [keyword...]
全部输出为 TSV（列号 A/B/C... 前缀），不写文件。
"""
import html
import re
import sys
import zipfile

NS = re.compile(r"\{[^}]*\}")


def strip_ns(t: str) -> str:
    return NS.sub("", t)


def _clean(t: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", t)).replace("\r", " ").replace("\n", " | ")


def col_name(ci: int) -> str:
    name = ""
    n = ci + 1
    while n > 0:
        n, rem = divmod(n - 1, 26)
        name = chr(65 + rem) + name
    return name


def col_index(ref: str) -> int:
    m = re.match(r"([A-Z]+)", ref)
    if not m:
        return 0
    idx = 0
    for ch in m.group(1):
        idx = idx * 26 + (ord(ch) - 64)
    return idx - 1


def row_index(ref: str) -> int:
    m = re.match(r"[A-Z]+(\d+)", ref)
    return int(m.group(1)) if m else 0


class Book:
    def __init__(self, path: str):
        self.z = zipfile.ZipFile(path)
        self.shared = []
        if "xl/sharedStrings.xml" in self.z.namelist():
            ss = strip_ns(self.z.read("xl/sharedStrings.xml").decode("utf-8", "replace"))
            for si in re.findall(r"<si>(.*?)</si>", ss, re.S):
                self.shared.append(_clean("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S))))
        wb = strip_ns(self.z.read("xl/workbook.xml").decode("utf-8", "replace"))
        rels = strip_ns(self.z.read("xl/_rels/workbook.xml.rels").decode("utf-8", "replace"))
        rel_map = {}
        for rm in re.finditer(r"<Relationship\b[^>]*/>", rels):
            a = dict(re.findall(r'(\w+)="([^"]*)"', rm.group(0)))
            if "Id" in a and "Target" in a:
                rel_map[a["Id"]] = a["Target"]
        self.sheets = re.findall(r'<sheet name="([^"]*)"[^>]*r:id="([^"]*)"', wb)
        self._rel = rel_map
        self._cache = {}

    def _sheet_xml(self, name: str) -> str:
        if name in self._cache:
            return self._cache[name]
        rid = dict((n, r) for n, r in self.sheets).get(name)
        if not rid:
            raise SystemExit("no such sheet: %s (have: %s)" % (name, [n for n, _ in self.sheets]))
        target = self._rel.get(rid, "")
        path = target.lstrip("/") if target.startswith("/") else "xl/" + target
        xml = strip_ns(self.z.read(path).decode("utf-8", "replace"))
        self._cache[name] = xml
        return xml

    def _cell(self, attrs, body) -> str:
        t = attrs.get("t", "")
        if t == "inlineStr":
            return _clean("".join(re.findall(r"<t[^>]*>(.*?)</t>", body, re.S)))
        if t == "s":
            v = re.search(r"<v>(.*?)</v>", body, re.S)
            return self.shared[int(v.group(1))] if v else ""
        if t == "str":
            v = re.search(r"<v>(.*?)</v>", body, re.S)
            if v:
                return _clean(v.group(1))
            return _clean("".join(re.findall(r"<t[^>]*>(.*?)</t>", body, re.S)))
        v = re.search(r"<v>(.*?)</v>", body, re.S)
        return _clean(v.group(1)) if v else ""

    def rows(self, name: str):
        xml = self._sheet_xml(name)
        for rm in re.finditer(r'<row[^>]*r="(\d+)"[^>]*>(.*?)</row>', xml, re.S):
            rn = int(rm.group(1))
            cells = {}
            for cm in re.finditer(r"<c([^>]*?)(?:/>|>(.*?)</c>)", rm.group(2), re.S):
                a = dict(re.findall(r'(\w+)="([^"]*)"', cm.group(1)))
                ref = a.get("r", "")
                if not ref:
                    continue
                cells[col_index(ref)] = (a.get("t", ""), self._cell(a, cm.group(2) or ""))
            yield rn, cells


def main():
    path = sys.argv[1]
    cmd = sys.argv[2] if len(sys.argv) > 2 else "sheets"
    bk = Book(path)
    if cmd == "sheets":
        for i, (n, _) in enumerate(bk.sheets):
            print("%d\t%s" % (i, n))
        return
    sheet = sys.argv[3]
    if cmd == "head":
        n = int(sys.argv[4]) if len(sys.argv) > 4 else 3
        for rn, cells in bk.rows(sheet):
            print("R%d\t%s" % (rn, "\t".join("%s=%s" % (col_name(c), cells[c][1]) for c in sorted(cells))))
            if rn >= n:
                break
    elif cmd == "rows":
        r1 = int(sys.argv[4])
        r2 = int(sys.argv[5]) if len(sys.argv) > 5 else r1
        for rn, cells in bk.rows(sheet):
            if r1 <= rn <= r2:
                print("R%d\t%s" % (rn, "\t".join("%s=%s" % (col_name(c), cells[c][1]) for c in sorted(cells))))
    elif cmd == "find":
        kws = sys.argv[4:]
        for rn, cells in bk.rows(sheet):
            hay = " ".join(v for _, v in cells.values())
            if any(k in hay for k in kws):
                print("R%d\t%s" % (rn, "\t".join("%s=%s" % (col_name(c), cells[c][1]) for c in sorted(cells))))
    else:
        raise SystemExit("unknown cmd " + cmd)


if __name__ == "__main__":
    main()
