# Battle runtime

`局内关卡01-顶部数据库`的普通房间、楼层和水平走廊仍由 `TowerDescent3D.gd` 使用塔楼模块程序生成。98F `floor_01_entry` 入口安全房已由 v003 正式美术接管：

- 33 个独立 PackedScene：`entry_safe_room/v003/<package>/<package>_root_top3d_v003.tscn`
- 整房总装配：`entry_safe_room/v003/env_entry_safe_room_root_top3d_v003.tscn`
- 包内不生成覆盖式玩法碰撞；承重与门体判定继续由 `TowerDescent3D.FloorSupport + RoomDoor3D` 负责

总装配只在 `room_door_world_*` 布局元数据冻结后安装，并在初始启动、撤退重建和楼层提交后刷新；重复调用保持幂等。`局内关卡01`是稳定编号，`顶部数据库`是可变设定名。未来新增整区战斗美术时统一使用稳定文件名 `zone_battle_vNNN.tscn`，不把设定名写入路径。
