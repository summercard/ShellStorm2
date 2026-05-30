# 轮次 325 — 2026-05-28 15:04 UTC+8

### 维度
**精英主动技能Tick链路打通（EnemyBase._physics_process 缺失 comp.tick(delta) 调用）**

---

## 一、问题发现

审查轮次324发现 `_inject_elite_active_skills()` 方法已实现：
- 静态工厂 `EliteActiveSkillComponent.inject_elite_skills(enemy, modifier_id, tier)` 被调用
- `EliteActiveSkillComponent.tick(delta)` 每帧评估技能冷却并触发执行

但追踪 `EnemyBase._physics_process()` 发现：**每帧 Tick 循环中从未调用 `comp.tick(delta)`**。

### 问题链路分析
```
EnemyBase._physics_process(delta)
  → _ai_tick(delta) [awareness_enabled=true路径]
  → _dispatch_behavior(delta) [awareness_enabled=false路径]
  → (两个路径都没有调用 child.tick(delta))
```

`EliteActiveSkillComponent.tick(delta)` 永远不会被驱动，精英主动技能（冲锋/护盾反射/召集/狂暴化/反制射击/瞬移打击）全部静默失效。

---

## 二、本轮改动

### 文件：`src/enemy/EnemyBase.gd`

在 `_physics_process()` 的 AI 状态机分支之后、velocity 应用之前，增加精英主动技能组件 Tick 调用：

```gdscript
if awareness_enabled:
    _ai_tick(delta)
else:
    _dispatch_behavior(delta)
    return

#精英主动技能组件每帧Tick（awareness_enabled=true时由AI状态机驱动，false时由_dispatch_behavior返回前驱动）
for child in get_children():
    if child.has_method("tick") and "elite_skill_triggered" in child:
        child.tick(delta)

velocity += _separation_velocity()
```

### 精英主动技能完整链路（打通后）
```
RoomWaveSpawner._spawn_enemy() [精英]
  → data["is_elite"]=true + modifier + tier
  → EnemyBase._ready() 或场景生成时
  → call_deferred("_inject_elite_active_skills", modifier, tier)
    → EliteActiveSkillComponent.new(self, tier)
    → add_child(comp)
    → inject_elite_skills(self, modifier_id, tier) [静态工厂，路由技能注册]
  → comp.elite_skill_triggered.connect(_on_elite_skill_triggered)

EnemyBase._physics_process(delta) [每帧]
  → _ai_tick(delta) [awareness_enabled=true]
  → (NEW) comp.tick(delta) [遍历子节点，调用elite_skill_triggered的组件]
    → _evaluate_elite_skills(delta) [技能冷却递减]
    → 冷却归零时 → _execute_elite_skill(skill) [执行6种精英技能]

6种精英主动技能：
- elite_charge：精英冲锋，接触伤害+击退
- shield_reflect：护盾反射，反弹玩家投射物
- elite_rally：召集令，范围内友军移速+伤害buff
- elite_enrage：狂暴化，低血量时属性提升
- skill_countershot：反制射击，概率沉默玩家
- elite_teleportstrike：瞬移打击，传送到玩家背后AOE
```

---

## 三、验证

- [x] Godot headless --check-only --quit: **EXIT 0** ✅
- [x] 链路：_physics_process → comp.tick(delta) → _evaluate_elite_skills → _execute_elite_skill ✅
- [ ] 人类试玩：精英怪实际执行冲锋/召集/护盾反射等主动技能

---

## 四、下轮最可能方向

1. **第二关专属怪物掉落表**：floor=2 战斗/精英/搜刮房间独立掉落表
2. **精英挂枪视觉深化**：当前只有🔫 emoji badge，可升级为 AttachGunToBullet 实际射击
3. **人类试玩验证**（最高优先级，所有核心系统已通过代码链路审查）

---

## 五、循环状态

- 状态：`running`
- 已完成轮次：325（本次325）
- 当前设计文档：`docs/PH06_怪物系统.md`
- 方向：游戏打磨 / 内容扩充 / 第二关 / 怪物种类 / 武器差异性 / 关卡设计