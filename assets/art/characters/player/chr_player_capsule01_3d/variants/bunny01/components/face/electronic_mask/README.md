# Bunny01 电子面具组件

- AssetID：`CHR-PLY-BUNNY01-FACE-ELECTRONIC-MASK`；版本：`v005`。
- 槽位：`glasses`（衣柜显示“面饰”）；样式：`electronic_mask`。
- 和兔耳使用同一“部件/样式”分类：Blender `01_部件/眼镜/眼镜__electronic_mask`。壳体与8个表情分别为可编辑网格。
- [模型母版](source/chr_bunny01_electronic_mask_model_v005.blend)和[动作母版](source/chr_bunny01_electronic_mask_animation_v005.blend)保留原角色11个网格及共享骨架，另加面具与8个表情网格；v001/v002/v003/v004源保留。
- [纯视觉GLB](components/chr_bunny01_electronic_mask_visual.glb)只含 `MaskShell`、`ExpressionPixels`及Blink形态键，没有重复骨架或碰撞。
- [稳定Prefab](runtime/chr_bunny01_electronic_mask_root.tscn)根缩放1，挂 `HeadJoint/FaceAccessorySocket`，从现有头部动作继承姿态。
- 原脸曲面复制后沿 Blender +Y 前移9mm，壳体厚4mm。默认平静为180个蓝光方块、两组6×15排列，颗粒11.8mm、中心间距14mm，每眼约81.8×207.8mm；贴合原头部曲面。
- 新角色及缺失/非法面饰配置默认佩戴。已有存档的合法选择继续保留；衣柜可选电子面具、其他面饰或“不佩戴”。切到女仆头时按既有防穿插规则隐藏面饰，切回兔头恢复选择。
- 双母版共享v021头部原点与骨架签名，保留原角色动作。动作源的线性闭眼/亮度曲线经[JSON中转](components/chr_bunny01_electronic_mask_expression_curves.json)生成[AnimationLibrary](runtime/chr_bunny01_electronic_mask_animations.tres)。`ExpressionPlayer`自动循环12秒`mask_idle`，包括两次眨眼/两段短闪；另有0.26秒`mask_blink`、0.42秒`mask_flicker`。每实例独立材质；纯局部表现，不新增玩家状态。依赖/源/导出哈希见[中转记录](character_transfer_ledger.json)，双母版独立验证见[源审计](source_validation.json)。
- 回滚：将 `PlayerAvatar3D.DEFAULT_CUSTOMIZATION.glasses` 恢复为 `none` 并移除目录映射/配件装配；旧角色、GLB及动作原文件仍在原位置。已有非法样式ID由默认规则回退。

专项入口：`tests/verification/verify_electronic_mask_flow.tscn`。无头模式测试装配、碰撞/武器不变、换装、实际保存/读档、动作跟随；Forward+模式额外截取实际网格并检查蓝光眼睛。

[大眼实际近景](previews/godot_face_closeup.png) · [闭眼](previews/godot_blink_closed.png) · [历史v002的12秒动画](previews/godot_expression.gif)。旧Blender front/three_quarter/face_closeup为v001历史预览。

v005为平静/开心/难过/红色生气/惊讶/爱心/问号/感叹号8种独立网格子资产的无嘴部深化版（子版本v003）；去除所有嘴部，眼睛、爱心及符号加宽加厚，颗粒增加到11.8mm；各有稳定GLB、Prefab与独立账本条目，见[目录数据](components/chr_bunny01_expression_catalog.json)及[实际8种总览](previews/expressions_overview.png)。模型中集合为`眼镜__electronic_mask/表情__<id>`，用source_object定位共享母版里的独立网格。符号不压缩眨眼。

选择/随机/保持的唯一所有者为`CharacterExpressionSystem`，代码在`src/presentation/expressions/`；PlayerExpressionStateAdapter消费真实状态事件随机调用，面具显示端只消费命令事件与网格。独立专项`verify_character_expression_flow`；[接口设计](../../../../../../../../../../docs/v0.1/design/character_expression_system.md)。动态表情不会装备面饰、改玩家状态或写存档。

v005所有表情材质自发光强度由5降低至1.25（减少75%），降低光晕并保持方块清晰；模型与动作双母版、GLB同步。原闪烁曲线使用相对亮度，新恢复强度1.25。
