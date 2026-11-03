# 00:5x 提交 + 推送 fbe40346（8 提交 / 253 项，工作区清空）

判据：`HEAD == origin/0.1.2 == fbe40346b2`。推送前一轮 3 个未推提交（special items r4–r6）一并上去。
LFS 无新增大对象。

## 8 个提交（按事务拆，不 `git add -A`）

| 提交 | 内容 |
|---|---|
| `df2d8bd6` | 第二只正式精英「夺械者·收租人」+ 首只真骨骼动画（41 骨/18 剪辑） |
| `1c381e1b` | 世界层三件：安全屋出生点归中 / 退出存档红字 / 默认灯态回归 |
| `130f4a14` | 远征99 boss 前置房点名投放（房间级能力字段 `elite_id`） |
| `e434f864` | 局内商人改复用 99F 贩卖机页面（MerchantUI → 适配器） |
| `bd324d00` | 远征03 场景雾定值 0.02 / 0.0057 + 修好从未生效的覆盖通道 |
| `888241dc` | 收租人行动时间轴 `EliteArmsTakerCombat`（**⚠ 施工中**） |
| `bc7567ba` | 索引/契约/完成度收口 + 内容库 + 三篇事务记忆 |
| `fbe40346` | `tests/rec/` 录制工具与证据入库 + `tests/rec/out/` 设忽略 |

## 这轮最该记住的三件事

### 1. 又一次「文档说改了、代码里没有」

`2026-11-02_expedition03_prop_scale_and_rug_matte.md` 与
`..._lobby_lounge_and_fixture_lighting.md` 都写「已通过
`furnishing.fixed_lobby_clutter_enabled=false` 关闭中央五件」，后者还附实测
`central_fixed_clutter: 0`。**该键全仓不存在**（grep 0 / `git log --all -S` 空 / 各分支全无）。
⇒ 业主一直看得见那五件。判据永远回读代码，不读记录。这已经是**同型第三次**。

### 2. 账本「补了行没刷基线」= 门禁红但账本表面正常

`register_second_elite_ledger.py` 只补《资产主表》行 + 扩公式区间，**不重算
`ledger_split_baseline.json`** ⇒ `verify_ledger_split` 报 `extra_assets:[新ID]`
+ 整片列指纹漂移（看着像账本被改坏，其实只是基线停在 1433 行）。

`scripts/refresh_ledger_baseline_second_elite.py`：按域顺序重算列指纹 + **分页指纹**，
并**逐页打印旧→新 digest**（可审计哪几页被接受）。dry-run 先看 `added/refreshed`：
本次 `added = [ENM-ELITE-ARMS-TAKER-3D]`、`refreshed = []` ⇒ 只有预期的 1 行新增，
没有夹带。顺带把 stale 的 `captured_at`（2026-11-02T17:51:12）纠正 —— 之前两轮都在待办里挂着。

`moved_sheet_mutated` 那类失败也要一起刷 `sheet_digests`，只刷 `column_digests` 不够。
新增页（本轮是 `关卡名称对照`）首次出现时 `from` 为空格，属正常。

### 3. 并发会话的处置口径（本轮又踩三次）

提交途中工作区被另一条会话反复写入：mtime 追到 **00:43**（比我开始提交还晚）、
`EliteArmsTakerCombat` 全新出现、推完立刻又冒出 `verify_second_elite_state_visual`。

口径：
- 每轮重新 `git status` → 重新归类 → 单独成提交；**绝不 `git add -A`**。
- 明确 WIP 的就照实标：`EliteArmsTakerCombat` 的契约文档自己写「施工中」，
  提交标题就写「⚠ 施工中，未验收」，不伪装成完成。
- 提交信息是历史快照。「燃烧瓶半径 2.4」在 `17c5ce64` 里后来被改成 1.25 ——
  **引用数值一律回读 `data/special_items/catalog.json`**。

## ⚠ 已知红项（未擅自处理）

| 门禁 | 状态 | 原因 |
|---|---|---|
| `check_asset_runtime_naming` | **exit 1** | `assets/art/enemies/elite_3d/enm_elite_arms_taker/runtime/enm_elite_arms_taker/` 下 4 个 `.bak_*` 编辑残档。被 `*.bak_*` 忽略规则挡住 ⇒ **不入库**，但门禁扫盘会报「新增备份残留」 |
| `check_verification_registry` | exit 1 | 历史欠账（10-18～11-02 的 5 条 unregistered），本轮新增的都登记了 |
| 资产 `ui_full` 5 / `vfx_full` 7 | exit 1 | 哈希漂移单列待核对，未批量接受 |
| `verify_expedition01_spawn_ramp` 等 | 红 | 远征01 盒数根因，与精英/安全屋改动无关（已核证 `git diff` 为空） |

`.bak_*` 未删：可能另一个会话还在用。**确认那边收工后删掉这 4 个文件即可转绿。**

## 门禁（我独立复跑的）

- `verify_ledger_split` → `LEDGER_SPLIT_VERIFY_OK assets=1434 ledgers=9 failure_count=0`
- `check_level_decoupling` → violations 0
- 房间脚本挂载门禁（30+ tscn）→ `script` / `.gd` ext_resource 计数全部持平
- `godot --check-only` 对 `EliteArmsTakerCombat` **报 class 未声明** ——
  原因是 `.godot/global_script_class_cache.cfg` 停在 00:13、新文件建于 00:37 之后，
  需编辑器重扫。**这不是代码错误的证据**，但也说明我没能验它。

## 未执行

`verify_second_elite_*` / `verify_expedition99_pre_boss_elite` / `verify_expedition_interaction_ui`
/ `verify_expedition03_scene_fog` 全部未在本会话跑过；原生渲染、完整通关、目标设备也未做。
提交信息里引用的读数均标明来源（并发会话日志）。
