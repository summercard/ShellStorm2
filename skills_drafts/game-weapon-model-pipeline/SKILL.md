---
name: game-weapon-model-pipeline
description: 制作并导入枪械和近战武器模型到 Godot，处理手持锚点、枪口/瞄具/命中挂点、武器局部动画、GLB 与 PackedScene。用于手枪、步枪、霰弹枪、刀剑、棍棒和斧类；不用于场景设施或普通可拾取道具。
---

# 枪械与近战武器模型制作、导出和 Godot 导入

制作可被角色稳定装备的武器资产。项目自己的坐标、角色骨骼、动画系统和命名契约优先于本规范。

## 边界与选择

- 适用：枪械、近战武器，以及它们的弹匣、瞄具、折叠件等武器专属可动部件。
- 不适用：建筑、固定设施和关卡模块使用场景与设施两套 skill；通用拾取物、消耗品、钥匙、容器和投掷物使用 `game-prop-model-pipeline`。
- 武器模型交付视觉、局部可动结构、稳定锚点和武器自身动画；角色系统交付手臂/手指姿势、全身动作、IK、瞄准、后坐力叠加、状态机和网络权威。

## 制作与导出

1. 先读取项目的武器类别、角色挂点、第一/第三人称策略、坐标轴、单位、材质与动画契约。没有项目契约时采用本 skill 的默认锚点约定。
   在 ShellStorm2 中，必须先读取 `game-character-model-pipeline` 所列的角色消费者：当前角色侧为 `WeaponSocket`，武器侧为 `GripSocket` 和 `MuzzleSocket`。这些项目名优先于本 skill 的通用 `GripAnchor`、`MuzzleAnchor` 命名，不能同时创建两套语义相同的挂点。
2. 保留可编辑源组件，导出独立游戏输出；不要把角色手、手套、手臂、角色骨骼或关卡展示物导入武器 GLB。
3. 输出根为 `WeaponRoot`，原点位于主手稳定握持位置。默认右、上、前分别为 `+X`、`+Y`、`-Z`，根缩放为 1；不以运行时补偿旋转或非等比缩放修正单件武器。
4. 导出显式空对象/Node3D 挂点，并保留在 GLB 中：`GripAnchor` 必需且默认与 `WeaponRoot` 同位同向；双手武器加 `SupportHandAnchor`；枪械加 `MuzzleAnchor`，需要瞄准时加 `AimAnchor`，可抛壳时加 `EjectAnchor`；近战武器加 `MeleeHitBase` 与 `MeleeHitTip`。所有朝向均按 `-Z` 为前。
5. 枪口位于真实弹道出口；瞄具锚点位于可用瞄线；近战命中两点覆盖实际攻击刃/头的扫掠范围。锚点是玩法接口，禁止只凭网格中心或对象名称推测。
6. 颜色、UV、材质、法线和贴图遵从项目契约。可复用色盘时，颜色通过色盘 UV 而不是新增颜色材质；主体与发光面保持独立，并避免无意义的材质复制后缀。
7. 动画仅包含武器自身可动件，例如枪机、扳机、弹匣、折叠托、旋转部件或近战可折叠机构。需要骨骼时只包含这些局部骨骼；不为手持姿势制作人形骨骼或手部动画。
8. 每个局部动画有稳定名称和项目要求的事件接口。常用事件为 `fire`, `reload_eject`, `reload_insert`, `reload_chamber`, `melee_damage_begin` 和 `melee_damage_end`；运行时状态和伤害权威由项目逻辑决定，不能由视觉帧单独决定。
9. 使用二进制 `.glb`。仅对导出副本应用变换、轴向转换与三角化；源 `.blend` 保留可编辑。建议目录为 `assets/art/weapons/source/`、`components/` 和 `runtime/`。

## Godot 包装与验收

1. 每件武器建立独立 PackedScene：稳定 `WeaponRoot`，其下有 `Visual`、导入的锚点、按项目需要设置的 `WorldCollision`、`HeldCollision`、交互节点与元数据。GLB 只承担视觉和局部动画，碰撞与玩法逻辑归包装场景。
2. 角色装备时，将 `GripAnchor` 精确对齐角色的 `WeaponSocket`；不要在角色脚本里为单件武器写临时旋转/位移修正。双手武器只提供 `SupportHandAnchor` 目标，副手 IK 与手部姿势由角色动画系统计算。
3. 首先验证武器可独立加载，然后在项目真实角色骨骼和待机/瞄准姿势下检查：主手不漂移、双手武器副手能到达支撑点、枪口朝向正确、瞄具可对齐、近战扫掠点完整。
4. 武器的世界碰撞、手持碰撞和伤害检测必须分离。近战伤害使用 `MeleeHitBase` 到 `MeleeHitTip` 的连续扫掠，并只在运行时打开的攻击窗口生效；不要把单帧静态碰撞盒当作命中判定。
5. 新版本 GLB → 包装场景引用 → 正式重新导入 → 角色挂接验证 → 关卡验证 → 资产台账与回滚记录。保留旧版本，除非用户明确授权删除。

完整的锚点、动画边界和验收清单见 [references/handheld-contract.md](references/handheld-contract.md)。
