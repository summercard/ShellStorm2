# -*- coding: utf-8 -*-
"""探针：查 ShellStorm2 台账里「3D-场景通用」表所在的 sheet 成员与最后数据行。"""
import re
import zipfile

LEDGER = r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ShellStorm2_美术资产台账_v001.xlsx"

with zipfile.ZipFile(LEDGER) as z:
    names = z.namelist()
    wb = z.read("xl/workbook.xml").decode("utf-8")
    rels = z.read("xl/_rels/workbook.xml.rels").decode("utf-8")
    sheets = re.findall(r'<sheet[^>]*name="([^"]+)"[^>]*r:id="([^"]+)"', wb)
    relmap = dict(re.findall(r'Id="([^"]+)"[^>]*Target="([^"]+)"', rels))
    print("=== sheets ===")
    target_member = None
    for name, rid in sheets:
        target = relmap.get(rid, "?")
        member = "xl/" + target.lstrip("/")
        print("  %-24s -> %s" % (name, member))
        if "场景通用" in name or "3D-场景通用" in name:
            target_member = member
    print("target_member =", target_member)

    if target_member:
        raw = z.read(target_member).decode("utf-8")
        rows = [int(m.group(1)) for m in re.finditer(r'<x:row r="(\d+)"', raw)]
        print("row count:", len(rows), "min:", min(rows), "max:", max(rows))
        print("last 10 rows:", sorted(rows)[-10:])
        # 打印最后 4 行的 A/B/C 单元格
        for rn in sorted(rows)[-4:]:
            m = re.search(r'<x:row r="%d"[^>]*>(.*?)</x:row>' % rn, raw, re.S)
            if not m:
                continue
            cells = re.findall(r'<x:c r="([A-Z]+)%d"[^>]*>(?:<x:v>(.*?)</x:v>)?</x:c>' % rn, m.group(1), re.S)
            head = {c[0]: (c[1] or "")[:70] for c in cells if c[0] in ("A", "B", "C", "K", "O")}
            print("  r%d: %s" % (rn, head))
        print("has mergeCells:", "<x:mergeCells>" in raw, "| has dataValidations:", "<x:dataValidations" in raw)
        # 该 sheet 用到的行样式集合
        styles = sorted(set(re.findall(r'<x:row r="\d+"[^>]*s="(\d+)"', raw)) | set(re.findall(r'<x:c r="[A-Z]+\d+" s="(\d+)"', raw)))
        print("styles used (first 10):", styles[:10])
