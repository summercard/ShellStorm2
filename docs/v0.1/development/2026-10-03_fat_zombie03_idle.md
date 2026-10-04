# 胖子僵尸03待机动画

功能ASSET-PIPELINE / ENEMY-AI；AssetID ENM-NORMAL-FAT-ZOMBIE03；资产v003，模型v002、动作v001。用户要求制作待机动画并更新账本。设计依据：[胖子僵尸03动作设计](../design/胖子僵尸03动作设计.md)的idle段。

## 制作与接入

在source/animation/enm_normal_fat_zombie03_animation_v001.blend建立可编辑idle Action：30fps，F0—96为3.2秒闭环，Blender播放F0—95避免重复闭合帧。前三分之一缓慢吸气后呼气，F48向右移重2cm、F72向左2cm、F96回到起点；胸前倾约8°，双臂垂下、手指自然卷握，肩部稍滞后。Hip呼吸上升1.5cm；脚部以解析双骨求解并逐帧校正鞋底。所有控制已烘焙为骨骼关键帧，不依赖运行脚本生成姿势。

原模型、静止骨架、顶点权重不变，模型与动作骨架签名相同。Root固定、骨Scale=1，碰撞和玩法未修改。GLB覆盖稳定路径；Godot导入设置settings/loop_mode=1，包装内AnimationPlayer默认autoplay=idle。尚未接入完整AI状态；其余12段未制作，整体包不提升active。

## 验证

源级连续两轮、半帧步长共385次：循环矩阵误差0，Root误差约1.4e-14，骨缩放误差0；最低脚底约-0.0000031m（浮点误差），最大脚位移0.0000813m。模型/动作骨架签名一致，网格与权重逐项摘要相同。已复核正面、侧面与三分之四关键姿态，修正手指反向卷曲，输出3.2秒循环GIF。

Godot实际工程导入idle长度3.20000005s、66骨、52条轨道、循环标记LOOP_LINEAR；姿态跨循环误差约8.4e-8，存在实际动作变化。默认待机自动播放接受独立探针验证。账本主表、3D-敌人与动画分页仅推进idle，其他条目保持待制作。

完整状态映射、攻击/受击/死亡时序不在本次验收范围。账本结构、资产查重、无损拆分检查作为本次门禁；全量敌人账本中的原有其他资产哈希不批量回填。

证据：资产包previews/idle_v001/validation.json、godot_validation.json、idle_preview.gif；回退记录位于_scratch/fat_zombie03/idle_v001_backup/。源文件以双母版继续维护，制作脚本仅用于重建本次动作，后续手工编辑不可被无意覆盖。
