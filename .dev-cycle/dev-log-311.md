## 轮次 311 — 2026-05-28 08:35 UTC+8

### 维度
BossActor 房间边界链路修复

### 问题分析
审查 `_on_boss_spawned()` 链路：

**发现：`_room_bounds` 从未被设置**
- `BossActor._clamp_to_room_bounds()` 依赖 `_room_bounds`，但此变量从未被外部写入
- `BossActor` 有 `set_room_bounds(bounds: Rect2)` 公开接口
- `RoomGameMode._on_boss_spawned()` 在调用 `configure_phases()` 之前没有调用 `set_room_bounds()`
- 结果：Boss 的冲刺边界限制 (`_clamp_to_room_bounds`) 实际工作在默认值 `Rect2(-400, -300, 800, 600)`，而非真实房间边界

**修复方案**
在 `configure_phases()` 调用前，通过 `map_manager.get_current_room_data()` 获取当前房间数据，调用 `_calculate_room_bounds_for_spawn_controller()` 计算真实边界，再调用 `boss_actor.set_room_bounds()` 传入。

### 代码改动
**文件：** `src/game/RoomGameMode.gd`

```gdscript
# 在 configure_phases() 调用前新增：
if boss_actor.has_method("set_room_bounds") and boss_room_instance != null:
    var current_room_data: RoomData = map_manager.get_current_room_data()
    if current_room_data != null:
        var boss_room_bounds: Rect2 = _calculate_room_bounds_for_spawn_controller(boss_room_instance, current_room_data)
        boss_actor.call("set_room_bounds", boss_room_bounds)
        print("[RoomGameMode] 为 BossActor 设置房间边界: %s" % str(boss_room_bounds))
```

### 玩家可感知结果
- Boss 冲刺将被真实房间边界截断，不会撞墙穿出
- Phase 2 的 charge 技能在房间范围内有效

### 验收标准
- [x] Godot headless --check-only --quit: **EXIT 0** ✅
- [x] git commit: `8a9e8b3` ✅
- [ ] 人类试玩：Boss 冲刺被房间边界正确截断
- [ ] 人类试玩：Boss 阶段切换（HP 66%/33%）+ 技能施放

### 剩余风险
1. Boss 死亡信号链路（boss_defeated → BossRoomLogic → MapManager → RoomGameMode）尚未人类试玩验证
2. Phase 3 狂暴效果持续性
3. 其余所有剩余项仍为人类试玩验证

### 循环状态
status: `running` — 人类试玩验证为唯一剩余项，不续排自动化循环

### 下轮最可能方向
人类试玩验证：Boss 阶段切换 / 技能施放 / 冲刺撞墙