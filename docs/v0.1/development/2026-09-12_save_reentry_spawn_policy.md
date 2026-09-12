# SAVE-RUN｜重登出生点策略调整

日期：2026-09-12。功能：`SAVE-RUN`、`ENTRY-AVATAR`。设计修订：09／16，随本记录同步更新。

## 变更

- 有效`combat`快照继续恢复同一行动的布局、房间进度和物品状态，但角色固定投放到快照`current_floor_index`对应的`stair_entry`安全房间中心，不再使用战斗房内精确坐标。
- 100F天台和99F基地的运行快照标为`scope=base`，不再续局；它们只记录最后下线的基地楼层。下次无可续局行动时，100F进入固定天台点，99F进入固定基地中心点。
- 无基地快照的旧档保持`tutorial_completed`兼容分流。

## 实现与验证

- `Dungeon3D`只接受`scope=combat`作为可续局行动；`TowerDescent3D`负责入口安全房间解析和100F／99F固定点。
- `verify_tower_runtime_restart_restore`更新为断言98F战斗快照重登后落在`floor_01_entry`中心，同时仍核对布局、进度和物品恢复。
- 本记录的验证结果以本轮命令输出为准；未执行项不得视为通过。
