# 无枪摆臂与双槽收取枪 v032

FeatureID：PLAYER-STATE / ASSET-PIPELINE / SAVE-PROFILE。工程0.1.0；现有资产CHR-PLY-CAPSULE01-3D-BUNNY01版本增量，模型装配保持v021。

## 规则与实现

- 无枪前进/后退的慢走、正常移动共4条循环增加肩肘带动的前后交替摆臂；无枪侧移及其他72条旧剪辑保持。耳朵沿用对应移动动作。
- 短枪、长枪、机枪各有主/副背槽收枪与取枪，共12条单次动作，每段0.45秒。右手将枪移至背部再释放；取枪反向执行。运行时叠加手部与枪挂点，下肢、身体和耳朵继续基础移动动作。
- 按1/2选择对应槽；重复按手中槽位则收起，手为空、两把已装备武器显示在背部；空手按有效槽取枪；换另一槽先收后取。空槽不操作，过渡期间不接受重复请求、射击或换弹；死亡/锁定等中断会结束过渡。
- Player3D保留active_weapon_slot与武器实例身份，独立weapon_holstered控制显示与战斗门禁；HUD手持标识区分选中槽。Dungeon3D快捷键接入请求流程，并在运行快照中保存/恢复weapon_holstered。装备事务与即时恢复接口继续保留。
- CharacterMotionLibrary3D按Player3D输出的phase/progress采样上半身源动画，不增加顶层角色状态或运行时手部IK。枪挂点持续绑定导出的右掌偏移。

## 产物与证据

动作母版：`assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/animation/chr_bunny01_animation_v032.blend`。
稳定采样库、GLB、中转和Prefab路径不变；JSON共88条，GLB74条（旧14条保留JSON采样）。GLB按动作声明时长统一60fps时间基准，不依赖混合场景fps。

证据目录：`outputs/character_pipeline/switch_v032/`。源文件重开16条专项通过，收取枪子帧掌心偏差小于0.4mm、缩放保持单位；Godot收取枪专项96检查通过（headless及真实渲染），方向270、开火373及动画/待机/姿势碰撞/换装/包围盒/下身挂点/状态画廊回归通过。装备事务、武器实例契约及归属回归通过。用户存档在autoload前隔离。

预览：`weapon_switch.gif`；测试入口：`tests/verification/verify_player3d_weapon_switch.tscn`，已注册专项套件。

## 边界

未执行全项目及移动端性能套件。远征续档入口headless返回SKIP，不计入通过；本轮验证收枪标志恢复与双背负显示，不宣称完整续档链路通过。手持与背负沿用原有不同显示倍率，交接处仍有尺寸切换。其他长枪支撑差异、世界脚底锁定、换弹/蓄力/重近战专属动作仍待完善。全局既有文档、命名和非本资产SHA问题不在本次范围，不修改债务白名单。

按角色S1–S6链路保留旧母版，以既有AssetID登记增量；无关账本格、公式、数据验证及资产指纹通过白名单差异保护，不整体重建基线。回退仅撤本轮角色代码差异并恢复v031导出，不覆盖其它工作区修改。
