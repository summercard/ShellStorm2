# Battle

- 场景入口：`scenes/TowerDescent3D.tscn`
- 运行时节点：`Blocks/Battle`
- 编号：`局内关卡01`（稳定，不随设定名修改）
- 设定名：`顶部数据库`（允许单独修改）
- 组合显示名：`局内关卡01-顶部数据库`
- AssetID：`ENV-TOWER-DESCENT-KIT-3D`
- 阶段：入口安全房已进入正式 Blender 美术与 Godot 接入；98–95F 其余房间、楼层和水平走廊仍为程序化/白盒
- 当前白盒：`source/art/whitebox/tower_zones/battle_level01/v002/`，含19个经 QA 的 Blender 白盒（房间、Boss竞技场、走廊模块）
- 入口安全房正式源：`assets/art/environments/tower_zones/battle/source/entry_safe_room/v003/局内关卡01_入口安全房_15x15m_正式美术_v003.blend`
- 入口安全房运行资产：`assets/art/environments/tower_zones/battle/components/entry_safe_room/v003/`（33个GLB）和 `assets/art/environments/tower_zones/battle/runtime/entry_safe_room/v003/`（33个独立PackedScene与整房总装配）
- 台账：`3D-场景通用` 中的 `ENV-BATTLE-L01-*` 逐项登记为 `battle_level01/v002/blender/` 下的文件
- 历史程序化数据：`source/art/whitebox/tower_zones/battle_level01/legacy/v011/data/whitebox_battle_98_95_v011.json`
- 效果图：`source/art/whitebox/tower_zones/battle_level01/v002/renders/`

`floor_01_entry` 是 98F 入口安全房，现由 `ENV-BATTLE-L01-SAFE-ENTRY` v003 正式美术总装配接管；其余 98–95F 房间、楼层和水平走廊仍由程序生成。`battle`、`Blocks/Battle`、AssetID 和 `局内关卡01` 是稳定身份；只修改 `setting_name` 即可更换“顶部数据库”设定名。整区战斗美术包装仍统一使用稳定文件名 `zone_battle_vNNN.tscn`。
