# 胖子僵尸03

AssetID：ENM-NORMAL-FAT-ZOMBIE03。源编号：03。内容标识：fat_zombie03。

当前版本v002：从原始FBX重建并修正连接骨重复变换；36根项目核心骨+30根保留附加骨，共66骨。新增无父级Root、Hip挂Root；全部蒙皮权重保留。模型源高3.142857m，按0.70且kind/variant=1展示为2.2m；脚底0，Blender+Y朝前，根Scale=1。颜色贴图512×512。v001仅作历史保留，存在骨架尺寸缺陷，不作为可用回退。

骨名及Root契约已修正，骨架签名独立，不能直接声称可共享其他怪物Action。头、左前臂、右小腿15°旋转对照原始绑定，误差小于0.000003m，局部探针无无关顶点移动；源重开与GLB内嵌512贴图复核通过。**动画尚未制作**：六段必需和七段补充动作已写成设计，尚缺独立动作母版、剪辑与状态绑定，未投放游戏怪物池。

Godot4.6.3实际工程复核66骨、36核心骨齐全、Root与Hip父子关系、512贴图、游戏高度2.2m、0动作及0碰撞。AI/碰撞/HP/伤害/掉落继续归Enemy3D；本包未修改玩法。设计提出的厚血和慢速参数尚未接入配置。

当前模型：source/model/enm_normal_fat_zombie03_model_v002.blend；512贴图：同目录textures/enm_normal_fat_zombie03_basecolor_v002.png。v002预览在previews/；审计在source/model/model_audit_v002.json；中转记录在runtime/character_transfer_ledger.json。

设计唯一主源：docs/v0.1/design/胖子僵尸03动作设计.md；登记到docs/v0.1/design/怪物设计.md。记录见docs/v0.1/development/2026-10-03_fat_zombie03_rig_and_action_design.md。
