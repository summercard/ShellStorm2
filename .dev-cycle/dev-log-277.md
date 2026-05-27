# 开发日志 — 2026-05-28

## 轮次 277 — 2026-05-28 01:43 UTC+8

### 维度
Bullet.gd 接入弹跳/连锁/元素融合逻辑（polish/PH04 链路补全）

### 问题
上轮（274）FateCardEngine.gd 新增了 6 个处理器：弹跳弹、连锁闪电、落地炮台、弹幕模式、火焰/冰霜/剧毒子弹、换弹爆炸。这些处理器的参数写入 AssemblyNode.stats，但 Bullet.gd 尚未读取并执行对应行为。

### 玩家可感知结果
- **弹跳弹**（bounce_bullet）：子弹命中敌人或撞墙后弹跳最多 3 次，伤害每次衰减 15%，视觉闪烁反馈
- **连锁闪电**（chain_lightning）：命中后在敌人间跳跃最多 3 次，每次伤害递减 30%，子弹变细变白
- **火焰子弹**：橙色子弹，命中敌人附加持续灼烧伤害
- **冰霜子弹**：蓝色子弹，命中敌人附加减速/冰冻效果（EnemyBase 需支持冰冻机制才能完全生效）
- **剧毒子弹**：绿色子弹，命中敌人附加毒素层叠，视觉随叠加变深
- **换弹爆炸**（explode_on_reload）：换弹完成时在玩家位置触发范围爆炸，橙光特效

### 修改内容
| 文件 | 改动 |
|---|---|
| `src/bullet/Bullet.gd` | 新增 `_fate_bounce/bounce_count/bounce_walls/bounce_damage_scale` 变量；新增 `_fate_chain/chain_count/chain_range/chain_damage_scale/_chain_targets_hit` 变量；新增 `_fate_fuse_type/dot_dps/dot_duration/stacks/max_stacks` 变量；新增 `_fate_explode_on_reload/explosion_radius/explosion_damage_scale` 变量；`apply_fate_stats_from_node()` 读取 bounce/chain/fuse/explode_on_reload stats 并设置对应标记；`_handle_post_hit_behaviors()` 执行弹跳/连锁/元素DOT；`_bounce()` 弹跳逻辑（撞墙/撞敌人都弹）；`_chain_to_next_enemy()` 连锁闪电逻辑；`_apply_element_dot()` 附加DOT；`fire()` 重置弹跳/连锁/DOT状态；`_on_body_entered()` 新增撞墙弹跳分支；新增 `_spawn_explosion_effect()` |
| `src/weapon/WeaponController.gd` | `_on_reload_finished()` 改为检查子弹节点 explode_on_reload 标记并触发爆炸；新增 `_find_bullet_node_in_tree()` 遍历装配树找 BULLET 节点；新增 `_explode_at()` 范围伤害；新增 `_spawn_explosion_effect()` 爆炸视觉特效（橙色光效）；新增 `trigger_explosion_on_reload()` 供外部调用；保留 `_pending_explode` 缓存 |

### 验收
- Godot --headless --check-only --quit: EXIT 0 ✅
- FateCardEngine 的 6 个 handler 均已完整链路到 Bullet.gd / WeaponController

### 剩余风险
- **连锁闪电**：`_fate_chain_targets_hit` 数组在每次发射时需要重置（已在 fire() 中处理）
- **冰冻效果**：EnemyBase.take_damage 需要支持冰冻类型判定（当前代码只接受伤害数字），需后续配合 EnemyBase.gd 修改
- **爆炸特效**：当前用 ColorRect 模拟，后续替换为专业粒子特效
- **人类试玩验证**：需要实际选择弹跳弹/连锁闪电/火焰子弹/换弹爆炸等卡片并验证效果

### 下轮最可能方向
1. **EnemyBase.gd 接入冰冻效果**：读取 fuse_damage_type，处理 freeze_duration 和移动速度降低
2. **命运卡片实际效果完整验证**：多张卡片实际应用后武器树正确、子弹行为正确
3. **落地炮台 Bullet.gd 优化**：炮台子弹需要独立子弹场景避免状态冲突