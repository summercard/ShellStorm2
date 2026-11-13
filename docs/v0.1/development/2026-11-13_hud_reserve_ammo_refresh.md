# 右下武器栏备弹读数拾取后不更新

- FeatureID：UI-HUD / INVENTORY / WEAPON
- 版本：0.1.0
- 来源：业主报障 —— 主界面右下角「30 · 153备弹」，拾取备弹后数字不动。
- 状态：修复已落地并通过专项 + 反向对照；真实跑图人工确认未做（见「未闭环」）。
- 主契约：[对话与战斗信息呈现设计](../design/对话与战斗信息呈现设计.md)（武器栏只读投影）、[04 技术施工 · 战斗与局内成长](../04_技术施工_战斗与局内成长.md) §6。

## 症状与判定

拾取弹药箱/怪物掉落备弹后，右下角武器栏的 `N备弹` 一直停在拾取前的数字；直到开出下一枪（弹匣变化 ⇒ `ammo_changed`）或切枪才跳到新值。截图现场为 `30 · 153备弹`，实际背包已有更多。

## 根因

备弹是**独立物品** `item_ammo_pack`，拾取走 `RewardSink.apply_ground → InventoryModule.add_item()`，只发 **`inventory_changed`**。

而武器栏那行文本由 `_apply_weapon_hud_command()` 在**写入时刻现算** `_get_reserve_ammo_count()`（主背包 + 快捷栏求和）。这个函数的唯一触发链是：

```
player.ammo_changed → _on_ammo_changed() → _hud_presenter.present_weapon() → weapon_hud_command_ready → _apply_weapon_hud_command()
```

`inventory_changed` 在本文件里只接了 `_refresh_loot_label`（金币读数）与运行存档 `_on_runtime_inventory_changed`（只 `queue_runtime_checkpoint`），**没有任何一条推 HUD 武器栏**。于是「备弹变了但弹匣没变」这一类变化全部漏刷：拾取、丢弃、快捷栏搬移、以及换弹扣备弹（这条被随后的 `ammo_changed` 掩盖了，所以平时看不出来）。

这不是 Presenter 的问题：`HUDPresenter3D.present_weapon()` 每次调用都无条件 `emit`，不缓存去重；缺的是**调用方没被通知**。

## 修法

`Dungeon3D._setup_run_modules()` 里在既有 `_inventory.inventory_changed.connect(_refresh_loot_label)` 之后补两条连线（主背包 + 快捷栏，与 `_get_reserve_ammo_count()` 的求和口径一致）：

```gdscript
_inventory.inventory_changed.connect(_on_reserve_ammo_pool_changed)
_quick_inventory.inventory_changed.connect(_on_reserve_ammo_pool_changed)
```

处理函数只做一件事：

```gdscript
func _on_reserve_ammo_pool_changed() -> void:
	_refresh_hud_weapon_model()   # force=false：只重推投影，不重建 3D 枪械图标
```

三点口径说明：

1. **`force=false` 是有意的。** 拾取不该重建武器图标；`present_weapon()` 在 `instance_id` 不变时 `model_action="keep"`，重建会带来每拾取一次就重配一次 `ItemModelIcon3D` 的无谓开销。
2. **不放进 `_activate_runtime_persistence()`。** 那里 `test_mode` 会整段跳过，HUD 刷新属于表现层、与存档无关，放在 `_setup_run_modules()` 才对所有运行路径生效。
3. **挂在背包信号而不是轮询。** 备弹变化本来就是事件驱动，逐帧算会白白吃开销；`inventory_changed` 只在真正写入时发。

## 验收

官方 runner（`scripts/run_verification_suite.sh scene verify_finite_ammo_flow`）在本机被**既有的** `check_expedition03_room_layouts.py` GBK 编码崩溃挡在 preflight（`UnicodeEncodeError: 'gbk' codec can't encode character '\u2194'`，设置 `PYTHONIOENCODING=utf-8` 亦未生效；与 2026-11-10 散射喷壶那条记录的同名障碍一致，非本轮引入）。故按既有规程改为隔离 `APPDATA`/`LOCALAPPDATA` 直跑场景（`test_mode=true` 由场景自带，用户数据目录在 Autoload 前隔离）：

| 项 | 命令 | 结果 |
|---|---|---|
| 正向 | `godot --headless --path . --scene res://tests/verification/verify_finite_ammo_flow.tscn` | exit 0，`FINITE_AMMO_FLOW_OK`，0 `SCRIPT ERROR` / 0 `ERROR`（仅有既有 UID 回退与 `ObjectDB leaked` 告警，本轮新增 0） |
| 反向对照 | 把 `_on_reserve_ammo_pool_changed()` 临时改成 `pass` 后同命令复跑 | exit 1，精确报 `picking up five reserve rounds did not refresh the weapon HUD: 30 · 0备弹` —— 与报障现场同形，证明门禁会红；对照跑完已删除，生产零残留 |
| 恢复后复跑 | 同上 | exit 0，`FINITE_AMMO_FLOW_OK` |

`verify_finite_ammo_flow` 内新增两条断言（都挂在既有的正样本上，不新建平行用例）：

- `inventory.add_item(ammo, 5)` 之后（= 拾取那一侧的副作用）：`ammo_label.text` 必须 `ends_with("· 5备弹")`。
- 换弹吃掉这 5 发之后：必须 `ends_with("· 0备弹")`（覆盖「消耗侧也走同一条刷新链」，不依赖随后的 `ammo_changed`）。

新增断言的现场文字样例：正向 `30 · 5备弹`，对照 `30 · 0备弹`。

文档门禁：`python3 scripts/check_documentation_contracts.py` → `issues` 11 条，全部为仓库既有断链（`docs/CREATION_PIPELINE_OUTLINE.md`、`CHANGELOG.md` 等），本轮新增断链 **0**。

## 未闭环

- **真实跑图人工确认未做**：无头夹具证明了文本投影链路，不等于玩家视角观感；拾取时的可读性（数字跳变是否够醒目）未看。
- **未做真渲染截图**：本轮不改布局、字号、颜色，只补一条通知链，故未进 `visual` 套件。
- 移动端/手柄输入未涉及。
- 官方 runner 的 GBK 预检崩溃是仓库既有问题，本轮**未**顺手改 `check_expedition03_room_layouts.py`（不在本次授权范围）；需要时可单独立项。
