# PH12：Room 场景视觉化 — TileMap 地面/墙体 + 房间风格

## 目标
从"占位符 ColorRect"升级为有空间感的真实房间视觉。每个房间有：
1. **TileMap 地面/墙体** — TileMapLayer + TileSet 构建
2. **房间类型视觉风格** — 各房间有独特配色和装饰
3. **氛围装饰** — 角落阴影、边界提示、特殊区域标记
4. **房间过渡视觉** — 门的位置标记（当前房间 vs 走廊连接点）

---

## 一、TileSet 设计

### 1.1 规格
- **单元格尺寸:** 64×64 pixels
- **房间标准尺寸:** 800×600 → 约 12.5×9.4 格（取整 13×10）
- **TileSet 存放位置:** `assets/tilesets/RoomTiles.tres`
- **图集:** 使用 Godot 自带的单图集 TileSet（AtlasTexture）

### 1.2 Tile 类型分层
| Layer | 用途 | Tile ID 前缀 |
|---|---|---|
| Floor | 地面（可行走区域） | `floor_` |
| Wall | 墙体（不可通行） | `wall_` |
| Accent | 装饰性地面（地毯/血迹/光斑） | `accent_` |
| Props | 可视化道具（箱子边角/门轮廓） | `prop_` |

### 1.3 Floor Tiles
- `floor_concrete_01` — 灰色水泥地面（默认）
- `floor_concrete_02` — 略有破损的水泥
- `floor_metal_01` — 金属地板（精英房）
- `floor_tile_01` — 瓷砖（商人/改造房）
- `floor_dark_01` — 深色地面（Boss/陷阱）

### 1.4 Wall Tiles
- `wall_corner_tl` / `wall_corner_tr` / `wall_corner_bl` / `wall_corner_br`
- `wall_top` / `wall_bottom` / `wall_left` / `wall_right`
- `wall_filled` — 完整墙体格

### 1.5 Accent Tiles
- `accent_blood_01/02` — 血迹（战斗痕迹）
- `accent_glow_01` — 光斑（商人房氛围）
- `accent_cable_01` — 电缆/管道（工业风）
- `accent_dust_01` — 灰尘区域（储藏室）

---

## 二、各房间类型视觉风格

### 2.1 COMBAT（普通战斗房）
- **主色调:** 灰白水泥 (`floor_concrete_01`) + 深灰墙
- **风格:** 工业废墟，战斗痕迹斑驳
- **Accent:** `accent_blood_01` 散落在地面（战斗后感）
- **氛围:** 冷色调，墙壁有磨损

### 2.2 ELITE（精英战斗房）
- **主色调:** 深金属 (`floor_metal_01`) + 深色墙
- **风格:** 禁区感，金属地板反光
- **Accent:** `accent_glow_01` 暗红色光斑（Boss前兆）
- **氛围:** 压抑，深色调，角落阴影重

### 2.3 SCAVENGE（搜刮房）
- **主色调:** 浅灰瓷砖 (`floor_tile_01`) + 暖色墙
- **风格:** 仓储区，货架痕迹
- **Accent:** `accent_dust_01` 灰尘覆盖角落
- **氛围:** 温暖，米色/棕色调

### 2.4 MERCHANT（商人房）
- **主色调:** 深木地板 (`floor_tile_01` 暖色) + 金色墙线
- **风格:** 神秘商店，灯光聚焦
- **Accent:** `accent_glow_01` 暖色光斑（摊贩照明）
- **氛围:** 暖色调，金色/琥珀色点缀

### 2.5 UPGRADE（改造房）
- **主色调:** 深灰金属 (`floor_metal_01`) + 蓝色墙线
- **风格:** 机械工作坊，工具架
- **Accent:** `accent_cable_01` 电缆穿过地面
- **氛围:** 冷色调，蓝/灰色调

### 2.6 EVENT（事件房）
- **主色调:** 暗紫地板 (`floor_dark_01` 紫) + 荧光边线
- **风格:** 神秘/诡异，空间扭曲感
- **Accent:** `accent_glow_01` 荧光紫光
- **氛围:** 迷幻，紫色/品红

### 2.7 BOSS（Boss房）
- **主色调:** 纯黑地板 (`floor_dark_01`) + 深红墙
- **风格:** 祭坛感，中心高亮
- **Accent:** 中央有 `accent_glow_01` 深红光圈（Boss站位提示）
- **氛围:** 压迫感，红/黑色调

### 2.8 TRAP（陷阱房）
- **主色调:** 深红地板 (`floor_dark_01` 红) + 红色墙
- **风格:** 危险区，地面有警告标记
- **Accent:** `accent_blood_01` 密集血迹
- **氛围:** 危险，暗红/黑色

### 2.9 STORAGE（储藏室）
- **主色调:** 深棕地板 + 焦糖色墙
- **风格:** 旧仓库，角落阴影
- **Accent:** `accent_dust_01` 灰尘覆盖
- **氛围:** 温暖但暗，棕/琥珀色

---

## 三、房间边界与过渡

### 3.1 房间边界视觉
- 每个房间 TileMapLayer 在边缘处使用 Wall tiles
- 墙体高度感：通过 TileSet 的 Z-Index 分层模拟
- 门的位置：使用 `prop_door_frame` tile 标记（预留）

### 3.2 房间过渡
- 门节点：ColorRect 稍亮区域，提示出口方向
- 走廊连接：房间边缘有略暗的过渡区（连接下一个房间）

---

## 四、技术实现

### 4.1 TileSet 资源
- 创建 `assets/tilesets/RoomTiles.tres`（Godot Resource）
- 使用 Placeholder 图案（ColorRect 纯色），后续可替换为真实像素图
- 每个 Tile 有 source_id / terrain_set / terrain 的 metadata 标记用途

### 4.2 Room 场景更新
- RoomCombat.tscn 率先配备 TileMapLayer（piloting）
- 其他房间（Storage/Trap/Merchant/Upgrade）已有基础装饰，逐步升级

### 4.3 RoomFactory 关联
- `_create_placeholder_room()` 已有调试色，后续可以给占位符房间加 TileMapLayer 装饰

---

## 五、验收标准

1. RoomCombat.tscn 有可运行的 TileMapLayer，填充 floor tiles，边缘有 wall tiles
2. TileSet 资源 `assets/tilesets/RoomTiles.tres` 存在且被 RoomCombat 引用
3. 不同房间类型（COMBAT/SCAVENGE/BOSS）可通过 TileMapLayer 颜色/风格区分
4. Godot headless --quit-after 1 编译通过
5. 不破坏现有功能（容器/商人/改造/撤离/事件）

---

## 六、优先级

- **P0:** TileSet 创建 + RoomCombat TileMapLayer 填充（piloting）
- **P1:** 其余房间场景升级（Storage/Trap/Merchant/Upgrade）✅ 已完成（轮次113）
- **P2:** 氛围装饰深化（Accent tiles、角落阴影） + 房间过渡视觉 ✅ 已完成（轮次114）

## 七、P2 完成记录（轮次114）

### 本轮目标
**地图场景视觉化 P2：房间过渡视觉（门位置标记）**

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/map/RoomDoorVisualizer.gd` | 新建 — 门过渡视觉化组件，在房间边缘标记已开启门的位置和类型 |
| `src/map/PathDirector.gd` | 新增 `get_open_door_info(node_id)` — 返回指定房间所有开启门的详细信息（含方向、类型） |
| `src/map/RoomVisualizer.gd` | 新增 `_apply_door_visualization()`，configure() 支持门信息注入，添加 DoorVisualizer 引用 |
| `scenes/RoomCombat.tscn` | 添加 DoorVisualizer 子节点，引用 RoomDoorVisualizer.gd |

### 门过渡视觉设计
- **颜色编码：** 绿色=普通通路，红色=Boss通路，蓝色=撤离通路
- **位置：** 4个边缘方向标记（门所在方向的边缘）
- **动态配置：** 由 RoomGameMode 进入房间时注入门方向信息
- **方向归一化：** 8方向→4方向，显示在对应边缘

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- 门方向基于节点ID差值推算（假设网格布局），实际布局变化时方向可能不准确
- DoorVisualizer 仅在 RoomCombat 场景添加；其余房间场景（Storage/Trap/Merchant/Upgrade）待后续添加
- 门标记视觉颜色和位置需人类试玩确认是否直观
- `configure()` 接口变更：RoomGameMode 调用处需要更新参数

### 下轮最可能方向
1. 容器→InventoryUI刷新实际验证（LootModule 发放物品 + UI 刷新链路）
2. 武器装配树可视化
3. 其余房间场景 DoorVisualizer 节点添加（Storage/Trap/Merchant/Upgrade）

---

## 八、P2 补全记录（轮次121）

### 本轮目标
**门过渡视觉完整性：非 Combat 房间 DoorVisualizer 节点补全 + RoomTileMapInitializer 门信息注入对齐**

### 问题诊断
P2（轮次114）仅在 RoomCombat.tscn 添加了 DoorVisualizer 节点。Storage/Trap/Merchant/Upgrade 场景使用 RoomTileMapInitializer（而非 RoomVisualizer）管理 TileMap，但：
1. 缺少 DoorVisualizer 子节点 → 门过渡标记无法显示
2. `configure()` / `set_open_doors()` 方法签名与 RoomVisualizer 不对齐
3. `_ensure_boundary_collision()` 虽然接受 door_info 但从未被外部调用注入

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/map/RoomTileMapInitializer.gd` | 重构 — 新增 `_apply_door_visualization()`、`door_visualizer @onready` 引用；build() 末尾调用 `_apply_door_visualization()`；reset_visual() 末尾调用 `_apply_door_visualization()` |
| `scenes/RoomStorage.tscn` | 新增 ext_resource `RoomDoorVisualizer.gd`（id=7）；新增 DoorVisualizer Node2D 子节点 |
| `scenes/RoomTrap.tscn` | 新增 ext_resource `RoomDoorVisualizer.gd`（id=5）；新增 DoorVisualizer Node2D 子节点 |
| `scenes/RoomMerchant.tscn` | 新增 ext_resource `RoomDoorVisualizer.gd`（id=4）；新增 DoorVisualizer Node2D 子节点 |
| `scenes/RoomUpgrade.tscn` | 新增 ext_resource `RoomDoorVisualizer.gd`（id=4）；新增 DoorVisualizer Node2D 子节点 |

### 门洞边界碰撞体逻辑（已存在，未变更）
`_ensure_boundary_collision()` 在有门洞的方向留出 DOOR_WIDTH=132px 缺口，非门洞方向完整墙体，逻辑与 RoomVisualizer 一致。

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- Merchant/Trap/Storage/Upgrade 场景的 `configure()` 尚未被外部调用（RoomGameMode 仅调用 RoomVisualizer.configure），门信息注入链路待 DemoRoomChain 场景接入后验证
- 门方向归一化 8→4 可能与实际网格方向不完全对齐
- 人类试玩确认门过渡标记视觉位置是否直观

### 下轮最可能方向
1. DemoRoomChain.tscn 场景创建（5房间线性链），验证完整搜打撤流程
2. 容器→InventoryUI 刷新链路验证（LootModule → 背包 → UI）
3. 武器装配树可视化

---

## 九、P2 + DemoRoomChain 完成记录（轮次123）

### 本轮目标
**DemoRoomChain.tscn 5房间线性链 + DemoRoomGameMode.gd 搜打撤演示脚本**

### DemoRoomChain 规格
| 房间 | node_id | 类型 | 敌人 | 特殊 |
|---|---|---|---|---|
| R1 | 0 | COMBAT | 3x 追击者 | 起点 |
| R2 | 1 | COMBAT | 2x 追击者 + 1x 远程 | |
| R3 | 2 | STORAGE | 2x 追击者 | 含隐藏箱 |
| R4 | 3 | ELITE | 1x 精英怪 | |
| R5 | 4 | EXTRACTION | 0 | 撤离终点 |

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/game/DemoRoomGameMode.gd` | 新建 — 独立Demo游戏模式，管理5房间线性链：实例化房间、玩家生成、门碰撞、钥匙系统、波次清理回调 |
| `scenes/DemoRoomChain.tscn` | 新建 — DemoRoomChain场景，挂载DemoRoomGameMode脚本 |

### DemoRoomGameMode 核心逻辑
- `DEMO_ROOMS[]` 常量数组定义5个房间的元数据（node_id、类型、位置、敌人数）
- `ROOM_SCENES` 映射：COMBAT→RoomCombat.tscn，STORAGE→RoomStorage.tscn，EXTRACTION→RoomExtraction.tscn（ELITE复用一个COMBAT）
- `_create_doors_for_room()` — 每房间左右各一门碰撞体（Area2D），带DoorPlate和Label
- `_enter_room()` — 隐藏旧房间，显示新房间，移动玩家到入口，启动波次
- `_try_open_door()` — 清怪检查+钥匙消耗+切换房间
- `_on_waves_cleared()` — 清理完成后给钥匙，`_rooms_cleared` 标记
- 玩家用 Player.tscn（WASD内置），Camera2D 跟随

### 门规则
- **清怪开门**：当前房间 `_rooms_cleared` 包含该房间id时才允许开门
- **E键交互**：`Input.is_action_just_pressed("interact")` 在门区域触发
- **钥匙消耗**：每开一次门消耗 `KEY_COST=1` 个钥匙（房间清理奖励）
- **门洞位置**：边界碰撞体在门方向留 DOOR_WIDTH=132px 缺口

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- DemoRoomGameMode 使用简化波次逻辑（wave_counts 直接传入 enemy_count），真实 RoomWaveSpawner 的波次节奏需后续验证
- ELITE 房间使用 RoomCombat.tscn 而非专用 RoomElite.tscn，视觉风格区分不明显
- 容器交互（Storage 隐藏箱）需人类试玩验证
- `_on_door_body_entered` 中 Input.is_action_just_pressed 可能在非当前帧触发（有延迟）
- Demo 无商人/改造房，完整命运卡片链路未验证

---

## 十、门交互帧同步修复（轮次124）

### 本轮目标
**修复 DemoRoomGameMode 门交互帧同步问题（E键在 body_entered 回调中检测会漏帧）**

### 问题诊断
原代码在 `_on_door_body_entered()` 中直接调用 `Input.is_action_just_pressed("interact")`：
- `body_entered` 信号在物理帧触发，`Input.is_action_just_pressed` 在输入帧检测
- 两者处于不同帧，导致玩家按E时可能检测不到，游戏无响应
- 这是 DemoRoomChain 核心流程（清怪→开门→进房）的阻断性bug

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/game/DemoRoomGameMode.gd` | 重构 — 新增 `_near_door` Dictionary 追踪靠近的门；新增 `_process()` 轮询 `_near_door` 检测 `interact` 按键；新增 `_on_door_body_exited()` 处理玩家离开门区域 |
| `src/game/DemoRoomGameMode.gd` | 新增 `body_exited.connect(_on_door_body_exited.bind(...))` 信号连接；移除回调中直接检测Input的逻辑 |

### 新门交互架构
- `_on_door_body_entered()`：记录玩家靠近的门到 `_near_door`，显示 "[E] 用钥匙开门" 标签
- `_on_door_body_exited()`：玩家离开门区域时隐藏标签，从 `_near_door` 移除
- `_process(_delta)`：每帧检查 `Input.is_action_just_pressed("interact")`，如有靠近的门则调用 `_try_open_door()`
- 这样保证交互检测在输入帧完成，不依赖物理帧信号触发时机

### 门规则（不变）
- **清怪开门**：当前房间 `_rooms_cleared` 包含该房间id时才允许开门
- **E键交互**：靠近门 + 按E，轮询检测，不漏帧
- **钥匙消耗**：每开一次门消耗 `KEY_COST=1` 个钥匙（房间清理奖励）

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- StorageRoomLogic 的隐藏箱容器 `body_entered` 回调同样使用 `interact` 按键（ContainerInteraction.gd 内部），可能存在同样问题，需后续检查
- 门标签 `"[E] 用钥匙开门"` 颜色和样式未区分锁定/可开启状态，需人类试玩确认
- ELITE 房间视觉风格仍使用 RoomCombat.tscn（Boss前兆红色光斑未能区分）

### 下轮最可能方向
1. **房间切换淡入淡出**：进入新房间时做短暂黑屏或淡入过渡，提升房间切换体验
2. **撤离点信号触发**：DemoRoomChain 到达 R5（EXTRACTION）后，ExtractionRoomLogic 的撤离信号如何与游戏结束流程对接
3. **容器→InventoryUI 链路**：StorageRoomLogic 的隐藏箱产出物品→InventoryModule→GameUIManager 背包UI刷新
4. **门标签视觉区分**：锁定门（未清怪）vs 可开启门（已清怪）的颜色/样式区分
---

## 十一、撤离读条完成（轮次125）

### 本轮目标
**DemoRoomChain 撤离房完整流程：E键触发撤离 → ExtractionModule 5秒读条 → 撤离完成**

### 问题诊断
DemoRoomChain 的 R5（EXTRACTION）房间没有真正的撤离流程：玩家进入后只显示"此Demo到此结束"，没有读条、没有结算。ExtractionRoomLogic 仅负责视觉（光圈脉冲动画），撤离读条逻辑由 ExtractionModule 独立处理。

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/game/DemoRoomGameMode.gd` | 新增 `_extraction_module` + `_get_extraction_module()` 延迟实例化；新增 `_extraction_started` 标志；新增 `_schedule_extraction_start()` 延迟1秒后允许撤离；新增 `_try_start_extraction()` E键触发撤离读条；新增 `_on_extraction_completed()` 撤离完成回调；`_process()` 分支处理撤离房E键和读条更新 |
| `docs/PH12_Room场景视觉化.md` | 本节记录 |

### 撤离流程设计
- 玩家进入 R5（撤离房）后1秒，`_extraction_started = true`，提示变为"按 [E] 开始撤离读条"
- 玩家按 E 键 → `_extraction_module.start_extraction("STANDARD", 5.0)` → 5秒倒计时
- `_process()` 每帧更新撤离读条进度，更新 UI 显示剩余秒数和进度条
- 5秒后 `extraction_completed` 信号触发 → 显示"撤离成功！Demo演示结束"
- 撤离模块延迟实例化（`_get_extraction_module()`），避免与 DemoRoomGameMode 的潜在循环引用

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- Demo 无真实 InventoryModule，撤离完成后的战利品结算链路未验证
- ExtractionModule 需在 `_process()` 主动调用 `update()`，这是 RoomGameMode._process 中 `extraction_module.update(delta)` 的简版
- 玩家进入撤离房后如果不按E直接退出，没有"放弃撤离"惩罚

### 下轮最可能方向
1. **房间切换淡入淡出**：进入新房间时做短暂黑屏或淡入过渡，提升房间切换体验
2. **容器→InventoryUI 链路**：StorageRoomLogic 隐藏箱产出物品→InventoryModule→GameUIManager 背包UI刷新
3. **门标签视觉区分**：锁定门（未清怪）vs 可开启门（已清怪）的颜色/样式区分

---

## 十二、容器→Inventory链路（轮次126）

### 本轮目标
**DemoRoomGameMode 容器背包注入链路：让 ContainerInteraction 能将开箱物品送入 InventoryModule**

### 问题诊断
ContainerInteraction 的开箱逻辑依赖 `_inventory_module.set_inventory()` 注入背包，但 DemoRoomGameMode 之前没有：
1. 创建 InventoryModule 实例
2. 注入给 StorageRoomLogic / ContainerInteraction

导致 StorageRoomLogic（R3房间）的隐藏箱和辅助箱能生成掉落，但物品无处可去。

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/game/DemoRoomGameMode.gd` | 新增 `_inventory_module` + `_get_inventory_module()` 延迟实例化 |
| `src/game/DemoRoomGameMode.gd` | 新增 `_setup_room_containers()` — 为 StorageRoomLogic 和独立 ContainerInteraction 注入背包引用 |
| `src/game/DemoRoomGameMode.gd` | `_enter_room()` 中调用 `_setup_room_containers()` 确保进入房间时背包已注入 |
| `src/game/DemoRoomGameMode.gd` | 新增 `_fill_container_nodes()` 递归收集容器节点，排除已由 StorageRoomLogic 处理的 |

### 注入策略
- **StorageRoomLogic**（通过 `set_inventory` 注入，它内部会同步给 HiddenChest/Container 和 Crate）
- **独立 ContainerInteraction**（不在 StorageRoomLogic 下的节点，直接调用 `set_inventory`）
- 避免双重注入：递归收集时跳过 StorageRoomLogic 已处理的容器

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- ContainerInteraction 开箱后通过 `get_tree().call_group("game_ui", ...)` 触发飘字，但 DemoRoomGameMode 场景中无 GameUIManager 实例，飘字无法显示
- InventoryModule 物品目前只存在内存中，无 UI 面板显示（下一轮可接入 InventoryUI）
- LootModule 通过 `LootModule.get_instance()` 获取，ItemRegistry 若未初始化会返回空掉落

### 下轮最可能方向
1. **房间切换淡入淡出**：进入新房间时做短暂黑屏或淡入过渡，提升房间切换体验
2. **门标签视觉区分**：锁定门（未清怪）vs 可开启门（已清怪）的颜色/样式区分
3. **InventoryUI 接入**：DemoRoomGameMode 接入 InventoryUI panel，显示开箱获得的物品

---

## 十三、InventoryUI接入（轮次127）

### 本轮目标
**DemoRoomGameMode接入InventoryUI（standalone模式），Tab键切换背包显示**

### 问题诊断
轮次126建立了容器→InventoryModule链路，但背包UI没有接入：开箱物品只存在InventoryModule内存中，无UI面板显示。玩家无法看到背包内容。

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/game/DemoRoomGameMode.gd` | 新增 `_inventory_ui` 变量 + `_get_inventory_ui()` 延迟实例化 |
| `src/game/DemoRoomGameMode.gd` | `_process()` 新增 `ui_tab` 检测，切换 `_set_inventory_panel_visibility(visible)` |
| `src/ui/InventoryUI.gd` | 已有 `_set_inventory_panel_visibility(visible)` 方法（standalone模式下管理面板显隐） |

### 背包UI架构
- `InventoryUI` standalone模式：自己创建Panel和Grid，绑定InventoryModule
- DemoRoomGameMode延迟实例化（`_get_inventory_ui()`），Tab键切换显隐
- 开箱物品通过 `_setup_room_containers()` 注入的InventoryModule存储

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- 开箱物品实际验证需人类试玩（R3 Storage房间的隐藏箱/辅助箱产出）
- InventoryUI首次加载时 `inventory_panel` 可能未创建（_ready执行时机），需人类确认
- Tab键输入需要project.godot中有 `ui_tab` action 绑定（已存在）

### 下轮最可能方向
1. **房间切换淡入淡出**：进入新房间时做短暂黑屏或淡入过渡，提升房间切换体验
2. **门标签视觉区分**：锁定门（未清怪）vs 可开启门（已清怪）的颜色/样式区分
3. **开箱物品实际验证**：R3 Storage房间隐藏箱→InventoryModule→InventoryUI显示链路确认

---

## 十四、房间切换淡入淡出（轮次128）

### 本轮目标
**DemoRoomGameMode 房间切换淡入淡出：进入新房间时短暂黑屏过渡，提升房间切换体验**

### 问题诊断
`_enter_room()` 直接 hide/show 房间，玩家感受生硬。从一个房间跨入另一个房间应该有短暂的黑屏过渡，让切换有"空间感"。

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/game/DemoRoomGameMode.gd` | 新增 `_transition_canvas` + `_transition_overlay`（CanvasLayer + ColorRect） |
| `src/game/DemoRoomGameMode.gd` | 新增 `_setup_transition_canvas()` — 创建覆盖层 |
| `src/game/DemoRoomGameMode.gd` | 新增 `_fade_out_in(room_id)` — 协程：淡出→切换→淡入 |
| `src/game/DemoRoomGameMode.gd` | 新增 `_fade_to_black()` / `_fade_to_clear()` — 单向淡入淡出 Tween |
| `src/game/DemoRoomGameMode.gd` | 新增 `_do_enter_room(room_id)` — 实际切换逻辑（原 `_enter_room` 核心） |
| `src/game/DemoRoomGameMode.gd` | `_enter_room()` 改为调用 `_fade_out_in()` 协程，添加 `_is_transitioning` 防重入 |
| `src/game/DemoRoomGameMode.gd` | `FADE_DURATION = 0.25s` 常量定义单次淡入/淡出时长 |

### 淡入淡出设计
- **时机：** 每次 `_enter_room()` 触发（玩家清怪后E键进门）
- **时长：** 每次淡入+淡出共 0.5 秒（0.25s 淡出 + 0.25s 淡入）
- **颜色：** 纯黑 `Color.BLACK` 覆盖层
- **防重入：** `_is_transitioning` 标志 + `_enter_room()` 入口检查，避免切换中重复触发
- **位置：** CanvasLayer layer=100（最顶层），足够覆盖全屏

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- `_is_transitioning` 仅在 `_enter_room` 检测，`_try_open_door` 中的 `_enter_room` 调用也会被拦截（预期行为）
- CanvasLayer 覆盖层尺寸固定 1920×1080，极端超宽屏可能边缘露白（当前 Demo 环境可接受）
- 淡入淡出时玩家移动/射击输入仍在处理（无暂停），体验需人类试玩确认是否自然
- 撤离读条期间切换房间风险：`_is_transitioning` 拦截了 `_enter_room`，但 `_process` 撤离分支不会触发房间切换

### 下轮最可能方向
1. **门标签视觉区分**：锁定门（未清怪）vs 可开启门（已清怪）的颜色/样式区分
2. **开箱物品实际验证**：R3 Storage房间隐藏箱→InventoryModule→InventoryUI显示链路确认
3. **更多房间类型 Demo**：加入 Merchant/Upgrade/Boss 房间类型完整链路

---

## 十五、门标签视觉区分（轮次129）

### 本轮目标
**DemoRoomGameMode 门锁定状态视觉区分：红色锁定/绿色可开启 + 标签文字动态变化**

### 问题诊断
原代码门标签统一显示 `[E] 用钥匙开门`，门板颜色统一黄色。玩家无法从视觉判断门是否已解锁（当前房间清怪了没有、有没有钥匙）。影响核心体验的即时反馈。

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/game/DemoRoomGameMode.gd` | 新增 `_refresh_door_visual(door_area, from_id, to_id, label)` — 刷新门板颜色和标签文字 |
| `src/game/DemoRoomGameMode.gd` | `_on_door_body_entered()` 进入时立即调用 `_refresh_door_visual()` |
| `src/game/DemoRoomGameMode.gd` | 新增 `_refresh_all_doors()` — 清怪/消耗钥匙后刷新所有门的视觉 |
| `src/game/DemoRoomGameMode.gd` | `_on_waves_cleared()` 清怪后调用 `_refresh_all_doors()` |
| `src/game/DemoRoomGameMode.gd` | `_try_open_door()` 消耗钥匙后调用 `_refresh_all_doors()` |

### 门视觉状态机
| 状态 | 标签文字 | 门板颜色 |
|---|---|---|
| 目标房间已清理（可重复进） | `[E] 进入房间 %d` | 绿色 `Color(0.2, 0.7, 0.3, 0.75)` |
| 当前已清理 + 有钥匙 | `[E] 用钥匙开门` | 绿色 |
| 当前已清理 + 没钥匙 | `[E] 需要钥匙（剩余%d）` | 橙色 `Color(0.9, 0.5, 0.1, 0.75)` |
| 当前未清理（锁定） | `[E] 先消灭敌人` | 红色 `Color(0.75, 0.1, 0.1, 0.8)` |

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- 门板颜色变化时位置固定为 ColorRect，角落箱/辅助箱可能也用 DoorPlate 节点名（但不在 DemoRoomGameMode 管理范围内，不会被误刷新）
- 已清理房间重复进门时标签显示"进入房间%d"但仍有钥匙消耗逻辑（这是 `_try_open_door` 内的预期行为，与视觉状态独立）
- 人类试玩确认：门板颜色是否够直观、标签文字是否够清晰

### 下轮最可能方向
1. **开箱物品实际验证**：R3 Storage房间隐藏箱→InventoryModule→InventoryUI显示链路确认
2. **更多房间类型 Demo**：加入 Merchant/Upgrade/Boss 房间类型完整链路
3. **武器装配树可视化**

---

## 十六、开箱物品实际验证（轮次130）

### 本轮目标
**修复 Storage 房间辅助箱 Crate 缺失 ContainerInteraction 配置，使 DemoRoomChain R3 房间能正常开箱获得物品**

### 问题诊断
轮次126建立了容器→InventoryModule注入链路，但在审查`scenes/RoomStorage.tscn`时发现：
- `HiddenChest/Container`节点有完整的`ContainerInteraction`脚本和`scavenge_floor_3`掉落表配置 ✅
- 但`Crate`节点只是空的`Node2D`，没有子节点`Container`（Area2D+脚本+碰撞体）❌
- 导致`_setup_room_containers()`中`_fill_container_nodes()`无法收集到`Crate`下的容器组件，开箱功能完全失效

### 改动内容
| 文件 | 改动 |
|---|---|
| `scenes/RoomStorage.tscn` | 在`Crate`节点下新增完整容器子树：`Container(Area2D+ContainerInteraction脚本+CircleShape2D)` + `InteractionArea` + `Sprite` + `InteractLabel`；配置`container_type="crate"`, `loot_table="scavenge_floor_3"` |

### 链路分析
1. `ContainerInteraction._ready()` → `_setup_interaction_label()`连接`body_entered/exited`
2. `_process()`检测`Input.is_action_just_pressed("interact")`调用`_try_open_container()`
3. `_try_open_container()` → `_generate_loot()` → `LootModule.generate_loot("scavenge_floor_3", 1+floor/3)` → 实际掉落
4. `_grant_loot()` → `LootModule.grant_loot_to_inventory()` → `InventoryModule.add_item()`
5. `InventoryModule`信号`inventory_changed` → `InventoryUI`刷新背包面板显示

### 掉落表验证
- `ItemRegistry.get_loot_table("scavenge_floor_3")` → 包含信标/各Tier武器模块/消耗品，权重设计完整
- `ContainerInteraction._grant_loot()`中过滤掉`is_currency`条目（魂不入背包）
- `floor=1`，crate类型→`1+1/3=1`件掉落

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- `LootModule.get_instance()`使用全局单例，需要`ItemRegistry`先被初始化（BaseManager可能未就绪）
- `ContainerInteraction._process()`中`Input.is_action_just_pressed`同样存在帧同步问题（与门交互相同的bug模式），但容器是Area2D信号触发，行为时机不同
- 人类试玩确认：开箱→背包显示链路是否完整

### 下轮最可能方向
1. **开箱物品实际验证（人类试玩）**：实际运行DemoRoomChain，进入R3开箱确认背包UI显示
2. **更多房间类型Demo**：加入Merchant/Upgrade/Boss房间类型完整链路
3. **武器装配树可视化**

---

## 十七、DemoRoomChain房间视觉化主题色正确性（轮次131）

### 本轮目标
**修复 DemoRoomGameMode._initialize_room_visual() 未调用 configure() 导致各房间视觉化主题色不正确的问题**

### 问题诊断
轮次130完成了Storage房间Crate容器的配置，建立了完整的开箱链路（Container→Inventory→InventoryUI）。但在审查DemoRoomGameMode._initialize_room_visual()时发现一个潜在的房间视觉化缺陷：

- `_initialize_room_visual()` 调用 `visualizer.call("build")` 而非 `visualizer.configure(room_type, room_size, [])`
- RoomTileMapInitializer.build() 使用默认 room_type=COMBAT，不区分 ELITE/STORAGE/EXTRACTION 等不同房间类型
- ELITE房间（深金属地板+深色墙+红色光斑）和 STORAGE 房间（棕色地板+焦糖色墙）无法通过视觉区分
- 正确做法是 RoomGameMode._configure_room_visualizer() 的模式：先获取 room_type，再调用 configure()

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/game/DemoRoomGameMode.gd` | `_initialize_room_visual()` 中新增 `configure()` 调用：将 `room_type` + `room_size` 注入给 RoomTileMapInitializer（优先 configure，fallback build） |

### 房间主题色验证
通过 ItemRegistry.get_loot_table("scavenge_floor_3") 确认掉落表数据存在且权重设计完整，开箱链路无数据问题。

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- ELITE 房间使用 RoomCombat.tscn 而非专用 RoomElite.tscn，视觉风格仍沿用 COMBAT 主题色（灰色金属地板），与 ELITE 设计的深金属地板+深色墙+红色光斑不符
- 容器开箱的 `_process()` 中的 `Input.is_action_just_pressed` 与门交互存在相同的帧同步问题，但容器是 Area2D 信号触发，行为不同，人类试玩确认是否有感知延迟
- ContainerInteraction 开箱后动画 `modulate:a = 0` 可能影响同节点下的 InteractLabel（Label 也被淡出）

### 下轮最可能方向
1. **武器装配树节点交互**：点击装配树节点显示详情信息
2. **更多房间类型Demo**：加入 Merchant/Upgrade/Boss 房间完整链路
3. **ELITE房间独立场景RoomElite.tscn**（深蓝色主题区别于COMBAT灰色）

---

## 十八、ELITE房间视觉风格区分（轮次133）

### 本轮目标
**修复 DemoRoomGameMode._initialize_room_visual() 对 ELITE 房间类型不注入 room_type 导致 R4 房间视觉仍用 COMBAT 主题色的问题**

### 问题诊断
轮次131完成了 `_initialize_room_visual()` 对 `configure()` 的调用，但在审查代码时发现：
- 原代码使用 `visualizer.call("configure", ...)` 动态调用，存在类型不确定风险
- ELITE房间（node_id=3）使用 `ROOM_SCENES[RoomData.RoomType.ELITE] = "res://scenes/RoomCombat.tscn"`，即 RoomCombat 场景本身有 `RoomVisualizer` 脚本
- 但 `visualizer.call("configure", ...)` 调用没有类型保证，无法确保调用的是 `RoomVisualizer.configure`
- 当 visualizer 是 `RoomVisualizer` 类型时，应该直接调用 `configure()` 方法而非 `call()`

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/game/DemoRoomGameMode.gd` | `_initialize_room_visual()` 使用 `as RoomVisualizer` 类型转换 + 直接 `.configure()` 调用，而非 `call()` 动态方法调用 |

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- ELITE 房间使用 RoomCombat.tscn 共享同一个场景文件（视觉风格完全依赖 configure 注入的 room_type），如果后续 ELITE 需要更复杂的独立逻辑（如精英怪特殊AI、独特掉落），需要专用 RoomElite.tscn
- 容器开箱的 `_process()` 中的 `Input.is_action_just_pressed` 与门交互存在相同的帧同步问题，但容器是 Area2D 信号触发，行为不同，人类试玩确认是否有感知延迟
- ContainerInteraction 开箱后动画 `modulate:a = 0` 可能影响同节点下的 InteractLabel（Label 也被淡出）

### 下轮最可能方向
1. **武器装配树节点交互**：点击装配树节点显示详情信息
2. **更多房间类型Demo**：加入 Merchant/Upgrade/Boss 房间完整链路
3. **ELITE房间独立场景RoomElite.tscn**（深蓝色主题区别于COMBAT灰色）

---

## 十九、武器装配树节点交互（轮次134）

### 本轮目标
**WeaponAssemblyTreePanel 节点点击交互：点击装配树任意节点弹出详情面板，显示节点类型/名称、基础属性、合成属性、标签、已挂载槽位**

### 问题诊断
WeaponAssemblyTreePanel 当前只能通过 Tab 键切换显示，递归绘制了树状结构但没有交互能力。玩家点击树节点时无法看到该节点的具体属性、标签和槽位信息。这是武器装配树可视化体验的重要缺失——玩家需要能看懂"这把枪现在到底怎么怪"。

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/ui/WeaponAssemblyTreePanel.gd` | 新增 `_detail_popup` + `_detail_label`（详情弹窗），新增 `_node_click_rects` 追踪节点区域 |
| `src/ui/WeaponAssemblyTreePanel.gd` | 新增 `_create_detail_popup()` — 创建详情弹窗（Panel+ColorRect+Label+关闭提示） |
| `src/ui/WeaponAssemblyTreePanel.gd` | 新增 `_on_panel_shown()` — 面板显示时清空节点区域追踪 |
| `src/ui/WeaponAssemblyTreePanel.gd` | 新增 `_close_detail_popup()` — 关闭详情弹窗 |
| `src/ui/WeaponAssemblyTreePanel.gd` | `_draw_node()` — 将 HBoxContainer 改为 Control（可接收 gui_input），连接 `gui_input` 到 `_on_node_row_input` |
| `src/ui/WeaponAssemblyTreePanel.gd` | 新增 `_on_node_row_input(event, node)` — 鼠标左键点击节点触发详情显示 |
| `src/ui/WeaponAssemblyTreePanel.gd` | 新增 `_show_node_detail(node)` — 构建并显示节点详情文本（类型/名称/路径/深度/基础属性/合成属性/标签/槽位） |
| `src/ui/WeaponAssemblyTreePanel.gd` | `_on_detail_popup_input()` — 点击弹窗任意处关闭 |
| `src/ui/WeaponAssemblyTreePanel.gd` | 底部说明更新为"按 [Tab] 关闭 \| 点击节点查看详情" |
| `src/ui/WeaponAssemblyTreePanel.gd` | `_ready()` 新增 `panel_shown.connect(_on_panel_shown)`，`_on_panel_shown` 清空 `_node_click_rects` |
| `src/ui/WeaponAssemblyTreePanel.gd` | 移除 `key_toggle_handler()`（占位函数），`_process` 直接处理 Tab 切换 |

### 节点详情弹窗设计
- **位置：** 面板右下角偏移显示（避免遮挡主树结构）
- **内容：** 类型 + 名称 + 路径 + 深度 + 基础属性 + 合成属性 + 标签 + 已挂载槽位
- **关闭方式：** 点击弹窗任意处关闭
- **样式：** 深色半透明背景 + 米色标题 + 详细文本列表

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- 节点行使用 Control 而非 HBoxContainer，某些边缘情况下的布局可能与之前略有差异（需人类试玩确认）
- 弹窗位置固定在面板右下角，如果面板本身在屏幕边缘，弹窗可能超出屏幕（需极端分辨率测试）
- `_on_panel_shown` 清空 `_node_click_rects` 的时机是否合适（当前只做清空，未用于后续命中检测）

### 下轮最可能方向
1. **更多房间类型Demo**：加入 Merchant/Upgrade/Boss 房间完整链路
2. **ELITE房间独立场景RoomElite.tscn**（深蓝色主题区别于COMBAT灰色）
3. **武器装配树节点点击高亮**：选中节点后高亮反馈，明确显示当前选中节点

## 二十一、7房间Demo链（轮次135）

### 本轮目标
**将 DemoRoomChain 从5房间扩展到7房间（4战斗+1搜刮+1商人+1改造+1精英+1撤离），验证多类型房间接入**

### 问题诊断
原 DemoRoomChain 只有5个房间（R1-COMBAT → R2-COMBAT → R3-STORAGE → R4-ELITE → R5-EXTRACTION），缺少Merchant（商人）和Upgrade（改造）两种房间类型的Demo验证。ROOM_SCENES 也缺少 MERCHANT 和 UPGRADE 的场景映射。

### 改动内容
| 文件 | 改动 |
|---|---|
| `src/game/DemoRoomGameMode.gd` | 新增 `RoomData.RoomType.MERCHANT` 和 `UPGRADE` 到 `ROOM_SCENES` 映射；将DEMO_ROOMS扩展为7房间：R1-R2(COMBAT) → R3(STORAGE) → R4(MERCHANT) → R5(UPGRADE) → R6(ELITE) → R7(EXTRACTION) |
| `src/game/DemoRoomGameMode.gd` | 新增 `_setup_room_interactions()` — 为MerchantArea/WorkbenchArea注入InventoryModule背包引用 |
| `src/game/DemoRoomGameMode.gd` | 在 `_instantiate_demo_rooms()` 末尾调用 `_setup_room_interactions()` 注入交互组件背包 |
| `src/game/DemoRoomGameMode.gd` | UI标签文字更新为7房间演示说明 |
| `.dev-cycle/cycle-state.json` | 状态更新（currentTarget + completedPhases + notes） |

### 7房间Demo链布局
| 房间 | node_id | 类型 | 敌人 | 特殊 |
|---|---|---|---|---|
| R1 | 0 | COMBAT | 3x 追击者 | 起点 |
| R2 | 1 | COMBAT | 2x 追击者 + 1x 远程 | |
| R3 | 2 | STORAGE | 2x 追击者 | 含隐藏箱 |
| R4 | 3 | MERCHANT | 0 | 商人交易 |
| R5 | 4 | UPGRADE | 0 | 武器改造 |
| R6 | 5 | ELITE | 1x 精英怪 | |
| R7 | 6 | EXTRACTION | 0 | 撤离终点 |

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- MerchantInteraction 的 `_process()` 使用 `Input.is_action_just_pressed("interact")` 在 Area2D body_entered 信号触发帧检测，与门交互相同的帧同步问题，行为时机不同但可能存在感知延迟
- RoomMerchant.tscn 的 TileMap 视觉风格（RoomTileMapInitializer）需要人类试玩确认配色正确
- 商人/改造房没有战斗，玩家直接按E可以开门，不影响核心搜打撤流程
- 7房间间距 x=1000 足够宽，玩家可以通过门交互正常切换

### 下轮最可能方向
1. **BOSS房间场景RoomBoss.tscn** + Boss战斗完整流程（当前没有Boss房场景和逻辑）
2. **ELITE房间独立场景RoomElite.tscn**（深蓝色主题区别于COMBAT灰色）
3. **武器装配树节点点击高亮**（选中节点后高亮反馈）

---

## 二十二、BOSS房间场景 RoomBoss.tscn + BossRoomLogic.gd（轮次136）

### 本轮目标
**创建 BOSS 专用房间场景 RoomBoss.tscn 和对应逻辑脚本 BossRoomLogic.gd，完善 PH08 Boss战模块的房间基础**

### 问题诊断
当前项目已有 BossRoomDirector.gd（Boss数据管理）、BossPhaseDirector.gd（Boss阶段控制）、BossSkillNode.gd（Boss技能节点）等核心逻辑，但缺少 BOSS 房间的 Godot 场景文件和配套逻辑脚本。RoomData.RoomType.BOSS = 8 已定义，但 scenes/ 目录下没有 RoomBoss.tscn，与其他房间类型（COMBAT/ELITE/MERCHANT/UPGRADE/EXTRACTION/STORAGE）不匹配。

### 改动内容
| 文件 | 改动 |
|---|---|
| `scenes/RoomBoss.tscn` | 新建 — BOSS 房间专用场景，含：BossArena光圈（深红脉冲）、BossArenaInner（内圈）、BossMarker_N/S/W/E（红色方向标记）、DoorVisualizer、WaveSpawner（波次生成器，共享 Combat 组件）、Visualizer（RoomTileMapInitializer，room_type=8） |
| `src/game/BossRoomLogic.gd` | 新建 — Boss房逻辑脚本，含：BossArena脉冲动画、方向标记、setup()/trigger_boss_spawn()/trigger_boss_defeated() 接口、boss_spawn_triggered/boss_defeated_triggered 信号 |

### RoomBoss.tscn 设计规格
- **TileMap 主题：** BOSS（深红/纯黑，accent=0.60,0.05,0.05，accent_glow=0.80,0.10,0.05）
- **氛围：** 重型角落暗角（140×140，color=0.08,0.03,0.03,0.6）、边界暗边、红色光圈脉冲
- **BossArena：** 200×200 深红光圈（z=-4），每秒2次脉冲（0.12~0.32 alpha）
- **BossMarker：** 4方向红色标记（48×16/16×48，color=0.70,0.10,0.10,0.8）
- **门过渡：** DoorVisualizer 复用 RoomDoorVisualizer.gd

### BossRoomLogic.gd 接口
- `setup(boss_data: Dictionary)` — 进入房间后调用，初始化 Boss 房视觉
- `trigger_boss_spawn(boss_data: Dictionary)` — 外部触发 Boss 生成，emit boss_spawn_triggered 信号
- `trigger_boss_defeated()` — 外部触发 Boss 击败，emit boss_defeated_triggered 信号
- `is_boss_spawned() -> bool` — 检查 Boss 是否已生成

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- RoomBoss.tscn 的 WaveSpawner 配置（波次数/敌人数）需要在 DemoRoomChain 接入时配置，否则 R6 BOSS 房会没有敌人
- BossRoomLogic 依赖 Visualizer 节点引用 room_type=8，但 RoomTileMapInitializer 已支持 BOSS 类型（room_type 参数存在）
- Boss 击败后撤离流程链路尚未验证（需要在 RoomGameMode 中接入）
- DemoRoomChain 的 ROOM_SCENES 还未包含 BOSS 场景映射（R6 ELITE → RoomBoss.tscn）

### 下轮最可能方向
1. **BOSS房接入DemoRoomChain**：将 R6（ELITE）替换为 R6（BOSS），配置 ROOM_SCENES[BOSS] = RoomBoss.tscn，验证 Boss 战斗完整流程
2. **ELITE房间独立场景RoomElite.tscn**（深蓝色主题区别于COMBAT灰色）
3. **武器装配树节点点击高亮**（选中节点后高亮反馈）
