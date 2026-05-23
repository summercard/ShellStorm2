# 轮次 25 — 2026-05-23 02:51

### 主题
搜打撤经济闭环 — 怪物击杀货币实时入账激活

### 选择本轮的原因
审查核心玩法体验：玩家在局内通过击杀怪物获取魂，用于向商人购买装备，这是搜打撤经济循环的核心驱动力。当前 `LootModule.generate_enemy_loot()` 中 Boss/精英额外掉落货币的逻辑是 `pass` 空注释（行128），怪物死亡只触发 RoomGameMode.notify_enemy_killed 的 +10 魂基础奖励，没有实时视觉反馈。

问题：玩家杀死一波怪后不能直观感受到"魂在增长"，只能在房间清理后看到 Credits 文字提示。货币获取缺少即时反馈感。

### 玩家可感知结果
- 怪物死亡时，屏幕上飘出"+10魂"（或根据怪物类型不同）的小字飘字动画
- 商人和 HUD 货币标签实时更新
- 商人房购买时能直观感受到"这是我刚才打怪赚的"

### 修改内容

**代码：**

1. **`src/game/LootModule.gd`** — 激活 Boss/精英额外货币奖励
   - 删除 `generate_enemy_loot()` 中的空 `pass` 注释块
   - 实现 `bonus_currency` 逻辑：is_elite 额外 (50+floor*20) 魂，is_boss 额外 (200+floor*20) 魂
   - 返回货币物品数据供外部（RoomGameMode）调用 `add_currency`

2. **`src/map/RoomWaveSpawner.gd`** — 击杀时触发货币飘字
   - `_spawn_enemy_instance()` 中，enemy 死亡后触发 `_on_enemy_died()`
   - 新增 `_emit_currency_feedback(spawn_pos: Vector2, amount: int)` 方法
   - 通过 `GameUIManager` 显示飘字（如果 GameUIManager 可用）

3. **`src/game/RoomGameMode.gd`** — `notify_enemy_killed()` 时传入货币数据
   - 改用 `LootModule.generate_enemy_loot()` 结算实际掉落
   - 传入 enemy_data 中的 `currency_reward` 字段给 `add_currency()`
   - 让每只怪物有差异化货币（普通 +10，精英 +25-40，Boss +50-100）

4. **`src/ui/GameUIManager.gd`** — 新增货币飘字方法
   - `show_currency_popup(amount: int, world_pos: Vector2)` — 在指定世界坐标显示飘字
   - 飘字使用 GameUIManager 的 CanvasLayer 坐标系转换
   - 飘字内容："+N魂"（绿色，2秒后消失）

**数据契约变化：**
- `LootModule.generate_enemy_loot()` 返回值增加 `currency_bonus` 字段（int）
- EnemyBase 怪物数据增加 `currency_value` 字段（基础值 10）
- 词缀系统（EnemyModifier）可增加怪物 `currency_value`（如"富裕"词缀 +50%）

### 验收标准
- [ ] 普通怪物死亡显示 "+10魂" 飘字
- [ ] 精英怪物死亡显示 "+25~40魂" 飘字（根据层级）
- [ ] Boss 死亡显示 "+50~100魂" 飘字
- [ ] 货币实时更新到 HUD 和商人面板
- [ ] 连续击杀快速刷新飘字（多个飘字并存）
- [ ] Godot headless 编译通过 ✅

### 剩余风险
- 飘字动画目前是简单的 Label 上浮，如果需要更华丽效果（数字跳动、颜色变化）后续迭代
- 不同怪物类型（远程、召唤型）的货币价值可能需要差异化，目前统一用 base enemy_data.currency_value
- 性能：大量怪物死亡时同时创建很多飘字节点，需要池化处理（后续优化）

### 下一轮最可能方向
1. **物品系统补全**：治疗药水/弹药包实际可用（use_action 生效）
2. **信标道具全局注册**：信标在掉落表和商人供货中更常见
3. **商人自动打开交易**：玩家进入商人房时自动弹出交易面板（替代按E交互）
---

# 轮次 26 — 2026-05-23 02:56

### 主题
物品系统补全 — 治疗药水/弹药包use_action生效 + 信标道具全局注册

### 选择本轮的原因
当前 `ItemRegistry` 已注册 `item_health_potion`（use_action: heal）、`item_ammo_pack`（use_action: refill_ammo）和 `item_beacon`（use_action: summon_beacon_extraction），但这些 use_action 在背包UI中完全没有被消费。

玩家在局内捡到治疗药水/弹药包后只能存入保险格，无法使用。信标道具虽然是撤离专用，但信标按钮也只是检查计数，没有触发物品消耗。

这直接破坏了"消耗品"作为搜打撤决策工具的核心价值——玩家无法在关键时刻使用药水救命或弹药补给翻盘。

### 玩家可感知结果
- 右键背包中的治疗药水：立即恢复 30 HP（视觉：血条跳动 + PlayerVisuals.flash_heal）
- 右键背包中的弹药包：立即触发换弹（弹药重置为满）
- 信标按钮点击：真实从背包扣除信标道具数量

### 修改内容

**代码：**

1. **`src/game/ItemUseHandler.gd`**（新建）— 集中处理 use_action 路由
   - `apply(item, context)`: 读取 `use_action` 字符串并 match 分发到 `_apply_heal`/`_apply_refill_ammo`/`_apply_summon_beacon`
   - `_apply_heal()`: 调用 `player.heal(heal_amount)` 或从 `context["player"]` 获取 Player
   - `_apply_refill_ammo()`: 调用 `player.weapon_tree.start_reload()` 触发换弹重置弹药
   - `_apply_summon_beacon()`: 获取 ExtractionDirector 并调用 `summon_beacon_extraction()`
   - `_resolve_player()/_resolve_extraction_director()`: 兼容多种节点路径

2. **`src/ui/GameUIManager.gd`** — 右键使用背包物品
   - `_on_slot_right_clicked()`: 当 `use_action` 非空时，先 `consume_item()` 扣物品，再动态加载 ItemUseHandler 脚本并调用 `apply()`
   - 动态加载避免跨脚本类型声明问题（Godot `--script-check` 不允许显式标注未导入的 class_name 类型）
   - 新增 `_get_player_reference()` 辅助方法

3. **`src/game/RoomGameMode.gd`** — 新增 `get_player()` 方法
   - 暴露内部 `player` 节点引用，供 GameUIManager 获取 Player 用于消耗品效果

**验证：**
- Godot headless `--script-check` 零错误 ✅

### 剩余风险或试玩问题
- 治疗药水的 PlayerVisuals.flash_heal 需要确认 PlayerVisuals 正确挂载在 Player 节点下
- 弹药包 refill 触发的是 start_reload()（2秒换弹动画），可能需要改成直接加弹药？当前设计是"换弹动画"，符合"弹药包=换弹"的隐喻
- 信标物品在 ExtractionProgressUI 中已有 BEACON 按钮，但没有触发 consume_item。BEACON 按钮走 ExtractionDirector.summon_beacon_extraction() 直接消耗，但 ExtractionDirector.summon_beacon_extraction() 内部已经调用了 `_inventory_ref.consume_item()`（来自 bind_inventory），所以信标消耗是通的

### 下一轮最可能的方向
基地系统UI补全——当前游戏主循环是局内搜打撤，但缺少基地主界面入口（游戏开始/失败后需要返回基地选择装备/升级）。建议先确认 Main.gd 或游戏入口场景是否已有基地框架，再推进枪械工坊/命运占卜屋等基地功能。

## 轮次23（2026-05-23 02:17 UTC+8）

### 维度选择
**搜打撤深化 — 命运卡片UI完善（房间清理后通知提示）**

轮次22完成了命运卡片UI的Tab键激活，但缺少一个关键体验链：**房间清理完成后玩家不知道该按Tab选卡**。本轮在 GameUIManager 中添加房间清理完成后的"按 Tab 选择命运卡片"提示标签，给玩家清晰的行动引导。

### 玩家可感知结果
- 房间清理完成后，屏幕底部居中淡入显示金色文字"按 Tab 选择命运卡片"，持续4秒后淡出
- 提示显示期间按 Tab 直接打开选卡界面（提示自动消失）
- 按 Esc 可关闭选卡界面

### 修改内容

**代码：**
1. `src/ui/GameUIManager.gd`
   - 新增 4 个变量：`_fate_card_notification_label`、`_fate_card_notification_timer`、`_FATE_CARD_NOTIFICATION_DURATION`（常量4秒）、`_fate_card_card_container`（用于后续Tab激活）、`_fate_card_panel_base`
   - `_setup_fate_card_ui()` 中：查找已有的命运卡片通知 Label，没有则动态创建（底部居中，金色文字，带暗色背景），初始化为透明
   - `_show_fate_card_notification()`：设置计时器4秒，显示标签，淡入动画
   - `_hide_fate_card_notification()`：淡出动画后隐藏标签
   - `_on_room_cleared()`：末尾调用 `_show_fate_card_notification()`
   - `_process()`：新增计时器倒计时逻辑和 Tab 键打开选卡界面检测（Tab 在非暂停且无其他面板时打开选卡）
   - `_on_extraction_completed()` 参数 `success` 改为 `_success`（消除未使用变量警告）
   - `_inventory_ui` 变量声明改为 `Control` 类型避免类型推断警告（后续会用正确类型）
   - 新增辅助变量和结构保留，供后续完善 Tab 选卡功能

### 验收标准
- [ ] 房间清理完成后屏幕底部显示"按 Tab 选择命运卡片"提示
- [ ] 提示4秒后自动消失
- [ ] 提示期间按 Tab 打开选卡界面（提示消失）
- [ ] Godot headless 编译零错误（EXITCODE: 0）

### 剩余风险
- 选卡界面（show_card_selection）的完整实现需要 Tab 键在系统已注册 ui_tab action，当前 project.godot 已添加此 action
- _inventory_ui 变量类型仍是 Control 而非 InventoryUI（需要解决类加载顺序后才能显式类型化）
- 命运卡片通知标签的位置可能因分辨率不同需要微调

### 下一轮最可能方向
1. **完成 Tab 选卡界面完整实现**：show_card_selection / hide_card_selection / _create_fate_card_button / _on_fate_card_selected
2. **出生房命运卡片强制展示**：出生时自动弹出3张初始卡
3. **商人房自动交易面板**：玩家进入商人房时自动打开商人面板
4. **基地系统UI补全**：基地主界面框架
