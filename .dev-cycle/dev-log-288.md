# 开发日志 — 2026-05-28

## 轮次 288 — 2026-05-28 03:10 UTC+8

### 维度
**命运卡片系统 Bug 修复：fire() 状态残留导致跨子弹状态泄漏**

### 问题发现
在审查命运卡片系统时，发现 `fire()` 方法（每次发射时重置状态）存在**严重的状态泄漏 Bug**：
- 只重置了 `_fate_bounce_count` 和 `_fate_chain_count`，但没有重置 `_fate_bounce`、`_fate_chain` 等核心布尔标志
- 没有重置 `_fate_fuse_type`、`_fate_fuse_dot_dps` 等元素 DOT 属性
- **没有还原子弹颜色**：上一发如果被命运卡片染成橙色/蓝色/绿色，下一发发射时如果没触发 crit，颜色会残留
- 上一发的 `_fate_scale`、`_fate_homing`、`_fate_explode_on_reload` 等状态理论上会泄漏到下一发普通子弹

### 玩家可感知结果
**修复前**：不同类型命运子弹连续射击时，子弹颜色、行为可能在发射瞬间混淆
**修复后**：每发子弹都从干净状态开始，颜色正确，命运效果不会跨子弹残留

### 修改内容

#### `src/bullet/Bullet.gd` — `fire()` 方法状态重置段
完全重写重置逻辑，新增：
- 重置所有 `_fate_bounce`、`_fate_chain`、`_fate_homing`、`_fate_uncontrolled_gun`、`_fate_size_growth`、`_fate_spawn_turret_on_land`、`_fate_home_on_land`、`_fate_explode_on_reload` 标志
- 重置所有 `_fate_fuse_*` DOT 属性和 `_fate_fuse_type`
- **新增颜色还原**：`shape.color = Color.WHITE`、`glow.color` 还原为默认橙色

### 验证
- `godot --headless --check-only --quit`: **EXIT 0** ✅

### 续排判断
**不续排** — 轮次 288 完成了本轮修复，状态为 running 但当前最高优先级仍是"等待用户主导人类试玩验证"。无设计分叉、无外部依赖、无破坏性风险，系统已为人类试玩做好了准备。

### 剩余风险（人类试玩验证项）
1. 冰霜子弹命中冰冻效果（0.5s/0.25s for elite）
2. 火焰子弹命中后 DOT 视觉（橙红色敌人）
3. 剧毒子弹叠加5层视觉（绿色加深）
4. 28张命运卡片实际效果体验
5. 撤离面板物品列表（修复后）正确显示
6. FateCardEngine 随机选卡效果（环境命运触发器）
7. 撤离守点强度缩放
8. 伤害飘字（GameUIManager.show_damage_popup 实际渲染）
9. 搜打撤经济系统平衡

### 下轮最可能方向
用户试玩后反馈 → 针对性修复或内容扩展