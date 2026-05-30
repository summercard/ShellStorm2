## 轮次 373 — 2026-05-29 20:02 UTC+8

### 维度
**PH06 怪物技能链路补全 — 基础怪物主动技能注入缺失修复**

### 问题分析
从核心玩法"怪物系统 + 战斗体验"审查，发现关键断点：

- `EnemyTypes.gd` 定义了6种基础怪物的 `spawn_*` 工厂方法，内含 `EnemySkillComponent` 注入（冲刺猛击/散射弹幕/召唤小怪/盾击/自爆/地刺等）
- `RoomWaveSpawner._spawn_enemy_instance()` 只注入 `ai_type` + `awareness_enabled=false`，**从未调用 EnemyTypes 的技能注入方法**
- 6种基础怪物（追猎型/远程型/召唤型/护盾型/自爆型/潜伏型）中只有 `EnemyBase._dispatch_behavior()` 的旧 AI 行为，无主动技能
- 精英怪的 `EliteActiveSkillComponent` 已正确注入，但精英≠基础怪，普通波次完全无技能

### 解决方案
在 `RoomWaveSpawner._spawn_enemy_instance()` 中，`set_enemy_data()` 之后新增技能注入：

```gdscript
const ENEMY_TYPES_SCRIPT := preload("res://src/enemy/EnemyTypes.gd")

# 在 _spawn_enemy_instance() 内（非精英时）
var enemy_type_key: String = data.get("enemy_type", "")
if not data.get("is_elite", false) and not enemy_type_key.is_empty():
    _inject_base_skill(enemy, enemy_type_key)
```

`_inject_base_skill()` 根据 enemy_type 调用 EnemyTypes 对应静态方法：
- `melee_chaser` → `inject_chaser_skill`（冲刺猛击+狂暴化）
- `ranged_caster` → `inject_ranged_skill`（散射弹幕+蓄力狙击）
- `summoner` → `inject_summoner_skill`（召唤小怪+治疗光环）
- `shielded` → `inject_tank_skill`（盾击+盾墙+钢铁意志）
- `exploder` → `inject_bomber_skill`（布陷阱+殉爆+碎片）
- `ambusher` → `inject_trapper_skill`（陷阱+毒孢子+藤蔓+地刺弹幕）

注意：`ambusher` 映射到 `inject_trapper_skill`（EnemyTypes 命名的 trapper，对应 PH06 的"潜伏型"）

### 玩家可感知结果
- **Before**：所有普通怪物只有移动追击+基础接触伤害
- **After**：每种基础怪物在波次战斗中展现冲刺猛击/散射弹幕/召唤小怪/盾击/殉爆自爆/地刺弹幕等主动技能

### 修改文件
- `src/map/RoomWaveSpawner.gd`：preload EnemyTypes + `_inject_base_skill()` 方法 + 在 `_spawn_enemy_instance()` 中调用

### 验收标准
- [x] Godot headless --quit-after 1 编译通过 ✅
- [ ] 人类试玩：进入 COMBAT 房间，观察近战怪是否有冲刺猛击（突进+眩晕）
- [ ] 人类试玩：观察远程怪是否有散射弹幕（3发偏移）+ 蓄力狙击
- [ ] 人类试玩：观察召唤怪是否周期性召唤小怪
- [ ] 人类试玩：观察护盾怪是否有盾击冲锋+盾墙格挡

### 剩余风险（人类试玩确认项）
1. 技能实际运行效果（时机/伤害/范围）
2. 技能动画/SFX 尚未接入
3. `EnemySkillComponent.tick()` 在 awareness_enabled=false 模式下的调用链路

### 续排判断
**继续排 cron** — 状态维持 `running`。PH06 怪物技能链路修复已实现，剩余为人类试玩确认项（无代码断点）。

### 下轮最可能方向
1. **人类试玩验证**（最高且唯一优先级）
2. **第二关怪物类型深化**
3. **战斗视觉反馈强化**
