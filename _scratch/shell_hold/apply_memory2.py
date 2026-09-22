# -*- coding: utf-8 -*-
"""写「弹壳停留时长再缩短 1 秒」事务记忆 + 索引行（均 CRLF）。"""
import os
import sys

MEM_DIR = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-22"
ENTRY = os.path.join(MEM_DIR, "1543_弹壳停留时长再缩短1秒.md")
INDEX = os.path.join(MEM_DIR, "_INDEX.md")

NOTE = """# 弹壳停留时长再缩短 1 秒（4.7s → 3.7s）

- **时间**：2026-09-22 15:43
- **类型**：观感定档回调（业主指定，单点常量 + 验收结构修正 + 反向对照）
- **涉及**：`src/vfx/VfxShellCasing3D.gd`、`tests/verification/verify_combat_vfx_toon_v002.gd`、
  `docs/v0.1/14.6_特效系统与制作规范.md`（v002.8）、`docs/v0.1/development/CHANGELOG.md`、
  skill `vfx-combat-effect-authoring`（§5.5.5 全文重写 + 契约表寿命行 + 排障表 3 行）
- **账本**：**未改动**（AssetID / Prefab / 版本 `v001` / PBR / 尺寸全未动）

## 需求

业主原话：「弹壳的停留时长加缩短 1 秒。」—— 句里「加」「缩短」两个动词并存（前一轮是「加 1.5 秒」，
疑为「再缩短」的笔误）。**按「再缩短 1 秒」执行**：`DEFAULT_LIFETIME: 4.7 → 3.7`。
（若主人本意是「再加 1 秒」= 5.7，只需把常量与三个期望值同向翻一次，成本约 1 分钟。）

## 结论一：两轮定档的沿革要写进源码注释，不能只留最后一个数

`3.2 →（+1.5）4.7 →（−1.0）**3.7**`。只写 `3.7` 会让下一个人看不懂「为什么不是整数 3.7」。
实测：`t_settle = 1.15 s` 恒定 ⇒ 停留 `2.55 s`（4.7 时 `3.55 s`）。

## 结论二（本轮最值钱）：把「增量」与「观感下限」拆成两个常量

v002.7 的写法：`_expect(hold >= EXPECTED_SHELL_SETTLED_HOLD_DELTA)` —— 用「本轮加了几秒」这个
**增量常量**去当**下限门槛**。第一轮两者数值恰好都是 `1.5`，看不出问题；本轮增量改成 `1.0` 后
判据立刻退化成 `hold ≥ 1.0`（弹壳静止后停留恒 ≥ 1.0）⇒ **废判据**。

正确结构（四个常量、各自独立、互不派生）：

| # | 断言 | 常量 | 守什么 |
|---|---|---|---|
| ① | 寿命 == 定档值 | `EXPECTED_SHELL_LIFETIME := 3.7` | 定档值本身 |
| ② | 上一版 − 寿命 == 缩短量 | `PREVIOUS := 4.7` / `DWELL_SHORTEN := 1.0` | **业主诉求本身** |
| ③ | 寿命 − t_settle ≥ 观感下限 | `EXPECTED_SHELL_HOLD_FLOOR := 1.5` | **下限守卫**（飞行段吃满寿命） |
| ④ | 必须测到静止时刻 | —（哨兵） | 防 ③ 拿 −1.0 恒真 |

**通法**：定档值 / 本轮增减量 / 观感下限 = 三个独立常量；换方向（加 ↔ 缩短）时 ② 的减号语义
要**同步翻**，不能只改数字。

## 结论三：「下限 / 守卫」类断言的反向对照必须造「触碰下限」的场景

第一轮只做了「改回上一版寿命」那组对照 ⇒ ③ 恒绿（4.7 下停留更长），**等于没测到它**。
本轮补 **RC9b**：把 `ROLL_DAMPING: 3.4 → 0.2` 让滚动迟迟不收敛 ⇒ `t_settle = 2.47 s`、
`hold = 1.23 s` ⇒ ③ 精确命中。

## 反向对照（两组都精准变红后还原，`grep -rn "REVERSE-CONTROL" src/ tests/` 为空）

- **RC9**（寿命退回 4.7）：精准 **3 红** —— `寿命不是定档值 3.70：4.700`、
  `实例寿命未按 DEFAULT_LIFETIME 初始化：4.700`、`停留缩短量不是 1.0s：上一版 4.70 − 寿命 4.70 = 0.00`；
  其余全绿、`EXIT=1`。还原后 `EXIT=0`。
- **RC9b**（`ROLL_DAMPING 3.4 → 0.2`）：③ 精确命中
  `弹壳落地静止后停留只有 1.23s（观感下限 1.5s）：t_settle=2.47 lifetime=3.70`。

## 成本（随寿命下降）

`12.0 发/s × 3.7 s ≈ 44` 枚同屏（4.7 s 时 ≈ 56 枚；3.2 s 时 ≈ 38 枚），
约 `13k` 三角面 / 约 `130` 次绘制。池对 active 无上限（`max_per_kind` 只管 inactive 桶），未改池化。

## 验证

`COMBAT_VFX_TOON_V002_OK (samples=16)` + 0 ERROR（抽样 `lifetime=3.70 settle_at=1.15 hold=2.55`）、
`VFX_POOL_LIFECYCLE_OK`、`SHELL_CASING_VISUAL_OK captured=4 skipped_headless=0`
（四机位重出图，散布判据 `off_line_residual=0.3393`）。
行尾：`.gd` 395 行 / 验收 955 行 / 两份文档 / skill 全部纯 CRLF、零 CRCRLF。

## 踩坑与并发发现

1. **文档锚点两处连撞**：① CHANGELOG 顶部已被**并发会话**插了「右摇杆瞄准手感重做」新节 ⇒
   不能再按「文档头 + 旧首节标题」取锚点，要**先回读真实首节标题**；
   ② 14.6 版本表末行紧接 `---`（**无空行**），锚点写成 `…|\\n\\n---\\n` 就 0 命中。
   ⇒ 插行前必须回读目标行尾原文，别凭记忆拼锚点。
2. ⚠️ **并发会话在 res:// 内留了脚本快照 ⇒ 全局类名抢注（P0，非本次改动所致）**：
   `ShellStorm2/_scratch/gamepad_submenu/baseline_bak/`（文件时间 14:30~14:44）含
   `Player3D.gd` / `PauseMenu3D.gd` / `GamepadInput.gd` / `InputSettingsManager.gd` + `.uid`，
   Godot 的 `.godot/global_script_class_cache.cfg` 已把 **`class Player3D` / `class PauseMenu3D`
   映射到这两份 _scratch 副本**（`src/player3d/Player3D.gd` 反而从缓存里消失）
   ⇒ 跑武器回归时报 `Parse Error: Class "Player3D" hides a global script class` +
   `Failed to load script "res://src/player3d/Player3D.gd"` ⇒ `verify_dual_weapon_quick_map_fate_flow`
   `EXIT=1`。**取证**：`git status --porcelain -- src/player3d src/ui src/core` 显示我只改了
   `src/vfx/VfxShellCasing3D.gd`（player/ui 的 `M` 是那个会话自己的改动）；该类名映射与一个 VFX
   寿命常量无因果关系。**未触碰对方文件**，按纪律只报告。修法（一句话）：
   把 `ShellStorm2/_scratch/gamepad_submenu/` 整体移到 res:// 之外（如
   `I:\\工作项目\\shellstrom2\\_scratch\\`）+ 删掉 `.godot/global_script_class_cache.cfg` 让它重建。
   ⇒ 复现了 MEMORY 里「脚本快照禁落 res:// 内（`class_name` 抢注 + class cache 被旧副本覆盖）」这条硬规则。
3. 本轮 `baseline_bak` 里连 `.uid` 都在 ⇒ Godot **真的把它们当项目脚本导入了**。
   光把后缀改成 `.txt` 不够，必须移出 res://。
"""

IDX_ROW = """| 15:43 | [弹壳停留时长再缩短 1 秒（4.7s → 3.7s）](1543_弹壳停留时长再缩短1秒.md) | **观感定档回调（单点常量 + 验收结构修正 + 反向对照）** | 业主原话「弹壳的停留时长加缩短 1 秒」（两动词并存，疑「再缩短」笔误）⇒ 按**再缩短 1 秒**执行：`VfxShellCasing3D.DEFAULT_LIFETIME: 4.7 → 3.7`，累计 `3.2 →（+1.5）4.7 →（−1.0）3.7`；`t_settle = 1.15 s` 恒定 ⇒ 停留 `2.55 s`。**本轮最值钱的修正**：v002.7 把行为断言 `hold ≥ 1.5` 写在了**增量常量**上（数值偶合、语义错位），增量改成 `1.0` 后立刻退化成废判据 ⇒ 拆为四个独立常量（定档值 ① / 本轮缩短量 ② / **观感下限 `EXPECTED_SHELL_HOLD_FLOOR := 1.5`** ③ / 静止时刻哨兵 ④），注释逐条写明各守什么；换方向时 ② 的减号语义要同步翻。**反向对照两组**：RC9 寿命退回 4.7 ⇒ 精准 3 红（其余全绿、EXIT=1）；**RC9b** `ROLL_DAMPING 3.4 → 0.2` 让飞行段吃满寿命 ⇒ ③ 精确命中 `停留只有 1.23s（观感下限 1.5s）：t_settle=2.47` —— **只跑 RC9 时 ③ 恒绿，等于没测到** ⇒ 「下限/守卫」类断言的反向对照必须造**触碰下限**的场景。复绿：`COMBAT_VFX_TOON_V002_OK samples=16`（`hold=2.55`）/ `VFX_POOL_LIFECYCLE_OK` / `SHELL_CASING_VISUAL_OK captured=4`（`off_line_residual=0.3393`）。成本：`12.0 发/s × 3.7 s ≈ 44` 枚同屏（4.7 时 ≈ 56），约 13k 面 / 约 130 绘制。账本**未改动**；14.6 §10 → v002.8；skill §5.5.5 全文重写。⚠️ **并发会话 P0 发现（非本次改动）**：`ShellStorm2/_scratch/gamepad_submenu/baseline_bak/`（14:30~14:44）在 **res:// 内**留了 `Player3D.gd` / `PauseMenu3D.gd` 等快照 + `.uid`，`.godot/global_script_class_cache.cfg` 已把 `class Player3D` / `class PauseMenu3D` 映射到这两份副本 ⇒ 武器回归 `verify_dual_weapon_quick_map_fate_flow` 报 `Class "Player3D" hides a global script class` + `EXIT=1`；已取证与本次改动无因果（`git status -- src/player3d src/ui src/core` 显示我只改了 `src/vfx/`），**未触碰对方文件**，建议把该目录整体移出 res:// 并让 class cache 重建。**未提交**。 |"""


def crlf(t: str) -> str:
    return t.replace("\r\n", "\n").replace("\n", "\r\n")


ok = True
blob = crlf(NOTE).encode("utf-8")
if os.path.exists(ENTRY):
    print("FAIL 事务文件已存在（不覆盖）：%s" % ENTRY)
    ok = False
else:
    open(ENTRY, "wb").write(blob)
    print("OK   事务记忆 %s (%d bytes)" % (os.path.basename(ENTRY), len(blob)))

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
