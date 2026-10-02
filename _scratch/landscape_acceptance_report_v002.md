# Cross Tower 路线景观补全独立验收报告 v002

日期：2026-10-03
资产：`ENV-OPENWORLD-LANDSCAPE-FOUNDATION`
正式路线：`assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn`

## 1. 结论

**结果：部分通过，整体阻塞，不得标记为全局通过。**

已通过的范围：

- 正式路线保持 Tower2、Tower3、Skyline08 根节点位置；Skyline08 完整 `Transform3D` 未改。
- 景观根场景已拆成 9 个可独立编辑 PackedScene。
- Godot 4.6.3 导入退出码 0。
- 正式探针退出码 0，输出 `LANDSCAPE_RUNTIME_DUMP_OK city=96 foundation=9`。
- 根场景及9个独立组件均 `loaded=true`。
- 主塔基础运行时最低视觉包络为 `Y=-24.30`，已计入 98F stage 位移、生产视觉偏移和地砖局部最低点。
- 地表顶面 `Y=-80.0`，厚度 `0.2m`；含基础和远景后边界为：
  - X `[-141.749374,149.250000]`
  - Z `[-218.096664,136.555222]`
  - 使用 `20.25m` 余量，满足至少 `20m`。
- `Tower2RemoteSilhouette_A` 的旧 `City[r2:i11]` 保守重叠已消除。

未通过/阻塞的范围：

- Tower2 源楼身底部 `Y=-100.5` 仍低于地表 `Y=-80`；本次未移动建筑，组件 metadata 明确记录该冲突，未假定用户批准。
- 完整保守运行时 AABB/XZ 检查仍有 53 对非目标-基础关系重叠，主要是既有 Tower2/桥/城市连接关系、基础与既有路线/城市包络关系；不能写成“全局无重叠”。
- 未执行三角级 mesh intersection。
- 未执行带窗口真实渲染截图；`tests/verification` 中没有现成的跨塔景观窗口渲染探针，本次未把 headless dump 冒充截图证据。
- 场景 XLSX 分账本未直接修改，尚未完成真实账本行登记。

## 2. 证据

| 项目 | 证据 | 结果 |
|---|---|---|
| 导入 | `_scratch/landscape_import_final.log` | `import_exit=0` |
| 运行时结构 | `_scratch/landscape_runtime_geometry_final2.log` | `probe_exit=0` |
| 运行时 dump | `_scratch/landscape_runtime_geometry_final2.json` | city=96、foundation=9 |
| 几何复算 | `scripts/verify_landscape_foundation_geometry.py` | objects=113、blocking=53、intentional=4 |
| 结果清单 | `assets/art/environments/open_world/runtime/open_world_landscape_foundation/footprint_check.json` | schema v003、明确记录阻塞 |
| 导入缓存 | `_scratch/landscape_appdata_final` | 独立 APPDATA |

Godot 日志中的 palette invalid UID 回退文本路径是既有工程警告；本次景观代理没有新增材质资源，且所有目标 PackedScene 均独立加载成功。

## 3. 运行时几何重点

- `Tower1FoundationBox`：size `(104,55.7,84)`，AABB Y `[-80,-24.30]`。
- `Tower2FoundationBox`：size `(74.13,20.5,54.112583)`，AABB Y `[-100.5,-80]`；不包含塔吊。
- `Tower3FoundationBox`：size `(73.917942,39.849998,49.621033)`，AABB XZ `[-48.973587,24.944349] × [-197.846664,-148.225632]`。
- `Skyline08FoundationBox`：保留完整路线矩阵，AABB XZ `[-30.815016,-2.880365] × [-138.698334,-103.678340]`。
- `OpenWorldGroundPlane`：运行时 AABB 与 metadata 读回一致到浮点误差范围内。

## 4. 检查边界

AABB/XZ 检查是保守包络筛查，不是三角级相交检测。目标与自身基础的4对交叠被单独记录为 `intentional_target_foundation_overlaps`；其他53对保留在 `pairwise_aabb_xz_overlap`，包括既有桥/塔/城市关系，不能把它们全部归咎于本次新增远景，也不能因此宣称新增远景三角相交。

## 5. 文件与保护范围

本次涉及：

- 正式景观根场景及9个组件场景。
- `footprint_check.json`、`asset_manifest.json`。
- `tests/verification/probe_open_world_landscape_foundation.gd`。
- `scripts/verify_landscape_foundation_geometry.py`。
- 工作报告、`MODULE_INDEX.md`、`CHANGELOG.md`。

未修改：

- 原始 Blender 源。
- `TowerAtmosphere3D.gd` 城市生成算法。
- 玩法、碰撞规则和建筑目标根节点。
- XLSX 场景分账本。

本轮快照：`I:/工作项目/shellstrom2/_scratch/landscape_pre_geometry_fix/baseline.json`。该快照只覆盖本轮修改前三个目标文件，不代表任务起始全工程备份。
