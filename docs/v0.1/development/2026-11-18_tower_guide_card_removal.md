# 塔楼左侧引导卡撤除：只留基地金币读数并挪到电芯下方

- 日期：2026-11-18；工程版本 0.1.0。
- FeatureID：`UI-HUD`。
- 来源：业主截图标注「帮我把这些内容去掉，没有用，只保留金币的数量 然后挪到电池下面」。
  截图红框圈住左上角 `99F / 恢复状态、补充物资… / I·Tab 背包·Esc 暂停 / 金币：◈ 2209` 四行，
  箭头指向血条与电芯行，即要求把这四行缩成一行金币、并把它放到电芯正下方。
- 主设计：[UI与UX全局设计及全界面清单 §UI-07](../design/UI与UX全局设计及全界面清单.md)、
  [UI风格规范_棱镜线框](../design/UI风格规范_棱镜线框.md)。
- 状态：**代码与文档完成，headless 结构探针通过**；同目录 `verify_reference_hud_fate_visual`
  的完整运行（含真渲染出图）未执行，见 §4。不提高 `UI-HUD` 的 partial。

## 1. 改动前的结构

`TowerDescent3D._install_tower_hud()` 用代码现搭一个 `MarginContainer "TowerCurrentInfoHUD"`，
绝对锚定 `(14, 176)`、盒 `264×118`，内部是 `VBoxContainer` + 四个 Label：

| 行 | 字段 | 内容来源 |
|---|---|---|
| 1 | `_tower_floor_label` | `_current_floor_number()` → `99F` / `楼顶 · 100F` |
| 2 | `_tower_target_label` | `_journey_objective(floor)` / `_expedition_objective()` |
| 3 | `_tower_elevator_label` | 按楼层三档硬编码的按键提示 |
| 4 | `_tower_base_currency_label` | `BaseManager.get_extraction_points()` |

四行文字全部来自 `if floor == 99 / >= 100 / room_type == …` 的字符串分支，没有数据驱动的任务系统。

## 2. 改动

### 2.1 `src/world3d/Dungeon3D.gd`（只加一个挂点，不改布局数值）

- `PlayerStatusBlock` 内的状态列 `stat_vbox` 原本是局部变量，外部无法安全插入子节点
  （按节点路径取的是无名 `VBoxContainer`，不稳）。本轮命名 `PlayerStatColumn`
  并存为成员 `_hud_stat_column`，供子类在血条 → 电芯之后追加读数。
- **没有**改动 `PlayerStatusBlock` 的锚框 `(18, 44)…(358, 174)`、`stat_vbox` 的
  `alignment = CENTER` 与 `separation = 6`。

### 2.2 `src/world3d/TowerDescent3D.gd`

1. `_install_tower_hud()` 重写：不再建 `MarginContainer` / `PanelContainer` / 四行 VBox，
   只建一个 `Label "TowerBaseCurrencyHUD"`（`prism` 语义 `warn`、13px、字距 2、5px 黑描边），
   `add_child` 到 `_hud_stat_column` —— 由容器排在 `FlashlightBatteryPanel` 正下方。
   没有 2px 引导竖线、没有背板（那条竖线随引导卡一起撤除）。
2. 删除成员 `_tower_floor_label` / `_tower_target_label` / `_tower_elevator_label`；
   `_refresh_tower_hud()` 收敛为一句金币写入，楼层/目标/按键三段赋值全部删除。
3. `_announce_floor_arrival()` 的「HUD 是否已装好」哨兵由 `_tower_floor_label == null`
   改为 `_tower_base_currency_label == null`（同一安装函数产出，语义等价）。
4. 删除 `_expedition_objective()` —— 唯一调用点已随引导卡消失，属纯死代码。
   **保留** `_journey_objective()`：它仍被 `verify_tower_journey_polish` 与
   `verify_opening_script_runtime` 直接调用做回归，且是本层目标规则的唯一表述；
   函数头已注明「不再渲染到 HUD，将来接任务系统从这里取值」。

### 2.3 楼层读数没有丢失

右上 `_hud_floor_label`（`高塔外层 · 99F`）仍是楼层读数的唯一出口，截图右上角本来就有一份；
引导卡第 1 行属重复信息。业主撤除它不影响「玩家是否知道自己在几层」。

## 3. 金币语义（改前改后未变）

| 读数 | 数据源 | 生命周期 |
|---|---|---|
| 左上 `金币：◈ N`（本轮位置） | `BaseManager.get_extraction_points()` | 基地持久金币，撤离后入库、跨局存在 |
| 右下 `金币 N`（`RunLootReadout`） | `Dungeon3D._run_value` | 本局局内金币，未撤离即归零 |

两个账户共用「金币」二字但不同真源，改版后依然分居左上/右下，未合并。

## 4. 验收

| 编号 | 项目 | 隔离 | 结果 | 退出码 |
|---|---|---|---|---|
| P1 | 临时结构探针 `_scratch/_probe_tower_currency_hud.tscn`（`TowerDescent3D.tscn` + `test_mode`，12 帧后取节点） | `APPDATA`/`LOCALAPPDATA` 指向 `.workbuddy/tmp/appdata_probe` | **通过**：`GUIDE_REMOVED=true`、`CURRENCY_FOUND=true`、`CURRENCY_TEXT=金币：◈ 0`、`CURRENCY_PARENT=PlayerStatColumn`、`CURRENCY_Y=99.2 BATTERY_END_Y=94.6`、`BELOW_BATTERY=true`、`HAS_PROGRESSBAR=false`、`PROBE_DONE` | exit 0 |
| P2 | `godot --headless --check-only --script res://src/world3d/TowerDescent3D.gd` | 同上 | **无语法错误**；输出中的 `Identifier not found: DialogueUI / NarrativeDirector / AudioManager` 是 `--check-only` 不带 Autoload 的既有预期故障，与本次改动无关（改前同样存在） | exit 0 |
| G1 | `python scripts/check_level_decoupling.py` | — | 7 个通用机制容器，`violations 0` | exit 0 |
| G2 | `python scripts/check_asset_runtime_naming.py` | — | `ASSET_RUNTIME_NAMING_OK`，欠账 289/13/0，无新增（本轮未动资产） | exit 0 |
| D1 | `python scripts/check_documentation_contracts.py`（改文档前基线） | — | 615 文档 / 3325 链接 / **15 issue**（14 条既有断链 + `verify_fat_zombie21_gait` 未登记） | exit 1（既有） |
| D2 | 同上（本轮文档改完） | — | 617 文档 / 3329 链接 / **15 issue，与 D1 逐条同集合、新增 0**（本轮新增的 4 处链接：设计页 §UI-07、风格规范、`development/README.md`、`MODULE_INDEX.md`，均不在 issue 列表内） | exit 1（同上既有集合） |

**未执行**：
- `tests/verification/verify_reference_hud_fate_visual` 完整运行 —— 该用例含 Forward+ 真渲染出图，
  headless 不能代替。其塔楼段断言已按新结构改写（见 §5），需在有真实渲染器的窗口里跑。
- 手动游玩与 720p/1080p 实机目视。**血条与电芯格因状态列居中会整体下移约 10 canvas px**，
  这个位移只有真实窗口能最终确认观感，headless 只证明了相对位置正确。
- Android / 移动端。

## 5. 测试同步（`tests/verification/verify_reference_hud_fate_visual.gd`）

原塔楼段断言「`HUD/TowerCurrentInfoHUD` 存在且在 `PlayerStatusBlock` 下方 20px 以上」，
该节点已不存在，会直接变红。改为四条：

1. `HUD/TowerCurrentInfoHUD` **不存在**（引导卡已撤）；
2. `TowerBaseCurrencyHUD` 存在；
3. 其 `global_position.y >= FlashlightBatteryPanel.get_global_rect().end.y`（在电芯下方）；
4. 该读数行内部不含 `ProgressBar`（沿用旧断言，防止重复灰血条回流）。

## 6. 回滚

单文件回滚即可：`TowerDescent3D._install_tower_hud()` 恢复四行 VBox 与 `(14, 176)` 锚框、
`_refresh_tower_hud()` 恢复三段赋值、`_announce_floor_arrival()` 哨兵换回 `_tower_floor_label`、
补回 `_expedition_objective()`；`Dungeon3D` 的 `_hud_stat_column` 可留（无副作用）。
测试与本文件 §5 同步回退。
