# 开发日志 - 轮次340（2026-05-28）

## 本轮目标
**GameUIManager room_info_label 显示升级：第N关 + 垂直层 + 房间类型**

## 玩家可感知结果
- HUD顶部的房间信息标签现在显示「第N关 · 房间类型」（如「第2关 · 普通战斗」）
- 垂直关卡地下室/二楼的房间会显示垂直层后缀（如「第1关 · [地下室]搜刮」）
- 支持所有垂直通道房间类型（STAIRS_DOWN/STAIRS_UP/ELEVATOR/BASEMENT）

## 修改的代码/数据
| 文件 | 改动 |
|---|---|
| `src/ui/GameUIManager.gd` | `_on_room_entered_for_minimap()` 中 match 扩展 BASEMENT/STAIRS_DOWN/STAIRS_UP/ELEVATOR 分支；显示格式升级为「第N关 · 房间类型」，垂直层时加 [xxx] 后缀 |

## 设计审查（自问）
1. **顶视角射击肉鸽独特性**：不改变核心框架，是HUD信息增强 ✅
2. **新决策/记忆点**：玩家更容易读懂自己在哪里（垂直层信息），帮助搜打撤决策 ✅
3. **玩家可读懂**：显示格式直观（关卡数字+房间类型+垂直层） ✅
4. **数值健康**：纯显示逻辑，不影响数值平衡 ✅

## 验证
- Godot headless --quit-after 1: EXIT 0 ✅

## 本轮完成度
- GameUIManager.room_info_label 显示升级（包含关卡数+垂直层+房间类型） ✅
- 掉落表 floor 参数链路已确认（LootModule.generate_container_loot 使用 room_data.floor） ✅
- 垂直关卡地下室房间掉落表 `basement_floor_N` 正确性已确认（ContentInjector._inject_basement_room 使用 room_data.floor） ✅

## 剩余风险/试玩问题
- 人类试玩确认：room_info_label 在大量房间进入时的更新速度和可见性
- 掉落表 floor 数值在地下室场景是否产生预期难度/奖励（地下室掉落更丰富，需人类试玩确认）
- 楼梯交互（E键）触发垂直切换的流畅度

## 下轮最可能方向
1. **第二关怪物差异深化**：检查 floor=2 时 MonsterInjector 是否正确使用 FLOOR_SCALING[2]（hp_mult=1.4, damage_mult=1.2）
2. **垂直关卡场景视觉化**：地下室房间（RoomData.RoomType.BASEMENT）的 Visualizer TileMap 主题色（深棕橙色）是否随楼层正确应用
3. **第二关掉落表验证**：loot_floor_2/scavenge_floor_2/combat_floor_2 的实际内容（Tier1/Tier2武器模块比例）
4. **信标道具掉落验证**：`item_beacon` 在 floor=2 掉落表中的权重（boss_floor_2=4.0）