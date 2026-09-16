# Battle 与 Stairs 白盒目录归一

日期：2026-09-14  
工程版本：0.1.0  
功能：`WORLD-BLOCKS r3`、`ASSET-SCENE-3D r2`

## 结果

- 明确 `Battle` 98–95F 与 `Stairs` 尚处于白盒阶段，不登记为正式 Blender 美术源。
- 建立 `source/art/whitebox/tower_zones/stairs/v011/`，固定分为 `data/`、`blender/`、`renders/`。
- `data/` 分别保存战斗区与楼梯区 JSON；二者共同约束一份白盒 Blender 母版。
- 将现有 v011 母版迁移并改名为 `whitebox_tower_battle_stairs_v011.blend`，补充白盒阶段和 JSON 路径元数据；没有重新导入 GLB。
- 天台与基地正式 Blender 源保持原目录不动。
- 同步 Godot 区块元数据、导入清单、构建脚本、区块 README、设计文档和美术资产台账。

## 兼容性

现有运行 GLB、PackedScene、碰撞、AssetID 与游戏逻辑均未移动。旧 v007–v010 塔楼母版保留在原目录作为历史生成链；正式活动引用只指向新白盒目录。

## 验收

- 两份白盒 JSON 与导入清单语法检查通过，退出码0；旧 v011 活动路径残留为0。
- 文档契约检查通过，退出码0：63份文档、366条本地链接、33个功能、45个测试引用。
- 资产台账结构检查通过，退出码0：418项；全量检查仍有206项既有SHA漂移，本次三个相关ID不在漂移结果中。
- `verify_tower_level_blocks` 通过，退出码0，输出 `TOWER_LEVEL_BLOCKS_OK`。
- 未执行 GLB 重新导入、真实渲染或白盒效果图签署；`renders/` 当前只有说明文件。
