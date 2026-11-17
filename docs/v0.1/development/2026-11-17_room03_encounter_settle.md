# 三号房倒计时收尾补判：完毕不出箱、门不解封

- 日期：2026-11-17；工程版本 0.1.0。
- FeatureID：`ENCOUNTER-EVENT / WORLD-PLAN / WORLD-LOOT / SAVE-RUN`。
- 来源：业主截图与描述「三号房打完倒计时怪后，没有触发出现箱子和门可以打开，被困在这里了」，并要求从关卡设计链路排查。上一段同名对话已定位到代码却没留交付记录，本轮重做并从「设计契约 → 运行证据 → 反向对照」三段收口。
- 主设计：[触发器刷怪 §10.5.2](../design/触发器刷怪设计.md)、[远征01 §11](../design/远征关卡01设计.md)、[关卡接入规范](../关卡接入规范.md)。本轮在 §10.5.2 补了一条「收尾判据」契约（完成事实只认 Director 快照、宿主按同一口径重算存活、允许读档补跑），设计正文只写规则，不写本轮日志。
- 状态：**逻辑修复与专项通过（122 项 0 失败）**；同套件其余段落存在 54 条既有红项（room_09 六结果遭遇），修复前后为同一集合，不是本轮引入。不提高 `ENCOUNTER-EVENT` / `WORLD-PLAN` 的 partial，不提交、不推送。

## 1. 现象与关键证据

症状是两个一起消失：`room_03` 清空最后一只怪，宝箱不落、房间门仍不可开（`sealed` 未解）。

11:22 的调试运行留下了决定性一行（`_scratch` 外的工程外日志，见 §4 证据表 R0）：

```
FLOW_INTEGRATION_ROOM03_FINAL status=completed terminal=true elapsed=40.0
  active=room_encounter:room_03#1 alive=0 reserved=0 nodes=0
  cleared=false sealed=true
```

`status=completed` / `alive=0` / `nodes=0` 说明**事件确实结束了、场上也确实没怪**；`cleared=false` / `sealed=true` 说明房间没走清房链。即「结束事实成立了，但收尾没执行」。

## 2. 根因：把两份易失状态当成了完成判据

链路是 `EncounterEventDirector3D._finish_instance()` → `Dungeon3D._on_encounter_event_finished()` → `_try_settle_encounter_room_clear()` → `_mark_room_cleared()`（出箱、解封、开门、奖励结算都在最后一环）。中间有两道门禁，用的都是**会被别人擦写的易失状态**：

| 位置 | 门禁 | 为什么不可靠 |
|---|---|---|
| `_on_encounter_event_finished` | `_room_encounter_active.has(room_id)` | 该表同时被 `_mark_room_cleared()`（清房即 `erase`）、读档恢复、流送卸载改写。它为空时整段回调被静默跳过 —— 连 `_try_settle` 都不会调用 |
| `_try_settle_encounter_room_clear` | `_alive_by_room[room_id] > 0` | 这是**增量账**：只由击杀/取消逐笔 `-1`。自爆连杀、休眠卸载、读档重放里任何一次漏销都会留下永远清不掉的幽灵计数 |

`_alive_by_room` 与实际实体脱钩时，Director 按自己那份权威计数（`EncounterEventHost3D.encounter_event_live_count()`：真实节点 + 休眠房间快照 + 在途预约）判定 `completed`，Dungeon 这边按幽灵计数判定「还有怪」，于是**事件结束但房间永远不清**：不出箱、不解封、门打不开。这与设计 §10.5.2「清零才完成、出箱解封沿原清房链」直接冲突。

## 3. 改动

只改 `src/world3d/Dungeon3D.gd` 两处 + 新增一个重算函数，不碰数据、Director、冻结时长与门扇表现。

1. **完成回调去门禁**：`room_id` 为空仍按老路径早退；其余一律以 Director 快照为准。保留 `instance_id` 比对，旧实例的迟到回调不吞新事件（记 `encounter_event_finished_stale` 存档原因）。`status != completed` 的解封行为不变。
2. **清房判定改为重算**：新增 `_synchronize_room_clear_live_count(room_id)`，按「已实例化节点（排除 `ai_state == "dead"` 与不计清房的精英/拟态箱）＋ 房间未流送时的休眠快照 ＋ `_reserved_spawn_count`」重算，并把结果**写回** `_alive_by_room`。口径与 Host 的 `encounter_event_live_count()` 对齐 —— 同一批事实不能一边按节点算、一边按增量账算，否则两边永远打架。
3. 幂等：`_try_settle_encounter_room_clear` 仍以 `room.cleared` 收口，重复调用不会二次出箱；`_mark_room_cleared` 内部的 `call_deferred("_ensure_room_clear_drop")` 保持不变。
4. **旧档自愈**：`_restore_runtime_world_save_snapshot()` 末尾 deferred 调 `_settle_orphaned_completed_encounters()` —— 遍历房间，只有「`room_encounter:<room>` 已在 `_encounter_event_completed_history` 里 + 房间未肃清 + 存活重算为 0」三条同时成立才补跑清房链。已经卡死的老存档（门锁着、地上没箱）读档即恢复，不需要重打；未完成或有活体的房间一律跳过。

不改的部分（有意为之）：不自动推开/打开门板（设计明写「出箱解封但不自动推门」，解封后由 `TowerDescent3D._on_room_unsealed()` 把门设为 `openable`，玩家按 E 开）；不放宽 `max_alive`；不改 40 秒窗口与末波循环语义。

## 4. 专项同步（`verify_expedition01_flow_integration`，manual）

原专项还停在 2026-11-11 的「60 秒 / 固定 5 批 36 只 / 无冻结」口径，与 11-16 冻结的 40 秒循环规则不一致，会先红在配置断言上。本轮按现行数据与设计改：

- 配置：`duration_sec=40`、`preparation_sec=0`、`freeze_player_sec=1`、`start_delay_sec=2`、`intermission_sec=0`、`max_alive=8`；五个限时房（03/04/06/09/10）同一组断言。
- 时序：先 `tick(1.0)` 走完触发冻结（此期间 `alert_phase=trigger_freeze`、`alert_remaining_sec=0`），第 2 秒首批 5 只。
- 批次：前两批严格 5 / 7；第三批模板 9 被 `max_alive=8` 截断成 `8 + 1`（这是设计「cap 不提高」的必然结果，不是掉怪），随后按末模板 8 循环。
- 截止：`tick` 到 39.99 不关派发，40.0 关派发进 `cleanup`，**残怪保留**、不完成、不解封。
- 收尾：残怪清零后必须 `completed` + 真实 `cleared` + 解封 + **自动落箱**（手动补调之前就要成立，业主报告的就是「地上没箱子」）。
- 新增**幽灵计数回归**：在残怪清零前把 `_alive_by_room` 人为抬高 2（模拟漏销，场上无对应实体），要求收口按真实节点重算 —— 这是本轮唯一能直接咬住业主症状的断言。

### 验收结果

| 编号 | 命令 / 场景 | 隔离 | 结果 | 退出码与证据 |
|---|---|---|---|---|
| R0 | 上一段对话 11:22 调试运行（复现用，非本轮） | 专用隔离 | 复现 `status=completed / alive=0 / cleared=false / sealed=true` | exit 1；`ShellStorm2-work/verification/shellstorm-verification.room03-debug4-1794885776/run.log` |
| R1 | `python _scratch/run_room03_only.py r5`（仅三号房段） | `shellstorm-verification.flow_integration_room03-r5`，Autoload 前隔离 | **通过：`FLOW_INTEGRATION_OK checks=122 failures=0`**；`spawned=29 peak=8 kills=29 cleared=true sealed=false chest_count=1` | exit 0；`ShellStorm2-work/verification/shellstorm-verification.flow_integration_room03-r5/run.log` |
| R1b | `python _scratch/run_room03_only.py r7`（加旧档自愈后复跑） | `…flow_integration_room03-r7` | **通过：`FLOW_INTEGRATION_OK checks=122 failures=0`** | exit 0；`…flow_integration_room03-r7/run.log` |
| R2 | 反向对照：换回修复前 `Dungeon3D.gd` 跑同一专项 | 同上 | **按预期变红 6 条**：`alive_by_room=2 reserved=0 nodes=0 cleared=false sealed=true chest=0`；`03截止残怪清零后必须completed…`、`03清房必须真实实例化唯一奖励宝箱：0` 等 | exit 1；`…flow_integration_room03-rev1/run.log` |
| R3 | `python tests/verification/run_expedition01_flow_integration.py verify_expedition01_flow_integration --standard-isolation`（完整套件） | `shellstorm-verification.flow_integration_verify_expedition01_flow_integration` | 662 项 54 失败：**三号房 0 红**；54 条全部来自 `verify_event_handler_orders()`（room_09 六结果遭遇） | exit 1；`_scratch/full_suite_final.log` |
| R3b | 加旧档自愈后再跑一次完整套件 | 同上 | 662 项 54 失败；与 R3 的失败集合**逐条同集合**（`IDENTICAL_SET`），三号房 0 红 | exit 1；`_scratch/full_suite_final2.log` |
| R4 | 反向对照：修复前跑完整套件 | 同上 | 661 项 60 失败 = 同一组 54 条 + 三号房 6 条 | exit 1；`_scratch/full_suite_prefix.log` |
| G1 | `python scripts/check_level_decoupling.py` | 7 个通用机制容器 | 通过：0 violation | exit 0 |
| G2 | `python scripts/check_verification_registry.py` | 313 场景 | 通过：smoke6/core246/visual42/manual19 | exit 0 |
| G3 | `git diff --check` | 本轮补丁 | 通过（仅既有 CRLF 提示） | exit 0 |
| D1 | `python scripts/check_documentation_contracts.py` | 605 文档 / 3253 本地链接 | exit 1，14 条断链，**新增 0**：11 条是既有旧断链，另 3 条是并行会话引用已缺失的 `2026-11-17_small_zombie_v007_eyes_head.md`（CHANGELOG:7、README:7、audit:48）。本轮三处新链接（CHANGELOG / README / MODULE_INDEX）均未出现在 issue 中 | exit 1；JSON issue 列表见运行输出 |
| V1 | 真渲染 / 实机走一遍三号房 | 未执行 | 待验收 | 不以 headless 代签 |

结论口径：R3 与 R4 逐条对比，**本轮新增红项 0、消除 6 条**（全部在三号房）。

## 5. 影响面与兼容

- 只影响「遭遇事件完成 → 房间肃清」这一条收尾路径。非遭遇房（`preplaced` 盒式房）、Boss 房、事件房（EVENT 型另需终端结算）判据未改，`_mark_room_cleared` 内部顺序未改。
- 存档 schema 未动（`BaseData 2.0`）。`_alive_by_room` 是运行时账，不落盘字段，写回只修内存真值。
- 旧局自愈：读档时 `_settle_orphaned_completed_encounters()` 会替已卡死的房间补跑清房链（判据见 §3.4），因此业主手上那份「打完没箱没门」的存档**读档即可恢复**，不必重打。这是**运行时自愈**，不是存档字段迁移：`BaseData 2.0` 与 `room_encounter_flow` 的 schema 一个字没改，也没有 `if 版本 < n` 分支。若房间还留着活体，自愈不动它，需要玩家自己打完。

## 6. 遗留与未覆盖

1. `verify_event_handler_orders()`（room_09 六结果遭遇）54 条既有红项：`六结果遭遇启动失败`、`actual=0`、`未结算终端就放行`。修复前后同集合，与本轮无关，需另立事务排查 `room_09` 的 `_start_room_encounter` 拒绝原因。
2. 三号房第四批只到 1 只（模板 9 被 `max_alive=8` 截断后的余量）：属设计「cap 不提高」，但实际体感是「第三波后突然只有 1 只」，是否需要调整模板应由设计侧裁定，本轮不改数值。
3. 真渲染与真人操作未验：本轮全部是 headless 逻辑证据，箱子出现的视觉反馈、门扇 `[E] 开启` 提示仍需真窗口确认。
4. 五房（04/06/09/10）只做了配置透传断言，未逐房跑完整 40 秒窗口；它们的清房收尾与 03 共用同一条链，但没有独立运行证据。
5. `_scratch/run_room03_only.py` 是收敛证据用的临时隔离 Runner（`--room03-timed-only`），未登记进 verification registry；正式登记仍以 `tests/verification/run_expedition01_flow_integration.py` 为唯一入口。
6. 旧档自愈路径（`_settle_orphaned_completed_encounters`）目前只有「跑完全套件不掉链」的间接证据，**没有独立断言**盯住「历史有 completed + 房间未清 + 零存活 ⇒ 读档后自动清房」这条修复。另需注意：r6 那次运行在 `_commit_floor_bundle` 阶段超时 900 秒被杀，同一命令重跑（r7）正常，判定为机器瞬时争用，不是本次改动引入的循环。
