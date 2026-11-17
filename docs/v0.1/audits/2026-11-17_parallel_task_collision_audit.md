# 并行任务文件冲突审计（2026-11-17）

范围：`0.2` 分支工作区未提交改动（43 文件 / +1326 −205）与 `1e29d9fd` 自动提交。
性质：**只读排查**，未修改任何代码、设计或账本。
结论一句话：**不是单点污染，而是「任务本身跨功能」＋「Dungeon3D 单文件承担多域」＋「登记册全局单点」三者叠加；执行层另有 4 处硬伤（测试错挂 1、索引断链 1、跨功能文档合写 2），门禁因只查「存在性」不查「唯一性」而全绿。**

---

## 1. 事实基线

- 未提交改动集中在 4 条互不相同的事务线：枪线/护枪剧情、豌豆容量校正、胖子僵尸 2.1 换皮、远征01 刷怪与清房。
- `1e29d9fd`（2026-11-17 04:04，265 项）已把「武器构筑全息 UI」「命运卡教程」「远征01 战斗手感」以及四套敌人美术源压进**同一个 commit**。自动提交使用全工作区暂存，**并行任务在提交点被迫合并，事后无法按功能回滚或归因**。
- 当前 `python scripts/check_feature_traceability.py` 输出 `FEATURE_TRACEABILITY_OK features=46 issues=[]`；`check_domain_boundaries.py` 仅拦 3 条固定模式（`BaseManager.data` / `_ensure_data` / `VfxPool3D._REGISTRY`）。两门禁都**不具备**发现本次问题的能力。

---

## 2. 三个问题的逐条回答

### 2.1 是否两个不同功能的代码在互相污染

**部分是，但不是主因。** 直接代码污染只有一处（`Dungeon3D.gd`），其余是登记层污染。

| 共享文件 | 任务 A 改了什么 | 任务 B 改了什么 | 性质 |
|---|---|---|---|
| `src/world3d/Dungeon3D.gd` | `_restore_pending_door_fate_overlay` 追加 `restore_offer_assembly`；`_purchase_fate_card` 追加 `notify_weapon_assembled`；`_finish_fate_overlay_exit` 追加 `notify_offer_exit_completed` | `_on_encounter_event_finished` 去掉易失索引门禁；`_try_settle_encounter_room_clear` 改为重算；新增 `_synchronize_room_clear_live_count` | **必然冲突**：同一文件、不同函数，Git 能自动合并，人工无法分离回滚 |
| `docs/v0.1/MODULE_INDEX.md` | 顶部新增 1 条 | 顶部新增位置相同 | 设计性冲突：约定「新记录插到第 1 行」 |
| `docs/v0.1/development/CHANGELOG.md` | 顶部新增 1 条 | 顶部新增位置相同 | 同上 |
| `docs/v0.1/development/README.md` | 顶部新增 1 条 | 顶部新增位置相同 | 同上 |
| `docs/v0.1/feature_registry.json` | `updated_at` 单值 + 4 个 feature 的 verification/development 列表 | 同一字段 | 结构冲突：日期是单值，无法表达多事务 |

### 2.2 还是任务本身就会动到其它功能

**这是主因，两条任务都是天然的跨功能任务。**

- **任务 A 横跨 4 个 FeatureID**：`WEAPON-COMBAT` / `FATE-RULES`（装配台连线与槽位）、`NARRATIVE-TRIGGER`（新剧情 `nar_tutorial_fate_assembled_01`）、`DIALOGUE-UI`（新对白的 wait 屏障）、`VFX-POOL`（socket impact）。「装配完成后退出 + 补一段剧情」在语义上就不可能只落在一个模块。
- **任务 B 横跨 4 个 FeatureID**：`WORLD-PLAN`（时长/批次/HP 数据）、`ENCOUNTER-EVENT`（冻结相位与截止行为）、`WORLD-LOOT`（清房出箱）、`SAVE-RUN`（快照恢复）。HP 与时长改动**本身是干净的**，落在 `data/level_plans/expedition_01/level_plan.json`（hp 99/198/150/18000）与 `floors/floor_00.json`（duration 40.0），与任务 A 零交集。
- 唯一无法避免的物理交汇就是 `Dungeon3D.gd`：**14405 行 / 586 个函数 / 262 个状态字段**，在 `MODULE_INDEX` 中被 `WORLD`、`WORLD-LOOT`、`WORLD-SECRET`、`ENCOUNTER-EVENT`、`BASE-RESCUE`、`NARRATIVE-TRIGGER` 等多行同时列为实现宿主。

即：主人要求的「功能模块可独立维护」在 `Dungeon3D` 这一层**从未成立**。

#### 2.2.1 `Dungeon3D` 内部的实际模块划分（按字段归属实测）

| # | 模块 | 字段数 | 核心入口（行号） | 职责 |
|---|---|---|---|---|
| 1 | 世界与房间装配 | 34 | `_create_secret_branches` L3857、`set_room_seal` L5034、`_spawn_room_enemies_impl` L5095 | 房壳、门扇、流送卸载、支线子图、传送 |
| 2 | 遭遇事件与刷怪 | 20 | `start/cancel/advance_encounter_event`、`get_encounter_event_snapshot` L1914–1932 | Director 编排、存活账 `_alive_by_room` L363、预约 `_reserved_room_spawns` L427 |
| 3 | 清房与掉落结算 | 14 | `_mark_room_cleared` L9625、`_ensure_room_clear_drop` L9796 | 清房判定、宝箱落地、击杀计数 |
| 4 | 命运卡购买与全息构建板 | **48** | `_purchase_fate_card` L10799、`_finish_fate_overlay_exit` L11361、`_fate_economy` L200 | 报价冻结、候选、成交、投影收放 |
| 5 | 存档快照与恢复 | 8 | `build_runtime_save_snapshot` L1081、`_restore_runtime_world_save_snapshot` L1645 | 运行快照、段级恢复、读档重放 |

**需修正上一轮的措辞**：「剧情教程」不是第五个模块。它只有 8 个字段，且集中在 4 根回调上（`notify_offer_open` / `restore_offer_assembly` / `notify_weapon_assembled` / `notify_offer_exit_completed`），寄生在命运域内。按字段规模，真正的第二大块是**玩家/HUD/模态（47 字段）**，严格说应算第 6 块。

**耦合机制不是共享可变状态**：被 ≥3 个域写入的字段仅 3 个，全部是「命运卡 → 掉落」的桥接量 —— `_room_key_count`、`_extra_loot_next_chest_count`、`_next_chest_quality_boost`。真正的问题是**跨域编排链写在同一文件**：

- 遭遇收尾链：`_on_encounter_event_finished` L1954（第 2 域区）→ `_try_settle_encounter_room_clear` L1992（第 2 域区）→ 写第 3 域的账并调 `_mark_room_cleared` L9625。改第 3 域必然回头动第 2 域这两段。
- 命运恢复链：`_restore_pending_door_fate_overlay` L1374 位于第 5 域（存档区），执行的却是第 4 域（命运）的账。任务 A 恰好改的就是这一个。

两任务在本文件内的实际落点：任务 A 在 L1374 / L10799 / L11361；任务 B 在 L1954 / L1992 / L2013。**行距最近 580 行，零重叠**。因此冲突不在代码，而在：同一文件 → 任一方语法或运行错误即令对方验收全红；共用验收与账本 → 串行排队。

#### 2.2.2 归属澄清：领域规则本来就不在 `Dungeon3D`

`Dungeon3D` 的定位是**关卡模块 / 调度器**，领域规则另有宿主，实测如下：

| 关注点 | 真正宿主 | `Dungeon3D` 的角色 |
|---|---|---|
| 命运卡规则（候选、方位、作用域） | `src/weapons/FateCardEngine.gd`、`FateOfferPolicy.gd`、`FateCardPresets.gd`、`TarotFateCatalog.gd` | 只调用（`FateOfferPolicy.allows(...)`、`_fate_economy.*`） |
| 命运经济与报价 | `FateEconomyService`（独立实例 `_fate_economy` L200） | 只调 `configure_from_runtime` / `frozen_quote_for_card` |
| 怪物属性数值 | `src/enemy3d/Enemy3D.gd` `PROFILES` L290 + `data/level_plans/expedition_01/level_plan.json` `monster_rules` | 只透传 `set_monster_rules` / `_ai_param` |
| 构建板 UI | `src/ui/weapon_build/` 共 10 个独立脚本 | 只 `load` 两个（`FateHologramPresentation` L10113、`FateIrreversibleConfirm` L10817） |

**因此「构建板属于 HUD 所以撞车」不成立**：构建板早已独立成目录，任务 B 全程零触碰 UI。构建板不是本次冲突来源。

`Dungeon3D` 内那 48 个 `fate_*` 字段是**本局状态**（这次这个门刷了哪三张、买了没、报价冻结值、pickup 认领账），属于关卡实例，放在关卡运行时装是合理归属 —— 不是「规则错放」。

#### 2.2.3 真因：命运域缺事件总线

对比两域的对外接口：

| 域 | 信号 | 剧情/外部如何感知 |
|---|---|---|
| 遭遇域 | ✅ `encounter_event_started` L33、`encounter_event_stage_started` L34、`encounter_event_finished` L35 | 订阅信号即可，无需改 `Dungeon3D` |
| 命运域 | ❌ **一个都没有** | 只能反向依赖，见下 |

因为没有 `fate_card_purchased` / `fate_offer_exited` 信号，剧情模块要感知购卡时刻只剩两条路，两条都是越界：

1. **让关卡模块反向 `call` 剧情模块** —— 任务 A 被迫改的正是这三处：`_purchase_fate_card` L10837 `call("notify_weapon_assembled", ...)`、`_finish_fate_overlay_exit` L11352 `call("notify_offer_exit_completed", ...)`、`_restore_pending_door_fate_overlay` L1394 `call("restore_offer_assembly", ...)`。
2. **反射读关卡私有字段** —— 既有债，已存在：`src/narrative/FateTutorial3D.gd` L121–122 `host.get("_door_fate_choices")`、`host.get("_door_fate_purchased")`。

结论：任务 A 碰 `Dungeon3D` **不是功能放错位置，而是当时没有别的路可走**。这是「缺事件总线」而不是「模块归属错误」。

**修法（不动玩法）**：给 `Dungeon3D` 补两个只出信号 —— `fate_card_purchased(evidence)` 与 `fate_offer_exited(offer_id, purchased)`，再补一个只读查询 `get_fate_offer_view()` 替代反射读。落地后任务 A 只需改 `FateTutorial3D.gd`（本已独立）+ 订阅信号，**完全不碰 `Dungeon3D`**，两任务即可真并行。这也是把「剧情教程寄生在命运域」解耦的唯一低风险动作。

### 2.3 两条任务有没有按要求执行

**有 4 处明确违规，可以逐条指认。**

| # | 问题 | 证据 |
|---|---|---|
| 1 | 测试被复制到无关功能名下 | `verify_pistol_fate_capacity`（豌豆槽容量）被同时登记进 `WEAPON-COMBAT`、`FATE-RULES`、`NARRATIVE-TRIGGER`、`DIALOGUE-UI` 四个 feature 的 `verification`。容量测试与对话 UI、剧情触发无关，属复制粘贴式归属。 |
| 2 | 索引断链（孤儿条目） | `CHANGELOG.md` 与 `development/README.md` 均新增链接 `[小僵尸v007抬头与双红眼](2026-11-17_small_zombie_v007_eyes_head.md)`，但该文件**不存在**（目录内只有 `2026-11-16_small_zombie_v006_integration.md`）。另一个并发会话写了索引却没有落记录文件。 |
| 3 | 跨功能合写同一节 | `09_技术施工_存档结算与复活.md` 的节标题被改成「命运教学完成历史与豌豆容量兼容」，把叙事完成历史与武器槽容量两条无关规则塞进一节；该文档 FeatureID 为 `SAVE-PROFILE / WORLD-LOOT / NARRATIVE-TRIGGER / WORLD-ENTRY`，**不含** `FATE-RULES / WEAPON-OWNERSHIP`。 |
| 4 | 表现章节承载数值规则 | `04_技术施工_战斗与局内成长.md` §13.0 标题改为「接线与护枪收口」，正文塞入 §5.1 豌豆 4/6/8 容量规则与 `RewardService` 改动顺序。容量规则本应只留在 §5.1 与玩法设计页。 |

---

## 3. 判定：三类原因占比

- **架构单点（约 55%）**：`Dungeon3D.gd` 承担世界/房间/遭遇/命运购买/剧情教程五种职责，任何跨功能任务必然落到同一文件。
- **任务天然跨功能（约 30%）**：两条任务各自都要 4 条功能线协同，无法压成单模块改动。
- **执行违规（约 15%）**：测试错挂、索引断链、跨功能合写。这部分是纯粹的失误，与架构无关。

**「两个任务互相写坏了对方代码」不成立**：函数级不重叠，无逻辑互相覆盖。实际发生的是**在同一个工作区、同一批文件上串行排队**，导致谁先落盘谁阻塞另一个。

---

## 4. 门禁为何全绿

`check_feature_traceability.py` 校验的是「FeatureID → 设计页 → owner → 开发记录 → 验收入口」这条链**是否都存在**，不校验「一个验收入口是否只属于一个功能」；断链的 small_zombie 记录没进 `feature_registry` 的 development 列表，因此不在扫描范围。`check_domain_boundaries.py` 只拦 3 条字符串模式，不分析文件级职责归属。二者对本次四类问题**均无检出能力**。

---

## 5. 建议（本次不改，供裁决）

1. **补命运域事件总线（最高优先，且是唯一能让两任务真并行的动作）**：`fate_card_purchased` / `fate_offer_exited` 两个信号 + `get_fate_offer_view()` 只读查询，替掉 `FateTutorial3D` 的反射读与 `Dungeon3D` 的反向 `call`。代价约两个方法，不动玩法、不动存档。
2. **把 `Dungeon3D` 的「遭遇收尾」搬成独立协作者**（如 `EncounterSettlementService`），宿主只留转发。注意：遭遇域**已有信号**，所以这条比命运域容易；真正卡住的是第 3 域的清房账，需先定义其唯一所有者。
2. **登记册改为按日期分文件 + 生成索引**：`development/2026-11-17/<事务>.md` 各自独立，`CHANGELOG` / `README` / `MODULE_INDEX` 顶部条目改由脚本汇总生成，消除「每条新记录都插第 1 行」的必撞结构。`feature_registry.updated_at` 改为数组或去掉。
3. **给自动提交加事务边界**：`git add -A` 前按 `docs/v0.1/development/<当日>/` 或改动文件集合分组提交，禁止把 4 条功能线压成一个 commit。
4. **补两条会失败的门禁**：① 一个 `verification.id` 只允许出现在一个 feature 下（`shared: true` 需显式声明）；② `CHANGELOG` / `README` 中所有 `development/*.md` 链接必须存在。
5. **跨功能任务开工前先写一份「交汇声明」**：列出本次会碰的共享文件与顺序，先占位再动手，避免两个会话在同一小时里各自追加顶部行。

---

## 6. 本次未做的事

未修改任何源码、设计文档、账本或测试；未运行会写盘的验收；未清理工作区（含 `_probe_loop.txt` 等临时文件）。
