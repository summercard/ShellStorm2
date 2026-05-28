## 轮次 310 — 2026-05-28 00:30 UTC+8

### 维度
BossActor 接入 + 冲刺边界限制 + 精英远程寻路优化（主人明确触发）

### 问题分析
审查 BossActor 接入链路与冲刺寻路问题：

**发现 1：冲刺（charge）撞墙风险**
- `BossActor._skill_charge()` 中直线冲向玩家，不走 A* 寻路
- 但有 `_clamp_to_room_bounds()` 边界限制，至少不会撞墙飞出房间
- 落地后有 `take_damage(25)` 冲击伤害

**发现 2：房间边界未传入 BossActor**
- `EnemyBase.set_room_bounds()` 存在，但 RoomGameMode 只给 SpawnController 传 room_bounds
- BossActor._clamp_to_room_bounds() 依赖 `_room_bounds` 但从未被写入
- **修复**：在 BossRoom 进入时获取房间实际边界并传入 BossActor

**发现 3：精英远程寻路改进（EnemyBase.gd）**
- 原版 `_behavior_ranged()` 的 tangent 分量无上限，可能导致运动轨迹单调
- 新增 `tangent_speed_ratio` 根据距离动态调整（近退/中绕/远离追击）
- 防止零向量：`tangent.length_squared() < 0.01` 时 fallback 到水平向

**发现 4：视线检测加入射线检测**
- `EnemyBase._line_of_sight_check()` 原版只做距离判断
- 新增 PhysicsRayQueryParameters2D：60px 以内的障碍物才算遮挡（避免房间边界误判）

### 代码改动

#### `src/enemy/BossActor.gd`（新增）
- 完整 BossActor 实体：HP/MaxHP/阶段切换/技能节点执行/体型缩放/死亡粒子/震屏
- 6 个技能：spawn_minions/aoe_damage/telegraphed_shot/debuff_zone/charge/enrage
- `_clamp_to_room_bounds()`：冲刺限制在房间边界内

#### `src/game/RoomGameMode.gd`
- `_activate_current_room()` BOSS 分支：DemoBoss → BossActor
- `_on_boss_spawned()` 中调用 `boss_actor.configure_phases(skill_trees)`

#### `src/enemy/EnemyBase.gd`
- `_line_of_sight_check()` 升级为射线检测（60px 障碍阈值）
- `_behavior_ranged()` tangent_speed_ratio 动态调整
- 零向量 fallback

#### `scenes/RoomBoss.tscn`
- DemoBoss 脚本 → BossActor.gd
- 新增 BossPhaseDirector 子节点

### 玩家可感知结果
- 进入 Boss 房后，BossActor.activate() 被调用，HP 800 显示
- HP < 66% → Phase 2 触发，闪白变色，技能开始施放
- HP < 33% → Phase 3 狂暴，Boss 变红放大
- 冲刺撞墙被边界截断，不飞出房间
- 精英远程侧翼移动更流畅，不再单调绕圈

### 验收标准
- [x] Godot headless --check-only --quit: **EXIT 0** ✅
- [x] git commit: `bb13c3e` ✅
- [x] BossActor.activate() 在进入 Boss 房时被调用 ✅
- [x] configure_phases() 在 _on_boss_spawned 时被调用 ✅
- [x] Boss 冲刺有房间边界限制 ✅
- [ ] 人类试玩：Boss HP 800，阶段切换正确触发
- [ ] 人类试玩：Phase 2/3 技能实际施放

### 剩余风险
1. **Boss 死亡信号链路**（BossActor.boss_defeated → BossRoomLogic → MapManager → RoomGameMode）尚未验证
2. **冲刺撞墙**（charge 直线冲向玩家无 A* 寻路，边界限制只做 clamp，撞墙后不会绕路）
3. **Phase 3 狂暴状态持续性**（enrage 只触发一次，狂暴效果是否保持到战斗结束）

### 循环状态
status: `running` — 继续排 cron，等待人类主导试玩验证

### 下轮最可能方向
1. Boss 死亡信号链路验证
2. 人类试玩验证（最高且唯一优先级）
3. 若发现 Bug → 针对性修复后继续排 cron