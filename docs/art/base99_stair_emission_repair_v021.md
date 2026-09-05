# 基地阁楼楼梯与自发光修订

2026-09-05。制作源：`base_facility_runtime_layout_hq_v017.blend`；优化源：`v021/base_facility_runtime_layout_hq_v021_structural.blend`。四项结构包装使用 V021 目录内的 `*_visual_top3d_v002.glb`。

## 楼梯

旧导出把源斜坡转成了世界轴对齐包围盒，造成垂直挡面。西北 L 梯在 V017 改为每跑水平长 5.8m、抬升 3.045m、坡度 27.699°，每跑16级，级高0.1903125m。两跑及顶层接驳平台维持阁楼出口坐标。范围外对象签名核对一致。

游戏使用源网格顶点构成的凸体阻挡。每跑与对应落地平台合为连续凸体，消除胶囊在内部接缝卡住的问题，护栏为独立凸体。角色现有44°最大地面角度保持不变。东侧过渡梯同步修正斜坡转换，造型未改。

## 自发光

源材质发光强度1.5，颜色来自公共色盘。Godot原先使用ADD，将白色发光因子加到色盘上，造成泛白。公共后导入脚本改为MULTIPLY，保留原强度和色盘颜色；已强制重新导入使用该脚本的设施GLB。

V021结构输出将自发光与主体分为独立网格。四包共7个输出网格、31,450三角面，逐面PaletteUV安全区和有效面积检查全部通过。未以整个源场景的历史校验问题替代本次输出验收。

## 验收

- `verify_base99_stair_walkable_v021`：真实Player3D在正式基地完成一楼→两跑→阁楼，以及反向通行；场景色盘发光混合检查通过。
- `verify_base99_structural_asset_integration`：正式基地结构引用检查通过。该既有测试退出时仍有资源释放警告，不影响通行断言。
- `outputs/verification/base99_stair_repair/optimized_output_validation.json`：7个输出网格的31,450个面全部通过UV和材质检查。
- `outputs/verification/base99_stair_repair/godot_stair.png`：正式布局验收截图，使用临时补光以检查结构，不修改游戏照明。

V017修改前备份：`outputs/verification/base99_stair_repair/base_facility_runtime_layout_hq_v017_before_stair_repair.blend`。旧GLB v001保留作回滚。
