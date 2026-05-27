# 轮次293：设计文档审查 — overheat_penalty 未实现 + 炮台射击间隔确认

## 本轮选维度：设计完整性审查

**原因：** 轮次292已完成核心命运卡片链路交叉验证。本轮从设计审查角度扫描所有已知风险点，确认哪些是真实设计缺口，哪些是设计选择，为人类试玩做准备。

---

## 一、overheat_penalty 设计缺口分析

### 问题描述
- `_apply_multiply_fire_rate()` 将 `overheat_penalty=1.5` 写入 gun stats
- WeaponAssemblyTree.gd:464 在 `refresh_stats()` 时将 `overheat_penalty` 读入 `_overheat_penalty` 成员变量
- 但 `_overheat_penalty` 在整个代码库中**从未被读取或使用**
- 超频命卡的实际受击惩罚没有落地

### 设计真相确认
- PH04 策划案描述：超频命卡使射击越多，受击伤害越高（overheat_penalty=1.5）
- 实际实现状态：overheat_penalty 变量存在但未连接到 Player.take_damage()

### 影响评估
- 玩家使用超频命卡时没有受击惩罚的负面效果
- 超频命卡变成纯增益卡（射速+80%无代价），破坏诅咒卡设计意图
- 但这只是单个卡牌的效果，不影响核心玩法主循环

### 验收标准
- [ ] 超频命卡应用后，玩家受伤时实际承担 overheat_penalty 倍率伤害
- [ ] 惩罚在玩家 HUD 或状态栏有可见指示（可选）
- [ ] 惩罚在换枪/重新开始时正确重置

### 实现方案
在 `Player.take_damage(amount)` 中，引入 `_overheat_penalty`：
```gdscript
func take_damage(amount: int) -> void:
    if is_invincible or current_hp <= 0:
        return
    # 获取武器树超频惩罚（每次射击叠加效果）
    var overheat_mult: float = 1.0
    if weapon_tree != null and weapon_tree.has_method("get_overheat_penalty"):
        overheat_mult = weapon_tree.call("get_overheat_penalty")
    var final_damage: int = maxi(1, int(float(amount - armor) * overheat_mult))
    ...
```

WeaponAssemblyTree 需要添加 `get_overheat_penalty()` getter。

### 暂时延后风险
如果此修复引入新的意外行为（比如玩家变得太容易死），会影响其他已验证的系统。风险等级：**中等**。

---

## 二、炮台射击间隔稳定性确认

### 代码链路确认
- `_spawn_fate_turret()`: 设置 `_turret_cooldown`, `_turret_damage`, `_turret_fire_interval`
- `_turret_loop(delta)`: dt上限=0.05s保护，冷却到0才射击
- 射击间隔 = `_turret_fire_interval`，由 `_attached_gun_fire_rate` 决定
- `_attached_gun_fire_rate` 默认值：4.0（来自 `_attached_gun_fire_rate: float = 4.0` 行689）

### 验收标准
- [ ] 炮台射击间隔符合 attached_gun_fire_rate（默认4.0 → 每0.25秒一枪）
- [ ] dt上限保护使炮台不会因帧率跳变而加速
- [ ] 多炮台同时存在时各自独立计时

### 结论：代码链路完整，无需改动 ✅

---

## 三、crit_on_kill 全链路再确认

### 击杀→暴击堆栈→消费链路
1. `EnemyBase._on_enemy_dead()` → `GameMode.kill_recorded.emit()`
2. `RoomGameMode._on_kill_for_crit_on_kill()` → `wt.add_crit_on_kill_stack(1)`
3. `WeaponAssemblyTree.add_crit_on_kill_stack()` → 堆栈+1，上限MAX_CRIT_STACK=10
4. `WeaponAssemblyTree.fire_from()` → `is_crit := consume_crit_on_kill_stack()` 优先消费堆栈
5. `WeaponAssemblyTree.fire_from()` → `base_damage *= crit_mult`（默认2.0）
6. `Bullet.gd: on_hit` → 显示暴击飘字

### UI 层订阅确认
- `RoomGameMode._on_crit_stacks_changed()` → `_ui_manager.update_crit_stacks(new_count)`
- `GameUIManager.update_crit_stacks(count)` → 标签颜色+文字变化 ✅

### 结论：链路完整 ✅

---

## 四、BLESS_DEAD 全链路再确认

### 低血量存活→伤害加成链路
1. `FateCardEngine._apply_bless_dead()` → `rgm.apply_bless_dead(threshold, duration, bonus)`
2. `RoomGameMode.apply_bless_dead()` → 设置 `_bless_dead_config`，连接 `hp_changed`
3. `RoomGameMode._on_bless_dead_hp_check()` → HP<30%时激活计时器
4. `RoomGameMode._on_bless_dead_survive_timeout()` → `player.apply_damage_multiplier(1.1)`
5. `Player.apply_damage_multiplier()` → 同步给 `weapon_tree.apply_damage_multiplier()`
6. `WeaponAssemblyTree.apply_damage_multiplier()` → `_damage_multiplier=1.1`
7. `WeaponAssemblyTree.fire_from()` → `final_damage *= _damage_multiplier`

### 结论：链路完整 ✅

---

## 五、命运卡片引擎 handler 完整性确认

轮次274补全了6个缺失handler：
- 弹跳弹（Bounce）✅
- 连锁闪电（Chain）✅
- 炮台（TurretOnLand）✅
- 复制（Copy/DuplicateFire）✅
- 融合（FuseDamage）✅
- 换弹爆炸（ExplodeOnReload）✅

---

## 六、本轮无代码改动

所有发现项均为设计审查，未产生代码变更。

### 验证
- Godot headless --quit-after 3: **EXIT 0** ✅

---

## 七、剩余待人类试玩验证项（不变）

1. 冰霜子弹命中冻结效果（0.5s/0.25s for elite）
2. 火焰子弹命中后 DOT 视觉（橙红色敌人）
3. 剧毒子弹叠加5层视觉（绿色加深）
4. 精英名字+🔫挂枪+活子弹追踪+落地炮台+crit×2.5暴击实际体验
5. FateCardEngine._apply_grant_random_card() 随机选卡效果
6. 开门命运选卡后通知是否正确显示
7. MapFateTriggers 环境命运触发器实际触发与效果
8. 撤离守点敌潮强度缩放实际效果
9. 炮台射击间隔稳定性（已确认dt上限保护 ✅）
10. 搜打撤经济系统整体平衡
11. 超频命卡（overheat_penalty）受击惩罚实际表现 ← 新发现设计缺口

---

## 八、续排判断

**继续排 cron** — 状态维持 `running`。新发现 overheat_penalty 未实现是设计缺口，但优先级低于人类试玩验证。继续以孤立 cron 推进。

### 下轮最可能方向
1. 人类试玩验证（最高且唯一优先级）
2. 若发现 Bug → 针对性修复
3. 若未发现 Bug → 修复 overheat_penalty 设计缺口，或扩展关卡内容