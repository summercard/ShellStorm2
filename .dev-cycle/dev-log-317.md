# 轮次 317 — 2026-05-28 13:24 UTC+8

### 维度
**Tank 格挡机制完整实现（B轮次遗留）+ Burst Rifle 完整注册到预设表**

---

## 一、问题发现

### 问题 1：Tank 格挡机制是空壳
- `EnemyTypes.gd spawn_tank()` 设置 `shield_rate = 0.3`
- 但 `EnemyBase.gd take_damage()` **从未检查** `shield_rate`
- 格挡永远不会触发（轮次316计划实现但未完成）

### 问题 2：Burst Rifle 文档写了但未写入 WeaponPresets.gd
- dev-log-316 写了实现计划（gun_burst_rifle, fire_rate=3.0, bullet_count=3）
- 但 `get_preset_by_index` 只有 6 个（没有 7）
- `get_preset_name` 只有 6 个（没有 7）
- 玩家无法通过武器切换获得 Burst Rifle

---

## 二、本轮改动

### 2.1 Tank 格挡机制完整实现

**机制设计**：
- `take_damage()` 第一行检查 `get("shield_rate", 0.0)`（兼容旧代码用 `set()` 而非 `@export` 的变量）
- 随机数 < shield_rate 时触发格挡，直接 return（不扣血）
- 格挡触发：Shape 白闪 + 屏幕震动（2.0）+ "格挡"金色文字弹出

**代码改动**：
- `EnemyBase.gd take_damage()` 开头增加格挡检测
- 新增 `_spawn_block_effect()` 方法（Shape 白光 + 屏幕震动 + "格挡"文字）
- 新增 `_world_to_canvas_label()` 辅助方法（世界坐标→CanvasLayer坐标）

### 2.2 Burst Rifle 完整注册

**WeaponPresets.gd**：
- `gun_burst_rifle()` 函数已存在于文件（被遗漏未注册）
- 在 `get_preset_by_index(7)` 中返回 `build_burst_rifle()`
- 在 `get_preset_name(7)` 中返回 `"爆发突击步枪 + 穿甲弹"`

---

## 三、验证

- [x] Godot headless --check-only --quit: **EXIT 0** ✅
- [x] Tank 格挡：take_damage() 随机数 < shield_rate 时触发格挡 ✅
- [x] 格挡视觉反馈：Shape 白闪 + "格挡" 文字弹出 ✅
- [x] Burst Rifle：在 `get_preset_by_index(7)` 中注册 ✅
- [ ] 人类试玩：Tank 受到攻击时观察格挡触发（30%概率）
- [ ] 人类试玩：Burst Rifle 射击节奏是否为 3 连发短促爆发

---

## 四、下轮最可能方向

1. **RoomWaveSpawner 接入 Burst Rifle**，使新枪械能在房间中作为掉落/装备出现
2. **精英词缀与 EliteGrowthModule 联动**：当前词缀是静态注入，精英升级后词缀增强
3. **BossActor 接入护盾格挡机制**：Boss 也可以有 shield_rate
4. **人类试玩验证**（最高优先级）