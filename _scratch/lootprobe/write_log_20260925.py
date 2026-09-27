# -*- coding: utf-8 -*-
"""写 2026-09-25 事务文件 + 追加 _INDEX.md 行（均 CRLF）。"""
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-25"
SLUG = "2340_expedition01_monsters_loot.md"
IDX = os.path.join(MEM, "_INDEX.md")

DOC = """# 23:40 · 远征关卡01 怪物与掉落盘点（+ MEMORY.md 瘦身）

**触发**：主人「查看远征关卡01的怪物和掉落情况，用表格方式给我」。

**类型**：只读盘点 + 文档交付（未改任何代码 / 资产 / 设计源；未提交 git）。

## 交付
- 报告 `ShellStorm2/outputs/expedition01_monsters_loot.html`（表 A–G，199 行表格：编成 / 名册数值 / 掉落规则 / 容器 / 池总览 / 池逐件明细 / 待裁决）。
- 生成器 `ShellStorm2/_scratch/lootprobe/build_expedition01_report.py`；
  池明细 `.../loot_pools_dump.tsv`（`dump_loot.gd` 探针产出，7 池 156 行）；
  运行时探针 `.../probe_expedition_monsters.tscn`（2026-09-22 既有，直接复用）。

## 实测口径（Godot 4.6.3 headless，seed 77001199）
- 主题 `iron_frontier`、`difficulty_rank = 1`（**全项目无任何场景/资源给它赋值**）⇒ `floor = 1`、
  `FLOOR_SCALING[1] = 1.0/1.0`、主题倍率 HP ×0.95 / 伤害 ×0.95 / 速度 ×1.0 ⇒ 怪物名带前缀「边境」。
- **层档按房序线性折算**：`clampi(int(idx / (记录数−1) × 3), 0, 3)`；本关记录 13 条 ⇒ 序列
  `[0,0,0,0,1,1,1,1,2,2,2,2,3]` ⇒ `room_01~03` 吃 `loot_floor_1_2`、`room_04~07` 吃 `loot_floor_3_4`、
  `room_08`/`room_10` 吃 `loot_floor_5`。⚠️ 它跟「越深越难」无关，只是「第几间房」。
- 单只普通怪：**26%** 出 1 件非货币物品（count 恒 1）、**34%** 出 `item_ammo_pack` 3–8 发
  （池里已抽到同一物品则以整包数量覆盖）、魂 = `2 + 1×floor` = **3**。
- 容器池恒为 `scavenge_floor_1`；每房可搜容器 = 房内 prop 的 50%（`size_class=tower_cell` ⇒ 3 个、
  `SCAVENGE`/`STORAGE` **+2** ⇒ 5 个、**Boss 房 = 0**）；开容器发 8 m 声音刺激。
- 编成期望 **≈ 52.5 只**（9 房刷怪 / 12 波；`room_09` 事件不刷、`boss` 房空、`entry`/`extraction` 不刷）。
- 🔴 **Boss 房无 Boss**：设计源未写 `boss_content_id`，而 `BossContentCatalog` 只登记 **95 / 90 / 85**，
  本关 `floor_number = 0` ⇒ `resolve_profile("", 0)` 返回空 ⇒ 运行时「首领房未指派首领 · 区域已放行」、
  **连精英随从也不刷**、`boss_floor_1` 池**永不消费**。
- ⚠️ 设计页 §4.5 把 `melee_chaser` 写成「小菌猪」，代码 `BASE_ENEMY_TYPES` 里是**「小僵尸」**。
- ⚠️ 主题 `enemy_pool` 被设计源架空：9 间房写了 `enemy_spawn_plan` ⇒ 公式路径的池与权重完全不参与。

## 记忆维护（系统提示 MEMORY.md 超注入上限被截断 ⇒ 强制治理）
- 两轮下沉：`MEMORY-playbooks.md` 新增两节 ——
  ① 「下滑自 MEMORY.md（2026-09-25 瘦身）」：导出包实测三结论 / 墙件换件两个必查 / 行尾转换的静默坑 /
  排查三坑 / 远征01 墙面裁定证据链 / 远征01 怪物与掉落口径；
  ② 「远景城市 / 99F 主灯 / 输入细则」。
- `MEMORY.md` 16.6 KB → 14.4 KB，长条目一律压成「结论 + 指针」。
- ⚠️ **观测到并发写入迹象**（两轮之间两文件合计字节差 −532）⇒ 未做全量覆盖式重写，只用「读 → 精确替换 → 写回」，
  任一 old 未命中即退出不写盘。两文件行尾已校验：纯 CRLF、`loneLF = 0`、`crcr = 0`。

## 待裁决
1. Boss 房是否指派首领（影响 `boss_floor_1` 是否有消费点）；
2. 设计页 `melee_chaser` 名称订正（「小菌猪」→「小僵尸」）。

## 未做
未改代码 / 资产 / 设计源；未 `git add`、未提交；`_scratch/lootprobe/` 新增 3 个草稿文件与 1 份 TSV 仍在工作区。
"""

ROW = ("| 23:40 | [远征关卡01 怪物与掉落盘点（+ MEMORY.md 瘦身）](2340_expedition01_monsters_loot.md) "
       "| **只读盘点 + 文档交付（未改代码/资产/设计源，未提交）** "
       "| 主人「查看远征关卡01的怪物和掉落情况，用表格方式」。产出 "
       "`ShellStorm2/outputs/expedition01_monsters_loot.html`（表 A–G / 199 行表格）。**实测（Godot 4.6.3 headless，seed 77001199）**："
       "主题 `iron_frontier`、`difficulty_rank = 1`（**全项目无赋值处**）⇒ floor=1、HP×0.95/伤害×0.95/速度×1.0；"
       "**层档按房序折算** `clampi(int(idx/(n−1)×3),0,3)`，n=13 ⇒ `room_01~03` 吃 `loot_floor_1_2`、`room_04~07` 吃 `loot_floor_3_4`、"
       "`room_08`/`room_10` 吃 `loot_floor_5`（与「越深越难」无关，只是第几间房）；单只普通怪 26% 掉 1 件 / 34% 掉弹药 3–8 / 魂 = 2+floor = 3；"
       "容器池恒 `scavenge_floor_1`，可搜容器 = prop 的 50%（tower_cell 3、SCAVENGE/STORAGE +2、**Boss 房 0**）；编成期望 ≈ 52.5 只。"
       "🔴 **Boss 房无 Boss**：`BossContentCatalog` 只登记 95/90/85，本关 `floor_number=0` ⇒ 空房放行、连精英随从也不刷、`boss_floor_1` 永不消费。"
       "⚠️ 设计页 §4.5 写 `melee_chaser`=「小菌猪」而代码是「小僵尸」；⚠️ 主题 `enemy_pool` 被设计源架空（9 房有 `enemy_spawn_plan`）。"
       "**记忆维护**：MEMORY.md 超注入上限被截断 ⇒ 两轮下沉到 playbooks 两节（导出包三结论 / 墙件换件两个必查 / 行尾静默坑 / 排查三坑 / 墙面裁定证据链 / 远征01 怪物掉落口径 / 远景城市·99F 主灯·输入细则），"
       "MEMORY.md 16.6KB → 14.4KB 全部留指针；⚠️ 观测到并发写入迹象（两轮间合计字节 −532）⇒ 未做全量覆盖。**待裁决**：Boss 房是否指派首领、设计页怪名订正。 |")


def read_lf(path):
    return open(path, "rb").read().decode("utf-8").replace("\r\n", "\n")


def write_crlf(path, text):
    data = text.replace("\n", "\r\n").encode("utf-8")
    open(path, "wb").write(data)
    return data


# 1) 事务文件（不存在才写，避免覆盖并发同名文件）
dst = os.path.join(MEM, SLUG)
if os.path.exists(dst):
    print("!! 事务文件已存在，未写：", dst)
    raise SystemExit(1)
d1 = write_crlf(dst, DOC)
print("事务文件 %s size=%d crlf=%d loneLF=%d" % (
    SLUG, len(d1), d1.count(b"\r\n"), d1.count(b"\n") - d1.count(b"\r\n")))

# 2) 追加索引行
idx = read_lf(IDX)
if "2340_expedition01_monsters_loot.md" in idx:
    print("!! 索引已含本行，跳过")
else:
    if not idx.endswith("\n"):
        idx += "\n"
    idx += ROW + "\n"
    d2 = write_crlf(IDX, idx)
    print("_INDEX.md size=%d crlf=%d loneLF=%d crcr=%d" % (
        len(d2), d2.count(b"\r\n"), d2.count(b"\n") - d2.count(b"\r\n"), d2.count(b"\r\r")))
