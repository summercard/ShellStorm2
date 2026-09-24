# 第五项：按正式游戏对齐技术施工契约

口径更正（2026-09-24）：本记录交付的是施工页中的当前接口/事实/差距，不是完整的独立玩法设计。功能设计源随后补于[设计目录](../design/README.md)，层级纠正见[独立记录](2026-09-24_design_source_correction.md)。原测试与差距证据不变。

日期：2026-09-24。工程版本：`0.1.0`。范围：功能关系计划 D0–D3 的主线文档补齐及 D4 遗留登记；本次**不改玩法代码、不升级游戏版本、不签署真实表现验收**。涉及功能：`INVENTORY-SLOTS`、`WEAPON-COMBAT`、`ENEMY-AI`、`BASE-SHOP`、`SAVE-PROFILE`、`DIALOGUE-UI`、`UI-HUD`、`TIME-DAYNIGHT`、`GRAPHICS-POSTFX`，并与既有 `REWARD-SERVICE/RUN-MERCHANT` 契约交叉核对。

## 判定原则

1. 正式入口、运行代码和当前内容定义已经具备的行为，写成“当前实现事实”；文档没有的补入主设计。
2. 原文有设计、游戏尚未做且不偏离当前方向的，保留为“未实现目标”，不以代码现状删除。
3. 原文与正式游戏实际行为相冲突的实现描述，按游戏修正；历史设计沿革和旧测试保留来源，但不冒充当前版本。
4. 文档核对只证明契约可追溯；通过逻辑专项不能代签真实渲染、设备性能或未覆盖的故障分支。

## 已核对并回填

| 主设计 | 正式证据 | 本次对齐与剩余风险 |
|---|---|---|
| 04 §9.5 背包容量 | `InventoryModule.resize_capacity_collect_overflow()`、`Dungeon3D._equip_backpack_from_inventory()` / `_drop_backpack_capacity_overflow()` | 保留“逐件落地失败整笔回滚”的用户目标，同时标明当前只有房间前置检查、落地结果未逐项收集；正常溢出专项不能证明失败原子性。 |
| 04 §10 战斗命中 | `Projectile3D.configure()`、`hit_confirmed`、`PlayerMeleeCombat3D.hit_resolved`、目标 `take_damage` | 将统一 DamageContext 标为未实现目标；远程和近战现行信号/位置参数分别列明。 |
| 06 §7.8/§7.10 敌人 | `Enemy3D.killed(enemy,get_enemy_data())`、`Dungeon3D._on_enemy_killed()` | 把“没有独立AI管理器”的旧事实改为已接入 Manager/Vision；补死亡→奖励 `grants[]`→地面及波次/清房链，说明 `loot` 信号参数名不代表已落地奖励。 |
| 07 §5.6、09 §5.6 基地贩卖机 | `BaseShopService`、`BaseManager` 四类购买/出售入口、`ItemRegistry`、99F设施映射 | 99F正式SUPPLY24H与旧BaseWorld长方体分开；补七类货架、内容ID/实例ID、128条完成日志、中文 `reason` 及无统一成交事件。商店各入口 revision 冲突域回滚仍待专项。 |
| 09 §3.3/§4 长期档 | `BaseManager.save_base()`、`ProfileSaveService`、`AtomicJsonStore` | 明确 BaseManager 是磁盘唯一写者；现行为单封套+行动快照，多文件根清单仍是目标；无通用保存结果事件。注册表 `SAVE-PROFILE` Owner 同步为 BaseManager。 |
| 18 对话 | `DialogueUI.gd`、`CharacterBark3D.gd`、`SpeechBubble3D.gd`、`NarrativeAdapter3D._ui_instruction()` | 原六处冲突按正式单路播放/无参命令/整场跳过/5字段普通Label/无队列字段收敛；另纠正“底栏/气泡共用同一schema和carrier”的旧推断。立绘、语音等方向一致扩展标未实现；抢占旧run无 `aborted`、适配器未检查空run、无跳过键。 |
| 04 §20.1 HUD | `HUDPresenter3D.gd`、`Dungeon3D.gd` | 只把武器栏投影认作独立 Presenter，整HUD仍由场景/其他UI协作。 |
| 15 时间 | `WorldTimeDomain.gd`、`GameTimeManager.gd` | 明确游戏秒、20分钟/日、事件/命令/快照、10秒落档与失败边界；注册表 `TIME-DAYNIGHT` Owner 同步为 GameTimeManager，纯算法仍由 WorldTimeDomain 负责。 |
| 新13.1 画质与后处理 | `GraphicsSettingsManager.gd`、`PostfxOverlay.gd`、`FlashlightColorTweaker.gd`、`project.godot`、`Player3D.tscn` | 首次补独立主设计：正式cfg、内存调试覆盖、Shader颗粒/色相、面板JSON持久化四层分开；`set_value(true)` 不证明写盘成功，调参写入也无结果契约。真实渲染/UI污染/设备预算未签。 |

跟踪表逐行更新了上述功能；[功能关系计划 §6](../FEATURE_RELATIONSHIP_PLAN.md)记录 D0–D4 的剩余批次。其余功能没有因本次文档编辑而自动标为“已核对”或“已验收”。

## 验证记录

| 验证 | 结果 | 边界 |
|---|---|---|
| `bash scripts/run_verification_suite.sh batch verify_dialogue_ui_flow verify_postfx_overlay_runtime verify_postfx_autopersist verify_graphics_settings_ui_flow verify_base_shop_save_flow verify_runtime_autosave_flow verify_reward_ground_handoff` | 退出码0，7/7通过，runner按场景隔离 `user://` | 基地商店故意制造损坏候选和旧revision，奖励故意制造错误Spec/无房间，日志中的对应 warning/error 属预期故障注入；无非预期脚本错误。 |
| `bash scripts/run_verification_suite.sh batch verify_backpack_equipment_flow verify_3d_melee_combat_flow verify_hud_presenter_3d verify_monster_ai_system_complete` | 退出码0，4/4通过，runner按场景隔离 `user://` | 证明正常缩容、近战、武器HUD投影与AI管理器专项；**未覆盖**背包逐件落地失败或统一命中schema。 |
| `python3 scripts/check_documentation_contracts.py`、`python3 scripts/check_feature_traceability.py`、`python3 scripts/check_asset_runtime_naming.py`、`git diff --check` | 均退出码0；文档125、功能37、追溯无断链 | 资产命名门禁仍报告存量欠账文件289/目录13/备份1，本轮无新增；静态通过不代替语义审查。 |
| 真实渲染、目标GPU、移动端、长测 | **未执行** | 不以 headless 状态/uniform 断言代签视觉或性能。 |

本次没有运行新的代码修复；库存缩容、商店 revision、对话抢占回执、调参保存结果属于**发现并记录的工程缺口**，不在文档变更中虚构已修复。
