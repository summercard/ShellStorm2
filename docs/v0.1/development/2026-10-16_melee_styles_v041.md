# 三类近战动作与打击反馈 v041

需求日期2026-10-16，交付核对2026-10-17。功能：PLAYER-STATE / WEAPON-COMBAT / ENEMY-AI / ASSET-PIPELINE。

主设计：[战斗与物品](../design/战斗奖励与物品流转设计.md)、[动作制作规范](../16.1_角色美术制作与动作导入流程.md)、[特效规范](../14.6_特效系统与制作规范.md)。本记录只记实现证据，参数以主设计为准。

## 实现

棒球棍普通三连；大斧慢速头顶下劈，按住蓄力、松开强击退；大剑点按左右交替横扫，按住进入持续整身旋转，松开收势。保留有效命中后的普通怪0.20/0.30秒硬直，玩家局部1帧停顿，斧普通/蓄力增强为2/4物理帧。空挥无玩家停顿，群体命中不叠加，同轮目标去重；旋风每0.25秒伤害一轮，仍逐目标检查墙体遮挡。

PlayerMeleeCombat3D唯一拥有ready/windup/active/recovery/charging/spinning，Player3D仅转发按下/松开及实施局部停顿；CharacterMotionLibrary3D消费只读快照按真实进度采样。动作来自Blender，碰撞、瞄准根与其他移动状态不由动画驱动。Enemy3D公开硬直与击退接口，死亡与Boss抗打断优先。五个VFX独立Prefab通过VfxPool3D注册，持续效果由动作机显式结束。

角色源：`art_source/characters/player/chr_player_capsule01_3d/variants/bunny01/source/animation/chr_bunny01_animation_v041.blend`。模型/装配v021、骨架SKEL-BUNNY01-004保持。运行库128条：新37条近战，原91条逐值保持；增量GLB仅含37条近战，其余动作保留在完整运行采样JSON及v039源追溯中。双手同源握持，左手柄间距0.18m。运行库路径保持components/chr_bunny01_motion/anim_bunny01_library.json与.glb。

已同步角色主表/动作表/中转记录/3D表、武器三行表现说明、敌人stagger规则、五个VFX主表及3D表、内容数据库输入与表现说明、current_source_index和asset_manifest。新FX编号24至28；资产基线只更新本次9个身份及指定专表，不接受无关哈希漂移。

## 验证证据

日志与预览位于工程外 `../ShellStorm2-work/sessions/2026-10-16_melee_v041/`，所有Godot测试在Autoload之前隔离APPDATA。

| 检查 | 结果 |
|---|---|
| Blender保存重开37动作 | 通过；半帧双掌误差<0.002m，根静止与单位缩放，普通阶段接缝一致 |
| 导出 | 128条JSON/37条纯动画GLB，无预览网格；原91条逐值不变 |
| import | exit0，无脚本错误 |
| verify_player3d_melee_motion（真实渲染） | 2312检查通过，三武器九段/双掌/硬直/命中拍/停顿/击杀/Boss例外 |
| verify_player3d_melee_styles | 50检查通过，输入分流/蓄力击退/旋风全方向和节奏/取消/特效跟随复借 |
| verify_player3d_melee_special_visual（真实渲染） | 264帧通过，7段特殊动作及横扫VFX；已亲眼检查斧下劈与旋风帧 |
| verify_3d_melee_combat_flow、verify_3d_melee_feedback_flow | exit0，无脚本错误；扇区、遮挡、去重与反馈 |
| verify_player3d_directional_motion | 1789检查通过 |
| verify_player3d_weapon_switch | 96检查通过 |
| verify_player3d_animation_flow、verify_player3d_weapon_pose_collision_flow | exit0，无脚本错误 |

首轮方向测试因Prefab仍标v040失败，更新真实动作版本v041后复测通过；没有放宽旧方向断言。此前源旋转四元数半球不连续与采样过疏问题已修复，最终源重开检查通过。旧近战用例按六态/新大剑特效契约更新。完整工程套件、移动设备性能、完整远征存档流程与数值平衡未执行，专项通过不代表这些已验收。

## 回滚

代码按本次文件差异回退；运行库与源备份在`../ShellStorm2-backup/2026-10-16_melee_v040/before_edits`及`../ShellStorm2-backup/2026-10-16_melee_v041/`。账本修改前副本在后者registration_before，恢复需逐域核对后续并行改动，禁止整本覆盖其他会话更新。

## 最终门禁与源归档

资产结构、角色/特效完整账本检查、1292资产分账本无损检查均通过；运行资产命名门禁通过（既有289文件/13目录命名欠账保持）。测试清单补登记两条近战新场景，并为已存在的飘字样式场景明确core归属。v039/v040源移至同批备份retired_sources，当前制作目录只留v041。历史行保持追溯，当前源索引指向v041。

最终文档契约检查通过（issues为空），角色、武器、敌人、特效四域完整检查均通过。Windows默认python3子进程编码曾导致检查器解码失败，使用同一Python解释器及UTF-8环境复跑通过；没有修改检查规则。
