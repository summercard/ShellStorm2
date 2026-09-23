# v0.1 功能关系与解耦跟踪表

工程版本：`0.1.0`；表格修订：r2；核对日期：2026-09-23；新拉取基线：`622d6c4a`。执行方法见[计划](FEATURE_RELATIONSHIP_PLAN.md)，功能的权威 Owner/设计/记录/验收路径见[模块索引](MODULE_INDEX.md)与[功能注册表](feature_registry.json)。本表是跟踪视图，状态栏不覆盖注册表的实现状态。

“局部独立”表示规则或事务可替身验证，正式场景仍有编排依赖；“链路清楚”表示交接可追溯但未达到独立维护；“关系待收口”表示写入、失败或场景生命周期仍混合。“已核对”仅指本轮有代码/注册表/验收证据，不能代替完整语义审查。跟进状态使用“待处理 / 核对中 / 待验收 / 已关闭 / 持续维护”，关闭时在开发记录中附证据并更新本表。

| FeatureID | 上游 → Owner → 下游/交接 | 解耦跟踪 | 设计文档与事实状态 | 待补的关系/文档工作 | 优先级 | 跟进状态 |
|---|---|---|---|---|---|---|
| PLAYER-STATE | 输入/伤害 → Player3D状态 → Avatar/HUD/存档 | 局部独立 | 03主设计已定位；原因码待补 | 写清状态变化原因、动作采样与快照字段 | P2 | 待处理 |
| PLAYER-INTERACT | 玩家输入/空间查询 → InteractionController → 门/设施命令 | 链路清楚 | 03主设计已定位；正式仲裁已实装 | 列设施拒绝码与 Tower 适配边界 | P1 | 待处理 |
| PLAYER-LIGHT | 物品使用 → Flashlight/Vision → 可见性/电量UI | 局部独立 | 03/15.1已定位；基地供电目标另列 | 对齐电池ID、耗能单位、存档与基地恢复交接 | P2 | 待处理 |
| WEAPON-COMBAT | 玩家状态/武器实例 → Combat3D → 敌人/伤害事件/VFX | 关系待收口 | 04已定位；统一命中上下文待补 | 定义命中事件schema与视觉反馈责任边界 | P1 | 待处理 |
| WEAPON-OWNERSHIP | 背包/保险 → 装备事务 → 玩家槽/结算 | 局部独立 | 04/09已定位；全局唯一归属待补 | 统一实例ID、转移幂等键和节点生命周期 | P1 | 待处理 |
| INVENTORY-SLOTS | 奖励/商店 → Inventory/Insurance → 装备/快捷栏/UI | 关系待收口 | 04已定位；场景编排分散 | 写清格位唯一写者、掉落/卸装回滚与UI只读边界 | P1 | 待处理 |
| FATE-RULES | 牌组ID/选择 → FateCardEngine → 玩家/武器/世界 | 局部独立 | 14/04已定位；48运行与78目标已区分 | 补世界作用域与Dungeon适配命令及失败结果 | P2 | 待处理 |
| WORLD-PLAN | 关卡内容 → FloorPlan/RoomGraph → Dungeon/Tower装配 | 局部独立 | 05/05.1已定位；生成和装配分层已记 | 统一布局ID、计划版本、加载失败交接 | P1 | 待处理 |
| WORLD-ENTRY | 基地设施ID → 菜单/读取页 → 远征关卡/runtime_map_id | 链路清楚 | 05/07/09已定位；正式入口已完成 | 持续核对退出/重新上线/存档隔离，不新增平行入口 | P1 | 持续维护 |
| WORLD-GATE | 塔楼楼层计划 → 到达/Boss门 → 快照/下一层 | 关系待收口 | 05/09保留用户设计；当前隐藏路线 | 保留失败证据，重开爬塔前补门事务与权限ID | 低 | 待处理 |
| WORLD-SEGMENT | 隔离门 → Tower提交/卸载 → SAVE-RUN恢复 | 关系待收口 | 05/09保留用户设计；当前隐藏路线 | 补提交ID、重启重放和永久遗失规则对照 | 低 | 待处理 |
| WORLD-LOOT | 清房/搜索/剧情`scene.spawn_item` → RewardCoordinator → 房间地面物/背包 | 关系待收口 | 04/05/08已定位；剧情落地入口已接通，旧item桥仍在 | 明确房间归属、地面实例ID与重启恢复；迁移旧字典桥 | P1 | 待处理 |
| REWARD-SERVICE | Spec/事件ID/剧情物品ID → RewardService/Coordinator → 三类发放口 | 局部独立 | 04 §22/05/01及08已定位；剧情固定物品解析已接入 | 令场景发放口唯一，登记废弃池与失败重试 | P1 | 待处理 |
| ENEMY-AI | 房间/玩家/光照 → Enemy3D/AI Manager → 攻击/死亡 | 关系待收口 | 06A/06已定位；物种行为集中 | 标明感知快照、死亡事件、流送/光照依赖 | P1 | 待处理 |
| ELITE-ROSTER | 内容名册 → EliteRosterService → BaseManager档案 | 局部独立 | 06已定位；1/12投放为当前事实 | 补预约/跨局成长事件与未投放内容状态 | P2 | 待处理 |
| BOSS-STAGES | Boss目录 → Enemy3D阶段 → 塔楼门权限 | 关系待收口 | 06已定位；实体钥匙与计数权限不符 | 分列设计钥匙ID和当前授权实现，待目标裁决 | 低 | 待处理 |
| BASE-FACILITY | 设施目录 → FacilityService → 交互/UI/持久化 | 链路清楚 | 07已定位；旧布局验收待裁决 | 建立设施ID→交互盒→命令→存档字段对照 | P1 | 待处理 |
| BASE-SHOP | 货品/余额 → BaseManager事务 → 库存/存档 | 局部独立 | 07/09已定位；扣款回滚已核对 | 写清货品ID、revision、成功事件和UI拒绝结果 | P1 | 待处理 |
| BASE-WORKSHOP | 蓝图ID/Tier → BaseManager/UpgradeService → BaseData/UI | 局部独立 | 07.1/07已定位；核心事务已核对 | 成本表外置与展示层读取契约 | P2 | 待处理 |
| RUN-MERCHANT | 房间商人 → MerchantUI/GameManager → 余额/背包/存档 | 关系待收口 | 04.1独立设计已有；事务契约待补 | 定义会话Owner、货币/库存命令与独立失败验收 | P1 | 待处理 |
| SAVE-PROFILE | 结算/剧情完成等领域提交 → BaseManager/ProfileSaveService/AtomicStore → BaseData | 局部独立 | 09已定位；`narrative_history`已由BaseManager独占写入并在失败时回滚 | 明确多写者revision、备份恢复与领域通知；剧情完成原因值保持一致 | P1 | 待处理 |
| SAVE-RUN | 战局状态/房间地面物 → RunPersistenceService → 快照/重载场景 | 局部独立 | 09已定位；正常恢复已核对，剧情地面枪仍不进快照 | 区分远征/隐藏塔楼的runtime_map_id；裁决并验收未拾取剧情物的跨重启恢复 | P1 | 待处理 |
| RUN-SETTLE | 撤离/死亡 → BaseManager结算 → 长期档/基地 | 局部独立 | 09已定位；事务验收已核对 | 对齐奖励/保险/档案提交次序及结果事件 | P1 | 待处理 |
| RUN-REVIVE | 死亡 → RevivalPolicy空策略 → no_revival_source | 局部独立 | 09只有当前空策略；目标设计待补 | 保留空策略事实，复活来源/次数/成本待设计 | P2 | 待处理 |
| NARRATIVE-TRIGGER | 场景事件/位置 → Director绑定Adapter → 对话/奖励/房间地面物；完整收口→BaseManager历史 | 局部独立 | 08主设计已定位；`run`跨局历史、`scene.spawn_item`已实装；单独专项通过，批次顺序污染待修 | 核对`duration/flow.end/skip`与中断不写档；补通用条件、地面物存档和批次独立验收 | P1 | 核对中 |
| DIALOGUE-UI | 剧情/脚本命令 → DialogueUI → 底栏/气泡/推进结果 | 局部独立 | 18独立设计已定位；6处契约差异 | 逐项按正式行为核对队列、跳过、BBCode、带参命令 | P1 | 待处理 |
| TIME-DAYNIGHT | 权威时间 → WorldTimeDomain → 太阳/HUD/能源 | 局部独立 | 15已定位；太阳/入口验收红 | 补时间单位、配置来源和表现订阅边界 | P1 | 待处理 |
| POWER-SYSTEM | 基地时间/电源 + 手电物品 → 两能源域 → 设施/光照 | 关系待收口 | 15.1独立设计已有；系统开发中 | 定义基地负载事件、恢复舱跨域转换与存档字段 | P2 | 待处理 |
| ENTRY-AVATAR | 新档/基地快照/战局快照 → GameEntryFlow/Tower → 98F开场或99F基地/玩家装配 | 关系待收口 | 16/16.1及09已定位；新档与天台下线判据已修，展示合同仍红 | 明确开场剧情刷枪与玩家卸枪分工；核对未拾取地面枪的存档缺口及展示相机 | P1 | 核对中 |
| UI-HUD | 玩家/战局快照 → HUDPresenter → HUD/地图/模态 | 局部独立 | 04已定位；其他UI仍跨域 | 定义只读快照、模态命令与直接写域禁线 | P1 | 待处理 |
| VFX-POOL | 战斗效果ID → VfxPool3D → Prefab/回收 | 局部独立 | 14.6已定位；旧池兼容链仍在 | 清点explosion旧入口、统一借还事件及资源版本 | P2 | 待处理 |
| AUDIO-MUSIC | 事件/场景ID → Audio/Music Manager → 声音总线 | 局部独立 | 10/14.8已定位；两种生命周期应分开 | 补事件ID→音效/音乐资产映射及静音/切场失败语义 | P2 | 待处理 |
| GRAPHICS-POSTFX | 画质设置 → GraphicsSettingsManager/PostfxOverlay → 画面 | 关系待收口 | **缺独立主设计**；13仅上级规范 | 新建主题契约或13独立章节；统一参数schema、Owner、重置与真实渲染验收 | P1 | 待处理 |
| PERFORMANCE-RUNTIME | 场景/设置指标 → RuntimePerformanceManager → 预算/诊断 | 链路清楚 | 13/11已定位；当前预算红 | 对齐真实GPU、节点、尖峰和长测证据口径 | P1 | 待处理 |
| TRAINING-RANGE | 只读蓝图 → TrainingRange3D → 会话统计/退出 | 独立 | 11.1独立设计完整；1.0已完成 | 新增能力另立修订，不将训练状态写入正式档 | 维护 | 持续维护 |
| ASSET-PIPELINE | 设计/Blend → 9域账本/GLB/Prefab → 正式场景 | 局部独立 | 10/10.1/16.1及账本说明已定位；拉取后410/0已核对 | 持续记录共享资产单账、稳定路径、源/运行版对应 | P2 | 待处理 |
| ASSET-ROOFTOP | Blender组件目录 → QA → 可选Godot导入 | 源端独立 | 独立组件契约已定位；未正式导入 | 导入时补运行AssetID、Prefab映射和真实渲染 | P2 | 待处理 |

工具链属于模块级横向能力，不占用第 38 个 FeatureID：功能注册/验证清单 → 隔离 Runner 与静态检查 → 退出码与证据。新拉取后发现 Runner 仅按批次隔离用户目录，`verify_narrative_timeline`写入跨局剧情历史后会污染紧接的`verify_opening_script_runtime`；单独运行开场105项通过，5场景批次为4通过/1失败。应保证场景间长期档独立或显式复位前置条件，并加入反向验收。现有边界门禁覆盖有限，需逐步扩展；视觉、设备与长测未执行时明确记为未执行。主规范见[测试与发布](11_测试与发布.md)和[文档标准](../DOCUMENTATION_STANDARD.md)。

## 更新一行时填写的证据

在本表对应行的“待补”处移除任务前，应在主设计和开发记录中留下：正式入口、状态写入者、命令/查询/事件及ID/schema、失败结果、验证命令与退出码。若只修文档，不改变游戏，也要写明代码/资产核对位置和未运行项。此表不把“完整解耦”作为统一关闭条件。
