# 战局区块最小通用组件库 v003

入口：[战局区块_通用组件库_v003.blend](战局区块_通用组件库_v003.blend)。按用户逐组选择从v002的77包收口到23包，v001/v002继续保留回滚。

- 01：仅保留第1个正常机柜与第4个破损机柜。
- 02：删除原第2个，保留工作台、控制终端和独立椅子。
- 03：删除原第3个，保留前两个设备岛。
- 04：第1个维修托盘已对齐组件轴；删除原第2、第3、第8至第10，保留5件。
- 06：仅保留第1个绿植。
- 08：仅保留新建5×0.3×11.9m标准墙，不保留房间横向拉长墙。
- 09：仅保留原前两块5m地砖。

其余05、07沿用v002代表件。所有组件正面为本地+Y、XY居中、底面Z=0，通过Append单个“通用包”集合使用。

## 导出状态（2026-09-16 更新）

08_墙壁组件的两件与 10_门组件的一件、以及 09_地板组件的两块 5m 地砖，均已落成**自包含可替换组件**：
稳定原点 + metadata 契约 + `ImportedModel` 实例（沿用 L 型转角包装的结构），并内嵌盒碰撞，
属逐实例化范式（范式 B）。

| slug | 视觉 GLB | 运行 PackedScene | 尺码(Blender XYZ, m) |
| --- | --- | --- | --- |
| wall_standard_5m | `battle/components/common_components/wall_standard_5m/wall_standard_5m_visual_top3d_v003.glb` | `battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d_v003.tscn` | 5.0 × 0.3 × 11.9 |
| wall_door_5m | `battle/components/common_components/wall_door_5m/wall_door_5m_visual_top3d_v003.glb` | `battle/runtime/common_components/wall_door_5m/wall_door_5m_root_top3d_v003.tscn` | 5.0 × 0.3 × 11.9（门洞 2.2 × 2.5） |
| door_5m | `battle/components/common_components/door_5m/door_5m_visual_top3d_v003.glb` | `battle/runtime/common_components/door_5m/door_5m_root_top3d_v003.tscn` | 2.2 × 0.18 × 2.5 |
| floor_tile_r01_c01 | `battle/components/common_components/floor_tile_5m/floor_tile_r01_c01_visual_top3d_v003.glb` | `battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d_v003.tscn` | 4.94 × 4.94 × 0.056 |
| floor_tile_r01_c02 | `battle/components/common_components/floor_tile_5m/floor_tile_r01_c02_visual_top3d_v003.glb` | `battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c02_root_top3d_v003.tscn` | 4.94 × 4.94 × 0.081 |

- 原点契约：底面中心（Blender 底面 Z=0 → Godot 底面 Y=0、XZ 居中），与全库一致。
- 尺寸来源全部是项目权威常量，脚本内不写美术估值：
  `TowerGeometry3D.GRID_UNIT_M=5.0` / `WALL_VISUAL_HEIGHT_M=11.9` / `WALL_LOGICAL_HEIGHT_M=12.0` /
  `DOOR_CLEAR_WIDTH_M=2.2` / `DOOR_CLEAR_HEIGHT_M=2.5`、`FloorPlanGenerator.WALL_THICKNESS_M=0.30`、
  `RoomDoor3D.PANEL_THICKNESS_M=0.18`。由此推出墙顶 0.10m 净空、门垛宽 1.4、门楣高 9.4。
- 门墙与门扇严格配对：门楣底 = 门扇顶 = 2.5m；门扇口径与 `RoomDoor3D` 一致（底边中心原点、开门垂直升起）。
- 色盘：五件的 `.glb.import` 均绑定 `tools/asset_pipeline/scene_facility_shared_palette_post_import.gd`；
  `.glb.import` 已通过 `.gitignore` 白名单进版本控制。
- 色盘导入契约断言：`tests/verification/verify_scene_facility_shared_palette.tscn` 现在会逐个校验
  `PALETTE_CONTRACT_ROOTS` 下每个 GLB 的 `.import`（后处理脚本路径 + `gltf/embedded_image_handling=0`），
  并校验公共色盘自身的 `.png.import` 必须 `compress/mode=0` + `mipmaps/generate=false`。
  2026-09-16 运行结果 `glbs=184 materials=1240 legacy_exempt=2`、退出码 0。
  两件 v003 之前的老资产因未绑色盘被登记为**精确路径欠账**（`LEGACY_PALETTE_EXEMPT_GLBS`），
  欠账表是双向断言：资产合规了或路径消失了都会报错，新违规不会被吞。
- 契约断言：`qa/probe_floor_tile_components.gd`（地砖，29 项），
  以及 `tests/verification/verify_common_wall_door_components.tscn`（墙/门，无头运行退出码 0）。
- 正式验证场景：地砖 `verify_common_floor_tile_components.tscn`、墙/门 `verify_common_wall_door_components.tscn`
  （均已加入 `scripts/run_verification_suite.sh` 的 `core` 套件）。
- 验收图：
  - 地砖 `outputs/verification/common_floor_tile_components.png` 与 `..._edge.png`；
  - 墙/门 `outputs/verification/common_wall_door_components.png`（标准墙 / 门墙+门扇 / 独立门扇总览）与
    `common_wall_door_components_door.png`（门洞 2.2×2.5 净空近景）。
- 台账：已登记到 `assets/registry/ShellStorm2_美术资产台账_v001.xlsx` 的「3D-场景通用」表
  r92/r93（地砖）与 r94/r95/r96（本三件）；
  补登脚本 `qa/register_floor_tile_ledger_rows.py` / `qa/register_wall_door_ledger_rows.py`，
  保真校验 `qa/verify_floor_tile_ledger_patch.py` / `qa/verify_wall_door_ledger_patch.py`。
- 导出脚本：`qa/export_floor_tile_5m.py`、`qa/export_wall_door_5m.py`；
  建模脚本 `qa/add_wall_door_components.py`；prefab 生成 `qa/build_wall_door_prefabs.py`；
  色盘导入绑定 `qa/bind_wall_door_palette_imports.py`；
  manifest/catalog 落成 `qa/finalize_wall_door_packages.py`；catalog 回写 `qa/sync_catalog_export_status.py`。

08_标准墙的 GLB 已在 2026-09-16 从本库源 blend 重新导出并完成 Godot 导入（此前工作区缺该导出件，
只剩 `.godot/imported` 缓存与 `export/wall_standard_5m_runtime_v003.blend.import` 残渣）。

其余 01–07 组件仍未生成 GLB、碰撞或 Godot 场景。

