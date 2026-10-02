# Cross Tower 路线景观补全交付记录

- 功能/资产：`ENV-OPENWORLD-LANDSCAPE-FOUNDATION`
- 正式路线：`assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn`
- 日期：2026-10-03
- 范围：只做 Godot 正式路线的场景装配代理；不改玩法规则、不改原始塔楼/skyline Blender、不改 `TowerAtmosphere3D.gd`、不新建材质资源。
- 02b 边界：本次是 `BoxMesh` 视觉代理和正式 PackedScene 装配，不宣称 Blender 源资产导入优化验收；后续替换为美术模块必须另走独立优化文件、GLB、重导入和保真门禁。

## 实施结果

1. 正式路线保留 `LandscapeFoundation` 引用；Tower2、Tower3、Skyline08 和 Skyline08 完整 `Transform3D` 未改。
2. 景观根场景拆为 9 个可独立编辑 PackedScene：4 个基础、1 个地表、4 个远景代理；根场景只保存实例位置和正式引用。
3. 全部视觉代理根 `scale` 为 1、无碰撞；材质统一复用 `res://assets/art/environments/tower_descent_3d/components/mat_tower_wall_solid_a_v001.tres`。
4. 每个补全对象保留 `target/top_y/ground_y/footprint_source/material_source/future_optimization_space` 六项 metadata。
5. 主塔基础按生产链修正为 98F stage `y=-24.0` + polished tile visual offset `-0.15` + 局部资产最低点 `-0.15`，最低视觉包络 `Y=-24.30`。
6. 地表厚度 `0.2m`、顶面 `Y=-80.0`；范围纳入目标、桥、城市、基础和远景，使用 `20.25m`（满足至少20m并保留浮点余量）。
7. `Tower2RemoteSilhouette_A` 移到确定性生产布局筛出的空槽中心 `(120,-140)`；不修改城市生成算法。

## 精确模块

| 节点 | 中心坐标 | 尺寸 | 顶面/底面 | 备注 |
|---|---:|---:|---:|---|
| Tower1FoundationBox | (0, -52.15, 5) | (104, 55.7, 84) | -24.3 / -80 | 主塔壳体 `[-50,50]×[-35,45]` 外扩2m；按98F生产地砖链核算 |
| Tower2FoundationBox | (40, -90.25, -90) | (74.13, 20.5, 54.112583) | -80 / -100.5 | 按楼身 floor_00 包络+2m；不包塔吊；源楼身底部仍低于地表 |
| Tower3FoundationBox | (-12.01462, -60.075001, -173.036148) | (73.917942, 39.849998, 49.621033) | -40.15 / -80 | 按运行时完整网格XZ包络+1m，保留非对称源bbox中心 |
| Skyline08FoundationBox | (-16.847691, -69.827294, -121.18834) | (27.93465, 20.345413, 35.02) | -59.654587 / -80 | 完整运行时bbox+1m；目标路线矩阵不变 |
| OpenWorldGroundPlane | (3.750313, -80.1, -40.770721) | (290.999374, 0.2, 354.651886) | -80 / -80.2 | X[-141.749374,149.25]，Z[-218.096664,136.555222]；含基础及20.25m余量 |
| Tower2RemoteSilhouette_A | (120, -49, -140) | (18,62,18) | -18 / -80 | 生产算法空槽；已消除与 `City[r2:i11]` 的重叠 |
| Tower2RemoteSilhouette_B | (80, -56, -130) | (18,48,16) | -32 / -80 | 生产算法筛查的远景槽 |
| Tower3RemoteSilhouette_A | (-70,-52,-173) | (16,56,18) | -24 / -80 | 生产算法筛查的远景槽 |
| Skyline08RemoteSilhouette_A | (-60,-59,-125) | (16,42,16) | -38 / -80 | 生产算法筛查的远景槽 |

## 垂向契约

Tower2 导出楼身的运行时底部是 `Y=-100.5`，低于请求地表 `Y=-80`。本次不移动 Tower2 根节点、不改变上部建筑，因此基础盒真实跨越 `[-100.5,-80]`；组件 metadata 同时记录 `top_y=-80.0`、`ground_y=-80.0` 和 `source_building_bottom_y=-100.5`。这仍是待美术确认的设计冲突，不宣称已统一为同一地表标高。

## AABB/XZ 检查边界

- 检查脚本：`scripts/verify_landscape_foundation_geometry.py`。
- 输入：Godot 运行时 dump `I:/工作项目/shellstrom2/_scratch/landscape_runtime_geometry_final2.json`、正式目标/桥包络、96栋生产城市布局和9个景观实例。
- 检查对象：113；城市布局：96；基础与远景均纳入。
- 预期目标-基础包络交叠：4对，单列为 `intentional_target_foundation_overlaps`。
- 其他保守 AABB/XZ 重叠：53对，仍阻塞全局“无重叠”结论；其中包括既有塔楼/桥/城市关系、基础与既有路线/城市关系，不等同新增远景三角相交。
- `Tower2RemoteSilhouette_A` 与 `City[r2:i11]` 的旧重叠已消除；当前没有执行三角级 mesh intersection，因此不声称三角级通过。

## 资产登记与验证证据

- 运行 manifest：`assets/art/environments/open_world/runtime/open_world_landscape_foundation/asset_manifest.json`，版本 `v002`。
- 运行场景：`assets/art/environments/open_world/runtime/open_world_landscape_foundation/env_open_world_landscape_foundation_root_top3d.tscn`。
- Godot：4.6.3；导入退出码0，日志 `I:/工作项目/shellstrom2/_scratch/landscape_import_final.log`。
- 运行探针退出码0，输出 `LANDSCAPE_RUNTIME_DUMP_OK city=96 foundation=9`；最新 dump `I:/工作项目/shellstrom2/_scratch/landscape_runtime_geometry_final2.json`。
- 根场景及9个独立 PackedScene 均 `loaded=true`；警告仅为项目已有 palette invalid UID 回退文本路径，不是本次景观资源加载失败。
- 真实渲染截图、三角级相交、全工程玩法长测和Blender导出/优化门禁本次未执行。`tests/verification` 中未发现现成的跨塔景观窗口渲染探针；本次没有为了截图新建临时相机/窗口场景，因此不把 headless 结构dump冒充真实渲染证据。
- 未直接修改 XLSX 分账本；`ledger_index.json` 的 scenes 域登记仍需按既有 `shellstorm2-asset-ledger-row-authoring` 流程完成。

## 当前阻塞

1. Tower2 源楼身底部 `Y=-100.5` 与地表 `Y=-80` 的契约冲突未获用户批准，故保留并标红。
2. 53 对保守 AABB/XZ 重叠中包含既有路线、城市、桥和基础包络关系，尚不能把整组声明为“无重叠”；三角级未执行。
3. 尚未执行带窗口真实渲染截图，也未完成场景分账本登记、MODULE_INDEX/CHANGELOG 定点登记和Git提交（按要求不提交）。
4. 本次修改前快照与哈希见 `I:/工作项目/shellstrom2/_scratch/landscape_pre_geometry_fix/baseline.json`；其范围只覆盖本轮修改前三个目标文件，不代表任务起始全工程备份。
