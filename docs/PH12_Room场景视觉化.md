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