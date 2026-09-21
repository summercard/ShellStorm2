# -*- coding: utf-8 -*-
"""账本同步：100F 天台装饰布局 五次修正（绿化贴墙）+ 天台不再生成室内照明设施。

改动四处：
  1) 3D-场景通用 P113..P128 —— 陈旧重放计数「99实例/7组/0启用碰撞」→「120实例/6组（…）」
  2) 3D-场景通用 row146 L 列 —— 追加五次修正说明
  3) 资产主表 row240 —— 同步重生成后的 .blend SHA-256 + T 列追加五次修正说明
  4) 域变更日志 —— 追加 v0.1.9
先备份，后回读校验。
"""
import shutil
from copy import copy

import openpyxl

P = "assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx"
BAK = P + ".bak_rooftop_decor_greenery_flush"
shutil.copy2(P, BAK)
print("backup ->", BAK)

wb = openpyxl.load_workbook(P)

# ── 1) 陈旧重放计数 ──
ws = wb["3D-场景通用"]
OLD = "接入 100F 装饰布局＝99实例/7组/0启用碰撞"
NEW = "接入 100F 装饰布局＝120实例/6组（绿化20件blocking，其余visual_only）"
hits = []
for row in ws.iter_rows():
    for cell in row:
        if isinstance(cell.value, str) and OLD in cell.value:
            cell.value = cell.value.replace(OLD, NEW)
            hits.append(cell.coordinate)
print("P列陈旧计数命中:", len(hits), hits)

# ── 2) row146 说明追加 ──
ADD_146 = (
    "；2026-09-21 五次修正：绿化 20 件由「离墙中心线 2.15m 的单一环线」改为**逐件按自身半进深"
    "背贴建筑外皮**（件心离墙中心线 = SHELL_WALL_T/2 − 埋入 0.05 + 半进深；花箱 0.5925 / 大盆栽"
    " 0.8727377 / 小盆栽 0.5473868），南/北/东/西四边各成对、背面齐平、正面自然错落；同时补齐朝向"
    "（front_direction=−Y ⇒ yaw 0/π/+π/2/−π/2 分别朝南/北/东/西，西侧花圃原 +π/2 正面朝墙里已修）"
)
ws.cell(146, 6).value = (ws.cell(146, 6).value or "") + ADD_146

# ── 3) 资产主表 row240 ──
ws2 = wb["资产主表"]
OLD_SHA = ws2.cell(240, 20).value
NEW_SHA = "7e8b2c511cbe1c9a6715f1f98829dcf480f9e839faaadc7b41318a4d4b19aa4a"
ws2.cell(240, 20).value = NEW_SHA
ADD_240 = (
    "2026-09-21 五次修正（业主实机报「花盆和花圃靠墙太远了，要挨着墙放，不然还有个空虚」）："
    "绿化环由「离墙中心线 2.15m 单一环线」改为**逐件按自身半进深背贴建筑外皮** —— 件心离墙中心线 = "
    "SHELL_WALL_T/2 − WALL_MOUNT_EMBED(0.05) + half_depth（背面埋进外皮 0.05m，与墙挂空调同口径）；"
    "花箱 0.5925 / 大盆栽 0.8727377 / 小盆栽 0.5473868，南/北/东/西四边各成对，背面齐平、正面自然错落"
    "（旧版每件背后空 1.14~1.45m 可见地砖带）。朝向补齐：三件 front_direction 均为 −Y ⇒ yaw 0/π/+π/2/−π/2 "
    "分别朝南/北/东/西（旧版西侧花圃 +π/2 正面朝墙里、与同墙藤蔓 −π/2 矛盾，一并修正）。布局 QA 新增"
    "「3e 绿化背贴外皮」断言（背面埋入量 = 0.05、沿墙法线跨度 = 2×半进深），可反向对照。重放实例仍 120/6 组、"
    "构件计数与 blocking 20 不变。"
)
ws2.cell(240, 25).value = (ws2.cell(240, 25).value or "") + ADD_240

# ── 4) 域变更日志 v0.1.9 ──
ws3 = wb["域变更日志"]
V019 = [
    "v0.1.9",
    "2026-09-21",
    "条目修正",
    "关卡场景 / 100F天台",
    (
        "100F 天台装饰布局五次修正两件事：①绿化环贴墙 —— 旧版把花箱/大盆栽/小盆栽压在「离墙中心线 2.15m」"
        "的单一环线上（离外皮 2.00m），而三件半进深只有 0.55~0.87m ⇒ 每件背后空出 1.14~1.45m 可见地砖带"
        "（业主原话「靠墙太远了，要挨着墙放，不然还有个空虚」）；现按每件自身半进深重算：件心离墙中心线 = "
        "SHELL_WALL_T/2 − WALL_MOUNT_EMBED + half_depth，背面埋进外皮 0.05m，南/北/东/西四边各成对、背面齐平。"
        "同时补齐朝向（front_direction=−Y ⇒ yaw 0/π/+π/2/−π/2 朝南/北/东/西），旧版西侧花圃写成 +π/2 正面朝墙里、"
        "与同墙藤蔓 −π/2 矛盾，一并修正。②天台不再生成室内照明设施 —— DungeonRoom3D._build_content() 在 "
        "size_class == \"rooftop\" 时跳过玩法顶灯 RoomCeilingLight 与墙边电灯开关 RoomLightSwitch3D"
        "（此前「清空屋顶设施」只清了家具与可搜容器，漏了照明；业主原话「天台为什么还会刷一个电灯开关」）；"
        "天台是露天甲板、自带室外光照（TowerAtmosphere3D 天光反弹 + 太阳 + 城市背景），两者都是室内残留。"
    ),
    (
        "AssetID / layout_id / layout_version 均不变（原地修正，不新增条目、不新增资产）；重放实例仍 120 / 6 组，"
        "构件计数不变（空调通风口 6 / 绿化 20 / 藤蔓 16 / 女儿墙挂藤 8 / 水管环 54 / 立管与支架 16），"
        "绿化 20 件 blocking 与其余 462 件 visual_only 的策略不变；结构壳体（234 地砖 / 68 件女儿墙 / 楼梯与碰撞）"
        "与玩法数值不变。布局 .blend SHA-256 de1d7ce6… → 7e8b2c51…、清单 .json SHA-256 → 7ba3bb4c…；"
        "账本门禁 check_asset_registry --ledger scenes 维持 46。"
    ),
    "摩斯拉",
]
for c, v in enumerate(V019, start=1):
    cell = ws3.cell(15, c)
    cell.value = v
    src = ws3.cell(14, c)
    if src.has_style:
        cell._style = copy(src._style)

wb.save(P)
print("saved")

# ── 回读校验 ──
wb2 = openpyxl.load_workbook(P, data_only=True)
w = wb2["3D-场景通用"]
left = sum(
    1
    for row in w.iter_rows()
    for cell in row
    if isinstance(cell.value, str) and "99实例" in cell.value
)
print("残留 99实例 单元格:", left)
print("P126 片段:", str(w.cell(126, 16).value)[:130])
print("行146 是否含五次修正:", "五次修正" in str(w.cell(146, 6).value))
m = wb2["资产主表"]
print("row240 SHA:", m.cell(240, 20).value)
print("row240 备注尾:", str(m.cell(240, 25).value)[-60:])
g = wb2["域变更日志"]
print("新日志行:", [str(g.cell(15, c).value)[:40] for c in range(1, 8)])
