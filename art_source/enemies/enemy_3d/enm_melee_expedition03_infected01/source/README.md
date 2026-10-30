# 远征03 · 普通感染者（T Pose 制作源）

AssetID：`ENM-MELEE-EXPEDITION03-INFECTED01`；制作状态：`authored`；制作日期：2026-10-30。

按用户提供的感染者参考图制作：凸眼、张嘴长舌、米白破旧衬衫、灰绿皮肤、深灰宽裤与短脚。整体以简约大轮廓为主，双臂水平展开成 T Pose。

| 项目 | 实测 |
|---|---|
| 高度 | 1.600 m，脚底 Z=0 |
| 原点 / 前向 / 根缩放 | 脚底中心 / Blender −Y / 1,1,1 |
| 网格 | 475 面，求值后仍为 475 三角，389 顶点 |
| 材质 | 4 个共享角色材质，颜色仅由色板 UV 选择 |
| 骨架 | SKEL-INFECTED01-002，20 骨，双母版 rest 签名一致 |
| 动作参考 | 单帧 `TPOSE_reference`，未制作战斗动作 |
| 验收 | 保存后独立重载，591/591 项通过，退出 0 |

v002：按用户红框，将肩部到手掌长度缩短约50%，臂展由1.900米改为1.130米；保持T Pose。非手臂网格、UV、面材质与其它骨骼位置逐项对照未变。参考标注见 `reference_arm_length_v002.png`。

## 文件

- [模型母版](enm_melee_expedition03_infected01_model_v002.blend)：本地可编辑网格和骨架。
- [动作参考母版](enm_melee_expedition03_infected01_animation_v002.blend)：同一静止骨架；网格以相对路径链接模型母版，保留编辑来源。
- [用户参考图](reference_infected01.png)。
- [完整资产清单](enm_melee_expedition03_infected01_manifest_v002.json)与[源专项验收摘要](source_validation_v002.json)：含文件 SHA-256 与骨架签名。

## NPC／怪物共享色板

运行 PNG：`assets/art/shared/palette/npc_palette_10x10_512.png`。
分层源 PSD：`art_source/shared/palette/npc_palette_10x10_512_v001.psd`。
色格表：`art_source/shared/palette/npc_palette_recipe_v001.json`。

沿用场景规则：512×512、10×10 纯色格，第10列为冷调灰阶；唯一外链，不打包、不复制到模型目录；贴图采用 Closest；只保留活动编辑/渲染层 `PaletteUV`。
每个面保留有面积的小 UV 岛，完全位于单个色格的安全内区。改色时在 Blender 的 UV Editing 中选择面岛，移至另一个色格，不新增材质球。

## 接入边界

本次交付是远征03用途的 Blender 制作源，已登记敌人账本；没有修改刷怪池、AI、数值或碰撞，也未建立 Godot PackedScene。
已核对消费者为 `Enemy3D` / `EnemyAvatar3D`。当前控制器另有 0.70×种类×变体缩放，不能把源高度直接当成游戏内高度；按默认0.70挂接约为1.12m，正式接入时需另外确定并验收展示高度，不在源内隐藏补偿。
12态名称仅保留为未来消费契约；本次没有制作或验证12态动作与运行时映射。

## 重建与验收

从工程根使用 Blender 4.5：

```powershell
blender --background --factory-startup --python-exit-code 1 --python scripts/blender/build_expedition03_infected.py
blender --background --factory-startup --python-exit-code 1 --python scripts/blender/audit_expedition03_infected.py
```

重建前会备份已有同名双母版到工程外会话目录。重建后必须重新审计，并同步账本、清单和源索引哈希。
正面、侧面、背面与三分之四预览位于工程外 `ShellStorm2-work/sessions/2026-10-30_expedition03_infected/v002/`，相机和灯光不进入母版。
