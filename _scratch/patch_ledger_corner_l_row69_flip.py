# -*- coding: utf-8 -*-
"""外科式 XML 补丁（第二次）：第 69 行 ENV-TOWER-CORNER-L-5M 的当日朝向修正。

背景：首版 L 墙角的长臂是纯平移（无偏航），装饰面留在 Godot +Z（L 的外侧），
玩家在房间里看到的是结构背。当日修正为 T(+2.5,0,0) @ Rz(+180°) 并重导出，
于是 GLB 变了 -> 本行的 T 列哈希必须同批更新；N 列的可视包络也随之由 5.3175 收成 5.15。

只改 N / T / Y 三个 <c>：
  · N —— 可视包络尺寸 + 记下「装饰面朝房内（长臂 -Z / 短臂 +X）」
  · T —— GLB 实测 SHA-256（297ffb52… -> 451ba73e…）
  · Y —— 追加 2026-09-19 同日朝向修正说明段
范围引用一律不动（不新增行，表仍是 6..241），其余 zip 条目字节原样复制。

用法：
    python patch_ledger_corner_l_row69_flip.py            # dry-run
    python patch_ledger_corner_l_row69_flip.py --apply    # 落盘（先自动备份）
"""
from __future__ import annotations

import re
import shutil
import sys
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

LEDGER = Path(r"I:\工作项目\shellstrom2\ShellStorm2\assets\registry\ledgers\ShellStorm2_场景账本_v001.xlsx")
BACKUP_SUFFIX = ".bak_corner_l_5m_flip"
SHEET_ASSET = "xl/worksheets/sheet3.xml"
ROW = 69

OLD_HASH = "297ffb52654c5ea187565d64357f2b4bcdd83fc7c5fe5343979a1c50d54c9527"
NEW_HASH = "451ba73e82aa38fa4bf91e8421496b09488cd202c453aee2c749619146031c71"

N_NEW = (
    "GLB / 可视包络 5.15×11.9×5.15m（原点=转角，两臂向 +X/-Z 伸出；两臂装饰面都朝房内："
    "长臂 Godot -Z、短臂 Godot +X）/ 结构占地 5×11.9×5m / 单 Mesh 三材质角色 / 自带两臂碰撞"
)

Y_APPEND = (
    "\n2026-09-19 同日朝向修正（grep 关键词：ARM_FACING_GODOT / CORNER_ARM_FACING_WRONG）："
    "首版长臂是纯平移 T(+2.5,0,0)、无偏航，于是保留了烘焙后朝 Godot +Z 的装饰面——那是 L 的外侧，"
    "玩家在房间里面对长臂时看到的是平整的结构背；短臂当时是对的（+X）。"
    "根因是「哪一侧算房间内」被写错：两臂沿 +X 与 -Z 伸出，房间内侧是两臂之间的凹象限（+X/-Z），"
    "而 prefab 注释与探针当时标成 -X/-Z，朝向断言也照错标号写成「长臂装饰面在 +Z」，于是自洽放行。"
    "正确口径只认运行时：_spawn_room_corner()（两臂从角点沿房间两条边指向房内）与 "
    "_build_corner_aware_wall_run()（南墙 rotation_y=PI、西墙 +PI/2，装饰面永远朝房内）。"
    "修正：长臂补 Rz(+180°)（与南墙同款；短臂不变）；派生脚本新增 ARM_FACING_GODOT 逐臂断言——"
    "拿「装饰面凸 0.3175 / 结构背 0.15」这条美术不对称当朝向指纹，逐臂比对自身 AABB，任一条反了即 "
    "CORNER_ARM_FACING_WRONG（既有包络/面数/材质/原点四类断言都抓不到朝向）；"
    "prefab origin_note 与 probe_corner_l_visual 机位改成「房内侧 = 两臂之间的凹象限（+X/-Z）」。"
    "重导出实测：两臂仍各 5319 面、L 合计 10638（「与直墙逐面一致」未被破坏）；可视包络 5.15×11.9×5.15、"
    "最小角 (-0.15, 0, -5.0)（z_max 由 0.3175 收成 0.15：装饰面朝内、外侧只剩结构背）；"
    "PREFAB_CONTRACT_OK count=6（0 ERROR）；CORNER_L_VISUAL_OK captured=4；"
    "逐面细节能量：长臂房内面 4.99 vs 外面 1.54，pair 图对照直墙 3.72 / L 长臂 3.97。"
    "本行 T 列 GLB 哈希随之二次改写（297ffb52… -> 451ba73e…）：路径与版本串仍是 v001"
    "（同一份资产的当日修正，不是新版本），但哈希变了，凡引用哈希处须同批更新。"
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
        ref, style, escape(text)
    )


def shared_value(shared_xml: str, index: int) -> str:
    import html as _html
    sis = re.findall(r"<si>(.*?)</si>", shared_xml, re.S)
    return _html.unescape("".join(re.findall(r"<t[^>]*>(.*?)</t>", sis[index], re.S)))


def cell_text(xml: str, ref: str, shared_xml: str = "") -> str | None:
    """inlineStr 直接取 <t>；共享字符串（t="s"）查 sharedStrings 表。"""
    import html as _html
    found = cell_block(xml, ref)
    if not found:
        return None
    block = found[2]
    if 't="s"' in block:
        m = re.search(r"<v>(\d+)</v>", block)
        if not m:
            return None
        return shared_value(shared_xml, int(m.group(1)))
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

    cur_n = cell_text(asset, "N%d" % ROW, shared) or ""
    cur_t = cell_text(asset, "T%d" % ROW, shared) or ""
    cur_y = cell_text(asset, "Y%d" % ROW, shared) or ""

    if "同日朝向修正" in cur_y:
        raise SystemExit("Y%d already carries the flip note — 拒绝重复追加" % ROW)
    if "2026-09-19：可视本体换成塔楼 A 套正式美术" not in cur_y:
        raise SystemExit("Y%d does not carry the 2026-09-19 upgrade note — 状态不符" % ROW)
    if cur_t != OLD_HASH:
        raise SystemExit("T%d is %r, expected the pre-flip hash %r" % (ROW, cur_t, OLD_HASH))
    if "5.3175" not in cur_n:
        raise SystemExit("N%d does not carry the pre-flip envelope %r" % (ROW, cur_n))

    log = []
    for col, text in (("N", N_NEW), ("T", NEW_HASH), ("Y", cur_y + Y_APPEND)):
        found = cell_block(asset, "%s%d" % (col, ROW))
        if not found:
            raise SystemExit("cell %s%d not found" % (col, ROW))
        start, end, block = found
        asset = asset[:start] + text_cell("%s%d" % (col, ROW), style_of(block), text) + asset[end:]
        log.append("  %-4s [%s] -> inlineStr(%d chars) %s" % (
            "%s%d" % (col, ROW), style_of(block).strip(), len(text), text[:46]))

    # S 列公式与范围引用本次不动，做一次结构自检
    s_block = cell_block(asset, "S%d" % ROW)
    if not s_block or "COUNTIF($R$6:$R$241,R%d)" % ROW not in s_block[2]:
        raise SystemExit("S%d formula shape unexpected" % ROW)

    if not apply:
        for line in log:
            print(line)
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
    for line in log:
        print(line)
    print("已写回 %s" % LEDGER.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
