# 胖子僵尸03

AssetID `ENM-NORMAL-FAT-ZOMBIE03`，源编号03，调用ID `fat_zombie03`。当前v011，模型/骨架/512贴图、13动画与Enemy3D共用12态正式接入。

模型母版 `source/model/enm_normal_fat_zombie03_model_v003.blend`；动作母版 `source/animation/enm_normal_fat_zombie03_animation_v008.blend`。2867顶点、5690三角、1材质、66骨（36核心+30附加）；Root无父级、Hip挂Root，对象Scale=1。源高3.142857米×0.7=游戏高2.2米。独立骨架签名，不直接共享其他怪物Action。v001骨架有尺寸缺陷，只保留历史。

纯视觉包 `runtime/enm_normal_fat_zombie03_root_top3d.tscn`无碰撞/AI/伤害；`fat_zombie03_formal_visual.gd`仅采样导入动作。实体 `res://scenes/enemies/fat_zombie03.tscn`继承共用Enemy3D。MonsterInjector固定波次/触发盒按ID调用，掉落与倍率沿用共用路径。

基准生命696、伤害19，巡逻0.30/追击0.60米每秒。前摇1.2秒、拍合一次结算、收势1.3秒；F30锁朝向，F36命中须1.55米内、前向半角60度且无墙阻挡。轻击上半身混合，重击硬直0.8秒。死亡立即清碰撞/AI组，原缩放播放2.6秒后回收。

idle/walking/running循环；其他10段单次。巡逻走路，追击/搜索/归位跑步；苏醒、起停、原地转身按状态和朝向触发。状态切换0.1秒导入姿势混合，攻击连续采样。玩法根位移/yaw归Enemy3D。腹部BellyGroundCompression死亡接地时压扁/展开，回弹时部分恢复，非死亡复位零；是离线表现，不是软体物理。hit_light经post_import去除默认下半身轨道，局部替换，不是加法差量。

设计主源 `docs/v0.1/design/胖子僵尸03动作设计.md`及`胖子僵尸03运行配置.md`；源审计、专项152项、负向对照、真实Forward+四图在`outputs/fat_zombie03_integration/`。验收 `tests/verification/verify_fat_zombie03.tscn`；可玩预览 `tests/verification/preview_fat_zombie03.tscn`（R重生/K死亡）。

历史预览 `previews/locomotion_v003/`、`attack_v005/`、`complete_v006/`、`death_v007/`、`belly_v008/`只代表当时版本。此怪已按用户指令接替壳甲卫兵的远征盒、随机池及主题池；专属脚步/拍合新音效未制作。
