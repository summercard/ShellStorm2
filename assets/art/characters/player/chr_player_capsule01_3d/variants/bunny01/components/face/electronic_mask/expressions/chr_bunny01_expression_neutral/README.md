# 电子面具表情：平静

AssetID：`CHR-PLY-BUNNY01-EXPR-NEUTRAL`；子版本v003，父面具v005；expression_id=`neutral`。

180颗11.8mm方块，14mm网格，颜色#21bfff；自发光1.25（原5的25%）；类别emotion；情绪无嘴部，眼睛/爱心/符号加粗放大。原head局部原点，独立根缩放1，无骨架/碰撞/玩法系统。

共享[模型母版](../../source/chr_bunny01_electronic_mask_model_v005.blend)与[动作母版](../../source/chr_bunny01_electronic_mask_animation_v005.blend)，用source_object `SRC_Face_ElectronicMask_Pixels`定位；此资产单独登记角色主表/组件/3D/表达记录。

由独立CharacterExpressionSystem选择，状态机通过适配器发命令；显示端消费网格及已有眨眼/闪烁，符号不压缩。源/中转哈希见[清单](asset_manifest.json)，[Forward+实拍](previews/expression_front.png)。独立逻辑与真实渲染验收通过。
