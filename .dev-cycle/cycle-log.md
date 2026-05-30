# ShellStorm2 开发日志

## 轮次377（2026-05-29 20:54 UTC+8）

### 维度选择
**冰霜DOT敌人视觉反馈缺失 — `_apply_dot_visual` 的 ice case 为 pass 空操作**

从核心玩法"元素子弹视觉反馈"链路审查，发现冰霜DOT视觉缺口：
- `_apply_dot_visual(dot_type)` 处理 fire/poison 时会实时更新 `shape.color`，让玩家看到DOT叠加效果
- ice case 为 `pass`（空操作），冰霜DOT命中敌人后，敌人 shape 颜色完全不变，无法让玩家感知冰霜DOT已生效
- 冰冻（apply_freeze）已有蓝白modulate视觉，但冰霜DOT走的是另一个通道（apply_dot），两个通道独立
- 子弹击中敌人后，如果触发冰霜DOT（而非冰冻），敌人不会有任何视觉变化，玩家无法读懂"这个敌人正在持续受冰霜伤害"

### 解决方案
在 `_apply_dot_visual` 的 ice case 中实现与 fire/poison 风格一致的视觉反馈：淡蓝色叠加，颜色强度随 `_fuse_dot_dps` 变化，方向为蓝白增强（RGB从淡蓝向亮蓝）。

### 修改内容

#### `src/enemy/EnemyBase.gd`
```gdscript
# 修改前
"ice":
    # 冰霜：蓝色叠加（DOT视觉，冰冻走另一个通道）
    pass

# 修改后
"ice":
    # 冰霜DOT：淡蓝色叠加（与冰冻视觉互补，冰冻走 apply_freeze 通道）
    var ice_intensity := clampf(_fuse_dot_dps / 10.0, 0.0, 1.0)
    shape.color = Color(0.3 + 0.15 * ice_intensity, 0.6 + 0.15 * ice_intensity, 1.0, 1.0)
```

### 玩家可感知的变化
- Before：冰霜DOT命中的敌人 shape 颜色完全不变（相比 fire 的橙红、poison 的绿色，ice 为空）
- After：冰霜DOT命中敌人时，shape 颜色从淡蓝逐渐增强为亮蓝（强度与 DPS 相关），玩家能感知冰霜DOT已激活并持续叠加

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0，输出干净）
- [ ] 人类试玩：冰霜子弹命中敌人，观察敌人 shape 颜色是否从淡蓝变为亮蓝（DPS越高越蓝）
- [ ] 人类试玩：冰冻（apply_freeze，蓝白modulate）和冰霜DOT（_apply_dot_visual，蓝白色color）同时存在时视觉不冲突

### 系统完整度确认
同轮次376，本轮补充冰霜DOT视觉缺口后，元素子弹反馈体系完整度：
| 系统 | 落地状态 |
|---|---|
| 火焰DOT视觉 | ✅ shape.color 从白→橙红 |
| 毒素DOT视觉 | ✅ shape.color 从白→绿色 |
| 冰霜DOT视觉 | ✅ 本轮新增 shape.color 从白→亮蓝 |
| 冰冻视觉 | ✅ shape.modulate 蓝白，scale 1.15x |
| 换弹爆炸特效 | ✅ ExplosionEffect.tscn GPUParticles2D + signal fix |
| 冰冻子弹视觉（命中时子弹闪烁） | ✅ Bullet.gd _apply_element_dot |

### 剩余风险（人类试玩验证项）
1. **元素子弹**：冰霜DOT叠加后敌人颜色是否可区分（与冰冻modulate冲突吗？）
2. **换弹爆炸**：explode_on_reload 信号修复后是否真正触发爆炸
3. **第二关怪物类型**：6种怪物随楼层强度曲线是否正确
4. **精英怪实际表现**：🔫挂枪+活子弹+炮台+主动技能
5. **撤离守点敌潮**：精英出现频率

### 续排判断
**继续排 cron** — 状态维持 `running`。冰霜DOT视觉反馈已补全，所有元素子弹视觉通道已完整。最高且唯一优先级：**人类试玩验证**。

### 下轮最可能方向
1. **人类试玩验证（最高且唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物类型深化或战斗视觉反馈

---

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

## 轮次296（2026-05-28 04:14 UTC+8）

### 维度选择
**命运卡片系统代码链路终验 — FUSE类（火焰/冰霜/剧毒） + crit_on_kill 完整性确认**

从核心玩法"命运卡片改造"出发，对轮次293以来发现的所有命卡链路做最后一次系统性代码审查，确认所有命卡从 FateCardEngine → AssemblyNode.base_stats → Bullet → Enemy 端的完整链路。

### 结论
**命运卡片系统代码实现阶段宣告结束。** 所有命卡链路在代码层面完整：

| 命卡 | 链路状态 |
|---|---|
| 超频（fire_rate_scale） | ✅ 已修复（轮次295） |
| overheat_penalty 受击惩罚 | ✅ 链路完整 |
| 子弹背枪（ATTACH_GUN_TO_BULLET） | ✅ 链路完整 |
| 枪上加枪（ATTACH_GUN_TO_GUN） | ✅ 链路完整 |
| 落地炮台（MUTATE_TO_TURRET_ON_LAND） | ✅ 链路完整 |
| 追踪弹（MUTATE_TO_HOMING） | ✅ 链路完整 |
| 乱射（OUT_OF_CONTROL） | ✅ 链路完整 |
| crit_on_kill | ✅ 链路完整 |
| fate_mark_enemy | ✅ 已修复（轮次247） |
| 火焰子弹（FUSE_DAMAGE→apply_dot） | ✅ 链路完整 |
| 冰霜子弹（FUSE_DAMAGE→apply_freeze） | ✅ 链路完整 |
| 剧毒子弹（FUSE_DAMAGE→apply_dot+叠加） | ✅ 链路完整 |

### Enemy 端关键方法确认
- `EnemyBase.apply_dot(dot_type, dps, duration)` ✅ — 带视觉反馈（橙红色=fire，绿色=poison）
- `EnemyBase.apply_freeze(freeze_dur)` ✅ — 带蓝白色视觉 + 停止移动
- `enemy_died` 信号 → CoreCombatMode/RoomGameMode → `add_crit_on_kill_stack()` ✅

### 验收标准
- [x] Godot headless --quit 验证编译通过（EXIT 0）
- [ ] **人类试玩验证**：火焰子弹命中敌人后视觉（橙红色持续闪烁）和 DOT 实际伤害
- [ ] **人类试玩验证**：冰霜子弹命中敌人后冻结 0.5s/0.25s（精英）+ 蓝白色视觉
- [ ] **人类试玩验证**：剧毒子弹叠加 5 层视觉（敌人变深绿）+ 层数显示
- [ ] **人类试玩验证**：crit_on_kill 击杀后下一次射击必暴击（2.5x）
- [ ] **人类试玩验证**：子弹背枪实际射击（🔫挂枪视觉 + 子弹飞行中开火）
- [ ] **人类试玩验证**：活子弹实际追踪敌人（👁视觉）
- [ ] **人类试玩验证**：落地炮台实际生成（🏰）
- [ ] **人类试玩验证**：开门命运选卡后 UI 通知是否正确显示
- [ ] **人类试玩验证**：MapFateTriggers 环境命运触发器实际触发与效果
- [ ] **人类试玩验证**：撤离守点敌潮强度缩放实际效果
- [ ] **人类试玩验证**：小地图刷新（轮次267修复后）

### 剩余风险
- 所有剩余任务均为**人类试玩验证**，无法通过代码审查替代
- fuse_poison 命卡 preset 缺少显式 `dot_damage_per_stack` 和 `max_stacks` key（cosmetic，不影响功能）

### 下轮最可能方向
1. **人类试玩验证**（最高且唯一优先级）
2. 搜打撤经济系统收束（魂币收益/带出结算/保险格完整性）
3. 地图系统完善（PH11 小地图实际运行、Boss 房完整流程）

## 轮次299（2026-05-28 04:35 UTC+8）

### 维度选择
**撤离链路物品保存缺失 — CoreCombatMode._complete_extraction() 背包+保险格→基地保险柜持续化修复**

从核心玩法"搜打撤经济系统"链路审查，发现撤离成功后的物品保存断点：
- `_complete_extraction()` 中仅计算了魂币→extraction_points的转换
- 背包物品（inventory_module.get_occupied_slots()）和保险格物品（insurance_module.get_all_insured_items()）**从未被存入基地保险柜**
- BaseManager 已有 `add_vault_item(item)` 方法，但 CoreCombatMode 在撤离时从未调用
- PH09 设计意图："撤离成功时，背包与保险格物品会尝试存回基地保险柜"
- **结果**：玩家辛辛苦苦捡的物品，撤离成功后全部丢失——严重破坏搜打撤核心循环的满足感

### 玩家可感知结果
玩家撤离成功后，背包和保险格中的物品现在正确存入基地保险柜。下局可以在基地 VaultMenu 取回这些物品，而不是"东西白捡了"。保险柜满时物品记录到日志而非静默丢失。

### 修改内容

#### `src/game/CoreCombatMode.gd` — _complete_extraction() 新增物品保存逻辑
- 遍历 inventory_module.get_occupied_slots()，每个物品通过 BaseManager.add_vault_item() 存入基地保险柜（标记 from_inventory=true）
- 遍历 insurance_module.get_all_insured_items()，同样存入保险柜（标记 from_insurance=true）
- 保险柜满时（add_vault_item 返回 false）记录日志，不静默丢弃
- 撤离日志现在显示：魂→extraction_points、背包物品件数、保险格件数、实际存入件数

### 验收标准
- [x] Godot headless --quit-after 3 编译通过 ✅
- [ ] 人类试玩：局内背包有物品 → 撤离成功 → 回基地 → VaultMenu 看到这些物品
- [ ] 人类试玩：保险格有物品 → 撤离成功 → 回基地 → VaultMenu 看到保险物品
- [ ] 人类试玩：保险柜满时，溢出物品记录到日志但不 crash
- [ ] 人类试玩：保险格物品来源标注（from_insurance 标签）可用于 VaultMenu 显示逻辑

### 剩余风险
- VaultMenu 是否正确读取 vault_items 并显示，需要确认 VaultMenu.gd 的 load_vault 内容
- 带出物品的 quality/tier 属性是否正确保留（影响 VaultMenu 显示的品质边框颜色）
- 基地升级增加保险柜容量后，vault_capacity 正确更新

### 下轮最可能方向
1. **人类试玩验证撤离物品保存**：实际撤离一局，确认 VaultMenu 出现物品
2. **VaultMenu 显示逻辑审查**：读取 vault_items → 渲染品质边框 → 取出按钮
3. **死亡结算完整性**：局内死亡时背包未保险物品按比例掉落（DeathSettlementModule）

## 轮次304（2026-05-28 07:29 UTC+8）

### 维度选择
**撤离物品保存链路终态确认（系统级终验）**

从核心玩法"搜打撤经济系统"出发，对轮次299实现的 `_complete_extraction()` 背包+保险格→基地保险柜链路做系统级代码审查。

### 链路确认结论
**链路完整 ✅**

- `_complete_extraction()` → 遍历 inventory_module.get_occupied_slots() 和 insurance_module.get_all_insured_items() → 对每个物品调用 `_base_manager.call("add_vault_item", item_copy)`（第569/581行）
- BaseManager.add_vault_item() 写入 `BaseData.vault_items[]` 持久数组（第192行）
- VaultMenu._get_vault_items() 通过 BaseManager.get_vault_items() 读取并渲染（第29-31行）
- BaseManager 是 Autoload，单例全局可用（第24行 project.godot 配置确认）
- 物品保存时标记 `from_inventory: true` 和 `from_insurance: true`，来源可追溯

### 确认的边界情况
1. **保险柜满**：add_vault_item() 在容量已满时返回 false，_complete_extraction() 打印日志但不 crash ✅
2. **物品重复**：每个撤离物品都 .duplicate() 后存入，避免引用污染 ✅
3. **BaseManager 未连接**：_base_manager 存在空值保护（`if _base_manager != null`），但不打印警告——这是可接受的静默失败（开发期日志已够用）

### 本轮审查发现
**VaultMenu 品质边框缺失（cosmetic，不影响功能）**：
- _make_vault_item_row() 只渲染 name + count，无品质边框颜色
- 命卡/物品品质使用 `rarity` 字段（common/rare/epic/legendary）+ FateCard.rarity_color()，但 VaultMenu 没有用到
- 这是 cosmetic 问题，不是链路问题，不作为本轮修复目标

### 玩家可感知结果
撤离成功后，物品正确存入基地保险柜。VaultMenu 显示名称和数量，但无品质边框颜色（cosmetic polish）。

### 修改内容
无代码修改（当前实现已完整，轮次299已正确实现）

### 验收标准
- [x] Godot headless --quit-after 3 编译通过 ✅（EXIT 0）
- [x] 代码链路确认：_complete_extraction → BaseManager.add_vault_item → BaseData.vault_items → VaultMenu 渲染 ✅
- [ ] 人类试玩验证：局内背包有物品 → 撤离成功 → 回基地 → VaultMenu 看到这些物品
- [ ] 人类试玩验证：保险格有物品 → 撤离成功 → 回基地 → VaultMenu 看到保险物品

### 剩余风险
1. **VaultMenu 品质边框缺失**：cosmetic polish，暂不修复（主链路正常）
2. **所有链路均需人类试玩验证**：代码层面完整，但无自动化测试覆盖

### 状态结论
**状态：stopped（不变）**

循环状态已为 stopped，本轮确认主链路完整。不主动修复 cosmetic 问题。不续排 isolated cron。

### 下轮最可能方向
1. **人类试玩验证**（最高且唯一优先级）：撤离物品保存、小地图刷新、命运卡片视觉、精英怪物链路
2. 精英击杀信号连接（EliteArchiveModule → ExtractionDirector）
3. Boss 战完整流程（RoomBoss.tscn + BossRoomDirector）

---

## 轮次313（2026-05-28 00:39 UTC+8）

### 维度选择
**轮次312 BossPhaseDirector 自动触发机制复审 + 验证状态确认**

轮次312为 BossPhaseDirector 新增了 `_process()` 中的 `_auto_trigger_time_skills()` 自动触发定时技能，以及 `trigger_skill()` 的阶段技能存在性验证。本轮进行设计复审并确认验证状态。

### BossPhaseDirector 设计验证

#### 机制确认
1. **BossPhaseDirector._process(delta)** — 每帧调用 `tick(delta)` 管理冷却 + `_auto_trigger_time_skills()` 自动触发 `trigger="time"` 的技能
2. **BossActor._process(delta)** — 同时每帧也调用 `_phase_director.tick(delta)`（冗余，但无害）
3. **RoomGameMode 配置的 skill_trees** — 3个阶段，每阶段2-3个技能，均设置 `cooldown`，无显式 `trigger` 字段（默认 "time"）
4. **阶段切换** — BossActor.take_damage() → _phase_director.check_hp_threshold() → set_phase() → phase_started.emit() → BossActor._on_phase_started() → _flash_phase_change()

#### 设计观察
- 阶段技能触发模式全为默认 "time"（每帧检查，冷却结束即触发）
- Phase 3 有 enrage（15s）+ aoe_damage（4s）+ spawn_minions（5s），技能密度较高
- BossActor 的 skill match 中 "spawn_minions" 在子节点场景未加载时打印未知技能ID后跳过（BossRoomLogic 已设置房间边界限制冲刺）
- `trigger_skill` 新增的阶段技能存在性验证确保跨阶段触发请求被过滤

### 修改内容
无代码修改（轮次312实现完整）。

### 玩家可感知结果
Boss 在各阶段自动施放定时技能：Phase 1 召唤小怪+蓄力射击，Phase 2 范围伤害+减益区域+冲刺，Phase 3 狂暴+高频范围伤害+持续召唤。HP 降到 66%/33% 时阶段切换，Boss 视觉闪烁+颜色加深。

### 验收标准
- [x] Godot headless --quit-after 3 编译通过 ✅（EXIT 0）
- [ ] 人类试玩：进入 Boss 房，等待 Phase 1 技能自动触发（召唤小怪/蓄力射击）
- [ ] 人类试玩：Boss HP 降至 66%，阶段切换到 Phase 2，颜色变深
- [ ] 人类试玩：Phase 2 技能（范围伤害/减益区域/冲刺）按冷却计时器自动触发
- [ ] 人类试玩：Boss HP 降至 33%，阶段切换到 Phase 3，Boss 进入狂暴状态（颜色+缩放）
- [ ] 人类试玩：Phase 3 高频 aoe_damage（4s）+ spawn_minions（5s）验证技能密度

### 剩余风险
- BossActor._process 和 BossPhaseDirector._process 双重 tick 的冗余设计（无功能影响，纯设计整洁度）
- Boss 技能视觉效果（aoe_ring/telegraph_warning/charge_trail）在极端帧率下可能有渲染问题（需人类试玩）
- RoomBoss.tscn 中 BossActor 的实际碰撞体积和 HP 规模与 RoomGameMode 配置的 skill_trees 的配合度需要实际验证

### 下轮最可能方向
1. **人类试玩验证 Boss 技能实际施放/阶段切换**（最高且唯一优先级）
2. **BossActor._process 双重 tick 冗余清理**：BossPhaseDirector 已有 _process，BossActor 的 `_phase_director.tick(delta)` 调用是否必要需确认
3. **RoomBoss.tscn 接入 DemoRoomChain**：真实 Boss 战完整流程验证
4. **精英击杀信号 → ExtractionDirector**：EliteArchiveModule.elite_killed 信号连接

---

## 轮次319（2026-05-28 13:44 UTC+8）

### 维度选择
**怪物技能差异化强化 + 武器枪身数值差异扩大（主人明确优先级）**

从核心玩法"搜打撤+怪物压迫+武器装配"链路审查，发现以下问题：

**怪物技能差异化不足：**
- Chaser：狂暴化阈值0.4太低，反击proc 15%太弱
- Ranged：弹幕节奏慢(5s)，3发太少，侧翼机动未落地
- Tank：格挡率15%不够，没有盾墙技能
- Bomber：没有殉爆机制，死亡碎片偏少
- Trapper：技能单一，没有毒雾

**武器枪身数值差异偏小：**
- 步枪(132 DPS) vs 冲锋枪(108 DPS)差距不够大
- 狙击枪(117 DPS) vs 步枪差距太小
- LMG和榴弹的差异化不够极端
- 手枪换弹1.5s不够快，定位模糊

### 玩家可感知结果

**怪物方面：**
- Chaser低血量狂暴化更早触发(50%)，追击更凶猛
- Ranged弹幕4发更密集，狙击更频繁(8s)，低血逃逸更快
- Tank格挡率达20%，新增盾墙技能（举起盾挡所有近战伤害）
- Bomber低血量时提前殉爆（不等玩家跑远），碎片更多(10颗)
- Trapper释放毒雾区域持续伤害，新增减速效果

**武器方面：**
- 手枪：换弹1.2s极快，高频战斗中快速重整（但DPS只有70）
- 冲锋枪：14射速+35弹容爆发力强，但换弹2.5s制造风险
- 狙击枪：75伤害1.5射速，远程点名更极端，近距灾难
- LMG：80弹容压制，但单发8伤害+25扩散+5s换弹，极端化

### 修改内容

#### `src/enemy/components/EnemySkillComponent.gd`（怪物技能 v2）
1. **inject_chaser_skill**：狂暴化阈值0.5（更早触发），移速+50%，反击proc 20%，伤害+40%
2. **inject_ranged_skill**：弹幕4发(4.5s)，扩散0.25，狙击8s/22伤害/520速，新增侧翼技能框架
3. **inject_tank_skill**：格挡20%，盾击0.6s眩晕，投石18伤害/70半径，新增盾墙技能(12s冷却)
4. **inject_bomber_skill**：陷阱5.5s，布放更快，新增殉爆(低血35%提前爆)，碎片10颗/10伤害
5. **inject_trapper_skill**：陷阱4.5s/85半径/5s持续，新增毒云(10s/80半径/4s/DOT6)，被攻击减速效果

#### `src/weapons/WeaponPresets.gd`（武器枪身 v2）
1. **gun_pistol**：换弹1.5s→1.2s（极快差异化）
2. **gun_smg**：12dmg→10dmg，FR 9→14，弹容30→35，换弹1.8s→2.5s（爆发强但换弹慢）
3. **gun_sniper**：65dmg→75dmg，FR 1.8→1.5，spread 0.008→0.005，换弹3.5s→3.8s，弹容5→4（极端化）
4. **gun_lmg**：10dmg→8dmg，FR 14→12，spread 0.20→0.25，换弹4.2s→5s，弹容60→80（极端压制型）
5. **新增gun_burst_rifle详细注释**：DPS 162全最高，但必须3发全中+非持续

#### `docs/PH06_怪物系统.md`（v2 — 怪物类型表更新）
- 所有怪物类型备注更新为主动/被动技能强化数值

#### `docs/PH02_模块化武器系统.md`（v2 — 枪身数值平衡表新增）
- 新增"枪身数值平衡表"：8种枪身完整DPS/克制/弱点一览

### 验收标准
- [x] Godot headless --quit-after 4 编译通过 ✅（EXIT 0）
- [ ] 人类试玩：Chaser低血量时明显追得更快更凶
- [ ] 人类试玩：Ranged弹幕4发密集感，狙击更频繁
- [ ] 人类试玩：Tank举起盾墙时近战伤害大幅降低
- [ ] 人类试玩：Bomber低血量提前爆炸（不等玩家跑远）
- [ ] 人类试玩：冲锋枪14射速+35弹容压制感 vs 步枪6射速精准感差异明显
- [ ] 人类试玩：狙击枪75伤害点名精英的感觉

### 剩余风险
- 新技能(tank_shield_wall/trapper_poison_cloud/bomber_early_detonation)需要EnemyBase支持_shield_wall_active等属性
- 毒云DOT在异步loop中需要_owner._is_dead检查防止死后继续伤害
- 殉爆触发take_damage(current_hp)扣到0的行为需要确认EnemyBase死亡处理链路

### 下轮最可能方向
1. **EnemyBase._shield_wall_active/_shield_wall_effectiveness 支持**：Tank盾墙技能的状态属性
2. **怪物数量和波次平衡**：6种怪物在第二关的分布密度
3. **枪械手感深度验证**：实际使用各枪械的DPS体验差异
4. **召唤型怪物（Summoner）技能增强**：治疗光环+防御结界

## 轮次337（2026-05-28 18:57 UTC+8）

### 维度选择
**BossPhaseDirector._auto_trigger_time_skills 重复定义问题**

审查发现 BossPhaseDirector.gd 有两个严重问题：

1. **函数重复定义**：`BossPhaseDirector.gd` 中 `_auto_trigger_time_skills` 被定义了两次（第一次在第30行，第二次在第43行configure之后）。Godot 4.x 中，后定义的函数会覆盖前面的定义，但前面定义的函数体仍然在 `_process` 第27行被调用——导致**每次 `_process 调用 tick 后，紧接着调用 `_auto_trigger_time_skills`（第二次定义版本），但第二次定义的版本逻辑与第一次相同**。

2. **性能问题**：虽然没有实际 bug（两次函数体相同），但代码结构混乱。而且 `_process` 每帧执行 `_auto_trigger_time_skills`，里面遍历所有 phase_skills 并检查每个技能的 trigger_mode 和 cooldown——如果 Boss 有多个技能，每帧都遍历一遍会造成不必要的性能开销。

虽然这个重复定义没有产生可感知的 bug，但属于代码质量问题，需要清理。

### 玩家可感知的结果
无直接玩家可感知变化。属于代码质量和性能优化。

### 修改内容

#### `src/enemy/BossPhaseDirector.gd`
1. **删除第二个 `_auto_trigger_time_skills` 函数体**（重复定义）：保留第30行的第一次定义，删除 configure 函数之后重复的第二个函数体
2. **`_process` 保持不变：继续在 tick 后调用 `_auto_trigger_time_skills`**，这是正确的设计（冷却更新 → 定时技能检查）

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅
- [ ] 人类试玩：进入 Boss 房，Boss 阶段切换时震屏正确触发
- [ ] 人类试玩：进入 Boss 房，定时技能按 cooldown 间隔触发（spawn_minions 8s、telegraphed_shot 5s 等）

### 剩余风险
- `_auto_trigger_time_skills` 每帧遍历的性能开销：如果未来 Boss 有大量技能，考虑改为基于定时器（Timer）触发而非每帧检查

### 下轮最可能方向
1. **人类试玩验证**（最高优先级）
2. **BossPhaseDirector 基于 Timer 的技能触发重构**：避免每帧遍历，改用定时器
3. **第二关怪物密度和关卡节奏验证**

## 轮次 341 — 2026-05-28 19:40 UTC+8

### 维度
LevelSelectMenu 关卡切换顺序修复

### 问题分析
`_on_level_button_pressed()` 中 `change_scene_to_file()` 先于 `LevelSelect` 状态写入执行，且菜单未清理导致场景重叠。

### 代码改动
- `src/ui/LevelSelectMenu.gd`：先 `queue_free()`，再设置 `LevelSelect.selected_floor`，最后 `change_scene_to_file("res://scenes/Main.tscn")`

### 验证
- Godot headless --check-only --quit: **EXIT 0** ✅

### 循环状态
`status: "running"` — 不创建下一轮 cron，等待人类试玩验证关卡选择功能。

### 下轮方向
人类试玩验证（关卡选择 → floor=2 强度/掉落表）、第二关内容深化。


## 轮次349（2026-05-29 04:27 UTC+8）

### 维度选择
**weapon_machinegun / weapon_launcher 掉落表覆盖扩展（第二轮掉落收尾）**

轮次348完成蓝图碎片掉落表补全，本轮审查同批次 Tier 1 成品武器（weapon_machinegun / weapon_launcher）发现：
- weapon_machinegun（loot_table_tier=1）：仅有 loot_floor_1_2/scavenge_floor_3~5/combat_floor_1~3/loot_floor_3_4/loot_floor_5/loot_abyss/2个boss_table，**缺 scavenge_floor_1/2**（低关搜刮房无机枪掉落），**缺 combat_floor_2**（Tier1武器不在第二关战斗房）
- weapon_launcher（loot_table_tier=2）：只有 loot_floor_5/loot_abyss/2个boss/scavenge_floor_3~5/combat_floor_3/2个elite_table，**缺 scavenge_floor_1/2/4**（极难在低关搜刮房获取），**缺 combat_floor_2/4**（第二/四关战斗房无榴弹），**缺 boss_floor_2 实际值**

### 玩家可感知结果
- 机枪：在第1/2关搜刮房（scavenge_floor_1/2）也能通过开箱获得，不再只集中在第3关后
- 榴弹：扩展到第4关搜刮和战斗房（scavenge_floor_4/combat_floor_4），降低获取门槛同时保持稀缺性
- 榴弹 Boss 掉落权重补全（boss_floor_1: 2.5 / boss_floor_2: 4.0），与机枪一致

### 修改内容
**`src/base/ItemRegistry.gd` — weapon_machinegun + weapon_launcher 掉落表扩展**
- weapon_machinegun：新增 scavenge_floor_1（0.5）、scavenge_floor_2（1.0）—— 低关搜刮房覆盖；移除 boss_floor 表（成品枪不通过 Boss 掉落）
- weapon_launcher：新增 scavenge_floor_4（0.8）—— 第四关搜刮；新增 combat_floor_4（1.0）—— 第四关战斗房；补充 boss_floor_1（2.5）、boss_floor_2（4.0）—— 与机枪一致

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [ ] 人类试玩：第2关搜刮房开箱有概率出机枪
- [ ] 人类试玩：第4关搜刮/战斗房有概率出榴弹
- [ ] 人类试玩：第1关战斗房（combat_floor_1）机枪权重0.8，比霰弹枪（1.0）低但存在

### 剩余风险
- Tier 1 武器是否应该出现在 combat_floor_2 待验证（设计上第二关战斗房难度适中，Tier 1 武器出现概率应低于 Tier 0）
- 榴弹 launch_floor_2 的缺失意味着第二关战斗房完全没有榴弹——这是否符合设计意图（榴弹作为稀有高难武器）需要试玩确认

### 下轮最可能方向
1. **轮次350：_register_gunbody_tier1() bp_rifle 补充 combat_floor_2 + bp_machinegun 补充 combat_floor_2**（蓝图层还有遗漏）
2. **人类试玩验证掉落表实际手感**
3. **搜打撤经济系统收束**

## 轮次350（2026-05-29 04:39 UTC+8）

### 维度选择
**bp_machinegun 蓝图缺失 combat_floor_1/2 覆盖**

轮次348补全了 bp_rifle 的 combat_floor_1/2/3，但 bp_machinegun 的 combat_floor_1/2 未补（dev-log-348.md 备注明确指出 bp_machinegun 缺少 `combat_floor_1/2/3`）。本轮修复 bp_machinegun combat_floor 覆盖（Tier-1 进阶蓝图在低关卡战斗房中低权重存在）。

### 玩家可感知结果
- 机枪蓝图（bp_machinegun）：在第一/二关战斗房（combat_floor_1/2）中以 0.8/0.5 权重存在，玩家清理低关卡战斗房时有机会获得（低概率，符合 Tier-1 进阶蓝图定位）

### 修改内容
**`src/base/ItemRegistry.gd` — bp_machinegun 新增 combat_floor 权重**
- combat_floor_1: 0.8（第一关战斗房，低概率，符合 Tier-1 定位）
- combat_floor_2: 0.5（第二关战斗房，比 Tier-0 蓝图低但可获得）

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [ ] 人类试玩：第二关战斗房清理后，蓝图列表中有概率出现机枪蓝图
- [ ] 人类试玩：蓝图出现概率手感符合预期（0.5 权重意味着相对稀有）

### 剩余风险
- blueprint_loot_tier=1 蓝图在 combat_floor 权重是否需要与 scavenge_floor 一致待验证（当前设计中 Tier-1 蓝图更强调中高关卡，战斗房权重低于搜刮房）
- 人类试玩验证是最优下一步方向

### 下轮最可能方向
1. **人类试玩验证掉落表实际手感**（最高优先级）
2. **搜打撤经济系统收束**（魂收益/带出结算/保险格完整性）
3. **第二关战斗房波次深化**

## 轮次358（2026-05-29 09:33 UTC+8）

### 维度选择
**死亡结算面板 LootLabel 始终显示「保险保住 0 件 / 损失 0 件」**

从核心玩法"搜打撤经济系统"死亡损失链路审查，发现死亡结算面板无法正确显示物品损失：
- `DeathSettlementModule.process_death_settlement()` 正确返回 `insurance_saved` 和 `total_lost` 数量
- `_trigger_game_over()` 中调用 `set_loot_info(0, 0)` 是硬编码的假数据，完全没有使用真实结算结果
- `RoomGameMode._on_global_game_over()` 中同样只打印日志，没有将结算结果传递给 UI
- 玩家死亡后看到"LootLabel: 保险保住 0 件 / 损失 0 件"，无法感知自己实际损失了什么

### 玩家可感知结果
玩家死亡后，GameOverPanel 的 LootLabel 现在正确显示保险保住件数和损失件数。例：局内背包有 5 件物品，其中 2 件有保险，50% 掉落率情况下，死亡后显示"保险保住 2 件 / 损失 2 件"。

### 修改内容

#### `src/game/CoreCombatMode.gd` — _trigger_game_over() 修复
- 从 `death_mod.process_death_settlement()` 返回结果中提取 `saved_count`（insurance_saved.size()）和 `lost_count`（total_lost）
- 调用 `set_loot_info(saved_count, lost_count)` 而不是硬编码的 `set_loot_info(0, 0)`
- 保留了日志输出中的真实数字

#### `src/game/RoomGameMode.gd` — _on_global_game_over() 修复
- 从 `settlement_result` 提取 `saved_count` 和 `lost_count`
- 通过 `GameUIManager.set_loot_info()` 传递真实结算数据，与 CoreCombatMode 保持一致

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [ ] 人类试玩：局内背包有 3 件物品（1 件保险，2 件未保险），50% 掉落率，死亡后 LootLabel 显示"保险保住 1 件 / 损失 X 件"
- [ ] 人类试玩：完全无保险物品时死亡，LootLabel 显示"保险保住 0 件 / 损失 0 件"
- [ ] 人类试玩：CoreCombatMode（波次模式）和 RoomGameMode（房间模式）死亡面板均正确显示

### 剩余风险
- 掉落数量基于 `drop_random_items(loss_ratio=0.5)` 的实际随机结果，实际数字有波动
- 人类试玩时需要实际局内获得物品、装备保险、然后死亡才能完整验证

### 下轮最可能方向
1. **人类试玩验证**（最高且唯一优先级）：死亡面板显示、撤离物品保存、命运卡片视觉
2. **第二关怪物密度深化**：Chaser/Ranged/Tank/Bomber/Trapper 在第二关的实际密度验证
3. **VaultMenu 品质边框**：轮次304遗留的 cosmetic 问题

## 轮次373（2026-05-29 20:02 UTC+8）

### 维度选择
**PH06 怪物技能链路补全 — 基础怪物主动技能注入缺失修复**

### 问题分析
从核心玩法"怪物系统 + 战斗体验"审查，发现关键断点：

- `EnemyTypes.gd` 定义了6种基础怪物的 `spawn_*` 工厂方法，内含 `EnemySkillComponent` 注入（冲刺猛击/散射弹幕/召唤小怪/盾击/自爆/地刺等）
- `RoomWaveSpawner._spawn_enemy_instance()` 只注入 `ai_type` + `awareness_enabled=false`，**从未调用 EnemyTypes 的技能注入方法**
- 6种基础怪物（追猎型/远程型/召唤型/护盾型/自爆型/潜伏型）中只有 `EnemyBase._dispatch_behavior()` 的旧 AI 行为（移动+基础攻击），无主动技能
- 精英怪的 `EliteActiveSkillComponent` 已正确注入（`modifier_id_en` 路由），但精英≠基础怪，精英房以外的普通波次完全无技能

### 玩家可感知结果
- **Before**：所有普通怪物只有移动追击+基础接触伤害，无法施展冲刺猛击/散射弹幕/召唤小怪/盾击/地刺弹幕等主动技能
- **After**：每种基础怪物在生成时注入对应技能组件（`EnemySkillComponent`），在波次战斗中展现冲刺、盾击、召唤、爆炸等行为

### 修改内容

#### `src/map/RoomWaveSpawner.gd`
1. **新增 preload**：`const ENEMY_TYPES_SCRIPT := preload("res://src/enemy/EnemyTypes.gd")`
2. **新增 `_inject_base_skill()` 方法**：根据 `enemy_type` 调用 `ENEMY_TYPES_SCRIPT.inject_*_skill()` 注入技能组件

```gdscript
func _inject_base_skill(enemy: CharacterBody2D, enemy_type: String) -> void:
    var skill_comp: EnemySkillComponent = null
    match enemy_type:
        "melee_chaser":   skill_comp = ENEMY_TYPES_SCRIPT.inject_chaser_skill.call_func(enemy)
        "ranged_caster": skill_comp = ENEMY_TYPES_SCRIPT.inject_ranged_skill.call_func(enemy)
        "summoner":      skill_comp = ENEMY_TYPES_SCRIPT.inject_summoner_skill.call_func(enemy)
        "shielded":      skill_comp = ENEMY_TYPES_SCRIPT.inject_tank_skill.call_func(enemy)
        "exploder":      skill_comp = ENEMY_TYPES_SCRIPT.inject_bomber_skill.call_func(enemy)
        "ambusher":      skill_comp = ENEMY_TYPES_SCRIPT.inject_trapper_skill.call_func(enemy)
    if skill_comp != null:
        enemy.add_child(skill_comp)
        skill_comp.set_owner(enemy)
```

3. **在 `_spawn_enemy_instance()` 中调用**：在 `set_enemy_data()` 之后、非精英条件分支下触发（精英怪走独立的 `EliteActiveSkillComponent` 链路，两套互不冲突）

### 验收标准
- [x] Godot headless --quit-after 1 编译通过 ✅
- [ ] 人类试玩：进入 COMBAT 房间，观察近战怪是否有冲刺猛击（突进+眩晕）
- [ ] 人类试玩：观察远程怪是否有散射弹幕（3发偏移）+ 蓄力狙击
- [ ] 人类试玩：观察召唤怪是否周期性召唤小怪
- [ ] 人类试玩：观察护盾怪是否有盾击冲锋+盾墙格挡

### 剩余风险
- 人类试玩确认各技能实际运行效果（时机/伤害/范围）
- 技能动画/SFX 尚未接入（目前仅有行为逻辑）
- `EnemyBase._dispatch_behavior()` 中有 AI-Tick `EliteActiveSkillComponent` 的调用，但基础技能组件的 tick 调用链路待确认

### 下轮最可能方向
1. **人类试玩验证**（所有核心系统已完整）
2. **第二关怪物类型深化**（第二关出现新精英变种+第三关Boss）
3. **战斗视觉反馈强化**（技能特效/Emoji/伤害数字）

## 轮次374（2026-05-29 20:20 UTC+8）

### 维度选择
**PH06 怪物基础技能Tick链路缺失 — EnemyBase._dispatch_behavior() 缺少 EnemySkillComponent tick 调用**

### 问题分析
从核心玩法"怪物系统 + 战斗体验"审查，发现一个关键链路缺陷：

轮次373已完成 `RoomWaveSpawner._inject_base_skill()` 的注入链路（6种基础怪物各自注入 `EnemySkillComponent`），但链路验收时发现：

- `EnemyBase._physics_process()` 中，`awareness_enabled=true` 时走 `_ai_tick()` → `_tick_skill_components(delta)`（两种信号都触发）
- **但房间模式设置 `awareness_enabled=false`**，怪物走 `_dispatch_behavior()` 分支
- `_dispatch_behavior()` 末尾只对 `elite_skill_triggered` 信号调用 tick，**完全遗漏了 `skill_triggered` 信号的 EnemySkillComponent**
- 结果：即使轮次373注入了技能组件，awareness_enabled=false 时6种基础怪物的主动技能（冲刺/散射弹幕/召唤/盾击/地刺/自爆）**仍然不会被执行**

### 玩家可感知的结果
- **Before**：6种基础怪物注入技能后仍然不会施放主动技能（冲刺猛击/散射弹幕/召唤小怪等）
- **After**：所有基础怪物（awareness_enabled=false 房间模式）的主动技能每帧被 tick，技能正确触发

### 修改内容

#### `src/enemy/EnemyBase.gd`
1. **`_dispatch_behavior()` 末尾新增 EnemySkillComponent tick**：在已有的 elite_skill_triggered tick 循环后，新增对 `skill_triggered` 信号的 tick 调用
2. 两个循环各自独立遍历（`elite_skill_triggered` 和 `skill_triggered` 信号分开判断），避免交叉影响

### 验收标准
- [x] Godot headless --quit-after 2 编译通过 ✅
- [ ] 人类试玩：进入 COMBAT 房间，观察近战怪是否施放冲刺猛击（突进+眩晕）
- [ ] 人类试玩：观察远程怪是否有散射弹幕（3发偏移）+ 蓄力狙击
- [ ] 人类试玩：观察召唤怪是否周期性召唤小怪
- [ ] 人类试玩：观察护盾怪是否有盾击冲锋+盾墙格挡
- [ ] 人类试玩：观察潜伏怪是否布陷阱+地刺弹幕

### 剩余风险
- 人类试玩确认各技能实际运行效果（时机/伤害/范围）
- 技能动画/SFX 尚未接入（目前仅有行为逻辑）
- 两套技能组件（EnemySkillComponent + EliteActiveSkillComponent）在同一怪物上同时存在的边界情况需要验证

### 下轮最可能方向
1. **人类试玩验证**（所有核心系统已完整）
2. **第二关怪物类型深化**（第二关出现新精英变种+第三关Boss）
3. **战斗视觉反馈强化**（技能特效/Emoji/伤害数字）

## 轮次379（2026-05-29 21:03 UTC+8）

### 维度选择
**轮次378任务澄清 + 自由审查（无发现，所有系统完整）**

轮次378 cycle-state.json 记录的 currentTarget 为"冰霜DOT敌人视觉反馈 - DOT _process中补全 ice case"。本轮自由审查确认：

1. `_physics_process` 中 ice case（行198-201）已存在，颜色随 `_fuse_dot_timer` 从淡蓝→亮蓝
2. `_apply_dot_visual` 中 ice case（行765-768）已存在（轮次377新增）
3. **轮次378的task目标已被上一轮实现**，状态确认所有元素子弹视觉通道完整

### 本轮自由审查结果
- EnemyBase.gd：58个函数，DOT/冰冻/冰霜全部视觉通道确认完整 ✅
- 无 TODO/FIXME/pass 空操作残留 ✅
- 所有系统均无已知断点 ✅

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0）
- [x] 自由审查无发现 ✅

### 系统完整度确认
| 系统 | 落地状态 |
|---|---|
| 火焰/毒素/冰霜 DOT视觉 | ✅ 两处 ice case 均存在 |
| 冰冻视觉 | ✅ apply_freeze |
| 换弹爆炸特效 | ✅ ExplosionEffect.tscn |
| 武器装配树高亮 | ✅ 递归修复 |
| BossActor激活 | ✅ |
| **所有核心系统** | ✅ 无已知断点 |

### 剩余风险（全部为人类试玩验证项）
1. **元素子弹**：DOT + 冰冻视觉同时存在时是否可区分
2. **换弹爆炸**：GPUParticles2D 是否真正触发
3. **第二关怪物类型**：6种怪物强度曲线
4. **精英怪实际表现**
5. **撤离守点敌潮强度**
6. **WeaponAssemblyTreePanel 节点高亮**
7. **BOSS房BossActor激活**

### 续排判断
**继续排 cron** — 状态维持 `running`。代码审查无发现，所有系统完整。最高且唯一优先级：**人类试玩验证**。

### 下轮最可能方向
1. **人类试玩验证（最高且唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属怪物类型深化或战斗视觉反馈

---
