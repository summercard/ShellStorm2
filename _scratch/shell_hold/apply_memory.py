# -*- coding: utf-8 -*-
"""写弹壳停留时长事务记忆 + 索引行（均 CRLF）。"""
import os
import sys

MEM_DIR = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-22"
ENTRY = os.path.join(MEM_DIR, "1150_弹壳停留时长加1_5秒.md")
INDEX = os.path.join(MEM_DIR, "_INDEX.md")

NOTE = """# 弹壳停留时长 +1.5 秒（3.2s → 4.7s）

- **时间**：2026-09-22 11:50
- **类型**：观感定档（业主指定，单点常量 + 验收 + 反向对照）
- **涉及**：`src/vfx/VfxShellCasing3D.gd`、`tests/verification/verify_combat_vfx_toon_v002.gd`、
  `docs/v0.1/14.6_特效系统与制作规范.md`（v002.7）、`docs/v0.1/development/CHANGELOG.md`、
  skill `vfx-combat-effect-authoring`（新增 §5.5.5 + 契约表寿命行 + §6 第 11 条 + 排障表两行）
- **账本**：**未改动**（AssetID / Prefab 路径 / 版本 `v001` / PBR `0.8-0.6` / 尺寸 `0.8` 全未动）

## 需求

业主原话：「弹壳的停留时长加 1.5 秒。」

## 结论一：加寿命就是加停留 —— 不要新建「停留参数」

弹壳的可见时长 = `VfxShellCasing3D.DEFAULT_LIFETIME`。飞行 / 弹跳 / 滚动三段的时长由物理常量
（`GRAVITY` / `BOUNCE_RESTITUTION` / `ROLL_DAMPING` …）与初速度决定，**与寿命无关**
⇒ 多出来的时间只能落在 `SETTLED`（落地躺平）之后 ⇒ 诉求等价于 `DEFAULT_LIFETIME: 3.2 → 4.7`。
建独立「停留参数」会与寿命语义重复，还会让两处口径打架。

实测（验收按 `1/60 s` 步进求静止时刻）：`t_settle = 1.15 s`、停留 `4.70 − 1.15 = 3.55 s`
（上一版 `3.20 − 1.15 = 2.05 s`）。

## 结论二：三条互补断言，且必须说清「哪条守什么」

`_check_shell_settled_hold()`（`samples=15 → 16`），期望值全部硬编码在验收侧、**互不派生**：

| # | 断言 | 守住的东西 |
|---|---|---|
| ① | `DEFAULT_LIFETIME == 4.7` | 定档值本身（外部真源，不引用被测常量） |
| ② | `lifetime − 3.2 == 1.5` | **业主诉求本身**（「加了 1.5 秒」） |
| ③ | `lifetime − t_settle ≥ 1.5` | 下限守卫：挡住「飞行段被调长、把这 1.5s 吃掉」 |

⚠️ **③ 不是「+1.5」的钉子**：寿命退回 3.2 时 ③ 仍成立（`2.05 ≥ 1.5`），真正咬住增量的是 ①②。
写这类断言必须**当场说明哪条守什么**，否则下一个人会误以为 ③ 守住了 1.5。
⚠️ 三个期望值**不要写成派生式**（`3.2 + 1.5` 或 `PREV + DELTA`）：派生式会让改坏一处时三处一起跟随
⇒ 自我印证，断言恒绿（与 1136 事务里 PBR 那条反例同源）。
⚠️ 用例必须用**全新实例**：主用例那枚弹壳已被推进到 1.94 s 且早已 `SETTLED`，
复用它会测到 `t_settle` = 第一个步长（恒真），断言直接废掉。

## 结论三：成本必须一起算（池对 active 无上限）

`VfxPool3D.max_per_kind = 32` 只管 **inactive 回收桶**（`retire()` 里桶满才 `queue_free`），
**active 是想借就 `instantiate`、无上限** ⇒ 拉长寿命 = 直接抬高同屏存活弹壳数：

- 射速 `1.0 ~ 12.0 发/s`（`BlueprintRegistry` 全体枪械）× `4.7 s` ⇒ 最坏同屏 ≈ `56` 枚
  （上一版 `12 × 3.2 ≈ 38` 枚，`+47%`）
- 每枚 3 个 `MeshInstance3D`、`288` 三角面（圆柱 48 + 圆环 192 + 球 48）
  ⇒ 约 `16k` 三角面 / 约 `170` 次绘制 ⇒ 仍很便宜，**未做任何池化或上限改动**

## 验收与反向对照

- 复绿：`COMBAT_VFX_TOON_V002_OK samples=16`（0 ERROR，`EXIT=0`）、`VFX_POOL_LIFECYCLE_OK`、
  `SHELL_CASING_VISUAL_OK captured=4 skipped_headless=0`（散布判据 `off_line_residual=0.3729` 仍生效）、
  武器回归 `DUAL_WEAPON_QUICK_MAP_FATE_OK` 全绿。
- **RC8**：`DEFAULT_LIFETIME` 退回 `3.2` ⇒ **精准 3 红**（寿命不是定档值 / 实例寿命未按常量初始化 /
  增量 `0.00 ≠ 1.5`），其余断言全绿、`EXIT=1`；还原后 `EXIT=0` 复绿。
  `grep -rn "REVERSE-CONTROL" src/ tests/` 为空。
- 行尾：`VfxShellCasing3D.gd` 391 行、验收脚本 942 行、两份文档、skill 全部纯 CRLF、零 CRCRLF。

## 踩坑

1. **14.6 版本表锚点写错**：先按「（未随机化时实测仅 `0.0114 m`）」取锚点，实际行文是
   「**，**未随机化时实测仅 …」⇒ 0 命中。长行文档插行前先回读真实结尾片段（别凭记忆拼）。
2. 文档节插入 CHANGELOG 时锚点用「标题 + 首个 `## ` 行名」最稳；新节末尾照原样式补 `<br>`。
"""

IDX_ROW = """| 11:50 | [弹壳停留时长 +1.5 秒（3.2s → 4.7s）](1150_弹壳停留时长加1_5秒.md) | **观感定档（单点常量 + 验收 + 反向对照）** | 业主原话「弹壳的停留时长加 1.5 秒」。**口径**：弹壳可见时长 = `VfxShellCasing3D.DEFAULT_LIFETIME`；飞行 / 弹跳 / 滚动三段由物理常量与初速度决定、**不随寿命变化** ⇒ 加寿命 = 加停留 ⇒ 诉求等价于 `3.2 → 4.7`。`t_settle = 1.15 s`、停留 `3.55 s`（上一版 `2.05 s`）。**三条互补断言**（期望值硬编码、互不派生）：① 寿命 = 4.7；② 增量 = 3.2 + 1.5（**业主诉求本身**）；③ 静止后停留 ≥ 1.5 s（**下限守卫**，退回 3.2 时仍成立 ⇒ 不冒充增量钉子）。用例强制**全新实例**（主用例那枚早已 SETTLED，复用会让 `t_settle` 恒取首步长而废掉）。**RC8**：寿命退回 3.2 ⇒ 精准 3 红、其余全绿、EXIT=1，还原复绿；`grep REVERSE-CONTROL` 为空。**成本如实核算**：`VfxPool3D.max_per_kind` 只管 **inactive 回收桶**、**active 无上限** ⇒ 射速 `1.0~12.0 发/s` × `4.7 s` 最坏同屏 ≈ `56` 枚（上一版 ≈ `38` 枚，+47%），每枚 3 件 / 288 三角面 ⇒ 约 16k 面 / 约 170 次绘制，未改池化。复绿：`COMBAT_VFX_TOON_V002_OK samples=16` / `VFX_POOL_LIFECYCLE_OK` / `SHELL_CASING_VISUAL_OK captured=4` / `DUAL_WEAPON_QUICK_MAP_FATE_OK`。账本**未改动**；14.6 §10 → v002.7；skill `vfx-combat-effect-authoring` 补 §5.5.5 等 5 处。**未提交**。 |"""


def crlf(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\n", "\r\n")


ok = True

blob = crlf(NOTE).encode("utf-8")
if os.path.exists(ENTRY):
    print("FAIL 事务文件已存在（不覆盖）：%s" % ENTRY)
    ok = False
else:
    open(ENTRY, "wb").write(blob)
    print("OK   事务记忆写入 %s (%d bytes)" % (os.path.basename(ENTRY), len(blob)))

data = open(INDEX, "rb").read()
anchor = crlf("| 时间 | 事务 | 类型 | 结论 |\n|---|---|---|---|\n").encode("utf-8")
if data.count(anchor) != 1:
    print("FAIL 索引表头锚点命中 %d 处" % data.count(anchor))
    ok = False
else:
    open(INDEX, "wb").write(data.replace(anchor, anchor + crlf(IDX_ROW + "\n").encode("utf-8")))
    chk = open(INDEX, "rb").read()
    print("OK   索引行插入 crcrlf=%d lone_lf=%d" % (chk.count(b"\r\r\n"), chk.count(b"\n") - chk.count(b"\r\n")))

sys.exit(0 if ok else 1)
