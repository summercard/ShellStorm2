# v0.1 模块、功能与工程契约索引

工程版本：0.1.0。设计索引修订：r8（2026-09-23）。事实核对基线：`622d6c4a` + 当前工作区。
本表建立追溯入口，不替代各模块设计，也不把现存实现自动认定为设计已批准。功能关系、解耦和文档补全见[执行计划](FEATURE_RELATIONSHIP_PLAN.md)与[逐项跟踪表](FEATURE_RELATIONSHIP_MATRIX.md)。[P0/P1/P2 后全项目完整复评](audits/2026-09-23_full_project_reassessment.md)保留其原时点证据；后续资产复核和开发记录优先于其中的旧数字。

## 1. 独立开发判断

“可独立”指可以通过清晰输入/输出和替身验证规则，不要求脱离 Godot 引擎；“部分”表示已有边界，但正式接入仍依赖全局或场景内部；“不足”表示状态、UI、存档或场景编排混合。按目录分文件、存在信号或存在测试，均不足以单独证明解耦。

| 模块ID | 当前事实所有者与数据链 | 独立开发结论 | 首要缺口 |
|---|---|---|---|
| PLAYER | `Player3D`状态/生命→独立状态类→Avatar；`PlayerInteractionController3D`仲裁→门/设施命令 | 部分 | Player3D仍含装备、背包接口、动作与全局依赖；状态原因契约不完整 |
| WEAPON | `BlueprintRegistry/ItemRegistry`内容→`WeaponInstance`→装配树→`WeaponModel3D/Projectile3D` | 部分 | 统一命中上下文、内容导入与全局所有权账本未闭环；需先明确节点树的生命周期 |
| INVENTORY | `InventoryModule/InsuranceModule`格位→`EquipmentTransactionService`换装→玩家实例槽 | 换装事务可独立，其余部分 | 场景仍编排卸装、快捷栏、掉落、回滚；集合去重不是全局唯一账本 |
| FATE | `FateCardPresets/TarotFateCatalog`→`FateCardEngine`→武器/角色/世界持有者 | 部分 | 世界执行器耦合Dungeon；48运行卡与78设计卡要持续区分 |
| WORLD | `FloorPlanGenerator`纯计划（塔楼 `generate()` + 远征 `generate_expedition()`）→`RoomGraphRuntime`查询→`Dungeon3D/TowerDescent3D`装配；`WORLD-BLOCKS`定义区块归属（塔楼主场景四区块 + 远征场景 `Blocks/Expedition`）；`BaseFacilityCatalog(mission_operations)`→`RogueMapSelectMenu`→`ExpeditionLoadingScreen`→远征关卡场景提供关卡入口 | 计划/查询可独立，生命周期部分收口 | 到达门现为“FloorBundle成功→快照成功→开门”；隔离卸载先落盘提交意图再删节点，恢复会重放已卸载段。但父子编排和私有字段依赖仍多，完整生命周期Service仍未提取 |
| ENEMY | `Enemy3D`战斗、`MonsterAIManager`调度、`EnemyIllumination3D`光照查询 | 部分 | 公共管理器及空间上下文必需；物种行为主要集中在Enemy3D |
| ELITE | `EliteContentCatalog`静态名册→`EliteRosterService`预约/成长→`BaseManager`公开档案命令/查询→`BaseData.elite_archive_records` | 部分 | 跨域私有字段写入已移除，写盘失败由BaseManager回滚；仅1/12内容投放 |
| BOSS | `BossContentCatalog`95/90/85定义→Enemy3D阶段→塔楼下行权限计数 | 部分 | 设计Boss钥匙ID与当前计数式授权不一致；门和持久化交接不足 |
| BASE | `BaseFacilityCatalog/Service`→`BaseManager`→BaseData；`BlueprintUpgradeService`拥有工坊纯规则；设施适配器→UI | 规则可局部独立，工坊事务已独立验收 | Manager仍含存储/多类交易/能源/外观/运行档；成本表尚未外置为版本化内容 |
| SAVE | `RunPersistenceService`快照→`ProfileSaveService`封套→`AtomicJsonStore`→BaseManager | 序列化可独立，结算/工坊/隔离边界已有事务 | 多写者互斥与领域通知未统一；塔楼完整故障套件仍受隐藏旧流程/P0基线限制 |
| NARRATIVE | 触发声明（位置/事件/脚本）→时间轴 JSON→`NarrativeDirector3D`绑定`NarrativeAdapter3D`→对话/奖励/房间地面物；完整收口→`BaseManager.narrative_history` | 部分；核心运行链与`run`跨局历史已接入 | `scene.spawn_item`经奖励服务解析并挂入房间；`BaseManager`独占长期历史写入且失败回滚。`retry/never`新语义、通用条件与全部内容投放仍待裁决/施工 |
| TIME | `WorldTimeDomain`→`GameTimeManager`→BaseData时间→太阳/HUD/能源恢复输入 | 算法可独立，接入部分 | 规则仍为代码常量；联动、持久化测试需进入明确模块验收集 |
| POWER | `BaseEnergyService/BaseManager`拥有基地电力；`PlayerFlashlight3D`拥有行动手电电量；恢复舱负责两域转换 | 当前两条链可独立验证，系统开发中 | 基地灯光与设施负载尚未接统一电网服务、事件和真实表现验收 |
| ENTRY | `GameEntryFlow`一次性入口意图→塔楼主页→玩法；AvatarCustomizationPersistence→BaseData | 部分 | 塔楼仍负责主页与设施UI装配；外观作者包、运行包装、用户装配版本需分别追踪 |
| PRESENTATION | `HUDPresenter3D`快照、公共UI组件；VfxPool/CombatEffectPool、AudioManager、MusicManager | HUD/音乐部分；VFX未收敛 | UI、音效、音乐已有独立账本/Skill/验收链；旧CombatEffectPool兼容链仍在；后处理仍缺独立主设计 |
| PERFORMANCE | GraphicsSettingsManager、PostfxOverlay、RuntimePerformanceManager→场景/渲染 | 部分 | 调参面板越过画质服务；预算失配、渲染用例归类不全 |
| TRAINING | `TrainingRange3D`→只读BlueprintRegistry→共用Player3D→训练会话统计 | **测试功能1.0已完成，可独立启动与验收** | 后续伤害分析、靶标编辑和自动压测另升功能版本 |
| ASSET | XLSX台账→生产源/转移账本→GLB→PackedScene→正式场景 | 有生产标准，运行表现仍需逐批验收 | 新拉取后9本分账本410项，完整性和拆账漂移均为0；真实渲染和未来增量仍需按域核签 |
| TOOLING | tests/verification、脚本、src/testing→隔离工程→日志与退出码 | 部分 | 用户目录与 `.godot` 已隔离，冷/热缓存自检通过；156 个验证场景已全部唯一归属；验证注册、跨域边界、37功能追溯和媒体资产门禁已并入文档总门禁 |

## 2. 功能追溯表

“设计”指已有主设计入口，完整性另列。“历史定位”不等于本次重新通过；记录缺失必须补实证，不能倒填虚构开发过程。

机器可追溯副本见 [`feature_registry.json`](feature_registry.json)。它为本表 37 个 FeatureID 逐条登记唯一状态 Owner、主设计、开发记录和已注册验收；`python3 scripts/check_feature_traceability.py` 阻止缺项、断链和未注册场景回退。

| 功能ID | 功能 | 主设计 | 正式代码/数据入口 | 验收入口（tests/verification） | 契约与记录现状 |
|---|---|---|---|---|---|
| PLAYER-STATE | 八态、移动、受击、冲刺 | [03](03_技术施工_玩家与操作.md) | `src/player3d/Player3D.gd`、`states/` | `verify_player3d_animation_flow` | 手枪待机/移动/换弹/开火/gallery专项已按显式`bp_pistol`前置恢复并通过；原因码/回放待补 |
| PLAYER-INTERACT | 门、灯、设施统一仲裁 | [03](03_技术施工_玩家与操作.md) | `PlayerInteractionController3D`→Tower | `verify_unified_player_interaction_flow` | 实现存在；原完成度“未统一”过期 |
| PLAYER-LIGHT | 手电、电池、光照/可见性 | [03](03_技术施工_玩家与操作.md)、[15.1](15.1_技术施工_电力系统.md) | `PlayerFlashlight3D/PlayerVision3D`→ItemUseHandler | `verify_3d_flashlight_charge_flow` | 当前链已纳入电力系统；基地供电表现仍待完善 |
| WEAPON-COMBAT | 远程/近战、命中与反馈 | [04](04_技术施工_战斗与局内成长.md) | `src/combat3d/`、`src/player3d/melee/` | `verify_3d_melee_combat_flow`、`verify_3d_melee_feedback_flow` | 有设计与历史；反馈验收未通过 |
| WEAPON-OWNERSHIP | 完整武器实例转移 | [04](04_技术施工_战斗与局内成长.md)、[09](09_技术施工_存档结算与复活.md) | `WeaponInstance`→`EquipmentTransactionService` | `verify_equipment_transaction_service`、`verify_weapon_instance_contract_matrix` | 可用替身验证；全局所有权仍待补 |
| INVENTORY-SLOTS | 背包、保险、快捷物品、扩容 | [04](04_技术施工_战斗与局内成长.md) | `InventoryModule/InsuranceModule`→Dungeon→InventoryUI | `verify_backpack_equipment_flow`、`verify_finite_ammo_flow`、`verify_guaranteed_loadout_ammo_flow` | 有规范与历史；场景编排分散 |
| FATE-RULES | 48运行塔罗、78目标牌组、三作用域 | [14](14_技术施工_命运塔罗牌组.md)、[04](04_技术施工_战斗与局内成长.md) | `FateCardPresets/FateCardEngine/TarotFateCatalog` | `verify_tarot_fate_runtime`、`verify_celestial_fate_scope_flow` | 有设计与历史；新增30张未施工 |
| WORLD-PLAN | 纯数据楼层/房间图与四区块归属 | [05](05_技术施工_关卡生成与爬楼.md)、[05.1](05.1_关卡区块设计.md) | `FloorPlanGenerator/RoomGraphRuntime`、`TowerDescent3D/Blocks` | `verify_floor_plan_generator`、`verify_room_graph_persistence_services`、`verify_tower_level_blocks` | 可独立；缺领域版本与完整门事务 |
| WORLD-ENTRY | 关卡入口：基地传送 + 读取界面 + 切换地图进入远征关卡 | [05](05_技术施工_关卡生成与爬楼.md)（§3.0）、[07](07_技术施工_基地设施.md)（§2.2）、[09](09_技术施工_存档结算与复活.md)（§5.1） | `BaseFacilityCatalog(mission_operations, ACTION_MENU)`→`RogueMapSelectMenu`→`ExpeditionLoadingScreen`→`ExpeditionLevel01_3D.tscn`（`expedition_mode`） | `verify_expedition_level01_flow`（已注册进 `core`）、`verify_central_expedition_hologram_facility` | **已完成**：平台交互、菜单、读取界面、场景切换、单层 7 房（15×15 安全房 + room_01…05 各25×25 + 撤离房25×25）、`Blocks/Expedition` 区块、撤离信标、出生点、`runtime_map_id` 存档隔离与 `combat` 作用域、出生安全房「退出战局」弃局离场契约（含关卡内重新上线路径）均已实装 |
| WORLD-GATE | 到达门、Boss门、楼梯 | [05](05_技术施工_关卡生成与爬楼.md)、[09](09_技术施工_存档结算与复活.md) | `TowerDescent3D`→FloorBundle→runtime checkpoint→RoomDoor3D | `verify_arrival_gate_floor_bundle_flow` | 2026-09-23裁决：连续爬塔非当前主玩法，97F以下关闭；旧到达门/Boss门综合失败降为低优先级保留。正式版本只要求远征主线、99F与98F区块00；未来重开爬塔时复核完整合同 |
| WORLD-SEGMENT | 隔离间、区段卸载、永久遗失 | [05](05_技术施工_关卡生成与爬楼.md)、[09](09_技术施工_存档结算与复活.md) | `TowerDescent3D._finalize_airlock_commit`→BaseManager checkpoint→unload | `verify_arrival_gate_floor_bundle_flow`、`verify_three_segment_tower_generation_flow` | 2026-09-23裁决：三区段、隔离间与永久遗失链当前关闭并降为低优先级；保留实现和验收，不判绿，未来连续爬塔重新开放时统一恢复与核签 |
| WORLD-LOOT | 搜索、清房钥匙、剧情刷物、掉落与拾取 | [04](04_技术施工_战斗与局内成长.md)、[05](05_技术施工_关卡生成与爬楼.md)、[08](08_技术施工_剧情触发.md) | `RuntimeRewardCoordinator`→`RewardService/ItemRegistry`→`Dungeon3D.narrative_spawn_item`/`GroundLootPickup3D` | `verify_reward_service_flow`、`verify_opening_script_runtime`、`verify_finite_ammo_flow` | `scene.spawn_item`已通过固定物品解析进入房间地面物；场景仍通过legacy item字典桥接表现，地面物跨重启恢复尚待契约决定 |
| REWARD-SERVICE | 统一奖励与掉落：一份 Spec → 唯一解析器 → 三个发放口（物品/任务/搜索/怪物/清房钥匙/保底备弹/剧情） | [04](04_技术施工_战斗与局内成长.md)（§22）、[05](05_技术施工_关卡生成与爬楼.md)（§11 `reward_slots[]`）、[01](01_内容数据库说明.md)（§5.5/§5.7） | `src/rewards/`：`RuntimeRewardCoordinator`（运行时调度/确定性事件ID）+`RewardPoolRegistry/RewardSpec/RewardService/RewardSink` | `verify_reward_service_flow`、`verify_requested_experience_upgrade_flow`、`verify_finite_ammo_flow`、`verify_narrative_timeline` | **解析消费点已正式切流**：搜索、击杀、清房、钥匙、保底备弹、剧情`grant.item`及新`scene.spawn_item`的固定物品解析均经统一服务；场景发放仍用legacy item桥，7个deprecated死池待裁决，真渲染截图门禁待补 |
| ENEMY-AI | 感知、导航、攻击、光照 | [06A](06A_怪物AI系统完整设计_评审稿.md)、[06](06_技术施工_怪物精英与Boss.md) | `Enemy3D/MonsterAIManager/MonsterVisionSystem3D` | `verify_monster_ai_system_complete`、`verify_enemy_illumination_states` | 有较完整规范；真实错误日志仍需严查 |
| ELITE-ROSTER | 唯一名册、预约、跨局成长 | [06](06_技术施工_怪物精英与Boss.md) | `EliteContentCatalog/EliteRosterService`→`BaseManager`档案命令/查询→BaseData | `verify_unique_elite_roster_flow`、`verify_first_elite_growth_flow` | 12名册/1投放；私有档案直写已移除，事务失败回滚；其余11为design_only |
| BOSS-STAGES | 95/90/85 Boss及下行权限 | [06](06_技术施工_怪物精英与Boss.md) | `BossContentCatalog`→Enemy3D→Tower | `verify_unique_boss_content_flow` | 有规范；钥匙实体契约未完全对齐 |
| BASE-FACILITY | 设施入口、禁射、常驻和恢复 | [07](07_技术施工_基地设施.md) | `BaseFacilityCatalog/Service`→BaseFacility3D | `verify_base_facility_framework`、`verify_tower_base_facility_persistent_flow` | 全息终端作者锁定交互盒及语义命名StaticBody碰撞已接入，交互区专项通过；其余旧基地资产专项仍待裁决 |
| BASE-SHOP | 基地购买、出售、保险柜转移 | [07](07_技术施工_基地设施.md)、[09](09_技术施工_存档结算与复活.md) | BaseManager事务→BaseShopService→ItemRegistry | `verify_base_shop_save_flow`、`verify_tower_facility_inventory_binding`、`verify_extraction_points_spend_transaction` | 商店已有幂等/回滚；普通资源扣款已在写盘失败和revision冲突时回滚/拒绝，工坊事务也已收口到BASE-WORKSHOP |
| BASE-WORKSHOP | 蓝图升级与手电模块 | [07.1](07.1_玩法系统_枪械工坊.md)、[07](07_技术施工_基地设施.md) | `WorkshopMenu`→`BaseManager.upgrade_blueprint`→`BlueprintUpgradeService`→BaseData | `verify_workshop_transaction_flow`（`core`） | **核心事务已完成**：扣魂+Tier+幂等ID一次写盘；成功/余额不足/旧Tier/写盘失败回滚/重试/重载幂等独立验收通过。成本数据外置和工坊详情表现仍待做 |
| RUN-MERCHANT | 局内商人、消费与回退 | [04.1](04.1_玩法系统_局内商人.md)、[04](04_技术施工_战斗与局内成长.md) | `src/ui/MerchantUI.gd`→GameManager/Inventory | `verify_full_3d_game_flow`（综合） | **开发中**：现行链已记录；会话、货币、背包、撤离条件和快照事务待收口 |
| SAVE-PROFILE | 总档封套、校验、迁移与复位 | [09](09_技术施工_存档结算与复活.md) | `BaseData/ProfileSaveService/AtomicJsonStore` | `verify_pause_game_save_reset_flow`、`verify_base_shop_save_flow`、`verify_extraction_points_spend_transaction` | 普通资源扣款失败回滚已有专项；文件底层失败/备份链仍需补完整故障矩阵 |
| SAVE-RUN | 行动自动存档、重载恢复 | [09](09_技术施工_存档结算与复活.md) | `RunPersistenceService`→Dungeon/Tower快照 | `verify_runtime_autosave_flow`、`verify_tower_runtime_restart_restore`（均已注册 `core`） | 实现与独立入口存在；本次只完成注册治理，故障恢复是否全绿仍以当前运行结果为准 |
| RUN-SETTLE | 撤离、死亡、保险返还 | [09](09_技术施工_存档结算与复活.md) | DeathSettlementModule→Dungeon/Tower→`BaseManager.commit_run_settlement` | `verify_run_settlement_transaction`、`verify_death_during_extraction_flow`、`verify_tower_extraction_return_flow` | 成功/死亡结算已一次原子写盘，写盘失败回滚、重试、跨重载幂等已有独立专项；本轮实测`verify_run_settlement_transaction` 通过 |
| RUN-REVIVE | 复活策略 | [09](09_技术施工_存档结算与复活.md) | `RevivalPolicy`（v0.1 空策略） | `verify_revival_policy_contract` | **契约已建立、玩法仍未实现**：无复活源时稳定返回`no_revival_source`、无预约与副作用；次数/成本/复活点仍由后续设计决定，不把返基地伪装成复活 |
| NARRATIVE-TRIGGER | 剧情触发、时间轴编排与调用权限 | [08](08_技术施工_剧情触发.md) | `src/narrative/`、`NarrativeDirector` Autoload、`BaseManager.narrative_history`、`data/narrative/` | `verify_narrative_timeline`、`verify_opening_script_runtime`（均注册 `core`） | **核心链与`run`跨局历史已实装**：完整收口写长期档，抢占/中止不写；剧情可通过`scene.spawn_item`落地物品。`retry/never`新语义、通用条件引擎与全部内容投放仍待裁决/施工。作者侧规范见 Skill `10-narrative-timeline-authoring` |
| DIALOGUE-UI | 底栏对话框、头顶气泡、打字机与推进 | [18](18_技术施工_UI与对话系统.md) | `src/ui/dialogue/DialogueUI.gd`（autoload）、`src/ui/bubble/`（气泡三件） | `verify_dialogue_ui_flow`、`verify_speech_bubble_3d`（均已注册`core`） | **已实装**：底栏（打字机/推进行/三态outcome）与头顶气泡（不透明管线规避TAA拖影）。可脱离剧情单独验收；**契约与实现有6处差异待收敛**（队列/`skippable`/BBCode/带参命令等） |
| TIME-DAYNIGHT | 权威时间、日夜与能源恢复时间输入 | [15](15_技术施工_时间日夜与基地能源.md) | WorldTimeDomain/GameTimeManager→太阳/HUD | `verify_main_entry_realtime_sun_flow` | 已与电力玩法拆分；统一数据配置仍待完善 |
| POWER-SYSTEM | 基地电力、手电电力、恢复舱与未来基地负载 | [15.1](15.1_技术施工_电力系统.md) | BaseEnergyService/BaseManager；PlayerFlashlight3D/ItemUseHandler | `verify_3d_flashlight_charge_flow`、`verify_base_overhaul_flow` | **开发中**：现有两条能源链已记录；基地灯光/设施用电待接入 |
| ENTRY-AVATAR | 启动分流、外观、衣柜、脱困 | [16](16_技术施工_主页面与角色换装.md)、[16.1](16.1_角色美术制作与动作导入流程.md)、[09](09_技术施工_存档结算与复活.md) | GameEntryFlow→Tower新档98F办公室/已有档99F基地→AvatarCustomizationPersistence | `verify_game_entry_flow`、`verify_avatar_return_persistence_flow`、`verify_block00_floor98_assembly` | 新档判据与天台下线误入新档问题已修；开场枪改由剧情生成。独立展示相机/视觉代理目标仍未满足，地面枪未拾取时的跨重启恢复待裁决 |
| UI-HUD | HUD、地图与模态输入 | [04](04_技术施工_战斗与局内成长.md) | HUDPresenter3D/DungeonMinimap3D/InventoryUI | `verify_hud_presenter_3d`、`verify_tactical_inventory_minimap_flow` | Presenter可独立；其他UI仍直接读写多域 |
| VFX-POOL | Prefab注册、借出、回收 | [14.6](14.6_特效系统与制作规范.md) | VfxPool3D/CombatEffectPool3D→战斗调用者 | `verify_vfx_pool_lifecycle`、`verify_combat_vfx_toon_v002`、`verify_3d_melee_feedback_flow`、`verify_3d_enemy_behavior_flow` | 近战和伤害飘字验收已迁正式 `VfxPool3D` AssetID；explosion 兼容链仍保留旧池，尚未完全退役 |
| AUDIO-MUSIC | 音效和场景音乐切换 | [10](10_资产与内容规范.md)、[14.8](14.8_音乐系统与配乐资产.md) | AudioManager/MusicCatalog/MusicManager/MusicTrigger | `verify_music_system`、`verify_requested_experience_upgrade_flow` | UI/音效/音乐已拆独立账本、Skill与验收链；功能层仍保持AudioManager与MusicManager边界，不合并播放生命周期 |
| GRAPHICS-POSTFX | 画面设置、调参、屏幕后处理 | [13](13_技术施工_性能优化与热管理.md)（上级） | GraphicsSettingsManager/PostfxOverlay/FlashlightColorTweaker | `verify_graphics_settings_ui_flow`、`verify_postfx_overlay_runtime` | PostFX 已补独立tscn并注册core；仍缺独立主设计，7/9项口径失配不因入口补齐而自动关闭 |
| PERFORMANCE-RUNTIME | 帧预算、流送、长测与退出 | [13](13_技术施工_性能优化与热管理.md)、[11](11_测试与发布.md) | RuntimePerformanceManager/GameplaySpatialRegistry3D | `verify_3d_performance_budget`、`verify_performance_runtime_complete` | 有规范/历史；节点预算失败，未执行本次真实GPU/长测 |
| TRAINING-RANGE | 独立靶场与武器预览 | [11.1](11.1_测试功能_独立训练场.md) | `src/training3d/TrainingRange3D.gd` | `verify_training_range_3d_flow`、`verify_training_range_3d_visual` | **功能版本1.0已完成**：当前注册表 19 架、67 组合，三类靶标、重置/退出、暂停及 BaseData 隔离均由注册表驱动的独立契约覆盖 |
| ASSET-PIPELINE | 模型、组件、导入、台账与放置 | [10](10_资产与内容规范.md)、[10.1](10.1_3D场景美术生产流程.md)、[16.1](16.1_角色美术制作与动作导入流程.md)、[账本入口](../../assets/registry/README.md) | 概念→白盒JSON/顶视图→风格稿→Blend→GLB→PackedScene→XLSX | `scripts/check_asset_registry.py`、`scripts/check_media_asset_domains.py`、资产专项、真实场景渲染 | 9本分账本中UI/音效/音乐已各自具有独立账本、Skill与验收链；原合并表现资源账本已退役。新拉取后410项资产完整性与拆账漂移均为0。战斗区 L 型走廊 Blender 房间种类源已拓宽到 15m 的 v003，尚无白模和运行时接入，见[记录](development/2026-09-23_battle_l_corridor_room_type_v003.md)。历史哈希/状态漂移已按正式运行资产和共享单账原则完成核对，后续替换仍需逐项确认来源 |
| ASSET-ROOFTOP | 天台参考组件与标准外墙 | [组件契约r2](design/rooftop_component_library.md) | `tower_zones/rooftop/source/reference_components/v002/`的Blend与catalog；Godot入口保留原版 | `qa/validate_rooftop.py`、锁区签名、严格逐面UV、固定镜头渲染 | Blender源44独立包完成；新增7挂藤变体与厚门口；运行天台设施已清空，见[清空记录](development/2026-09-17_rooftop_facilities_removed.md)；外墙主体5×0.30×11.9m；未导出或接入Godot，见[交付记录](development/2026-09-17_rooftop_ivy_thick_door_v002.md) |

## 3. 开发记录定位

当前全部功能共同关联[本次审计记录](development/2026-09-12_documentation_audit.md)，它只记录审计，不冒充功能开发史。既有功能的原始开发记录按下列位置回溯：

- PLAYER：[玩家历史](development/history/03_玩家与操作_历史记录.md)。
- WEAPON/INVENTORY/FATE/UI：[战斗历史](development/history/04_战斗与局内成长_历史记录.md)。
- ENEMY/ELITE/BOSS：[怪物历史](development/history/06_怪物精英与Boss_历史记录.md)、[精英推送摘要](development/history/14.5_推送更新摘要_2026-08-27.md)。
- BASE：[基地历史](development/history/07_基地设施_历史记录.md)。
- PERFORMANCE/TOOLING：[性能历史](development/history/13_性能优化与热管理_历史记录.md)、[测试历史](development/history/11_测试与发布_历史记录.md)。
- AUDIO/VFX：[音乐修复](development/history/14.8_音乐系统与配乐资产_历史记录.md)、[特效快照](development/history/14.6_特效系统与制作规范_历史记录.md)。
- WORLD/SAVE/TIME/ENTRY/ASSET：[版本开发日志](development/CHANGELOG.md)及[场景成品化历史](development/history/17_天台至98层成品化验收.md)。逐功能关联已收录到 `feature_registry.json`，不再只依赖本节的人工分组。
- P2 追溯和媒体资产拆分：[P2修复记录](development/2026-09-23_p2_media_and_traceability_repair.md)。
- WORLD-ENTRY：[关卡传送入口与远征关卡设计](development/2026-09-18_level_teleport_entry_and_standalone_map.md)、[远征关卡出生安全房退出门契约](development/2026-09-19_standalone_safe_room_exit_contract.md)、[远征关卡01制作记录](development/2026-09-19_expedition_level01_buildout.md)。
- NARRATIVE：剧情时间轴核心链与对话 UI 均已实装并进入 core；见 `src/narrative/`、`verify_narrative_timeline`、`verify_opening_script_runtime`。玩法事件（`MapFateTriggers`/命运卡）与剧情事件保持区分，不合并。RUN-REVIVE 已有空策略契约但无实际复活来源；GRAPHICS-POSTFX 已有独立验收入口但仍缺独立主设计；RUN-MERCHANT与BASE-WORKSHOP已建立开发中文档。开发中功能不得因文档已建立而提前标成实现完成。

## 4. 允许的独立开发方式

优先将楼层计划、房间图查询、装备交换、HUD映射、时间/能源计算作为稳定边界，使用输入快照和替身开发。跨模块输入使用内容ID、实例ID、布局ID、事务ID和版本化快照相连；UI与表现订阅结果，不成为领域事实源。

塔楼生命周期、统一结算、工坊交易、VFX迁移暂不能按“已完全解耦”并行改写；**剧情已冻结命令、数据所有者与失败语义**（见 [08](08_技术施工_剧情触发.md) §5/§6/§8），可按 v0.2 阶段独立施工。其余先冻结命令、数据所有者与失败语义，再做逐链路提取。每次提取同时保留正常流程与故障恢复验收，不做一次性大重写。

`REWARD-SERVICE`（[04](04_技术施工_战斗与局内成长.md) §22）属于“已冻结命令、数据所有者与失败语义”的一类，可按 §22.11 五步独立施工：解析器是 `RefCounted` 纯逻辑，输入 `(spec, seed, floor, depth, multipliers)`、输出实体数组，**不依赖 Godot 场景**即可用替身验证；禁止它反向读 `Dungeon3D`/`RoomGraphRuntime`/任何 `world3d`。第 1 步影子模式不改现网行为，是安全起点。
