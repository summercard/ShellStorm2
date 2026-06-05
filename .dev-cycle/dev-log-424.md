# ShellStorm2 开发日志

## 轮次424（2026-05-30 20:56 UTC+8）

### 维度
**换弹爆炸机制断点修复 + Godot 编译验证**

### 问题发现

在交叉审查轮次423剩余验证项时，发现换弹爆炸命运卡片（`explode_on_reload`）存在**调用链路断裂**：

1. `_on_reload_finished_impl()` 在换弹完成时正确读取 weapon_tree 子弹节点的 `explode_on_reload` 标记并触发爆炸 ✅
2. `trigger_explosion_on_reload()` 方法被设计为供外部调用，但内部 `_pending_explode` 仅在 `trigger_explosion_on_reload()` 内被读取，且**没有任何代码向其写入**
3. 任何外部调用 `trigger_explosion_on_reload()` 都会因 `_pending_explode.is_empty()` 直接返回，导致外部调用方无法触发爆炸

### 修复方案

将 `trigger_explosion_on_reload()` 改为直接从 `weapon_tree` 读取爆炸参数：

```gdscript
func trigger_explosion_on_reload(bullet_damage: int, bullet_global_pos: Vector2) -> void:
    if weapon_tree == null:
        return
    var bullet_node: AssemblyNode = _find_bullet_node_in_tree()
    if bullet_node == null:
        return
    var stats: Dictionary = bullet_node.get_base_stats()
    if not stats.get("explode_on_reload", false):
        return
    var radius: float = stats.get("explosion_radius", 150.0)
    var damage_scale: float = stats.get("explosion_damage_scale", 0.8)
    var explosion_damage: int = int(float(bullet_damage) * damage_scale)
    _explode_at(bullet_global_pos, explosion_damage, radius)
```

同时将 `_pending_explode` 注释为"预留（暂无外部写入方）"。

---

### 改动文件
- `src/weapon/WeaponController.gd`：`trigger_explosion_on_reload()` 函数重构 + `_pending_explode` 注释更新

### 验收标准
- [x] Godot headless --check-only --quit 编译通过 ✅（EXIT 0，输出干净）
- [x] `_on_reload_finished_impl()` 仍能正常触发换弹爆炸（直接读 weapon_tree）✅
- [x] `trigger_explosion_on_reload()` 现在从 weapon_tree 读取参数，不再依赖空的 `_pending_explode` ✅
- [ ] **人类试玩验证（所有剩余验证项）**

---

### 剩余风险（全部为人类试玩验证项）
1. **元素子弹**：冰霜DOT（蓝白色）/火焰DOT（橙红色）/毒DOT（绿色）是否可区分
2. **换弹爆炸**：GPUParticles2D ExplosionEffect 是否真正触发
3. **第二关怪物强度**：HP×1.4/DMG×1.2 实际表现，6种怪物是否都出现
4. **精英怪实际表现**：🔫挂枪+活子弹+炮台+主动技能是否正常
5. **ScreenShake**：受击时 Camera2D.offset 是否正确震动
6. **命卡效果**：房间清理后命卡界面是否弹出
7. **撤离战利品面板**：成功撤离后是否正确弹出
8. **基地保险柜**：存入/取出/下局带入是否正确

---

### 续排判断
**继续排 cron** — 状态维持 `running`。

修复了一个真实的代码缺陷（`trigger_explosion_on_reload()` 从未被正确调用的问题）。所有核心系统已完整。待验证项均为**人类试玩验证项**，需要人类实际运行游戏确认。

用户尚未停止或改方向，无真实设计分叉/外部依赖/破坏性风险。

---

### 下轮最可能方向
1. **人类试玩验证（最高且唯一优先级）**
2. 若发现 Bug → 针对性修复
3. 若无 Bug → 第二关专属内容深化或战斗视觉反馈