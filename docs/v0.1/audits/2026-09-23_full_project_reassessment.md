# ShellStorm2 全项目完整复评（2026-09-23）

> 复评基线：Git `a419bc6a`，工程版本 `0.1.0`（以 `project.godot` 为准）。
>
> 复评范围：文档与功能追溯、Godot 代码/场景、资产源与运行资产、九本资产分账本、项目 Skill、验证注册与当前 headless 实跑、Git 跟踪与本地生成目录。
>
> 复评原则：以当前工作区实测为准；历史通过不等于本次通过；代码现状不自动升级为用户设计；本报告不修改玩法、资产内容或验收阈值。

> 后续事实更新（不改写本报告原时点数据）：2026-09-23 新拉取 `622d6c4a` 后资产账本复核为 410 项、9 本分账本、完整性问题 0、拆账漂移 0；功能解耦和设计文档补全按[功能关系计划](../FEATURE_RELATIONSHIP_PLAN.md)与[跟踪表](../FEATURE_RELATIONSHIP_MATRIX.md)继续。下文 426/230 只代表本次复评时点。

## 1. 总结论

P0/P1/P2 修复后，项目的**治理骨架已明显完善**：已建立 19 个工程模块、37 个可机器追溯功能、9 个独立资产账本、156 个唯一归属验收场景；文档、功能追溯、验证注册、跨域边界和媒体拆域门禁全部通过。

但项目仍不能判定为“所有功能均可独立维护”或“当前可发布”：37 个功能中只有 2 个状态为 `complete`，30 个仍为 `partial`；P0-1～3 后 headless core 129 项中仍有 15 项失败；资产账本 426 条中仍报告 230 项问题；视觉、目标 GPU、移动端和长时稳定性本轮未执行。

| 原始问题 | 当前结论 | 等级 | 相比 2026-09-22 |
|---|---|---:|---|
| 功能解耦与数据串联 | 边界比旧审计清楚，已阻止已知跨域私有写入；主流程大体串通，但大型场景编排器、24 个 Autoload、运行时奖励类型错误和隐藏塔楼流程仍阻止全面独立维护 | 黄/红 | P1 关闭奖励解析、工坊、结算、档案和换装事务；大型编排器未解决 |
| 资产拆分与制成链路 | 9 个资产域均有独立账本和匹配 Skill；媒体拆域完成，但全账本仍有 230 项异常且 9/9 owner 均待分配 | 红 | 7 本增至 9 本；媒体错配关闭；问题 231→230 |
| 设计、日志与规范 | 37/37 已具 Owner、设计、开发记录和验收映射；但并非 37 项都有独立完整设计/独立开发日志，且只有 2 项完成 | 黄/绿 | 精确机器追溯从 15/37 提升到 37/37 |
| 验收机制 | 156/156 场景均唯一注册，隔离与静态门禁有效；P0-1～3 后 core 114/129 非失败、15 失败，不能作为发布绿线 | 红 | 漏登 47 项已清零；复评基线20个失败降至15个；core 仍红 |
| 命名、目录与中心文档 | 中心入口和新增命名门禁有效；历史运行资产债务、`_scratch`/`output` 混用和用户数据入库仍存在 | 黄 | 新增债务受阻；历史债务未清零 |
| 精简与整理 | P1 已移除 790 个跟踪文件；当前另有 5 个高置信度跟踪清理项、约 17,611 个本地生成/忽略文件可清理，1,547 个跟踪候选需复核 | 黄/绿 | 大批重复快照已清理，无未跟踪文件回潮 |

总体判断：**工程治理成熟度已由“框架存在但断链”提升到“追溯和门禁成体系”，运行与资产健康度仍为红线。** 下一步应优先恢复剩余 15 个 core 失败和 230 项资产账本异常，而不是继续新增平行框架。

## 2. 本次采用的工程原则

依据 `docs/README.md`、`DOCUMENTATION_STANDARD.md`、`MODULE_INDEX.md` 和各模块主设计，本次按以下条件判断：

| 原则 | 合格判据 | 当前结论 |
|---|---|---|
| 唯一状态所有者 | 每项状态有明确 owner，其他域通过命令/查询/事件访问 | 37 项均登记 owner，跨域静态门禁通过；场景编排器仍聚合过多责任 |
| 清晰契约 | 输入/输出、ID/schema、失败/回滚与正式接入明确 | 工坊、结算、换装、奖励解析较好；商人、复活、塔楼完整生命周期不足 |
| 分层与解耦 | 数据、领域规则、运行编排、场景适配、表现资产可替换 | 纯规则层较好；Tower/Dungeon/BaseManager/UI 仍跨层 |
| 设计先行 | 规则改变前有主设计与功能索引 | 37/37 有设计入口；部分仅指向上级设计，不能等同独立完整设计 |
| 可追溯 | FeatureID → owner → 设计 → 开发记录 → 验收 | 机器门禁 37/37 通过 |
| 独立验收 | 正常/失败路径可单独执行并记录退出码 | 注册完整；当前运行失败15项，视觉/硬件/长测未执行 |
| 资产稳定路径 | 运行路径不带版本号，源文件/账本记录版本 | 新增门禁通过；历史债务仍为 289 文件、13 目录、1 备份 |

## 3. 系统、玩法与游戏流程

### 3.1 规模与完成度

| 指标 | 当前值 | 结论 |
|---|---:|---|
| 工程模块 | 19 | 模块索引完整 |
| 功能条目 | 37 | 37/37 追溯链完整 |
| 功能状态 | complete 2；partial 30；development 3；contract_only 1；source_only 1 | 只有 `WORLD-ENTRY`、`TRAINING-RANGE` 完成 |
| 功能 owner | 33 个唯一 owner 覆盖 37 项 | 状态所有者已明确，不等于人员负责人 |
| GDScript | `src/` 195 个、约 69,427 行 | 规模已需要严格边界治理 |
| Autoload | 24 | 统一入口明确，但全局依赖面偏大 |
| 最大编排器 | Tower 6,153 行；Dungeon 5,684 行；DungeonRoom 3,203 行；Player 1,983 行；BaseManager 1,517 行 | 仍是独立维护的主要阻塞 |

### 3.2 19 个模块逐项结论

| 类别 | 模块 | 当前权威链路 | 独立维护 | 数据串联 | 主要剩余问题 |
|---|---|---|---:|---:|---|
| 核心角色 | PLAYER | `Player3D` → 状态类 → `PlayerAvatar3D`；交互控制器 → 门/设施 | 部分 | 通 | 玩家脚本仍聚合装备、背包、动作；手枪跑步/换弹/待机/开火握姿多项回归 |
| 战斗玩法 | WEAPON | 内容注册 → `WeaponInstance` → 装配树 → 模型/投射物/近战 | 部分 | 通 | 实例转移可独立验；统一命中和全局所有权仍未完全闭环 |
| 战斗玩法 | INVENTORY | 背包/保险格位 → `EquipmentTransactionService` → 玩家槽位 | 事务可独立，其余部分 | 通 | 场景仍编排快捷栏、掉落和部分生命周期 |
| 构筑玩法 | FATE | 牌组内容 → `FateCardEngine` → 武器/角色/世界持有者 | 部分 | 通 | 48 张运行卡与 78 张目标牌组并存；世界执行仍依赖 Dungeon |
| 流程/世界 | WORLD | 关卡设计源/计划 → 房间图 → Dungeon/Tower 或独立远征场景 | 计划/远征入口较独立；塔楼生命周期不足 | 主线通，隐藏塔楼不通 | `WORLD-ENTRY` 已完成；到达门/区段旧综合流程、镜头与流送仍失败 |
| 敌人玩法 | ENEMY | `Enemy3D` + AI Manager + 光照/空间查询 | 部分 | 通 | 物种行为仍集中；塔楼阳光判定综合回归失败 |
| 敌人玩法 | ELITE | 静态名册 → `EliteRosterService` → BaseManager 档案事务 | 部分 | 通 | 私有直写已关闭；12 名册仅 1 个正式投放 |
| Boss玩法 | BOSS | Boss 目录 → Enemy 阶段 → 下行权限 | 部分 | 有偏差 | 钥匙实体设计与计数式权限仍未完全一致 |
| 局外玩法 | BASE | 设施目录/服务 → `BaseManager`/规则服务 → BaseData → UI | 规则/工坊事务可独立，其余部分 | 基本通 | 基地布局、交互热区、旧设施/旧综合验收和节点预算均有失败 |
| 流程/存档 | SAVE | Run 快照 → Profile 封套 → Atomic store → BaseManager | 序列化和主要事务可独立 | 通 | 多写者/通知未统一；隐藏塔楼故障套件仍红 |
| 剧情系统 | NARRATIVE | 触发声明 → 时间轴 → Director/Adapter → 对话/系统命令 | 部分，核心链可独立验 | 通 | 核心时间轴通过；跨局历史、通用条件和全部内容投放未完成 |
| 世界规则 | TIME | `WorldTimeDomain` → Time Manager → 太阳/HUD/能源 | 算法可独立 | 部分通 | 入口太阳/展示页综合验收失败；配置仍偏代码常量 |
| 世界规则 | POWER | BaseEnergyService；PlayerFlashlight；恢复设施转换 | 两条链可独立验 | 通 | 基地灯光/设施负载尚未成为统一电网事件链 |
| 入口流程 | ENTRY | `GameEntryFlow` → 启动页/99F/远征 | 部分 | 主链通 | 主入口演出验收脚本编译失败，展示相机/太阳契约仍红 |
| 表现系统 | PRESENTATION | HUD Presenter、UI、VFX 池、Audio/Music、PostFX | HUD/音乐较独立，其余部分 | 基本通 | UI 仍跨域；旧 VFX 兼容链；PostFX 缺独立主设计 |
| 性能系统 | PERFORMANCE | 画质/后处理/运行时管理器 → 场景与渲染 | 部分 | 通 | UI/总节点/构建尖峰预算失败；真实 GPU 与长测未执行 |
| 工具玩法 | TRAINING | 独立训练场 → 只读注册表 → 共用 Player → 会话统计 | **是** | 通 | 19 架、67 组合 headless 通过；视觉用例本轮未执行 |
| 资产系统 | ASSET | 账本 → 原始源 → GLB/资源 → PackedScene → 运行引用 | 流程标准独立，健康度不足 | 有漂移 | 230 项账本问题、20 项拆账基线漂移、9 域均无人负责 |
| 工具链 | TOOLING | 验收清单 → 隔离工程 → 运行日志/退出码/静态门禁 | 部分 | 通 | 注册和隔离已修；当前 core 15 失败，视觉/硬件/长测未跑 |

直接结论：**TRAINING 是唯一达到完整模块级独立维护的模块；WORLD-ENTRY 是第二个完成的功能级入口，但 WORLD 模块整体仍不独立。** P1 已关闭已知 `BaseManager.data`/VFX 私有注册表等生产代码跨域访问，`check_domain_boundaries.py` 当前通过；这证明边界治理有效，但不能抵消大型编排器和运行回归。

### 3.3 关键数据流

| 数据流 | 当前状态 | 实测证据 | 结论 |
|---|---:|---|---|
| 冷启动/返航 → 99F → 远征菜单 → 读取页 → 独立关卡 | 通 | `verify_game_entry_flow`、`verify_central_expedition_hologram_facility`、`verify_expedition_level01_flow` 通过 | 当前正式主循环入口可用 |
| 关卡设计源 → 房间生成/内容透传 | 通 | 关卡设计源、99 测试关、FloorPlan/RoomGraph 均通过 | 纯计划层健康 |
| 战斗/搜索/剧情 → 统一奖励解析 | 部分通 | 奖励服务、有限弹药、体验升级通过；`_spawn_loot_items`延迟数组边界已修复 | 解析与发放桥已接通；相邻房流送仍使综合入口保持红色 |
| 背包/保险 → 装备实例交换 | 通 | 装备事务、武器矩阵、背包/保险专项通过 | P1 事务边界有效 |
| 工坊/资源扣款/结算 → 原子存档 | 通 | 工坊、撤离点、行动结算、死亡中断专项通过 | 失败回滚和幂等已建立 |
| 行动快照 → 重启恢复 | 通 | autosave 与 tower restart 通过 | 正常恢复链有效 |
| 隐藏塔楼到达门 → 区段提交/卸载 | 不通 | `verify_arrival_gate_floor_bundle_flow` 级联失败 | 当前设计保留，但不可作为可用流程 |
| 剧情触发 → 时间轴 → 多域适配/对话 | 通 | Narrative、Dialogue、Speech Bubble 通过 | 核心链可维护 |

## 4. 资产体系

### 4.1 九个资产域

所有域都有独立 XLSX 账本和可找到的项目 Skill；UI、音效、音乐已不再共用错误的模型导入流程。下表“问题”来自本次逐域 `full` 检查。

| 域 | 条目 | 独立账本 | Primary Skill | 独立链路 | 本次问题 | Owner |
|---|---:|---:|---|---:|---:|---|
| characters | 31 | 是 | `game-character-model-pipeline` | 高 | 18 SHA 漂移 | 待分配 |
| enemies | 12 | 是 | `game-character-model-pipeline` | 中高 | 4 SHA 漂移 | 待分配 |
| scenes | 236 | 是 | `scene-full-pipeline` | 高 | 138 SHA、17 路径、5 状态、1 缺 SHA、1 文件名，共 162 | 待分配 |
| props | 20 | 是 | `game-prop-model-pipeline` | 中高 | 7 路径、8 SHA，共 15 | 待分配 |
| weapons | 36 | 是 | `game-weapon-model-pipeline` | 高 | 19 SHA 漂移 | 待分配 |
| vfx | 17 | 是 | `vfx-combat-effect-authoring` | 中高 | 6 SHA 漂移 | 待分配 |
| ui | 17 | 是 | `ui-asset-pipeline` | 中 | 6 SHA 漂移 | 待分配 |
| audio | 48 | 是 | `audio-sfx-asset-pipeline` | 中高 | **0** | 待分配 |
| music | 9 | 是 | `music-asset-pipeline` | 中高 | **0** | 待分配 |
| **总计** | **426** | **9/9** | **9/9 可定位** | — | **230** | **0/9 已分配** |

### 4.2 资产门禁

| 门禁 | 退出码 | 当前结果 |
|---|---:|---|
| `check_media_asset_domains.py` | 0 | UI 17、音效 48、音乐 9；74 条媒体资产与 6 个注册验收入口完整 |
| `check_asset_registry.py --scope structure` | 1 | 5 个场景状态 `白盒组件` 不在合法枚举 |
| `check_asset_registry.py --scope full` | 1 | 426 条、230 项：199 SHA、24 路径、5 状态、1 缺 SHA、1 非规范文件名 |
| `verify_ledger_split.py` | 1 | 20 项非媒体漂移：2 丢失、4 新增、10 行内容变化、4 专表变化；敌人 3、场景 13、武器 2、VFX 2 |
| `check_asset_runtime_naming.py` | 0 | 无新增债务；历史债务仍为 289 文件、13 目录、1 备份，版本引用 GDScript 23、TSCN 93 |

资产结论：**账本/Skill/流程框架已经清晰拆分，但“有框架”不等于“制成链健康”。** 音效和音乐账本当前为绿；其余 7 域至少有一类异常。所有人员 owner 仍为空，无法形成按域签署、追责和过期处理闭环。

## 5. 设计文档、开发日志与规范

| 检查项 | 当前结果 | 评价 |
|---|---:|---|
| 文档契约 | 110 文档、534 本地链接、60 个测试引用，0 问题 | 通过 |
| 功能追溯 | 37/37 功能与机器表一致；65 个场景链接、3 个命令链接 | 通过 |
| Owner/设计/记录/验收缺项 | 0/0/0/0 | 结构覆盖完整 |
| 独立开发记录目录 | 57 个 Markdown | 记录体系存在 |
| 功能完成状态 | 2 complete / 30 partial / 3 development / 1 contract_only / 1 source_only | 不能把文档覆盖率当完工率 |

仍不满足“每个玩法/功能均有独立完整设计和独立开发日志”的原因：

1. `GRAPHICS-POSTFX` 仍只挂在性能上级设计，缺独立主设计。
2. `RUN-REVIVE` 只有明确的空策略契约，没有复活玩法设计与实现。
3. `RUN-MERCHANT`、`POWER-SYSTEM` 等仍为 development；多项 partial 功能只在综合设计中占一节。
4. 部分开发记录仍指向共享 `CHANGELOG` 或模块历史，而不是该功能一次变更一份独立日志。
5. `docs/README.md` 与版本 README 在本复评前仍指向 2026-09-12 审计；本报告同步把中心入口更新到当前复评。

结论：**“文档驱动和可追溯”已成立；“每项功能都有独立且完整的设计/日志/规范”仍只部分成立。**

## 6. 验收机制与本次实跑

### 6.1 机制覆盖

| 层级 | 当前规模/结果 | 结论 |
|---|---|---|
| 文档/追溯/边界静态门禁 | 全部通过 | 绿 |
| 验收注册 | 156 场景：smoke 6、core 123、visual 26、manual 1、retired 0；漏登/重复 0 | 绿 |
| 隔离 | 用户目录和 `.godot` 缓存隔离自检通过 | 绿 |
| Smoke（包含于本次 core） | 4/6 非失败 | 红；失败为塔楼光照/墙体/战斗综合、完整 3D 流程预算 |
| Headless aggregate core | P0-1～3后重跑：129项，114非失败，15失败，退出码1；复评原始基线为109/20 | 红 |
| Visual | 26 项，本轮未执行 | 未知，不得判绿 |
| Manual | 1 项，本轮未执行 | 未知 |
| 目标 GPU/移动端/30–60 分钟长测 | 未执行 | 未知 |
| 资产结构/完整性 | structure 5 项；full 230 项 | 红 |

### 6.2 20 个失败入口

| 失败组 | 入口 | 主要事实 |
|---|---|---|
| 塔楼/世界 | `verify_tower_lighting_wall_combat_regressions` | 阳光误判、99F 支撑面失活、98F 首波未生成 |
| 性能/综合 | `verify_full_3d_game_flow` | 2,782 节点超预算 |
| 隐藏塔楼流程 | `verify_arrival_gate_floor_bundle_flow` | 98F 门、快照、FloorBundle、Boss/隔离门和卸载链级联失败 |
| 基地/玩家 | `verify_base_world_flow` | 首片 596 节点超预算；手枪跑步握姿失败 |
| 门契约 | `verify_door_passability` | 基础门链通过，但当前没有 EVENT 房样本导致 1 项失败 |
| 性能 | `verify_3d_performance_budget` | 固定 UI 279/171、预览 290/190、总节点 2561/2560、构建 162.1/120ms |
| 运行发放/流送 | `verify_3d_parity_core` | `_spawn_loot_items` 延迟调用数组类型错误、相邻房未流送、2559/2200 节点超预算 |
| 玩家动作 | `verify_3d_reload_state_flow` | 换弹使手枪右手握姿脱离 |
| 基地布局 | `verify_base99_loft_layout_v021` | 床架位置/朝向与验收不一致 |
| 基地资产 | `verify_base99_optimized_packages_v021` | 多个 v002 GLB/包装路径缺失或已迁移 |
| 基地资产 | `verify_base99_wall_visual_replacement` | 当前 99F/100F 布局与旧视觉替换契约不一致 |
| 基地交互 | `verify_base_facility_interaction_zones` | 远征情报室缺碰撞；售货机正面/热区/距离错误 |
| 基地旧功能 | `verify_base_optional_facilities_removed` | 验收仍要求已不存在的 `_create_standalone_elevator` |
| 基地综合 | `verify_base_overhaul_flow` | 验收脚本 `float` 调用错误，并有太阳、设施、入口展示等旧契约失败 |
| 入口演出 | `verify_main_entry_cinematic_flow` | 验收脚本类型推断编译失败，退出码 2 |
| 入口/时间 | `verify_main_entry_realtime_sun_flow` | 太阳峰值和展示相机/灯光/玩家 yaw 契约失败 |
| 玩家动作 | `verify_player3d_diy_flow` | 手枪静止、移动、开火握姿失败 |
| 玩家动作 | `verify_player3d_idle_animation_flow` | 头部延迟重心与手枪呼吸握姿失败 |
| 玩家动作 | `verify_player3d_state_gallery_flow` | 开火覆盖层未保持右手握姿 |
| 镜头/塔楼 | `verify_tower_camera_occlusion_flow` | 98F/楼梯墙样本与碰撞标记缺失，镜头回收失败 |

重复出现但未单独导致全部用例失败的警告：基地尘埃 VFX 使用失效 UID 后退回文本路径；`mission_operations` 多处缺交互/实体形状。两者应作为共享根因排查，而不是在每个用例中分别打补丁。

结论：项目已经有较完整的**验收机制**，但当前**验收结果不合格**。本节记录复评时20个失败的原始基线；P0-1～3后已降至15个，仍包含生产实现问题和旧契约/测试自身错误，不能直接放宽阈值或删除目标设计。

### 6.3 P0-1～3 修复后增量状态（2026-09-23）

本节记录P0-1～3后的全量复验。`bash scripts/run_verification_suite.sh aggregate core`已重跑：129项中114项非失败、15项失败、退出码1；上节“20个失败”保留为修复前历史基线。详细证据见 [P0修复记录](../development/2026-09-23_p0_runtime_entry_player_repair.md)。

| 原问题 | 当前状态 | 裁决 |
|---|---|---|
| `verify_main_entry_cinematic_flow`退出2 | 已可完整执行，现退出1并报告17项设计差异 | 编译/隔离/headless挂死关闭；独立展示相机设计未完成，不判绿 |
| `verify_base_overhaul_flow`的`float`构造错误 | 已可完整执行，现退出1 | 脚本错误关闭；太阳、L梯连续碰撞、设施尺寸/位置权威和入口展示差异保留 |
| `_spawn_loot_items`延迟数组类型错误 | 已关闭 | `verify_3d_parity_core`不再出现该错误；相邻房流送与节点预算仍红 |
| `mission_operations`缺交互/实体碰撞 | 已关闭 | 作者锁定交互盒与语义命名StaticBody可被识别，设施交互专项exit 0 |
| 手枪换弹/DIY/待机/开火/gallery簇 | 已关闭 | 5个逻辑用例exit 0；根因是测试误把新出厂长枪当手枪，未改动作数据或阈值 |
| `verify_base_world_flow`手枪跑步握姿 | 已关闭 | 显式装配`bp_pistol`后该断言消失；场景仍因596/500节点预算退出1 |
| 手枪握持真实渲染 | 已执行并通过 | Apple M1 / Forward+，握点0.00mm、枪口/弹道0.000°，截图已人工查看 |

当前15个失败入口：`verify_tower_lighting_wall_combat_regressions`、`verify_full_3d_game_flow`、`verify_arrival_gate_floor_bundle_flow`、`verify_base_world_flow`、`verify_door_passability`、`verify_3d_performance_budget`、`verify_3d_parity_core`、`verify_base99_loft_layout_v021`、`verify_base99_optimized_packages_v021`、`verify_base99_wall_visual_replacement`、`verify_base_optional_facilities_removed`、`verify_base_overhaul_flow`、`verify_main_entry_cinematic_flow`、`verify_main_entry_realtime_sun_flow`、`verify_tower_camera_occlusion_flow`。

### 6.4 P0-4/P0-7产品范围裁决（2026-09-23）

用户确认连续爬塔不再是当前主要玩法。当前最新正式版本是“99F远征情报室→单层远征关卡”主线，加上99F基地和98F区块00；`DEEPEST_PLANNED_FLOOR=98`、97F以下关闭、98↔99门采用普通交通门的现状即为当前批准版本。

- P0-4不再作为当前主线Bug包。`verify_arrival_gate_floor_bundle_flow`中98—95生成、95→94 Boss门/电梯、隔离间、旧首门封闭/撤退等失败降为低优先级，未来连续爬塔重新开放时再修。
- P0-7采用同一逻辑：只服务隐藏连续爬塔的旧实现、旧资产路径和旧验收合同保留但不立即清零；若同一共享问题能在正式远征主线复现，再按当前Bug提级。
- 本裁决不删除旧实现和验收，也不把失败写成通过。详细记录见[连续爬塔与遗留合同优先级裁决](../development/2026-09-23_hidden_tower_priority_adjudication.md)。

## 7. 命名、目录和中心查询

| 主题 | 中心入口/门禁 | 当前评价 |
|---|---|---|
| 文档导航 | `docs/README.md`、`docs/v0.1/README.md` | 清晰；本次更新到当前复评 |
| 模块/功能 | `MODULE_INDEX.md`、`feature_registry.json` | 37 项机器追溯通过 |
| 文档规范 | `DOCUMENTATION_STANDARD.md` | 有命名、状态、主设计/日志分离规则 |
| 资产规范 | `10_资产与内容规范.md`、`assets/registry/README.md`、`ledger_index.json` | 9 域集中可查 |
| 运行资产命名 | `check_asset_runtime_naming.py` | 新增债务受阻，历史债务未清零 |
| 验收查询 | `run_verification_suite.sh`、注册检查 | 156 场景唯一归属 |

目录问题：

| 问题 | 当前规模 | 影响 |
|---|---:|---|
| 版本化运行资产历史债务 | 289 文件、13 目录、1 备份；引用 gd 23 / tscn 93 | 稳定替换和引用迁移成本高 |
| `_scratch/` 跟踪内容 | 1,468 文件、约 158 MiB | 临时脚本、备份、证据和可能唯一源混杂 |
| `output/` 跟踪内容 | 80 文件、约 76 MiB | 外部/试验交付与正式项目资产边界不清 |
| Godot 用户数据入库 | 4 个跟踪文件、约 11 MiB；另有 2 个忽略 `.import` | 包含正式存档、预览图与 GPU pipeline cache，不属于源码 |
| OS 垃圾 | 36 个忽略的 `.DS_Store` | 无工程价值 |

结论：**命名规范和中心文档体系存在且可用；历史债务和目录边界仍需治理。**

## 8. 可删除与需复核内容

本复评不执行删除。数量分为“已完成清理”“当前高置信度可清”“必须复核”三类。

### 8.1 已完成

P1 已删除 7 份用户快照和 14 个根目录一次性文件，共 **790 个 Git 跟踪文件、约 691 MiB**；复评开始时工作区没有未跟踪文件，这批内容没有回潮。本次新增的复评 Markdown 是明确交付物，不属于清理候选。

### 8.2 当前高置信度可清

| 类型 | 文件数 | 体积 | 处置 |
|---|---:|---:|---|
| `.godot/` | 12,943 | 约 3.02 GiB | 可重建；删除后先 import 再验收 |
| `outputs/` 内容（保留跟踪的 `.gdignore`） | 4,553 | 约 1.91 GiB | 文档已定义为可删除临时产物 |
| `.codex-tmp/` | 76 | 约 22 MiB | 临时数据 |
| `.dev-cycle/` | 1 | 约 12 KiB | 本地生成状态 |
| 忽略的 `.DS_Store` | 36 | 很小 | OS 元数据 |
| `Godot/app_userdata/` 中 2 个忽略导入文件 | 2 | 很小 | 用户预览导入缓存 |
| **本地/忽略小计** | **17,611** | **约 4.95 GiB** | 可清理或重建 |
| `Godot/app_userdata/` 中 4 个跟踪文件 | 4 | 约 11 MiB | 从 Git 移除；存档如需保留先迁出 |
| `_scratch/TFS3D.orig` | 1 | 约 73 KiB | 一次性原始备份，无正式引用价值 |
| **跟踪小计** | **5** | **约 11.1 MiB** | 建议下一批清理提交 |
| **高置信度总计** | **17,616** | **约 4.96 GiB** | 本地缓存与 Git 清理分开执行 |

### 8.3 必须复核后再处理

| 路径 | 跟踪文件 | 体积 | 原因 |
|---|---:|---:|---|
| `_scratch/`（扣除上述 `.orig`） | 1,467 | 约 158 MiB | 含 QA、资产恢复、账本检查、截图和备份；可能有唯一证据/源 |
| `output/` | 80 | 约 76 MiB | 含 Blender、脚本、渲染与交付说明；需确认是否为唯一原稿 |
| **合计** | **1,547** | **约 234 MiB** | 不能整目录删除 |

因此，对“与工程无关的文件有多少”的当前可靠回答是：**可高置信度清理 17,616 个文件，其中只有 5 个是 Git 跟踪文件；其余主要是可重建本地缓存/输出。另有 1,547 个跟踪候选需要逐项确认，不能直接认定为无关文件。**

## 9. 后续整改顺序

| 优先级 | 工作包 | 完成定义 |
|---|---|---|
| P0 | 修复阻断级验收问题 | 先处理入口验收编译失败、运行奖励数组类型错误、缺资产/错误路径；所有用例可真实启动 |
| P0 | 恢复当前正式主线门禁 | 只处理远征主线、99F基地、98F区块00与共享运行时代码的真实回归；隐藏连续爬塔失败不再占用P0 |
| P0 | 资产账本分域核签 | 230 项按来源逐域处理；禁止批量接受哈希；9 个域分配负责人 |
| P0 | 玩家手枪动作簇 | 一次修复跑步、换弹、待机、开火和 gallery 五个相关用例，避免逐测试补丁 |
| P0 | 基地资产/交互簇 | 对照当前正式布局裁决 v021/v002 旧验收、缺路径、情报室碰撞和售货机热区 |
| P0 | 视觉与性能发布证据 | core 绿后执行 26 个真实渲染用例、目标 GPU、移动端和长测；明确退出码与未执行项 |
| P1 | 大型编排器继续瘦身 | 提取 Tower 生命周期、Dungeon 发放 sink、BaseManager 剩余领域服务；禁止新私有跨域访问 |
| P1 | 功能设计独立化 | 为 PostFX、Merchant、Power、Revive 补独立契约与失败语义；共享历史逐步拆为功能日志 |
| P1 | 运行资产去版本化 | 按既定批次计划消化 289/13/1 债务和 23/93 引用 |
| P2 | 仓库第二批整理 | 先清 5 个高置信度跟踪文件，再对 1,547 个候选做引用/原始性/证据价值分类 |
| P3 | 隐藏连续爬塔恢复债务 | 保留98—95/94—90/89—85、Boss门、隔离间、区段卸载和旧资产/验收合同；未来明确重开时统一修复并重新进入发布门禁 |

## 10. 对原始六个问题的直接回答

1. **工程架构**：19 个工程模块、37 个功能。边界和追溯已建立，数据主链大体通畅；只有 TRAINING 达到完整模块级独立维护，WORLD-ENTRY 达到功能级完成。其余多数仍为部分独立。
2. **资产**：9 个资产域、9 本独立账本、426 条资产、9 个匹配 Skill。框架拆分清晰，但 230 项账本问题、20 项拆账基线漂移、9 域 owner 全空，当前制成链不能判绿。
3. **设计/日志/规范**：37/37 都能追溯到设计、开发记录和验收，但部分只链接上级设计或共享历史；只有 2 项 complete，因此“全功能独立设计与日志”仍未完全成立。
4. **验收**：每个功能都有已注册入口，156 场景无漏登；P0-1～3后 headless core 仍有15项失败，视觉/硬件/长测未执行，所以机制有、结果未过。
5. **命名/目录/中心文档**：中心查询体系完整，新增运行资产命名门禁有效；历史版本债务、scratch/output 混放和用户数据入库仍需处理。
6. **精简**：P1 已清 790 个跟踪文件；当前可再高置信度清理 17,616 个文件、约 4.96 GiB，其中 5 个为 Git 跟踪文件。另有 1,547 个跟踪候选需先复核。

## 11. 本次命令证据与限制

通过：

- `python3 scripts/check_documentation_contracts.py`
- `python3 scripts/check_feature_traceability.py`
- `python3 scripts/check_verification_registry.py`
- `python3 scripts/check_domain_boundaries.py`
- `python3 scripts/check_media_asset_domains.py`
- `python3 scripts/check_asset_runtime_naming.py`

失败并已如实计入：

- `python3 scripts/check_asset_registry.py --scope structure`：5 项
- `python3 scripts/check_asset_registry.py --scope full`：230 项
- `python3 tools/asset_pipeline/verify_ledger_split.py`：20 项
- `bash scripts/run_verification_suite.sh aggregate core`：P0-1～3后129项中15失败，退出码1（复评原始基线为20失败）

未执行：26 个 visual 场景、1 个 manual 场景、目标 GPU、移动端导出、30–60 分钟长测。未执行项不计为通过。
