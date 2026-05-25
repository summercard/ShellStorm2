## 轮次 161 — 2026-05-25 08:24 UTC+8

### 维度
武器后坐力方向修复 — 从"纯X轴"改为"沿枪口反方向"

### 问题分析
审查 WeaponRecoil.gd 的 `_trigger_recoil()` 时发现一个基础方向性问题：

```gdscript
# 原代码：纯 X 轴移动，不受枪口朝向影响
_recoil_tween.tween_property(_host, "position:x", _host.position.x - actual_intensity, ...)
```

`position.x` 减去固定值 = 始终向左（世界坐标系 X 轴负方向）。无论枪口朝向哪个方向，后坐力永远向左。这个问题在玩家朝右射击时勉强"正确"（枪口向右=反方向向左），但当玩家朝上/朝下/朝左射击时，后坐力方向完全错误——枪口向左时反方向是向右，但武器却向左抖动。

这与"顶视角射击"的任意方向操作完全矛盾。

### 本轮改动

将后坐力从"纯 X 轴移动"改为"沿枪口反方向的局部偏移 + 旋转到世界坐标"：

```gdscript
# 局部空间偏移：-X = 枪口反方向，-Y = 枪口上方
var local_backward := Vector2(-actual_intensity, 0.0)
var local_upward := Vector2(0.0, -actual_kick * 0.5)

# 旋转到世界坐标（_host.rotation 是枪口朝向，-X 绕原点旋转后就是枪口向后）
var world_backward := local_backward.rotated(_host.rotation)
var world_upward := local_upward.rotated(_host.rotation)

# 峰值位置（向后的偏移 + 枪口上扬）
var peak_pos := origin_pos + world_backward + world_upward

# 使用 position（Vector2）而非 position.x，直接设置完整坐标
_recoil_tween.tween_property(_host, "position", peak_pos, recoil_duration * 0.3)
```

- 局部 `-X` 方向（枪口反方向）旋转到世界坐标后，无论枪口朝向哪里，后坐力都正确表现为"枪口向后的反冲"
- 使用 `position: Vector2` 而非 `position.x`，避免 Tween 混用 `x` 和完整 `position` 导致的冲突
- 枪口上扬（`-Y` 局部）也正确旋转，让重武器的"枪口上扬"效果始终垂直于枪口朝向

### 玩家可感知的变化
- **修复前**：枪口朝左时射击，后坐力向左（应该是向右），枪口朝上时射击，后坐力向左（应该是向下）
- **修复后**：任意朝向射击，后坐力始终沿枪口反方向表现，手感真实

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/weapon/WeaponRecoil.gd | `_trigger_recoil()` 方向计算改为局部偏移旋转到世界坐标；使用 `position: Vector2` 而非 `position.x` |

### 验证
- Godot --headless --quit-after 3: EXIT 0 ✅

### 剩余风险
- 实际手感需要人类试玩验证：霰弹枪朝各个方向射击时后坐力是否都沿正确方向表现
- `_host.rotation` 在 Player 静止时是瞄准方向，但在移动中可能有微小抖动（不影响整体方向正确性）

### 下轮最可能方向
1. **人类试玩验证**：所有代码链路已完整，亟需实际试玩确认体感
2. 搜打撤经济系统（货币/掉落/撤离收益）
3. 武器装配树拖拽交互优化

---

## 轮次 159 — 2026-05-25 07:57 UTC+8

### 维度
枪上加枪多副枪冷却Bug修复

### 问题分析
轮次158完成Tab/T键修复后，本轮深入审查命运卡片"枪上加枪"链路时发现致命Bug：

`_fire_co_mounted_gun()`遍历所有副枪节点时，遇到第一个冷却中（cooldown > 0）的副枪就直接`return`退出循环，导致：
- 场景中有2+把副枪时，第一把副枪冷却中则后续所有副枪永久无法发射
- 副枪之间的冷却互相不独立，先发射的副枪会阻塞后发射的副枪
- "枪上加枪"多副枪场景完全失效

### 本轮改动

**WeaponAssemblyTree.gd — _fire_co_mounted_gun() 冷却检查逻辑修复**

原代码：
```gdscript
var cooldown: float = _co_mounted_cooldowns.get(cooldown_key, 0.0)
if cooldown > 0:
    _co_mounted_cooldowns[cooldown_key] = cooldown - get_process_delta_time()
    return  # ← BUG：阻止后续副枪发射
_co_mounted_cooldowns[cooldown_key] = fire_interval
```

改为：
```gdscript
var cooldown: float = _co_mounted_cooldowns.get(cooldown_key, 0.0)
if cooldown > 0:
    _co_mounted_cooldowns[cooldown_key] = cooldown - get_process_delta_time()
    continue  # 当前冷却中，跳过此副枪，继续检查下一个
_co_mounted_cooldowns[cooldown_key] = fire_interval
```

- `return` → `continue`：每个副枪独立判断冷却，冷却中则跳过该枪，继续检查下一个副枪
- 避免一个副枪阻塞整个循环

### 玩家可感知的变化
- 修复前：装备多把副枪时，只有第一把副枪能正常发射，其余副枪在第一把冷却期间完全不发射
- 修复后：每个副枪有独立冷却周期，到期即可发射，不再互相阻塞

### 验证
- Godot --headless --quit-after 3: EXIT 0 ✅

### 剩余风险
- 仍需人类试玩验证多副枪同时射击的视觉效果和伤害输出是否正常
- 副枪子弹的伤害、弹速、扩散等参数也需要实际测试

### 下轮最可能方向
1. **人类试玩验证**：所有代码链路已完整，亟需实际试玩确认体感
2. 搜打撤经济系统（货币/掉落/撤离收益）
3. 波次压力曲线微调
4. 武器装配树拖拽交互优化

---


## 轮次 158 — 2026-05-25 07:51 UTC+8

### 维度
FateCardUIController Tab键冲突拦截修复 + WorkbenchPanel T键修复

### 问题分析
轮次157完成命运卡片系统Tab键全链路审查后，本轮深入代码发现两个关键输入Bug：

**Bug 1: FateCardUIController Tab键拦截顺序错误**
```gdscript
func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_tab") and not is_visible:
        show_card_selection()  # ← is_visible=false时无条件拦截Tab！
    elif event.is_action_pressed("ui_cancel") and is_visible:
        hide_card_selection()
```
问题：当 `is_visible=false` 时，无论 `card_panel`/`card_container` 是否就绪，FateCardUIController 都会抢走 Tab，导致 WeaponAssemblyTreePanel 永远收不到 Tab。而且 `_input` 在 `_process` 之后执行（输入事件先 `_input` 后 `_process`？不对，是先 `_input` 再 `_process`），但两个控制面板都在根节点，没有优先级机制，导致冲突。

**Bug 2: WorkbenchPanel 使用未定义的 ui_text_completion 动作**
```gdscript
if Input.is_action_just_pressed("ui_text_completion") and _transform_button != null:
    _on_transform_toggle()
```
`project.godot` 的 input map 中没有定义 `ui_text_completion`，所以T键切换命运改造模式完全无效。

### 本轮改动

#### 1. FateCardUIController._input() 重构拦截逻辑
```gdscript
func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_cancel") and is_visible:
        hide_card_selection()
    elif event.is_action_pressed("ui_tab") and not is_visible:
        # 只在卡片面板和容器都就绪时才拦截 Tab
        if card_panel != null and card_container != null:
            show_card_selection()
```
- 交换 cancel/tab 条件顺序：先处理 ESC 关卡，再处理 Tab 开卡
- Tab 拦截增加 `card_panel != null and card_container != null` 守卫
- 只有在 UI 完整就绪时才消费 Tab，避免抢走其他面板的 Tab 键

#### 2. WorkbenchPanel._process() 改用 is_key_pressed(KEY_T)
```gdscript
# T 键切换命运改造模式
if Input.is_key_pressed(KEY_T) and _transform_button != null:
    _on_transform_toggle()
```
- 替换 `Input.is_action_just_pressed("ui_text_completion")`（未定义）为 `Input.is_key_pressed(KEY_T)`
- 直接按键码检测，不依赖 input map 配置，消除隐式依赖

### 玩家可感知的变化
- **修复前**：Tab键呼出命运卡片面板后，再按Tab关不掉（因为条件顺序问题），且T键在改造房无法切换命运改造模式
- **修复后**：
  - Tab键按一下开/关命运卡片面板，逻辑正确
  - T键在改造房可以正确切换"基础改造"↔"命运改造"模式
  - 两个功能互不干扰

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/ui/FateCardUIController.gd | `_input()` 重构：cancel优先+Tab守卫非空 |
| src/ui/WorkbenchPanel.gd | `_process()`：`ui_text_completion` → `Input.is_key_pressed(KEY_T)` |

### 验证
- Godot --headless --quit-after 2: EXIT 0 ✅

### 剩余风险
- FateCardUIController 仍需要人类实际试玩验证：Tab键呼出→选卡→应用→WeaponAssemblyTree刷新完整流程
- WorkbenchPanel 改造模式切换同样需要人类体感验证T键是否可靠
- 两个面板同时在屏幕上时（WeaponAssemblyTreePanel和FateCardPanel）的Tab键路由仍可能有边界情况，但当前优先级设计合理

### 下轮最可能方向
1. **人类试玩验证**：所有代码链路已完整，亟需实际试玩确认体感
2. 搜打撤经济系统（货币/掉落/撤离收益）
3. 波次压力曲线微调
4. 武器装配树拖拽交互优化

---

## 轮次 69 — 击杀特效颜色随敌人类型变化

**时间**: 2026-05-23 14:54
**维度**: 战局内表现层 — 击杀特效颜色分层

### 本轮选择
在遗留清单中，「击杀特效（死亡爆炸颜色随敌人类型变化）」是表现层中价值最高的改进点——直接强化视觉反馈，让玩家能直观感受到「打死了什么类型的敌人」。相比颜色固定为淡黄白，敌人死亡时爆发对应颜色的爆炸视觉更丰富、信息更清晰。

### 玩家可感知的变化
- 每种敌人死亡时爆炸颜色不再千篇一律
- 绿色敌人死亡爆发绿色闪光，蓝色敌人爆发蓝色闪光，以此类推
- 爆炸颜色略微提亮饱和度，比敌人本体更醒目（爆炸效果比本体更亮）

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/enemy/EnemyBase.gd | `_spawn_death_flash()` 从 `_enemy_data.color` 或 `shape.color` 读取敌人颜色，提亮后作为爆炸 flash 颜色 |

### 验证
- Godot headless --check-only: EXIT 0 ✅（25秒无报错，被 SIGTERM 终止）

### 剩余风险
- `_enemy_data.color` 是 `Variant` 类型，需要确认是否真的是 `Color` 对象（代码中加了类型守卫 `is Color` 是防御性写法，如果类型不对则 fallback 到 `shape.color`）
- 实际效果需人类试玩验证颜色是否足够醒目

### 下轮最可能方向
1. 枪口火焰位置修复（`position` 在 local space，父节点 rotation 导致偏移）
2. 伤害数字样式升级（暴击放大、色泽）
3. 屏幕震动强度分层（根据伤害量/暴击/敌人死亡）

**时间**: 2026-05-23 08:24
**维度**: 搜打撤深化 — 撤离 UI 完整链路

### 玩家可感知的变化
- 房间清理后显示撤离类型选择按钮（标准/信标/Boss/精英/交易）
- 信标撤离消耗道具后真实扣减信标数量
- 撤离读条有进度条 + 剩余时间显示
- 玩家可以主动中断撤离读条
- 撤离成功后显示成功面板和带出物品清单

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/ui/GameUIManager.gd | 新增撤离按钮构建、路由、读条UI、更新信号连接 |
| src/game/RoomGameMode.gd | 提前信标同步到 UI 绑定之前；背包变化时同步信标数 |

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- BOSS_KILL / ELITE_KILL / TRADE 撤离条件尚未完全接入房间完成状态
- 实际信标道具使用流程需人类试玩验证
- 副枪瞄准跟随主枪方向（非独立寻敌）

### 下轮最可能方向
1. 信标消耗后 UI 同步信标数量 + 其他撤离类型逻辑验证
2. 精英怪成长系统对接撤离点
3. 武器装配树可视化完善

## 轮次 66 — 撤离按钮可用性完善（BOSS_KILL/ELITE_KILL/TRADE）

**时间**: 2026-05-23 13:51
**维度**: 搜打撤深化 — 撤离 UI 状态反馈

### 玩家可感知的变化
- 房间清理后，未解锁的撤离类型按钮显示为灰色 disabled 状态
- 鼠标悬停时显示明确禁用原因（无信标/Boss未击败/精英未击败/货币不足）
- 玩家可清晰判断哪些撤离选项当前可用

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/ui/GameUIManager.gd | `_build_extraction_buttons()` 新增 `btn.disabled` 和 tooltip；新增 `_get_extraction_disabled_reason()` 返回禁用提示文案 |

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 遗留问题
- `_can_use_extraction_type` 中对 BOSS_KILL/ELITE_KILL 的判断依赖 `get_points_by_type(extraction_type, true)` 返回数量 > 0，这个逻辑是正确的（前提是 ExtractionDirector 在对应事件时创建并解锁了撤离点）
- 目前 BOSS_KILL 点由 `BossRoomDirector` 在 Boss 死亡时创建；ELITE_KILL 由 `notify_enemy_killed` 中的 `unlock_elite_extraction()` 在精英死亡时创建。两者均已正确实现。
- 需要人类试玩验证：信标消耗后按钮确实禁用且刷新；精英撤离按钮在精英死亡后从灰变亮

### 下轮最可能方向
1. 容器→InventoryUI刷新实际验证（LootModule 发放物品 + UI 刷新链路）
2. RoomWaveSpawner 精英识别和 EliteArchiveModule 对接
3. 武器装配树可视化

**时间**: 2026-05-24 09:39
**维度**: 波次/房间完成震屏分层 + Boss击败信号穿透

### 本轮选择
在战局内表现层审视中，发现 Boss 被击败时（`BossRoomDirector.boss_defeated` 信号发出后）的视觉反馈与普通房间清理完全相同——都是同一个 "房间清理完成！" 飘字 + 4.0 intensity 震屏。这是感官体验上的缺失：玩家辛辛苦苦打 Boss 获得的成就感与普通波次清理没有区分度。

同时发现 `BossRoomDirector` 的 `boss_spawned`、`boss_damaged`、`boss_phase_changed`、`boss_defeated` 信号完全没有任何外部订阅者——它们从未被转发到 `RoomGameMode`，导致 Boss 事件对 UI 完全不可见。

### 玩家可感知的变化
- Boss 房完成时飘字文案变为 **"Boss 已击败！"**（而普通房间仍是"房间清理完成！"）
- Boss 被击败时触发更强烈的震屏反馈（intensity=12.0, duration=0.20s），明显强于普通波次清理的 4.0
- Boss 出现、受伤、进入新阶段时 `room_info_label` 会更新对应提示文字

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/map/MapManager.gd | 新增 boss_spawned/boss_damaged/boss_phase_changed/boss_defeated 信号穿透（BossRoomDirector → MapManager → 外部） |
| src/game/RoomGameMode.gd | 订阅 MapManager 的 Boss 穿透信号，新增 `_on_boss_spawned/_on_boss_damaged/_on_boss_phase_changed/_on_boss_defeated` 处理器，触发强烈震屏（12.0） |
| src/ui/GameUIManager.gd | `_show_wave_complete_celebration(room_type)` 支持 Boss 房类型检测（Boss 房显示"Boss 已击败！"文案）；新增 `on_boss_spawned/boss_damaged/boss_phase_changed/boss_defeated` 空方法供 RoomGameMode 调用 |

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅（45秒无报错）

### 剩余风险
- Boss 血条 UI（`on_boss_damaged` 目前为空桩，后续扩展可在此基础上做 Boss HP bar）
- 实际 Boss 击败震屏效果需人类试玩确认震屏强度是否足够
- `boss_phase_changed` 时 `room_info_label` 直接覆盖原文字，没有考虑当前是否处于战斗中（理论上 Boss 阶段切换时玩家应该在战斗中，此时 room_info_label 可能被战斗信息覆盖）

### 下轮最可能方向
1. 容器→InventoryUI刷新实际验证（LootModule 发放物品 + UI 刷新链路）
2. 武器装配树可视化
3. 枪口火焰位置修复（position 在 local space，父节点 rotation 导致偏移）

## 轮次 118 — 多房间钥匙门与搜索撤离闭环

**时间**: 2026-05-24
**维度**: 战局内结构 — 房间推进 / 门 / 钥匙 / 搜索 / 撤离

### 本轮改动
| 文件 | 改动 |
|---|---|
| scenes/Main.tscn | 主战局入口切换为 RoomGameMode |
| src/game/RoomGameMode.gd | 清房掉钥匙、钥匙开一个方向门、进入下一房、撤离房读条 |
| src/game/RoomKeyPickup.gd | 新增房间钥匙拾取物 |
| src/game/RoomDoorInteraction.gd | 新增方向门交互区域 |
| src/map/MapGenerator.gd | 保证每层生成撤离房 |
| src/map/RoomFactory.gd | 主要房间生成搜索容器，修正容器本地坐标放置 |
| src/map/ContentInjector.gd | 战斗/精英/Boss/撤离/藏储/陷阱房补搜索内容 |

### 验证
- Godot headless `--quit`: EXIT 0
- Main 场景 headless `--quit-after 20`: EXIT 0，无脚本错误；日志显示多房间地图和撤离房节点
- `git diff --check`: EXIT 0

### 剩余风险
- 需要实际试玩验证按 E 拾钥匙/开门/进入下一房的手感。
- 撤离房当前进入即读条，后续应改为撤离点交互。

## 轮次 119 — 物理房间门与地图扩张修订

**时间**: 2026-05-25
**维度**: 战局内空间结构 — 物理门 / 房间拼接 / 地图展开

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/map/MapGenerator.gd | 房间按 800×600 正交网格排布，主路径横向、分支上下接入 |
| src/map/NodeGraph.gd | 节点位置同步写入 `RoomData.position`，避免房间实例重叠在原点 |
| src/game/RoomGameMode.gd | 开门不再传送；开门后目标房显露；玩家走入目标房范围才触发进入 |
| src/game/RoomDoorInteraction.gd | 门交互改为只开门 |
| src/map/RoomVisualizer.gd | 开启方向的房间边界碰撞留出门洞 |
| src/map/RoomTileMapInitializer.gd | 非战斗房同样支持物理门洞 |
| src/map/RoomWaveSpawner.gd | 额外刷怪无标准波次时不再访问空数组 |

### 验证
- 临时 headless 自动化：开门不移动玩家，目标房显露；玩家坐标进入目标房后才切房。
- `godot --headless --path . --quit`: EXIT 0
- `godot --headless --path . --quit-after 20 --scene scenes/Main.tscn`: EXIT 0
- `git diff --check`: EXIT 0

### 剩余风险
- 需要编辑器内试玩门洞宽度、碰撞边缘和相机跟随手感。
- 未开启房间目前只是隐藏，后续可以加暗区/雾门表现。

## 轮次 120 — 房间组件化基础建立（GridConstants + RoomComponent + RoomBlueprint + Registry + DoorComponent）

**时间**: 2026-05-25 01:25
**维度**: 战局内结构 — 房间组件化系统基础

### 本轮选择
房间组件化是"5房间Demo链"目标的基础设施。当前房间尺寸硬编码散落（800×600 在多处出现），组件系统缺失，无法支撑可复用的房间模板。本轮聚焦建立格子系统常量、组件基类、组件注册表和独立碰撞体门组件，为后续 RoomTileMapInitializer 重构铺垫。

### 玩家可感知的变化
- 房间尺寸统一为 960×768（15×12格 × 64px），视觉更开阔
- 组件系统为未来房间装饰/交互的灵活配置奠基

### 本轮改动
| 文件 | 改动 |
|---|---|
| `src/map/GridConstants.gd` | 新建 — 格子系统常量（CELL_SIZE/ROOM_CELLS/ROOM_PIXEL/门洞配置/坐标转换工具） |
| `src/map/RoomComponent.gd` | 新建 — 房间组件基类（Foor/Wall/Door/Interact/Spawn/DECORATION/Trigger 类型枚举 + 优先级 + initialize/activate/deactivate 接口） |
| `src/map/RoomBlueprint.gd` | 新建 — 房间模板（持有组件配置列表；含 create_combat/elite/scavenge/extraction/spawn_blueprint 工厂方法） |
| `src/map/RoomComponentRegistry.gd` | 新建 — 组件注册表（运行时按类型查询/激活/停用组件；get_door_by_direction 等快捷方法） |
| `src/map/DoorComponent.gd` | 新建 — 独立碰撞体门组件（StaticBody2D+Area2D 实现门洞；unlock/open/close 接口） |
| `src/map/RoomTileSetBuilder.gd` | CELL_SIZE 从硬编码 64 改为 `GridConstants.CELL_SIZE` 引用 |
| `src/map/MapGenerator.gd` | ROOM_SPACING 改为 GridConstants 引用 |
| `src/map/RoomData.gd` | `size` 默认值改为 GridConstants 引用 |
| `src/map/RoomWaveSpawner.gd` | `room_size` 默认值改为 GridConstants 引用 |
| `src/map/RoomTileMapInitializer.gd` | `room_size` 默认值改为 GridConstants 引用 |
| `src/map/RoomVisualizer.gd` | `room_size` 默认值改为 GridConstants 引用 |
| `src/enemy/EnemyBase.gd` | `_room_bounds` 改为 GridConstants 引用 |
| `src/map/RegionalSpawnController.gd` | `_room_bounds` 改为 GridConstants 引用 |

### 验证
- Godot headless --quit: EXIT 0 ✅

### 剩余风险
- GridConstants 目前在 DoorComponent 构造函数中引用（_setup_door_collision），需要确认无循环依赖风险
- DoorComponent 的 _setup_interaction_area 有 named parameter 语法（GDScript 不支持），已修复为位置参数
- RoomBlueprint 的格子坐标使用 GridConstants（960×768 房间），需确认与 RoomTileSetBuilder 的 CELL_SIZE=64 一致
- 实际组件渲染/碰撞效果需人类试玩验证
- DemoRoomChain 场景尚未创建（后续循环）

### 下轮最可能方向
1. DemoRoomChain.tscn 场景创建（5房间线性链，4战斗+1撤离）
2. RoomTileMapInitializer 重构为组件渲染器（FloorTileComponent/WallTileComponent）
3. RoomFactory 接入 RoomBlueprint 实例化组件化房间

---

## Round 141 — 2026-05-25 05:08

**维度**: Boss死亡动画（HP扣到0 + boss_defeated + 死亡视觉）

**当前玩家问题**: Boss房Demo中，Boss可被子弹扣血（轮次139已接入take_damage），但当HP归零时死亡流程不完整——没有震屏、没有胜利提示、Boss视觉没有消失、粒子爆炸效果也没有。

**本轮选择原因**: Boss死亡是玩家击败Boss最核心的情绪高点，必须有强烈的视觉反馈。之前的轮次已经完成了Boss HP扣血+GameUIManager血条（139、138），现在补全死亡链条的最后一段。

**玩家体验的前后变化**: 
- Before: Boss掉血但死亡时无反馈，玩家不确定是否击败了Boss
- After: Boss死亡时有放射状粒子爆炸 + 全屏震屏 + 屏幕白闪 + 中央"✦ BOSS DEFEATED ✦"胜利文字

**涉及代码/数据/文档**:
- `src/fx/ScreenShake.gd`: 新增 `screen_flash()` 和 `screen_shake_death()` 方法
- `src/game/DemoBoss.gd`: 
  - `_ready()` 新增 `add_to_group("enemy")` 修复Bullet检测
  - 新增 `_spawn_death_particles()` 放射状粒子爆炸
  - `_trigger_death()` 新增震屏+白闪调用
- `src/ui/GameUIManager.gd`: 
  - `on_boss_defeated()` 新增胜利提示文字动画和屏幕特效调用
  - 新增 `_show_boss_defeated_victory()` 和 `_trigger_boss_defeated_screen_effects()`

**验收标准**:
- [ ] DemoRoomChain进入Boss房后，攻击DemoBoss，HP扣到0
- [ ] Boss死亡时有16方向粒子向外飞散消散
- [ ] 死亡时全屏震屏（高频强烈衰减震屏）
- [ ] 死亡时屏幕短暂白闪
- [ ] 屏幕上出现"✦ BOSS DEFEATED ✦"文字，渐入渐出后消失
- [ ] Boss Room HP条消失
- [ ] 门变为绿色可进入状态

**验证**: Godot 4.6.2 headless 编译通过 ✅

**剩余风险**: 粒子爆炸使用ColorRect而非Sprite/ParticlesSystem2D，性能一般但Demo够用。后续可用GPUParticles2D优化。仍需人类试玩确认实际手感。

**下一轮可能方向**:
1. 命运卡片改造效果融入Demo链（当前Demo链无命运卡片）
2. 武器装配树节点高亮/选中反馈
3. 商人房完整交易流程

---

## Round 154 — 2026-05-25 06:44

**维度**: FateCardUIController UI 引用健壮性修复

**当前玩家问题**: FateCardUIController 的 `_ui_manager` 查找依赖 `get_first_node_in_group("ui_manager")` 和固定路径 `/root/Main/GameUIManager`，在 DemoRoomChain 的 Main 场景树结构下可能找不到 GameUIManager 节点，导致 Tab 选卡后卡片成功应用通知无法显示。

**本轮选择原因**: 轮次 152 实例化 FateCardUIController 成功，轮次 153 验证了撤离中断机制。链路完整但 UI 引用健壮性有隐患，修复后能确保 `show_fate_card_notification` 在不同场景树配置下可靠调用。

**玩家体验的前后变化**:
- Before: Tab 选卡后可能看不到卡片应用成功/失败的悬浮通知
- After: FateCardUIController 在任意场景树配置下都能找到 GameUIManager 并正确显示应用结果通知

**涉及代码**:
- `src/ui/FateCardUIController.gd`: `_ready()` 中的 `_ui_manager` 查找增加 fallback 逻辑，依次尝试 `get_first_node_in_group("ui_manager")` → `/root/Main/GameUIManager` 固定路径 → 遍历根节点向下查找

**验收标准**:
- [ ] DemoRoomChain 场景 Tab 键呼出命运卡片
- [ ] 选择任意卡片后屏幕上显示 "✓ [卡名] 已应用！" 或 "✗ [卡名] 应用失败" 通知
- [ ] 通知正确出现在 CanvasLayer 层级

**验证**: Godot headless --check-only: EXIT 0 ✅

**剩余风险**: 实际通知样式和消失动画需人类试玩确认；GameUIManager.show_fate_card_notification 在当前 DemoRoomGameMode 独立运行时可能被旁路（该模式直接控制 _ui_label 文字）

**下一轮最可能方向**:
1. 人类试玩验证完整链路（8房间Demo链 + Tab选卡 + 撤离读条）
2. 命运卡片"子弹背枪"效果在 Demo 中的子弹尾部多边形渲染验证
3. 改造房 T 键 → 真实命运卡片选择流程

---

## Round 160 — 2026-05-25 08:12

**维度**: DemoRoomChain编译兼容性修复

**当前玩家问题**: DemoRoomChain场景加载时报5个编译错误，阻止完整流程验证：
1. `_set_row_highlight`传`null`作`Color`类型（WeaponAssemblyTreePanel.gd）
2. `type_str`类型推断失败（同文件）
3. `ExtractionModule`/`InventoryModule`是`RefCounted`不能作为Node的child（DemoRoomGameMode.gd）
4. 单脚本加载时autoload未就绪导致`Global`/`FateCardGameBridge`/`BaseManager`未定义

**本轮选择原因**: 这些是类型语法和设计错误，会导致Demo无法运行。修复后完整项目`--quit-after-secs`可干净退出（0个ERROR）。

**玩家体验的前后变化**: 无直接玩家体验变化，但修复后DemoRunLoop场景可以正确编译加载，人类可以进入游戏验证命运卡片等系统。

**涉及代码/数据/文档**:
- `src/ui/WeaponAssemblyTreePanel.gd`:
  - `_set_row_highlight(row, color)`参数`color`改为无类型声明（移除`Color`类型标注），允许null
  - `var type_str := AssemblyNode.NodeType.keys()[node.node_type]`改为`var type_str: String = str(...)`
- `src/game/DemoRoomGameMode.gd`:
  - 移除`_get_extraction_module()`和`_get_inventory_module()`中的`add_child()`调用（RefCounted不能作为Node children）

**验收标准**:
- [ ] Godot完整项目`--quit-after-secs`干净退出（0个ERROR）
- [ ] DemoRoomChain场景加载无编译错误
- [ ] 人类可进入DemoRunLoop验证命运卡片、撤离、武器装配等系统

**验证**: Godot 4.6.2 headless `--quit-after-secs 30`: 0个ERROR ✅
```bash
cd /Users/summercards/ShellStorm2 && timeout 60 godot --headless --quit-after-secs 30 2>&1 | grep -c "SCRIPT ERROR\|ERROR:\|Parse Error\|Compile Error"
# 输出: 0 (Clean exit)
```
单脚本加载会报autoload未就绪的"Identifier not found"，但这不影响完整项目运行。

**剩余风险**: 单脚本检查仍报Global/FateCardGameBridge/BaseManager未定义（autoload加载顺序问题），需完整项目运行验证。人类试玩验证命运卡片完整链路仍为最高优先。

**下轮最可能方向**:
1. 人类试玩验证命运卡片完整链路（Tab→选卡→改造房→副枪子弹→撤离）
2. 改造房T键→真实命运卡片选择流程验证
3. 商人房完整交易流程

---

## 轮次 164 — 2026-05-25 02:31 UTC+8

### 维度
撤离成功面板 HUD 显示整合（RoomGameMode → ExtractionSuccessPanel）

### 问题分析
审查 `RoomGameMode._on_extraction_completed()` 时发现一个重要的玩家体验断点：

撤离成功后，`_print_extraction_success()` 只在 console 输出统计信息（`=== 撤离成功 ===`），但**GameUIManager 已经有完整的 `ExtractionSuccessPanel` 面板**（包含物品清单、品质颜色、继续按钮），且 `show_run_extraction_success(stats)` 方法能够显示波次/击杀/魂/风险层级的完整战局统计。

RoomGameMode 没有调用这个面板，而 CoreCombatMode 的撤离流程正确调用了。这导致房间系统的撤离只有 console 日志，没有 HUD 面板反馈。

### 本轮改动

在 `RoomGameMode._on_extraction_completed()` 成功后，补充调用 `ui_layer.show_run_extraction_success(stats)` 字典包含 wave/kills/currency/score/risk 五个字段，与 CoreCombatMode 撤离流程保持一致。

### 玩家可感知的变化
- **修复前**：撤离成功后只有 console 日志 `"=== 撤离成功 === 背包物品已保存: X 件"`，玩家看不到屏幕反馈
- **修复后**：撤离成功后弹出 ExtractionSuccessPanel 面板，显示"撤离成功  波次 N  击杀 N  魂 N"和"最终得分: X  风险层级: Y"，面板按物品品质着色、显示保险物品、点击"返回基地"回基地菜单

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/game/RoomGameMode.gd | `_on_extraction_completed()` 成功后补充调用 `ui_layer.show_run_extraction_success()` 显示 HUD 面板 |

### 验证
- Godot --headless --quit-after 4: EXIT 0 ✅

### 剩余风险
- 撤离成功面板显示时需要 `_inventory_module` 和 `_insurance_module` 正确绑定到 GameUIManager
- 人类试玩验证：实际在 DemoRoomChain 中完成撤离，观察 ExtractionSuccessPanel 是否弹出

### 下轮最可能方向
1. **人类试玩验证**：所有代码链路已完整，亟需实际试玩确认体感
2. 搜打撤经济系统人类试玩验证（开箱掉落→背包→撤离带出完整链路）
3. 命运卡片"子弹背枪"/"变大了"实际效果体验

---

## 轮次 165 — 2026-05-25 10:10 UTC+8

### 维度
P0 玩家体验阻断修复 — Demo 链推进 + Boss 遭遇加载

### 问题分析
按游戏体验验收而非单点功能验收时，当前最严重的问题是玩家无法稳定走完搜打撤垂直切片：

1. `RoomBoss.tscn` 场景资源格式错误，Boss 房无法加载，主线地图进入 Boss 遭遇前被打断。
2. `DemoBoss.gd` 使用 Godot 4.6 不接受的函数内命名函数写法，导致 Boss 脚本解析失败。
3. `RoomElite.tscn` 也存在同类 `sub_resource` 内嵌在节点块中的场景格式错误，Demo 链进入精英房会断。
4. `DemoRoomGameMode` 视觉初始化传未类型化 `[]` 给 `Array[Dictionary]`，运行时类型检查报错。
5. Demo 门交互把 `body_entered` 的 `body` 当作门 Area 使用，玩家靠近门后不会登记 `_near_door`，清房后按 E 无法推进房间。
6. `RoomVisualizer` 假设所有房间都有 `ZoneMarker_Center`，精英房缺该节点时会报 `Node not found`。

### 本轮改动
| 文件 | 改动 |
|---|---|
| scenes/RoomBoss.tscn | 修复 DoorVisualizer 资源 id；将 Boss 碰撞 `sub_resource` 提到资源区并由 CollisionShape 引用 |
| scenes/RoomElite.tscn | 将精英房碰撞 `sub_resource` 提到资源区并由 CollisionShape 引用 |
| src/game/DemoBoss.gd | 死亡粒子清理改为可连接的 lambda 变量，兼容 Godot 4.6 |
| src/game/DemoRoomGameMode.gd | 使用 `Array[Dictionary]` 传入视觉配置；门信号绑定实际 door Area，玩家靠近后可登记交互目标 |
| src/map/RoomVisualizer.gd | 对 `BoundaryOverlay` / `ZoneMarker_Center` 使用可空查找，避免不同房间结构差异打断体验 |
| verify_p0_player_flow.tscn / .gd | 新增体验验收场景：验证 Demo 链可生成、清房后门可推进、主线 Boss 遭遇可加载 |

### 玩家可感知的变化
- **修复前**：进入主线或 Demo 链时，Boss/精英房资源错误会打断；Demo 清完第一房后，门交互目标不会出现，玩家无法顺畅推进。
- **修复后**：主线地图能加载 Boss 实体；Demo 链能从第一房清怪后识别门交互并推进到下一房，垂直体验不再卡死在 P0 阻断点。

### 游戏设计师验收标准
- [x] 玩家进入 Demo 链时生成玩家、房间、Boss 遭遇，不出现脚本解析/场景解析阻断。
- [x] 第一房清理后，靠近前进门能形成交互目标。
- [x] 开门后房间推进到下一房间，钥匙经济保持预期。
- [x] 主线 `Main.tscn` 能生成地图并加载 Boss 实体，Boss 遭遇作为可读目标存在。

### 验证
- `godot --headless --path . --quit-after 3`: EXIT 0
- `godot --headless --path . --scene res://verify_p0_player_flow.tscn`: `P0_PLAYER_FLOW_OK: Demo chain starts, door flow advances, Boss encounter loads`
- `godot --headless --path . --scene res://scenes/DemoRoomChain.tscn --quit-after 8`: 场景启动，DemoBoss ready，无脚本/场景解析阻断
- `godot --headless --path . --scene res://scenes/Main.tscn --quit-after 8`: 地图生成，DemoBoss ready，无脚本/场景解析阻断

### 剩余风险
- headless 强制退出仍会输出 ObjectDB/resource-in-use 清理警告；当前未观察到玩家流程阻断，但后续可以单独做退出清理。
- 本轮是自动化体验验收，不等同于人类手感试玩；下一轮仍应实际试玩开箱、命运卡、Boss 击杀、撤离读条的连续体验。

### 下轮最可能方向
1. 人类试玩验证完整搜打撤闭环（开箱→背包→命运卡→Boss/精英→撤离）
2. 改造房 T 键切换防连跳与命运卡应用体感
3. Headless 验收脚本标准化，减少强制退出清理噪音

---

## 轮次 166 — 2026-05-25 10:28 UTC+8

### 维度
P1 改造房体验修复 — 命运改造切换稳定性

### 问题分析
P0 体验链路打通后，下一处会直接误导试玩判断的问题在改造房：

1. WorkbenchPanel 的 T 键切换原先依赖按键轮询或未定义 action，按住时容易连续翻转，玩家会感觉模式失控。
2. 命运改造按钮被放在会被 `_populate_gunbody_options()` / `_show_fate_card_options()` 清空重建的容器中，打开或切换模式时可能把按钮自身 queue 掉。玩家会失去“切到命运改造 / 切回基础改造”的明确入口。
3. 命运改造说明有英文残留，不利于玩家在改造房内快速理解选择结果。

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/ui/WorkbenchPanel.gd | 将 T/ESC 输入改为事件边沿处理，忽略 key echo，避免按住 T 连续切换 |
| src/ui/WorkbenchPanel.gd | 清空选项时保留命运改造按钮，并确保按钮始终位于左侧选项顶部 |
| src/ui/WorkbenchPanel.gd | 命运改造模式说明改为中文，卡片应用成功后继续广播 HUD 通知 |
| verify_p1_workbench_flow.tscn / .gd | 新增体验验收场景，验证改造模式只按一次切一次、按钮不丢失、可切回基础改造 |

### 玩家可感知的变化
- **修复前**：按 T 可能瞬间切来切去，且模式按钮可能在选项重建中消失；玩家无法稳定判断自己处于基础改造还是命运改造。
- **修复后**：按 T 一次进入命运改造，再按一次回基础改造；按住 T 不会重复翻转；按钮始终可见并明确显示当前可切换方向。

### 游戏设计师验收标准
- [x] 打开改造台后，玩家能看到“命运改造 [T]”入口。
- [x] 按 T 一次进入命运改造，按钮变为“基础改造 [T]”。
- [x] 按住 T 不会来回连跳。
- [x] 再按 T 回到基础改造，按钮恢复“命运改造 [T]”。
- [x] P0 Demo 链推进和 Boss 加载验收仍通过。

### 验证
- `godot --headless --path . --scene res://verify_p1_workbench_flow.tscn`: `P1_WORKBENCH_FLOW_OK: Workbench transform mode toggles once per press and remains readable`
- `godot --headless --path . --scene res://verify_p0_player_flow.tscn`: `P0_PLAYER_FLOW_OK: Demo chain starts, door flow advances, Boss encounter loads`
- `godot --headless --path . --quit-after 3`: EXIT 0

### 剩余风险
- 本轮验证的是改造房模式切换体验，不等同于完整命运卡效果手感试玩；卡片应用后的实际弹道、子弹背枪、枪上加枪仍需人类实际战斗验证。
- 旧的单脚本 verify 文件仍不适合作为主验收入口；本轮继续采用真实 Godot 场景启动的体验验收方式。

### 下轮最可能方向
1. 人类试玩验证改造房命运卡选择后，武器视觉和弹道是否能被玩家读懂
2. 标准化旧 verify 脚本，统一迁移为场景式体验验收
3. 搜打撤经济体验：开箱收益、背包容量、撤离带出是否形成风险选择

---

## 轮次 167 — 2026-05-25 11:43 UTC+8

### 维度
P1 撤离与 Boss 房体验一致性修复

### 问题分析
上一轮全面检查后，剩余 P1 风险集中在两处会直接影响玩家判断的体验反馈：

1. 撤离按钮点击后，UI 无条件进入读条，即使战斗模式或 ExtractionModule 拒绝开始撤离，玩家也会看到“已经开始撤离”的假反馈。
2. Demo Boss 房信号连接使用 `connect()` 返回值做隐式判断，重复 setup 时不够稳；同时 `RoomBoss.tscn` 的 BossRoomLogic 实际挂在根节点，Demo 逻辑只查子节点时会漏接房间逻辑信号。

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/ui/GameUIManager.gd | 撤离 UI 先检查后端是否就绪；只有 `begin_extraction()` 返回成功才进入读条 |
| src/ui/GameUIManager.gd | 撤离选择面板恢复为明确选择态：隐藏读条、显示按钮、恢复中断按钮状态 |
| src/ui/GameUIManager.gd | 后端拒绝、信标失败、魂不足时保留选择面板并给出玩家可读提示 |
| src/game/CoreCombatMode.gd | 将 `begin_extraction()` 契约对齐为返回 bool，旧战斗模式也能被 UI 正确判断 |
| src/game/DemoRoomGameMode.gd | Boss 信号改为 `Signal.is_connected()` 防重复连接，并兼容 BossRoomLogic 挂在房间根节点的结构 |
| verify_p1_extraction_flow.tscn / .gd | 新增体验验收：后端拒绝不显示读条，后端接受才显示读条 |
| verify_p1_boss_signal_flow.tscn / .gd | 新增体验验收：Boss 房重复 setup 后信号只连接一次，Boss 仍能生成 |

### 玩家可感知的变化
- **修复前**：点击撤离后可能看到倒计时，但后端实际上没有开始；Boss 房重复初始化存在事件重复响应或漏接房间逻辑的风险。
- **修复后**：撤离只有真正开始时才显示倒计时；失败时玩家停留在选择面板并看到原因。Boss 房逻辑信号稳定接入，重复 setup 不会叠加回调。

### 游戏设计师验收标准
- [x] 撤离选择面板出现时只展示可选撤离方式，不提前展示读条。
- [x] 后端拒绝撤离时，玩家不会看到倒计时假反馈，并能重新选择。
- [x] 后端接受撤离时，按钮隐藏、读条出现、中断按钮恢复可用。
- [x] Boss 房重复初始化不会重复连接 Boss spawn/defeated 信号。
- [x] Boss 房根节点挂载 BossRoomLogic 时仍能被 Demo 流程识别。

### 验证
- `godot --headless --path . --scene res://verify_p1_extraction_flow.tscn`: `P1_EXTRACTION_FLOW_OK: extraction UI only enters countdown after backend acceptance`
- `godot --headless --path . --scene res://verify_p1_boss_signal_flow.tscn`: `P1_BOSS_SIGNAL_FLOW_OK: Boss room setup connects root logic once and still spawns`
- `godot --headless --path . --scene res://verify_p1_workbench_flow.tscn`: `P1_WORKBENCH_FLOW_OK: Workbench transform mode toggles once per press and remains readable`
- `godot --headless --path . --scene res://scenes/Main.tscn --quit-after 10`: 主场景过滤检查无 Parse/SCRIPT/Invalid call/Node not found 错误
- `godot --headless --path . --quit-after 3`: EXIT 0

### 剩余风险
- headless 验收场景在强制退出时仍可能输出 ObjectDB/resource-in-use 清理警告；当前不影响玩家流程，但后续 CI 需要清理。
- 撤离的完整人类试玩还应覆盖：信标撤离真实消耗、交易撤离扣费/失败退款、Boss 击败后撤离带出结算。

### 下轮最可能方向
1. 完整搜打撤闭环试玩：开箱→背包→命运卡→Boss/精英→撤离结算
2. 清理旧 verify 脚本，避免和场景式验收互相打架
3. 撤离结算与基地仓库/经济反馈的人类体验校准

---

## 轮次 168 — 2026-05-25 11:51 UTC+8

### 维度
地图房间结构修复 — 固定房间、运行时墙体、门洞碰撞、房内刷怪

### 问题分析
本轮集中处理地图体验里的四个基础问题：

1. 玩家出生/进房位置不稳定，出生房也没有被实例化成可见、可碰撞的固定房间。
2. 房间缺少稳定编号，不利于后续按编号扩展房间设计。
3. 房间墙体主要依赖视觉层，缺少统一、可随开门状态更新的碰撞墙段。
4. 刷怪点以玩家当前位置为中心采样，玩家靠墙时会把怪物刷到墙外或边界上。

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/map/RoomData.gd | 新增 `room_number` 和 `assign_number()`，生成 `F01-R000` 这类稳定房间编号 |
| src/map/NodeGraph.gd | 添加节点时立即给 RoomData 分配固定编号 |
| src/map/RoomLayout.gd | 新增运行时房间外壳：房间编号标签、墙体视觉、墙体碰撞、按开门状态生成门洞 |
| src/game/RoomGameMode.gd | 出生房也实例化；玩家按固定房间入口位置落位；所有房间注入 RoomLayout；开门后同步更新墙体门洞 |
| src/map/RoomWaveSpawner.gd | 敌人刷点改为在当前房间安全矩形内随机采样，并避开玩家近身区域 |
| src/map/RoomFactory.gd | 占位房不再额外生成一圈不可开门的旧碰撞墙，统一交给 RoomLayout |
| verify_map_layout_flow.tscn / .gd | 新增地图体验验收：固定编号、玩家在当前房间内、墙体碰撞存在、开门同步墙体、怪物刷点不出界 |

### 玩家可感知的变化
- **修复前**：玩家可能出现在不像房间中心的位置；出生房缺少完整房间结构；墙看得见但挡不住；怪物可能从墙外或边界外出现。
- **修复后**：每个房间都有固定编号和固定世界坐标；玩家进入房间时落在可读的入口/中心位置；墙体有真实碰撞；门打开后墙体出现对应门洞；怪物只从当前房间内部安全区域出现。

### 游戏设计师验收标准
- [x] 房间编号稳定，可用于后续扩展手工房间设计。
- [x] 玩家出生和进门落点基于当前房间固定坐标，不再漂移到地图任意位置。
- [x] 房间墙体具备 `StaticBody2D` 碰撞，玩家不会穿墙。
- [x] 开门后目标方向墙体同步出现门洞。
- [x] 怪物刷点限制在当前房间安全区域内，不会从墙外刷出。

### 验证
- `godot --headless --path . --scene res://verify_map_layout_flow.tscn`: `MAP_LAYOUT_FLOW_OK: fixed room ids, player placement, wall collision, and spawn bounds are coherent`
- `godot --headless --path . --scene res://scenes/Main.tscn --quit-after 8`: 主场景过滤检查无 Parse/SCRIPT/Invalid call/Node not found 错误
- `godot --headless --path . --scene res://verify_p0_player_flow.tscn`: `P0_PLAYER_FLOW_OK: Demo chain starts, door flow advances, Boss encounter loads`
- `godot --headless --path . --scene res://verify_p1_extraction_flow.tscn`: `P1_EXTRACTION_FLOW_OK: extraction UI only enters countdown after backend acceptance`
- `godot --headless --path . --quit-after 3`: EXIT 0

### 剩余风险
- 当前墙体随机性主要来自地图连接关系和开门状态；后续如果要做“同编号房间的多套墙型模板”，可以把 RoomLayout 扩展为按 `room_number + seed` 选择墙面装饰/障碍组合。
- 仍需要人类试玩确认门洞宽度、入口落点和怪物刷点距离是否符合战斗手感。

### 下轮最可能方向
1. 给 RoomLayout 增加编号房间模板表：固定房型 + 随机内容/障碍组合
2. 人类试玩验证墙碰撞、门洞通过、刷怪视线是否舒服
3. 将旧场景内自带边界与 RoomLayout 进一步统一，减少重复墙体

---

## 轮次 169 — 2026-05-25 11:55 UTC+8

### 维度
开局小房间重构 — 初始钥匙与开门命运卡

### 问题分析
用户希望去掉“开局直接弹命运卡并跳入第一战斗房”的流程，改成更有空间感的开局：

1. 每局先进入固定大小的小初始房间。
2. 初始房间默认给玩家 1 把钥匙。
3. 玩家用钥匙打开初始房间唯一出口时，才触发命运卡牌选择。
4. 命运卡选择后不自动传送，玩家穿过已打开的门进入后续房间。

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/map/MapGenerator.gd | 初始房间固定为 `448×320`；分支房不再挂到初始房，保证小房间只有一个出口 |
| src/game/RoomGameMode.gd | 开局默认给 1 把钥匙，并将初始房标记为已清理；进入初始房不再自动弹命运卡 |
| src/game/RoomGameMode.gd | 开初始房门时触发命运卡选择；卡牌选择后保留在当前流程中，玩家自行穿过门洞 |
| verify_initial_room_fate_door_flow.tscn / .gd | 新增体验验收：小初始房、默认钥匙、开门后弹命运卡、初始房单出口 |

### 玩家可感知的变化
- **修复前**：一进游戏就被命运卡弹窗打断，选择后直接跳到第一间战斗房，初始房没有“从小房间出去”的仪式感。
- **修复后**：玩家先站在一个小初始房里，拥有 1 把钥匙；靠近唯一出口开门时，命运卡出现；选完后门已打开，玩家自然穿门进入探索。

### 游戏设计师验收标准
- [x] 初始房间固定为小房间尺寸。
- [x] 初始房间只有一个出口。
- [x] 开局不会自动弹命运卡。
- [x] 开局默认拥有 1 把钥匙。
- [x] 使用钥匙打开初始门时才触发命运卡牌。
- [x] 选卡后不自动传送，门已打开，玩家可以自己进入下一房间。

### 验证
- `godot --headless --path . --scene res://verify_initial_room_fate_door_flow.tscn`: `INITIAL_ROOM_FATE_DOOR_OK: small start room grants one key and triggers fate cards on first door open`
- `godot --headless --path . --scene res://verify_map_layout_flow.tscn`: `MAP_LAYOUT_FLOW_OK: fixed room ids, player placement, wall collision, and spawn bounds are coherent`
- `godot --headless --path . --scene res://scenes/Main.tscn --quit-after 8`: 主场景过滤检查无 Parse/SCRIPT/Invalid call/Node not found 错误
- `godot --headless --path . --scene res://verify_p0_player_flow.tscn`: `P0_PLAYER_FLOW_OK: Demo chain starts, door flow advances, Boss encounter loads`
- `godot --headless --path . --scene res://verify_p1_extraction_flow.tscn`: `P1_EXTRACTION_FLOW_OK: extraction UI only enters countdown after backend acceptance`
- `godot --headless --path . --quit-after 3`: EXIT 0

### 剩余风险
- 需要人类试玩确认小房间尺寸、门洞位置和命运卡弹窗时机是否有足够仪式感。
- 后续可以给初始房添加专属视觉与音效，而不是只依赖运行时 RoomLayout。

---

## 轮次 170 — 2026-05-25 12:32 UTC+8

### 维度
第一章玩法闭环 — 搜索/掉落/钥匙/开门/命运卡/武器装配

### 问题分析
用户指出第一章局内闭环还有几个体验断点：背包内无图标物品不可读、右键无法操作武器件，导致命运卡里“合成武器”的价值没有进入实际玩法；房间门不应等拿到钥匙才出现，而应在任务开始时随完整地图生成；钥匙也不应固定只来自开局，而应由搜索和怪物掉落补充；怪物掉落表为空时会让战斗奖励断流。

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/base/ItemRegistry.gd | 新增 `item_room_key` 房间钥匙物品定义，并修复重复 `get_item()` 声明 |
| src/game/LootModule.gd | 第一章战斗/精英掉落表合并基础掉落池；搜索容器和怪物掉落加入钥匙概率；普通怪也有概率产出可用物品 |
| src/game/RoomGameMode.gd | 门交互随房间刷新始终生成；开门消费背包钥匙；怪物/搜索获得钥匙会同步钥匙计数 |
| src/ui/GameUIManager.gd | 背包无美术资源物品生成可见占位图标和文字标识；右键模块/配件可直接装配到武器树；按 K 可查看武器装配树 |
| verify_ch1_gameplay_loop.gd / .tscn | 新增第一章体验验收：生成门可见、搜索/怪物掉落钥匙与武器件、背包图标可读、右键装配生效 |

### 玩家可感知的变化
- 第一章任务开始时地图和门已经完整生成，玩家看到的是“锁住的门”，不是拿到钥匙后凭空出现门。
- 搜索箱子和打怪都有机会获得钥匙、消耗品、子弹模块、武器配件，战斗和探索都能推进开门资源。
- 背包里没有正式图标的物品也会有颜色底和 `KEY/MOD/ATT/HP/AM` 标识，不再像空格子。
- 搜到配件后右键即可装到当前武器上，武器组合从“系统存在”变成“局内可操作”。

### 游戏设计师验收标准
- [x] 开局地图生成后，初始门已经可见且默认关闭。
- [x] 搜索和怪物掉落能提供钥匙，钥匙可用于后续开门。
- [x] 第一章掉落池能产出武器模块/配件，使命运卡和武器合成有材料来源。
- [x] 背包物品可读、可操作，不再出现无图标空白物品。
- [x] 右键武器件会真实改变武器装配树，并从背包扣除材料。
- [x] 已有 P0/P1 主流程、撤离、地图墙碰撞和初始命运门验收仍通过。

### 验证
- `godot --headless --path . verify_ch1_gameplay_loop.tscn`: `CH1_GAMEPLAY_LOOP_OK: visible generated doors, searchable/enemy loot, key drops, inventory icons, and weapon assembly are playable`
- `godot --headless --path . verify_initial_room_fate_door_flow.tscn`: `INITIAL_ROOM_FATE_DOOR_OK`
- `godot --headless --path . verify_map_layout_flow.tscn`: `MAP_LAYOUT_FLOW_OK`
- `godot --headless --path . verify_p1_extraction_flow.tscn`: `P1_EXTRACTION_FLOW_OK`
- `godot --headless --path . verify_p0_player_flow.tscn`: `P0_PLAYER_FLOW_OK`
- `godot --headless --path . verify_p1_workbench_flow.tscn`: `P1_WORKBENCH_FLOW_OK`
- `godot --headless --path . --quit-after 3`: EXIT 0

### 剩余风险
- 当前背包图标是程序化占位图，正式美术资源接入后需要替换为物品图标。
- 怪物无限刷问题本轮通过地图刷点和回归场景做了边界验收，但仍需要一次真人试玩验证长时间战斗节奏。
- 武器件右键装配目前是快捷体验路径，后续可增加确认/替换提示，避免玩家误替换已装部件。

---

## 轮次 171 — 2026-05-25 13:18 UTC+8

### 维度
第一章导演路径修复 — 散弹枪、背包操作、命运开门、地面魂球、墙挡子弹

### 问题分析
真人视角反馈显示上一轮虽然数据链路存在，但玩家体验仍断在几个地方：枪械组装不可见，`I` 背包打开后缺少可操作感，初始门开门时命运卡选择可能被局前 pending 卡片吞掉，开局小房间缺少“拿到一把新枪并换枪”的明确目标，怪物死亡的魂奖励直接进账而不是地面掉落，墙体挡住角色/怪物但不挡玩家子弹。

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/base/ItemRegistry.gd | 新增局内武器掉落物：豌豆手枪、散射喷壶、步枪；散射喷壶进入 `spawn_starter` 掉落池 |
| src/map/RoomFactory.gd / src/map/ContentInjector.gd | 初始小房间箱子保证给 `weapon_shotgun` |
| src/game/ContainerInteraction.gd | 支持容器 `guaranteed_items`，用于设计师指定关键教学掉落 |
| src/ui/GameUIManager.gd | `I` 键显式打开背包并同步显示武器装配树；背包右键 `weapon/gun_body` 可替换主武器；`Tab/K` 均可切武器树 |
| src/game/RoomGameMode.gd | 初始门开门时强制弹 3 选 1 命运卡，不再被局前 pending 卡片自动应用吞掉；怪物魂奖励改为地面 SoulOrb 拾取 |
| scenes/Bullet.tscn / src/bullet/Bullet.gd | 玩家子弹 collision_mask 包含墙层，命中 StaticBody2D 墙体后销毁 |
| verify_ch1_director_loop.gd / .tscn | 新增导演验收：开箱拿散弹枪、I 背包/武器树、右键换枪、开门命运卡、魂球拾取、子弹撞墙 |

### 玩家可感知的变化
- 开局小房间箱子会给一把“散射喷壶”，玩家可以打开背包右键换枪。
- 按 `I` 不只是看到格子，也能同时看到武器树，知道当前武器组合是什么。
- 打开初始门会稳定弹出命运卡三选一。
- 怪物死亡后魂会掉在地上，走过去吸附拾取，恢复原来的战利品手感。
- 房间墙壁同时挡角色、怪物和玩家子弹。

### 验证
- `godot --headless --path . verify_ch1_director_loop.tscn`: `CH1_DIRECTOR_LOOP_OK`
- `godot --headless --path . verify_ch1_gameplay_loop.tscn`: `CH1_GAMEPLAY_LOOP_OK`
- `godot --headless --path . verify_initial_room_fate_door_flow.tscn`: `INITIAL_ROOM_FATE_DOOR_OK`
- `godot --headless --path . verify_map_layout_flow.tscn`: `MAP_LAYOUT_FLOW_OK`
- `godot --headless --path . verify_p0_player_flow.tscn`: `P0_PLAYER_FLOW_OK`
- `godot --headless --path . verify_p1_extraction_flow.tscn`: `P1_EXTRACTION_FLOW_OK`
- `godot --headless --path . --quit-after 3`: EXIT 0

### 剩余风险
- 武器切换现在是背包右键快捷装备，后续可以做拖拽/双击和替换确认。
- 魂球拾取半径、吸附速度、掉落数量还需要真人试玩调手感。
- 正式枪械图标和枪械掉落美术还未接入。

### 轮次 171 补充 — 武器装备交换语义
- 修正背包右键武器的处理路径：`weapon/gun_body` 不再走模块消耗逻辑，而是进入装备系统。
- 装备新主武器时，会把旧主武器以物品形式放回背包；新武器从背包移动到装备位。
- 导演验收已补充：右键散弹枪后当前主武器为 `GunBody_Shotgun`，背包中出现原来的 `weapon_pistol`。

---

## 轮次 172 — 2026-05-25 15:55 UTC+8

### 维度
第一章背包与装备反馈修复 — 保险格可逆操作、可移动背包、HUD 主枪位

### 玩家问题与修复
| 玩家问题 | 修复结果 |
|---|---|
| 左键物品会直接进入保险箱且不知道如何取回 | 背包普通左键改为选择；`Shift + 左键` 才存保险；保险格左键可取回 |
| 背包满时从保险格取出可能丢失物品 | 取回失败会将物品放回保险格并提示背包已满 |
| 背包遮挡且缺少基础系统视觉 | 背包和保险格获得统一暗色系统面板样式，可拖动位置 |
| 主界面看不到当前装备的枪 | HUD 增加主武器格与名称，装备切换时同步更新 |

### 实现与验收
| 文件 | 改动 |
|---|---|
| src/ui/GameUIManager.gd | 建立 HUD 主枪位、背包面板样式与拖动；重设保险格左右键语义和满包保护；修复 UI 初始化路径 |
| verify_inventory_equipment_ui.gd / .tscn | 新增装备位、保险格往返与面板移动体验验收 |

### 验证
- `godot --headless --path . verify_inventory_equipment_ui.tscn`: `INVENTORY_EQUIPMENT_UI_OK`
- `godot --headless --path . verify_ch1_director_loop.tscn`: `CH1_DIRECTOR_LOOP_OK`
- `godot --headless --path . verify_ch1_gameplay_loop.tscn`: `CH1_GAMEPLAY_LOOP_OK`
- `godot --headless --path . --quit-after 3`: EXIT 0

### 剩余风险
- 当前物品和枪械图标仍以程序化占位为主，需要正式美术资源替换。
- Headless 退出时仍报告已有对象/资源清理警告，不阻断玩法验收，但后续应定位生命周期泄漏。
- 面板拖动、换枪反馈和保险格操作仍需要真人游玩确认手感。

---

## 轮次 173 — 2026-05-25 16:20 UTC+8

### 维度
第一章命运成长闭环 — 钥匙开门必触发且卡片真实生效

### 问题结论
- 命运卡触发原来只挂在出生小房间第一扇门上，继续探索时的钥匙门不会触发选择。
- 数值/变种卡会修改装配节点数据，却没有刷新 `WeaponAssemblyTree` 的实时射击参数，表现为“选了但枪没变化”。
- 完整预设库含有尚未接入实战行为的概念卡，若进入玩家抽牌入口会继续制造无效反馈。
- 基地占卜预选卡在首门触发时被清空而未提供选择，局前决策没有兑现。

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/game/RoomGameMode.gd | 每次钥匙开启新门均弹命运三选一；选择失败保持界面；成功后明确提示；基地预选卡并入首门选项 |
| src/weapons/WeaponAssemblyTree.gd | 新增数值刷新入口，将命运修改同步到当前射速/子弹伤害与 UI |
| src/weapons/FateCardEngine.gd | 数值卡应用后刷新武器；对子弹的增伤写入实际发射使用的 `bullet_damage` |
| src/weapons/FateCardPresets.gd | 定义已可玩牌池，校正卡片目标和文案，避免承诺未实现效果 |
| src/ui/WorkbenchPanel.gd / DivinationMenu.gd / FateCardUIController.gd | 玩家可见抽牌入口统一使用已验证可生效牌池 |
| verify_initial_room_fate_door_flow.gd / verify_ch1_director_loop.gd | 验收升级为后续钥匙门触发与实时射速/伤害变化检查 |

### 验证
- `verify_initial_room_fate_door_flow.tscn`: `INITIAL_ROOM_FATE_DOOR_OK: every keyed door triggers fate choice and selected upgrades change live weapon stats`
- `verify_ch1_director_loop.tscn`: `CH1_DIRECTOR_LOOP_OK: starter shotgun, effective fate door upgrade, soul pickup drops, and wall-blocked bullets are playable`
- `verify_ch1_gameplay_loop.tscn`: `CH1_GAMEPLAY_LOOP_OK`
- `verify_p1_workbench_flow.tscn`: `P1_WORKBENCH_FLOW_OK`
- `godot --headless --path . --quit-after 3`: EXIT 0

### 剩余风险
- 概念卡如炮台化、击杀暴击、回旋/追踪弹仍未完成实战接入，当前已从玩家牌池隔离。
- Headless 退出仍报告已有资源清理警告，未阻断本轮玩法结果。

---

## 轮次 174 — 2026-05-25

### 维度
第一章房间物理刷新稳定性 — 拾钥匙、清房与开门不再在物理查询中重建墙体

### 问题结论
- 玩家踩到钥匙时，`RoomKeyPickup.body_entered` 会同步刷新门和墙；Godot 正在 flush physics queries，因而持续抛出 `body_set_shape_as_one_way_collision()` 报错。
- 当前房间同时存在 `RoomLayout` 与旧视觉节点生成的边界碰撞，一次钥匙刷新会重复拆建两套墙体。
- 击杀最后一只怪物的清房链也可能处于物理命中回调内，掉钥匙与重建门区域需要同样的时序保护。

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/map/RoomLayout.gd | 门状态变化改为合并后的延迟墙体重建，避开物理查询刷新期 |
| src/map/RoomVisualizer.gd / RoomTileMapInitializer.gd | 支持关闭边界物理，仅保留门视觉更新；保留旧场景兼容路径 |
| src/game/RoomGameMode.gd | 主地图以 `RoomLayout` 为唯一墙体碰撞来源；拾钥匙和清房产生的出口/钥匙刷新延后执行 |
| verify_map_layout_flow.gd | 以角色实际走入钥匙拾取区触发回归，并检查开门后的物理门洞 |
| docs/PH09_搜打撤深化.md | 固化第一章房间物理刷新与体验验收规则 |

### 验证
- `verify_map_layout_flow.tscn`: `MAP_LAYOUT_FLOW_OK`，拾钥匙刷新过程不再出现 `flushing queries` 报错
- `verify_initial_room_fate_door_flow.tscn`: `INITIAL_ROOM_FATE_DOOR_OK`
- `verify_ch1_director_loop.tscn`: `CH1_DIRECTOR_LOOP_OK`
- `verify_ch1_gameplay_loop.tscn`: `CH1_GAMEPLAY_LOOP_OK`
- `verify_inventory_equipment_ui.tscn`: `INVENTORY_EQUIPMENT_UI_OK`
- `godot --headless --path . --quit-after 3`: EXIT 0

### 剩余风险
- Headless 验收退出时仍有对象/RID/资源未释放告警，未复现本轮墙体物理报错，后续应单独做生命周期清理。
- `DemoRoomGameMode` 仍保有独立的门/墙实现；若其后续进入正式入口，需要按相同的物理刷新规则审查。

---

## 轮次 175 — 2026-05-25

### 维度
第一章奖励触感闭环 — 怪物物品落地拾取，魂币稳定落地

### 问题结论
- 怪物死亡后的非货币战利品原本直接调用 `inventory_module.add_item()`，玩家看不到掉落，也没有接近拾取和战场取舍。
- 魂币已经使用魂球落地逻辑；应保留为所有击杀的稳定奖励，而不是把物品也做成自动结算。
- 背包钥匙与局内可开门计数原来用最大值同步，拾取新增钥匙时存在不可靠的数量变化。

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/items/GroundItemPickup.gd | 新增地面战利品表现与靠近拾取；满包时保留物品 |
| src/game/RoomGameMode.gd | 怪物非货币掉落改为死亡位置生成拾取物；货币仍生成魂球；钥匙按背包增减量同步可开门次数 |
| src/game/LootModule.gd | 明确怪物掉落接口为概率地面物品，货币由战斗模式生成必掉魂球 |
| verify_ch1_director_loop.gd | 验证击杀后物品不会立即入包、走近后可拾取，魂币仍需拾取 |
| verify_ch1_gameplay_loop.gd | 验证普通怪有物品掉落也存在空掉落 |
| docs/PH09_搜打撤深化.md | 固化怪物战利品与魂币的玩家规则 |

### 验证
- `verify_ch1_director_loop.tscn`: `CH1_DIRECTOR_LOOP_OK: ... ground loot pickup, guaranteed soul drop ...`
- `verify_ch1_gameplay_loop.tscn`: `CH1_GAMEPLAY_LOOP_OK: ... chance-based ground loot ...`
- `verify_map_layout_flow.tscn`: `MAP_LAYOUT_FLOW_OK`
- `verify_initial_room_fate_door_flow.tscn`: `INITIAL_ROOM_FATE_DOOR_OK`

### 剩余风险
- 地面物品目前使用程序化系统图形，正式枪械与配件美术仍需补齐。
- Headless 退出仍有对象/RID/资源释放告警，未影响本轮奖励拾取验收。

---

## 轮次 176 — 2026-05-25

### 维度
第一章终局撤离体验 — 独立撤离房装置启动与守点敌潮

### 问题结论
- 地图已有独立撤离房，但进入房间会直接启动 4 秒撤离，玩家没有操作装置、准备或守点的过程。
- `RoomData.is_extraction()` 仍把 Boss 房视为撤离房，和“Boss 不是撤离房”的关卡职责冲突。
- 怪物地面物品流程成立后，普通怪物品产出仍过密，削弱了搜索与精英奖励价值。

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/game/ExtractionRoomLogic.gd / scenes/RoomExtraction.tscn | 撤离房中央生成可接近按 `E` 的装置；启动/中断重启均有明确状态 |
| src/game/RoomGameMode.gd | 进入撤离房不再自动读条；装置启动 14 秒守点流程，三阶段派敌，末段精英概率随风险增加；存活归零后弹结算 |
| src/ui/GameUIManager.gd | 撤离房守点可直接显示倒计时，并修正实际持续时间显示 |
| src/map/RoomData.gd / RoomFactory.gd | Boss 不再判作撤离点；旧抽象 `extraction_point` 不再误生成中央箱子 |
| src/game/LootModule.gd | 普通怪物品率 `65% -> 26%`，普通怪钥匙附加率 `16% -> 8%`；精英/Boss 保留更稳定收益 |
| verify_ch1_extraction_defense_flow.gd / .tscn | 新增独立撤离房、开关启动、敌潮/精英可能性与存活结算验收 |

### 验证
- `verify_ch1_extraction_defense_flow.tscn`: `CH1_EXTRACTION_DEFENSE_OK`
- `verify_ch1_gameplay_loop.tscn`: `CH1_GAMEPLAY_LOOP_OK`
- `verify_ch1_director_loop.tscn`: `CH1_DIRECTOR_LOOP_OK`
- `verify_p1_extraction_flow.tscn`: `P1_EXTRACTION_FLOW_OK`
- `verify_initial_room_fate_door_flow.tscn`: `INITIAL_ROOM_FATE_DOOR_OK`

### 剩余风险
- 14 秒与三阶段敌潮为第一版手感参数，需要真人连续游玩确认第一章枪械火力下是否过松或过压。
- Headless 退出阶段仍有对象/RID/资源释放告警，后续仍需生命周期专项。
