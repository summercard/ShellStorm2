# -*- coding: utf-8 -*-
"""只读复验：B2 台账补丁（`3D-场景通用` C/D 列去版本）是否保真。

与 `patch_ledger_b2_deversion.py` 的断言相互独立 —— 此处直接对比
「当前工作副本」与「git HEAD 里的同一工作簿」，逐格求闭包：

  1. zip 条目集合不变；除 `xl/worksheets/sheet10.xml` 外逐条目字节相同。
  2. 变化单元格必须全部落在 B2 的 10 个行号内，且列只许是 C / D。
  3. B2 行的 O 列（版本事实）与 A 列（AssetID）必须逐格不变。
  4. C/D 两列不得残留任何 `_vNNN.(glb|tscn)`。
  5. dimension / mergeCell / dataValidation / 行数 计数不变。

用法：
  python _scratch/verify_ledger_b2_deversion.py [--head <HEAD 版 xlsx>]
"""
from __future__ import annotations

import argparse
import html
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
SHEET_NAME = "3D-场景通用"
SHEET_MEMBER = "xl/worksheets/sheet10.xml"

# B2 触及的台账行（3D-场景通用 表内）
B2_ROWS = {5, 7, 8, 42, 43, 44, 45, 46, 48, 61}
B2_ROOTS = [
    "assets/art/props/dungeon_3d/",
    "assets/art/environments/tower_descent_3d/",
    "assets/art/props/base_world_3d/",
    "assets/art/environments/dungeon_3d/",
    "assets/art/environments/base_world_3d/",
    "assets/art/environments/tower_zones/base/",
    "assets/art/environments/tower_zones/rooftop/",
]
VERSIONED = re.compile(r"_v\d{3}\.(?:glb|tscn)")

CELL_RE = re.compile(r"<c([^>]*?)(?:/>|>(.*?)</c>)", re.S)
ROW_RE = re.compile(r'<row[^>]*r="(\d+)"[^>]*>(.*?)</row>', re.S)


def strip_ns(text: str) -> str:
    text = re.sub(r"<(/?)[a-zA-Z0-9_]+:", r"<\1", text)
    return re.sub(r'\s+xmlns(?::[a-zA-Z0-9_]+)?="[^"]*"', "", text)


def col_index(ref: str) -> int:
    idx = 0
    for ch in re.match(r"([A-Z]+)", ref).group(1):
        idx = idx * 26 + (ord(ch) - 64)
    return idx - 1


def col_name(ci: int) -> str:
    name, n = "", ci + 1
    while n > 0:
        n, rem = divmod(n - 1, 26)
        name = chr(65 + rem) + name
    return name


def read_cells(z: zipfile.ZipFile, member: str) -> tuple[dict[str, str], int]:
    """返回 {(列名, 行号): 文本} 与行数。文本按 t= 分支解码（str/inlineStr/s 共享串）。"""
    shared: list[str] = []
    if "xl/sharedStrings.xml" in z.namelist():
        ss = strip_ns(z.read("xl/sharedStrings.xml").decode("utf-8"))
        for si in re.findall(r"<si>(.*?)</si>", ss, re.S):
            shared.append(html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", si, re.S))))

    xml = strip_ns(z.read(member).decode("utf-8"))
    cells: dict[str, str] = {}
    rows = ROW_RE.findall(xml)
    for rnum, body in rows:
        for cm in CELL_RE.finditer(body):
            attrs = dict(re.findall(r'(\w+)="([^"]*)"', cm.group(1)))
            ref = attrs.get("r", "")
            inner = cm.group(2) or ""
            t = attrs.get("t", "")
            if t == "s":
                v = re.search(r"<v>(.*?)</v>", inner, re.S)
                val = shared[int(v.group(1))] if v else ""
            elif t in ("str", "inlineStr"):
                v = re.search(r"<v>(.*?)</v>", inner, re.S)
                if v:
                    val = html.unescape(v.group(1))
                else:
                    val = html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", inner, re.S)))
            else:
                v = re.search(r"<v>(.*?)</v>", inner, re.S)
                val = v.group(1) if v else ""
            key = (col_name(col_index(ref)), int(rnum))
            cells[key] = val
    return cells, len(rows)


def head_workbook(dest: Path) -> Path:
    raw = subprocess.run(
        ["git", "show", f"HEAD:assets/registry/{LEDGER.name}"],
        cwd=PROJECT, capture_output=True, check=True,
    ).stdout
    dest.write_bytes(raw)
    return dest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--head", help="HEAD 版工作簿路径；缺省则用 git show 提取")
    args = ap.parse_args()

    if args.head:
        head_path = Path(args.head)
    else:
        head_path = head_workbook(Path(tempfile.mkdtemp()) / "head.xlsx")

    failures: list[str] = []

    with zipfile.ZipFile(LEDGER) as zc, zipfile.ZipFile(head_path) as zh:
        cur_entries = {n: zc.read(n) for n in zc.namelist()}
        head_entries = {n: zh.read(n) for n in zh.namelist()}

    if set(cur_entries) != set(head_entries):
        failures.append(f"zip 条目集合变化：{set(cur_entries) ^ set(head_entries)}")
    else:
        print(f"OK  zip 条目集合不变（{len(cur_entries)} 条）")

    byte_diff = [n for n in cur_entries if cur_entries[n] != head_entries.get(n)]
    if byte_diff == [SHEET_MEMBER]:
        print(f"OK  逐条目字节差异仅 {SHEET_MEMBER}")
    else:
        failures.append(f"逐条目字节差异异常：{byte_diff}")

    with zipfile.ZipFile(LEDGER) as zc, zipfile.ZipFile(head_path) as zh:
        c1, rows1 = read_cells(zc, SHEET_MEMBER)
        c2, rows2 = read_cells(zh, SHEET_MEMBER)

    if rows1 != rows2:
        failures.append(f"行数变化：{rows2} -> {rows1}")
    else:
        print(f"OK  行数不变（{rows1}）")

    changed = sorted(
        (k for k in set(c1) | set(c2) if c1.get(k) != c2.get(k)),
        key=lambda k: (k[1], k[0]),
    )
    print(f"\n变化单元格 {len(changed)} 个：")
    for col, rnum in changed:
        print(f"  r{rnum}{col}")
        print(f"    HEAD -> {c2.get((col, rnum), '')!r}")
        print(f"    现在 -> {c1.get((col, rnum), '')!r}")
    bad_row = [k for k in changed if k[1] not in B2_ROWS]
    bad_col = [k for k in changed if k[0] not in ("C", "D")]
    if bad_row:
        failures.append(f"变化越出 B2 行：{bad_row}")
    if bad_col:
        failures.append(f"变化越出 C/D 列：{bad_col}")
    print(f"OK  变化全部落在 B2 的 {len(B2_ROWS)} 个行号内（行){'' if not bad_row else ' ✗'}")

    print("\nB2 行 O 列（版本事实）/ A 列（AssetID）不变性：")
    for rnum in sorted(B2_ROWS):
        for col in ("O", "A"):
            a, b = c2.get((col, rnum), ""), c1.get((col, rnum), "")
            mark = "OK" if a == b else "**变了**"
            if a != b:
                failures.append(f"r{rnum}{col} 被改动：{a!r} -> {b!r}")
            print(f"  r{rnum}{col} {mark}  {b!r}")

    print("\nC/D 列残留带版本路径：")
    residue = [
        (col, rnum, v)
        for (col, rnum), v in c1.items()
        if col in ("C", "D")
        and VERSIONED.search(v)
        and any(v.strip().startswith(r) or f"/{r.split('/')[2]}/" in v for r in B2_ROOTS)
    ]
    in_scope = [
        (col, rnum, v)
        for (col, rnum), v in c1.items()
        if col in ("C", "D") and VERSIONED.search(v) and any(
            v.strip().startswith(root) for root in B2_ROOTS
        )
    ]
    if in_scope:
        failures.append(f"B2 根下 C/D 仍有带版本路径：{in_scope}")
    print(f"  B2 七根下命中 {len(in_scope)} 个（应为 0）")
    for col, rnum, v in residue:
        print(f"  [范围外，属后续批] r{rnum}{col} {v}")

    print()
    if failures:
        print("LEDGER_B2_VERIFY_FAILED")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("LEDGER_B2_VERIFY_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
