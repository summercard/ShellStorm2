# 远征01 Boss房组件拆解 QA 报告

## 1. 任务范围

本版本从已验收的房间种类源 `Boss房种类_故障数据库_50x40m_v002.blend` 拆出可复用组件库，并为每个组件生成可独立打开、单独渲染和单独验收的 Blender 源文件。

本次只处理：

- 建筑结构组件
- 地面系统组件
- 固定设施组件
- 环境支持组件
- 完整服务器与破损服务器的独立资产包
- 粗重电线管、墙面护圈和固定卡箍的独立资产包
- 组件 manifest、catalog、组件树、独立文件探针和源文件验收

本次不处理玩法、房间生成、门状态机、敌人、掉落、存档、导航、GLB 导出、Godot 碰撞、Godot PackedScene 或运行时接入。

## 2. 输入与输出

输入源：

`assets/art/environments/tower_zones/expedition/source/room_types/boss_room/v002/Boss房种类_故障数据库_50x40m_v002.blend`

输入源 SHA-256：

`e61a8ca0dcd5b133a09bc13d6567bbcba513838709ea77fbac951670b9ad0b29`

组件库母版：

`assets/art/environments/tower_zones/expedition/source/common_components/v001/expedition_boss_room_components_source_v001.blend`

组件库目录：

- `component_catalog.json`
- `component_tree.txt`
- `decomposition_report.json`
- `component_probe_report.json`
- `independent_files_validation.json`
- `validation_game_prop.json`
- `component_packages/<component_slug>/<component_slug>.blend`
- `component_packages/<component_slug>/asset_manifest.json`
- `component_packages/<component_slug>/component_probe.json`
- `component_packages/<component_slug>/validation_game_prop.json`

## 3. 拆解统计

| 项目 | 结果 |
|---|---:|
| 组件包总数 | 214 |
| 建筑结构 | 77 |
| 地面系统 | 81 |
| 固定设施 | 44 |
| 环境支持 | 12 |
| 输出网格 | 602 |
| 独立 `.blend` 文件 | 214 |
| 独立文件通过数 | 214 / 214 |
| 源对象归属重复 | 0 |
| 源房间 SHA-256 匹配 | 是 |
| `room_owned_geometry` | 全部为 `false` |

214 个组件均有独立输出 Collection、编辑 Collection、ROOT 对象、AssetID、包络、局部原点、正面轴、允许旋转和源文件追溯信息。独立文件不是对房间总场景的引用，而是可单独打开的组件源。

## 4. 独立文件验收

`independent_files_validation.json`：**PASS**

对 214 个独立 `.blend` 文件逐件重新打开并验收，全部通过以下检查：

- 输出对象集合与 catalog 完全一致；
- 文件只有一个组件场景；
- ROOT 位置、旋转和缩放符合单位契约；
- Mesh 相对 ROOT 的局部变换和 `matrix_parent_inverse` 符合单位契约；
- 输出 Collection 的 `instance_offset == (0, 0, 0)`；
- 输出包非空；
- 输出对象只归属于一个输出 Collection；
- 相机已就绪，可单独渲染；
- `room_owned_geometry=false`；
- 独立文件包络与 catalog 一致；
- 组件底部位于局部 `z=0`；
- 标准材质与 PaletteUV 验收通过。

这次验收覆盖了组件文件本身，而不只是母版中的 Collection。母版同时保留 `00_Component_Gallery` 分离展示场景；该场景使用真实 Collection Instance，并按网格分开摆放，不再把归零后的组件重叠到同一位置。

## 5. 三层锚点与接口验收

`component_probe_report.json`：**PASS**

通过项：

- 214 个组件包 Collection 均存在且非空；
- 602 个输出网格均存在；
- 输出 Collection `instance_offset == (0, 0, 0)`；
- ROOT 位置、旋转和缩放均为单位契约；
- Mesh 相对 ROOT 的位置、旋转和缩放均为单位契约；
- 所有输出对象名称唯一；
- 所有输出对象保留 `room_owned_geometry=false`；
- 所有输出组件均有 AssetID、来源 SHA-256、局部包络、正面轴和允许旋转记录；
- 完整服务器、破损服务器、粗重电线管组件均在 catalog 中独立登记；
- 组件没有携带房间编号布局作为运行时固定世界坐标，源世界坐标仅保留在追溯 metadata 中。

正面轴按 Blender Z-up 记录，并在 manifest 中同时写入 Godot 对应轴。完整服务器、破损服务器和管线组件均已登记独立 front-axis 契约；本次未将方位化装饰复制成多个伪通用组件。

## 6. 标准美术资产验收

使用 `blender-game-prop-standard` 的 `validate_game_prop.py` 验收：**PASSED**

最终结果：

- 输出网格扫描数：1216；其中包含母版中的制作源和游戏输出副本；
- 多边形数：86870；
- PaletteUV 合格多边形：86870 / 86870；
- 公共材质角色：4 个；
- 材质预算：通过；
- 无未使用材质：通过；
- 无额外 UV 层：通过；
- PaletteUV 为编辑层和渲染层：通过；
- 色盘外链与 Closest 采样：通过；
- 自发光与主体分离：通过；
- 自发光对象命名：通过；
- 无展示地面或展示台：通过。

每个独立文件还带有自己的 `validation_game_prop.json`，并在独立文件复验中通过 `standard_material_uv` 检查。

## 7. 视觉检查

母版低成本预览：

`renders/component_library_overview_workbench.png`

该图使用 Workbench 灰模，只用于确认组件库整体的形体、厚度、破损状态和管线边界，不作为最终材质渲染证据。

检查结论：

- 服务器柜体保持厚重底座、厚侧护板、深维护舱和顶部压梁；
- 完整服务器与破损服务器可区分；
- 破损服务器没有替换或破坏主体骨架；
- 粗重电线管、弯头、护圈和卡箍没有并入单个服务器包；
- 组件库没有被合并为整屋资产；
- 母版 gallery 已改为分离摆放的组件实例，避免重叠预览造成错误的摆位证据。

本版本没有另外生成完整服务器、破损服务器和管线组件的独立文件代表渲染图；正面轴与局部接口以独立文件探针、manifest 和 catalog 契约为准，不把 Workbench 总览图当作精确轴向验收。

## 8. 已知边界与下一阶段

- 未导出 GLB；
- 未创建 Godot PackedScene；
- 未制作 Godot 碰撞；
- 未接入远征01运行时；
- 未修改远征01设计源、房间生成器、玩法、门状态机、敌人、掉落或存档；
- `runtime_connected=false`；
- `ledger_registration=pending`，当前仍是组件源，不是正式运行时资产；
- 远征01 当前设计源仍没有 Boss 房席位；
- 下一阶段必须由 Godot 导入流程处理 GLB、碰撞、PackedScene、稳定引用和台账转正。

Blender 4.5 Eevee 预览曾触发 GPU shader out-of-memory 崩溃。该问题发生在预览渲染阶段，不影响组件复制、独立文件落盘、独立文件重开或标准验收。最终总览预览改用 Workbench 完成。

## 9. 结论

远征01 Boss 房种类 v002 已按 `02-battle-room-component-decomposer` 拆成组件库源 v001，并完成 214 个独立组件 `.blend` 文件的生成与逐件复验。

当前状态：

`component_source_ready=true`

`independent_files_ready=true`

`independent_files_validation=214/214`

`runtime_connected=false`

本交付可以交给下一阶段的 `godot-model-asset-import-standard` 或对应场景导入流程；不得将本报告解读为 GLB、PackedScene 或运行时接入已完成。
