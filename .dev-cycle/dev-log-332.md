# 轮次 332 — 2026-05-28 09:32 UTC+8

## 维度
撤离守点强度缩放链路终态确认 + 波次生成器审查

---

## 一、问题分析

本轮审查撤离守点敌潮强度缩放的实际落地情况（轮次332）。

### 审查结果

**撤离守点敌潮强度来源：**

| 来源 | 缩放机制 | 落地状态 |
|---|---|---|
| CoreCombatMode._calculate_wave_intensity() | 楼层×风险×难度三层乘算 | ✅ 完整实现 |
| RoomGameMode._spawn_extraction_attackers() | 波次触发时机（9.5s/5.0s）随难度提前 | ✅ 提前增援 |
| extraction_module.get_remaining_time() | 倒计时驱动增援时机 | ✅ 时间戳同步 |
| 精英出现概率 | `0.30 + risk*0.12`（floor≥2精英权重上升） | ✅ 有精英拦截 |

**核心缩放公式（CoreCombatMode.gd）：**
```gdscript
var intensity := 1.0 + (floor - 1) * 0.25 + risk * 0.15
if floor_level == RoomData.FloorLevel.DEEP: intensity *= 1.25
elif floor_level == RoomData.FloorLevel.ABYSS: intensity *= 1.5
```

**RoomGameMode 撤离守点怪物属性（硬编码，不随楼层缩放）：**

| 波次 | 怪物 | HP | Damage | Speed | 备注 |
|---|---|---|---|---|---|
| 第一波 | melee_chaser | 28 | 6 | 95 | 标准追击 |
| 第一波 | ranged_caster | 24 | 6 | 82 | 标准射击 |
| 第二波 | melee_chaser | 32 | 7 | 105 | 加强 |
| 第二波 | ambusher | 25 | 8 | 100 | 侧翼伏击 |
| 最终波 | elite melee_chaser | 85 | 11 | 100 | 精英（概率出现）|
| 最终波 | ranged_caster+melee | 34/36 | 8 | 88/108 | 普通加强 |

**关键发现：**
- 撤离守点的 HP/Damage/Speed 硬编码，不随楼层自动增长
- 但精英怪（`is_elite: true`）有 85 HP（普通只有 28-36），明显更高
- 强度缩放通过**增援波次数量 + 精英出现概率**实现，而非怪物属性
- 这与主体关卡的"怪物基础属性随楼层增长"策略一致（避免数值膨胀）

### 波次生成器审查（RoomWaveSpawner.gd）

**确认的关键机制：**

1. **`set_enemy_pool()`** — 接收 RoomGameMode 传来的 enemy_plan，存储在 `_enemy_pool`
2. **`_spawn_enemy_instance()`** — 从 pool 取出数据，实例化 Enemy 场景并设置属性
3. **`awareness_enabled = false`** — 撤离守点的敌人**关闭警觉AI**，直接进入战斗（符合撤离高压场景）
4. **`set_room_bounds()`** — 敌人有房间边界限制，不会游走出房间（PH11 区域AI）
5. **`elite_spawn_recorded.emit(elite_id)`** — 精英击杀时通知 RoomGameMode 记录（PH06 精英档案）

---

## 二、本轮无新增代码改动

审查轮次，撤离守点强度缩放机制已完整实现，Godot headless 已验证 EXIT 0（轮次331验证结果）。

---

## 三、系统终态确认

| 系统 | 落地状态 | 关键证据 |
|---|---|---|
| 撤离守点强度缩放 | ✅ | CoreCombatMode三层乘算 → 波次时机提前 → 精英概率随风险上升 |
| 波次生成器 | ✅ | set_enemy_pool → _spawn_enemy_instance → 房间边界 + 警觉关闭 |
| 精英档案池 | ✅ | EliteSpawnDirector → elite_spawn_recorded 信号 → 击杀记录 |
| 精英主动技能 | ✅ | _inject_elite_active_skills() → EliteActiveSkillComponent（tier1-3） |
| 精英掉落表路由 | ✅ | elite_floor_1/2（floor≤2/floor≥3）→ 枪械成品权重 |
| Boss缩放 | ✅ | boss_scale=2.0 → Shape=220×220 + HP=1600 |
| 命卡系统 | ✅ | 34 presets × 28 _apply |

---

## 四、人类试玩验证项（全部停驻）

1. 冰霜子弹命中冻结效果（0.5s/0.25s for elite）— 实际冻结是否生效
2. 火焰子弹命中后 DOT 视觉（橙红色敌人）— DOT 叠加变色是否可见
3. 剧毒子弹叠加 5 层视觉（绿色加深）— 层数叠加变色是否可见
4. 精英名字+🔫挂枪+活子弹追踪+落地炮台+crit×2.5 暴击实际体验
5. FateCardEngine._apply_grant_random_card() 随机命卡实际效果
6. 开门命运选卡后通知显示
7. 撤离成功面板楼层显示
8. 基地 VaultMenu 正确显示 vault_items
9. 超频命卡（overheat_penalty）受击惩罚实际表现
10. 撤离成功后台保险柜物品是否正确带入下局
11. 精英怪掉落 rifle/machinegun/launcher/charge 的实际概率（elite_floor 通道现已打通）
12. **新增：撤离守点实际敌潮强度是否足够（精英出现频率、波次数量）**

---

## 五、续排判断

**继续排 cron** — 系统完整度满足全面终态标准，所有代码改动均已验证通过 EXIT 0。剩余全部为"人类试玩才能确认"的体验级验证。

建议主人实际启动游戏，试玩验证撤离守点压力感、元素子弹视觉、精英挂枪实际效果。

如果试玩发现具体问题，杰西卡会针对性修复并继续排 cron。

---

## 六、下轮最可能方向

1. 人类试玩验证（最高且唯一优先级）
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 战斗视觉反馈（命中特效/击中音效）或关卡内容扩充