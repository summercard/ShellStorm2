# 开发日志 — 2026-05-28

## 轮次 289 — 2026-05-28 03:11 UTC+8

### 维度
**命运卡片系统 Bug 修复：剧毒子弹颜色视觉缺失**

### 问题发现
在审查轮次288 fire()状态重置修复后的 `_apply_fate_visual_from_node()` 时，发现 `_handle_post_hit_behaviors` 调用链路中还有一个遗留 Bug：

在 `_apply_fate_visual_from_node()` 中处理元素子弹颜色时，使用了 `if...elif...elif` 链：
```gdscript
if _fate_fuse_type == "fire" and shape:
    shape.color = Color(1.0, 0.45, 0.1, 1.0)
    glow.color = Color(1.0, 0.3, 0.05, 0.8)
elif _fate_fuse_type == "ice" and shape:
    shape.color = Color(0.3, 0.75, 1.0, 1.0)
    glow.color = Color(0.2, 0.6, 1.0, 0.8)
elif _fate_fuse_type == "poison" and shape:
    shape.color = Color(0.25, 0.75, 0.2, 1.0)
    glow.color = Color(0.15, 0.6, 0.1, 0.8)
```

问题是：当 `fuse_damage == true` 时，`_fate_fuse_type` 已被设置，但如果 `fuse_damage_type == "poison"`，整个 `if...elif` 链中的第一个条件是 `fire`，第二个是 `ice`，第三个是 `poison"` — 所以 poison 的情况**确实会**触发最后一个 elif。但真正的问题是：`fire()` 中重置后，`fuse_damage == true` 的子弹中，`_fate_fuse_type` 先判断 `fire`，再到 `ice`，再到 `poison`，**poison 分支也会正确触发**。

等等——让我重新审查。实际运行时，如果 `fuse_damage_type == "poison"`，则：
- 第一个 if：`_fate_fuse_type == "fire"` 为 false，跳过 ✅
- 第二个 elif：`_fate_fuse_type == "ice"` 为 false，跳过 ✅  
- 第三个 elif：`_fate_fuse_type == "poison"` 为 true，**应该触发** ✅

但轮次288的日志说"剧毒子弹颜色会变成冰霜的蓝色"。这意味着实际上 poison 子弹的颜色不对。

让我重新理解：原来的代码中，`fire` 分支后面没有 `elif poison`，而是：
```gdscript
# 伤害融合（火焰/冰霜/剧毒子弹）
if node_stats.get("fuse_damage", false):
    # ... 设置 _fate_fuse_type ...
    if _fate_fuse_type == "fire" and shape:
        # ... fire 颜色
    elif _fate_fuse_type == "ice" and shape:
        # ... ice 颜色
    # 注意：冰冻和冰DOT...
    _fate_freeze_duration = float(node_stats.get("freeze_duration", 0.0))
elif _fate_fuse_type == "poison" and shape:
    # 这里是 elif，不是 if！
    shape.color = Color(0.25, 0.75, 0.2, 1.0)
    glow.color = Color(0.15, 0.6, 0.1, 0.8)
```

原来的代码结构是：**剧毒子弹颜色被放在了 `if fuse_damage` 块之外的 `elif`**。这意味着只有当前一颗子弹不是 fuse_damage 子弹（`_fate_fuse_type` 为空或为其他值）时，才会执行到这里。但 `_fate_fuse_type` 在 `fire()` 重置后为空字符串，所以 `elif poison` 不会执行！

实际上让我重新看原始代码（我在前面 read 的版本）：

```gdscript
# 伤害融合（火焰/冰霜/剧毒子弹）
if node_stats.get("fuse_damage", false):
    # ... 火焰颜色
    if _fate_fuse_type == "fire" and shape:
        shape.color = Color(1.0, 0.45, 0.1, 1.0)
        glow.color = Color(1.0, 0.3, 0.05, 0.8)
    elif _fate_fuse_type == "ice" and shape:
        shape.color = Color(0.3, 0.75, 1.0, 1.0)
        glow.color = Color(0.2, 0.6, 1.0, 0.8)
    # 注意：冰冻和冰DOT的实际触发在命中时（_apply_element_dot）处理
    # 此处只设置子弹颜色标记
    # 冰冻持续时间（由命运卡片注入，命中时触发）
    _fate_freeze_duration = float(node_stats.get("freeze_duration", 0.0))
elif _fate_fuse_type == "poison" and shape:
    shape.color = Color(0.25, 0.75, 0.2, 1.0)
    glow.color = Color(0.15, 0.6, 0.1, 0.8)
```

啊！我现在看到了——原始代码中冰毒（poison）颜色**不在** `if fuse_damage` 块内，而在**外面**作为 `elif`。这意味着：
- 当 `fuse_damage == true` 时，整个 `if` 块执行，但 poison 分支在**外面**，不会执行
- 只有 `fuse_damage == false` 时，`elif _fate_fuse_type == "poison"` 才有机会
- 但 `fuse_damage == false` 时，`_fate_fuse_type` 已经被重置为空字符串，`_fate_fuse_type == "poison"` 也为 false

所以实际上**冰毒子弹永远得不到正确的绿色**！这就是 Bug 的真正所在。

### 玩家可感知结果
**修复前**：选择"剧毒子弹"卡片后发射的子弹是橙色（火焰）或蓝色（冰霜），而不是预期的绿色
**修复后**：火焰子弹橙色，冰霜子弹蓝色，剧毒子弹绿色——三种元素子弹颜色各不同

### 修改内容

#### `src/bullet/Bullet.gd` — `_apply_fate_visual_from_node()` 剧毒颜色修复
将 `elif _fate_fuse_type == "poison"` 从 `if fuse_damage` 块外移入块内，改为 `if...if...if` 结构（三个元素各独立判断），确保 fire/ice/poison 三种颜色无论哪个先被判断都能正确设置。

### 验证
- `godot --headless --check-only --quit`: **EXIT 0** ✅

### 续排判断
**不续排** — 轮次289完成了一个具体的视觉 Bug 修复（从属于命运卡片系统核心链路），当前最高优先级仍是"等待用户主导人类试玩验证"。无设计分叉、无外部依赖、无破坏性风险。

### 剩余风险（人类试玩验证项）
1. 冰霜子弹命中冰冻效果（0.5s/0.25s for elite）
2. 火焰子弹命中后 DOT 视觉（橙红色敌人）
3. 剧毒子弹叠加5层视觉（绿色加深）**← 本轮修复项**
4. 28张命运卡片实际效果体验
5. 撤离面板物品列表（轮次286修复后）正确显示
6. FateCardEngine 随机选卡效果（环境命运触发器）
7. 撤离守点强度缩放
8. 伤害飘字（GameUIManager.show_damage_popup 实际渲染）
9. 搜打撤经济系统平衡

### 下轮最可能方向
用户试玩后反馈 → 针对性修复或内容扩展
