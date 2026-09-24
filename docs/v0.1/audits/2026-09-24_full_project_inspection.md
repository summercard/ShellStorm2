# ShellStorm2 全项目深度检查报告

日期：2026-09-24。工程版本：`project.godot` 0.1.0。检查基线：工作区 HEAD `bda2c828`（当日另一会话仍在提交，见 §10 限制）。

检查依据：先按 [工程文档入口](../../README.md) 的顺序读 [文档驱动开发规范](../../DOCUMENTATION_STANDARD.md)、[模块与功能索引](../MODULE_INDEX.md)、[游戏设计](../README.md)、[功能关系计划](../FEATURE_RELATIONSHIP_PLAN.md) 与 [跟踪表](../FEATURE_RELATIONSHIP_MATRIX.md)，确立判定原则；再对当前工作区**实跑**静态门禁与运行验收，并清点目录与文件。

本文只记录本次实测事实，不改写旧审计的时点结论，也不修改玩法、资产内容或验收阈值。旧基线见 [2026-09-23 全项目完整复评](2026-09-23_full_project_reassessment.md)。

---

## 0. 结论速览

| # | 问题 | 结论 | 等级 |
|---:|---|---|---|
| 1 | 架构解耦与数据串联 | 19 模块 / 37 功能边界与追溯已建立，**主链数据串通**；仅训练场达到完整模块级独立维护。Tower/Dungeon/Player/BaseManager 四个巨型编排器 + 24 个 Autoload 仍是独立维护的主要阻塞 | 黄 |
| 2 | 资产模块、账本、Skill、制成链路 | 9 域 9 本分账本 + 9 个匹配 Skill 的框架清晰；`full` 报 204 项**全部为 SHA 类**，其中**约 98% 是行尾假漂移**，真内容漂移仅 5 行；9 域 Owner 全为「待分配」 | 黄 |
| 3 | 设计文档 / 开发日志 / 规范体系 | 37/37 可机器追溯到 Owner、主设计、开发记录、验收入口；150 份 md、68 份独立交付记录、19 份模板与规范；仍有 10 项功能只挂上级共享设计，无独立主设计 | 绿/黄 |
| 4 | 验收机制 | 机制完整（160 场景唯一归属、按场景隔离 `user://`、退出码 + 预期错误清单判分）；**结果未全绿**：本次实跑 smoke 4/6、主线 12 项全部通过 | 黄 |
| 5 | 命名 / 目录 / 中心文档 | 中心查询体系完整、新增命名门禁有效；存量去版本化债务 289 文件 / 13 目录 / 23+93 处引用未清；个人存档与编辑器设置仍在 Git 中 | 黄 |
| 6 | 可清理文件 | 仓库内可高置信度清理约 **3.9 GB**（多为可重建缓存）；跟踪文件中有 5 类边界不清项；仓库外工作区另有 **37,107 个文件 / 12.2 GB** 一次性产物 | 黄 |

**一句话**：这个工程的**治理体系（文档、追溯、门禁、命名）已经成体系且真实可跑**；当前风险不在「有没有规矩」，而在 ①四个巨型编排器的解耦、②运行验收红灯、③存量债务与工作区垃圾。

### 本次三处红灯经归因**全部不是内容缺陷**，必须纠正地看待

| 现象 | 表面结论 | 实测归因 | 证据 |
|---|---|---|---|
| `check_feature_traceability.py` 报 37 项「MODULE_INDEX design links absent from registry」 | 追溯链断裂 | **工具跨平台缺陷**：脚本用 `str(Path)` 比较（Windows 产出反斜杠），注册表存正斜杠 | 改用 `Path` 对象比较后不匹配数 = **0 / 37** |
| `check_asset_registry.py --scope full` 报 204 项 SHA 不一致 | 204 个资产内容漂移 | **约 98% 是行尾假漂移**：账本按 LF 记录，工作区为 CRLF，`_sha256` 读原始字节 | 239 项抽样归因：LF 规范化后匹配 **234**，真内容漂移 **5** |
| `verify_opening_script_runtime` 退出 1，报「开场剧本未起跑」 | **正式主线入口 P0 回归** | 🔴 **本报告自己的假红**：诊断用的直跑脚本让所有场景**共用一个 `user://`**，而跨局档案 `narrative_history` 已记下开场 ⇒ `once = "run"` 拒绝重播 | 全新隔离目录单跑 **退出 0 / 105 项检查全过**；同目录二连跑 = 第一次过、第二次红 |

三处都属于「检查工具在 Windows 工作区不可用 / 用法不对」，不是工程内容出问题。第 1、2 处的修复见 §8；**第 3 处的更正与修改方案见本文件 §0.1（紧跟本节）**。

---

## 0.1 · P0 剧本项：撤回 + 修改方案（剧本 × 剧情工具 × 设计文档 三处同步）

<div style="color:#B71C1C;background:#FDECEA;padding:12px 14px;border-radius:8px;border-left:4px solid #B71C1C">

**⛔ 撤回：本报告原定 P0「开场剧本触发链断裂」不成立。**

`verify_opening_script_runtime` 在**正确隔离**下**完全通过**（退出码 0、`105 项检查 / 8 项观察`、无 `OPENING_SCRIPT_RUNTIME_FAIL`），与 2026-09-23 基线逐字一致。
它是被我的诊断脚本打红的：直跑批次让 26 个场景**共用一个 `APPDATA` 目录**，而套件是**每场景独立 `user://`**。

**二连跑实证**（同一隔离目录，同一命令）：

| 次序 | 结果 |
|---|---|
| 第 1 次（目录干净） | 退出 0 · 105 项检查 · 无 FAIL |
| 第 2 次（同目录） | 退出 1 · 4 项检查 · `点开始后 30s 内开场剧本仍未起跑（gameplay_started 触发链断了）` |

⇒ 产品行为**与设计一致**：`once = "run"` 的消耗记录落 `BaseData.narrative_history`，同一份存档里开场只演一次。**这不是回归，是我把验收前置条件搞错了。**

</div>

<div style="color:#1565C0;background:#E8F0FE;padding:12px 14px;border-radius:8px;border-left:4px solid #1565C0">

**修改方案（待业主确认后执行）** —— 按「剧本 · 剧情工具 · 设计文档」三处同步落地，禁止只改代码不入文档。

**A. 剧本本体（`data/narrative/nar_tower_opening_01_wake.json`）—— 建议不动**

| 项 | 结论 |
|---|---|
| `trigger` | `{"kind":"event","on":"gameplay_started","filter":{"room_id":"floor_01_exit"},"once":"run"}` 保持原样 |
| `spawn_key` | `nar_tower_opening_01_wake:starter_weapon` 保持原样（`66093dc2` 新增，幂等防重，正确） |
| 理由 | 实测剧本能正常起播、正常收口、开场地上的枪正确落地；**当前无证据支持改剧本**。为「让验收变绿」而改剧本属于反向改动 |

**B. 剧情工具（Skill `10-narrative-timeline-authoring`）—— 必须改 2 条**

| 位置 | 现状 | 改为 |
|---|---|---|
| 已知坑 **#7** | 「`once:"run"` 是本局内存态，续局后会再来一次。**需要严格一次要等跨局历史落地**」 | **已过期**（跨局历史 2026-09-23 已落地）。改为：「`once:"run"` 的消耗记录已落 `BaseData.narrative_history`，**同一份存档不再重播**；要重看须走复位存档。归零点 = `game_save_reset_completed`」 |
| 已知坑 **#12** | 「验收会写 `user://`（`GameTimeManager` 定时刷档）。跑验收**前快照、后还原**用户目录」 | 补足硬约束：「**跨局档案会改变下一次的运行条件** ⇒ ① 每条用例必须独占自己的 `user://`（套件已这么做，直跑必须自己造）；② **同一目录连续重跑同一场景 = 必红**（开场/剧情类最典型），不是回归；③ 直跑多场景批次时，一条场景一个目录，禁止共用」 |

**C. 剧情系统设计文档（`docs/v0.1/08_技术施工_剧情触发.md`）—— 必须改 2 处**

| 位置 | 现状 | 改为 |
|---|---|---|
| §9 内容边界 ·「标记不进存档」 | 已写明 `narrative_history` 与「复位存档 ⇒ 新档能重新看到开场」 | 补一句**验收口径**：「跨局档案是运行前置条件的一部分；任何剧情验收必须在**干净 `user://`** 下判定，同目录重跑结论无效」 |
| §11 验收标准 · 证据要求 | 只有「反向对照」「降级分支要有断言」 | 新增一条：「**顺序独立**：同一用例在干净目录下首次执行必须通过；把它的结论复用到第二个序列之前，必须先清目录」 |

**D. 唯一真正的产品待裁决项（不属于本次 P0，但与此同源）**

设计文档 §9 目前只给了**一条**让开场重演的路径 —— 「复位存档」（整档换新）。2026-09-23 交付记录里已把它登记为欠账：**已看过开场的档，玩家自己无法再要求「重看开场」**。三个选项请业主裁决：

| 选项 | 做法 | 代价 |
|---|---|---|
| **甲** | 维持现状（只看一次 + 复位存档） | 零改动；玩家只能整档重来 |
| **乙** | 剧本侧新增一个**可重看**标记（如 `once:"reviewable"` 或 `replay_key`），由基地某设施/设置项触发 | 要同时改剧情系统本体（`NarrativeDirector3D` 裁决）、08 文档 §4.3、Skill 10 schema 章、以及台账/内容表 |
| **丙** | 不新增档位，只加一个**「重看开场」调试入口**（操作设置页），复用它把 `narrative_history` 中该条清除 | 改动最小；但要明确它是否进正式版 |

</div>

### 与本项相关的报告条目（便于回改）

| 位置 | 条目 | 处置 |
|---|---|---|
| §0 速览 | 第 4 行「验收机制 — 结果未全绿」 | 保留，但 P0 一栏已撤回 |
| §0 三处红灯表 | 第 3 行（本次新增） | 已更正为「本报告自己的假红」 |
| §2.3 数据流 | 「剧情触发 → 时间轴 → 对话/发物」一行 | **由「不通（回归）」改为「通」** |
| §5.2 主线批次 | `verify_opening_script_runtime` 一行 | **由「失败（回归）」改为「通过（需逐场景独立 `user://`）」** |
| §5.3 高优先问题 | 原「P0｜开场剧本触发链断裂」 | **整条撤回**，替换为假红说明 |
| §8 整改建议 | 原 P0 第 1 行「修 `verify_opening_script_runtime`」 | **删除**；改为「修直跑脚本的逐场景隔离」 |
| §9 命令证据 | 失败清单中的 `verify_opening_script_runtime` | 移入通过清单并标注隔离前提 |
| §10 限制 | 第 2 条 | 补「直跑批次的 `user://` 隔离由脚本自建，本次首版漏做，已更正」 |

---

---

## 1. 判定原则（从文档提取）

| 原则 | 文档来源 | 合格判据 |
|---|---|---|
| 唯一状态所有者 | [规范](../../DOCUMENTATION_STANDARD.md) §3 | 每项状态只有一个服务/数据域拥有最终写入权 |
| 最小工程契约 | 同上 §3 | feature_id / 版本 / 来源状态 / Owner / 输入命令 / 输出事件 / 数据链 / 失败收口 / 独立开发入口 / 正式接入 / 验收 / 开发记录 共 12 字段 |
| 解耦 ≠ 拆文件 | [AGENTS.md](../../../AGENTS.md) | 「不要用复制平行实现或仅拆文件代替解耦」 |
| 独立开发判据 | [MODULE_INDEX](../MODULE_INDEX.md) §1 | 「可独立」指可通过清晰输入/输出与替身验证，不要求脱离引擎 |
| 三文档分工 | [规范](../../DOCUMENTATION_STANDARD.md) §1 | 设计契约 / 开发记录 / 版本状态三分离，不互相复制 |
| 验收四要素 | [AGENTS.md](../../../AGENTS.md) | 分别记录退出码、预期故障、非预期脚本错误、未执行项 |
| 资产稳定路径 | [AGENTS.md](../../../AGENTS.md) | 运行路径不带版本号，版本只写 source / manifest / 台账 / prefab metadata |
| 分域账本 | [规范](../../DOCUMENTATION_STANDARD.md) §5 | 资产行必须落在所属域分账本，总目录不登记资产行 |

---

## 2. 问题 1：工程架构是否解耦、数据是否串通

### 2.1 规模事实

| 指标 | 实测值 | 说明 |
|---|---:|---|
| Git 跟踪文件 | 8,666 | 仓库 2,220 MB |
| `src/` GDScript | 196 个 / 70,306 行 | 顶层目录 21 个 |
| Autoload | 24 | 全局依赖面偏大 |
| 工程模块（逻辑） | 19 | 与 MODULE_INDEX §1 一致 |
| 可机器追溯功能 | 37 | complete 2 / partial 31 / development 2 / contract_only 1 / source_only 1 |
| 功能 Owner | 32 个唯一值，0 项「待分配」 | 已明确 |

### 2.2 19 个模块的独立维护结论

| 模块 | 权威链路 | 独立维护 | 数据串联 | 首要缺口 |
|---|---|---|---|---|
| PLAYER | `Player3D` → 状态类 → `PlayerAvatar3D`；交互控制器 → 门/设施 | 部分 | 通 | 玩家脚本仍聚合装备、背包、动作 |
| WEAPON | 内容注册 → `WeaponInstance` → 装配树 → 模型/投射物/近战 | 部分 | 通 | 统一命中上下文与全局所有权账本未闭环 |
| INVENTORY | 背包/保险格位 → `EquipmentTransactionService` → 玩家槽 | 事务可独立，其余部分 | 通 | 场景仍编排卸装、快捷栏、掉落 |
| FATE | 牌组内容 → `FateCardEngine` → 三类作用域持有者 | 部分 | 通 | 48 运行卡 / 78 目标牌组并存；世界执行依赖 Dungeon |
| WORLD | `FloorPlanGenerator` 纯计划 → `RoomGraphRuntime` 查询 → Dungeon/Tower 装配 | 计划/远征入口较独立，塔楼生命周期不足 | 主线通，隐藏爬塔不通 | 父子编排与私有字段依赖多，生命周期 Service 未提取 |
| ENEMY | `Enemy3D` + `MonsterAIManager` + `EnemyIllumination3D` | 部分 | 通 | 物种行为集中在 Enemy3D |
| ELITE | `EliteContentCatalog` → `EliteRosterService` → BaseManager 档案事务 | 部分 | 通 | 12 名册仅 1 个正式投放 |
| BOSS | `BossContentCatalog` → Enemy3D 阶段 → 塔楼下行权限 | 部分 | 有偏差 | 设计钥匙 ID 与计数式授权不一致 |
| BASE | 设施目录/服务 → `BaseManager` → BaseData → UI | 规则/工坊事务可独立 | 基本通 | Manager 仍含存储/多类交易/能源/外观 |
| SAVE | Run 快照 → Profile 封套 → `AtomicJsonStore` → BaseManager | 序列化与主要事务可独立 | 通 | 多写者互斥与领域通知未统一 |
| NARRATIVE | 触发声明 → 时间轴 JSON → Director/Adapter → 对话/奖励/地面物 | 部分，核心链可独立验 | 通 | `retry/never` 新语义与全内容投放未完成 |
| TIME | `WorldTimeDomain` → `GameTimeManager` → 太阳/HUD/能源 | 算法可独立 | 部分通 | 规则仍为代码常量 |
| POWER | `BaseEnergyService`；`PlayerFlashlight3D`；恢复舱转换 | 两条链可独立验 | 通 | 基地负载未接统一电网服务 |
| ENTRY | `GameEntryFlow` → 塔楼主页 → 玩法 | 部分 | 主链通 | 塔楼仍负责主页与设施 UI 装配 |
| PRESENTATION | `HUDPresenter3D` 快照、公共 UI 组件、VfxPool、Audio/Music | HUD/音乐部分；VFX 未收敛 | 基本通 | UI 仍跨域；旧 CombatEffectPool 兼容链仍在 |
| PERFORMANCE | GraphicsSettings / PostfxOverlay / RuntimePerformanceManager | 部分 | 通 | 调参面板越权；预算失配 |
| TRAINING | `TrainingRange3D` → 只读注册表 → 共用 Player → 会话统计 | **是（唯一完整模块级）** | 通 | 已 1.0 完成 |
| ASSET | XLSX 台账 → 源 → GLB → PackedScene → 正式场景 | 流程标准独立，健康度不足 | 有漂移 | 存量命名债务与真 SHA 漂移 |
| TOOLING | 验证清单 → 隔离工程 → 日志/退出码/静态门禁 | 部分 | 通 | 门禁跨平台缺陷；视觉/硬件/长测未跑 |

### 2.3 数据串联（主链实测）

| 数据流 | 结论 | 本次实测证据 |
|---|---|---|
| 冷启动 → 99F 基地 → 远征菜单 → 读取页 → 独立关卡 | 通 | `verify_game_entry_flow` 0/0、`verify_expedition_level01_flow` 0/0 |
| 远征撤离 → 携带物返还 | 通 | `verify_expedition_extraction_carry_return` 0/0 |
| 新档 98F 开场 → 99F 下线 → 重登 → 拾取 | 通 | `verify_new_save_handoff` 0/0 |
| 行动快照 → 重启恢复 | 通 | `verify_runtime_autosave_flow` 0/0 |
| 撤离/死亡 → 原子结算 | 通 | `verify_run_settlement_transaction` 0/0 |
| 工坊扣魂 + Tier + 幂等写盘 | 通 | `verify_workshop_transaction_flow` 0/0 |
| 奖励统一解析 → 四个发放口 | 通 | `verify_reward_service_flow` 0/0 |
| 装备实例转移与回滚 | 通 | `verify_equipment_transaction_service` 0/0 |
| 剧情触发 → 时间轴 → 对话/发物 | 通 | `verify_narrative_timeline` 0/0、`verify_opening_script_runtime` **0/0（105 项检查，需干净 `user://`）** —— 见 §0.1 更正 |
| 隐藏塔楼到达门 → 区段提交/卸载 | 不通（已裁决为低优先级） | `verify_tower_lighting_wall_combat_regressions` 退出 1 |
| 战斗/综合 3D 流程 | 不通（节点预算） | `verify_full_3d_game_flow`：2,784 节点超预算 |

### 2.4 解耦的主要阻塞

| 编排器 | 行数 | 说明 |
|---|---:|---|
| `src/world3d/TowerDescent3D.gd` | 6,168 | 塔楼生命周期、门事务、快照、卸载混合 |
| `src/world3d/Dungeon3D.gd` | 5,959 | 房间装配、发放 sink、商人、UI 编排 |
| `src/world3d/DungeonRoom3D.gd` | 3,254 | 房间内容与设施装配 |
| `src/player3d/Player3D.gd` | 1,983 | 状态 + 装备接口 + 动作 + 全局依赖 |
| `src/world3d/TowerFloorStage3D.gd` | 1,761 | 楼层舞台 |
| `src/enemy3d/Enemy3D.gd` | 1,743 | 物种行为集中 |
| `src/base/BaseManager.gd` | 1,588 | 存储 / 交易 / 能源 / 外观 / 运行档 |

跨域私有访问门禁（`check_domain_boundaries.py`）当前**违规 0**，但它只覆盖 3 类已知模式（`BaseManager.data`、`_ensure_data`、`VfxPool3D._REGISTRY`），覆盖面有限。

---

## 3. 问题 2：资产模块、账本、Skill 与制成链路

### 3.1 九个资产域

| 域 | 条目 | 独立账本 | Primary Skill | Skill 存在于正本 | 本次问题 | Owner |
|---|---:|---|---|---|---:|---|
| characters | 16 | 是 | game-character-model-pipeline | 是 | 3 SHA | 待分配 |
| enemies | 13 | 是 | game-character-model-pipeline | 是 | 4 SHA | 待分配 |
| scenes | 236 | 是 | scene-full-pipeline | 是 | 153 SHA | 待分配 |
| props | 20 | 是 | game-prop-model-pipeline | 是 | 15 SHA | 待分配 |
| weapons | 36 | 是 | game-weapon-model-pipeline | 是 | 19 SHA | 待分配 |
| vfx | 16 | 是 | vfx-combat-effect-authoring | 是 | 5 SHA | 待分配 |
| ui | 16 | 是 | ui-asset-pipeline | **否**（仅项目 `.codex/skills`） | 5 SHA | 待分配 |
| audio | 48 | 是 | audio-sfx-asset-pipeline | **否**（仅项目 `.codex/skills`） | 0 | 待分配 |
| music | 9 | 是 | music-asset-pipeline | **否**（仅项目 `.codex/skills`） | 0 | 待分配 |
| **合计** | **410** | **9/9** | 9/9 可定位 | **6/9** | **204** | **0/9** |

真源：`assets/registry/ledger_index.json`；总目录只放索引不登记资产行。

### 3.2 门禁实测

| 门禁 | 退出码 | 结果 |
|---|---:|---|
| `check_asset_registry.py --scope structure` | 0 | 410 项 / 9 账本 / 问题 0（旧审计的 5 项状态枚举已关闭） |
| `check_asset_registry.py --scope full` | **1** | 204 项，**全部为 `sha_mismatch`**（旧审计的 24 路径 + 5 状态 + 1 缺 SHA + 1 文件名均已关闭） |
| `verify_ledger_split.py` | **0** | 410 项、9 账本、缺失 0、多余 0、列摘要漂移 0（旧审计的 20 项漂移已清零） |
| `check_media_asset_domains.py` | 0 | 3 域、73 项媒体资产、注册验收入口完整 |
| `check_asset_runtime_naming.py` | 0 | 只拦新增；存量欠账 289 文件 / 13 目录 / 1 备份，带版本引用 gd 23 / tscn 93 |
| `check_ledger_refs.py` | **1** | 悬空引用 49、待重定 21、历史记录 176 json + 14 文本；带 `--allow-pending` 退出 0（已在 2026-09-22 审计登记为已知债务） |
| `check_classname_unique.py` | 0 | 171 个 class、重复 0 |

### 3.3 204 项「SHA 漂移」的归因（本次独立复核）

复现方式：逐行读 9 本分账本 `资产主表` 的路径列与 SHA 列，对同一文件分别计算原始字节 / LF 规范化 / CRLF 规范化三种 SHA。

| 归类 | 行数 | 判定 |
|---|---:|---|
| 原始字节一致 | 69 | 正常（多为二进制 .glb/.png/.wav） |
| **仅行尾不同（LF 规范化后一致）** | **234** | **假漂移**，非内容变更 |
| 真内容漂移 | **5** | 需处理 |

5 行真漂移明细：

| 域 | AssetID | 文件 | 追溯 |
|---|---|---|---|
| scenes | ENV-TOWER-DESCENT-KIT-3D | `scenes/TowerDescent3D.tscn` | 2026-09-17 `7d41a299` 去版本化后未回填 |
| scenes | ENV-TOWER-CORNER-T-5M | `assets/art/props/dungeon_3d/prp_corner_t_5m.tscn` | 同上 |
| scenes | ENV-TOWER-CORNER-X-5M | `assets/art/props/dungeon_3d/prp_corner_x_5m.tscn` | 同上 |
| scenes | PRP-BASE-FACILITY-LIGHT-GRID-3D | `assets/art/props/dungeon_3d/prp_base_facility_light_grid_root_top3d.tscn` | 同上 |
| props | ITM-PICKUP-BASE-GROUND-ITEM | `src/world3d/GroundLootPickup3D.gd` | 2026-09-24 `66093dc2` 开局存档修改 |

**结论**：资产制成链路的**框架（域 → 账本 → Skill → 流程）拆分清晰且已完成媒体拆域**；当前 `full` 红灯约 98% 由「账本按 LF 记录 SHA、工作区为 CRLF」造成，属门禁口径问题，不是 204 个资产损坏。真正需要处理的是 5 行。

### 3.4 Skill 镜像一致性（四副本对比）

| 副本 | 数量 | 相对正本的差异 |
|---|---:|---|
| 正本 `~/.workbuddy/skills` | 31 | — |
| `~/.codex/skills` | 39 | 缺 `blender-mcp-bridge`、`shellstorm2-asset-ledger-row-authoring`；多 10 个他项目技能 |
| 项目 `skills_drafts` | 35 | 缺同上 2 个；多 6 个 `0X-character-*` 旧链路 |
| 项目 `.codex/skills` | 38 | 缺同上 2 个；多 6 个 `0X-character-*` + `ui/audio-sfx/music-asset-pipeline` |

问题：账本为 ui / audio / music 三域声明的 Primary Skill 只存在于项目 `.codex/skills` 一处，正本缺失；另有 6 个 `0X-character-*` 疑似被 `game-character-model-pipeline` 取代但未清理。

---

## 4. 问题 3：设计文档、开发日志与规范体系

| 检查项 | 实测 | 评价 |
|---|---:|---|
| `docs/**/*.md` | 150 | 分四层：主题页 36 / 功能设计 9 / 开发记录 70 / 审计 4 / 美术验收 5 / 归档 11 |
| 独立交付记录（`development/*.md` 扣 README+CHANGELOG） | 68 | 一交付一记录，符合规范 |
| 模块历史记录（`development/history/`） | 10 | 历史拆出并保留锚点 |
| 模板 | 2 | `templates/feature_design.md`、`templates/development_record.md` |
| 规范体系 | 19 份主题施工文档 + [资产与内容规范](../10_资产与内容规范.md) + [3D 美术生产流程](../10.1_3D场景美术生产流程.md) + [角色美术流程](../16.1_角色美术制作与动作导入流程.md) | 完整 |
| 37 功能 × Owner/主设计/开发记录/验收 | 37/37 齐备 | 结构覆盖完整 |
| **只挂上级共享设计、无独立主设计** | **10 项** | PLAYER-STATE、PLAYER-INTERACT、WORLD-ENTRY、WORLD-GATE、WORLD-SEGMENT、ELITE-ROSTER、BOSS-STAGES、BASE-FACILITY、RUN-REVIVE、PERFORMANCE-RUNTIME |
| 已引用 `design/` 独立设计页 | 15 项 | 含 WORLD-LOOT、REWARD-SERVICE、SAVE 三件套、BASE-SHOP、RUN-MERCHANT、DIALOGUE-UI、GRAPHICS-POSTFX 等 |
| 功能实现状态 | complete 2 / partial 31 / development 2 / contract_only 1 / source_only 1 | **文档覆盖率 ≠ 完工率** |

**判定**：问题 3 中「**制作前是否有独立规范体系**」——**是**，且是这份工程最扎实的部分（模板 + 19 份施工规范 + 31 个 Skill + 门禁）。「**是否每个玩法都有独立设计文档**」——**不完全是**，10 项仍挂在共享上级设计里；「**是否都有开发日志**」——**是**，68 份一交付一记录。

---

## 5. 问题 4：验收机制

### 5.1 机制层级

| 层级 | 实测 | 结论 |
|---|---|---|
| 文档/追溯/边界静态门禁 | 见 §5.3 | 4 绿 4 红（其中 2 红为工具缺陷、1 红为已登记债务） |
| 验收注册 | 160 场景唯一归属：smoke 6 / core 127 / visual 26 / manual 1 / retired 0，漏登与重复 0 | 绿 |
| 判分方式 | Godot 退出码 + `<NAME>_OK/_FAIL` 标记 + `check_verification_log.py` 对非预期 `ERROR:`/`SCRIPT ERROR:` 判 3、资源泄漏判 4 | 有层次，可机器判定 |
| 隔离 | Runner 为**每个场景**分配独立 `user://`，预检与正片共用同一目录 | 绿（消除了跨场景长期档污染） |
| 真实渲染 | visual 26 项独立成组，不混入 headless | 机制正确 |
| 设备/长时 | 目标 GPU、移动端、30–60 分钟长测有入口 | 未执行 |

### 5.2 本次实跑（HEAD `bda2c828`，直跑，未使用会在本机退化成整盘复制的套件脚本）

**smoke 6 项 → 4 通过 / 2 失败**

| 场景 | 结果 |
|---|---|
| verify_3d_only_project_structure | 通过 |
| verify_player3d_avatar_bounds | 通过 |
| verify_tower_grid_component_alignment | 通过（旧基线为红，现已修好） |
| verify_tower_level_blocks | 通过 |
| verify_tower_lighting_wall_combat_regressions | **失败**：99F 楼面支撑在关闭舞台流送时未保持物理激活；98F 中心门开门未生成首波敌人 |
| verify_full_3d_game_flow | **失败**：3D 关卡节点 2,784 超原型预算 |

**正式主线关键链路 12 项 → 12 通过 / 0 失败**

| 场景 | 结果 |
|---|---|
| verify_game_entry_flow | 通过 |
| verify_expedition_level01_flow | 通过 |
| verify_expedition_extraction_carry_return | 通过 |
| verify_narrative_timeline | 通过 |
| verify_opening_script_runtime | **通过**（须干净 `user://`；见 §0.1） |
| verify_new_save_handoff | 通过 |
| verify_runtime_autosave_flow | 通过 |
| verify_run_settlement_transaction | 通过 |
| verify_workshop_transaction_flow | 通过 |
| verify_reward_service_flow | 通过 |
| verify_equipment_transaction_service | 通过 |
| verify_training_range_3d_flow | 通过 |

### 5.3 本次发现的高优先问题

<div style="color:#B71C1C;background:#FDECEA;padding:10px 12px;border-radius:6px">

**~~P0｜开场剧本触发链断裂~~ —— 已撤回，是我自己的假红**

原始观测（**在共用一个 `user://` 的直跑批次里**）：

```
ERROR: OPENING_SCRIPT_RUNTIME_FAIL: 点开始后 30s 内开场剧本仍未起跑（gameplay_started 触发链断了）
verify_opening_script_runtime_FAIL checks=4 failures=1   （退出码 1）
```

**更正**：把该场景放进**干净隔离目录**单跑 ⇒ 退出 0、`105 项检查 / 8 项观察`、无任何 FAIL。同目录二连跑 ⇒ 第一次过、第二次红。

真因 = 跨局档案 `BaseData.narrative_history` 已记录开场 ⇒ `once = "run"` 拒绝重播（**设计如此**）。**正式主线入口没有回归。** 完整更正与修改方案见 §0.1。

</div>

**门禁工具的跨平台缺陷（建议优先修，成本一行）**

- `scripts/check_feature_traceability.py:35`：`str(resolved.relative_to(root))` → Windows 产出反斜杠。改为 `.as_posix()` 即可；已实测修正后不匹配数 0/37。
- 连带 `check_documentation_contracts.py` 也因嵌入该校验而退出 1。
- `scripts/check_asset_registry.py:92 _sha256` 读原始字节，建议与账本记录口径统一（写入侧规范化行尾，或校验侧比对 LF 规范化哈希）。

**已裁决为低优先级（不重复占用 P0）**

- 隐藏连续爬塔链路（到达门、区段提交、Boss 门、隔离间）：产品范围已裁为低优先级，保留实现与红项。
- 节点预算类失败（`verify_full_3d_game_flow` 2,784）：属性能预算口径，需与目标设备一起评估，不宜单独放宽阈值。

---

## 6. 问题 5：命名、目录与中心文档

### 6.1 中心查询体系（可用）

| 主题 | 中心入口 | 状态 |
|---|---|---|
| 文档导航 | [docs/README.md](../../README.md) | 完整，含阅读顺序 |
| 文档规范 | [DOCUMENTATION_STANDARD.md](../../DOCUMENTATION_STANDARD.md) | 含命名、状态、主设计/日志分离规则 |
| 模块 / 功能 | [MODULE_INDEX.md](../MODULE_INDEX.md) + [feature_registry.json](../feature_registry.json) | 37 项机器可追溯 |
| 功能关系 | [FEATURE_RELATIONSHIP_PLAN.md](../FEATURE_RELATIONSHIP_PLAN.md) + [跟踪表](../FEATURE_RELATIONSHIP_MATRIX.md) | 逐项交接与缺口 |
| 资产规范 | [10_资产与内容规范.md](../10_资产与内容规范.md) + [assets/registry/README.md](../../../assets/registry/README.md) + `ledger_index.json` | 9 域集中可查，单一真源 |
| 验收查询 | `scripts/run_verification_suite.sh` + `check_verification_registry.py` | 160 场景唯一归属 |
| 命名门禁 | `check_asset_runtime_naming.py`、`check_classname_unique.py`、`PRODUCTION_NAME_PATTERN` | 新增受拦 |

### 6.2 三类文件的命名/存放规则

| 文件类型 | 命名与存放规则 | 执行情况 |
|---|---|---|
| 运行资产（`components/`、`runtime/`） | 路径恒定、不含 `_vNNN` | 新增受拦；存量 289 文件 / 13 目录未清 |
| 源资产（`source/`） | 允许版本号，`_vNNN.blend` | 合规 |
| 代码 | `class_name` 全局唯一；GDScript 在 `src/` 按域分目录 | 171 类 0 重复；21 个域目录 |
| 验证场景 | `tests/verification/verify_<feature>.tscn/.gd`，必须注册 | 160 个 verify_* 全部唯一归属；另有 preview_/probe_/audit_ 55 个工具场景 |
| 台账 | `assets/registry/ledgers/ShellStorm2_<域>账本_v001.xlsx` | 9 本齐备 |

### 6.3 目录边界问题

| 问题 | 规模 | 影响 |
|---|---:|---|
| 版本化运行资产历史债务 | 289 文件 / 13 目录 / 1 备份；引用 gd 23 / tscn 93 | 稳定替换与引用迁移成本高 |
| `_scratch/`（仓库内，已跟踪） | 1,468 文件 / 153 MB | 临时探针、备份、证据与可能唯一源混杂 |
| `output/`（已跟踪） | 80 文件 / 52 MB | 果冻 v001–v003、粉色房间样例，与正式资产边界不清 |
| `Godot/` 个人数据入库 | `app_userdata/弹壳风暴2/` 下 4 文件（含 `base_save.json`、预览 png、RTX 4060 Ti pipeline cache）+ `editor_settings-4.6.tres` | 存档与设备缓存不属源码 |
| 根目录孤立素材 | `bgm_wasteland.wav`（7.6 MB）+ `generate_bgm.py` | 正式音频链在 `assets/audio/`，此二者未见运行引用 |

---

## 7. 问题 6：可清理的无关文件

### 7.1 仓库内 · 可高置信度清理（本地生成/可重建，均被 Git 忽略）

| 路径 | 文件数 | 体积 | 处置 |
|---|---:|---:|---|
| `.godot/` | 11,224 | **3.8 GB** | 可重建；删后需重新 import。注意：今日清理记录曾降至 8.5 MiB，本次实测又回到 3.8 GB（编辑器运行 + 本次诊断刷新导入缓存所致） |
| `.codex-tmp/` | 7,800 | 320 MB | 临时数据 |
| `build/` | 4 | 230 MB | 构建输出（已忽略） |
| `outputs/` | 192 | 31 MB | 文档定义的可删除临时产物，保留 `.gdignore` |
| **小计** | **19,220** | **约 4.4 GB** | 删除不影响仓库内容 |

### 7.2 仓库内 · 建议从 Git 迁出（跟踪文件）

| 路径 | 文件数 | 体积 | 原因 |
|---|---:|---:|---|
| `Godot/app_userdata/弹壳风暴2/` | 4 | 11.1 MB | 个人存档、预览图、GPU pipeline cache |
| `Godot/editor_settings-4.6.tres` | 1 | 小 | 编辑器个人设置 |
| `_scratch/TFS3D.orig` | 1 | 73 KB | 一次性原始备份 |

### 7.3 仓库内 · 必须逐项复核（不能整目录删）

| 路径 | 文件数 | 体积 | 原因 |
|---|---:|---:|---|
| `_scratch/` | 1,468 | 153 MB | 含探针证据、迁移脚本、md5 基线；去版本化文档仍引用其中脚本 |
| `output/` | 80 | 52 MB | 可能是他项目/样例的唯一原稿 |
| `.blend1` 自动回退副本 | 49 | 110.8 MB | 其中 13 个**无同名主文件**，可能是仅存可编辑副本 |
| `*.bak*` 台账/内容库备份 | 69 | 18.6 MB | 本地忽略；需逐件与正本+账本比对 |
| 根目录 `bgm_wasteland.wav` + `generate_bgm.py` | 2 | 7.6 MB | 未接入正式音频链，待归档或接链 |

### 7.4 仓库外工作区（`I:\工作项目\shellstrom2`，不在 Git 中）

| 路径 | 文件数 | 体积 |
|---|---:|---:|
| `_scratch/` | 17,137 | 6.0 GB |
| `outputs/` | 13,502 | 4.5 GB |
| `.codex-tools/` | 6,122 | 1.66 GB |
| `_b3tmp/`、`_conflict_check/`、`_scratch_logs/`、`_ss_probe/`、`__pycache__/` | 约 280 | 约 5 MB |
| 一次性散落文件：`_probe*.txt` ×9、`$null`、`out.txt<I:…>（文件名本身是命令拼接事故产物）`、`inspect.py`、`inspect2.py`、`optimize.py`、`optimize2.py`、`rerender.py` | 14 | < 1 MB |
| **小计** | **37,107** | **12.2 GB** |

### 7.5 汇总

| 分类 | 文件数 | 体积 | 可执行性 |
|---|---:|---:|---|
| 仓库内·可高置信度清理 | 19,220 | 约 4.4 GB | 可直接执行 |
| 仓库内·跟踪文件迁出 | 6 | 约 11.2 MB | 需先备份存档 |
| 仓库内·需逐项复核 | 1,668 | 约 342 MB | 不可整目录删 |
| 仓库外工作区 | 37,107 | 约 12.2 GB | 需先确认 `outputs/`、`_scratch/` 是否有唯一原件 |

---

## 8. 整改建议（按优先级）

| 优先级 | 工作项 | 完成定义 | 成本 |
|---|---|---|---|
| **P0** | 修**直跑脚本的逐场景 `user://` 隔离** | 每条场景独占一个 `APPDATA` 目录；同一目录重跑不再产生假红（本次 P0 假红的根因） | 小（脚本 3 行） |
| **P1** | **剧情工具 + 设计文档同步 4 条** | 按 §0.1 方案 B、C 落地；不落地后续还会有人踩同一个坑 | 小 |
| **P1** | 裁决「开场重看」入口（§0.1 方案 D 甲/乙/丙） | 结论写入 08 §9；选乙或丙时三处（剧本 + 剧情系统本体 + Skill/文档）同步改 | 中 |
| **P0** | 修门禁跨平台缺陷 | `check_feature_traceability.py` 改 `.as_posix()`；`check_documentation_contracts.py` 随之转绿 | 一行 |
| **P0** | 统一 SHA 口径 | 决定「账本按 LF 记录」或「校验按 LF 比对」，使 `--scope full` 只剩真漂移 | 一行或重算一次台账 |
| **P1** | 处理 5 行真 SHA 漂移 | 4 行回填去版本化后的哈希；1 行核对今日改动是否已批准 | 小 |
| **P1** | 9 域指定 Owner | `ledger_index.json` 的 `owner` 不再为「待分配」 | 管理动作 |
| **P1** | 补 3 个 Skill 到正本 | `ui/audio-sfx/music-asset-pipeline` 进入 `~/.workbuddy/skills` 并全镜像同步 | 小 |
| **P1** | 巨型编排器瘦身 | 提取 Tower 生命周期、Dungeon 发放 sink、BaseManager 剩余领域服务；禁止新私有跨域访问 | 大 |
| **P2** | 10 项功能补独立主设计 | 按 `templates/feature_design.md` 的 12 字段补齐 | 中 |
| **P2** | 清 `Godot/` 个人数据与根目录孤立素材 | 存档先迁出备份，再从索引移除 | 小 |
| **P2** | `_scratch/`、`output/` 分类归档 | 被引用的脚本移入维护目录，其余归档 | 中 |
| **P2** | 运行资产去版本化 | 按既定批次消化 289/13/1 与 23/93 引用 | 大 |
| **P3** | 仓库外工作区整理 | 12.2 GB 一次性产物归档或清理 | 中 |
| **P3** | 隐藏连续爬塔恢复 | 保留实现与红项，未来重开时统一修复 | 大 |

---

## 9. 本次命令证据

**通过（退出码 0）**

- `check_verification_registry.py`：160 场景唯一归属
- `check_domain_boundaries.py`：违规 0
- `check_media_asset_domains.py`：3 域 / 73 项 / 0 问题
- `check_asset_runtime_naming.py`：无新增债务
- `check_classname_unique.py`：171 类 / 0 重复
- `check_asset_registry.py --scope structure`：410 项 / 9 账本 / 0 问题
- `verify_ledger_split.py`：410 项 / 0 失败
- 直跑 smoke 6 项（4 通过）、正式主线 12 项（**12 通过**）
- `verify_opening_script_runtime`：**退出 0 / 105 项检查**（在干净 `user://` 下单跑；见 §0.1 更正）

**失败并如实计入**

- `check_feature_traceability.py`：退出 1 / 37 项 —— **归因为工具跨平台缺陷，修正后 0/37**
- `check_documentation_contracts.py`：退出 1（嵌入上项结果）
- `check_asset_registry.py --scope full`：退出 1 / 204 项 —— **约 98% 为行尾假漂移，真漂移 5 行**
- `check_ledger_refs.py`：退出 1（悬空 49 / 待重定 21）—— 已在 2026-09-22 审计登记，带 `--allow-pending` 退出 0
- `verify_tower_lighting_wall_combat_regressions`：退出 1，已知红
- `verify_full_3d_game_flow`：退出 1（2,784 节点），已知红

**未执行（不计为通过）**

- 26 个 visual 真实渲染场景
- 1 个 manual 场景
- 目标 GPU 性能、移动端导出、30–60 分钟长测
- 完整 `aggregate core`（约 130 项）本轮未重跑

---

## 10. 本次检查的限制

1. **基线在移动**：检查期间另一会话持续提交（`66093dc2` → `bda2c828`），验收场景注册数由 157 增至 160。文中数字均标注为本次时点值。
2. **未跑完整 core**：本机 `run_verification_suite.sh` 的 `ln -s` 会退化成整工程复制（单次 5.6 GB），故采用「预检 → 直接跑场景 → `check_verification_log.py` 判分」的等价直跑；覆盖 smoke 6 + 主线 12，未覆盖全部 127 个 core。
   🔴 **本条已订正**：首版直跑批次让全部场景**共用一个 `APPDATA` 目录**，等于取消了套件的「每场景独立 `user://`」契约，直接导致 `verify_opening_script_runtime` 假红（见 §0.1）。**正确做法 = 一条场景一个 `APPDATA` 目录**。凡直跑，隔离必须由脚本自建，不能依赖调用者记得。
3. **本次诊断动作的副作用**：为排除自身环境干扰，执行过一次 `--headless --import` 刷新全局类缓存（使新增 `RunMerchantService` 被正确注册）。该动作只重建被 Git 忽略的 `.godot/`，未改动仓库内容——检查结束时 `git status` 除一条非本次产生的未跟踪脚本外为空。
4. **未修改任何玩法、资产、验收阈值或共享脚本**：本文为只读审计结论，门禁修复建议已列在 §8。
