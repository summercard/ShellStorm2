# ShellStorm2 玩家角色资产契约

## 母版

- 路径：`assets/art/characters/player/chr_player_avatar_template_3d/source/chr_player_avatar_template_source_v001.blend`
- 资产ID：`CHR-PLAYER-AVATAR-TEMPLATE-001`
- 单位：1 Blender Unit = 1米
- 总高：1.50m
- 原点：脚底地面中心，Z=0
- 正面：Blender -Y；Godot -Z
- 正式根缩放：`Vector3(1,1,1)`

## 稳定槽位

`body`、`head`、`hand`、`feet`、`hat`、`glasses`、`lower_body`。运行时衣柜首期展示前6类；`lower_body`保留为正式扩展槽。

## 稳定挂点

`Weapon`、`StowedWeaponPrimary`、`StowedWeaponSecondary`、`Backpack`、`LowerBody`、`Hat`、`Glasses`、`EarL`、`EarR`。精确Blender坐标记录在母版旁的 `chr_player_avatar_template_manifest_v001.json`，不要手工抄写后另建第二套数值。

## 所有权

- GLB/角色变体PackedScene：视觉、材质、槽位节点、表现挂点。
- `scenes/Player3D.tscn`及其脚本：玩法碰撞、HP、输入、武器、手电、状态机。
- 衣柜：只写合法外观ID到 `BaseData.avatar_customization`。

组件替换不得改变玩法所有权。需要新玩法接口时应另立需求，不在美术导入步骤中顺手拼接。
