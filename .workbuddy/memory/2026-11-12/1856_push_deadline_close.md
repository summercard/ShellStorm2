# 1856 推送：遭遇截止关闭 + 精英读条期预置 + 三关复测

## 业主口述

> 「tuisong」

## 事实链

- 接手时 **`HEAD == origin/0.2`，零待推送提交** —— 又一次是每日自动提交把前一批推走的。
  这已是连续第二轮出现「说推送但其实没东西可推」。
- 工作区压着 30 项未提交改动（帧优化事务的续篇），提交成 `5804e5fe` 再推：
  `97096d5d..5804e5fe`，**30 文件 / +1499 −255**。
- 最后写入时间 17:12，接手时 18:53 —— 1 小时 40 分无变动、零 Godot 进程 ⇒ 无并发会话。

## 本批内容

| # | 块 | 关键点 |
|---|---|---|
| ① | 截止行为 | `deadline_behavior`：`fail_if_uncleared`（缺省不变）/ `close_dispatch_and_clear`；Host 新增 `encounter_event_close_dispatch()` 只撤未实到预约；`repeat_last_stage` 允许清批后重复末波 |
| ② | 精英读条期预置 | `EnemyAvatar3D.instantiate_elite_visual()` + `configure_elite_content(..., prepared)`；读条期收集游荡规则与点名精英、按正式场景去重 |
| ③ | 远征01 五限时房 | `deadline_behavior` + `repeat_last_stage=true` + `start_delay_sec=2`；`LevelPlanValidator` 跟进 |
| ④ | 存档原子性 | `AtomicJsonStore` / `ProfileSaveService` / `BaseManager` 小幅对齐 |
| ⑤ | 三关复测 | 同种子 41021；01 读条 66.3s / 02 15.6s / 03 53.0s；03 首次 n05 长帧 1218.7 ms（同步回调仅 19.0 ms） |
| ⑥ | 探针修正 | 独立飞行探针原按平静路线标定，战斗路线连续 3 次漏记；改按正式玩家发射上下文指定敌我/目标组/掩码 |

## 语义澄清（已写回设计，别记错）

- `duration_sec` 正数 = 总时间窗口，**不是准备时长**；有限无截止组合可写 0
- `start_delay_sec` = 首批派发门槛，**≠ `preparation_sec`**；远征01 五个限时房均为 2 秒且计入 60 秒总窗口
- `light_on_finish` = 事件完成时开灯，**≠ 截止瞬间开灯**

## 门禁

| 门禁 | 结果 |
|---|---|
| `check_verification_registry` | **OK scenes=306** |
| `check_level_decoupling` | violations **0** |
| `check_asset_runtime_naming` | **OK** 289/13 未增 |
| `sync_runtime_design_data --check` | 52 文件 **0 问题** |
| `check_documentation_contracts` | 11 条断链，全部既有，新增 0 |
| `verify_ledger_split` | 红 **109**（未变） |

## 遗留（连续两轮挂着）

`assets/ui/fonts/dseg/` 两个 ttf **缺 .import**，`.godot/imported/` 只有 `.fontdata*.tmp`。
`EncounterCountdownRing` 有 `assert(font_error == OK)`，导入完成前必失败。
⇒ **验收计时环之前，必须先在编辑器里确认字体导入成功。** 这条不修，DSEG 换字体等于没验。

三个垃圾文件仍在：`_probe_loop.txt`、`override.cfg.disabled_20261109`、
`verify_main_story_boss_gate.report.json`。已第五轮手动排除，建议加 `.gitignore`。
