# -*- coding: utf-8 -*-
"""门禁：远征关卡01 设计页《3.1.1 Blender 资产完成情况》必须与场景账本一致。

判定口径见设计页 §3 的《Blender 资产完成度：判定规则》。本脚本做四件事：

  A. 文档表里出现的每个 AssetID，必须在账本里存在（两个 sheet 任一）；
  B. 该 AssetID 由账本推出的级别，必须出现在同一行的「账本制作状态」列里；
  B2. 该行的「级别」列（房型整体）必须等于「账本制作状态」列里出现过的**最低**级
      —— 对应设计页 §3 规则 3「一房多源取最低」；
  C. 账本里所有「远征相关行」都必须被文档表收录（漏写即失败）；
  D. 远征的房间种类源目录，必须「已在账本登记」或「已在文档里标为未登记」——
     防止出现第三处账本缺口却没人知道。

级别推导（唯一实现，文档只描述口径）：
  ✅ 已接入        —— 制作状态含「已接入」
  🟩 已导出未接入  —— GLB 或 Prefab 列已填且非「未制作」
  🟦 已登记未导出  —— 制作状态含「已完成」，且 GLB/Prefab 均未制作
  ⬜ 未开始        —— 其余
  🟨 有源未登记    —— 账本无行（本脚本只在 D 里用到，推不出来就说明是真没行）

用法：python scripts/check_expedition_room_asset_status.py [--json] [--doc <设计页路径>]
      （--doc 仅供 tests/tooling 里的自测把文档指向临时副本用）
退出码：0 = 通过；1 = 失败
"""

import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[1]
DESIGN_MD = ROOT / "docs/v0.1/design/远征关卡01设计.md"
LEDGER = ROOT / "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
EXPEDITION_DIR = ROOT / "assets/art/environments/tower_zones/expedition"
ROOM_TYPES_DIR = EXPEDITION_DIR / "source/room_types"

DOC_TABLE_MARKER = "#### 3.1.1"
LEVELS = ("✅", "🟩", "🟦", "🟨", "⬜")
# 由高到低。房型整体级别取「账本制作状态」列里出现过的**最低**级（设计页 §3 规则 3）。
LEVEL_ORDER = {"⬜": 0, "🟨": 1, "🟦": 2, "🟩": 3, "✅": 4}
ID_RE = re.compile(r"`(ENV-[A-Z0-9][A-Z0-9-]*)`")


# ---------------------------------------------------------------- 账本

def derive_level(status, prefab, glb):
    s = str(status or "")
    if "已接入" in s:
        return "✅"
    filled = lambda v: bool(str(v or "").strip()) and "未制作" not in str(v)
    if filled(prefab) or filled(glb):
        return "🟩"
    if "已完成" in s:
        return "🟦"
    return "⬜"


def read_ledger():
    """返回 {AssetID: {sheet, status, prefab, glb, source, usage, level}}"""
    wb = load_workbook(LEDGER, data_only=False)
    out = {}

    ws = wb["3D-场景通用"]
    for r in range(5, ws.max_row + 1):
        aid = ws.cell(row=r, column=1).value
        if not aid or not str(aid).strip():
            continue
        aid = str(aid).strip()
        status = ws.cell(row=r, column=14).value
        prefab = ws.cell(row=r, column=3).value
        glb = ws.cell(row=r, column=4).value
        out[aid] = dict(
            sheet="3D-场景通用", row=r, status=status,
            prefab=prefab, glb=glb,
            source=ws.cell(row=r, column=5).value,
            usage=ws.cell(row=r, column=13).value,
            level=derive_level(status, prefab, glb),
        )

    ws2 = wb["资产主表"]
    for r in range(6, ws2.max_row + 1):
        aid = ws2.cell(row=r, column=1).value
        if not aid or not str(aid).strip():
            continue
        aid = str(aid).strip()
        status = ws2.cell(row=r, column=11).value
        out.setdefault(aid, dict(
            sheet="资产主表", row=r, status=status,
            prefab=None, glb=None,
            source=ws2.cell(row=r, column=16).value,
            usage=ws2.cell(row=r, column=10).value,
            level=derive_level(status, None, None),
        ))
    return out


def is_expedition_row(rec, aid):
    if "EXPEDITION" in aid.upper():
        return True
    blob = "%s %s" % (rec.get("usage") or "", rec.get("status") or "")
    return "远征" in blob


# ---------------------------------------------------------------- 文档

def read_doc_table():
    md = DESIGN_MD.read_text(encoding="utf-8")
    if DOC_TABLE_MARKER not in md:
        raise SystemExit("设计页里找不到 %r —— 判定规则表被删了？" % DOC_TABLE_MARKER)
    start = md.index(DOC_TABLE_MARKER)
    end = md.find("\n### ", start)
    block = md[start: end if end != -1 else len(md)]

    rows = []
    for line in block.splitlines():
        if not line.startswith("|"):
            continue
        if set(line) <= set("|-: "):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        rows.append(dict(
            raw=line,
            cells=cells,
            # 第 5 列 = 账本制作状态（唯一允许出现级别 emoji 的地方）
            status_cell=cells[4] if len(cells) > 4 else "",
            # 第 6 列 = 房型整体级别（多源时取最低级）
            level_cell=cells[5] if len(cells) > 5 else "",
            ids=ID_RE.findall(line),
            levels=set(ch for ch in LEVELS if ch in line),
        ))
    # 丢掉表头行（含「AssetID」）
    return [r for r in rows if "AssetID" not in r["raw"]]


# ---------------------------------------------------------------- 检查

def main():
    global DESIGN_MD
    argv = sys.argv[1:]
    for i, a in enumerate(argv):
        if a == "--doc" and i + 1 < len(argv):
            DESIGN_MD = Path(argv[i + 1])

    ledger = read_ledger()
    doc = read_doc_table()
    failures = []

    doc_ids = set()
    for row in doc:
        for aid in row["ids"]:
            doc_ids.add(aid)
            if aid not in ledger:
                failures.append("A｜文档写了 %s，但账本里查无此行" % aid)
                continue
            rec = ledger[aid]
            # B：级别 emoji 必须写在「账本制作状态」列里，且与该行账本状态推出的级别一致。
            #    只看那一列 —— 整行扫 emoji 太宽松（同一行别处写对了就能蒙混过关）。
            if rec["level"] not in row["status_cell"]:
                failures.append(
                    "B｜%s 的级别不一致：账本（%s 第 %d 行，制作状态=%r）推出 %s，"
                    "但文档「账本制作状态」列里写的是 %r"
                    % (aid, rec["sheet"], rec["row"], str(rec["status"])[:40],
                       rec["level"], row["status_cell"][:60]))

        # 整行级别（房型整体）：多源取最低。只对有 AssetID 的行判 —— 空行「—」不参与。
        if row["ids"]:
            present = [ch for ch in LEVELS if ch in row["status_cell"]]
            if present:
                lowest = min(present, key=lambda ch: LEVEL_ORDER[ch])
                if lowest not in row["level_cell"]:
                    failures.append(
                        "B2｜房型整体级别不一致：该行「账本制作状态」里出现 %s，"
                        "按规则取最低应写 %s，但「级别」列写的是 %r"
                        % ("".join(sorted(set(present), key=lambda c: LEVEL_ORDER[c])),
                           lowest, row["level_cell"][:60]))

    # C：账本里的远征相关行有没有被文档漏写
    ledger_exp = {aid for aid, rec in ledger.items() if is_expedition_row(rec, aid)}
    for aid in sorted(ledger_exp - doc_ids):
        rec = ledger[aid]
        failures.append("C｜账本里有远征相关行 %s（%s 第 %d 行）但文档表没收录"
                        % (aid, rec["sheet"], rec["row"]))

    # D：房间种类源目录必须「已登记」或「已标未登记」
    room_type_dirs = []
    if ROOM_TYPES_DIR.is_dir():
        room_type_dirs = sorted(p for p in ROOM_TYPES_DIR.iterdir() if p.is_dir())
    registered_blob = " ".join(
        "%s %s" % (str(rec.get("source") or ""), str(rec.get("glb") or ""))
        for rec in ledger.values())
    for d in room_type_dirs:
        name = d.name
        if name in registered_blob:
            continue
        # 未登记：必须在文档里被显式标成「未登记」（同一行同时出现该目录名与「未登记」字样）
        flagged = any((name in r["raw"]) and ("未登记" in r["raw"]) for r in doc)
        if not flagged:
            failures.append(
                "D｜房间种类源目录 %s 既没在账本登记，也没在文档里标为「未登记」" % name)

    ok = not failures
    result = dict(
        ok=ok,
        ledger_assets=len(ledger),
        ledger_expedition_rows=sorted(ledger_exp),
        doc_asset_ids=sorted(doc_ids),
        room_type_dirs=[d.name for d in room_type_dirs],
        failures=failures,
    )
    if "--json" in sys.argv:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("=== 远征关卡01 资产状态 × 账本 同步校验 ===")
        print("账本资产总数      : %d" % len(ledger))
        print("账本远征相关行    : %s" % (", ".join(sorted(ledger_exp)) or "（无）"))
        print("文档表收录 AssetID: %s" % (", ".join(sorted(doc_ids)) or "（无）"))
        print("房间种类源目录    : %s" % (", ".join(d.name for d in room_type_dirs) or "（无）"))
        print()
        if ok:
            print("EXPEDITION_ASSET_STATUS_OK")
        else:
            print("发现 %d 处不一致：" % len(failures))
            for f in failures:
                print("  ✗ " + f)
            print()
            print("EXPEDITION_ASSET_STATUS_FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
