# -*- coding: utf-8 -*-
"""B3：把台账里 base_facility_3d 的**运行路径单元格**就地去掉版本号。

（去版本化计划 §4.1 第 ⑦ 步；沿用 B2 的做法，见 _scratch/patch_ledger_b2_deversion.py）

只改「运行路径列」：
  * 3D-场景通用 (sheet10)  C = runtime tscn,  D = components glb
  * 3D-设施     (sheet11)  C = runtime tscn,  D = components glb
  * 资产主表    (sheet2)   O = 权威运行 tscn 路径

**明确不动**（保住版本事实 / 契约豁免）：
  * E 列（source .blend）—— source 按命名契约允许带版本
  * 资产主表 P 列（关联文件清单）、Y 列（变更日志）—— 历史事实
  * asset_import_manifest_v001.json —— 按命名契约豁免（用于记录源版本）

判定「纯运行路径单元格」：单元格文本 strip 后**恰好**是本批前缀下的一个非 source 路径。
任何含分隔符 / 说明文字 / 换行的单元格一律跳过（避免篡改记录）。

映射：优先用已暂存的 rename map（能正确处理 corner_l_5m 这类「同名冲突已 PINNED」的格），
否则退化为「去掉全部 _vNNN」。**目标文件必须真实存在**，否则列入 blocked 交人工判断。

幂等：目标串已就位则不重复改。
落盘：就地在原文件写（memory：勿 tmp+replace，Windows 会 WinError 5）。

用法：
  python patch_ledger_b3_deversion.py            # dry-run
  python patch_ledger_b3_deversion.py --apply    # 落盘（先备份）
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

PROJECT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
LEDGER = PROJECT / "assets/registry/ShellStorm2_美术资产台账_v001.xlsx"
PREFIX = "assets/art/environments/base_facility_3d"
BACKUP_SUFFIX = ".bak_b3_deversion"

# (sheet xml 成员, sheet 名, 允许的列)
TARGETS = [
    ("xl/worksheets/sheet10.xml", "3D-场景通用", ("C", "D")),
    ("xl/worksheets/sheet11.xml", "3D-设施", ("C", "D")),
    ("xl/worksheets/sheet2.xml", "资产主表", ("O",)),
]

V = re.compile(r"_v\d{3}")
CELL = re.compile(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", re.S)


def rename_map() -> dict:
    raw = subprocess.run(
        ["git", "-C", str(PROJECT), "diff", "--cached", "--name-status", "-z", "-M",
         "--diff-filter=R", "--", PREFIX],
        capture_output=True).stdout.decode("utf-8", "surrogateescape")
    parts = [p for p in raw.split("\0") if p]
    return {parts[i + 1]: parts[i + 2] for i in range(0, len(parts) - 2, 3)}


def cell_text(inner: str) -> str:
    """t="str"/inlineStr 的文本；t="s" 的 <v> 是索引，不在此解析。"""
    ts = re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", inner, re.S)
    if ts:
        return "".join(ts)
    v = re.search(r"<(?:x:)?v>(.*?)</(?:x:)?v>", inner, re.S)
    return v.group(1) if v else ""


def sst_text(si: str) -> str:
    return "".join(re.findall(r"<(?:x:)?t[^>]*>(.*?)</(?:x:)?t>", si, re.S))


def main() -> int:
    apply = "--apply" in sys.argv
    if not LEDGER.is_file():
        raise SystemExit(f"缺少台账：{LEDGER}")

    with zipfile.ZipFile(LEDGER) as zin:
        members = zin.namelist()
        blobs = {name: zin.read(name) for name in members}

    rmap = rename_map()
    print(f"staged renames under {PREFIX}: {len(rmap)}")

    sst = []
    if "xl/sharedStrings.xml" in members:
        sst = re.findall(r"<(?:x:)?si>(.*?)</(?:x:)?si>",
                         blobs["xl/sharedStrings.xml"].decode("utf8", "ignore"), re.S)

    # member -> [(inner_start, inner_end, new_inner, tag, old, new)]
    edits: dict[str, list] = {}
    blocked: list[tuple] = []
    shared_hits: list[tuple] = []

    for member, sheetname, cols in TARGETS:
        if member not in members:
            raise SystemExit(f"缺少 zip 成员 {member}")
        txt = blobs[member].decode("utf8")
        for m in CELL.finditer(txt):
            attrs, inner = m.group(1), m.group(2)
            r = re.search(r'r="([A-Z]+)(\d+)"', attrs)
            if not r or r.group(1) not in cols:
                continue
            t = re.search(r't="([^"]*)"', attrs)
            tval = t.group(1) if t else ""
            tag = f"{sheetname}!{r.group(1)}{r.group(2)}"

            if tval == "s":     # 共享字符串：值不在本 sheet，本脚本不动
                vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", inner)
                if vm and int(vm.group(1)) < len(sst):
                    real = sst_text(sst[int(vm.group(1))]).strip()
                    if real.startswith(PREFIX) and V.search(real):
                        shared_hits.append((tag, real[:120]))
                continue

            val = cell_text(inner)
            if not val:
                continue
            v = val.strip()
            if not v.startswith(PREFIX) or not V.search(v):
                continue
            # 只认「整格就是一个路径」；混合文本/带说明的一律不动
            if v != val or "\n" in v or "；" in v or ";" in v or "（" in v:
                continue
            if "/source/" in v or v.endswith(".blend"):
                continue
            new = rmap.get(v) or V.sub("", v)
            if new == v:
                continue
            if not (PROJECT / new).is_file():
                blocked.append((tag, v, new, "稳定目标不存在"))
                continue
            edits.setdefault(member, []).append(
                (m.start(2), m.end(2), inner.replace(v, new), tag, v, new))

    total = sum(len(v) for v in edits.values())
    print(f"\n可自动改写单元格：{total}")
    for member in sorted(edits):
        for _s, _e, _ni, tag, old, new in edits[member]:
            print(f"  {tag}\n      {old}\n   -> {new}")
    if shared_hits:
        print(f"\n!! 共享字符串命中（本脚本不处理）：{len(shared_hits)}")
        for tag, real in shared_hits:
            print(f"   {tag}  {real}")
    if blocked:
        print(f"\n!! 无法自动判定，交人工：{len(blocked)}")
        for tag, old, new, why in blocked:
            print(f"   {tag}  [{why}]\n      {old}\n   ~> {new}")

    if not apply:
        print("\n（dry-run，未写盘；加 --apply 落盘）")
        return 0
    if shared_hits:
        raise SystemExit("存在共享字符串命中，拒绝写入（先人工处理）")
    if not edits:
        print("无改动")
        return 0

    # —— 按 inner 区间逆序重建（标签原样保留）——
    new_blobs = dict(blobs)
    for member, lst in edits.items():
        txt = blobs[member].decode("utf8")
        out, last = [], 0
        for s, e, ni, *_ in sorted(lst, key=lambda x: x[0]):
            out.append(txt[last:s])
            out.append(ni)
            last = e
        out.append(txt[last:])
        new_blobs[member] = "".join(out).encode("utf8")

    # —— 保真校验 ——
    for member in edits:
        orig = blobs[member].decode("utf8")
        news = new_blobs[member].decode("utf8")
        for tag in ("dimension", "mergeCell", "dataValidation", "row", "c"):
            a = len(re.findall(r"<(?:x:)?%s\b" % tag, orig))
            b = len(re.findall(r"<(?:x:)?%s\b" % tag, news))
            if a != b:
                raise SystemExit(f"{member}: {tag} 数量变化 {a}->{b}，拒绝写入")

    backup = LEDGER.with_name(LEDGER.name + BACKUP_SUFFIX)
    shutil.copy2(LEDGER, backup)
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as zout:
        for name in members:
            zout.writestr(name, new_blobs[name])

    with zipfile.ZipFile(LEDGER) as z:
        assert z.namelist() == members, "zip 条目集合变了"
        diff = [n for n in members if z.read(n) != blobs[n]]
    unexpected = set(diff) - set(edits)
    if unexpected:
        raise SystemExit(f"非预期差异条目：{sorted(unexpected)}")
    print(f"\nLEDGER_B3_OK 已写入 {len(diff)} 个成员（备份 {backup.name}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
