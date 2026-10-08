# Boss002 v032：贴地挪动与机身扭转

2026-10-08，BOSS-STAGES / ASSET-PIPELINE，游戏0.1.0，动画设计r26。用户要求走路时底座不翘起，直接左右挪动，身体左右扭动。

## 交付

通过已打开的Blender与MCP修改v031动画，另存v032模型/动画双母版。仅修改move的pedestal_motion、support三段及腕部旧倾斜补偿；底座取消23°倾斜、竖直抬升和挪转，横向行程0.46m，底面固定0.005m。后支撑逐段延迟扭转，机身总扭转范围41.36°；双手前后行程约1.08/1.74m。保留1.6s、48帧原地循环、代码上刷和表情。

其他15剪辑数据逐值不变，其他Blender动作曲线哈希不变，v031双母版SHA不变。64骨架静止姿态签名一致，模型几何未改，复用现役纯视觉GLB；只重新采样move并更新稳定路径monitor_motion.json。Prefab元数据、manifest、中转、敌人账本、制作明细同步v032/active。没有修改控制器、碰撞、技能数值、其他动作或远征刷新规则。

规范源位于assets/art/enemies/bosses/enm_boss_monitor002/source/，预览及源检查位于同资产previews/move_v032/；正式状态消费仍是MonitorBossPresentation。回滚保留v031源及Git基线。

## 验收证据

- Blender真实求值97个整/半帧：底面0.004999999–0.005000014m，顶面高度也保持不变，闭环误差0。左右行程0.460000008m、机身扭转41.36°，双母版同签名。source_audit.json记录。
- verify_monitor_boss_flow：509项、退出0、无非预期脚本错误；新增60Hz全圈底座不倾斜、不升降和横移幅度回归。原技能/状态/骨姿态/网格边界判据全部保持。
- verify_monitor_boss_visual --walk：真实OpenGL渲染48帧、退出0、无非预期脚本错误；人工检查起点和左右极值。visual_report.json及frames/记录，monitor_walk.mp4为4圈6.4秒预览。
- MCP初次脚本末尾恢复界面时context.window为空；资产保存、采样与检查已经完成。随后以window_manager.windows[0]恢复界面并独立读取v032成功，未重复改写动作。
- 本轮未重跑完整远征撤离/收益链和其他动作的视频；它们不在本次走路修订范围。

账本与文档门禁结果在交付时补录；保留工作区既有问题，不以历史通过冒充本轮全局通过。
