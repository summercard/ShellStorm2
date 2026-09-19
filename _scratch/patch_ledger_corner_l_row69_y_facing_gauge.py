# -*- coding: utf-8 -*-
"""外科式 XML 补丁（第三次）：第 69 行 ENV-TOWER-CORNER-L-5M 的 Y 列追加「逐面朝向判据已固化进探针」。

为什么还要补一次：第二次补丁记的是**离线对照脚本**测得的 4.99 / 1.54。
本轮把同口径判据固化进了 `probe_corner_l_visual.gd`（`FACE_GAUGES` + `_measure_faces()`），
并做了反向对照（防假绿）。台账是本资产的权威记录，应能自洽地回答
「这个朝向缺陷以后还抓不抓得到」，否则只看台账的人会以为证据永远依赖临时脚本。

只改 Y 一个 <c>，其余 zip 条目字节原样复制；不新增行，表仍是 6..241。

用法：
    python patch_ledger_corner_l_row69_y_facing_gauge.py            # dry-run
    python patch_ledger_corner_l_row69_y_facing_gauge.py --apply    # 落盘（先自动备份）
"""
from __future__ import annotations

import html as _html
import re
import shutil
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

LEDGER = Path(
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ledgers\ShellStorm2_场景账本_v001.xlsx"
)
BACKUP_SUFFIX = ".bak_corner_l_5m_facing_gauge"
SHEET_ASSET = "xl/worksheets/sheet3.xml"
ROW = 69

Y_APPEND = (
    "判据固化（2026-09-19 同日，第二轮）：上述逐面细节能量已从临时对照脚本搬进画面探针 "
    "probe_corner_l_visual.gd —— 新增 FACE_GAUGES + _measure_faces()：把长臂装饰面"
    "（房内侧 z=-0.3175）与结构背（外侧 z=+0.15）的世界四角用 Camera3D.unproject_position() "
    "投影到屏幕取外接矩形裁出来，量高通能量（积分图盒式模糊半径 6，平均 |灰度-邻域均值|，"
    "与离线脚本同口径）；判据 room/outer >= FACE_ENERGY_RATIO_MIN = 1.6，机内实测 3.220"
    "（0.02099 / 0.00652，多轮重跑数值一致）。反向对照（把两个取样面互换机位）得 0.149 -> exit 1 "
    "并报「长臂装饰面疑似朝外」，判别力约 21x —— 即该判据不是「怎么都绿」的摆设。"
    "这是本件唯一能抓住「面朝反」的自动判据：包络 / 面数 / 材质角色 / 原点约定四类断言对朝向缺陷全部全绿。"
)

CELL_RE = re.compile(r'<c r="(?P<ref>[A-Z]+\d+)"(?P<attrs>[^>]*?)(?:/>|>.*?</c>)', re.S)


def cell_block(xml: str, ref: str):
    for m in CELL_RE.finditer(xml):
        if m.group("ref") == ref:
            return m.start(), m.end(), m.group(0)
    return None


def style_of(block: str) -> str:
    m = re.search(r'\ss="(\d+)"', block)
    return ' s="%s"' % m.group(1) if m else ""


def text_cell(ref: str, style: str, text: str) -> str:
    return '<c r="%s"%s t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>' % (
        ref,
        style,
        escape(text),
    )


def shared_value(shared_xml: str, index: int) -> str:
    sis = re.findall(r"<si>(.*?)</si>", shared_xml, re.S)
    return _html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", sis[index], re.S)))


def cell_text(xml: str, ref: str, shared_xml: str = "") -> str | None:
    """inlineStr 直接取 <t>；共享字符串（t="s"）查 sharedStrings 表。"""
    found = cell_block(xml, ref)
    if not found:
        return None
    block = found[2]
    if 't="s"' in block:
        m = re.search(r"<v>(\d+)</v>", block)
        return shared_value(shared_xml, int(m.group(1))) if m else None
    m = re.search(r"<t[^>]*>(.*?)</t>", block, re.S)
    return _html.unescape(m.group(1)) if m else None


def main() -> int:
    apply = "--apply" in sys.argv
    with zipfile.ZipFile(LEDGER) as z:
        names = z.namelist()
        infos = {n: z.getinfo(n) for n in names}
        blobs = {n: z.read(n) for n in names}

    asset = blobs[SHEET_ASSET].decode("utf-8")
    shared = blobs["xl/sharedStrings.xml"].decode("utf-8")

    cur_id = cell_text(asset, "A%d" % ROW, shared)
    if cur_id != "ENV-TOWER-CORNER-L-5M":
        raise SystemExit("row %d is not ENV-TOWER-CORNER-L-5M (got %r)" % (ROW, cur_id))

    cur_y = cell_text(asset, "Y%d" % ROW, shared) or ""

    if "判据固化" in cur_y:
        raise SystemExit("Y%d already carries the facing-gauge note — 拒绝重复追加" % ROW)
    if "同日朝向修正" not in cur_y:
        raise SystemExit("Y%d does not carry the flip note — 状态不符（先跑第二次补丁）" % ROW)
    if "4.99 vs 外面 1.54" not in cur_y:
        raise SystemExit("Y%d does not carry the offline 4.99/1.54 numbers — 状态不符" % ROW)

    found = cell_block(asset, "Y%d" % ROW)
    if not found:
        raise SystemExit("cell Y%d not found" % ROW)
    start, end, block = found
    new_block = text_cell("Y%d" % ROW, style_of(block), cur_y + Y_APPEND)
    asset = asset[:start] + new_block + asset[end:]

    s_block = cell_block(asset, "S%d" % ROW)
    if not s_block or "COUNTIF($R$6:$R$241,R%d)" % ROW not in s_block[2]:
        raise SystemExit("S%d formula shape unexpected" % ROW)

    info = "  Y%d [%s] -> inlineStr(%d chars)" % (ROW, style_of(block).strip(), len(cur_y + Y_APPEND))

    if not apply:
        print(info)
        print("  appended tail:", Y_APPEND[:70], "...")
        print("\n[dry-run] 未落盘。加 --apply 执行。")
        return 0

    backup = LEDGER.with_name(LEDGER.name + BACKUP_SUFFIX)
    shutil.copy2(LEDGER, backup)
    print("备份 -> %s" % backup.name)

    blobs[SHEET_ASSET] = asset.encode("utf-8")
    with zipfile.ZipFile(LEDGER, "w", zipfile.ZIP_DEFLATED) as z:
        for n in names:
            zi = zipfile.ZipInfo(n, date_time=infos[n].date_time)
            zi.compress_type = infos[n].compress_type
            zi.external_attr = infos[n].external_attr
            z.writestr(zi, blobs[n])
    print(info)
    print("已写回 %s" % LEDGER.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
