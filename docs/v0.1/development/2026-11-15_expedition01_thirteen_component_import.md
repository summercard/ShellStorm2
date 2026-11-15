# 远征01十三优化组件正式导入与当前面数排名

日期：2026-11-15。功能：ASSET-PIPELINE / WORLD-PLAN。工程版本0.1.0不变。输入为[十三件优化候选](2026-11-15_expedition01_thirteen_component_optimization.md)；关卡契约见[远征01设计](../design/远征关卡01设计.md)。

## 授权与实施

用户查看十三件同图对比后明确要求导入并重新统计当前前20。只导入本批十三件；工位v031 50%候选不在本批，仍未替换原运行组件。本批正式GLB和Prefab路径恒定，不重建房间、不改碰撞节点/布局/玩法/存档。

- 桥房near_server/cross_gantry/low_platform_z4805/low_platform_z6005/lower_control、DB workbench_a/repair_island/wall_service、办公室wall_t1110_5m使用v032；四server_rack使用修正版v033。
- 原始源与批准优化源哈希核对通过，先备份再修改。备份位于工程同级 `ShellStorm2-backup/2026-11-15_expedition01_batch13_import/before_edits/`。
- 从已保存并重开的独立优化Blend输出Collection导出，GLB排除图片/贴图/相机/灯/动画，Y-up映射仅一次。
- 首轮5件凹多边形导出出现切线计算警告。逐材质断言不存在NORMAL_MAP节点后，以明确无切线策略重导全部13件：公共色盘纯色材质不消费切线空间法线图，保留法线及UV，不让导出器静默失败。第二轮无该警告；Blender的use_nodes未来弃用提示不影响本版执行。
- 13稳定GLB同路径替换，13Prefab仅asset_version/optimized_path/glb_sha256元数据变化，非元数据文本与备份一致，故碰撞、节点、接口和覆盖均保留；原import UID及公共色盘post-import设置保留。

## 验证

工程外所有证据经 `scripts/workspace_paths.py` 定位到 `outputs/expedition01_optimization/batch13_20261115/import_0932/`。

| 项 | 结果 |
|---|---|
| Blender导出前三角与最终GLB | 13件一致，合计119720→15240，减少87.2703% |
| Godot正式import | 已出现13目标各自import完成以及reimport后置完成；全工程继续重复UID信息，之后停止进程，不宣称整条全工程import正常退出 |
| Godot真实OpenGL组件验证 | exit0，passed=true、13记录、failures=[]；截图godot_thirteen_asset_wall.png |
| 实际加载面数/版本/公共色盘/最近邻 | 13/13通过 |
| 原点与轴向包络 | 与优化源 `(bx,bz,-by)` 预测min/max比较，误差门限1mm，全通过 |
| 碰撞数量 | 逐件与修改前Prefab声明节点数量一致，工作台2，其余原有保持，未新增 |
| 冻结房间 | 177份TSCN哈希保持 |
| 工位 | 原运行GLB/Prefab哈希保持；原16328三角，8162候选未导入 |
| 原始源/批准优化源 | 均与批准清单哈希一致 |

真实加载仍有其他既有资源的公共色盘旧UID路径回退警告，以及兼容渲染器TAA不可用警告。目标13件材质检查通过；不把路径回退视作全工程无问题。未跑真实远征整关游玩、Forward+性能、移动端或完整smoke/core/full套件，不提升整关partial状态。

## 追溯登记

13源包asset_manifest定点补optimization_v032/v033、优化路径/hash、实际triangle_count、runtime_asset_version和稳定运行引用；原始源版本另留，不把原始源版本错误提升为优化版。

十三个含下划线的旧AssetID均无独立账本行，本批不改ID不新增行。场景账本仅资产主表Y243（OFFICE）、Y244（BRIDGE）、Y246（DB）追加追溯，域日志r119/v0.1.89；房型总行M/O/T及全部3D分页保持。baseline仅三总行v与column_digests/25改变；asset_count=1447、当前九域union=1449的旧差异不吸收。逐格报告见ledger_sync/transaction.json；账本备份及改前改后门禁对照见ledger_sync/final_report.json。

场景登记、结构、分账本与远征状态门禁仍为改前红项，改后输出相同（地址噪声归一后），不吞错或放宽。运行命名、账本引用退出0；文档门禁退出1为同一组11条旧断链。本批新开发记录/索引链接另由最终文档检查确认。

## 最新排名口径

按现行远征01房表13主路房间及4秘密共享静态壳递归实际TSCN实例引用，去重172个GLB；从磁盘当前GLB默认场景节点计算三角面，不乘房间摆放数，不扫描未使用旧库，不包含脚本动态创建网格/角色/敌人。数据在current_top20.json（含完整172件与前20）；本批13件全部退出前20。历史优化件本次不排除，方便观察真实当前高面数。排名第一工位仍是原版；第二通用门墙为其他关卡共享资产，后续修改应单列影响范围。
