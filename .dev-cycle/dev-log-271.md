# 开发日志 — 2026-05-27

## 轮次 271 — 2026-05-27 08:03 UTC+8

### 维度
PH12 Room场景视觉化：门光效脉冲 + 开启动画深化

### 问题
门标记（DoorVisualizer）当前只有静态 ColorRect，没有开启动画。房间清理完成后，玩家只看到门板颜色从红变绿（标签层面），但门标记本身没有"变亮+脉冲"的光效来告诉玩家"这里可以走了"。这是从 PH12 第七节（轮次129/131/133）就计划好的深化项，一直未落地。

### 玩家可感知结果
- 房间清理完成后，所有门标记同步变亮（颜色更饱和）+ 脉冲光效（alpha 在 0.3~1.0 范围呼吸）
- 玩家在视觉上直观感受到"这扇门现在可以走了"
- 蓝色撤离门/红色Boss门/绿色普通门各自保持颜色特征，但解锁后光效更抢眼

### 修改内容
| 文件 | 改动 |
|---|---|
| `src/map/RoomDoorVisualizer.gd` | 新增 DoorState 枚举（INACTIVE/ACTIVE/UNLOCKED）；新增 `_door_states` 数组追踪每个门的状态；新增 `set_door_state()` 单门状态更新；新增 `set_all_doors_unlocked()` 批量解锁；新增 `_process()` 脉冲动画（只在有解锁门时运行）；新增 `_update_door_visual()` / `_apply_pulse()` 视觉刷新；`_reset()` 同步清理 `_door_states` |
| `src/game/RoomGameMode.gd` | `_configure_room_visualizer()` 末尾调用 `door_viz.set_all_doors_unlocked()`（清怪后触发门解锁光效） |

### 门光效设计
- **INACTIVE（初始）：** 基础颜色 alpha=0.6（绿色/红色/蓝色）
- **UNLOCKED（解锁）：** GLOW_COLORS 更亮 alpha=0.75，每帧脉冲 alpha 0.3~1.0 呼吸
- **颜色区分：** extraction=蓝 glow / boss=红 glow / normal=绿 glow
- **只对解锁门脉冲：** 未解锁门保持静态亮度，不消耗性能

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- 房间清理后立即重置（重新进入房间）时脉冲状态是否正确重置（_reset 已清理 _any_unlocked）
- DemoRoomChain 场景的 RoomTileMapInitializer 管理房间（无 RoomVisualizer）是否影响门光效（DoorVisualizer 节点在各场景已配置）

### 下轮最可能方向
1. **PH07精英怪档案池持久化实际验证**：eliteId 持久化、存活逃脱→档案池→再次登场链路
2. **撤离成功界面资源获取提示**：撤离成功后界面显示"本局获得 X 资源点数"（非控制台可见）
3. **PH12门框三维化**：给门框本身加立体感（厚度感、光晕边缘）
