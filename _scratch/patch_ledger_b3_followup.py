# -*- coding: utf-8 -*-
"""B3 步骤⑦ 收尾：处理 3D-场景通用 D65/D66 两格——「目录 + 括号说明」形式。

这两格的值形如
    assets/art/environments/base_facility_3d/components/env_base99_wall_contents_v021（18个GLB）
含全角括号说明，被主脚本的「纯路径」判据跳过。它们确实是运行路径列（D=components glb），
目录段 _v021 在磁盘上已不存在，需要去版本，同时**保留**括号里的说明。

只动这两格；其余含说明文字的单元格（P/Y 等历史列）一概不碰。

用法：python patch_ledger_b3_followup.py [--apply]
"""
from __future__ import annotations

import re
import shutil
import sys
import zipfile
from pathlib import Path

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
SHEET = "xl/worksheets/sheet10.xml"
BACKUP_SUFFIX = ".bak_b3_deversion_followup"
PREFIX = "assets/art/environments/base_facility_3d"

CELL = re.compile(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", re.S)
SPLIT = re.compile(r"^(assets/[A-Za-z0-9_/.\-]*?)_v\d{3}(（[^）]*）)$")


def main() -> int:
    apply = "--apply" in sys.argv
    with zipfile.ZipFile(LEDGER) as zin:
        members = zin.namelist()
        blobs = {n: zin.read(n) for n in members}

    txt = blobs[SHEET].decode("utf8")
    edits = []
    for m in CELL.finditer(txt):
        attrs, inner = m.group(1), m.group(2)
        r = re.search(r'r="([A-Z]+)(\d+)"', attrs)
        if not r or r.group(1) != "D" or r.group(2) not in ("65", "66"):
            continue
        t = re.search(r't="([^"]*)"', attrs)
        if not (t and t.group(1) == "inlineStr"):
            raise SystemExit(f"D{r.group(2)} 不是 inlineStr（t={t.group(1) if t else None}），停手")
        tm = re.search(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", inner, re.S)
        if not tm:
            raise SystemExit(f"D{r.group(2)} 取不到文本")
        old = tm.group(1)
        sm = SPLIT.match(old)
        if not sm:
            raise SystemExit(f"D{r.group(2)} 形态不符（无 _vNNN + 全角括号）：{old!r}")
        new = sm.group(1) + sm.group(2)
        if not (PROJECT / sm.group(1)).is_dir():
            raise SystemExit(f"D{r.group(2)} 去版本后的目录不存在：{sm.group(1)}")
        edits.append((m.start(2), m.end(2), inner.replace(old, new),
                      f"D{r.group(2)}", old, new))

    print(f"命中 {len(edits)} 格：")
    for _s, _e, _ni, tag, old, new in edits:
        print(f"  {tag}\n      {old}\n   -> {new}")
    if len(edits) != 2:
        raise SystemExit(f"预期 2 格，实得 {len(edits)} —— 停手")
    if not apply:
        print("\n（dry-run，未写盘）")
        return 0

    out, last = [], 0
    for s, e, ni, *_ in sorted(edits, key=lambda x: x[0]):
        out.append(txt[last:s])
        out.append(ni)
        last = e
    out.append(txt[last:])
    new_sheet = "".join(out)

    for tag in ("dimension", "mergeCell", "dataValidation", "row", "c"):
        a = len(re.findall(r"<(?:x:)?%s\b" % tag, txt))
        b = len(re.findall(r"<(?:x:)?%s\b" % tag, new_sheet))
        if a != b:
            raise SystemExit(f"{tag} 数量变化 {a}->{b}，拒绝写入")

    backup = LEDGER.with_name(LEDGER.name + BACKUP_SUFFIX)
    shutil.copy2(LEDGER, backup)
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as zout:
        for name in members:
            zout.writestr(name, new_sheet.encode("utf8") if name == SHEET else blobs[name])

    with zipfile.ZipFile(LEDGER) as z:
        assert z.namelist() == members, "zip 条目集合变了"
        diff = [n for n in members if z.read(n) != blobs[n]]
    if diff != [SHEET]:
        raise SystemExit(f"非预期差异条目：{diff}")
    print(f"\nLEDGER_B3_FOLLOWUP_OK 已写入（备份 {backup.name}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
