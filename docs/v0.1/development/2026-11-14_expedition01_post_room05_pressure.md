# 远征01房间05后战斗心流与小僵尸数值调整

日期：2026-11-14；工程版本：0.1.0；开发线：0.2。
功能ID：`WORLD-PLAN`、`ENCOUNTER-EVENT`。

## 1. 用户要求

- 房间05以后进入比较激烈的战斗。
- 小僵尸移动速度降低30%。
- 后期数量增加30%。

## 2. 设计裁定

- `room_05` 保留为强度转折房：31只同场，包含4只胖子、4只远程和1只显式强化小僵尸；本轮不对room_05额外堆量。
- 后期段定义为 `room_06`—`room_10`。
- 后期数量增加只作用于普通小僵尸 `melee_chaser`；显式强化小僵尸 `melee_chaser_strong` 不重复增加；Boss不纳入本轮增量。
- 限时房普通小僵尸逐条使用 `ceil(n × 1.30)`；同场上限使用 `ceil(max_alive × 1.30)`。
- 预置房通过实例级 `count_bonus` 分配增加量，不改共享刷怪盒资产。`room_07` 普通小僵尸 11→15，`room_08` 普通小僵尸 11→15。
- 小僵尸速度：`3.5 × 0.70 = 2.45 m/s`。强化小僵尸继承该基础移动速度。
- 保留07奖励缓冲、08强化远程复习、60秒限时窗口、冻结1秒、首批第2秒、末批循环、截止清场和奖励结算语义。

## 3. 实际变更

### 3.1 权威数据

- `art_source/design/whitebox/tower_zones/expedition_01/v001/data/level_plan.json`
  - `monster_rules.stats.per_kind.melee_chaser.speed`: `3.5 → 2.45`。
  - 在规则说明中登记速度公式及强化继承边界。
- `art_source/design/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json`
  - room06：普通小僵尸5/5/6→7/7/8，`max_alive=10→13`。
  - room07：普通小僵尸总量11→15，实例级增量分配为4/3/3。
  - room08：普通小僵尸总量11→15，实例级增量分配为2/2/0/2/2；远程随机区间保留。
  - room09：普通小僵尸8/9/10/10→11/12/13/13，`max_alive=16→21`。
  - room10：普通小僵尸8/9→11/12，`max_alive=10→13`。

### 3.2 运行投影与验收

使用 `scripts/sync_runtime_design_data.py` 同步运行投影和manifest，共52个映射文件，无drift。

专项脚本同步更新为新模板、数量、容量、速度与room05/Boss边界断言：
`tests/verification/verify_expedition01_spawn_ramp.py`。

## 4. 验证结果

| 检查 | 结果 |
|---|---|
| `python scripts/sync_runtime_design_data.py --check` | exit 0；52 files，issues=[] |
| `python scripts/check_level_decoupling.py` | exit 0；0 violations |
| `python -m py_compile tests/verification/verify_expedition01_spawn_ramp.py` | exit 0 |
| `python -B tests/verification/verify_expedition01_spawn_ramp.py` | exit 0；数据、投影、真实LevelPlanValidator、房间波次及Boss边界通过 |
| `git diff --check` | exit 0；仅有既有CRLF转换提示 |
| `python scripts/check_documentation_contracts.py` | exit 1；11条既有文档断链，本轮未新增；详见命令输出 |

专项关键输出：

- room06 waves=`10/11/15`，cap=13。
- room07 total=16，普通小僵尸=15，另含1只强化小僵尸。
- room08 waves=`19—20`，普通小僵尸=15。
- room09 waves=`15/19/23/27`，cap=21。
- room10 waves=`13/15`，cap=13。
- room05保持31只；Boss静态波次保持4/5/1—2，总量10—11，动态增援排除在本统计外。
- 普通小僵尸速度=2.45m/s；强化继承断言通过。

## 5. 未执行项与风险

- 未执行五房真实玩家游玩、视听体验和目标设备验收；静态/无头专项不能代签“激烈但公平”的手感。
- 未改变共享机制代码；若实机发现13/21的同场上限造成积压或过载，下一轮应基于实测激活峰值调整数据，而不是放宽断言。
- 文档契约检查仍被11条既有断链阻断，本轮未顺手修复无关文档债务。

改动前备份：
`I:\工作项目\shellstrom2\ShellStorm2-backup\2026-11-14_expedition01_post_room05_pressure\before_edits\`
