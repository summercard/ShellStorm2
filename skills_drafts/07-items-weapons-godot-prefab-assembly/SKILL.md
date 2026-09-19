---
name: 07-items-weapons-godot-prefab-assembly
description: 当需要把已通过美术验收的道具或枪械 Blender 输出导出 GLB 并在 Godot 中组装为正式 PackedScene 时使用，处理稳定路径、碰撞与挂点分离、重导入与独立加载验证。覆盖道具分支与枪械分支；不重新设计造型，不修改玩法代码。
agent_created: true
metadata:
  display_name_zh: 07 道具与武器 Godot Prefab 组装
---

# 道具与武器 Godot Prefab 组装

把 `06-items-weapons-blender-authoring` 产出的 Blender 输出转成可独立加载、可替换、可登记的
Godot 运行时资产。坐标、比例、材质、路径与验收细节沿用 `godot-model-asset-import-standard`，
本 Skill 只规定道具与武器特有的部分。

## 触发

- `把道具导出到 Godot`、`组装武器的 PackedScene`
- `重新导入这把枪的 GLB`
- `给道具建正式 Prefab`、`替换道具的视觉模型`

输入：已验收的 `.blend` 源 + `asset_contract.json` + `source_manifest.json`。

## 第一步：确认导出输入

导出前逐项确认，不确认就停止：

1. 根集合重命名完成，`01_制作组件` 与 `90_展示环境` 不参与导出；
2. 材质角色数量符合分支上限，色盘为外链，`export_image_format="NONE"`；
3. 挂点空对象齐全且名称与项目契约一致；
4. `animation_tier` 与已交付动画一致；
5. 根缩放为 1，原点与朝向符合 `asset_contract.json`。

只对**导出副本**应用轴向转换、变换烘焙与三角化；源 `.blend` 保持可编辑。

## 稳定路径契约

```text
assets/art/items_weapons/<props|weapons>/<slug>/
├─ source/<资产逻辑名>_source_v###.blend      ← 版本只在这里
├─ components/<资产逻辑名>_visual_top3d.glb   ← 稳定路径
├─ rig/<资产逻辑名>_skeleton_v###.glb          ← 仅 tier_1 / tier_2
└─ runtime/<资产逻辑名>_root_top3d.tscn        ← 稳定路径
```

- `components/`、`runtime/`、`rig/` 的目录名与文件名**不含版本号**。
- 替换 = 覆盖同路径同名文件 → 重新导入 → 包装场景与代码引用保持不变 → 关卡验证 → 台账同步。
- 禁止为新版本派生文件名或目录，禁止并存旧版；回滚由版本控制系统承担。
- `.import` 与 `.uid` 留在原路径不重建。GLB 不带版本号后，溯源入口只有三处：
  `source_manifest.json`、Prefab 根节点 `metadata/asset_version`、账本版本列。

## PackedScene 组装

每个资产单位一份独立 PackedScene，职责划分：

| 内容 | 归属 |
|---|---|
| 视觉网格、贴图、材质、资产自身局部动画 | GLB |
| 稳定根节点、`Visual` 节点、挂点、包围盒元数据 | PackedScene |
| 拾取触发器、物理刚体、库存脚本、交互脚本、标签 | PackedScene（按实际用途） |

**道具分支**

1. 稳定根为 `ItemRoot`，视觉置于 `Visual`。
2. 按实际用途增加分离的节点：`PickupTrigger`、`WorldCollision`、`PhysicsCollision`、`HoldAnchor`、交互节点。
3. 触发拾取的范围**不能**同时充当实体阻挡碰撞；掉落/投掷物的物理碰撞**不能**替代拾取触发器。
4. 可手持道具在真实角色 `ItemSocket` 或项目指定挂点下验证 `HoldAnchor`；
   不为单件道具在角色脚本里写补偿变换。
5. 没有手持需求的道具不得被强加武器握点契约。

**枪械分支**

1. 稳定根为 `WeaponRoot`，视觉置于 `Visual`，GLB 导出的锚点保持原位。
2. 装备时将 `GripSocket` 精确对齐角色 `WeaponSocket`；不为单件武器写临时旋转/位移修正。
3. 世界碰撞、手持碰撞与伤害检测**必须分离**。
4. 近战伤害使用 `MeleeHitBase` → `MeleeHitTip` 的连续扫掠，只在运行时打开的攻击窗口生效；
   不得把单帧静态碰撞盒当命中判定。
5. 双手武器只提供 `SupportHandSocket` 目标；副手 IK 与手部姿势由角色动画系统计算。

**共同约束**

- 根节点保持 `scale = 1`。需要不同大小或朝向时用表现节点或另建包装场景，不在共享根上临时缩放。
- 纯装饰资产不得意外注册玩法组、添加交互碰撞或继承设施脚本。
- Prefab 根节点写入 `metadata/asset_version`，与源版本一致。

## 重新导入与验证

使用编辑器正式导入命令：

```powershell
godot --headless --import --path "<项目目录>"
```

至少验证：

- GLB 生成 `.import` 且无导入错误；每个 PackedScene 可独立加载和实例化；
- 材质数量、色盘采样、自发光与透明度正确；
- 包围盒、原点、正面方向符合 `asset_contract.json`；
- 挂点齐全，位置与朝向与 Blender 中一致；
- 语义独立附件确实不在主模型中，可作为独立节点移动；
- `tier_1` / `tier_2` 的动画可播放，动作名与运行时事件对齐；
- 实际关卡引用同一稳定路径且外观替换成功。

## 输出与门禁

交付：GLB、`rig/` 骨架（如适用）、PackedScene、导出清单、独立加载结果、账本更新、验收图。

门禁（任一失败即停）：

- 稳定路径带版本号，或为新版本派生新文件 → 失败；
- 碰撞与拾取/命中判定混用同一节点 → 失败；
- 根缩放不为 1，或靠运行时补偿修正锚点 → 失败；
- GLB 内嵌图片或材质数与分支上限不符 → 失败；
- 只改了 GLB 却遗漏包装场景、代码映射或测试路径 → 失败；
- 用 headless 结构结果代替视觉验收 → 失败。

字段口径与常见故障见 [references/prefab_assembly_contract.md](references/prefab_assembly_contract.md)；
运行时清单结构见 [assets/runtime_manifest_template.json](assets/runtime_manifest_template.json)。

通过后交给 `08-items-weapons-code-integration`。
