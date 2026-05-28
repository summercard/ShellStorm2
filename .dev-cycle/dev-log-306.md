## 轮次 306 — 2026-05-28 08:02 UTC+8

### 维度
Boss技能链路实现 + Boss体型scale联动

### 当前问题审查

**BossPhaseDirector 是空壳？** ✅ 框架已存在但技能执行空
- `BossPhaseDirector.gd`：阶段切换逻辑完整，`check_hp_threshold` / `set_phase` / `trigger_skill` 均已实现
- `BossSkillNode.gd`：预置工厂方法存在（`create_spawn_minions` 等），但 `_execute_skill()` 是空实现
- `DemoBoss.gd`：只有 HP 管理，无阶段、无技能、无体型联动

**DemoBoss 的问题**：
- 无阶段切换概念
- 无技能施放
- HP 500/500 固定，`DemoRoomChain` 里 boss 房场景用的是它
- `RoomBoss.tscn` 的 Boss 节点 `DemoBoss` 硬编码了 `max_hp=500`，无法动态配置

**Boss 体型？** ❌ 无
- DemoBoss 是 80×80 的固定大小
- `EnemyBase.apply_scale()` 已存在（巨大化词缀），但 Boss 没用它
- PH06 策划里 Boss 体型缩放需求未落地

### 本轮目标
**实现 `BossActor`（替换 DemoBoss）并落地 6 个真实可执行技能**：
- `spawn_minions`：Boss 周围生成 3 只小怪
- `aoe_damage`：以 Boss 为中心的 AOE 伤害圈
- `telegraphed_shot`：蓄力 1 秒后向玩家发射高伤害子弹（含预警圈）
- `debuff_zone`：在玩家位置留下持续 3 秒的减益区域
- `charge`：Boss 冲向玩家，落地冲击波
- `enrage`：狂暴，攻速翻倍，颜色加深放大

**Boss 体型scale联动**：
- `boss_scale` 参数 → 碰撞半径、shape大小、HP、房间边界约束全部联动
- 阶段切换时颜色/大小变化（Phase 1→2→3 逐渐加深/放大）

### 修改内容

#### `src/enemy/BossActor.gd`（新文件）
- 整合 `BossPhaseDirector` 引用（`_phase_director = $BossPhaseDirector`）
- `@onready var _phase_director: Node = $BossPhaseDirector as Node`
- 监听 `phase_started` / `skill_triggered` 信号
- 6 个技能方法：`_skill_spawn_minions` / `_skill_aoe_damage` / `_skill_telegraphed_shot` / `_skill_debuff_zone` / `_skill_charge` / `_skill_enrage`
- `_execute_skill_by_id(skill_id)` 路由到具体技能
- `boss_scale` 参数驱动：`shape.size`、`collision_radius`、`HP`、`_room_bounds`
- 阶段切换视觉：`_flash_phase_change(phase)` 闪烁 + 缩放回弹

#### `scenes/RoomBoss.tscn`（修改）
- 节点 `DemoBoss` → `BossActor`
- 脚本引用 DemoBoss.gd → BossActor.gd
- 新增 ext_resource 引用 BossPhaseDirector.gd（id=2_boss_phase_director）
- `BossPhaseDirector` 子节点脚本指向 BossPhaseDirector.gd
- Shape：`80×80` → `100×100`，颜色加深（Phase 1 基准色）
- BossNameLabel 偏移从 `-95` → `-110`（适配更大 shape）

### 玩家可感知结果
- Boss 有 3 阶段，血量分别触发阶段切换
- 阶段切换时 Boss 闪白 + 缩放回弹，颜色加深
- Phase 2+ Boss 开始施放技能（小怪刷新/AOE/蓄力射击等）
- Boss 体型可配置（大 Boss 默认 scale=1.0，但可以通过 `apply_scale` 放大到 2.0 倍）
- Phase 3 狂暴时 Boss 冒红烟、颜色最红、体型略大

### 验收标准
- [x] Godot headless --check-only: **EXIT 0**（编译通过）
- [ ] 人类试玩：进入 Boss 房后，Boss HP 低于 66% 时阶段切换到 Phase 2
- [ ] 人类试玩：Phase 2 时 `spawn_minions` 技能触发，Boss 周围生成小怪
- [ ] 人类试玩：Phase 3 狂暴时 Boss 颜色变红并略放大

### 剩余风险
1. `BossPhaseDirector` 的 `_cooldowns` 是 Dictionary[float]，冷却更新依赖 `tick()` 每帧递减，当前 cooldown 逻辑需要验证
2. `_skill_debuff_zone` 只是视觉区域，减伤效果需要在 Player 侧监听区域进入/离开（暂未实现）
3. `configure_phases()` 需要外部调用，BossRoomLogic 或 MapManager 需要在生成 Boss 后调用配置技能树（需要后续接入）
4. 没有实现 `NavigationRegion2D` / A*，Boss 冲刺用 Tween 直线，撞墙时不会绕行

### 下轮最可能方向
1. **Boss 冲刺（charge）A* 寻路接入**（大房间内 Boss 直线冲向玩家可能撞墙）
2. **Boss 房波次生成器接入**（BossPhaseDirector 配置好后需要在 BossRoomLogic 正确调用 `configure_phases`）
3. 精英怪 HugeModifier 的 `apply_scale` 在多房间联动时边界约束是否正确（EnemyBase._room_bounds 按比例放大后是否影响相邻房间 AI 联动）