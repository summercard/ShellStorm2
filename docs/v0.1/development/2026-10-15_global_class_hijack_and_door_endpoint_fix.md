# 2026-10-15 全局类被抢注（TowerDescent3D）＋ 门端口归属缺失键

> 症状来自主人在编辑器/运行时看到的一屏报错：
> `Parse Error: Class "TowerDescent3D" hides a global script class.` +
> `Failed to load script "res://src/world3d/TowerDescent3D.gd"`，
> 以及「游戏开场直接掉到地图外边去，无法正常进行游戏」。

## 1. 事故链（一因一果，九个症状同一个根）

一份**带 `class_name` 的脚本副本**被放进了 `res://` 内的扫描范围，抢注了全局类：

```text
_scratch/encounter_reg/head_tower.gd      ← 第 1 行是 `class_name TowerDescent3D`
```

`_scratch/` 在 `res://` 内、且**没有 `.gdignore`**，Godot 会照常扫描它。
扫描顺序里那份副本赢了，`.godot/global_script_class_cache.cfg` 里
`TowerDescent3D` 一度指向 `res://_scratch/encounter_reg/head_tower.gd`：

```text
1339:"class": &"TowerDescent3D",
1344:"path": "res://_scratch/encounter_reg/head_tower.gd"   ← 真身被挤出缓存
```

于是真身 `src/world3d/TowerDescent3D.gd` 一加载就报 `hides a global script class`
并解析失败，接着是连锁崩塌（**全部由这一个根因派生，不是九个独立问题**）：

| # | 表面症状 | 真实原因 |
|---|---|---|
| 1 | `Class "TowerDescent3D" hides a global script class.` | 副本抢注 |
| 2 | `Failed to load script "res://src/world3d/TowerDescent3D.gd"` | 同上 |
| 3 | `Invalid access to property or key 'run_completed' on a base object of type 'Node3D'` | 脚本没加载 ⇒ 场景根退化成 `Node3D` |
| 4 | `Nonexistent function '_get_run_settlement_transaction_id' (via call) in base 'Node3D'` | 同上 |
| 5 | `Invalid assignment of property 'test_mode' on a base object of type 'Nil'` | 同上 |
| 6 | 塔楼/远征场景「无法实例化」 | 同上 |
| 7 | **开场没地板、玩家直接掉出地图** | 塔楼没构建出来 |
| 8 | 大量 `RID allocations leaked` / `resources still in use` | 场景半初始化就被丢弃 |
| 9 | 三个回归红（`verify_tower_extraction_return_flow`、`verify_death_during_extraction_flow`、`verify_expedition_extraction_carry_return`） | 同上 |

## 2. 这是本仓库**第二次**踩同一个坑

`docs/v0.1/development/2026-09-22_main_entry_cinematic_redesign.md` 已记录过一次，措辞几乎逐字相同：

> 真实工程 `.godot/global_script_class_cache.cfg` 里全局类 `Player3D` 被
> `res://_scratch/gamepad_submenu/baseline_bak/Player3D.gd`（他人并发备份，同声明 `class_name Player3D`）
> 抢注，真实 `src/player3d/Player3D.gd` 被挤出缓存 …… 全局类解析失败
> （连带大量 "Could not find type" 连锁报错）。

⇒ 这不是偶发失误，是**结构性陷阱**：`_scratch/` 被当作「随手放东西的地方」，
但它同时在 `res://` 内。任何完整脚本副本落进去都会变成一颗定时炸弹。

## 3. 修复

| 动作 | 内容 |
|---|---|
| 删副本 | `_scratch/encounter_reg/head_tower.gd`（及其 `.uid`） |
| 补忽略规则 | 新增 `_scratch/.gdignore` —— 让 Godot 完全不扫描该目录，**根治** |
| 刷类缓存 | `godot --headless --path . --import`；核对 `TowerDescent3D / Dungeon3D / Enemy3D / ItemRegistry / InventoryModule / InventoryUI` 全部指回 `src/**`，`res://_scratch` 条目归零 |

`.gdignore` 是可逆的单行文件：删掉它并重新导入即可撤销。
代价（已明说）：`_scratch/` 下的 3 个临时探针（`exp02_topview.gd`、
`probe_bullet_mesh_stats.gd`、`probe_mesh_lod_sweep.gd`）不再被 Godot 导入，
如需运行要临时移出该目录。**输出写入不受影响**（`.gdignore` 只管扫描，不管文件系统）。

### 顺带核实：`.workbuddy/` 下的同类副本**无害**

排查时发现 `ShellStorm2/.workbuddy/backup/20261014_health_bar_visual/before_edits/`
下还有 `Dungeon3D.gd` 与 `Enemy3D.gd` 两份带 `class_name` 的副本。但：

- 它们**没有** `.uid` 文件 ⇒ Godot 从未导入它们
- 缓存里 `Dungeon3D` / `Enemy3D` 都指向 `src/**` 正确位置

⇒ Godot 跳过点目录，`.workbuddy/` 不参与扫描。**不需要动它**（那是项目数据目录，不可删）。

## 4. 一并修掉的真实运行时崩溃：`door_endpoint_owners` 缺失键

清掉抢注后，回归日志里浮出一条**之前被抢注噪音掩盖**的真 bug：

```text
SCRIPT ERROR: Invalid access to property or key 'door_endpoint_owners' on a base object of type 'Dictionary'.
   at: TowerDescent3D._register_edge_topology (TowerDescent3D.gd:5619)
```

**机制**：`Dungeon3D._record()` 初始化了 `doors`、`door_targets`，**唯独漏了
`door_endpoint_owners`**；而 `TowerDescent3D._register_edge_topology()` 会无条件执行

```gdscript
(record["door_endpoint_owners"] as Dictionary)[direction] = bool(pair[3])
```

`record[...]` 对缺失键返回 `null`，`as Dictionary` 仍是 `null`，对 `null` 索引赋值即抛错。
此前只有 `_append_plan_room_record()` 补过这个键，所以**经 `_append_tower_record()` 创建的
record**（塔楼壳体、楼梯端点等）一直缺键 —— 撤离返航重建初始环
（`_reset_initial_loop_world_after_retreat`）就会踩到。

**危害不止一行报错**：这是 `SCRIPT ERROR`，会**打断函数执行** ⇒ 门端口归属写了一半就退出，
后续门/撤离逻辑带病运行。属于「游戏无法正常进行」的组成部分。

**修复（两处，语义零变化）**：

1. `Dungeon3D._record()` 补 `"door_endpoint_owners": {}` —— 根治，所有 record 天生带键；
2. `TowerDescent3D._register_edge_topology()` 写前兜底 —— 防「旧档恢复 / 更早路径构建」的
   record 仍缺键；缺键的正确语义与空字典完全一致。

**验证**：`verify_tower_extraction_return_flow` 与 `verify_death_during_extraction_flow`
两份日志里该报错由 1~2 次降为 **0**，`SCRIPT ERROR` 总数 **0**。

## 5. 验收（修复后实跑）

```text
全新导入（--import）：严重报错（hides a global / Parse Error / Failed to load script /
                      Could not find type）0 行，EXIT=0
```

| 场景 | 结果 | 日志硬错误 |
|---|---|---|
| `verify_tower_descent_flow` | ✅ `EXIT=0` | 0 |
| `verify_game_entry_flow` | ✅ `EXIT=0` | 0 |
| `verify_encounter_event_flow` | ✅ `EXIT=0`（`samples=31`） | 0 |
| `verify_death_during_extraction_flow` | ✅ `EXIT=0` | 0（修 `door_endpoint_owners` 前有 2 次 SCRIPT ERROR） |
| `verify_block00_floor98_assembly` | ⚠️ `EXIT=1`，228 断言 **227 通过** | 0 |
| `verify_tower_extraction_return_flow` | ❌ `EXIT=1`，剩 3 条「准备/断言」类 | 0（该崩溃已修） |

**已消失**：`hides a global script class`、`Failed to load script TowerDescent3D`、
`run_completed` / `_get_run_settlement_transaction_id` / `test_mode on Nil` 等 Node3D 退化解引用、
`door_endpoint_owners` 崩溃 —— 六份日志中全部为 **0**。

## 6. 未修、如实列出（均与本轮两个根因无关）

- `verify_block00_floor98_assembly` 唯一失败的断言：
  `和平区房间 floor_01_entry 刷怪登记=3 期望 0（改动前为敌意房数量）`
  证据行：`type=STAIR_LOBBY 首访=true 刷怪登记=3 待刷波次=0 cleared=true`。
  **已排除**：`ROOM_TYPES_WITH_HOSTILES` 不含 `STAIR_LOBBY` ⇒ 该房根本不走刷怪入口；
  本轮改动**没有任何一处增加 `_alive_by_room`**（唯一动过的是延迟出怪丢弃分支的 `-1`）。
  现象特征是「有计数、无敌人、无波次、房间已放行」的**计数残留**，属 98F 和平区契约
  落地或测试内状态传递问题，需单独排查，本轮不擅自改。
- `verify_tower_extraction_return_flow` 剩余 3 条：`清房开门回归房没有可控灯光`、
  `无法准备成功撤离装备背包`、`死亡结算没有区分未保险物品` —— 落在背包棋盘化
  （`BASE_INVENTORY_CAPACITY` 12→24、`GridInventoryBoard` 等未提交新件）与保险结算那条改动流。
- `verify_opening_script_runtime` 125 项检查仅 1 项失败（地面剧情枪剩余 1），
  与 `verify_new_save_handoff` 同族，属开场剧情枪拾取归属链。
- 既有资源警告：大量 `.glb` 报 `invalid UID ... using text path instead`（非本轮引入）。

## 7. 教训（写给以后）

1. **不要在 `res://` 内放带 `class_name` 的脚本副本。** 备份/快照要放项目外；
   若必须留在项目内，放在有 `.gdignore` 的目录里（现在 `_scratch/` 已是）。
2. **拿 `git show` 导出对比副本时，一定落到项目外或忽略目录。** 本次就是
   `git show HEAD:src/world3d/TowerDescent3D.gd > _scratch/.../head_tower.gd` 造成的。
3. **看到 `hides a global script class`，第一反应是查类缓存指向，而不是改代码。**
   `.godot/global_script_class_cache.cfg` 里那条 `path` 就是答案。
4. **抢注会掩盖其它真 bug。** `door_endpoint_owners` 那条本可以更早被发现，
   但被一屏 Node3D 连锁报错淹没了 —— 修完根因要**重跑一遍**，别以为清了噪音就没事。
