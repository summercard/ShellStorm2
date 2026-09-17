# -*- coding: utf-8 -*-
"""只读：扫台账「3D-场景通用」C/D 两列里带版本号的运行资产路径，给出 B2 去版本化建议。

判据与 deversion_batch.py 一致：稳定名 = 去掉 `_vNNN` 后缀 / `vNNN/` 目录段。
只列 B2 七个根下的路径；其余批次原样列出但不建议（供人工确认）。
"""
from __future__ import annotations

import html
import re
import sys
import zipfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"

B2_ROOTS = [
    "assets/art/props/dungeon_3d/",
    "assets/art/environments/tower_descent_3d/",
    "assets/art/props/base_world_3d/",
    "assets/art/environments/dungeon_3d/",
    "assets/art/environments/base_world_3d/",
    "assets/art/environments/tower_zones/base/",
    "assets/art/environments/tower_zones/rooftop/",
]

VERSION_SUFFIX = re.compile(r"_v(\d{3})(?=\.)")
VERSION_DIR = re.compile(r"^v\d{3}$")


def strip_ns(text: str) -> str:
    text = re.sub(r"<(/?)[a-zA-Z0-9_]+:", r"<\1", text)
    return re.sub(r'\s+xmlns(?::[a-zA-Z0-9_]+)?="[^"]*"', "", text)


def col_name(ci: int) -> str:
    name, n = "", ci + 1
    while n > 0:
        n, rem = divmod(n - 1, 26)
        name = chr(65 + rem) + name
    return name


def col_index(ref: str) -> int:
    idx = 0
    for ch in re.match(r"([A-Z]+)", ref).group(1):
        idx = idx * 26 + (ord(ch) - 64)
    return idx - 1


def stable_path(rel: str) -> str:
    parts = [p for p in rel.split("/") if not VERSION_DIR.match(p)]
    parts[-1] = VERSION_SUFFIX.sub("", parts[-1], count=1)
    return "/".join(parts)


def main() -> int:
    wanted = sys.argv[1] if len(sys.argv) > 1 else "3D-场景通用"
    with zipfile.ZipFile(LEDGER) as z:
        shared = []
        ss = strip_ns(z.read("xl/sharedStrings.xml").decode("utf-8"))
        for si in re.findall(r"<si>(.*?)</si>", ss, re.S):
            shared.append(html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S))))

        wb = strip_ns(z.read("xl/workbook.xml").decode("utf-8"))
        rels = strip_ns(z.read("xl/_rels/workbook.xml.rels").decode("utf-8"))
        rel_map = {a["Id"]: a["Target"] for a in
                   (dict(re.findall(r'(\w+)="([^"]*)"', m.group(0)))
                    for m in re.finditer(r"<Relationship\b[^>]*/>", rels))
                   if "Id" in a and "Target" in a}
        sheets = re.findall(r'<sheet name="([^"]*)"[^>]*r:id="([^"]*)"', wb)

        target = None
        for name, rid in sheets:
            if name == wanted:
                t = rel_map.get(rid, "")
                target = t.lstrip("/") if t.startswith("/") else "xl/" + t
        if target is None or target not in z.namelist():
            raise SystemExit(f"找不到 sheet {wanted} 的 XML")
        print(f"sheet={wanted}  member={target}")

        xml = strip_ns(z.read(target).decode("utf-8"))
        cell_re = re.compile(r'<c([^>]*?)(?:/>|>(.*?)</c>)', re.S)
        rows = re.findall(r'<row[^>]*r="(\d+)"[^>]*>(.*?)</row>', xml, re.S)
        print(f"总行数={len(rows)}")

        hits = 0
        for rnum, body in rows:
            for cm in cell_re.finditer(body):
                attrs = dict(re.findall(r'(\w+)="([^"]*)"', cm.group(1)))
                ref = attrs.get("r", "")
                ci = col_index(ref) if ref else None
                if ci not in (2, 3):  # C / D
                    continue
                t = attrs.get("t", "")
                inner = cm.group(2) or ""
                if t == "s":
                    v = re.search(r"<v>(.*?)</v>", inner, re.S)
                    val = shared[int(v.group(1))] if v else ""
                elif t == "inlineStr":
                    # 本表 C 列（Prefab 路径）就是 inlineStr：文本落 <is><t>，不是 <v>。
                    val = html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", inner, re.S)))
                elif t == "str":
                    v = re.search(r"<v>(.*?)</v>", inner, re.S)
                    if v:
                        val = html.unescape(v.group(1))
                    else:
                        val = html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", inner, re.S)))
                else:
                    v = re.search(r"<v>(.*?)</v>", inner, re.S)
                    val = v.group(1) if v else ""
                if not re.search(r"_v\d{3}\.(?:glb|tscn)", val):
                    continue
                p = val.strip()
                in_b2 = any(p.startswith(r) for r in B2_ROOTS)
                st = stable_path(p)
                exists = "EXISTS" if (PROJECT / st).is_file() else "MISSING"
                hits += 1
                tag = "B2 " if in_b2 else "   "
                print(f"{tag}r{rnum}{col_name(ci)} {exists:8s} {p}")
                print(f"          -> {st}")
        print(f"\n命中 {hits} 个单元格")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
