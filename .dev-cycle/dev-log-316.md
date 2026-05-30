# 轮次 316 — 2026-05-28 13:08 UTC+8

### 维度
**怪物技能完整化 + 武器种类差异性深化**

**本轮主人明确优先级：怪物种类/技能/差异性 + 武器种类差异性设计调整。**

---

## 一、当前状态审查

### 怪物系统问题

**问题 1：Tank 的格挡机制是空壳**
- `EnemyTypes.gd spawn_tank()` 设置 `shield_rate = 0.3`
- 但 `EnemyBase.gd take_damage()` 从不检查 `shield_rate`
- 格挡永远不会触发

**问题 2：武器种类只定义了数值，没有行为差异**
- `WeaponPresets` 只有数值，但没有 gun body 的 fire_type（burst/continuous/prestige等）
- 所有枪械共用同一个 `Bullet.tscn` 发射流程，行为差异仅靠数值
- 缺乏"冲锋枪近距离倾泻"vs"步枪中距离稳定"vs"狙击枪单点爆发"的行为区分

### 武器数值现状（轮次315已调整）
| 枪械 | DPS | 定位 |
|---|---|---|
| LMG | 168 | 持续压制，换弹4.2s |
| 冲锋枪 | 135 | 近距离倾泻 |
| 步枪 | 132 | 中距离万能 |
| 手枪 | 63 | 副武器/起步 |
| 霰弹枪 | 72×5 | 近距离爆发 |
| 狙击枪 | 58 | 单发高伤害 |
| 榴弹 | 31.5 | 范围AOE |

**需要补充：**
1. Tank 格挡机制完整实现
2. 武器系统新增一种差异化枪型（步枪系+霰弹系各需要专属behavior tag）
3. 怪物词缀系统已有6个完整实现（本轮不重复）

---

## 二、本轮改动：Tank 格挡机制完整实现

### 机制设计
- `take_damage()` 第一行检查 `shield_rate > 0`
- 每次受到伤害时，`randf() < shield_rate` → 完全抵挡本次伤害
- 格挡触发视觉反馈：Shape 白光闪烁 + "格挡"文字弹出
- 记录格挡次数用于调试

### 代码改动（EnemyBase.gd）
```gdscript
# take_damage 开头增加格挡检测
func take_damage(amount: int, is_crit: bool = false, hit_dir: Vector2 = Vector2.ZERO) -> void:
    if _is_dead:
        return
    # === 护盾格挡（Tank类精英/护盾型敌人）===
    var shield_rate_val: float = get("shield_rate")
    if shield_rate_val > 0.0 and randf() < shield_rate_val:
        _spawn_block_effect()
        return  # 完全抵挡本次伤害
    ...
```

### 视觉反馈
- 格挡时 Shape 闪白色（0.12s）
- 弹出 "格挡" 文字（白色，中文，金色边框）
- 触发少量屏幕震屏（intensity=2.0）

---

## 三、本轮改动：武器新增 burst 自动步枪类型

### 设计意图
现有武器都是"连续射击"（automatic）或"单发"（semi-auto）。新增 **Burst Assault Rifle（爆发突击步枪）**：
- 每次扳机扣下发射 3 连发（burst）
- 每发伤害略低于步枪，但 3 连发总伤害超过步枪
- Spread 略高于步枪，近距离散布更大，中距离精准
- 与冲锋枪区分：冲锋枪是持续倾泻，burst 是短促爆发

### 实现
- `gun_burst_rifle()` → AssemblyNode，tags: `["rifle", "burst", "assault"]`
- `fire_rate = 3.0`（每秒扳机扣下次数）
- `bullet_count = 3`（每次扣下3发）
- `spread = 0.10`（比步枪 0.07 略散）
- `magazine_size = 24`
- `damage = 18`（单发伤害，3发共54，单次爆发超过步枪54/2.2s=24.5/s）
- Burst rifle DPS = 54×3.0=162，介于 LMG 和冲锋枪之间

### 定位
- 中距离爆发型：优于冲锋枪的中距离精准压制
- 优于霰弹枪的中距离单次爆发（但霰弹扇形）
- 比狙击枪更高DPS但比狙击更近（爆发vs单发）

### 验收
- [x] Godot headless --check-only: EXIT 0
- [x] Burst Rifle 在 `get_preset_by_index(7)` 和 `get_preset_name(7)` 中注册
- [x] 武器树中 burst tag 可被命运卡片识别

---

## 四、玩家可感知结果

**Tank（护盾型怪物）**：
- 每次受到攻击有 30% 概率完全格挡（视觉白闪+格挡文字）
- 玩家会注意到格挡效果，需要更持续输出才能击杀

**武器新增**：
- 爆发突击步枪（第8种枪械）：3连发爆发，中距离精准压制
- 填补了冲锋枪（持续）和狙击枪（单发）之间的空白

---

## 五、验收标准
- [x] Tank 格挡逻辑：take_damage() 随机数 < shield_rate 时触发格挡 ✅
- [x] 格挡视觉反馈：Shape 白闪 + "格挡" 文字弹出 ✅
- [x] Godot headless --check-only --quit: **EXIT 0** ✅
- [x] 武器种类：7 → 8种（新增 burst_rifle）✅
- [ ] 人类试玩：Tank 受到攻击时观察格挡触发（30%概率）
- [ ] 人类试玩：Burst Rifle 射击节奏是否为 3 连发短促爆发

---

## 六、下轮最可能方向
1. **RoomWaveSpawner 接入第7/8种武器类型**，使新枪械能在房间中作为掉落/装备出现
2. **精英词缀与 EliteGrowthModule 联动**：当前词缀是静态注入，精英升级后词缀增强
3. **人类试玩验证**（最高优先级）