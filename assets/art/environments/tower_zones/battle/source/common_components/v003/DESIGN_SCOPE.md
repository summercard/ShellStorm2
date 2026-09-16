# 战局区块通用组件库 v003

依用户逐组选择收口为最小组装库。01保留第1与第4，02删除第2，03删除第3，04摆正第1并删除第2、第3、第8至第10，06仅留第1。05与07维持v002代表件。

墙体不沿用房间横向拉长墙，重建唯一5×0.3×11.9m视觉标准墙；逻辑阻挡仍按12m契约留给后续引擎包装。地板仅保留v002前两块5m地砖作为组装变体。v001/v002和来源房间均不覆盖。

## 09 地板组件的落地口径

两块地砖（`floor_tile_r01_c01` / `floor_tile_r01_c02`）已导出为可替换组件，需注意与**运行时塔楼地板**的三处口径差，
接入运行时前必须显式处理，否则会穿模或双重碰撞：

| 项 | 本组件（v003 通用地砖） | 运行时（`TowerFloorStage3D`） |
| --- | --- | --- |
| 平面尺寸 | 4.94 × 4.94 m | `GRID_UNIT` = 5.00 × 5.00 m |
| 厚度 | 0.056 / 0.081 m（薄壳） | `FLOOR_THICKNESS` = 0.30 m（承重板） |
| 原点 | 底面中心（底面 Y=0） | 几何中心，顶面 Y=0（transform.y = −0.15） |
| 实例化 | 逐实例 prefab（范式 B） | MultiMesh A/B 棋盘（范式 A） |
| 碰撞 | 内嵌逐砖 Box | 整层矩形 Box（`_build_support()`） |

- 平面缝隙 = 5.00 − 4.94 = **0.06 m**（每块四边各留 0.03），是刻意的分格留缝，不是误差。
- 若要求地砖顶面与行走面 Y=0 齐平，实例需另加 `y = −厚度`（c01 −0.056 / c02 −0.081）；
  该偏移已写进 PackedScene 的 `snap_to_walk_plane_offset_m`，并由
  `tests/verification/verify_common_floor_tile_components.tscn` 断言。
- 运行时的地砖是 MultiMesh，无法直接实例化 PackedScene；接入需改 `_build_floor()` 的实例化策略，
  并同时与 `_build_support()` 的整层碰撞去重。

### 这条「缝」与「厚度」目前是硬编码在断言里的

上表的差值是跨文件契约：改 `GRID_UNIT`、改 `FLOOR_THICKNESS`、或重导地砖改了 footprint/厚度，
都会让地砖与步行面不再齐平。为了让漂移当场暴露而不是靠回忆，以下位置各有一条断言：

| 断言 | 覆盖 |
| --- | --- |
| `qa/probe_floor_tile_components.gd` | 原点=底面中心、footprint 4.94、厚度=manifest 值、内嵌碰撞齐平、色盘 3/3 绑定 |
| `tests/verification/verify_common_floor_tile_components.tscn` | 上表全部口径 + `snap_to_walk_plane_offset_m` = −厚度 + 留缝 = 0.06 |
| `tests/verification/verify_scene_facility_shared_palette.tscn` | 公共色盘 `compress/mode=0` 与 `mipmaps/generate=false`，以及组件 GLB 必须外链色盘、不内嵌图片 |

## 08 墙壁组件与 10 门组件的落地口径

三件新组件（`wall_standard_5m` / `wall_door_5m` / `door_5m`）与地砖同属范式 B。
它们的尺寸全部由项目权威常量求出，**不要在关卡里另外写死一套**：

| 量 | 取值 | 权威来源 |
| --- | --- | --- |
| 墙格宽 | 5.0 m | `TowerGeometry3D.GRID_UNIT_M` |
| 墙/门墙厚度 | 0.30 m | `FloorPlanGenerator.WALL_THICKNESS_M` |
| 视觉墙高 | 11.9 m | `TowerGeometry3D.WALL_VISUAL_HEIGHT_M` |
| 逻辑层高 | 12.0 m（墙顶留 0.10 m 净空） | `TowerGeometry3D.WALL_LOGICAL_HEIGHT_M` |
| 门洞净宽/净高 | 2.2 × 2.5 m | `TowerGeometry3D.DOOR_CLEAR_WIDTH_M` / `DOOR_CLEAR_HEIGHT_M` |
| 门扇厚 | 0.18 m | `RoomDoor3D.PANEL_THICKNESS_M` |

- 由以上推出：门垛宽 = (5.0 − 2.2) / 2 = **1.4 m**，门楣高 = 11.9 − 2.5 = **9.4 m**。
  门墙的碰撞由左门垛、右门垛、门楣三个 Box 组成，**门洞处不产生碰撞**，
  通行由门扇自身或宿主门逻辑负责。
- 门墙与门扇严格配对：门楣底 = 门扇顶 = 2.5 m，门扇宽 = 门洞宽 = 2.2 m，由验证场景断言。
- 门扇口径与 `RoomDoor3D` 一致：**底边中心为原点**，开门是**垂直升起**（改 `panel.position.y`）而非旋转，
  故原点无需落在铰链轴上。接入 `RoomDoor3D` 时只取其 `ImportedModel` 子树（或直接把 GLB PackedScene
  传作 panel visual），否则本组件内嵌碰撞会与 `RoomDoor3D` 自建的 `DoorCollision` 重复。

### 这三件的「尺寸」也硬编码在断言里

与地砖同理，改常量或重导资产都会让墙与门洞不再对齐，以下位置各有断言当场暴露漂移：

| 断言 | 覆盖 |
| --- | --- |
| `tests/verification/verify_common_wall_door_components.tscn` | 七条权威常量仍在预期值 + 三件的原点/包围盒/碰撞 shape 数与位置 + 门洞 2.2×2.5 无碰撞 + 门墙/门扇配对 |
| `tests/verification/verify_scene_facility_shared_palette.tscn` | 三件 GLB 的 `.import` 必须绑公共色盘后处理且不内嵌图片 |

