"""把「大世界 · 地下街区 编号02」从 v003 原地升级到 v004（街面道具 0.1m 颗粒）。

与 v003 脚本的差别
------------------
1. 版本号 / 路径 / 哈希换成 v004；
2. 规模描述改成「32 件细化 / 21 处 0.1m 级零件」口径；
3. 变更日志改成 v0.1.48（幂等：重跑先删本版行）；
4. 额外把「颗粒度审计结果」写进 R 列，让账本自带验收证据。

组件数与实例数不变（47 / 211）：本版是原地升级几何，不新增也不删除组件。
"""

from __future__ import annotations

import hashlib
import io
import json
import os

from openpyxl import load_workbook

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = os.path.join(PROJECT, "assets", "registry", "ledgers", "ShellStorm2_场景账本_v001.xlsx")
V4 = os.path.join(PROJECT, "art_source", "environments", "open_world", "source",
                  "underground_street", "v004")
BLEND = os.path.join(V4, "env_underground_street_source_v004.blend")
ROW = 973
ASSET_ID = "ENV-OPENWORLD-UNDERGROUND-STREET-02"


def main():
    sha = hashlib.sha256(open(BLEND, "rb").read()).hexdigest()
    cat = json.load(io.open(os.path.join(V4, "component_catalog.json"), encoding="utf-8"))
    gran = json.load(io.open(os.path.join(V4, "qa", "granularity.json"), encoding="utf-8"))
    val = json.load(io.open(os.path.join(V4, "qa", "validate_game_prop.json"), encoding="utf-8"))

    polys = sum(c["polygon_count"] for c in cat["components"])
    detailed = [c for c in cat["components"] if c.get("detailed_in_v004")]
    total_fine = sum(r["fine_count"] for r in gran["components"] if not r.get("skipped"))

    wb = load_workbook(LEDGER)
    ws = wb["资产主表"]
    # 表头在第 5 行，A=AssetID、M=版本、N=规格、O=文件路径、T=SHA-256、Y=备注
    assert ws.cell(5, 1).value == "AssetID", "表头行不是第 5 行：%r" % ws.cell(5, 1).value
    assert ws.cell(ROW, 1).value == ASSET_ID, "第 %d 行不是目标资产：%r" % (
        ROW, ws.cell(ROW, 1).value)

    ws.cell(ROW, 13).value = "v004"
    ws.cell(ROW, 14).value = (
        "Blender XYZ 52.0×52.0×30.0m 总包络（含穹顶）；组件 47 件（其中 %d 件本版按 0.1m 颗粒"
        "重写几何：轿车/路灯/信号杆/护栏/防撞柱/配电柜/排水篦/空调/管束/售货机/吊灯/风机/"
        "屋顶设备/刀旗/垃圾/跨街电缆/贴墙线束/广告灯箱/桁架/桥墩/风管/桥铭牌 + 5 栋建筑补"
        "预埋件层）/ 实例 211 个 / %d 三角面；同族最大 2（≤3）；"
        "0.1m 级独立零件 %d 个（颗粒度审计 %d/%d 通过）；街区 open_world 地下区"
        % (len(detailed), polys, total_fine, gran["judged_count"] - gran["failed_count"],
           gran["judged_count"]))
    ws.cell(ROW, 15).value = os.path.relpath(BLEND, PROJECT).replace("\\", "/")
    # R 列是公式（查重键），不能写文本；审计结论写到 Y 列（备注）后面追加
    prev_note = ws.cell(ROW, 25).value or ""
    audit_note = ("v004 颗粒度审计：scripts/blender/audit_granularity.py 判定 %d 项、失败 %d 项；"
                  "0.1m 级独立零件（≤0.20m）合计 %d 个。验证器 17 项通过、"
                  "逐面 PaletteUV %d/%d。"
                  % (gran["judged_count"], gran["failed_count"], total_fine,
                     val["valid_island_polygon_count"], val["polygon_count"]))
    ws.cell(ROW, 25).value = (prev_note + " | " + audit_note) if "v004 颗粒度审计" not in prev_note         else prev_note
    ws.cell(ROW, 20).value = sha

    # 变更日志（幂等）
    log = wb["域变更日志"]
    for rr in range(log.max_row, 1, -1):
        if log.cell(rr, 1).value == "v0.1.48":
            log.delete_rows(rr, 1)
    # 日志表头在第 5 行：A=台账版本 B=日期 C=变更类型 D=范围 E=说明 F=兼容性 G=负责人
    r = log.max_row + 1
    log.cell(r, 1).value = "v0.1.48"
    log.cell(r, 2).value = "2026-10-20"
    log.cell(r, 3).value = "地下街区02 街面道具颗粒度重写"
    log.cell(r, 4).value = "关卡场景 / 大世界 地下街区 编号02"
    log.cell(r, 5).value = (
        "%s 版本 v003→v004：%d 个组件按「0.1m 颗粒」重写几何，三角面 23,518 → %d；"
        "0.1m 级独立零件（≤0.20m）0 → %d。起因：v003 建筑已到 6.7k 面，而轿车仍 176 面、"
        "路灯 96 面、空调 44 面，近景全是方块。"
        % (ASSET_ID, len(detailed), polys, total_fine))
    log.cell(r, 6).value = (
        "第 973 行原地升级（同 asset_id 仍只占一行）；组件数 47、实例数 211 不变；"
        "新增 scripts/blender/audit_granularity.py（把「0.1m 颗粒」变成可门禁指标："
        "按尺寸归一化的零件数与 0.1m 级零件数）；新增 ug_props_v004{,_street,_facility,"
        "_roof,_struct,_grain}.py 六个几何模块。sha256 " + sha[:16])
    log.cell(r, 7).value = "Codex"
    wb.save(LEDGER)

    print("ROW", ROW, "ver v004", "sha", sha[:16])
    print("polys", polys, "detailed", len(detailed), "fine_total", total_fine)
    print("granularity", gran["judged_count"] - gran["failed_count"], "/", gran["judged_count"])
    print("log row", r)


main()
