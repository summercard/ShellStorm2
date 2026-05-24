# ShellStorm2 开发日志

## 轮次146（2026-05-25 05:27 UTC+8）

### 维度选择
**命运卡片改造后枪械视觉不刷新 — WeaponAssemblyTree → WeaponDisplay 链路补全**

从核心玩法"武器装配树+命运卡片改造"链路审查，发现一个关键断点：
- WorkbenchPanel 选中命运卡片 → `FateCardGameBridge.apply_card_instance()` → `FateCardEngine.apply_card()` → 武器树挂载新节点并 emit `tree_changed`
- `WeaponAssemblyTreePanel` 通过 `tree_changed` 信号刷新树结构显示
- **但 `WeaponDisplay`（玩家手上枪的视觉表现）完全没有监听 `tree_changed`** — 玩家换枪身后枪型正确，但命运卡片改造武器树结构后，枪型视觉不会更新

这是命运卡片核心体验的缺口：玩家改造了武器（装上了奇怪子弹、多了枪上枪），但手上拿的枪形状不变，严重破坏"无厘头武器进化"的可感知性。

### 玩家可感知的结果
命运卡片改造武器后，枪械外形能正确刷新。具体来说：
- 在改造房选择"子弹背枪"类命运卡片 → 子弹节点上挂载了枪身节点 → `tree_changed` 触发 → `WeaponDisplay` 收到通知并刷新枪型显示
- 枪型切换（主枪身改变）时枪械多边形形状立即切换

### 修改内容

#### `src/weapon/WeaponDisplay.gd` — 核心修复

**问题根源**：`WeaponDisplay._ready()` 在 `_refresh_weapon_from_player()` 时 `_weapon_tree` 尚未初始化（因为 WeaponDisplay 是 Player 子节点，Player.get_weapon_tree() 需要 Player._ready 执行完），导致 weapon_fired 连接失败且无 tree_changed 监听。

**修复方案**：
1. 移除 `_ready()` 中直接调用 `_weapon_tree.weapon_fired.connect`（此时 tree 为 null）
2. 改为在 `_refresh_weapon_from_player()` 内部延迟获取 tree 后**同时**连接两个信号：`tree_changed`（命运卡片改造触发刷新）+ `weapon_fired`（射击动画）
3. 新增 `_on_tree_changed_by_fate()` 回调：`tree_changed` 触发时取 `weapon_tree.get_root().node_name` 并调用 `_update_gun_display()` 刷新枪型
4. `_refresh_weapon_from_player()` 支持重复调用（先断开旧连接，防止重复订阅）
5. 添加 `await get_tree().create_timer(0.05).timeout` 延迟初始化，确保 Player 已就绪

### 验收标准
- [x] Godot headless --quit-after 3 编译通过 ✅
- [ ] 人类试玩：在改造房选择一张命运卡片（如"子弹背枪"），卡片应用后枪型显示正确刷新
- [ ] 人类试玩：在 Workbench 切换枪身（如从 Pistol 换成 Rifle），WeaponDisplay 枪型立即更新
- [ ] 人类试玩：连续多次命运改造，树刷新不丢失、不重复订阅信号

### 剩余风险
- 枪型列表 `GUN_SHAPES` 键名（如 "GunBody_Pistol"）是否与实际 BlueprintRegistry 的 item_id 一致，需要在完整 DemoRoomChain 中验证
- 命运卡片改造后如果枪型没变（节点名称相同），`_update_gun_display` 会跳过更新，此时枪型视觉确实不需要变化，但命运改造的"枪上枪"视觉需要额外机制（如额外节点叠加），属于下一轮方向

### 下轮最可能方向
1. **命运卡片改造后视觉完整性**（子弹背枪后枪在子弹上+自动射击效果）：验证子弹飞行时携带的枪是否正确渲染
2. **DemoRoomChain 完整试玩验证**：当前所有功能在 DemoRoomChain 链路上逐一验证
3. **Bullet.gd 命中后处理**：子弹命中有击退但缺乏伤害反馈 UI（如伤害数字）

---

## 轮次122（2026-05-25 01:59 UTC+8）

### 维度选择
**撤离房场景缺失填补 — RoomExtraction.tscn + ExtractionRoomLogic.gd**

从组件化目标和 DemoRoomChain 规格出发审查，发现撤离房场景完全缺失：
- RoomFactory.SCENE_MAP 中 EXTRACTION → "res://scenes/RoomExtraction.tscn"
- 但 scenes/ 中只有 Combat/Merchant/Storage/Trap/Upgrade，缺少 RoomExtraction.tscn
- RoomTileSetBuilder.ROOM_THEMES 中已有 EXTRACTION 主题（深蓝/青色）
- PH12 设计文档中 EXTRACTION 视觉风格定义存在，代码未实现

### 玩家可感知结果
- 撤离房（EXTRACTION）现在有专属场景：`scenes/RoomExtraction.tscn`
- 撤离房风格：深蓝/青色调 + 中央撤离光圈 + 4方向出口标记
- 撤离光圈脉冲动画：进入撤离房后光圈持续脉动，视觉暗示"这是终点"
- 方向标记强化：进入撤离房后 4 个方向标记颜色从 0.7 → 0.85 alpha，强化可离开感
- 搜打撤终点现在有正确的视觉锚点

### 修改内容
| 文件 | 改动 |
|---|---|
| `scenes/RoomExtraction.tscn` | 新建 — 撤离房场景，含 TileMap（EXTRACTION主题）+ 4角落暗角 + 中央光圈 ExtractionCircle + 4方向 ExitMarker + DoorVisualizer |
| `src/game/ExtractionRoomLogic.gd` | 新建 — 撤离房逻辑组件，含光圈脉冲动画 `_process()` + `activate_extraction()` 视觉激活方法 |
| `src/game/RoomGameMode.gd` | `_activate_extraction_room()` 末尾新增 `_apply_extraction_visual_activation()` 调用链 |

### 技术细节
- **TileMap 主题**：RoomTileSetBuilder.ROOM_THEMES[EXTRACTION]（深蓝/青色），在 `RoomTileMapInitializer.build()` 时自动应用
- **Visualizer 节点**：RoomExtraction.tscn 根节点 script = ExtractionRoomLogic，Visualizer 子节点 = RoomTileMapInitializer
- **门过渡视觉**：DoorVisualizer 节点已添加，与其他房间一致（P2 补全）
- **撤离光圈动画**：sin 脉冲，周期 2.5rad/s，alpha 在 0.08~0.23 间脉动
- **视觉激活链路**：RoomGameMode._activate_extraction_room() → _apply_extraction_visual_activation() → room_instance.activate_extraction()（ExtractionRoomLogic 实例方法）

### 验收标准
- [x] Godot headless --quit-after 1 编译通过 ✅
- [ ] 玩家进入 EXTRACTION 房间，撤离光圈可见且持续脉动
- [ ] 玩家进入 EXTRACTION 房间，4 个方向 ExitMarker 颜色强化
- [ ] 玩家在撤离读条期间走回其他房间，撤离中断且撤离光圈停止脉动
- [ ] 完整搜打撤 DemoRoomChain 试玩验证

### 剩余风险
- ExtractionRoomLogic 光圈脉冲在玩家中断撤离时未停止（需要额外信号触发 reset）
- RoomExtraction.tscn 的 Visualizer 节点与 RoomFactory 联动逻辑待真实试玩确认
- DoorVisualizer 方向标记在撤离房场景的实际显示位置需要人类试玩确认是否合理

### 下轮最可能方向
1. **DemoRoomChain 场景创建**（5房间线性链）：建立完整搜打撤 Demo 链
2. **撤离中断光圈停止**：extraction_aborted → ExtractionRoomLogic 光圈停止脉动
3. **RoomTileSetBuilder 补全 STORAGE 主题**：Storage 房间地板色已定义但未在 TileSet 中正确应用

---

## 轮次36（2026-05-23 05:12 UTC+8）

### 维度选择
**商人房折返重入逻辑 — 离开再进入时面板重新打开的边界情况**

上一轮轮次35完成了商人房自动弹出交易面板（进入即触发），本轮审查折返重入时的边界行为。

### 核心问题分析
1. **状态不一致**：`RoomGameMode._auto_open_merchant()` 调用 `ui.show_merchant()` 但没有更新 `MerchantInteraction._state`。状态仍为 `IDLE`，离开商人房时 `_on_body_exited` 检查到 `state != MerchantState.ACTIVE`，不会触发 `_close_shop()` → 面板无法正确关闭。
2. **面板可见性实现**：`MerchantUI._set_panel_visibility(visible)` 使用 `visible_ratio = 1.0 / 0.0`，这是 Tween 动画属性，不是简单的开关/显示。重复进入时 `show_merchant()` 再次设置 `visible_ratio = 1.0`，内部 `_build_shop_grid()` 会重建 UI。

### 玩家可感知结果
- 玩家进入商人房 → 面板自动弹出 ✅
- 玩家离开商人房 → 面板保持打开（因为 `_state` 未同步）❌
- 玩家折返进入同一商人房 → 面板重建（可能闪烁）

### 修改内容
| 文件 | 改动 |
|---|---|
| `src/game/MerchantInteraction.gd` | 新增 `force_set_active()` 方法，将 `_state` 设为 `ACTIVE` 并隐藏交互标签 |
| `src/game/RoomGameMode.gd` | `_auto_open_merchant()` 在 `show_merchant()` 后调用 `merchant_interaction.force_set_active()` 同步状态 |

### 验收标准
- [ ] 玩家离开商人房时，面板正确关闭（无需再按E）
- [ ] 玩家折返进入商人房，面板重新打开
- [ ] 面板关闭后，玩家再次进入相邻房间再折返，面板仍能重新打开
- [ ] Godot headless 编译通过 ✅

### 剩余风险
- 面板关闭后状态为 `AVAILABLE`，玩家折返时 `room_entered` 会重新触发 `_auto_open_merchant()`（再次 `show_merchant`），这会正确工作
- 如果 `visible_ratio` 动画在玩家折返时还在播放，`show_merchant()` 重设 `visible_ratio = 1.0` 可能导致动画重新播放（视觉闪烁）
- 建议后续在 `MerchantUI.show_merchant()` 中加 `visible_ratio = 1.0` 之前先 `stop()` 动画

### 下一轮最可能方向
1. **商人房面板 Tween 动画打断处理**：折返时停止旧动画再重新打开
2. **商人房商品刷新逻辑**：玩家长时间停留时商品是否应该动态刷新
3. **物品系统完善**：信标/消耗品掉落途径，补全局内经济闭环
4. **基地出生房装修**：出生房视觉/UI补全

---

## 轮次16（2026-05-23 01:19 UTC+8）

### 维度选择
**搜打撤深化 — 信标撤离完整链路**

从核心玩法视角审查，搜打撤的核心决策之一是"什么时候撤"。信标撤离是一个高风险高回报的选择：
- 玩家消耗一个信标道具 → 在当前位置召唤撤离点（省去跑路时间）
- 但信标撤离按钮显示的信标数量一直是0，且 BEACON 按钮没有实际扣除信标

这是一个明显的体验断点：信标撤离的 UI 和逻辑没有真实连通。

### 玩家可感知结果
- 玩家在背包持有信标道具（`item_beacon`）时，撤离面板的信标数量正确显示
- 信标撤离按钮在信标不足时灰显
- 点击信标撤离时，从背包真实扣除一个信标道具
- 撤离成功后信标计数刷新

### 修改内容

**代码：**
1. `src/map/ExtractionDirector.gd`
   - 新增 `_beacon_item_id` 成员变量（默认 `"item_beacon"`）
   - 新增 `get_beacon_item_id()` 返回信标道具ID
   - 新增 `sync_beacon_count_from_inventory(inventory: InventoryModule)` 从背包同步信标数量
   - 新增 `has_beacon()` 检查是否还有信标可用

2. `src/ui/GameUIManager.gd`
   - 新增 `_extraction_director` 成员变量
   - 新增 `set_extraction_director(director: Node)` 绑定方法
   - 新增 `_sync_beacon_label()` 更新信标标签显示
   - `_update_extraction_buttons()` 接入真实信标/Boss/精英可用性检查
   - `_on_extraction_ready()` 调用 `_sync_beacon_label()`
   - BEACON 按钮按下时调用 `extraction_director.summon_beacon_extraction()` 消耗信标

3. `src/game/RoomGameMode.gd`
   - `_on_extraction_completed()` 成功后调用 `_sync_beacon_count()` 刷新信标
   - `_on_map_generated()` 时调用 `_sync_beacon_count()` 同步初始信标
   - 新增 `_sync_beacon_count()` 方法

**数据契约：**
- 信标道具ID 统一为 `"item_beacon"`（与物品系统对齐，后续物品表扩展时保持一致）

### 验收标准
- [ ] 玩家背包有信标时，撤离面板显示"信标数量: N"
- [ ] 玩家背包无信标时，信标撤离按钮灰显
- [ ] 点击信标撤离，信标数量减1
- [ ] 撤离成功后信标数量刷新（减少）
- [ ] Boss撤离、精英撤离按钮在对应撤离点存在时才可用
- [ ] Godot headless 编译通过 ✅

### 剩余风险
- 信标道具目前还没有实际掉落/获取途径（物品系统尚未完善），需要配合物品生成系统
- `item_beacon` 物品尚未在物品表中注册，实际运行时信标数量会一直为0直至物品系统就绪

### 下一轮可能方向
1. **物品系统基础**：注册信标道具到物品表，让玩家可以通过箱子/商人获得信标
2. **搜打撤经济闭环**：完善资源（魂、弹药、消耗品）的局内循环
3. **命运卡片抽取UI**：当前玩家还不能实际使用命运卡片改造武器
4. **精英怪成长系统**：作为长期威胁和复仇目标与搜打撤深度结合
## 轮次35（2026-05-23 05:08 UTC+8）

### 维度选择
**商人房自动交易面板**

核心问题：玩家进入商人房后需要按 E 才能打开交易面板，体验有断层——玩家预期是"看到商人就能交易"。这是搜打撤流程中重要的资源交互节点，必须"进入即触发"。

### 玩家可感知结果
- 玩家踏入商人房，商人面板自动弹出，无需按 E 键
- 货币充足时商品绿色边框，货币不足时红色边框
- 点击商品直接购买并入背包
- 按 ESC 或点击 X 关闭面板，退出商人房不触发重新打开

### 修改内容

**代码：**
1. `src/game/RoomGameMode.gd`
   - `_on_room_entered()` 中新增商人房类型检测（`RoomData.RoomType.MERCHANT`），进入即调用 `_auto_open_merchant()`
   - 新增 `_auto_open_merchant(room_data: RoomData)` 方法：
     - 通过 `map_manager._current_room_id` + `get_instantiated_room()` 查找商人房节点
     - 获取 `MerchantArea` → `MerchantInteraction` 引用
     - 绑定背包 `set_inventory()`，确保商品已生成
     - 调用 `get_or_create_merchant_ui().show_merchant()` 自动展示面板
     - 更新房间标签提示"与 [流浪商人] 交易中..."
   - 商人房清理进度初始化为 0/1（无波次）

### 验收标准
- [ ] 玩家进入商人房时，MerchantUI 面板自动弹出（无需按键）
- [ ] 商品列表显示 6 个物品，价格正确
- [ ] 货币充足时购买成功，物品入背包
- [ ] ESC / X 关闭面板正常
- [ ] 离开商人房再进入，不产生重复面板
- [ ] Godot headless 编译通过 ✅

### 剩余风险
- **重复进入触发**：`room_entered` 每次进入房间都会触发；如果玩家离开商人房后折返，`show_merchant()` 会被再次调用（MerchantUI 内部 `visible_ratio` 重新设为 1.0，不重复创建），但需验证 MerchantUI 关闭后能否正确重新打开
- **商品数量**：6 个商品的硬编码与房间内实际商品数量是否匹配需要确认 LootModule.generate_merchant_goods() 在该层的实际返回数量

### 下一轮可能方向
1. **商人房重复进入逻辑**：玩家折返时面板重新打开的边界情况
2. **商人房内容完善**：加入购买音效、物品图标、商人对话气泡
3. **物品系统**：信标道具尚未有掉落途径，物品系统完善后可让玩家真正使用信标撤离
4. **命运卡片实用化**：当前命运卡片只展示了效果，还没有和武器装配系统深度结合

## 轮次61（2026-05-23 08:42 UTC+8）

### 维度选择
**撤离系统链路修复 — Boss/精英击杀后撤离点解锁的信号断裂**

### 核心问题分析
本轮审查 P14 的遗留问题："BOSS_KILL/ELITE_KILL/TRADE 撤离类型的按钮可用性接入真实房间完成状态"。发现了严重的逻辑断裂：

1. **BOSS_KILL 撤离点从未解锁**：BossRoomDirector._defeat_boss() 中调用 `ExtractionDirector.new().unlock_boss_extraction()`，每次创建新的局部 ExtractionDirector 实例，而不是操作 MapManager 中那个唯一的 extraction_director。这意味着地图初始化时添加的 BOSS_KILL 占位点（从未被创建）永远不会被解锁，GameUIManager._can_use_extraction_type("BOSS_KILL") 永远返回 false。

2. **ELITE_KILL 撤离点提前解锁错误**：MapManager._setup_extraction_points() 在地图生成时就 add_extraction_point(ELITE_KILL) 并立即 unlock_extraction()，没有等待精英击杀事件。这导致按钮一开始就可点击（虚假可用），但实际上精英还未击杀。

3. **TRADE 撤离无实现**：只有枚举值和按钮文案，没有对应的解锁逻辑和 countdown 处理。

### 玩家可感知结果
- 玩家在第一层击败 Boss 后，Boss 撤离按钮仍然灰显，无法使用
- 第一层精英撤离按钮在精英未击杀时就能点，但点了无效（按钮条件检查 size > 0 但点后实际逻辑缺失）
- TRADE 撤离按钮文案有但实际无效

### 修改内容
| 文件 | 改动 |
|---|---|
| `src/map/BossRoomDirector.gd` | 新增 `_extraction_director` 成员变量；新增 `set_extraction_director()` 注入方法；`_defeat_boss()` 中优先使用注入引用解锁 Boss 撤离，兜底通过节点路径获取 |
| `src/map/MapManager.gd` | `_init()` 中调用 `boss_director.set_extraction_director(extraction_director)` 完成注入；修改 `_setup_extraction_points()` 不再提前 unlock ELITE_KILL，注释说明由精英击杀事件触发 |
| `src/map/ExtractionDirector.gd` | ELITE_KILL 和 BOSS_KILL 的解锁已有对应方法 unlock_elite_extraction() / unlock_boss_extraction()，结构正确 |

### 验收标准
- [ ] 击败 Boss 后，Boss 撤离按钮变为可用（可点击非灰显）
- [ ] 第二层起，精英撤离点初始灰显，精英击杀后变为可用
- [ ] Godot headless --quit-after 1 编译 EXIT: 0 ✅

### 剩余风险
- **精英击杀信号未连接**：EliteArchiveModule.elite_killed 信号目前没有接收者，无法触发 unlock_elite_extraction()。需要 RoomGameMode 或 MapManager 连接该信号并调用 ExtractionDirector.unlock_elite_extraction()——但 EliteArchiveModule 在当前代码中似乎没有在游戏流程中被实例化
- **TRADE 撤离**：需要确认是否作为功能保留，还是从 5 种类型中移除
- **实际试玩验证**：需要人类试玩确认 Boss 击杀后按钮变化

### 下一轮最可能方向
1. **精英击杀信号连接**：找到或创建 EliteArchiveModule 实例并连接 elite_killed → ExtractionDirector.unlock_elite_extraction()
2. **TRADE 撤离处理**：确认设计意图，或移除按钮
3. **宝箱系统完善**：P14 剩余的"宝箱/容器开启→物品入背包→InventoryUI刷新"逻辑

