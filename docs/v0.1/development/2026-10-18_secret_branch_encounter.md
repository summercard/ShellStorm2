# 2026-10-18 子图遭遇编成：每间固定 5 强化 + 2 普通

关联：[支线秘密房间设计 §7](../design/支线秘密房间设计.md)、[05 §5.5](../05_技术施工_关卡生成与爬楼.md)、[完成度清单](../12_全游戏完成度清单.md)

## 1. 裁定

> 「不用加掉落加成 子图里 固定刷每个房间里有 5 只强化怪物和两只普通怪物。」

因此本期的口径是三句话：

1. **数量写死**：每间子图房 5 只强化怪 + 2 只普通怪，不随楼层 / 进度 / 已清房数漂移。
2. **不加掉落加成**：收益就是这 7 只怪的常规击杀掉落。
3. 主图那套刷怪规则（波次、钥匙、命运卡、房间奖励结算）**一条都不进子图**。

## 2. 实现位置

| 环节 | 位置 | 说明 |
|---|---|---|
| 编成 | `MonsterInjector.build_secret_branch_encounter()` | 唯一真源；5 强化 + 2 普通，按种子轮转怪种 |
| 触发 | `SecretBranch3D._on_branch_room_player_entered()` | 只把「玩家进了哪一间」上报给上层 |
| 刷怪 | `Dungeon3D._on_secret_branch_room_entered()` → `_spawn_secret_branch_room_enemies()` | 切 `_current_room_id` + 调 `_spawn_enemy_batch` |
| 清房 | `Dungeon3D._on_secret_branch_room_cleared()` | 由 `_resolve_room_enemy_departure` 在存活归零时进入 |
| 查证 | `Dungeon3D.secret_branch_encounter_snapshot()` | 逐间存活数 / 怪种 / 是否已清 |

## 3. 四个坑（都是「看起来对、跑起来不对」）

### 3.1 强化档位必须关掉 15% 掷骰

`_generate_basic_enemy` 的默认出口会按 `monster_rules.strong_variant.chance` 把普通怪升级成强化怪。
如果编成走默认参数，那 2 只「普通怪」各有 15% 概率变成强化怪 —— 玩家数出来是 6 强化 + 1 普通，
「每间 5 + 2」当场破功。所以两头都显式 `allow_strong = false`：强化那边传的是变种 id（本来就免疫），
普通那边靠这个开关钉死。

### 3.2 不切 `_current_room_id`，怪会站着不动

`MonsterAIManager._target_is_legal()` 只允许「本房敌人」把玩家当目标：
`_current_room_id == enemy.room_id`。子图房间不在 `_records`，进房不会走 `_on_room_entered`，
`_current_room_id` 会一直停在主图房间上。

现象很迷惑：怪刷出来了、血条也在，就是不追人、不攻击。

`_spawn_enemy_batch` 里的 `enemy.set_runtime_active(room.room_id == _current_room_id, ...)`
也吃同一个值 —— 不切，7 只怪连物理帧都不跑。

**不能**改用 `_on_room_entered`：那条链要重算流送、换小地图、写存档检查点，全部以主图房间图为前提。

### 3.3 清房不能借 `_mark_room_cleared`

`_mark_room_cleared` 会：发房间钥匙 → 走 `RuntimeRewardCoordinator` 房间奖励 → 让命运卡计数推进 →
刷新撤离信标锁。这四件都是主图语义，套在子图上会凭空多出钥匙和结算。

另外它对子图房是**静默空操作**（`_room_by_id.get()` 为 null 直接 return），
于是「7 只全打死了但房间永远算不清」——HUD 一直停在「暗室清剿」。

### 3.4 验收里两条自伤

- **`configure` 会清空运行期回调**：A11 用 6 个参数重配 `SecretBranch3D`（只为替换「已清数」provider），
  顺手把新注入的 `_room_enter_handler` 覆盖成空 `Callable`。现象是「重配之后进的房间不刷怪」，
  而房间自己那侧的 `entered` 已经置真 —— 两本账对不上。现在 `configure` 只在拿到有效 `Callable` 时覆盖。
- **边遍历边删**：击杀会在 `_claim_enemy_departure` 里把节点从 `_enemy_nodes_by_room[room_id]` 移除。
  验收脚本直接 `for value in array` 就会每杀一只跳过一只（7 只里剩 3 只存活），看着像「伤害没生效」。
  必须遍历 `.duplicate()`。

## 4. 顺手补通的两个口

- **子图房间门原本按不开**：门交互由 `Dungeon3D.get_interaction_candidate` 按 `_current_room_id`
  取房再找最近门扇，子图房取不到 → 候选为空 → 按 E 没反应，玩家会卡在第二间门外。
  现在取不到时回落到 `SecretBranch3D.nearest_closed_door()`，并用 `mode = "secret_branch_door"`
  走一条「只把门抬起来」的交互分支（不消耗钥匙、不触发命运卡）。
- **在子图里存档会写出查不到的 room_id**：`_runtime_current_room_id_for_save()` 原本直接返回
  `_current_room_id`。现在子图房间回落到 `_last_main_room_id`（最近一次主图房间）——
  宁可丢掉支线进度，也不能让续局按一个 `_room_by_id` 里没有的 id 恢复。

## 5. 验收

`verify_secret_branch_flow` 增至 **19 条**（新增 A19）：

| 断言 | 内容 |
|---|---|
| A19-a | 没进过的子图房**不刷怪**（`secret_branch_encounter_snapshot()` 里没有它） |
| A19-b | 进房后恰好 **5 强化 + 2 普通**，怪种逐条核对 |
| A19-c | 7 只全灭后**房间标清**、存活归零 |

反向对照：把 `allow_strong` 改回默认（普通怪可能升级）/ 把 `_current_room_id` 不切 / 清房改回
`_mark_room_cleared`，三种都能让 A19 变红。

实跑环境：`bash scripts/run_verification_suite.sh scene verify_secret_branch_flow`，输出
`SECRET_BRANCH_FLOW_OK`。

> 备注：2026-10-18 16:26 另一条工作流正在改 `art_source/.../level_plan.json`（枪械移出普通怪掉落），
> `data/level_plans/.../level_plan.json` 尚未同步，`sync_runtime_design_data.py --check` 会红。
> 本轮验收为此在临时脚本里跳过该门禁一次，与本改动无关。

## 6. 仍未做

- **A12**：B1–B3 跳跃边界的运行时断言（现在只有静态数据核对）。
- **A13**：子图与主图**分开**的击杀账（现在子图击杀只并入全局 `_kills`，没有单列）。
- 子图怪不进存档：在子图里退出重进，房间会按「未进过」重建（怪重刷）。这是「子图不参与存档」
  的必然结果，若以后要保进度，得给子图单开一份 segment 状态。
