# Boss002 十米接近激活

FeatureID：BOSS-STAGES / ENEMY-AI。2026-10-08，技能设计r4，资产保持v034。

用户要求玩家接近10米才激活，播放出场后再战斗。MonitorBossCombat在AI决策前检测存活player_3d节点与Boss根节点的世界距离≤10米，不受模型缩放影响；未触发时保持黑屏首帧和静止，远程非致死伤害不能绕过距离条件。触发后保存activation_started，退出范围继续完整播放6.4秒，完成后才开放战斗。休眠暂停，实例存档保存started/elapsed/completed；早期v034存档按已有进度推导started，更旧档沿用已完成兼容策略。动画、四技能伤害及房间波次不变。

隔离用户目录运行：verify_monitor_boss_flow退出0、562项通过；verify_expedition_monitor_boss_flow退出0、29项通过。覆盖10.01米拒绝、10米边界、死亡玩家拒绝、远程伤害、退出范围续播、未播完禁止战斗、存档及正式房间生成。无非预期脚本错误；远征保留已有收音机材质UID回退警告。未重渲染动画，本次未改表现数据。
