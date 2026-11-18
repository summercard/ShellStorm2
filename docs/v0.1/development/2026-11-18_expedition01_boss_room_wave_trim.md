# 远征01 Boss 房去掉第二、第三波普通敌群

日期：2026-11-18
归属：WORLD-PLAN / ENCOUNTER-EVENT
状态：配置与文档已改；按业主明确指示本轮不做运行验收

## 1. 业主指令

> 「这两波去掉，直接去掉并且更新关卡设计文档。不用验收。」

指的是一张手机截图上标出的两行：

- 第 2 波：`box_room_spread` ＋ `box_corner_ambush`
- 第 3 波：`box_wall_arc`

## 2. 改动内容

### 2.1 设计源与运行时投影（同一份数据两处）

| 文件 | 角色 |
|---|---|
| `art_source/design/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json` | 设计源（权威） |
| `data/level_plans/expedition_01/floors/floor_00.json` | 运行时投影，逐字节同步 |

`rooms[key=boss]` 的改动：

```text
spawn_placements: 4 → 1
  [0] box_boss_arena   center_m [0.0, -22.5]   ← 保留
  [1] box_room_spread  center_m [-7.5, -15.0]  ← 删除
  [2] box_corner_ambush center_m [7.5, -22.5]  ← 删除
  [3] box_wall_arc     center_m [0.0, -32.5]   ← 删除

encounter.stages: 3 波 → 1 波
  [{"boxes":[0]}, {"boxes":[1,2]}, {"boxes":[3]}]
  ⇒ [{"boxes":[0]}]
```

保留的 `box_boss_arena.spawn_overrides` 未改：

- 0 s：`boss` ×1（显示器 Boss002）
- 1.5 s：`melee_chaser_strong` ×1 ＋ `ranged_caster_strong` ×1
- 3 s：`summoner` ×1

因此 Boss 房现在是 **1 个波次、4 个护场单位**（Boss ＋ 强化小僵尸 ＋ 强化远程 ＋ 召唤者）。

### 2.2 未改动

- `boss_reinforcement_plan`（Boss 激活完成 12 s 后东/西两侧每 9 s 投 3 只、同时最多 6 只）保持原值。
- 共享盒资产 `data/spawn_boxes/box_boss_arena.json` 未改 —— 它被 11 间房引用，改资产会波及其它房。
- `box_room_spread` / `box_corner_ambush` / `box_wall_arc` 三个盒**定义本身保留**，其它房仍在用；本轮只删 Boss 房对它们的实例引用。
- `data/level_plans/expedition_01/level_plan.json` 无 Boss 房波次副本，不需要改。
- 远征 03 的 Boss 房是另一份数据，不受影响。

## 3. 运行时会怎样

`Dungeon3D._spawn_room_enemies_impl()` 的判据是「房间有 `spawn_placements` 就只认盒子」，BOSS 房也不例外，所以：

- 进房刷出 `box_boss_arena` 的一波（盒子内延迟照旧 0 / 1.5 / 3 s）。
- 这一波清空即满足本房清房条件，结算一次清房奖励、按既有门策略放行。
- 不再出现「打完 Boss 与护场，还要再等两波普通怪」的情形。

## 4. 文档同步

| 文档 | 改了什么 |
|---|---|
| `docs/v0.1/design/远征关卡01设计.md` | Boss 投放段、§3.1 Boss 房契约表（删第二/三波两行、改清房与通行口径）、§4.5 现行分配、§4.5.0 盒数 33→30、§4.5.2 统计、§11.1 编成表 `boss#0` 行、§11 盒数 29+4→29+1、§12.7 断言口径 |
| `docs/v0.1/design/Boss002显示器技能设计.md` | 「三波」改为单波并写明被删的两波 |
| `docs/v0.1/design/触发器刷怪设计.md` | 现行盒数统计 33→30（历史段落与盒资产定义表不动） |
| `docs/v0.1/关卡接入规范.md` | 接入现状统计 29＋4=33 → 29＋1=30 |
| `data/runtime_design_data_manifest.json` | 投影脚本重算 sha256 |

## 5. 验证

按业主「不用验收」的明确指示，本轮**没有启动 Godot**，也没有做真实战斗或人工进房验证。已做的只是防止把配置改坏、防止源与投影分叉的静态检查：

| 检查 | 结果 |
|---|---|
| 两份 `floor_00.json` JSON 解析 | 通过，13 间房 |
| `LevelPlanValidator` 判据 C（盒下标不越界、不重复、每个实例都被排到） | 通过：1 个实例被 stage0 完整引用 |
| `python scripts/sync_runtime_design_data.py --check` | `{"files": 52, "issues": []}` |
| 源/投影行尾 | 源 CRLF 无孤立 LF；投影与源逐字节一致 |

未验证项（如实列出，不算通过）：

- 真实进房后的实到数量、清房判定与开门时机。
- `verify_expedition_monitor_boss_flow` 未重跑。为避免留下必红断言，已把其中硬编码的 `_room_wave_totals == 3` 改为 `== 1`、把「三波清完自动清房」文案改为「唯一护场波清完自动清房」；这是测试契约跟随设计，不是运行通过。
- Boss 房相关美术、镜头、安全地面净空均未复验。

## 6. 二次修订（同日）：护场随从也一并删除

### 6.1 业主追加指令

> 「不对啊，我刚才让你把一开始刷在 boss 房的怪物去掉，你怎么没去掉。主动增援的不要变。把 boss 房的周围那些怪物去掉。」

附带截图显示进房后 Boss 显示器两侧仍站着强化小僵尸与远程，玩家在坡道口。

上一轮理解偏了：只删了第 2、3 波，而**首波盒子 `box_boss_arena` 的 `spawn_overrides` 里还挂着 SM／SR／召唤者三条**，所以 Boss 周围那三只依旧会刷。本轮按业主原意补齐。

### 6.2 改动

`rooms[key=boss].spawn_placements[0].spawn_overrides`：

```text
改前：[boss ×1 @0s] [melee_chaser_strong ×1 @1.5s] [ranged_caster_strong ×1 @1.5s] [summoner ×1 @3s]
改后：[boss ×1 @0s]
```

设计源与运行时投影同步改，逐字节一致。

**没有动**：

- `boss_reinforcement_plan`（业主明确「主动增援的不要变」）：12 s 起、东/西两侧、每 9 s 三只、同时最多 6 只，原值保留。
- 共享盒资产 `data/spawn_boxes/box_boss_arena.json` 的 `spawns` 清单（boss + elite×2 + summoner）——它被多个关卡复用，实例声明 `spawn_overrides` 时按「完整替换当前实例清单」生效，所以只改实例即可。
- 远征 03 的 Boss 房数据（另一份 `floor_00.json`）。

### 6.3 现在的 Boss 房

| 阶段 | 内容 |
|---|---|
| 进房 | **只有 1 只显示器 Boss**，周围没有任何普通怪 |
| 3.2 剧情 | Boss 被 `story_activation_hold` 挂住，静止不出手 |
| 激活完成 | `boss_reinforcement_plan` 开始投放两侧增援（原规则不变） |
| 清房 | Boss 阵亡即满足清房条件，结算一次奖励、按既有门策略开门 |

### 6.4 测试契约跟随

`verify_expedition_monitor_boss_flow.gd`：

| 断言 | 改前 | 改后 |
|---|---|---|
| Boss 阵亡时 | `check(not room.cleared, "只击败 Boss 不跳过随从和后续波次")` | 改为统计场上是否有 Boss 以外的活物：`check(remaining_guard == 0, "Boss 房无护场随从，Boss 阵亡后场上无残留活物")` |
| 清房 | `check(room.cleared, "唯一护场波清完自动清房")` | `check(room.cleared, "Boss 阵亡即满足本房清房条件")` |

新断言比原断言更严：**只要有护场怪被加回来，`remaining_guard` 会大于 0 并立刻变红。**

### 6.5 静态验证

| 检查 | 结果 |
|---|---|
| 两份 `floor_00.json` JSON 解析 | 通过，13 间房；`spawn_overrides` 只剩 boss 一条 |
| `spawn_placements` 数 / `encounter.stages` | 1 / `[{boxes:[0]}]`（判据 C 仍成立） |
| `boss_reinforcement_plan.enabled` | `true`（未被误关） |
| 52 份投影源/运行时逐字节对比 | `MISMATCH 0` |
| 行尾 | 源 CRLF 2036、无孤立 LF |

未验证（本轮未跑 Godot）：

- 真实进房后的实到数量、Boss 阵亡到清房的延迟、开门时机。
- `verify_expedition_monitor_boss_flow` 未重跑。
- 激活后增援的实到数量与节奏未复验。
