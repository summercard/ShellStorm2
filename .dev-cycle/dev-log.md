
## 轮次 59 — 信标道具使用流程打通

**时间**: 2026-05-23 08:24
**维度**: 搜打撤深化 — 撤离 UI 完整链路

### 玩家可感知的变化
- 房间清理后显示撤离类型选择按钮（标准/信标/Boss/精英/交易）
- 信标撤离消耗道具后真实扣减信标数量
- 撤离读条有进度条 + 剩余时间显示
- 玩家可以主动中断撤离读条
- 撤离成功后显示成功面板和带出物品清单

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/ui/GameUIManager.gd | 新增撤离按钮构建、路由、读条UI、更新信号连接 |
| src/game/RoomGameMode.gd | 提前信标同步到 UI 绑定之前；背包变化时同步信标数 |

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 剩余风险
- BOSS_KILL / ELITE_KILL / TRADE 撤离条件尚未完全接入房间完成状态
- 实际信标道具使用流程需人类试玩验证
- 副枪瞄准跟随主枪方向（非独立寻敌）

### 下轮最可能方向
1. 信标消耗后 UI 同步信标数量 + 其他撤离类型逻辑验证
2. 精英怪成长系统对接撤离点
3. 武器装配树可视化完善

## 轮次 66 — 撤离按钮可用性完善（BOSS_KILL/ELITE_KILL/TRADE）

**时间**: 2026-05-23 13:51
**维度**: 搜打撤深化 — 撤离 UI 状态反馈

### 玩家可感知的变化
- 房间清理后，未解锁的撤离类型按钮显示为灰色 disabled 状态
- 鼠标悬停时显示明确禁用原因（无信标/Boss未击败/精英未击败/货币不足）
- 玩家可清晰判断哪些撤离选项当前可用

### 本轮改动
| 文件 | 改动 |
|---|---|
| src/ui/GameUIManager.gd | `_build_extraction_buttons()` 新增 `btn.disabled` 和 tooltip；新增 `_get_extraction_disabled_reason()` 返回禁用提示文案 |

### 验证
- Godot headless --quit-after 1: EXIT 0 ✅

### 遗留问题
- `_can_use_extraction_type` 中对 BOSS_KILL/ELITE_KILL 的判断依赖 `get_points_by_type(extraction_type, true)` 返回数量 > 0，这个逻辑是正确的（前提是 ExtractionDirector 在对应事件时创建并解锁了撤离点）
- 目前 BOSS_KILL 点由 `BossRoomDirector` 在 Boss 死亡时创建；ELITE_KILL 由 `notify_enemy_killed` 中的 `unlock_elite_extraction()` 在精英死亡时创建。两者均已正确实现。
- 需要人类试玩验证：信标消耗后按钮确实禁用且刷新；精英撤离按钮在精英死亡后从灰变亮

### 下轮最可能方向
1. 容器→InventoryUI刷新实际验证（LootModule 发放物品 + UI 刷新链路）
2. RoomWaveSpawner 精英识别和 EliteArchiveModule 对接
3. 武器装配树可视化
