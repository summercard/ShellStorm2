# Battle

- 场景入口：`scenes/TowerDescent3D.tscn`
- 运行时节点：`Blocks/Battle`
- 编号：`局内关卡01`（稳定，不随设定名修改）
- 设定名：`顶部数据库`（允许单独修改）
- 组合显示名：`局内关卡01-顶部数据库`
- AssetID：`ENV-TOWER-DESCENT-KIT-3D`
- 阶段：白盒，尚未进入正式 Blender 美术制作
- 白盒数据：`source/art/whitebox/tower_zones/v011/data/whitebox_battle_98_95_v011.json`
- 白盒数据：`source/art/whitebox/tower_zones/v011/data/whitebox_battle_98_95_v011.json`；当前无 Blender 输出，历史合并文件已清理为楼梯专用白盒。
- 效果图：`source/art/whitebox/tower_zones/v011/renders/`

98–95F 房间、楼层和水平走廊由程序生成，因此当前没有正式美术源或独立静态区块 PackedScene。`battle`、`Blocks/Battle`、AssetID 和 `局内关卡01` 是稳定身份；只修改 `setting_name` 即可更换“顶部数据库”设定名。`runtime/` 保留给未来不改变玩法身份的战斗区美术包装。
