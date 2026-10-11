# master_office_layout · 区块00-主人的办公室

> ShellStorm2 顶视角射击搜打撤肉鸽 —— 98F 固定剧情层「区块00-主人的办公室」的 Blender 布局源。
> 取代原 98F 的程序化房间布局，作为一条**手工摆位的固定关卡**。

## 这一版交付了什么 / 没交付什么

| 项 | 状态 |
| --- | --- |
| Blender 布局源（`.blend` + `.layout.json` + 组件包清单） | ✅ 已交付（v002） |
| 渲染验收图（俯视 / 透视 / 各房间 / 纯墙俯视） | ✅ 已交付 |
| GLB 导出 + Godot PackedScene 装配 | ⛔ **本轮未做**（主人选择「先停在 Blender 源」） |
| 运行时接线（含 99F↔98F 楼梯末端门处理） | ⛔ **本轮未做**（主人选择「只交付 Blender 布局，运行时不动」） |

> 也就是说：**这一版没有任何 GDScript 被改动，也没导出 GLB。** 区块00 尚未接进运行时，
> 原 98F 程序化布局仍然生效。接线是下一轮的事。

## 当前正式来源

- 当前母版：`source/block_00_master_office_layout_v002.blend`
- 布局清单：`source/block_00_master_office_layout_v002.layout.json`
- Godot 侧占位清单：`source/block_00_master_office_layout_v002.godot.json`
- 历史版本：`source/block_00_master_office_layout_v001.blend`（已是废线，仅留追溯）

规则：当前 `.blend` 就是正式基线；后续更新时复制并提升版本号（`v002 -> v003`），
新文件完成后自动成为正式来源，历史版本保留不删。

## 目录结构

```text
master_office_layout/
├── source/                                     母版源与派生产物
│   ├── block_00_master_office_layout_v002.blend        ← 当前正式母版
│   ├── block_00_master_office_layout_v002.layout.json  摆位真源
│   ├── block_00_master_office_layout_v002.godot.json   Godot 侧占位（pending）
│   ├── block_00_master_office_layout_v001.blend        历史版本
│   └── renders/                                        验收渲染图
├── component_packages/                         本布局用到的组件包清单（6 份）
│   ├── architecture/{wall_standard_5m,wall_door_5m,door_5m,corner_l_5m}/
│   └── floor/{floor_tile_r01_c01,floor_tile_r01_c02}/
└── README.md
```

## 关卡设计

层高锚点：**98F**（99F 下方，与原 98 层同高）。房间沿 +X 单列排布，由西向东：

```text
(西) 办公室 15×20  ─门→  会议室 40×15  ─门→  走廊 5×20  ─门→  门厅 15×15  → (东) 出口 = 99F 楼梯末端门位
     x[-40,-25]            x[-25,15]            x[15,20]           x[20,35]
```

| room_id | 名称 | 尺寸 | x 范围 | y 范围 | 门 | plane_priority | use_corner_l |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `corridor` | 走廊 | 5×20 | [15, 20] | [-10, 10] | 西 2.5 / 东 2.5 | 0 | 否 |
| `meeting_room` | 会议室 | 40×15 | [-25, 15] | [-5, 10] | 西 2.5 / 东 2.5 | 1 | 是 |
| `master_office` | 办公室 | 15×20 | [-40, -25] | [-10, 10] | 东 2.5 | 2 | 是 |
| `lobby` | 门厅 | 15×15 | [20, 35] | [-5, 10] | 西 2.5 | 3 | 是（另有东出口） |

- **入口**：`lobby` 东侧 `(35.0, 2.5, 0.0)`。这就是原 99F→98F 楼梯间末端门位。
  本版**只留门洞、不挂门扇**（`exits.east = 2.5` 无 `DOORLEAF`）；「去掉这扇门」的**运行时口径**
  本轮未定义，留到下轮接线时一并处理。
- **邻接**（全部 `wall_axis = x`，门都开在 2.5 lane）：
  `lobby↔corridor@x=20`、`corridor↔meeting_room@x=15`、`meeting_room↔master_office@x=-25`。
- 各房间 y 范围不一致（办公室/走廊 20m，会议室/门厅 15m）⇒ 房间之间是**错位拼接**，
  产生额外的东西向封堵墙与 4 个 L 角件补角。

## 摆位模型（关键）

**lane 归属**（`placement_model` 字段）：

1. 把关卡拆成若干 **墙平面**（`x=常数` 或 `y=常数`）。
2. 每个平面按 **5m 切 lane**，全局 key = `int((中心 - 2.5) / 5)`。
3. 每个房间声明自己需要的 lane；**L 角件的每条臂各占 1 个 lane**。
4. **同一 lane 全局只有一个实例** —— 被 L 臂占用的 lane 不再放墙。

这套模型在结构上直接排除两种最丑的错：**相邻房间共面双墙（z-fighting）** 和 **漏墙**。
不需要靠「摆完再检查有没有重叠」这种事后手段。

> 塔楼既有约定是相邻房间之间留 5m 空隙（不共面），已在 `floor_98.json` 中确认；
> 本布局沿用同一坐标契约。

### 坐标契约

| 项 | 约定 |
| --- | --- |
| 轴 | Blender Z-up；(x, y) 对应 Godot (x, -z)，Blender **X=东、Y=北** |
| 位置 | `position_m` 直接取 Blender 世界坐标，运行时**无需换算** |
| 旋转 | `rotation_z_deg` 为 Blender 绕 Z 旋转，与 Godot `rotation.y` **同值** |
| 原点 | 墙 / 门墙 / 门扇：**底面中心**（落在墙结构中心平面上）；L 角件：**角点**（两臂沿 +X/+Y 各 5m） |

朝向表：`ROT_FACE_IN = {south:0, north:180, west:-90, east:90}`；
L 角件 `ROT_CORNER = {SW:0, SE:90, NE:180, NW:-90}`（与 `DungeonRoom3D.gd` 的 `ROT_CORNER` 同表）。

## 实例统计（v002）

| 角色 | 数量 | 说明 |
| --- | --- | --- |
| `corner_l` | 11 | L 角件：会议室 4 + 门厅 4 + 办公室 3 |
| `solid_wall` | 23 | 实心墙 |
| `door_wall` | 4 | 门墙（3 扇内部门 + 1 处东出口门洞） |
| `door_leaf_preview` | 3 | 门扇（**仅预览**，东出口不挂扇） |
| `floor_tile` | 49 | 地砖（r01_c01 25 + r01_c02 24，两种砖面交替） |
| **合计** | **90** | |

墙 lane 共 **27** 条（`x=常数` 平面 8 条、`y=常数` 平面 19 条）：`solid` 23 + `door` 3 + `exit` 1。
L 臂 lane 22 条（11 角件 × 2 臂）⇒ **22 + 27 = 49 条 lane，全关卡每条只出一个实例**。

> 角件去重：办公室的 NE 角与会议室的 NW 角是**同一个世界点** `(-25.0, 10.0)`，
> 按 `plane_priority` 判归会议室，办公室该角记入 `corners_dropped`（共 1 处去重）。
> 所以房间角位名义上是 4+4+4 = 12 个，实际只放 11 个角件。

世界包络：`lo = (-40.150, -10.150, 0.000)`、`hi = (35.150, 10.150, 11.900)`
（= 设计包围盒各向外扩 0.15m 墙结构半厚；高 11.900m 为可见墙高）。

## 引用的组件库与资产 ID

本布局**不拥有任何几何**（`room_owned_geometry = false`），全部由 6 个既有组件包实例拼成：

| 组件包（本地键） | AssetID | 库文件 |
| --- | --- | --- |
| `wall_standard_5m_通用包` | `ENV-BATTLE-COMMON-WALL-STANDARD-5M` | `common_components/v007` |
| `wall_door_5m_通用包` | `ENV-BATTLE-COMMON-WALL-DOOR-5M` | `common_components/v007` |
| `door_5m_通用包` | `ENV-BATTLE-COMMON-DOOR-5M` | `common_components/v007` |
| `floor_tile_r01_c01_通用包` | `ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01` | `common_components/v007` |
| `floor_tile_r01_c02_通用包` | `ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02` | `common_components/v007` |
| `runtime_v001`（L 角件） | `ENV-TOWER-CORNER-L-5M` | `tower_descent_3d/.../corner_l_5m/v001` |

> **AssetID 已存在 ⇒ 只升级既有行，不得新增**（否则 `duplicate_asset_id`）。
> 本布局**没有引入任何新 AssetID**，只是消费既有组件。

### v006 / v007 说明

本布局源链接 `common_components/v007`。v006 与 v007 的这 5 个组件包**几何逐值相同**
（网格数 / 面数 / 局部包络一致），差别仅在 **v007 把 `door_5m` 与 `wall_door_5m` 的库原点归零规范化**
（v006 分别为 `(2.6, -69.3444, 0)` 与 `(8.0, -58.3444, 0)`）。

账本该 5 行的「版本 / Blender 源文件」字段仍写 **v006**，属**版本字段滞后**；
塔楼 L 角件的派生清单已记录其源出 v007。**摆位代码逐包实测库原点，故两版均安全。**

## ⚠️ 库原点陷阱（改这一版必读）

Blender Collection Instance 的**实例世界变换 = empty.matrix_world @ 库对象.matrix_world**。

组件包在库里**并不位于世界原点**（是作者留下的历史摆放位）。因此：

1. 摆位必须**逐包补偿库原点**：`empty.location = target - Rz(rot) @ anchor`。
2. **`libraries.load()` 之后立刻读 `obj.matrix_world` 会拿到陈旧的单位矩阵** —— 必须通过
   `evaluated_depsgraph_get().object_instances` 读真实变换。这是本版踩过的坑：
   v001 的世界包络算成了 `(-98.494, -73.814) ~ (78.494, 68.494)`，就是库原点被重复叠加导致的。

## ⚠️ Blender 63 字节 ID 名限制

Blender 对象/集合 ID 名上限 **63 字节（UTF-8）**，中文 1 字 = 3 字节。超长名会被**静默截断**，
下游所有按名查找的代码随即失效。

本版踩过：「区块00-主人的办公室_中文资产管理」的完整路径名组合一度超限。现已把根集合名
定为 `区块00-主人的办公室_中文资产管理`（约 14 中文字 = 42 字节，安全），并在建集合处
**加了断言**：`if c.name != name: raise` —— 一旦超限立刻报错，不再静默。

## 命名契约

```text
根集合            区块00-主人的办公室_中文资产管理
├── 01_白盒布局_可编辑
└── 02_游戏输出_独立资产包_v002
```

实例前缀：`CORNER_`（L 角件）/ `WALL_`（实心墙）/ `DOORWALL_`（门墙）/
`DOORLEAF_`（门扇预览）/ `FLOOR_`（地砖）。

## 校验

构建脚本自带 5 项证据校验，全部 PASS 才算成功：

1. 实例 ID 无重复；
2. 无非单位缩放（`non_unit_scale_count = 0`）；
3. 无非法旋转（`illegal_rotation_count = 0`）；
4. **lane 守恒**：22 条 L 臂 lane + 27 条墙 lane = 49，且无重叠；
5. depsgraph 网格数 = 1322（期望值由组件几何推出，非硬编码）；世界包络与设计包围盒相符（±0.02）；
   装饰朝向（22 条 L 臂 + 27 面墙**全部朝房间内**，每条都做反向对照）。

重建命令（Blender 无头）：

```powershell
blender --background --python _scratch\build_block00_master_office.py
```

渲染验收图：

```powershell
blender --background --python _scratch\render_block00.py
blender --background --python _scratch\render_block00_plan.py
blender --background --python _scratch\render_block00_walls_only.py   # 纯墙俯视，验无共面双墙
```

## 下一轮（尚未开始）

1. 导出 GLB + 建 Godot PackedScene（按「有房间布局即重放」的路线接成可运行房间）。
2. 把区块00 接进运行时；届时一并定义 **99F↔98F 楼梯末端门「去掉」的运行时口径**。
3. 补 `master_office_layout/使用说明.md` 的运行时入口章节（等接线完成后再写，避免写空话）。

## 原则

- Blender 源是资产本体与版本来源；GLB / PackedScene 是派生物，不能反向定义源版本。
- **不新增 AssetID**：能复用既有组件就复用，两个内容 ID 指向同一稳定 PackedScene 也不复制文件。
- 摆位真源是 `.layout.json`；改布局改脚本、重跑、别手改 JSON。
- 历史版本只用于回滚追溯。
