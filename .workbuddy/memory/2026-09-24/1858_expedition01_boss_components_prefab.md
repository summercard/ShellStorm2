# 1858 远征01 Boss房通用组件：导出 GLB + 建自包含 PackedScene（Task #37 / #38）

## 业主口径（原话）
- 「boss房间带有资产的房间，需要先输出组建再拼装，没有的，通用墙体，墙门，门扇，L转角，地砖先用通用的，内部装饰组建先不摆设。」
- 「墙体，L拐角，地砖，门扇，门墙要做成通用组件，用于boss房互用。大屏幕独立，其它里头的组件，相似的也要做成通用然后互用，不要全量加进去。」
- 选定：**复用 5 类通用件 + 新增 6 件专属件**。

## 结论：6 件专属件 = 无法用壳体通用件表达的件
`ENV-EXPEDITION-BOSSROOM-*`：`BASE-FLOOR-BASE` / `MAIN-FAULT-SCREEN` / `HEAVY-CONDUITS` /
`NORTH-WALL-TYPOGRAPHY` / `SOUTH-FLOOR-MARKING` / `DEBRIS-00`。

壳体 5 类**复用不复制**（避免两份真源），运行时引用见 `DungeonRoom3D.gd`：
实墙 `battle/.../wall_standard_5m`、门墙 `battle/.../wall_door_5m`、地砖 `battle/.../floor_tile_5m`(c01/c02)、
门扇 `assets/art/props/dungeon_3d/prp_tower_door_leaf_5m.tscn`（塔楼 A 套）、
L 转角 `assets/art/props/dungeon_3d/prp_corner_l_5m.tscn`。
⇒ 远征不自建壳体组件库，跨区引用 battle 库是**有意**的。

## 产物（全部 CRLF，除 .import 为 LF）
- GLB ×6：`expedition/components/common_components/<slug>/<slug>_visual_top3d.glb`
- tscn ×6：`expedition/runtime/common_components/<slug>/<slug>_root_top3d.tscn`（范式 B，`load_steps=2`）
- 库 ID `ENV-EXPEDITION-L01-COMMON-COMPONENT-LIBRARY`；`library_root` = `.../tower_zones/expedition`
- QA 脚本（`source/common_components/v001/qa/`）：
  `export_boss_shell_components.py`、`bind_boss_component_palette_imports.py`、
  `build_boss_component_prefabs.py`、`probe_boss_component_prefabs.gd`
- `expedition/runtime/README.md` 记录目录契约与复现命令

## 碰撞：6 件**全部无内嵌阻挡**（按设计，非漏做）
沿用入口安全房 v007 判例（逐件理由写在 `metadata/collision_exclusion_reason`）：
- `base_floor_base` → `collision_owner=TowerFloorStage3D._build_support`、`policy=external_owner_no_shape_in_package`
- 其余 5 件 → `owner=none`、`policy=no_blocking_by_design`
  （主屏底面 3.805m / 墙面标识 7.446m 够不着；入口标识 12mm、碎屑 220mm 属地面装饰）
- ⚠ `heavy_conduits` 是唯一「底部落在走行面附近」的实体：轴向包络 47.31×32.30m，
  内嵌盒会**封死房间**故不持有阻挡。若美术确认它占玩家通路，须**由房间层下发分段盒**，
  不能改回包络盒。

## 验收
`probe_boss_component_prefabs.gd`：**pass=96 fail=0 PROBE_OK**，无 SCRIPT ERROR。
断言项：可加载 / 根节点名 / asset_id / version / library_id / origin_contract=bottom_center /
forward_axis / collision_owner / collision_policy / collision_shape_count=0 / MeshInstance 数 /
尺寸逐轴（容差 2mm）/ 底面 Y=0 / XZ 居中 / 包内无 StaticBody3D、CollisionShape3D / 色盘全绑。

## 坑（新发现，跨项目可用）
- **`Path.write_text` 在 Windows 会把 `\n` 翻成 `\r\n`** ⇒ 想让 Godot 生成的 `.import` 保 LF，
  必须**字节级读写**（`read_bytes`/`write_bytes`）。战局先例脚本
  `battle/source/common_components/v004/qa/bind_v004_palette_imports.py`（及 v003 同款）
  用了 `write_text` ⇒ 打完契约后工作区变 CRLF。因 `.gitattributes` 有 `*.import text eol=lf`，
  git 侧不显脏、检出即 LF，属**潜伏缺陷**（未改，待主人裁决）。
- **GLB 想让材质绑上共享色盘，必须在 `.glb.import` 里设两处**：
  `import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"`
  ＋ `gltf/embedded_image_handling=0`。否则 albedo_texture 为空，模型无色。
  设完必须**再跑一次 `--import`** 才会重生成 `.scn`。
- GDScript 里 `String(int)` 非法（Godot 4），metadata 取整数要 `str(...)`。
  战局地板组件探针能过是因为它断言的 metadata 全是字符串。

## 未完（Task #39~#43）
#39 catalog 驱动替换 `DungeonRoom3D._authored_component_prefab()` 硬编码表；
#40 Boss 房静态布局清单（schema `shellstorm2.battle.room_instance_layout`，
范本 `source/art/blender/master_office_layout/source/block_00_master_office_layout_v002.layout.json`）；
#41 通用壳体组合器（其余 12 房）；#42 设计源房型模板约束 + 补 `LevelPlanLoader.normalize_floor`
与 `FloorPlanGenerator.room_from_source` 两道 `authored_layout_*` 透传；#43 账本/设计页同步 + 全门禁。

⚠ `HeavyConduits` 的 `metadata/forward_axis="+Y"`（地板底盘）与 `eol` 检查等
已在本轮定稿，后续改动不要回退。
