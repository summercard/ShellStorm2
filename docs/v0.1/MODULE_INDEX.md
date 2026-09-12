# v0.1 模块、功能与工程契约索引

工程版本：0.1.0。设计索引修订：r1（2026-09-12）。审计代码基线：`31ed360`。
本表建立追溯入口，不替代各模块设计，也不把现存实现自动认定为设计已批准。当前验收结果见 [工程审计](audits/2026-09-12_engineering_audit.md)。

## 1. 独立开发判断

“可独立”指可以通过清晰输入/输出和替身验证规则，不要求脱离 Godot 引擎；“部分”表示已有边界，但正式接入仍依赖全局或场景内部；“不足”表示状态、UI、存档或场景编排混合。按目录分文件、存在信号或存在测试，均不足以单独证明解耦。

| 模块ID | 当前事实所有者与数据链 | 独立开发结论 | 首要缺口 |
|---|---|---|---|
| PLAYER | `Player3D`状态/生命→独立状态类→Avatar；`PlayerInteractionController3D`仲裁→门/设施命令 | 部分 | Player3D仍含装备、背包接口、动作与全局依赖；状态原因契约不完整 |
| WEAPON | `BlueprintRegistry/ItemRegistry`内容→`WeaponInstance`→装配树→`WeaponModel3D/Projectile3D` | 部分 | 统一命中上下文、内容导入与全局所有权账本未闭环；需先明确节点树的生命周期 |
| INVENTORY | `InventoryModule/InsuranceModule`格位→`EquipmentTransactionService`换装→玩家实例槽 | 换装事务可独立，其余部分 | 场景仍编排卸装、快捷栏、掉落、回滚；集合去重不是全局唯一账本 |
| FATE | `FateCardPresets/TarotFateCatalog`→`FateCardEngine`→武器/角色/世界持有者 | 部分 | 世界执行器耦合Dungeon；48运行卡与78设计卡要持续区分 |
| WORLD | `FloorPlanGenerator`纯计划→`RoomGraphRuntime`查询→`Dungeon3D/TowerDescent3D`装配 | 计划/查询可独立，生命周期不足 | 9572行父子编排和私有字段依赖；当前设计允许开门/卸载先于快照成功，生命周期Service仍未提取 |
| ENEMY | `Enemy3D`战斗、`MonsterAIManager`调度、`EnemyIllumination3D`光照查询 | 部分 | 公共管理器及空间上下文必需；物种行为主要集中在Enemy3D |
| ELITE | `EliteContentCatalog`静态名册→`EliteRosterService`预约/成长→`BaseData.elite_archive_records` | 部分 | 服务直接写BaseManager.data并调用私有ensure；仅1/12内容投放 |
| BOSS | `BossContentCatalog`95/90/85定义→Enemy3D阶段→塔楼下行权限计数 | 部分 | 设计Boss钥匙ID与当前计数式授权不一致；门和持久化交接不足 |
| BASE | `BaseFacilityCatalog/Service`→`BaseManager`→BaseData；设施适配器→UI | 规则可局部独立，事务部分 | Manager含存储/交易/能源/外观/运行档；工坊UI分两次保存扣款和解锁 |
| SAVE | `RunPersistenceService`快照→`ProfileSaveService`封套→`AtomicJsonStore`→BaseManager | 序列化可独立，业务提交不足 | 结算事务、故障恢复、多写者互斥和领域通知未统一 |
| NARRATIVE | 目标`NarrativeTriggerService`；当前仅NPC静态对话与MapFateTriggers | 未建立 | 定义表、队列、去重、中断、奖励提交、剧情存档和三条切片均未闭环 |
| TIME | `WorldTimeDomain`→`GameTimeManager`→BaseData时间→太阳/HUD/能源恢复输入 | 算法可独立，接入部分 | 规则仍为代码常量；联动、持久化测试需进入明确模块验收集 |
| POWER | `BaseEnergyService/BaseManager`拥有基地电力；`PlayerFlashlight3D`拥有行动手电电量；恢复舱负责两域转换 | 当前两条链可独立验证，系统开发中 | 基地灯光与设施负载尚未接统一电网服务、事件和真实表现验收 |
| ENTRY | `GameEntryFlow`一次性入口意图→塔楼主页→玩法；AvatarCustomizationPersistence→BaseData | 部分 | 塔楼仍负责主页与设施UI装配；外观作者包、运行包装、用户装配版本需分别追踪 |
| PRESENTATION | `HUDPresenter3D`快照、公共UI组件；VfxPool/CombatEffectPool、AudioManager、MusicManager | HUD/音乐部分；VFX未收敛 | 新旧特效并行且回收失败；UI仍有业务事务；后处理缺独立设计 |
| PERFORMANCE | GraphicsSettingsManager、PostfxOverlay、RuntimePerformanceManager→场景/渲染 | 部分 | 调参面板越过画质服务；预算失配、渲染用例归类不全 |
| TRAINING | `TrainingRange3D`→只读BlueprintRegistry→共用Player3D→训练会话统计 | **测试功能1.0已完成，可独立启动与验收** | 后续伤害分析、靶标编辑和自动压测另升功能版本 |
| ASSET | XLSX台账→生产源/转移账本→GLB→PackedScene→正式场景 | 有生产标准，验收闭环不足 | 418条登记中214条单文件哈希不匹配；需按批次核对来源 |
| TOOLING | tests/verification、脚本、src/testing→日志与退出码 | 不足 | 无统一运行前存档隔离；错误日志可能退出0；文档语义未自动门禁 |

## 2. 功能追溯表

“设计”指已有主设计入口，完整性另列。“历史定位”不等于本次重新通过；记录缺失必须补实证，不能倒填虚构开发过程。

| 功能ID | 功能 | 主设计 | 正式代码/数据入口 | 验收入口（tests/verification） | 契约与记录现状 |
|---|---|---|---|---|---|
| PLAYER-STATE | 八态、移动、受击、冲刺 | [03](03_技术施工_玩家与操作.md) | `src/player3d/Player3D.gd`、`states/` | `verify_player3d_animation_flow` | 有设计与历史；原因码/回放待补 |
| PLAYER-INTERACT | 门、灯、设施统一仲裁 | [03](03_技术施工_玩家与操作.md) | `PlayerInteractionController3D`→Tower | `verify_unified_player_interaction_flow` | 实现存在；原完成度“未统一”过期 |
| PLAYER-LIGHT | 手电、电池、光照/可见性 | [03](03_技术施工_玩家与操作.md)、[15.1](15.1_技术施工_电力系统.md) | `PlayerFlashlight3D/PlayerVision3D`→ItemUseHandler | `verify_3d_flashlight_charge_flow` | 当前链已纳入电力系统；基地供电表现仍待完善 |
| WEAPON-COMBAT | 远程/近战、命中与反馈 | [04](04_技术施工_战斗与局内成长.md) | `src/combat3d/`、`src/player3d/melee/` | `verify_3d_melee_combat_flow`、`verify_3d_melee_feedback_flow` | 有设计与历史；反馈验收未通过 |
| WEAPON-OWNERSHIP | 完整武器实例转移 | [04](04_技术施工_战斗与局内成长.md)、[09](09_技术施工_存档结算与复活.md) | `WeaponInstance`→`EquipmentTransactionService` | `verify_equipment_transaction_service`、`verify_weapon_instance_contract_matrix` | 可用替身验证；全局所有权仍待补 |
| INVENTORY-SLOTS | 背包、保险、快捷物品、扩容 | [04](04_技术施工_战斗与局内成长.md) | `InventoryModule/InsuranceModule`→Dungeon→InventoryUI | `verify_backpack_equipment_flow`、`verify_finite_ammo_flow` | 有规范与历史；场景编排分散 |
| FATE-RULES | 48运行塔罗、78目标牌组、三作用域 | [14](14_技术施工_命运塔罗牌组.md)、[04](04_技术施工_战斗与局内成长.md) | `FateCardPresets/FateCardEngine/TarotFateCatalog` | `verify_tarot_fate_runtime`、`verify_celestial_fate_scope_flow` | 有设计与历史；新增30张未施工 |
| WORLD-PLAN | 纯数据楼层/房间图 | [05](05_技术施工_关卡生成与爬楼.md) | `FloorPlanGenerator/RoomGraphRuntime` | `verify_floor_plan_generator`、`verify_room_graph_persistence_services` | 可独立；缺领域版本与完整门事务 |
| WORLD-GATE | 到达门、Boss门、楼梯 | [05](05_技术施工_关卡生成与爬楼.md)、[09](09_技术施工_存档结算与复活.md) | `TowerDescent3D`→FloorBundle→RoomDoor3D | `verify_arrival_gate_floor_bundle_flow` | 当前契约与工程一致：内存生成/验证完成后开门，不等待快照写盘；未保存状态可在重启后丢失 |
| WORLD-SEGMENT | 隔离间、区段卸载、永久遗失 | [05](05_技术施工_关卡生成与爬楼.md) | `TowerDescent3D._finalize_airlock_commit` | `verify_three_segment_tower_generation_flow` | 当前契约与工程一致：前门交互时先关闭后侧路线并卸载旧段；无独立提交回执或跨重启保证 |
| WORLD-LOOT | 搜索、清房钥匙、掉落与拾取 | [04](04_技术施工_战斗与局内成长.md)、[05](05_技术施工_关卡生成与爬楼.md) | `LootModule/ItemRegistry/GroundLootPickup3D` | `verify_requested_experience_upgrade_flow` | 有设计/历史；批量数值仍手工投影 |
| ENEMY-AI | 感知、导航、攻击、光照 | [06A](06A_怪物AI系统完整设计_评审稿.md)、[06](06_技术施工_怪物精英与Boss.md) | `Enemy3D/MonsterAIManager/MonsterVisionSystem3D` | `verify_monster_ai_system_complete`、`verify_enemy_illumination_states` | 有较完整规范；真实错误日志仍需严查 |
| ELITE-ROSTER | 唯一名册、预约、跨局成长 | [06](06_技术施工_怪物精英与Boss.md) | `EliteContentCatalog/EliteRosterService`→BaseData | `verify_unique_elite_roster_flow`、`verify_first_elite_growth_flow` | 12名册/1投放；其余11为design_only |
| BOSS-STAGES | 95/90/85 Boss及下行权限 | [06](06_技术施工_怪物精英与Boss.md) | `BossContentCatalog`→Enemy3D→Tower | `verify_unique_boss_content_flow` | 有规范；钥匙实体契约未完全对齐 |
| BASE-FACILITY | 设施入口、禁射、常驻和恢复 | [07](07_技术施工_基地设施.md) | `BaseFacilityCatalog/Service`→BaseFacility3D | `verify_base_facility_framework`、`verify_tower_base_facility_persistent_flow` | 设计与历史可定位；资产专项部分失败 |
| BASE-SHOP | 基地购买、出售、保险柜转移 | [07](07_技术施工_基地设施.md)、[09](09_技术施工_存档结算与复活.md) | BaseManager事务→BaseShopService→ItemRegistry | `verify_base_shop_save_flow`、`verify_tower_facility_inventory_binding`、`verify_extraction_points_spend_transaction` | 商店已有幂等/回滚；普通资源扣款已在写盘失败和revision冲突时回滚/拒绝，工坊组合事务仍未收口 |
| BASE-WORKSHOP | 蓝图升级与手电模块 | [07.1](07.1_玩法系统_枪械工坊.md)、[07](07_技术施工_基地设施.md) | `src/ui/WorkshopMenu.gd`→BaseManager | `verify_base_facility_framework`（相邻覆盖） | **开发中**：独立契约已建立；升级扣款与Tier仍需合并为原子事务并补故障专项 |
| RUN-MERCHANT | 局内商人、消费与回退 | [04.1](04.1_玩法系统_局内商人.md)、[04](04_技术施工_战斗与局内成长.md) | `src/ui/MerchantUI.gd`→GameManager/Inventory | `verify_full_3d_game_flow`（综合） | **开发中**：现行链已记录；会话、货币、背包、撤离条件和快照事务待收口 |
| SAVE-PROFILE | 总档封套、校验、迁移与复位 | [09](09_技术施工_存档结算与复活.md) | `BaseData/ProfileSaveService/AtomicJsonStore` | `verify_pause_game_save_reset_flow`、`verify_base_shop_save_flow`、`verify_extraction_points_spend_transaction` | 普通资源扣款失败回滚已有专项；文件底层失败/备份链仍需补完整故障矩阵 |
| SAVE-RUN | 行动自动存档、重载恢复 | [09](09_技术施工_存档结算与复活.md) | `RunPersistenceService`→Dungeon/Tower快照 | `verify_runtime_autosave_flow`、`verify_tower_runtime_restart_restore` | 实现存在；核心套件未包含这两项，本审计另行执行 |
| RUN-SETTLE | 撤离、死亡、保险返还 | [09](09_技术施工_存档结算与复活.md) | DeathSettlementModule→Dungeon/Tower→BaseManager | `verify_tower_extraction_return_flow` | 正常路径有；一组写盘尚未成为一次结算事务 |
| RUN-REVIVE | 复活策略 | [09](09_技术施工_存档结算与复活.md) | 目标`RevivalPolicy`，当前不存在 | 待建立空策略/次数/失败测试 | 仅目标；禁止将返基地当成复活完成 |
| NARRATIVE-TRIGGER | 剧情条件、事件队列与跨局历史 | [08](08_技术施工_剧情触发.md) | 当前ThemedNPC3D/MapFateTriggers；目标NarrativeTriggerService不存在 | 待建立三条切片 | 设计框架有，独立实现和开发证据缺失 |
| TIME-DAYNIGHT | 权威时间、日夜与能源恢复时间输入 | [15](15_技术施工_时间日夜与基地能源.md) | WorldTimeDomain/GameTimeManager→太阳/HUD | `verify_main_entry_realtime_sun_flow` | 已与电力玩法拆分；统一数据配置仍待完善 |
| POWER-SYSTEM | 基地电力、手电电力、恢复舱与未来基地负载 | [15.1](15.1_技术施工_电力系统.md) | BaseEnergyService/BaseManager；PlayerFlashlight3D/ItemUseHandler | `verify_3d_flashlight_charge_flow`、`verify_base_overhaul_flow` | **开发中**：现有两条能源链已记录；基地灯光/设施用电待接入 |
| ENTRY-AVATAR | 启动分流、外观、衣柜、脱困 | [16](16_技术施工_主页面与角色换装.md)、[16.1](16.1_角色美术制作与动作导入流程.md) | GameEntryFlow→Tower/MainEntryScreen3D→AvatarCustomizationPersistence | `verify_game_entry_flow`、`verify_avatar_return_persistence_flow` | 有设计/历史；调参面板不应混入角色契约 |
| UI-HUD | HUD、地图与模态输入 | [04](04_技术施工_战斗与局内成长.md) | HUDPresenter3D/DungeonMinimap3D/InventoryUI | `verify_hud_presenter_3d`、`verify_tactical_inventory_minimap_flow` | Presenter可独立；其他UI仍直接读写多域 |
| VFX-POOL | Prefab注册、借出、回收 | [14.6](14.6_特效系统与制作规范.md) | VfxPool3D/CombatEffectPool3D→战斗调用者 | `verify_3d_melee_feedback_flow`（旧池断言） | 双池迁移未完成、信号回收错误；新池缺专用回收测试 |
| AUDIO-MUSIC | 音效和场景音乐切换 | [10](10_资产与内容规范.md)、[14.8](14.8_音乐系统与配乐资产.md) | AudioManager/MusicCatalog/MusicManager/MusicTrigger | `verify_music_system`、`verify_requested_experience_upgrade_flow` | 有规范/音乐修复历史；音效与新VFX接入需联验 |
| GRAPHICS-POSTFX | 画面设置、调参、屏幕后处理 | [13](13_技术施工_性能优化与热管理.md)（上级） | GraphicsSettingsManager/PostfxOverlay/FlashlightColorTweaker | `verify_graphics_settings_ui_flow`、`verify_postfx_overlay_runtime`（仅脚本，缺tscn） | 新后处理缺独立设计和日志关联；7/9项口径失配 |
| PERFORMANCE-RUNTIME | 帧预算、流送、长测与退出 | [13](13_技术施工_性能优化与热管理.md)、[11](11_测试与发布.md) | RuntimePerformanceManager/GameplaySpatialRegistry3D | `verify_3d_performance_budget`、`verify_performance_runtime_complete` | 有规范/历史；节点预算失败，未执行本次真实GPU/长测 |
| TRAINING-RANGE | 独立靶场与武器预览 | [11.1](11.1_测试功能_独立训练场.md) | `src/training3d/TrainingRange3D.gd` | `verify_training_range_3d_flow`、`verify_training_range_3d_visual` | **功能版本1.0已完成**：18枪架、59组合、三类靶标、重置/退出、暂停及BaseData隔离已有独立契约 |
| ASSET-PIPELINE | 模型、组件、导入、台账与放置 | [10](10_资产与内容规范.md)、[16.1](16.1_角色美术制作与动作导入流程.md) | source/art→tools/asset_pipeline→assets/art→XLSX | `scripts/check_asset_registry.py`、资产专项 | 有标准和批次记录；214项哈希漂移未签署 |

## 3. 开发记录定位

当前全部功能共同关联[本次审计记录](development/2026-09-12_documentation_audit.md)，它只记录审计，不冒充功能开发史。既有功能的原始开发记录按下列位置回溯：

- PLAYER：[玩家历史](development/history/03_玩家与操作_历史记录.md)。
- WEAPON/INVENTORY/FATE/UI：[战斗历史](development/history/04_战斗与局内成长_历史记录.md)。
- ENEMY/ELITE/BOSS：[怪物历史](development/history/06_怪物精英与Boss_历史记录.md)、[精英推送摘要](development/history/14.5_推送更新摘要_2026-08-27.md)。
- BASE：[基地历史](development/history/07_基地设施_历史记录.md)。
- PERFORMANCE/TOOLING：[性能历史](development/history/13_性能优化与热管理_历史记录.md)、[测试历史](development/history/11_测试与发布_历史记录.md)。
- AUDIO/VFX：[音乐修复](development/history/14.8_音乐系统与配乐资产_历史记录.md)、[特效快照](development/history/14.6_特效系统与制作规范_历史记录.md)。
- WORLD/SAVE/TIME/ENTRY/ASSET：[版本开发日志](development/CHANGELOG.md)及[场景成品化历史](development/history/17_天台至98层成品化验收.md)。这些尚未逐条绑定功能ID，属于追溯债务。
- NARRATIVE/RUN-REVIVE/GRAPHICS-POSTFX仍缺功能级独立契约；RUN-MERCHANT与BASE-WORKSHOP已建立开发中文档，TRAINING-RANGE功能1.0已完成。开发中功能不得因文档已建立而提前标成实现完成。

## 4. 允许的独立开发方式

优先将楼层计划、房间图查询、装备交换、HUD映射、时间/能源计算作为稳定边界，使用输入快照和替身开发。跨模块输入使用内容ID、实例ID、布局ID、事务ID和版本化快照相连；UI与表现订阅结果，不成为领域事实源。

塔楼生命周期、统一结算、工坊交易、剧情、VFX迁移暂不能按“已完全解耦”并行改写。先冻结命令、数据所有者与失败语义，再做逐链路提取。每次提取同时保留正常流程与故障恢复验收，不做一次性大重写。
