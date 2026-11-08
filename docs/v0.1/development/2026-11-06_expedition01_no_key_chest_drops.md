# 远征01 开门不弹命运卡 + 钥匙经济退役 + 清房/Boss 宝箱

日期：2026-11-06；记录ID：2026-11-06_expedition01_no_key_chest_drops；
功能ID：WORLD-PLAN / WORLD-GATE / WORLD-LOOT / FATE-RULES / REWARD-SERVICE；
工程版本：0.1.0（`project.godot` 未改）。

> **当前口径覆盖说明（2026-11-07）：** 本记录保留为历史施工证据，不代表当前方案。当前远征01规则是：宝箱开启只散落奖励，不直接弹命运卡购买界面；普通宝箱有 30% 概率生成命运卡专用掉落物并另掉 2—3 件消耗品；高级宝箱 100% 生成专用掉落物，并另掉 5—8 件其他物品及 1 把枪；玩家主动点击/按键交互专用掉落物后，才进入统一三选一购买事务。命运卡掉落物、奖励解析与完整运行接线仍为 `partial`。下文中“只由宝箱触发”“宝箱购买界面”等描述均属于本记录当时的历史口径。

设计依据与修订：`design/远征关卡01设计.md` 顶部新增「2026-11-06 裁定（门与掉落重排）」；
并同步 §1 目标文案、§2 循环图与门后购卡段、§3.3 Boss 表；`design/命运卡六关投放设计.md` §8 追加同日修订；
`关卡接入规范.md` 新增 §3.1.2（三段能力段）。代码基线：工作区（提交前标记工作区）。

## 1. 业主口径与改了什么

> 业主原话：「修改逻辑，玩家开门不会弹命运卡，在关卡中后期的房间，完成房间关卡后，
> 不是会掉落一个钥匙吗？这个改成掉落其他东西 有概率掉落一个宝箱（和远征03的宝箱一致）
> 然后门不需要钥匙，只要清理怪物完成自动变成可以开启状态。关卡boss击败后，掉落一个宝箱。」

| 项 | 改前 | 改后 |
|---|---|---|
| 开门 | 清房 + 消耗 1 把钥匙 + 弹命运卡三选一 | **清房即可开**：不消耗钥匙、不弹命运卡 |
| 命运卡入口 | 门后（每门必出一次，10~11 次/局） | **只由宝箱触发**（与远征03 同一套购买界面） |
| 清房掉落 | 掉 1 把 `item_room_key` | **45% 掉一只宝箱，否则掉一件清房补给** |
| 钥匙经济 | 开局 1 把、清房产钥匙、门消耗 | **整体退役**（`economy.room_keys_enabled=false`） |
| Boss | 清房后掉 1 把钥匙 | **首领阵亡必掉一只宝箱**（品质下限 `rare`） |
| 构筑机会 | 10~11 次（每门一次） | **期望 5.5 次**（清房 4.5 + Boss 1） |

## 2. 数值与公式（全部落在数据段，改一个数即可调）

| 参数 | 值 | 推导 |
|---|---|---|
| `clear_drops.content_room.chest_chance` | **0.45** | 10 间内容房 × 0.45 = 4.5；+ Boss 保底 1 ⇒ 5.5 次/局。取约一半而不是等量：宝箱额外给 2 件物资，单次价值高于门后三选一；等量则构筑强度原地不动 |
| 补给池权重 | 血瓶 40.405 : 弹药 3.045 | 沿用远征03 清房权重池（删钥匙行后的相对值）。**剔除货币** —— 本关卡价基准就是击杀收益，清房再掺货币会把基准抬高 |
| 宝箱品质权重 | common 62 / uncommon 26 / rare 10 / epic 2 | 与远征03 完全一致 |
| 宝箱掉落 | `drop_count=2`、池 `loot_floor_1_2`、`fate_card_per_open=0` | 同上；0 = 不自动发卡，改由购买界面卖 |
| 宝箱拟态 | 每箱 20% | 同上。⚠️ 本关 5.5 只箱/局 ⇒ **期望 1.1 只拟态**（远征03 只有 0.4）；要压回 0.4 就把 `mimic.chance` 设 0.07 |
| Boss 箱品质下限 | `rare` | 只提下限不动权重：同权重下 common+uncommon 占 88%，Boss 箱 88% 出普通卡与体感不符；剔除后 rare 10 : epic 2 ⇒ 83% / 17% |

**掷骰口径**：`ratio = absi(hash("run_seed|room_id|用途")) % 1000003 / 1000003`，不是运行时 RNG。
同 seed 同房恒得同一结果 ⇒ 读档、流送卸载重建、重进房间都不会让「这间房掉不掉箱子」改变。

## 3. 代码与数据变更

| 文件 | 改动 |
|---|---|
| `src/game/ClearDropService.gd`（新增） | 清房掉落纯服务：`configure / roll_room_drop`，只回答「掉什么」，不建节点、不碰钱包、不认关卡 ID |
| `src/world3d/Dungeon3D.gd` | 新增 `configure_clear_drops()`、`_ensure_room_clear_drop()`、`_ensure_boss_chest_drop()`、`_apply_clear_drop()`、`_clear_drop_offset()`；`_mark_room_cleared()` 追加清房掉落调用；`_mark_room_boss_defeated()` 追加首领箱调用；新增 `_fate_offer_price_index` / `_fate_price_door_index()` 并写进门后快照（宝箱入口按「已清内容房数」报价，门后入口口径不变） |
| `src/world3d/DungeonRoom3D.gd` | 抽出 `_instantiate_chest_node()`；新增 `spawn_runtime_chest()` / `find_chest_by_id()` / `_rebuild_runtime_chests()`；`_on_treasure_chest_opened()` 改**合并**写账（保留 `spawned/config`）；`_restore_treasure_chests()` 先按账重造运行期宝箱 |
| `src/world3d/TowerDescent3D.gd` | 新增 `_plan_door_policy` / `_plan_room_keys_enabled`，在 `_build_expedition_records()` 读计划三段；`_door_policy_for_edge()` 在固定交通接口之后、flow 默认之前返回计划策略；`_room_key_economy_enabled()` 加计划开关 |
| `src/map/FloorPlanGenerator.gd` | 计划字典透传 `door_policy` / `economy` / `clear_drops`（不进 `layout_id` canonical，不断存档） |
| `src/framework/GameDesignConfig.gd` | 远征01 目标文案：「穿过命运之门」→「开启宝箱构筑命运」 |
| `art_source/design/whitebox/tower_zones/expedition_01/v001/data/level_plan.json` | **设计源**新增 `door_policy`、`economy`、`clear_drops` 三段（含推导说明） |
| `data/level_plans/expedition_01/level_plan.json` | 由 `sync_runtime_design_data.py` 投影（逐字节一致） |
| `tests/verification/verify_expedition_level01_flow.gd` | `_verify_door_policies` 改为断言「全门免钥匙、不弹命运卡」，并**补上此前从未检查的 `room_10→boss` 与 `boss→extraction` 两条边**；`_verify_fate_on_door` 改为断言「开门不弹卡 / 不扣钥匙 / 清房不掉钥匙」；新增 `_verify_clear_drops`（逐房比对服务掷骰与世界状态）与 `_verify_boss_chest` |

**为什么用能力段而不是关卡 ID**：三段都是「写了才生效、不写逐字不变」。
`Dungeon3D`/`FloorPlanGenerator` 里没有出现任何 `"expedition_0N"` 字面量，
`TowerDescent3D` 作为关卡装配器只读计划数据。`check_level_decoupling.py` 见 §5。

## 4. 存档与恢复

- 运行期宝箱的账在房间层（`treasure_chests[chest_id] = {spawned, opened, config, offset, rotation_deg}`），
  走既有 `get_persistent_detail_state("treasure_chests")` 采集 ⇒ 房间流送卸载重建、读档都能原样重造。
- `_on_treasure_chest_opened()` 原来是**整条覆盖**，会把 `spawned/config` 冲掉；
  后果是「开过的清房宝箱走远再回来整个消失」。现改为合并写，`verify_clear_drops` 有一条断言盯着 `spawned`。
- 门后快照新增 `price_index`；旧档没有该键 ⇒ 0 ⇒ 退回门序号口径，冻结报价本身仍随 `quotes` 恢复，不受影响。

## 5. 验收

**执行方式**：在正式工程目录内、临时把用户目录切到 `ShellStorm2TmpVerify` 跑单场景（跑完已还原
`project.godot` 并删除该用户目录）。未走 `run_verification_suite.sh`（整套会整份复制约 5 GB 导入缓存）。

| 项 | 结果 |
|---|---|
| `verify_fate_economy_service` | **退出码 0，`checks=398 failures=0`**（该场景原来靠「开门」拿报价，已改为宝箱入口并反向断言开门不弹卡） |
| `verify_expedition_monitor_boss_flow` | 退出码 1，**49 checks / 3 failures**，3 条均为既有数据漂移：`monster_rules.stats.per_kind.boss.hp=32000` 而断言写 52000、`box_boss_arena.center_m=[0,-22.5]` 而断言要求房心、波次数断言仍按旧编成。本轮改写的五条（撤离门清房门槛 / 免钥匙 / 不弹卡 / Boss 房不掉钥匙 / 首领箱存在）**全部通过** |
| `verify_expedition_level01_flow` 退出码 | **1（非本功能原因）** |
| 本功能新增/改写的断言 | **全部通过**：全门 `requires_key=false` / `triggers_fate=false` / `requires_clear=true`；`_room_key_economy_enabled()` 为假；开门不弹卡、不扣钥匙；清房不掉钥匙；`CLEAR_DROP_SAMPLE rooms=3 chests=1`（掷骰与世界状态逐房一致）；Boss 箱存在且品质 ≥ rare |
| 既有红项（与本功能无关，未修） | ① `缺少两个立体入口`；② `读取界面标题不是远征关卡01：CloseAI数据库`（11-02 改名未同步断言）；③ `怪物掉落表应有 13 行，实际 11`（设计源本身就是 11 行）；④ `Expedition 区块 display_name 不正确：CloseAI数据库`；⑤ room_06/07/10 墙体碰撞格心缺失；⑥ `collision_shape_count` 与实测形状数不一致 |
| `python scripts/check_level_decoupling.py` | **退出码 0，violations 0**（7 个通用机制容器，无 `"expedition_0N"` 字面量） |
| `python scripts/sync_runtime_design_data.py --check` | **52 文件 0 issues**（设计源与运行目录逐字节一致） |
| `python scripts/check_documentation_contracts.py` | 退出码 0；`issues` 均为既有项（14 条断链 + `openpyxl` 缺失导致 media domain 检查未执行），本轮新增文档未产生新断链 |

## 6. 门禁与未执行项

- **未执行**：整套 `core` 套件（整套会整份复制约 5 GB 导入缓存，本轮按场景逐个跑）；
  真实渲染手测（宝箱抖动/掉落/购买界面在画面上的观感）；拟态箱端到端（掷到拟态后击杀掉落的完整链路）。
- **携带钥匙的口径没动**：`verify_expedition_departure_carry` 仍按快照把 `room_key_count` 带进远征。
  本关已无消费口 ⇒ 这些钥匙进关后是「拿得到、用不掉」的死道具。不改它是因为交接契约是跨关通用的，
  为一个关卡的消费口消失去改交接语义，会让塔楼与远征02 一起受影响；要清就单独开一条「无钥匙关卡的
  携带裁剪」裁定。
- 远征01 门禁的既有红项（§5 表里 6 条）与本功能无关，未修也未放宽。
- 同轮 `sync_runtime_design_data.py` 顺带把 `art_source/.../expedition_03/v001/data/flows/`（另一会话的
  **未跟踪**设计源）投影进 `data/level_plans/expedition_03/`。这是「设计源为权威」的既定行为，不是本功能改动。
