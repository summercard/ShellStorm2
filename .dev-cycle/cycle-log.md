# ShellStorm2 开发日志

## 轮次190（2026-05-26 03:27 UTC+8）

### 维度选择
**LightSync.gd 房间切换后 PlayerVisionLight 遗漏问题**

从核心玩法"视野遮挡系统"链路审查，发现一个关键问题：
- RoomTileMapInitializer._build_vision_layer() 在每个房间实例化时在 parent 节点下创建 PlayerVisionLight（PointLight2D）和 VisionDarkness（CanvasModulate）
- LightSync.gd 在 _ready 中通过 find_child 查找 PlayerVisionLight，然后每帧同步到 Player 全局坐标
- 当房间切换（RoomGameMode._stop_current_room_spawner 清理旧房间，LightSync 的 `_tracked_light` 仍然指向已 queue_free 的旧房间光源）
- 由于 PlayerVisionLight 是在 room 实例下动态创建的（非场景预制），LightSync 查找时需要从 Main 逐层 find_child("PlayerVisionLight")，而每个房间都有独立的 PlayerVisionLight
- 问题：LightSync 在 _ready 中只查一次；如果旧房间被清理、新房间的 PlayerVisionLight 虽然存在但名字相同，LightSync 仍然持有已释放的引用

### 解决方案
将 LightSync.gd 的单次初始化改为每帧动态查找（保持轻量）：移除 _ready 中的一次性查找，在 _process 每帧中通过 `main.find_child("PlayerVisionLight", true, false)` 实时获取当前房间的光源节点。RoomTileMapInitializer 创建的 light.set_meta("_tracked", true) 确保查找准确。

### 修改内容

#### `src/fx/LightSync.gd`
1. **移除 `_ready()` 中的初始化**：不再在 _ready 中查找并缓存 PlayerVisionLight
2. **修改 `_process()` 逻辑**：每帧先找 Main，再从 Main.find_child("PlayerVisionLight", true, false) 获取当前有效引用，最后同步到 player 位置
3. **保持轻量**：每次 find_child 只遍历一次树（递归），考虑到 60fps 下查找开销可控，且解决了引用失效的根本问题

### 玩家可感知结果
- 玩家从房间A进入房间B时，视野光源正确跟随玩家，新房间墙壁产生正确的 LightOccluder 实时阴影
- 多房间探索时视野遮挡不会因为房间切换而失效
- 黑暗角落的分布由房间几何决定，玩家光源照亮周围，形成"探索越深越暗"的压迫感

### 验收标准
- [x] Godot headless --quit-after 3 编译通过 ✅
- [ ] 人类试玩：进入 DemoRoomChain → 清理房间1 → 进入房间2，观察视觉阴影正确跟随玩家光源
- [ ] 人类试玩：连续穿过多个房间，视野光源持续跟随，不出现"光留在原地"的情况

### 剩余风险
- 每帧 find_child 遍历整树对性能有轻微影响（需要实际测试是否需要优化）
- 房间切换时旧房间节点的清理时机需要和 RoomGameMode._stop_current_room_spawner 配合

### 下轮最可能方向
1. **命运卡片枪械视觉刷新完整性**：WeaponDisplay 的 tree_changed 信号响应后，AttachedGun 多边形是否正确刷新
2. **人类试玩验证命运卡片视觉（eyes+legs+fate_scale）**：实际选卡后子弹视觉是否正确
3. **搜打撤经济系统收束**：魂币收益/带出结算/保险格完整性

---

## 轮次183（2026-05-26 02:24 UTC+8）

### 维度选择
**命运卡片应用音效缺失 — AudioManager + SynthSfx + FateCardEngine 链路补全**

从核心玩法"命运卡片改造"链路审查，发现一个关键缺口：
- FateCardEngine.apply_card() 成功执行后，仅有日志输出和 UI notification
- 命运卡片的核心体验（玩家在门后或改造房选择卡片，卡片应用后武器立即变化）完全缺少音效反馈
- 没有声音的卡片应用体验不完整——"命运降临"应该有声音锚点

### 玩家可感知的结果
玩家在门后或工作台选择命运卡片后，卡片应用成功时播放一段上升琶音效（5音符，-6dB），暗示"命运降临、力量改变"。每次卡片成功应用都触发，与射击/暴击/换弹音效并列，形成完整的声音反馈体系。

### 修改内容

#### `src/core/SynthSfx.gd`
1. 新增 `play_fate_card()` 方法：程序化合成上升琶音（5个音符从261.63Hz到659.25Hz，每个0.10s，-6dB），专门用于命运卡片应用
2. 新增 `_make_arpeggio_up()` 辅助方法：将频率数组反转实现从低到高的琶音效果

#### `src/core/AudioManager.gd`
1. SFX 映射新增 `"fate_card": ""`（空路径，无文件时降级到程序化合成）
2. 新增 `play_fate_card_sfx()` 实例方法：调用 `play_sfx("fate_card")`
3. `_play_fallback_sfx()` 新增 `"fate_card"` case：路由到 `_synth.play_fate_card()`

#### `src/weapons/FateCardEngine.gd`
1. 末尾新增静态方法 `_fate_audio_card_applied()`：通过 `Engine.get_singleton("AudioManager")` 获取 AudioManager 并调用 `play_fate_card_sfx()`
2. 在全部 17 个效果执行方法的 `result.success = true` 之后插入 `_fate_audio_card_applied()` 调用

### 验收标准
- [x] Godot headless --quit-after 3 编译通过 ✅
- [ ] 人类试玩：在门后三选一选择"变大了"/"子弹背枪"/"超频"等卡片，应用成功时播放上升琶音
- [ ] 人类试玩：连续选择多张卡片，每张都触发音效（无重复/遗漏）
- [ ] 人类试玩：命运卡片应用失败时不触发音效

### 剩余风险
- 音效触发时机依赖 Engine.get_singleton("AudioManager")，在某些非主场景测试中可能返回 null（已做 null 检查）
- 上升琶音是否与整体音效风格协调需要人类试玩确认（可能需要调整频率/时长/音量）
- 未来接入真实音频文件后，只需在 SFX 映射中填入文件路径即可，无需修改代码

### 下轮最可能方向
1. **人类试玩验证**（音效链路/轨迹颜色/枪身命运视觉）
2. **命运卡片加眼睛/加脚视觉接入 WeaponDisplay**（子弹eyes/legs在WeaponDisplay上渲染，玩家手持枪可见）
3. **搜打撤经济系统收束**（魂币收益/带出结算/保险格完整性）

---

## 轮次149（2026-05-25 06:05 UTC+8）

### 维度选择
**命运卡片"子弹背枪"挂载枪多边形兜底 — Bullet.gd 渲染逻辑支持 AttachedGun_* 前缀匹配**

轮次148完成了 Bullet.gd 的 AttachedGunPolygon 节点添加和 GUN_SHAPES 定义，但在审查链路时发现一个渲染断点：
- `_apply_attach_gun_to_bullet()` 创建的挂载枪节点名为 `"AttachedGun_" + card.card_id`（例如 `AttachedGun_card_bullet_carry_gun_001`）
- `_render_attached_gun()` 使用 `GUN_SHAPES.get(gun_name, DEFAULT_GUN_SHAPE)` 直接精确匹配键名
- `GUN_SHAPES` 中没有 `AttachedGun_*` 前缀的键，导致渲染回退到 `DEFAULT_GUN_SHAPE`（灰色多边形，视觉不明确）
- 此外，`DEFAULT_GUN_SHAPE` 的 polygon 顶点数（5个）与 `AttachedGun` 专用外形（5个）不匹配，且颜色不够独特（灰色 vs 暗金色）

### 玩家可感知结果
选择"子弹背枪"命运卡片后，发射的子弹尾部会显示一个暗金色的小型枪多边形（而非默认灰色通用形状）。挂载枪有独特的视觉身份，让玩家明确感知"子弹上背了一把枪"。

### 修改内容

#### `src/bullet/Bullet.gd`

1. **GUN_SHAPES 新增 "AttachedGun" 专用键**：
   - 专门给命运卡片"子弹背枪"等机制创建的挂载枪使用
   - 形状：紧凑手枪外形（5顶点多边形），暗金色，区分于玩家主枪
   - 匹配模式：`AttachedGun_*` 前缀节点名统一渲染为此类型

2. **`_render_attached_gun()` 前缀匹配逻辑**：
   - 优先精确匹配键名（如 "GunBody_Pistol"）
   - 回退：检测 `gun_name.begins_with("AttachedGun")` 前缀，匹配到 "AttachedGun" 键
   - 最终兜底：`DEFAULT_GUN_SHAPE`

### 验收标准
- [x] Godot headless --quit-after 4 编译通过 ✅
- [ ] 人类试玩：在改造房选择"子弹背枪"卡片后，发射子弹尾部显示暗金色小型枪多边形
- [ ] 人类试玩：挂载枪多边形在子弹飞行/转向时持续跟随子弹（AttachedGunPolygon 作为 Bullet 子节点）
- [ ] 人类试玩：命运视觉（变大了/加眼睛/加脚）与挂载枪多边形同时存在时，两者都能正确渲染

### 剩余风险
- 挂载枪多边形位置固定在 Bullet 本地坐标（0,0），朝向随子弹方向旋转，但视觉上"背在子弹尾部"的位置感需要确认（可能需要局部偏移）
- 挂载枪自动射击（`_process_attached_gun_firing`）在子弹转向时方向是否正确追踪敌人，需要人类试玩验证
- `visual_has_eyes/legs` 标签的视觉叠加在挂载枪多边形上，需要确认 z_index 层叠顺序

### 下轮最可能方向
1. **命运卡片完整链路人类试玩验证**：DemoRoomChain 实际验证子弹背枪+命运视觉（eyes/legs/scale）+自动射击的完整流程
2. **挂载枪多边形位置微调**：当前AttachedGunPolygon在(0,0)，可能需要偏移到子弹尾部让视觉更自然
3. **改造房命运卡片→WeaponDisplay枪型实际刷新链路验证**

---

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


## 轮次247（2026-05-27 02:07 UTC+8）

### 维度选择
**环境命运触发器 GRANT_RANDOM_CARD 效果为空 — MAP_TRIGGER 类命卡只记录不应用**

从核心玩法"命运卡片改造"链路审查，结合轮次246精英Attachment模块落地后的下一目标（人类试玩验证），发现环境命运触发器存在关键缺陷：
- MapFateTriggers.gd 监听游戏事件（击杀/开箱/进入房间），触发阈值后激活 MAP_TRIGGER 类命卡
- fate_mark_enemy（击杀第10敌获得随机命卡）使用 `EffectAction.GRANT_RANDOM_CARD`
- 当前 `_apply_grant_random_card()` 只调用 `bridge.grant_random_card_from_trigger()` 将卡片**记录到 applied_cards 列表**，但**从未执行卡片的 EffectAction**
- 结果：fate_mark_enemy 触发后，给的是一张"记录在列表里但武器树没有任何变化"的空气命卡
- grant_random_card_from_trigger() 还只从 ENHANCE/RULE/MUTATE 抽，漏掉了 COMBINE 类可用组合卡

### 玩家可感知的结果
击杀第10个敌人后，触发的命运标记效果现在真正给予并应用一张随机命卡（从可玩命卡池不含诅咒类），武器树实际变化。例如触发"变大了"后子弹实际变大，触发"子弹背枪"后子弹携带枪身飞行。UI 显示"随机命卡：XXX — 效果描述"。

### 修改内容

#### `src/weapons/FateCardEngine.gd` — _apply_grant_random_card 重写
原实现只记录到列表 → 改为直接通过 FateCardEngine.apply_card() 真正应用随机卡片的 EffectAction。
排除 CARD.CURSE 类（风险过高不随机给），调用 `bridge.record_applied_card()` 记录到列表。

#### `src/game/FateCardGameBridge.gd` — grant_random_card_from_trigger 保留 + record_applied_card 新增
保留原方法（供其他调用方使用），新增 `record_applied_card(card)` 方法供 FateCardEngine 在环境命运触发器中调用，避免 double-count。

### 验收标准
- [x] Godot headless --quit-after 4 编译通过 ✅
- [ ] 人类试玩：击杀第10个敌人触发 fate_mark_enemy，获得的随机命卡实际修改武器树（观察卡片名称与武器变化对应）
- [ ] 人类试玩：连续多次环境命运触发，每次都正确应用不同随机命卡（无重复、无遗漏）
- [ ] 人类试玩：诅咒降临等 CURSE 类命卡不会通过随机给予（由玩家主动选择）
- [ ] 人类试玩：精英多枪扇形射击+追踪弹+落地炮台+乱射+火力暴食+Attachment修饰 完整验证

### 剩余风险
- 随机命卡池不含 CURSE 类，但 COMBINE 类（如子弹背枪/枪上加枪）是否过强需要试玩确认
- record_applied_card 在 bridge 为 null 时未打印警告（已在 engine_result.message 中注明）

### 下轮最可能方向
1. **人类试玩验证**（精英Attachment链路+fate_mark_enemy随机命卡链路）
2. **FateCardPresets.map_trigger_presets() 方法创建**：将 MAP_TRIGGER 类命卡聚合，替代注释标记的"环境触发型"
3. **搜打撤经济系统收束**（魂币收益/带出结算/保险格完整性）
## 轮次 267 — 2026-05-27 07:28

### 维度选择
**小地图脏标记重绘驱动修复（polish/边界问题）**

### 问题诊断
在审查 GameUIManager.gd 小地图系统时发现一个阻断性bug：`_minimap_dirty` 标记在地图生成/房间切换/区域揭示时会被正确设置为 `true`，`_draw()` 也实现了完整的 `_draw_minimap_rserver()` RenderingServer 绘制逻辑，但 **`_process()` 中完全没有驱动 `queue_redraw()` 的代码**，导致 `_minimap_dirty` 永远无法触发 ReferenceRect 重绘回调，小地图实际上永远不会刷新。

这是一个典型的"脏标记设置了但消费者缺失"bug，表现为玩家在小地图上永远看不到房间切换/探索揭示的更新。

### 玩家可感知结果
- 修复后：小地图在房间切换、区域揭示、地图生成时能正确刷新
- 玩家能在小地图上看到自己移动到不同房间节点、看到已揭示相邻房间的连线

### 修改内容
**代码：**
1. `src/ui/GameUIManager.gd`
   - `_process()` 新增 `if _minimap_dirty:` 分支
   - 当脏标记为 true 时：重置脏标记 → 调用 `_minimap_view.queue_redraw()` 触发 `_draw()` 回调
   - 脏标记来源：`_on_map_generated_for_minimap()` / `_on_room_entered_for_minimap()` / `_on_adjacent_rooms_revealed()` / `_on_minimap_view_resized()` 均正确设置

### 验收标准
- [ ] 地图生成时小地图显示所有房间节点和连线
- [ ] 玩家进入新房间时小地图高亮点更新到当前房间节点
- [ ] 相邻房间揭示时小地图正确显示新房间节点
- [ ] Godot headless --quit-after 1 编译通过 ✅

### 剩余风险
- `_draw()` 中的玩家位置点偏移计算依赖 `map_rect.size`，当房间网格跨度较大时玩家点可能跳变（需人类试玩确认）
- 小地图玩家位置跟随的实际精度需在 RoomGameMode map_generated 信号发出后才能验证

### 下轮最可能方向
1. PH11大地图小地图实际运行验证（RoomGameMode map_generated信号发出时机 + 小地图节点数据正确性）
2. RoomBoss.tscn接入DemoRoomChain验证Boss战完整流程
3. 继续polish其他边界问题
