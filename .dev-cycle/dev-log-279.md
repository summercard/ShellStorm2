# 开发日志 — 2026-05-28

## 轮次 279 — 2026-05-28 01:59 UTC+8

### 维度
EnemyBase.gd 接入冰冻机制 + 火焰/冰霜/剧毒子弹 DOT 完整链路

### 问题
上轮（277）Bullet.gd 已接入弹跳/连锁/元素DOT，但 EnemyBase 没有 `apply_dot()` 和 `apply_freeze()` 方法，导致：
- 火焰/剧毒子弹命中时，Bullet 调用 `enemy.apply_dot()` 但敌人无此方法，退而求其次走 `take_damage()` 一次性伤害（而非真正的持续伤害）
- 冰霜子弹命中时，Bullet 尝试调用 `enemy.apply_freeze()` 但敌人无此方法，冰冻效果完全失效

### 玩家可感知结果
- **冰霜子弹**：命中敌人后，敌人冻结 0.5 秒（普通怪）/ 0.25 秒（精英怪），停止移动和攻击，视觉上呈蓝白色
- **火焰子弹**：命中后敌人持续受到灼烧伤害（每0.5秒一次），持续3秒，敌人颜色逐渐变红
- **剧毒子弹**：命中后敌人持续受到毒素伤害，持续时间内视觉变绿加深
- **DOT叠加**：同一类型DOT叠加时，伤害和持续时间都会叠加（最多5层）
- **冰冻期间DOT暂停**：冰冻时DOT计时暂停，避免同时触发视觉混乱

### 修改内容

**EnemyBase.gd：**
- 新增 DOT 状态变量：`_fuse_dot_active`、`_fuse_dot_type`、`_fuse_dot_dps`、`_fuse_dot_timer`、`_fuse_dot_duration`、`_fuse_dot_original_speed`
- 新增冰冻状态变量：`_frozen`、`_freeze_timer`、`_freeze_original_modulate`
- `_physics_process()` 前半段新增：DOT每0.5秒tick扣血、冰冻时停止移动、冻结结束恢复颜色/大小
- 新增 `apply_dot(dot_type, dps, duration)` 方法：DOT入口，刷新持续时间，叠加伤害
- 新增 `_apply_dot_visual()` 方法：DOT视觉（火焰红、毒绿、冰霜蓝）
- 新增 `apply_freeze(duration)` 方法：冰冻入口，停止移动，视觉蓝白缩放
- 冰冻时DOT不叠加（冰冻覆盖DOT）

**Bullet.gd：**
- 新增 `_fate_freeze_duration` 变量（冰冻持续时间）
- `fire()` 中重置 `_fate_freeze_duration = 0.0`
- `apply_fate_stats_from_node()` 中读取 `freeze_duration` 参数到 `_fate_freeze_duration`
- `_apply_element_dot()` 中冰冻子弹优先触发冰冻，不触发DOT
- 冰冻优先于DOT，避免冰霜子弹同时触发两种效果

### 验收
- Godot --headless --check-only --quit: EXIT 0 ✅
- Bullet.gd `freeze_duration` 参数链路完整：FateCardEngine → AssemblyNode.stats → Bullet._fate_freeze_duration → EnemyBase.apply_freeze()
- EnemyBase._physics_process 冰冻/DOT逻辑在每帧正确执行
- `fire()` 重置 _fate_freeze_duration 防止状态泄漏

### 剩余风险
- **冰冻视觉**：当前用 modulate + scale 简单表现，后续可加冰晶粒子
- **人类试玩验证**：实际用冰霜子弹、火焰子弹、剧毒子弹命中怪物，验证冰冻停止、DOT持续扣血效果
- **精英怪冰冻减半**：freeze_duration_elite 参数在 FateCardEngine 已写入但 Bullet 读取的是 freeze_duration（未区分精英）；可后续在 Bullet 命中判断敌人类型后使用不同 freeze 值

### 下轮最可能方向
1. **Human playtest**：实际选择冰霜/火焰/剧毒命运卡片并验证效果（最高优先级）
2. **落地炮台 Bullet.gd 优化**：炮台子弹需要独立子弹场景避免状态冲突
3. **精英怪冰冻时间区分**：Bullet 命中时读取 EliteModifier 判断是否精英，使用 freeze_duration_elite