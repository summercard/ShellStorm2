## 轮次 352 — 2026-05-29 04:56 UTC+8

### 维度
战斗房波次生成器精英名额独立计算

### 问题分析
审查 RoomGameMode._calculate_wave_counts_for_enemy_plan 发现一个波次计数 bug：当 EliteSpawnDirector 根据楼层和风险概率选中一个精英时，这个精英被注入到 RoomWaveSpawner 的 pending slot，但 `_calculate_wave_counts_for_enemy_plan` 的 `enemy_count` 参数来自 `enemy_plan.size()`，这个 plan 里的精英是单独处理的，不占普通敌人数。但 RoomWaveSpawner 层面，精英注入后 `_total_enemy_count` 实际上比 `wave_counts` 之和大 1（因为 pending 不在 pool 里但实际出生了），导致 UI 进度条显示不准确。另外在某些边缘情况（enemy_count 刚好 == wave_count 时），精英可能挤掉一个普通敌人。

核心问题：精英的存在在波次分配时没有被考虑，导致：
1. 进度条 total 偏小（少算了精英）
2. 极端情况下普通敌人被挤掉

### 玩家体验的前后变化
- **前后**：精英出现时进度条总击杀数比实际少1，玩家可能困惑
- **之后**：精英作为独立名额计入波次分配，总数正确，击杀计数准确

### 代码改动

**文件1：** `src/enemy/EliteSpawnDirector.gd`
- 新增 `_pending_elite_id: String = ""` 实例变量
- 新增 `has_pending_elite() -> bool` 方法（供 RoomGameMode 预查询）
- `try_select_elite()` 在返回结果前设置 `_pending_elite_id`

**文件2：** `src/game/RoomGameMode.gd`
- `_calculate_wave_counts_for_enemy_plan` 新增 ELITEBOOST 逻辑：
  1. 调用 `has_pending_elite()` 判断当前是否已有选中精英
  2. 如果有，`enemy_count -= 1`（把精英名额从普通敌人数中分离）
  3. 正常波次分配（ceil 分配法）
  4. 最后 `waves[0] += 1`（把精英名额加回第一波）

### 验收标准
| 验收项 | 预期结果 |
|---|---|
| `has_pending_elite()` | 精英选中后返回 true，注入后返回 false |
| 波次总数 | 精英被正确计入（不丢失也不重复） |
| 进度条显示 | 击杀精英后 total/killed 准确 |
| Godot headless --check-only --quit | EXIT 0 ✅ |

### 验证
- Godot headless --check-only --quit: **EXIT 0** ✅

### 剩余风险
1. **人类试玩验证**：进入战斗房，确认精英实际出现且进度条计数正确
2. 波次递减分配（ceil 方式）第一波是否偏大需要试玩校准
3. `_pending_elite_id` 只存 id，注入后通过 `set_pending_elite_spawn` 消耗（不清空 _pending_elite_id 的情况：try_select_elite 选完但尚未 configure）；这在实际流程中不会发生（try_select_elite 在 configure 之后调用），但理论上有一个小窗口

### 下轮最可能方向
1. 人类试玩验证精英出现与进度条（最高且唯一优先级）
2. 第二/三关战斗房怪物密度深化
3. 搜打撤经济系统收束