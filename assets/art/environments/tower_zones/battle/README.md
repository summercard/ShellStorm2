# Battle

- 场景入口：`scenes/TowerDescent3D.tscn`
- 运行时节点：`Blocks/Battle`
- 编号：`局内关卡01`（稳定，不随设定名修改）
- 设定名：`顶部数据库`（允许单独修改）
- 组合显示名：`局内关卡01-顶部数据库`
- AssetID：`ENV-TOWER-DESCENT-KIT-3D`
- 阶段：白盒，尚未进入正式 Blender 美术制作或 Godot 接入
- 当前白盒：`source/art/whitebox/tower_zones/battle_level01/v002/`，含19个经 QA 的 Blender 白盒（房间、Boss竞技场、走廊模块）
- 台账：`3D-场景通用` 中的 `ENV-BATTLE-L01-*` 逐项登记为 `battle_level01/v002/blender/` 下的文件
- 历史程序化数据：`source/art/whitebox/tower_zones/battle_level01/legacy/v011/data/whitebox_battle_98_95_v011.json`
- 效果图：`source/art/whitebox/tower_zones/battle_level01/v002/renders/`

98–95F 房间、楼层和水平走廊仍由程序生成，因此当前没有正式美术源或独立静态区块 PackedScene。`battle`、`Blocks/Battle`、AssetID 和 `局内关卡01` 是稳定身份；只修改 `setting_name` 即可更换“顶部数据库”设定名。`runtime/` 保留给未来不改变玩法身份的战斗区美术包装。
