# 远征01下一批九组件优化与正式导入

日期：2026-11-15。功能：ASSET-PIPELINE / WORLD-PLAN。设计依据：[远征01](../design/远征关卡01设计.md)、[制作源目录](../../ART_SOURCE_LAYOUT.md)、[上一批十三件导入](2026-11-15_expedition01_thirteen_component_import.md)。工程版本0.1.0不变。

## 授权、提交与筛选

业主要求先推送已完成工作，再将最新前20里此前未优化件按本次标准优化并导入。先以44个批准文件提交 `ab4152d5d9e15cda83d72490bd5a63762c9fa149`，正常推送到origin/0.2（bf850456→ab4152d5），保留无关记忆/探针/配置/测试报告。十三件独立优化源已由此前提交跟踪，本次未漏源。未强推、未跳过hook。

当前20件中排除11件：工位已有50%候选但未导入；历史优化共享门墙/转角墙/门扇/直墙，以及Boss电缆/显示壳/出口门框/设备组/矩阵/楼梯。共享件按历史处理证据排除，不宣称其已重验当前完整02b标准。剩9件；不从第21名向后补位，不重做已优化件。

OFFICE shelving/corner_guard原运行元数据指向v009源但工程内缺失；从工程同级 `ShellStorm2-backup/2026-10-11_slimming/original_tree/assets/art/environments/tower_zones/expedition/source/common_components/v009/component_packages/` 核对并byte复制源/必要清单回art_source对应位置。归档源与恢复源哈希相同；DB v014同名件不是本轮来源，未用其替代。此恢复不移动/覆盖归档文件。

## 减面与自检

按真实输出集合逐连通小结构，确认圆角箱壳才重建六面方箱，规则直圆杆沿自身轴框架改方截面；非识别件原形保留，不整体Decimate。原材质角色、每块所有loop一致的原色格直接继承，安全内区有面积小UV岛，主体/发光分离。不擅自设计型号差异、调色或美化PBR。

预算 `T_after <= floor(T_before / 5)`，减面率 `R = 1 - T_after / T_before`。同输出集合/求值口径，单组件不乘实例。

| 组件 | 原始三角 | v034三角 | 预算上限 |
|---|---:|---:|---:|
| door_wall | 6604 | 844 | 1320 |
| wall_t970_5m | 6320 | 848 | 1264 |
| wall_top_service | 6048 | 672 | 1209 |
| bridge_guardrail | 5640 | 648 | 1128 |
| wall_t615_5m | 5632 | 736 | 1126 |
| equipment_rack | 5432 | 728 | 1086 |
| shelving | 5076 | 564 | 1015 |
| corner_guard | 4752 | 528 | 950 |
| end_power | 4644 | 612 | 928 |
| 合计 | 50148 | 6180 | 减少87.6765% |

9件各自原包 `export/v034/<slug>_optimized_v034.blend` 与optimization_manifest.json持久保留。独立进程重开严格UV/材质验证9/9通过；整体输出bbox_max_delta_m均0.0，对象/原点/集合偏移与源一致。108张固定6视角前后图与12张细长件局部图保留。主代理逐件六视角复核无大面塌陷、主结构丢失；护栏/墙顶设施/周边护柱全景较细，近景见各包证据。方形化后高光更硬，门墙原始背面深黑与原有孔隙在候选保留，未把它们改成新设计。

## 导入与登记

先备份到工程同级 `ShellStorm2-backup/2026-11-15_expedition01_next9/before_edits/`，从持久优化源重开导出稳定GLB，图片/贴图为0，原Normals/UV保留，无切线空间法线图故显式不导切线。保持GLB/Prefab路径和import UID；Prefab只版本/优化源/GLB哈希元数据改变，非元数据文本一致，碰撞不改。

工程外证据统一由workspace_paths输出：`outputs/expedition01_optimization/next9_20261115/`。`final_report.json`与`import/manifest.json`为正式追溯；`import/godot_verification.json`为真实组件验证。

- Godot正式import自然退出0，原始日志逐条确认九目标及后处理完成；首次监控ANSI/英文STEP匹配漏记已修成日志复核，不伪造重导结果。全项目含旧UID信息，不声明全工程clean。
- 启动前隔离APPDATA/LOCALAPPDATA，真实OpenGL组件加载exit0，9/9、failures=[]；实际三角/版本/公共色盘/Closest/轴向原点bbox/原碰撞数均符合记录。专项0 SCRIPT ERROR/ERROR；旧资源UID与兼容渲染TAA告警保留。
- 原始源与其依赖/色盘哈希不变，177份房间TSCN及工位GLB/Prefab保持；不改整房布局、玩法、角色、存档。
- 九源包asset_manifest定点追溯v034、优化源hash、实际GLB/Prefabhash/面数及引用。旧ID不重命名不扩登记。场景账本仅Y243（OFFICE5件）、Y244（BRIDGE2件）、Y246（DB2件）+域日志r120更新；baseline仅三房型指纹及col25，所有3D分页/公式/DV保持。asset_count1447、union1449的旧差异不吸收。

账本门禁改前改后输出一致（地址噪声归一），旧红项保持；运行命名与账本引用exit0。最终文档检查exit1，11条均为旧断链，本批开发记录与新增日志/索引入口无断链；运行命名exit0，关卡解耦exit0（7容器、0违规），证据见final_gates.json。未跑整关通行/角色胶囊净空、Forward+帧率、移动端或完整smoke/core/full，不提升整关partial。

## 交付边界

第一步推送已完成。随后九件优化及导入为本地新工作，不追加第二次推送；未获另一次推送指令时不把它混入先前checkpoint。总图all9_before_after.png便于直接查看，不依赖HTML相对图片加载。
