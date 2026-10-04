# 胖子僵尸03：行走屈肘与夸张跑步

2026-10-03；FeatureID：ENEMY-AI、ASSET-PIPELINE；AssetID：ENM-NORMAL-FAT-ZOMBIE03；资产v005，模型v002，动画v003。

依据用户确认的行走脚步，仅调整上半身双臂：上臂略抬，小臂前收，自然屈肘，手掌保持展开。保存重开后以半帧采样逐骨比较v002/v003，walking的Root、Hip、双腿与双脚矩阵误差0；idle全部骨骼矩阵误差0。

新制作running：30fps、F0—36闭合、1.2秒；张臂屈肘，手臂前后甩摆约24°，胸肩侧摆±9°、扭转±10°，腰腹与头部错拍跟随。髋左右总幅8cm、上下起伏6cm；抬脚9cm，F0/F18重踏，支撑周期60%，没有双脚同时腾空。按步幅标定参考速度0.60m/s；仅修订动作设计建议，未修改玩法速度配置。

真实渲染三分之四、侧面和顶视角序列，顶视剪影双臂在身体外可辨。跑步最小双手横向间距约1.98m、双肘约1.70m；头部左右总幅约15.9cm。根固定、全部骨骼Scale为1，蒙皮网格和静止骨架签名未改。未声称腹部有独立软体模拟，腹部随腰腹骨链做错拍摆动。

Godot4.6.3实际导入3段动作，时长3.2/2.0/1.2秒，均LOOP_LINEAR，66骨，Prefab默认idle；关闭running循环的内存负对照按预期退出1、报告失败，正式资源保持循环。Blender连续两轮半帧采样通过，报告在资产previews/locomotion_v003/；preservation_and_amplitude.json记录保留性和幅度，godot_validation.json及godot_negative_loop.json记录导入与反向验证。

敌人账本主表、3D-敌人、敌人动画与状态、域日志、中转JSON和无损基线同步为3段已验收、余10段待制作。动画源source/animation/enm_normal_fat_zombie03_animation_v003.blend，稳定GLB原位覆盖；v002源与_scratch/fat_zombie03/locomotion_v003_backup保留回滚。完整AI绑定、攻击/受击/死亡等其余动作及实际投放未完成。

结构、拆分无损和资产guard专项通过；其他资产既存4项SHA不匹配保持不变。全局命名检查与文档检查仍失败，分别为既存运行路径版本债务、4项测试未注册及python3环境缺openpyxl；未掩盖为全绿，退出码见gates.json。
