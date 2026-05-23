## 轮次38补充 — 怪物出生位置优化

**时间:** 2026-05-22 21:30 UTC

### 本轮目标
战斗房同波次敌人在出生点重叠，看着很假。需要让敌人在房间内随机分散。

### 改动内容
- `RoomWaveSpawner.gd`: `_get_spawn_position()` 新增 `room_size` 参数，限制出生点在房间矩形内
- `RoomWaveSpawner.gd`: 同波次敌人生成前预先生成所有位置，确保 `min_spawn_distance=60px` 不重叠
- `RoomGameMode._start_combat_waves()`: 传入 `room_data.size` 让各房间尺寸生效
- `RoomData.gd`: 添加 `size` 字段并在 `RoomFactory` 生成房间时注入

### 验收
- 同波次敌人在房间内分散出生，不再重叠
- Godot headless 编译 EXITCODE: 0 ✅
- 逻辑保持：出生点随机但不超出房间边界，间隔足够不重叠