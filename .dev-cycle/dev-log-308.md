## 轮次 308 — 2026-05-28 08:09 UTC+8

### 维度
BossActor 技能树配置接入 + DemoBoss 残留引用清理

### 当前问题审查

轮次 307 完成了 RoomBoss.tscn 从 DemoBoss → BossActor 的脚本切换（`BossActor.gd` 已挂载，`BossPhaseDirector` 子节点已连接），但存在两个关键断点：

1. **RoomGameMode._on_boss_spawned() 没有配置技能树**：`BossPhaseDirector` 需要外部调用 `configure_phases(skill_trees)` 才能驱动 HP 阈值触发阶段切换和技能触发
2. **RoomGameMode._activate_current_room() 仍在查找 `DemoBoss`**：进入 Boss 房时 `get_node_or_null("DemoBoss")` 找不到节点（已改名为 `BossActor`），`activate()` 根本没被调用

### 本轮目标
将 RoomGameMode 的 Boss 房进入逻辑从 DemoBoss 切换到 BossActor，并在 `_on_boss_spawned()` 中配置 BossActor 的技能树，让阶段切换和技能真正可执行。

### 修改内容

#### `src/game/RoomGameMode.gd`

**修改1：Boss 房进入时激活 BossActor**
- 位置：`_activate_current_room()` 的 BOSS 分支
- `DemoBoss` → `BossActor`
- 新增 BossRoomDirector 的 boss_data 注入（max_hp 从 boss_data 读取）
- Boss HP 设置为 800（从 `boss_data.get("max_hp", 800)` 获取）

**修改2：_on_boss_spawned() 中配置技能树**
- 新增 `configure_phases(skill_trees)` 调用
- 技能树配置：
  - Phase 1：`spawn_minions`(8s)、`telegraphed_shot`(5s)
  - Phase 2：`aoe_damage`(6s)、`debuff_zone`(10s)、`charge`(7s)
  - Phase 3：`enrage`(15s)、`aoe_damage`(4s)、`spawn_minions`(5s)

### 玩家可感知结果
- 进入 Boss 房后，BossActor.activate() 被调用，BossHP 800 显示
- HP 低于 66% 时，Phase 2 触发，Boss 闪白+颜色变深，Phase 2 技能开始施放
- HP 低于 33% 时，Phase 3 狂暴，Boss 变红+放大，开始高频施放技能
- 6 个技能（spawn_minions/aoe_damage/telegraphed_shot/debuff_zone/charge/enrage）在对应阶段可被触发

### 验收标准
- [x] Godot headless --quit-after 3: **EXIT 0**（编译通过）✅
- [ ] 人类试玩：进入 Boss 房后，Boss HP 800，HP 66%/33% 阶段切换正确触发
- [ ] 人类试玩：Phase 2 时 `spawn_minions` / `aoe_damage` / `charge` 等技能实际生效

### 剩余风险
1. **Boss 死亡信号未连通**：BossActor.boss_defeated → BossRoomLogic.trigger_boss_defeated → 但 RoomGameMode 监听的是 MapManager boss_defeated 信号（BossRoomDirector._defeat_boss → boss_defeated.emit），信号链路需要确认
2. **Boss 冲刺 charge 直线冲向玩家，A* 寻路未接入**：会撞墙
3. **Phase 3 狂暴后 enrage 技能只触发一次**（cooldown=15s），狂暴状态是否持续需要验证

### 下轮最可能方向
1. **Boss 冲刺（charge）A* 寻路接入**（直线冲向玩家撞墙问题）
2. **Boss 死亡信号链路验证**（BossActor.boss_defeated → BossRoomLogic → MapManager → RoomGameMode 确认连通）
3. **Phase 3 狂暴状态持续性**：enrage 触发后狂暴效果是否保持到战斗结束