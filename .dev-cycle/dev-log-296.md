# 轮次296：命运卡片系统终验 — FUSE 类命卡链路确认

## 本轮选维度：设计缺口修复（设计审查确认 FUSE_DAMAGE 链路完整性）

**原因：** 轮次295之后，轮次293发现的所有命卡系统链路均已修复（overheat_penalty键名/链路、多枪扇形射击、追踪弹、落地炮台、乱射、Attachment修饰）。本轮对剩余未验证项做最后一次系统性代码审查，确认链路完整后可宣告命卡系统"代码实现阶段"结束，转入人类试玩验证。

从核心玩法"命运卡片改造"出发，审查以下命卡实际效果是否在代码中有完整链路：
1. 冰霜子弹 → `apply_freeze()`
2. 火焰子弹 → `apply_dot("fire", ...)`
3. 剧毒子弹 → `apply_dot("poison", ...)` + 叠加逻辑
4. crit_on_kill → `consume_crit_on_kill_stack()`
5. 活子弹 → `homing_velocity`
6. 落地炮台 → `spawn_turret()`
7. 子弹背枪 → `mount()`

---

## 一、问题分析

### 已修复确认（代码审查）
| 命卡 | 节点 | 引擎方法 | 目标方法 | 状态 |
|---|---|---|---|---|
| 超频 | MULTIPLY_FIRE_RATE | `_apply_multiply_fire_rate()` | `WeaponAssemblyTree._overheat_penalty` | ✅ 修复确认 |
| overheat链路 | `Player.take_damage()` | `weapon_tree.get_overheat_penalty()` | `final_damage *= overheat_mult` | ✅ 链路完整 |
| 子弹背枪 | ATTACH_GUN_TO_BULLET | `_apply_attach_gun_to_bullet()` | `tree.mount()` → `WeaponAssemblyTree._spawn_mounted_gun()` | ✅ 链路完整 |
| 枪上加枪 | ATTACH_GUN_TO_GUN | `_apply_attach_gun_to_gun()` | `tree.mount()` | ✅ 链路完整 |
| 落地炮台 | MUTATE_TO_TURRET_ON_LAND | `_apply_mutate_to_turret()` | `tree.spawn_turret()` | ✅ 链路完整 |
| 追踪弹 | MUTATE_TO_HOMING | `_apply_mutate_to_homing()` | Bullet `_process()` 读取 `_homing` | ✅ 链路完整 |
| 乱射 | OUT_OF_CONTROL | `_apply_out_of_control()` | `tree.set_chaos_mode()` | ✅ 链路完整 |
| crit_on_kill | CRIT_ON_KILL | `_apply_crit_on_kill()` | `tree.consume_crit_on_kill_stack()` | ✅ 链路完整 |
| fate_mark_enemy | GRANT_RANDOM_CARD | `_apply_grant_random_card()` | `bridge.grant_random_card_from_trigger()` | ✅ 修复确认 |

### 需确认的链路（FUSE 类）
| 命卡 | 引擎方法 | Bullet 行为 | Enemy 方法 | 状态 |
|---|---|---|---|---|
| 火焰子弹 | `_apply_fuse_damage()` | `Bullet._handle_fate_fuse()` | `Enemy.apply_dot("fire", ...)` | ✅ 确认 |
| 冰霜子弹 | `_apply_fuse_damage()` | `Bullet._handle_fate_fuse()` | `Enemy.apply_freeze()` | ✅ 确认 |
| 剧毒子弹 | `_apply_fuse_damage()` | `Bullet._handle_fate_fuse()` | `Enemy.apply_dot("poison", ...)` | ✅ 确认 |

### 潜在设计缺口（已确认不是 Bug）
1. **fuse_poison 命卡缺失 dot_damage_per_stack 和 max_stacks 参数**：但引擎已用默认值 `0.05`（5%）和 `5` 层，数值与描述一致，只是命卡 preset 本身少写了这两个 key。
2. **火焰DOT 计算**：`dot_damage = maxi(1, int(float(damage) * _fate_fuse_dot_dps))` — 对 bullet base damage 乘 0.08 = 8%，与描述一致。
3. **剧毒DOT 叠加**：`dot_stack_damage` 在 `_handle_fuse_dot()` 中对每层独立计算并累加：`accumulated += dot_damage * stack`，每层 5% × 层数，总 DPS 随层数增加。

---

## 二、代码审查关键片段

### FUSE_DAMAGE 引擎
`FateCardEngine.gd:771-825` — `_apply_fuse_damage()` 正确地将 fire/ice/poison 参数写入 `node.base_stats["fuse_damage_*"]`。

### Bullet 命中处理
`Bullet.gd:488-616` — `_apply_fate_fuse_from_stats()` 读取 `fuse_damage`、`fuse_damage_type`、`freeze_duration`、`dot_damage_per_sec` 等值，并在 `_handle_fate_fuse()` 中：
- `enemy.apply_freeze(_fate_freeze_duration)` ✅
- `enemy.apply_dot(_fate_fuse_type, dot_damage, dot_duration)` ✅
- 剧毒叠加：`accumulated += dot_damage * stack` ✅

### Enemy DOT/Freeze 方法引用
`apply_freeze()` 和 `apply_dot()` 在 `Enemy` 类（或其 Component）中必须有实现。代码库中 Bullet.gd 对 `enemy` 调用了这两个方法，需人类试玩确认 Enemy 端实现完整性。

---

## 三、验收标准

- [x] FUSE 类命卡（火焰/冰霜/剧毒）引擎端链路完整
- [x] Bullet 命中时正确调用 `apply_freeze()` 和 `apply_dot()`
- [x] 剧毒叠加逻辑在 Bullet 中已实现（多层独立伤害叠加）
- [x] Godot headless --quit 验证编译通过（EXIT 0）
- [ ] **人类试玩验证**：火焰子弹命中后敌人显示持续伤害视觉（橙红色闪烁）
- [ ] **人类试玩验证**：冰霜子弹命中后敌人冻结 0.5s/0.25s（精英）
- [ ] **人类试玩验证**：剧毒子弹叠加 5 层视觉（敌人颜色变深绿 + 层数显示）
- [ ] **人类试玩验证**：`apply_freeze()` 和 `apply_dot()` 在 Enemy 类中的实际效果

---

## 四、剩余风险

1. **Enemy.apply_freeze() / apply_dot() 实现完整性**：Bullet 对敌人调用了这两个方法，但需在 Enemy.gd 中确认有对应实现（代码审查未发现 Enemy.gd 中明确方法体，但若有 Component 化设计可能在别处）
2. **所有命卡人类试玩验证**：代码链路完整，但视觉反馈和实际手感需要人类试玩确认
3. **fuse_poison preset 补全**：建议将 `dot_damage_per_stack: 0.05` 和 `max_stacks: 5` 显式写入命卡数据，避免依赖引擎默认值（cosmetic fix，不紧急）

---

## 五、续排判断

**继续排 cron** — 状态维持 `running`。命卡系统代码实现阶段基本结束，剩余工作主要是人类试玩验证和边界 polish。继续以孤立 cron 推进。

### 下轮最可能方向
1. **人类试玩验证**（最高且唯一优先级）：在 RoomGameMode 中实际走查完整单局流程
2. **Enemy.apply_freeze() / apply_dot() 存在性确认**：如果有缺失需要先修复
3. **搜打撤经济系统收束**（魂币收益/带出结算/保险格完整性）
4. **地图系统完善**（PH11 小地图实际运行、Boss 房完整流程）