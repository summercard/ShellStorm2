# master_office_layout · component packages

区块00-主人的办公室用到的组件包清单（6 份）。

本布局**不拥有几何**（`room_owned_geometry = false`），90 个实例全部是对既有组件包的引用。
这里的 `asset_manifest.json` 只是**用量与引用记录**，不是新的资产定义 ——
组件本体在各自的库文件里（见下），**AssetID 已存在，不得新增**。

| 目录 | AssetID | 库文件 | 用量 |
| --- | --- | --- | --- |
| `architecture/wall_standard_5m/` | `ENV-BATTLE-COMMON-WALL-STANDARD-5M` | `common_components/v007` | 23 |
| `architecture/wall_door_5m/` | `ENV-BATTLE-COMMON-WALL-DOOR-5M` | `common_components/v007` | 4 |
| `architecture/door_5m/` | `ENV-BATTLE-COMMON-DOOR-5M` | `common_components/v007` | 3 |
| `architecture/corner_l_5m/` | `ENV-TOWER-CORNER-L-5M` | `tower_descent_3d/.../corner_l_5m/v001` | 11 |
| `floor/floor_tile_r01_c01/` | `ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01` | `common_components/v007` | 25 |
| `floor/floor_tile_r01_c02/` | `ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02` | `common_components/v007` | 24 |

库路径：

```text
assets/art/environments/tower_zones/battle/source/common_components/v007/env_battle_common_components_source_v007.blend
assets/art/environments/tower_descent_3d/source/corner_l_5m/env_tower_corner_l_5m_source_v001.blend
```

> 账本（`assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx`）该 5 行的「版本 / Blender 源文件」
> 字段仍写 **v006**，属版本字段滞后；v006 与 v007 这 5 个组件包几何逐值相同，
> 差别仅在 v007 把 `door_5m` / `wall_door_5m` 的库原点归零规范化。摆位代码逐包实测库原点，两版均安全。
