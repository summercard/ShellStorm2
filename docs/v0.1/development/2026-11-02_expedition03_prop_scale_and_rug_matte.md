# 远征03陈设倍增、入口展示移除与地毯亚光

日期：2026-11-02。FeatureID：WORLD-PLAN / ASSET-PIPELINE。来源：用户五张实机截图的三项明确返修。

## 交付结果

1. 安全房中央五件来自DungeonRoom3D固定展示分支，不是正式TSCN的墙边摆件。本关通过furnishing.fixed_lobby_clutter_enabled=false关闭；DungeonRoom3D缺省true，经TowerDescent3D记录及Dungeon3D初始房间、TowerDescent3D动态房间两条configure路径透传。正式房间手摆24件易碎设施保留。
2. 实测图示窄桌、行李车、小盆栽原来均单位缩放，没有被等比缩小；本轮在20份有效房间TSCN中把201窄桌、17行李车、109小盆栽按当前尺寸XYZ×2，400件桌面灯/文件/固定花艺随宿主同步，共727个实例Transform。已有1.25倍插花按原比例再×2，不能误判为必须绝对2.0。源几何、Prefab和其他家具不改；模型/碰撞包络一起做局部避让。
3. 三类公馆地毯采用manor_rug_palette_post_import.gd，继承原公共色盘绑定后覆写织物参数：roughness0.96、metallic/specular0、clearcoat/emission关闭。颜色、PaletteUV、采样和稳定路径不变，重导入仍为亚光；原GLB/Blender几何不变。

## 验证

- 20份正式文件逐节点对照备份：只修改727个目标实例Transform，其他文本、节点身份、灯光参数和碰撞定义保持。附属物相对宿主的变换一致放大；全部目标三轴比例相对原值×2。
- Godot专项退出0：2209项断言，含逐节点保存/相对缩放、三地毯亚光与公共色盘、默认安全房五件保留/显式关闭两组对照、受影响件全部合法门位净空；0断言错误。
- 真实碰撞盒投影与原布局对照，受影响件新增物理重叠0。复查修正3组新门口冲突与3对物理重叠，最终均0新增。原布局中2份文件的8条既有候选门位净空问题保持，本轮没有放宽阈值或改动相关柜架；结果详见door_comparison.json。
- 原生Forward+实际关卡，种子1118653462：中央样品5→0，作者设施24→24；流送卸载重建后中央仍0、作者设施仍24。布局ID前后逐字相同f00_b5641fb3a7ead30d。正式用户存档未使用：测试前即在独立project.godot显式设置自定义目录，实际OS.get_user_data_dir核对为ShellStorm2_verification_manor_adjustments_20261102。
- 原生最终运行未出现SCRIPT ERROR/引擎ERROR；旧资源公共色盘UID失效后按文本路径加载的WARNING单独保留，未以此宣称全库无告警。
- 早期验证发现Transform3D手写行列顺序不一致，改用Godot var_to_str/str_to_var原生序列化；入口房初始configure最初漏透传，补齐后重新完成实际运行；失败日志留在工程外，不计为通过。

## 文档与账本

同步远征03主设计、场景工坊流程和场景账本。房间运行登记更新本轮20行的当前SHA、日期和依据，不改历史保留快照SHA；3件地毯主表/Prefab备注及导入manifest登记PBR覆写，无损基线仅更新有意变更行和相关分页摘要。

[修改前原生画面](../../art/expedition03_adjustments_20261102/before_runtime.png) / [修改后原生画面](../../art/expedition03_adjustments_20261102/after_runtime.png)。专项JSON、源对照摘要同目录。过程脚本与完整日志在ShellStorm2-work/sessions/2026-11-02_manor_adjustments，改前文件在ShellStorm2-backup/2026-11-02_manor_adjustments/before_edits。

未执行：完整通关、全量战斗/寻路/结算套件及其他渲染后端；不提升整关partial状态。不提交或推送。

项目门禁：关卡解耦、运行命名、资产登记结构、全域账本拆分一致性及本轮git diff --check均退出0；文档总检查退出1，报告17项既有断链/登记问题，本轮新记录与证据链接未报错。20行当前SHA再次逐行核对与磁盘一致。
