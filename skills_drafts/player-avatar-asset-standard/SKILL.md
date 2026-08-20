---
name: player-avatar-asset-standard
description: 为 ShellStorm2 制作、拆分、验收或导入玩家角色与可换装配件。用户提到角色Blender母版、1.5米尺寸、身体/头/手/脚/帽子/眼镜/下身附件、挂点、角色GLB、换装Prefab、角色方向比例或外观入库时使用。本Skill保存在项目草稿目录，当前不安装到Codex全局技能目录。
---

# 玩家角色资产制作与带入规范

以项目正式母版为唯一尺寸与挂点依据，生成纯表现角色组件；角色碰撞、武器、生命和状态机继续由现有 `Player3D` Prefab拥有。

## 开始前

1. 完整读取 [references/shellstorm-player-avatar-contract.md](references/shellstorm-player-avatar-contract.md)。
2. 打开 `assets/art/characters/player/chr_player_avatar_template_3d/source/chr_player_avatar_template_source_v001.blend`，不得从截图或旧场景缩放反推尺寸。
3. 阅读目标角色现有PackedScene、`PlayerAvatar3D.CUSTOMIZATION_OPTIONS`、资产台账和命名规范。

## Blender制作

1. 单位为米，角色总高基准1.50m，地面中心原点Z=0，Blender正面为-Y，Godot正面为-Z，正式根缩放为1。
2. 每个组件放入母版对应集合：`Body`、`Head`、`Hands`、`Feet`、`Hat`、`Glasses`、`LowerBody`。不得把武器、背包或展示台焊进角色网格。
3. 对齐母版挂点；保持左右件命名和轴向一致。帽子、眼镜、耳饰、下身附件不得改变角色整体碰撞。
4. 制作组件可保持可编辑；每个正式槽位建立独立输出根。应用输出副本变换、法线与三角化，不破坏源组件。
5. 角色与配件材质使用稳定语义名；变色测试优先通过现有材质/颜色参数完成，不为每个颜色复制整套逻辑。
6. 保存新版本并渲染正面、侧面、背面及游戏视角预览。运行 `scripts/blender/validate_player_avatar_asset_template.py` 验证母版。

## Godot带入

1. 源Blend进入角色资产 `source/`；槽位GLB进入 `components/`；完整角色或槽位包装进入 `runtime/`/`variants/`。
2. GLB只负责视觉。角色PackedScene保留稳定根、挂点和表现装配；`Player3D.tscn`继续拥有CharacterBody碰撞、武器、手电、HP、输入和状态机。
3. 包装根保持scale1。禁止用关卡实例的0.7或其他临时缩放修正正式角色尺寸。
4. 新外观ID先加入合法目录，再接衣柜UI与存档；非法或旧存档ID必须回退到默认外观。
5. 每类至少准备3个可选外观；衣柜只修改表现层，切换前后角色碰撞、功能脚本和武器挂点不变。
6. 更新资产台账：资产ID、类别、Prefab、GLB、源Blend、槽位、版本、功能脚本、碰撞归属和状态。

## 验收

- Blender母版验证通过，总高、原点、方向、集合和挂点齐全。
- 每个GLB可独立导入，根缩放1，正面和包围盒正确。
- 身体、头、手、脚、帽子、眼镜及下身附件可独立替换；每类至少3款测试项。
- 换装保存/读取通过，主页面和衣柜使用同一个实时角色。
- 玩家边界、八态动画、武器握持、背包/下身挂点、碰撞与战斗回归全部通过。
- 台账、设计文档和开发日志已同步。

## 禁止事项

- 不把视觉网格碰撞当作玩家主碰撞。
- 不因某个配件修改通用角色逻辑或临时打补丁。
- 不覆盖旧版本源文件，不在临时目录或桌面保存正式贴图。
- 不安装本Skill到 `.codex/skills`，除非用户以后明确授权。
