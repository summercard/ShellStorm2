# ShellStorm2 角色反推资料

本文件记录当前工程的可核验入口，不代替执行时对目标资产的再次审计。引用路径均相对 ShellStorm2 项目根目录。

## 先读的运行时证据

| 目标 | 当前证据 |
|---|---|
| 玩家表现层 | `src/player3d/PlayerAvatar3D.gd` |
| 玩家玩法根与主碰撞 | `scenes/Player3D.tscn`、`src/player3d/Player3D.gd` |
| 当前 Bunny 变体组装 | `assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/chr_player_capsule01_bunny01_root_top3d_v006.tscn` |
| 玩家动画验收 | `tests/verification/verify_player3d_animation_flow.gd` |
| 玩家尺寸验收 | `tests/verification/verify_player3d_avatar_bounds.gd` |
| 手持/背挂验收 | `tests/verification/verify_player3d_weapon_grip_visual.gd`、`tests/verification/verify_player3d_lower_body_socket_flow.gd` |
| 敌人表现与尺寸消费 | `src/enemy3d/EnemyAvatar3D.gd`、对应 `Enemy3D` 场景和测试 |

当前 Bunny 玩家是**节点驱动角色**，不是可随意替换成 Skeleton 的角色：`BunnyRig` 下含 `BodyJoint`、`HeadJoint`、`HandRoot/HandJointL`、`HandRoot/HandJointR`、`FeetRoot/FootJointL`、`FeetRoot/FootJointR`，其状态姿势由 `PlayerAvatar3D.gd` 驱动。新玩家变体必须先确认当前消费者是否仍使用这套层级。

## 当前玩家挂点与所有权

- 角色侧正式挂点包括 `WeaponSocket`、`StowedWeaponSocketPrimary`、`StowedWeaponSocketSecondary`、`BackpackSocket` 与 `LowerBodySocket`；耳饰 socket 属于头部表现层。
- 当前右手枢轴契约：`HandJointR` 是掌心球中心；装备流程验证它与武器 `GripSocket` 重合。武器 `MuzzleSocket` 的本地 `-Z` 方向必须与实际射击方向一致。
- 角色外观可以拥有 body/head/hand/feet/hat/glasses/lower_body 等槽位，但实际可用列表与存档处理由 `PlayerAvatar3D.CUSTOMIZATION_OPTIONS` 和其消费者定义。
- `Player3D.tscn` 拥有玩家玩法碰撞、移动、生命、输入、武器、手电与状态机。角色 GLB 或外观变体不得加入或替换这些职责。

## Blender 源文件处理

当前玩家相关 Blender 入口：

- 母版：`assets/art/characters/player/chr_player_avatar_template_3d/source/chr_player_avatar_template_source_v001.blend`
- 当前 Bunny 变体源：`assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/source/chr_player_capsule01_bunny01_top3d_v006.blend`
- 旧猫形版本：`assets/art/characters/player/chr_player_capsule01_3d/source/`
- 只读审计：`scripts/blender/audit_player_avatar_source.py`
- 母版验证：`scripts/blender/validate_player_avatar_asset_template.py`

先定位实际 Blender 可执行文件，再在目标源副本上运行：

```powershell
blender --background "<角色源文件>.blend" --python "scripts/blender/audit_player_avatar_source.py"
blender --background "assets/art/characters/player/chr_player_avatar_template_3d/source/chr_player_avatar_template_source_v001.blend" --python "scripts/blender/validate_player_avatar_asset_template.py"
```

审计输出必须至少确认单位、可见网格包围盒、集合、对象父级、位置、旋转、缩放和隐藏状态。Blender 缺失时可以继续反推 Godot 消费者，但不能声称源 Blend 已验证。

## 不可混用的尺寸与方向

- 玩家母版 manifest 规定：作者参考高度 `1.5m`、地面原点、Blender `-Y` 到 Godot `-Z`、运行时根缩放 `1`。
- 当前 Bunny 运行时代码还记录了其源模型的 `+X` 原始前向、进入 Godot 时的 `90` 度修正，以及以 `1.5 / 2.475` 参与表现层换算。
- 当前 Bunny 尺寸测试验证的是运行时静态装配高度 `1.05m`，不是母版的 `1.5m` 作者参考高度。

因此，制作 Bunny 变体时不得把母版方向或高度数字直接复制到 Bunny 源文件。先选择目标资产，然后分别验证该资产的作者尺度、导出转换与实际运行时包围盒；任何改变都必须同步更新其验收测试和 manifest。
