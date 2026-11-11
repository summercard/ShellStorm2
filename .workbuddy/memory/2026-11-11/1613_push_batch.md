# 1613 提交并推送：宝箱聚光灯 + 遭遇准备期/HUD + 远征01 数据

## 业主口述

> 「提交和推送」

## 提交

`bc5b890a` — 0.2 收口三条并行事务，**62 文件 / +1947 行**（`git diff --stat` 口径 35 文件有余，
实际含新增 23 个）。三条事务都不是我这个会话写的，我只做收口与门禁。

| # | 事务 | 主要落点 |
|---|---|---|
| ① | 宝箱聚光灯出现动画 | `chest_spotlight_beam.gdshader`（新）、`TreasureChest3D` 0.42s SINE EASE_OUT 时间轴、`verify_chest_appear_fx_prompt`、道具账本两行备注 |
| ② | 门入口条带 / 准备期 / 远端涌入 / 警报 HUD | `触发器刷怪设计 §3.3.7`、`EncounterEventDirector3D`、`EncounterAlertOverlay`（新）、`EncounterCountdownRing` 改纯消费快照、5 个新验收 |
| ③ | 远征01 十三房数据与心流 | `data/level_plans/expedition_01/*`、`LevelPlanValidator`、`SecretBranch3D`、`远征01 §12 心流曲线` |

跨事务：`VfxPool3D.COMBAT_PREWARM` 加 `FX01_TELEPORT_IN`、`BaseManager._read_validated_profile()`。

## 补登的那一件（唯一红项）

`check_verification_registry` 报 `unregistered: verify_encounter_preparation_hud_integration`。

**关键**：这个门禁读的是 `scripts/run_verification_suite.sh` 里 `core_scenes` 等 5 个数组，
**不读 `feature_registry.json`** —— 我第一次只改了 registry，门禁照样红。两处都要。

- `run_verification_suite.sh`：加进 `core_scenes`（紧邻 `verify_encounter_trigger_room_flow`）；
- `feature_registry.json` → `ENCOUNTER-EVENT.verification`：补 `kind=scene` + `suite=core` + `requires`。

跑过确认：`ENCOUNTER_ALERT_CONFIG_INTEGRATION_OK checks=19 failures=0`（exit 0）。
**坑**：该测试硬断言 `APPDATA` 含 `shellstorm-verification.`，直接跑会 exit 1 报「必须启动前隔离userdata」。

## 账本门禁：红 228，且**这次刷不动**

- `failure_count 227 → 228`：HEAD 已是 227。R 列 `==LOWER(...)`（双等号）、S 列数组公式，
  xlsx 被外部编辑器重存所致。道具账本两行 col25 备注变更（已核对：只有这 2 格变了）使它 +1。
- `baseline 1445 / union 1447 / extra 2`：两只奖励宝箱（`PRP-3D-REWARD-CHEST-ADVANCED/NORMAL`）
  在账本里、基线里没有。
- **`split_asset_ledger.py --baseline-only` 现在跑不了**：报
  「`ShellStorm2_美术资产台账_v001.xlsx` 没有《资产主表》表，无法作为基线来源」——
  拆分后主账本已不带该 sheet，刷新路径已坏死，不是加个参数能绕。
  ⇒ 基线刷不动，只能从写入端重建。没改门禁、没批接受账本。

## 门禁读数

| 门禁 | 结果 |
|---|---|
| `check_verification_registry` | **OK scenes=305**（core 245 / visual 42 / smoke 6 / manual 12） |
| `check_level_decoupling` | violations **0** |
| `check_asset_runtime_naming` | **OK**，289/13 未增 |
| `sync_runtime_design_data --check` | 52 文件 **0 问题** |
| `check_documentation_contracts` | 11 条断链，**全部既有**（本轮新增 0） |
| `verify_ledger_split` | **红 228**（见上，HEAD 存量） |

## 未提交

`_probe_loop.txt`（0 字节）、`override.cfg.disabled_20261109`、`verify_main_story_boss_gate.report.json`
—— 都是产物垃圾，没跟踪、没 `.gitignore`，删了不影响构建。

## 一条观察

三条事务里②（遭遇准备期）**没有开发记录**：`docs/v0.1/development/` 下没有对应文件，
设计 §3.3.7 已写、代码已落、验收也有，但 AGENTS.md 要求的独立开发记录缺。
我没代写 —— 这个功能面太大（6 个机制交叉：封门/准备/冻结/远端涌入/警报/恢复），
凭 diff 反推记录只会得到一份假的精确。留给原会话或在下一轮正式补。
