# Expedition runtime

`远征关卡01` 目前**不产出整区 PackedScene**：房间壳体由
`src/world3d/DungeonRoom3D.gd` 的 `_build_authored_layout_shell()` 按摆位清单逐实例装配。
`远征关卡01` 是稳定编号；将来若要新增整区运行资产，沿用 `zone_expedition_vNNN.tscn`
这类稳定文件名，不把可变设定名写进路径。

## `common_components/` —— 远征自有通用组件库 v001

库 ID `ENV-EXPEDITION-L01-COMMON-COMPONENT-LIBRARY`，库根
`res://assets/art/environments/tower_zones/expedition`。
本轮 6 件，均为 **Boss 房专属**、无法用壳体通用件表达的件。范式 B（自包含可替换组件）：
视觉 GLB ＋ 稳定根 ＋ 契约写在 `metadata/`。

| slug | AssetID | Godot 包围盒 (x,y,z) m | 碰撞归属 |
| --- | --- | --- | --- |
| `base_floor_base` | `ENV-EXPEDITION-BOSSROOM-BASE-FLOOR-BASE` | 50 × 0.26 × 40 | 无 —— 承重归 `TowerFloorStage3D._build_support()` |
| `main_fault_screen` | `ENV-EXPEDITION-BOSSROOM-MAIN-FAULT-SCREEN` | 21.52 × 7.09 × 1.575 | 无 —— 底面离走行面 3.805 m，够不着 |
| `heavy_conduits` | `ENV-EXPEDITION-BOSSROOM-HEAVY-CONDUITS` | 47.31 × 3.672 × 32.304 | 无 —— 轴向包络盒会封死房间，不按包络持有 |
| `north_wall_typography` | `ENV-EXPEDITION-BOSSROOM-NORTH-WALL-TYPOGRAPHY` | 35.90 × 2.32 × 0.042 | 无 —— 底面离走行面 7.446 m，够不着 |
| `south_floor_marking` | `ENV-EXPEDITION-BOSSROOM-SOUTH-FLOOR-MARKING` | 3.697 × 0.012 × 2.727 | 无 —— 12 mm 地面贴花 |
| `debris_00` | `ENV-EXPEDITION-BOSSROOM-DEBRIS-00` | 2.425 × 0.22 × 1.988 | 无 —— 220 mm 地面固定碎屑 |

「无碰撞」是**按设计**，不是漏做；逐件理由写在 `metadata/collision_exclusion_reason`。
判定沿用入口安全房 v007 已确立的同类件判例（`entry_safe_room/floor_base` 归
`TowerFloorStage3D`；`north_nexus_sign` / `overhead_services` / `debris_papers` 一律
`no_blocking_by_design`）。

⚠ `heavy_conduits` 是 6 件里唯一「底部落在走行面附近」的实体。它按轴向包络盒
（47.31 × 32.30）给内嵌盒会把整个房间封死，故不持有阻挡；若后续美术确认它确实占据
玩家通路，须**由房间层另行下发分段碰撞盒**，不能改回包络盒。

## 壳体 5 类：复用，不在本目录复制

房间壳体的墙 / 门墙 / 门扇 / 地砖 / L 转角**复用既有组件**，本目录不另建副本，
避免同一件资产出现两份真源。**ID → PackedScene 的对齐表不在代码里**，统一由
跨区注册表解析：

`assets/art/environments/tower_zones/shared/runtime/shell_component_catalog.json`
（schema `shellstorm2.runtime_shell_component_catalog.v001`）

| 类 | 注册表 `component_id` | 运行时 prefab |
| --- | --- | --- |
| 实墙 5 m | `ENV-SHARED-GENERIC-WALL-STANDARD-5M` | `battle/runtime/common_components/wall_standard_5m` |
| 门墙 5 m | `ENV-SHARED-GENERIC-WALL-DOOR-5M` | `battle/runtime/common_components/wall_door_5m` |
| 门扇 5 m | `ENV-SHARED-GENERIC-DOOR-5M` | `assets/art/props/dungeon_3d/prp_tower_door_leaf_5m.tscn`（塔楼 A 套） |
| 地砖 5 m | `ENV-SHARED-GENERIC-FLOOR-TILE-R01-C01` / `-C02` | `battle/runtime/common_components/floor_tile_5m` |
| L 转角 5 m | `ENV-SHARED-GENERIC-CORNER-L-5M` | `assets/art/props/dungeon_3d/prp_corner_l_5m.tscn` |

每件登记 `aliases`（具体批次号，如 `ENV-BATTLE-COMMON-*` / `ENV-TOWER-CORNER-L-5M`）——
摆位源两侧任写其一都命中同一 prefab。L 转角角色实际由
`DungeonRoom3D._spawn_room_corner()` 装配（`FACILITY` 房取 base99 角件），注册表只为
「ID 可解析 + 台账可追溯」兜底。

解析链（`DungeonRoom3D._authored_component_prefab()`）四条口径：
注册表缺失 / 空 / schema 不符 → 报错 + 空表；条目缺 `prefab_path` 或 ID 重复登记 →
报错 + 跳过该条；未登记 ID → 返回 `null`，**绝不回退成别的组件**；登记了路径但文件不在
或加载不出 → 报错 + 返回 `null`。

## 复现与验收

```text
# 1) 导出 6 件 GLB（Blender 4.5，无头）
"D:\Program Files\Blender Foundation\Blender 4.5\blender.exe" \
    --background --factory-startup --python \
    source/common_components/v001/qa/export_boss_shell_components.py

# 2) Godot 首次导入，生成 .glb.import
Godot_v4.6.3-stable_win64_console.exe --headless --path <项目根> --import

# 3) 给 .import 打公共色盘契约（字节级保 LF；幂等）
python source/common_components/v001/qa/bind_boss_component_palette_imports.py

# 4) 生成 6 件 PackedScene 到本目录（范式 B，CRLF）
python source/common_components/v001/qa/build_boss_component_prefabs.py

# 5) 契约探针（96 项断言：可加载 / 元数据 / 尺寸 / 原点 / 无阻挡 / 色盘）
Godot_v4.6.3-stable_win64_console.exe --headless --path <项目根> --script \
    res://assets/art/environments/tower_zones/expedition/source/common_components/v001/qa/probe_boss_component_prefabs.gd
```

`.import` 必须保持 LF（`.gitattributes` 已声明 `*.import text eol=lf`），且
`import_script/path` 指向 `tools/asset_pipeline/scene_facility_shared_palette_post_import.gd`；
本目录下 6 个 Run 时 `tscn` 保持 CRLF。
