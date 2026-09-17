# -*- coding: utf-8 -*-
"""B4 台账失效格分类器（对齐 b4_ledger_audit.py 的口径）。

判据：单元格文本含 assets/…_vNNN.(glb|tscn)，且该路径磁盘不存在。
分类：
  A) 路径落在 rooftop_shelter_3d → B4 归属，需按列语义裁决改/不改
  B) 其它                       → 既有欠账（B1/B2/B6 或更早），非本批
对每条给出 HEAD 状态，坐实「本批造成」还是「本来就不存在」。
只读。
"""
from __future__ import annotations
import re, zipfile, subprocess, collections
from pathlib import Path

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
ROOT_B4 = "assets/art/environments/rooftop_shelter_3d/"

CELL = re.compile(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", re.S)
PATH = re.compile(r"assets/[A-Za-z0-9_./\u4e00-\u9fff\-]*?_v\d{3}\.(?:glb|tscn)")


def sst_text(si):
    return "".join(re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", si, re.S))


def cell_text(inner):
    ts = re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", inner, re.S)
    if ts:
        return "".join(ts)
    v = re.search(r"<(?:x:)?v>(.*?)</(?:x:)?v>", inner, re.S)
    return v.group(1) if v else ""


def col_idx(letters):
    n = 0
    for ch in letters:
        n = n * 26 + (ord(ch) - 64)
    return n


def idx_col(n):
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def head_exists(p):
    return subprocess.run(["git", "cat-file", "-e", f"HEAD:{p}"],
                          capture_output=True).returncode == 0


def main():
    with zipfile.ZipFile(LEDGER) as z:
        members = z.namelist()
        blobs = {n: z.read(n) for n in members}

    rels = blobs["xl/_rels/workbook.xml.rels"].decode("utf8")
    rid2tgt = {}
    for tag in re.findall(r"<(?:x:)?Relationship\b[^>]*/?>", rels):
        i = re.search(r'Id="([^"]+)"', tag); t = re.search(r'Target="([^"]+)"', tag)
        if i and t:
            rid2tgt[i.group(1)] = t.group(1)
    wb = blobs["xl/workbook.xml"].decode("utf8")
    name2member = {}
    for tag in re.findall(r"<(?:x:)?sheet\b[^>]*/?>", wb):
        nm = re.search(r'name="([^"]+)"', tag); rid = re.search(r'r:id="([^"]+)"', tag)
        if not nm or not rid:
            continue
        t = rid2tgt.get(rid.group(1), "")
        if not t:
            continue
        norm = t.lstrip("/")
        if not norm.startswith("xl/"):
            norm = "xl/" + norm
        name2member[nm.group(1)] = norm

    sst = re.findall(r"<(?:x:)?si>(.*?)</(?:x:)?si>",
                     blobs["xl/sharedStrings.xml"].decode("utf8", "ignore"), re.S)

    stale = []
    headers = {}
    for name, member in name2member.items():
        if member not in members:
            continue
        txt = blobs[member].decode("utf8")
        cells = {}
        for m in CELL.finditer(txt):
            attrs, inner = m.group(1), m.group(2)
            r = re.search(r'r="([A-Z]+)(\d+)"', attrs)
            if not r:
                continue
            t = re.search(r't="([^"]*)"', attrs)
            tval = t.group(1) if t else ""
            if tval == "s":
                vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", inner)
                val = sst_text(sst[int(vm.group(1))]) if vm and int(vm.group(1)) < len(sst) else ""
            else:
                val = cell_text(inner)
            if val:
                cells[(int(r.group(2)), col_idx(r.group(1)))] = val
        for (rr, cc), val in cells.items():
            if rr <= 3:
                headers.setdefault((name, idx_col(cc)), val.strip()[:40])
        for (rr, cc), val in sorted(cells.items()):
            if rr <= 3:
                continue
            for p in set(PATH.findall(val)):
                if not (PROJECT / p).exists():
                    stale.append((name, idx_col(cc), rr, p, val.strip()))

    print("失效格总数 = %d" % len(stale))

    b4 = [s for s in stale if s[3].startswith(ROOT_B4)]
    other = [s for s in stale if not s[3].startswith(ROOT_B4)]

    print("\n=== A) B4 归属（路径在 rooftop_shelter_3d）%d ===" % len(b4))
    for nm, col, rr, p, full in sorted(b4):
        print("  [%s!%s%d]  表头=%-24s HEAD存在=%s" % (nm, col, rr, headers.get((nm, col), "?"), head_exists(p)))
        print("        -> %s" % p)
        print("        (整格) %s" % full[:160])

    print("\n=== B) 非 B4（既有欠账）%d —— 按 sheet!列 聚合 ===" % len(other))
    agg = collections.Counter("%s!%s" % (nm, col) for nm, col, rr, p, f in other)
    for k, v in sorted(agg.items()):
        nm, col = k.split("!")
        print("  %-22s %3d   表头=%s" % (k, v, headers.get((nm, col), "?")))

    he = [s for s in stale if head_exists(s[3])]
    print("\n=== 汇总 ===")
    print("  失效格总数              = %d" % len(stale))
    print("  HEAD 时路径存在（本批改坏）= %d" % len(he))
    for nm, col, rr, p, f in sorted(he):
        print("        [%s!%s%d] %s" % (nm, col, rr, p))
    print("  HEAD 时已不存在（欠账）  = %d" % (len(stale) - len(he)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
