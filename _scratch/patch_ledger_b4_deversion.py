# -*- coding: utf-8 -*-
"""B4：把台账里 rooftop_shelter_3d 的**运行路径单元格**就地去掉版本号。

（去版本化计划 §4.1 第 ⑦ 步；沿用 B3 / B6 的白名单范式）

本批只有 2 格（由 _scratch/b4_ledger_classify.py 全台账审计 + 行上下文判定）：
  * 3D-场景通用 (sheet10) D61 = 运行资产路径（GLB）
        env_rooftop_shelter_90x80m_facilities_v021.glb
     -> env_rooftop_shelter_90x80m_facilities.glb        （v021 占规范名）
  * 资产主表   (sheet2)  O300 = 文件路径（唯一登记源）
        env_rooftop_shelter_50m_game_v011.glb
     -> env_rooftop_shelter_50m_game.glb                 （collapse 留最高代）

**明确不动**（B3/B6 先例）：
  * 3D-场景通用 E（source）/ O（版本事实）/ M（Blocks）等非运行路径列
  * 资产主表 P（关联文件清单）/ Y（变更日志）/ M（版本 v011）/ E（source）
    —— 历史与源事实，改了就是篡改记录
  * reports/*.json 与 asset_import_manifest_v001.json —— 命名契约豁免

**白名单判据**：单元格文本 strip 后**恰好等于**暂存区 rename map 里的一个「旧路径」。
这条判据同时锁死 (sheet, 列, 期望旧值) 三者，散文格与历史列天然不命中。

映射只用暂存区 rename map（不猜「去掉 _vNNN」），且**目标文件必须真实存在**。

幂等；落盘就地写（memory：勿 tmp+replace，Windows 会 WinError 5）。

用法：
  python _scratch/patch_ledger_b4_deversion.py            # dry-run
  python _scratch/patch_ledger_b4_deversion.py --apply    # 落盘（先备份）
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
BACKUP_SUFFIX = ".bak_b4_deversion"

B4_ROOT = "assets/art/environments/rooftop_shelter_3d/"

# (zip 成员, sheet 名, 允许的列) —— 运行路径列
TARGETS = [
    ("xl/worksheets/sheet10.xml", "3D-场景通用", ("D",)),
    ("xl/worksheets/sheet2.xml", "资产主表", ("O",)),
]

# 只允许这 2 格被改写（(sheet 名, 列, 行) -> 期望的新值后缀），双重锁
ALLOWED_CELLS = {
    ("3D-场景通用", "D", "61"),
    ("资产主表", "O", "300"),
}

V = re.compile(r"_v\d{3}")
CELL = re.compile(r"<(?:x:)?c\b([^>]*?)>(.*?)</(?:x:)?c>", re.S)


def rename_map() -> dict:
    raw = subprocess.run(
        ["git", "-C", str(PROJECT), "diff", "--cached", "--name-status", "-z", "-M",
         "--diff-filter=R"],
        capture_output=True).stdout.decode("utf-8", "surrogateescape")
    parts = [p for p in raw.split("\0") if p]
    return {parts[i + 1]: parts[i + 2] for i in range(0, len(parts) - 2, 3)}


def cell_text(inner: str) -> str:
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
    whitelist = {o: n for o, n in rmap.items() if o.startswith(B4_ROOT)}
    print(f"暂存区 rename 总数 {len(rmap)}；落在 B4 根内 {len(whitelist)}")
    for o in sorted(x for x in whitelist if V.search(x)):
        print(f"   {o}\n    -> {whitelist[o]}")

    sst = []
    if "xl/sharedStrings.xml" in members:
        sst = re.findall(r"<(?:x:)?si>(.*?)</(?:x:)?si>",
                         blobs["xl/sharedStrings.xml"].decode("utf8", "ignore"), re.S)

    edits: dict[str, list] = {}
    blocked: list[tuple] = []
    shared_hits: list[tuple] = []
    skipped_other_cols: list[tuple] = []
    seen_allowed: set[tuple] = set()

    for member, sheetname, cols in TARGETS:
        if member not in members:
            raise SystemExit(f"缺少 zip 成员 {member}")
        txt = blobs[member].decode("utf8")
        for m in CELL.finditer(txt):
            attrs, inner = m.group(1), m.group(2)
            r = re.search(r'r="([A-Z]+)(\d+)"', attrs)
            if not r:
                continue
            col, row = r.group(1), r.group(2)
            t = re.search(r't="([^"]*)"', attrs)
            tval = t.group(1) if t else ""
            tag = f"{sheetname}!{col}{row}"

            if col not in cols:
                if tval == "s":
                    vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", inner)
                    real = sst_text(sst[int(vm.group(1))]).strip() if (vm and int(vm.group(1)) < len(sst)) else ""
                    if V.search(real) and B4_ROOT in real:
                        skipped_other_cols.append((tag, tval, real[:110]))
                    continue
                real = cell_text(inner).strip()
                if V.search(real) and B4_ROOT in real:
                    skipped_other_cols.append((tag, tval, real[:110]))
                continue

            if tval == "s":
                vm = re.search(r"<(?:x:)?v>(\d+)</(?:x:)?v>", inner)
                if vm and int(vm.group(1)) < len(sst):
                    real = sst_text(sst[int(vm.group(1))]).strip()
                    if real in whitelist:
                        shared_hits.append((tag, real))
                continue

            val = cell_text(inner)
            if not val:
                continue
            v = val.strip()
            if v not in whitelist:
                continue
            new = whitelist[v]
            if new == v:
                continue
            if (sheetname, col, row) not in ALLOWED_CELLS:
                blocked.append((tag, v, new, "不在 ALLOWED_CELLS 白名单内"))
                continue
            seen_allowed.add((sheetname, col, row))
            if not (PROJECT / new).is_file():
                blocked.append((tag, v, new, "稳定目标不存在"))
                continue
            edits.setdefault(member, []).append(
                (m.start(2), m.end(2), inner.replace(v, new), tag, v, new))

    total = sum(len(v) for v in edits.values())
    print(f"\n可改写单元格：{total}")
    for member in sorted(edits):
        for _s, _e, _ni, tag, old, new in edits[member]:
            print(f"  {tag}\n      {old}\n   -> {new}")
    if shared_hits:
        print(f"\n!! 共享字符串命中（本脚本不处理，将拒绝写入）：{len(shared_hits)}")
        for tag, real in shared_hits:
            print(f"   {tag}  {real}")
    if blocked:
        print(f"\n!! 无法自动判定，交人工：{len(blocked)}")
        for tag, old, new, why in blocked:
            print(f"   {tag}  [{why}]\n      {old}\n   ~> {new}")
    if skipped_other_cols:
        print(f"\n—— 非目标列上的带版本残留（按契约保留，仅列出）：{len(skipped_other_cols)}")
        for tag, tval, real in skipped_other_cols:
            print(f"   {tag} ({tval})  {real}")

    EXPECTED = 2
    if not apply:
        print(f"\n（dry-run，未写盘；加 --apply 落盘。预期 {EXPECTED} 格）")
        if total == 0 and not seen_allowed and not blocked and not shared_hits:
            print("（本次 0 格 —— 可能已落盘过；请用 b4_ledger_classify.py 复核）")
        return 0 if total == EXPECTED else 1
    if shared_hits:
        raise SystemExit("存在共享字符串命中，拒绝写入（先人工处理）")
    if blocked:
        raise SystemExit("存在 blocked 项，拒绝写入（先人工判断）")
    if total != EXPECTED:
        raise SystemExit(f"改写格数 {total} != 预期 {EXPECTED}，拒绝写入")
    if seen_allowed != ALLOWED_CELLS:
        raise SystemExit(f"命中格集合 {sorted(seen_allowed)} != 白名单 {sorted(ALLOWED_CELLS)}")

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
    print(f"\nLEDGER_B4_OK 已写入 {len(diff)} 个成员 / {total} 格（备份 {backup.name}）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
