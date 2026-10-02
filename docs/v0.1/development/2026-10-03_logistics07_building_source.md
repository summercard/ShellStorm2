# 07号物流建筑 Blender 源制作与登记

- FeatureID：ASSET-PIPELINE。工程版本：0.1.0。日期：2026-10-03。
- 来源：用户提供的 SKYLINE LOGISTICS 07 号建筑参考图，并明确要求按项目制作 skill 完成、录入账本。
- AssetID：`ENV-OPENWORLD-LOGISTICS07`。当前源：v004。
- 范围：独立开放世界建筑外观美术源，三段立面、屋顶设施、广告牌、办公入口、三联装卸门与静态车辆展示。不改变现有关卡、塔楼、玩法或运行时布局。

## 依据与尺度

执行 `scene-full-pipeline` 的阶段路由、`blender-game-prop-standard` 及其完整 specification、`shellstorm2-asset-ledger-row-authoring`。工程依据为 [资产规范](../10_资产与内容规范.md)、[场景流程](../10.1_3D场景美术生产流程.md)和 [3D目录规范](../../../assets/art/3D模型资产目录与命名规范.md)。

参考图无实际尺寸。本次采用明确标注的外观美术尺度：主体28×20×18m、Blender Z-up、正面-Y、地面Z=0、屋顶18m。该尺寸不是新关卡契约，不套用主塔12m战斗墙体，也不宣称具备楼内通行。`block_id=open_world`，`floor_range=三段立面及屋顶`。制作计划与参考图在源目录保留。

## 交付

源文件：`assets/art/environments/open_world/source/logistics_07/v004/env_logistics_07_source_v004.blend`。v001–v003保留为过程回滚源，独立目录的 `.gdignore` 阻止制作源进入Godot导入。

334个末级资产包与334份磁盘manifest一一对应，25类组件制作计划；345个输出网格、345个隐藏制作网格，输出51,368多边形。每包记录局部原点、世界位置、朝向、尺寸、材质、碰撞与导出状态。文字保留可编辑字体源及网格输出。地砖和自身标记归同一独立地砖包，车辆、叉车、箱堆与花池为独立静态展示资产包，不具备物理或交互逻辑。

保留4个规范材质角色，外链唯一公共色盘，不生成私有贴图；主体与自发光网格分离。共6张Cycles真实渲染：参考全景、屋顶俯视、入口广告近景、装卸区、屋顶设备、背面完整性。展示相机灯光独立归类。

## 验收与登记

| 检查 | 退出码 | 结果 |
|---|---|---|
| Blender后台构建及6视角渲染 | 0 | 源与预览保存成功 |
| `tools/blender/audit_logistics07_source.py` | 0 | 重开文件，包归属、清单、包围盒、140块屋顶地砖、关键结构、非负地面通过 |
| skill `validate_game_prop.py --all-meshes --max-materials 4` | 0 | 源和输出共102,736面全部具备单格内有面积PaletteUV；材质、活动UV、Closest、外链色盘通过 |
| `check_asset_registry.py --scope structure` | 0 | 全域账本结构通过 |
| `verify_ledger_split.py` | 0 | 9域、1004资产，无丢失、无额外资产、无列摘要漂移 |
| `check_asset_registry.py --scope full --ledger scenes` | 1 | 写入前后相同的153项旧资产SHA不一致；本次资产无问题，逐项差异对照在qa记录 |
| `check_asset_runtime_naming.py` | 1 | 工程既有带版本运行路径及引用债务；本次仅创建source目录，没有新建运行资产 |
| `check_documentation_contracts.py` | 1 | 同一Python解释器复跑，仍有4项既有未注册验证脚本；无本次文档路径错误 |

本次新行位于场景分账本《资产主表》第824行，状态为“Blender源已完成”，版本v004，记录源文件SHA-256。账本路径由 `assets/registry/ledger_index.json` 解析；同步查重公式区间、总览、数据验证、域变更日志及新增资产基线。旧资产内容列与指纹未改动。备份位于 `_scratch/logistics07_ledger_backup/`。

文档检查最初由系统 `python3` 启动子检查导致缺少openpyxl，复跑仅把子进程解释器绑定为有依赖的当前Python，未修改检查规则。剩余未登记脚本为 `verify_base99_swivel_chairs`、`verify_expedition01_spawn_ramp`、`verify_expedition_resume_entry`、`verify_pushable_base_chairs`，不在本次修改范围。

## 当前边界

本次完成建筑Blender源与资产登记；未生成优化派生源、GLB、Godot PackedScene、碰撞、LOD、导航或游戏摆位，不向3D Prefab分页写空壳记录。公共色盘限制下，颜色与参考图的写实旧化质感存在差异；预览供用户进行最终视觉复核。未提升ASSET-PIPELINE整体完成状态。
