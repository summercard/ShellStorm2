# 子弹模块（弹种挂件）可装备化 + 装备界面弹药显示

- 日期：2026-10-17
- 类型：可用性修复（装备入口 / 装备界面信息）
- 关联上一条：`2026-10-17_starter_rifle_sticky_dot_fix.md`（初始步枪误挂黏黏弹）

## 玩家反馈的问题

「弹种挂件在游戏里是不是没有玩家可以装备的入口？」

答案是**有，但只有一条隐蔽入口，而且界面在骗人**：

| 原有入口 | 实现 | 玩家能不能发现 |
|---|---|---|
| 背包左键子弹模块 | `Dungeon3D._on_inventory_item_clicked` → `type=="module"` | 不能：悬浮卡写的是「拖拽：换位或丢弃到地面」 |
| 拖到武器格 | **不存在**：`ItemSlot._can_drop_data` 只接受 `type=="weapon"` | 拖一次失败就再也不会试 |
| 改造台 | `WorkbenchPanel._populate_bullet_options` 按蓝图 tier 全量列出 | 白给，不消耗物品 ⇒ 与地面掉落的模块物品是两套体系 |

## 本次改动

### 1. 入口补齐（三条）

- **背包左键**：子弹模块改走专用事务 `Dungeon3D._install_bullet_module_from_inventory`
  → `Player3D.install_bullet_module_to_weapon_slot`（写武器实例、旧模块回背包、运行态刷新）。
  原先走 `_install_weapon_module_from_item`，只改活树、不落实例，切枪/入包会丢。
- **拖到主武器格 / 副武器格**：`ItemSlot._can_drop_data` 与 `set_drag_feedback` 接受
  `type=="module" && subtype=="bullet"`；`InventoryUI._on_slot_drop_received` 的
  `weapon_0/weapon_1` 分支发出新信号 `bullet_module_install_requested`，由
  `Dungeon3D` / `TrainingRange3D` 各自接（局内走背包事务，靶场只改内存）。
- **配件不被误吃**：武器格仍然拒绝 `type=="attachment"`（由新增断言钉住）。

### 2. 装备界面显示当前弹药（业主本次追加要求）

`InventoryUI` 的每把武器下面新增一行「弹药」：

- 只读小格（`slot_kind = "bullet_display_N"`，`drag_disabled = true`）显示模块图标；
- 右侧竖排「弹药 / 模块名」，空态为灰色「未装填」；
- 数据源是新增的 `Player3D.get_equipped_bullet_item_for_slot(slot_index)`，
  内部读 `WeaponInstance.get_presentation_snapshot()` 新增的 `bullet_module` 字段
  （弹药槽不在 `PUBLIC_ATTACHMENT_SLOTS` 里，不能混进「配件」列表）；
- 活动槽读运行树、备用槽读实例快照，与配件布局同源，换弹/切枪都会立刻刷新
  （实例变化 → `weapon_instance_changed` → `_refresh_equipment_ui`）。

### 3. 悬浮卡文案

`InventoryUI._bullet_module_hover_text()`：显示「命中伤害 +N · 弹速 ×X」、
左键装配、可拖到主/副武器格。不再落到通用分支的「丢弃到地面」。

## 验收

新增 `tests/verification/verify_bullet_module_equipment_flow.tscn`（已登记进
`scripts/run_verification_suite.sh`），判据 `BULLET_MODULE_EQUIPMENT_OK`：

1. 出厂枪弹药槽是标准弹（运行态复核）；
2. 左键装配：黏黏弹进槽、背包清零、换下的标准弹回包、运行树带 `sticky/dot`、
   **装备界面弹药行当场刷新**；
3. 拖到 `weapon_0` / `weapon_1` 均可换弹，且给副武器换弹不切换当前武器；
4. 装备界面两把武器各自显示正确模块名，弹药格 `slot_item` 非空、`drag_disabled` 为真；
5. 悬浮卡含「左键」「拖到主/副武器格」、不含「丢弃到地面」；
6. 武器格接受子弹模块、拒绝瞄具；
7. 装到近战武器（无弹药槽）失败时，模块整份退回背包、槽位不被写；
8. 背包其余格塞满时 1 换 1 仍成功，旧弹回填腾出的那一格、不吞物品。

结果：

| 用例 | 结果 |
|---|---|
| `verify_bullet_module_equipment_flow` | `BULLET_MODULE_EQUIPMENT_OK`，exit 0 |
| `verify_weapon_attachment_inventory_flow` | `WEAPON_ATTACHMENT_INVENTORY_FLOW_OK`，exit 0 |
| `verify_starting_weapon_contract` | `STARTING_WEAPON_CONTRACT_OK`，exit 0 |
| `verify_training_range_equipment_ui` | `TRAINING_RANGE_EQUIPMENT_UI_OK`，exit 0 |
| `verify_training_range_3d_flow` | `TRAINING_RANGE_3D_FLOW_OK`，exit 0 |
| `verify_inventory_experience_visual` | `INVENTORY_EXPERIENCE_VISUAL_OK checks=36`，exit 0 |

负向自测：把 `weapon_0/weapon_1` 分支的 `bullet_module_install_requested.emit(...)`
临时改成 `pass` ⇒ 新用例 5 条断言同时报红（拖主武器/拖副武器/两条界面文案），
恢复后转绿。

`verify_3d_inventory_weapon_flow` 与 `verify_tactical_inventory_minimap_flow` 在
**本次改动前的 HEAD 基线上同样失败**（headless 无渲染器，报「96x96 projection
budget」「material is null」等），与本改动无关，已用临时回退 HEAD 的方式确认。

## 未做（需业主裁决）

改造台 `WorkbenchPanel` 仍然按蓝图 tier **免费**列出全部弹种，不校验背包持有。
也就是说「地上掉的子弹模块」和「改造台免费换弹」两套体系并存。是否改成校验持有，
涉及平衡与便利性，留待拍板。

## 界面实拍

`outputs/inventory_qa/inventory_1280.png`（真实渲染，1280×720）：
主武器格下方出现「弹药」行——勾选态小图标 + 「标准子弹模块」；
副武器空槽显示灰色「未装填」。

> ⚠️ `verify_inventory_experience_visual` 在**本机窗口模式**下会报 12 条
> `native drag ...` 失败；已临时回退到 HEAD 用同一命令复跑，ERROR 数同为 12、
> 退出码同为 1 ⇒ 属本机渲染/鼠标模拟环境问题，与本次改动无关。
> headless 模式该用例 36 项全过（`INVENTORY_EXPERIENCE_VISUAL_OK checks=36`）。
