# 胖子僵尸03：补齐九段动作源

2026-10-03；ENEMY-AI / ASSET-PIPELINE；ENM-NORMAL-FAT-ZOMBIE03；资产v008、模型v002、动作v006。

新增hurt 0.8秒、dead 2.6秒、awaken 1.2秒、alert 0.6秒、turn_l/turn_r各0.8秒、move_start 0.4秒、move_stop 0.6秒、hit_light 0.3秒，全部30fps单次。已有idle/walking/running/attack的曲线及键值逐项比较不变。

死亡为屈膝失力、向前倒伏、前臂伸撑、腿向后摊开，F36触地后一次2.5厘米回弹，F54—78静止。对死亡过渡进行网格接地修正并以四分之一帧烘焙，半帧全网格检查；Root固定、不缩放骨骼。死亡未制作独立软体腹部模拟，也未逐脚安排左右膝的独立碰撞事件。真实三分之四、侧面预览位于previews/complete_v006/。

轻受击仅有Waist/Spine01/Spine02/Neck/Head/HeadTop_End轨道。glTF导出筛选后，Godot仍可能补全默认骨轨道，因此增加专属EditorScenePostImport过滤。该剪辑是局部替换轨道，不是已减去参考姿势的加法差量；后续必须通过骨过滤混合接入，不能全身播放覆盖攻击。

起步末帧对接walking F0，刹停回idle F0；running起停过渡待状态适配。转向提供左右换脚和躯干扭转，Root无yaw，真实转角由后续适配提供。13段源齐全不等于完整AI与伤害接线完成；不标记active。

Godot逐段验证名称、时长、循环与运动幅度，另外检查死亡末段保持、起停接缝及轻受击轨道白名单。源报告validation.json，Godot报告godot_validation.json。结构、无损拆分与asset_guard专项检查，既存全局SHA/命名/文档门禁问题单列gates.json。回退源animation_v005与complete_v006_backup。
