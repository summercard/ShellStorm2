# 局内关卡01 · 入口安全房 15×15m 正式美术 v007

入口：[Blender 美术源](env_battle_l01_safe_entry_layout_source_v007.blend)。资产身份 `ENV-BATTLE-L01-SAFE-ENTRY`，属 `battle`，设计范围见 [DESIGN_SCOPE 摘要](#范围与契约)。

v007 是 v006 的**收尾版本**。v006 已经把墙与地砖**模块**交给通用组件，但仍自持 7 个方位化装饰包（4 面墙装甲、地砖压条、南/东门禁）；v007 把这批装饰也并进 `common_components/v004`，房间侧只剩槽位引用。

## 范围与契约

- 房间为 **15×15m** 内净空，墙中线 ±7.35m，墙内脸 7.2m / 外脸 7.5m，墙厚 0.30m。
- 视觉墙高 **11.9m**（逻辑层高 12.0m，顶部 0.10m 留给上层楼板）；可行走面 z=**0.30**，结构板顶 z=**0.26**。
- 运行时布局（权威）：北 3 实墙；南 实墙+门+实墙；东 实墙+门+实墙；西 3 实墙。两门洞切向中心均为 0，净宽 **2.2m**、净高 **2.5m**。
- 网格 5.0m；地砖模块 4.94m 见方 + 0.06m 勾缝。

来源：运行时探针实测（`_probe_safe_room_door.txt`），非从旧模型或效果图反推。

## 使用与归类

- `01_制作组件` 保留可编辑源，默认隐藏；资产包输出默认显示。
- **17 个独立资产包**（[目录树](component_packages_v007/tree.txt) / [总清单](component_packages_v007/catalog.json)）：14 设施 + 3 支持件（含承重底板）。主体与 UI 自发光分离。
- 视图层：`01_完整结构_交付` 保留完整 11.9m 墙体；`02_剖切展示_隐藏近侧墙` 供展示，未删除墙体。
- 材质遵循四共享角色，唯一色盘外链 `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`；不要单独搬走 Blend，否则相对贴图路径失效。

## 范式 B · 可替换组件契约

**墙体、地面与门不再是房间资产，连它们的装饰也不是。** 房间只保留槽位（placement）与引用，几何**与装饰**都由 `common_components/v004` 提供：

| 用途 | 通用组件 | 数量 | 组件自带装饰 |
|---|---|---|---|
| 实墙 | `wall_standard_5m`（5.0×0.3×11.9） | 10 | 4 件槽位装甲单元 |
| 带门洞墙 | `wall_door_5m`（2 门垛 + 1 门楣） | 2 | 11 件装甲门禁（含门楣护板、LED、状态灯、禁行屏） |
| 门扇 | `door_5m`（2.2×0.18×2.5） | 2 | — |
| 地砖 | `floor_tile_r01_c01` / `r01_c02` | 5 / 4 | 25 / 22 件砖面美术（4 压边 + 2 蓝拼缝 + 磨损） |

共 **23 个槽位、311 个槽位对象**（结构 36 + 装饰 275）。构建时已**显式移除**房间自有的 15 个墙/地模块（`WALL_*` 6 + `FLOOR_TILE_*` 9）、16 个旧包，以及 7 个已被 v004 吸收的装饰包（249 件）；`qa/task_validation.json` 的 `removed_wall_floor_modules` / `removed_room_owned_packages` / `removed_wall_floor_decoration` 记录清单。

**关键性质：一个单元服务所有槽位与所有朝向。** 同一组件的每个槽位，其装饰在**槽位自身局部帧**里逐值相同（`qa/component_slot_uniformity.json`）；北/南/东的装甲单元、南/东的门禁在组件局部帧完全一致。因此**不需要按方位区分资产**。

例外：**承重底板**（对象 `FLOOR_BASE`，15×15×0.26）由房间自持，归 `floor_base` 包。理由：通用库没有底板；参考房间 `main_room_02/v003` 同样保留 `floor/floor_base` 包。它的顶面正是 5m 地砖 60mm 勾缝下露出的面。

碰撞归属：所有槽位声明 `collision_owner = godot_0p30m_structural_proxy`、`room_owned_geometry = false`、`export_policy = reuse_common_component_visual_only`；碰撞、门状态机、导航全部仍归引擎，GLB 只负责视觉。

## 预览与验收

[参考全景](renders/01_参考全景.png) · [完整结构顶视](renders/02_完整结构顶视.png) · [北墙柜组与核心近景](renders/03_北墙柜组与核心近景.png) · [西北办公室近景](renders/04_西北办公室近景.png) · [东侧维修间与机械臂近景](renders/05_东侧维修间与机械臂近景.png) · [验收报告](QA_REPORT.md)

蓝灰板材、服务器列、中央终端岛、破损核心、顶部管线灯带与黄色机械臂已落到模型中。为遵守白盒，保留 11.9m 墙高、5m 网格与两个门洞位置；细节密度与破损造型为项目色盘化表现，非像素级复刻。

**本交付为 Blender 美术源 + 房间包 GLB/PackedScene。** 通用组件库 v004 的墙/地/门四件已另行导出并绑色盘（见 `battle/components/common_components/`）；房间自身的 17 个设施/支持包已导出 GLB 与运行时 PackedScene。

**运行时接线已完成（2026-09-17）**：入口安全房 v007 已在 `DungeonRoom3D._build_safe_room_shell()` 接入——按本层实际门向把整房旋转，墙/地/门走通用组件 v004 的 `runtime/common_components/*_root_top3d_v004.tscn`，17 个房间包按各自 `metadata/room_placement_position` 摆位。运行时探针 `tests/verification/probe_safe_room_v007_integration` 通过（`SAFE_ROOM_V007_INTEGRATION_OK`）。游戏内灯光验收与性能验收未做。台账 `assets/registry/ShellStorm2_美术资产台账_v001.xlsx` 的 `ENV-BATTLE-L01-SAFE-ENTRY` / `ENV-BATTLE-L01-SAFE-EXIT` 已由 v003 白模升为 v007 正式美术已接入。
