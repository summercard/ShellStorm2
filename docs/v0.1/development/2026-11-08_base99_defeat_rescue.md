# 战败归航救援（BASE-RESCUE）开发记录 · 2026-11-08

FeatureID：`BASE-RESCUE`。玩法口径见[设计页](../design/战败归航救援与绿苔台词.md)，工程契约见[基地NPC §14](../20_技术施工_基地NPC.md)。

## 1. 来源

业主 2026-11-08 原话：远征被击败回 99F 时进入一段短剧情——玩家趴着、绿苔站在边上说两句「啧啧，太危险了，看我把你捞回来了。感谢我吧，我还帮你捞回了点东西，下次去可要小心了。」，说完玩家跳起来可操作；边上放一只浅灰箱子，开箱掉随机 1–2 件上局物品（含装备与包裹，不含保险箱）＋ 1–2 件补给（血瓶/弹药/手雷/电池），10 秒后用收租人的消失特效消失。

同轮追加：「对话可以多做几套」，并给出连败台词（2 次打趣、3 次无语）与三条随机台词。

**前提要求**：先看既有功能再动手，能复用就复用。实际复用清单见 §3。

## 2. 落地结果

| 项 | 结果 |
|---|---|
| 触发 | 远征关卡阵亡 + 入口原因 `death_return_99f` + 有救援暂存；塔楼死亡不演 |
| 演出 | 玩家钉在归航点、`dead` 剪辑相位 1.0 冻结、`set_scripted_input_hold(true)`；绿苔 `begin_scripted_appearance()` 站到侧后 1.6m 并逐句说；说完相位 1.0→0.0（1.1s）起身、归还输入、绿苔回巡逻 |
| 台词 | 固定两句 + 按连败次数追加（2 次两句、3 次一句、其余从三条随机池抽） |
| 宝箱 | `TreasureChest3D.explicit_grants` + `body_tint`（摘色盘平涂浅灰）；`spawn_transient_chest()` 不进房间账 |
| 内容 | 结算前抽 1–2 件携带物（背包槽 + 双手武器 + 装备背包，按实例排除保险格）＋ 1–2 件补给；独立随机流（种子 = 本局种子） |
| 落档 | `BaseData.rescue_cache` / `rescue_defeat_streak` 随 `commit_run_settlement()` 同事务写入、失败一起回滚 |
| 消失 | 开箱 10s 后 `VFX-TELEPORT-OUT-3D`（= 收租人撤退同一件）+ 同帧 `despawn()`，1.2s 后释放 |

## 3. 复用而非重写

| 需求 | 复用的既有能力 |
|---|---|
| 趴下 / 起身 | `PlayerAvatar3D.set_narrative_pose()`（开场剧本 `nar_tower_opening_01_wake` 同一套） |
| 逐句气泡 | `CharacterBark3D` + `SpeechBubble3D`（NPC 循环台词同一套），只新增「演出期间放宽换行」 |
| 站定 / 停巡 / 转头 | `NpcCharacter3D` 的节拍站定机制，新增三个脚本化演出入口 |
| 开箱链 | `TreasureChest3D` + `Dungeon3D._on_chest_open_requested()`（抖动→蓄力→砰→落地→房间账） |
| 地面发放 | `RewardSink.apply_ground()` 与 `_spawn_loot_items()`（不改发放协议） |
| 消失特效 | `VfxPool3D.FX01_TELEPORT_OUT` |
| 存档事务 | `BaseManager.commit_run_settlement()`（不新开第二个事务） |
| 输入独占 | `Dungeon3D._narrative_holds_player_input()`（并入同一优先级，不是另开一套锁） |

## 4. 改动文件

- 新增 `src/base3d/Base99Rescue3D.gd`（演出时序、阶段、箱子生命周期、浅灰配色常量）。
- 新增 `tests/verification/verify_base99_rescue.gd` / `.tscn`。
- `src/base/BaseData.gd`：`rescue_cache`、`rescue_defeat_streak`（含 `_to_dict` / `from_dict`）。
- `src/base/BaseManager.gd`：`commit_run_settlement()` 写暂存 + 连败计数（带 `old_*` 回滚）；`get_rescue_cache()` / `has_rescue_cache()` / `get_rescue_defeat_streak()` / `clear_rescue_cache()` / 两个 `replace_*_for_test()`。
- `src/world3d/Dungeon3D.gd`：`_plan_rescue_items()` 等抽签函数、`build_rescue_chest_grants()`、`set_scripted_input_hold()`、`_resolve_chest_grants()` 走 explicit 清单；顺带补齐工作区里 `_spawn_loot_items` 第 7 参数与缺失的 `_build_chest_spawn_positions` / `_chest_scatter_offset`（见 §6）。
- `src/world3d/TreasureChest3D.gd`：`explicit_grants` / `body_tint` / `trim_tint`、`get_explicit_grants()`、`has_explicit_grants()`、`despawn()`、快照加四项。
- `src/world3d/RewardChestVisual3D.gd`：`apply_flat_tint()`（摘 `albedo_texture`，不是压暗）。
- `src/world3d/DungeonRoom3D.gd`：`spawn_transient_chest()`（不记账的临时箱）。
- `src/world3d/TowerDescent3D.gd`：`_install_base_rescue()` / `_start_base_rescue()` / `find_base_rescue()` / `get_facility_spawn_point()`。
- `src/npc/NpcCatalog.gd`：`RESCUE_LINES` / `RESCUE_STREAK_LINES` / `RESCUE_POOL_LINES` 与取句函数。
- `src/npc/NpcCharacter3D.gd`：脚本化演出三入口 + `set_bubble_wrap_width()` + 快照三项。
- `src/player3d/PlayerAvatar3D.gd`：`get_narrative_pose_snapshot()`。
- `scripts/run_verification_suite.sh`：`core_scenes` 登记 `verify_base99_rescue`。

## 5. 验收

命令（headless，隔离 `APPDATA`/`LOCALAPPDATA` 到工程内临时目录）：

```bash
"<godot>" --headless --path . --scene res://tests/verification/verify_base99_rescue.tscn
```

结果：`BASE99_RESCUE_OK`，exit 0，日志内 `SCRIPT ERROR` / `Compile Error` 为 0。

| 断言组 | 覆盖 |
|---|---|
| R01–R02 | 固定两句逐字 == 业主原话；连败台词与随机池逐字 == 业主原话；每句 ≤ 28 字（两行口径） |
| R03 | 无暂存：`phase=idle`、不放箱子 |
| R04 | 远征真实场景里抽签：1–2 件携带物 + 1–2 件补给；`item_id == item.id`；同实例不重复；保险格那件不入选 |
| R05 | 塔楼死亡抽签返回空 |
| R06 | 趴着（`clip=dead`、`phase≈1.0`）、`input_locked` 为真、绿苔 `scripted_appearance`、离玩家 ≤ 2.6m、箱内有清单、身板无色盘贴图且 albedo ≈ 浅灰、箱子离绿苔 ≤ 1.4m |
| R07/R08 | 第一句、第二句气泡逐字 |
| R08b | 第二次连败两句按顺序出现；快照 `script_lines` 共 4 句且顺序正确；池子三档取句正确 |
| R09 | 说完交还输入、姿态清掉、`phase=chest_waiting`、绿苔结束演出 |
| R10 | 开箱后暂存清空、地面上真实出现物资 |
| R11 | 10 秒内 `phase=vanished` 且 `VFX-TELEPORT-OUT-3D` 处于激活；1.4s 后节点释放 |
| R12 | 暂存已清：重进基地不再演、不再放箱 |
| R13 | 连败计数：远征战败 +1、塔楼死亡不变、成功撤离清零 |

### 反向对照（实测会红，已还原）

| 变异 | 结果 |
|---|---|
| `_play_cutscene()` 不追加连败台词 | exit 1，R08b 报 3 条（两句未出现 + 快照只有 2 句） |
| `_place_player_prone()` 不调 `set_narrative_pose` | exit 1，R06 报「玩家没有进入叙事姿态」 |
| 箱子不传 `body_tint` | exit 1，R06 报「身板仍绑着色盘贴图」+「不是约定的浅灰 (1,1,1,1)」 |

## 6. 顺带修掉的既有阻塞（非本功能设计）

工作区里已有一段未提交的「宝箱奖励外围环带」半成品：`_deliver_ground_rewards()` 已给 `_spawn_loot_items()` 传第 7 个参数，但函数签名只有 6 个，且 `_build_chest_spawn_positions()` / `_chest_scatter_offset()` 缺失 ⇒ **整个 `Dungeon3D` 编译失败、所有塔楼/远征场景加载为 Nil**。

处理：给 `_spawn_loot_items()` 补 `presentation_context` 参数并按 `mode == "chest_arc"` 走环带落点；补齐缺失函数（严格支撑射线 + 净空球查询 + 最小间距 + 确定性种子）。普通掉落（缺省空字典）行为逐帧不变。**这部分属 WORLD-LOOT，本记录只登记"为了让本功能可验收而补齐"，不改其设计口径。**

## 7. 未完成 / 已知限制

- **真实渲染对照未出图**：玩家相机下的趴姿、3.40m 挂高 + 700px 换行的气泡、浅灰箱实际颜色都只有 headless 数值断言，没有截图。
- 演出期间鼠标仍可转向（沿用 `actor.pose` 口径：只锁玩法输入）。若观感需要"连镜头一起定住"，要走 `camera.focus` 那条时间轴能力。
- 连败计数只做语气，不做成就/统计展示。
- 玩家在开箱前退游戏：重启后按设计只放箱子不演（未单独写断言，靠 R03/R12 两条间接覆盖）。
