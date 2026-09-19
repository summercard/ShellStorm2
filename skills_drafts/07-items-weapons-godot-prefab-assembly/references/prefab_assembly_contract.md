# Godot Prefab 组装契约

本文件是 `07-items-weapons-godot-prefab-assembly` 的导出参数、节点树与故障口径。

## 1. 导出参数

| 项 | 值 |
|---|---|
| 交换格式 | 二进制 `.glb` |
| 图片 | `export_image_format="NONE"`（色盘外链，GLB 不内嵌） |
| 变换 | 只对导出副本烘焙；源 `.blend` 保持可编辑 |
| 三角化 | 导出副本上执行 |
| 根缩放 | 1 |
| 参与导出的集合 | `02_游戏输出_整合模型`、`10_骨骼与动画`、`80_挂点_交互接口` |
| 不导出的集合 | `01_制作组件_已统一材质`、`90_展示环境_灯光相机` |

## 2. 稳定路径

```text
assets/art/items_weapons/<props|weapons>/<slug>/
├─ source/<资产逻辑名>_source_v###.blend
├─ components/<资产逻辑名>_visual_top3d.glb
├─ rig/<资产逻辑名>_skeleton_v###.glb
└─ runtime/<资产逻辑名>_root_top3d.tscn
```

- `components/` / `runtime/` / `rig/` 目录名与文件名**不含版本号**。
- 替换 = 覆盖同路径同名文件 → 重新导入 → 引用不变 → 验证 → 台账同步。
- 禁止派生新版本文件名或目录，禁止新旧并存；回滚由版本控制承担。
- `.import` 与 `.uid` 留在原路径不重建。
- 溯源入口只有三处：`source_manifest.json`、Prefab 根节点 `metadata/asset_version`、账本版本列。

## 3. PackedScene 节点树

**道具分支**

```text
ItemRoot (Node3D, scale=1)
├─ Visual (GLB 实例)
├─ PickupTrigger (Area3D)        仅可拾取道具
├─ WorldCollision (StaticBody3D) 仅世界摆放阻挡
├─ PhysicsCollision (RigidBody3D) 仅掉落/投掷
├─ HoldAnchor (Node3D)           仅可手持道具
└─ InteractionNode               仅可交互道具
```

**枪械分支**

```text
WeaponRoot (Node3D, scale=1)
├─ Visual (GLB 实例，含导入的锚点)
├─ WorldCollision (StaticBody3D) 世界掉落的实体阻挡
├─ HeldCollision (Area3D 或形状)  手持状态碰撞
└─ InteractionNode               仅需要拾取时
```

**硬规则**

- 触发拾取的范围不能同时充当实体阻挡碰撞。
- 掉落/投掷物的物理碰撞不能替代拾取触发器。
- 武器的世界碰撞、手持碰撞与伤害检测三者分离。
- 近战伤害用 `MeleeHitBase` → `MeleeHitTip` 连续扫掠，只在运行时攻击窗口生效；单帧静态碰撞盒不算命中判定。
- 纯装饰资产不得注册玩法组、加交互碰撞或继承设施脚本。
- 根节点 `scale = 1`；需要不同尺寸或朝向时用表现节点或另建包装场景。

## 4. 元数据字段

Prefab 根节点 `metadata`：

| 键 | 值 |
|---|---|
| `asset_version` | 当前源版本，如 `v001` |
| `asset_id` | 账本 AssetID |
| `logical_id` | 内容ID / 源键 |
| `branch` | `prop` / `weapon` |
| `animation_tier` | 三档之一 |
| `collision_owner` | `Prefab自身` / `外部脚本` / `混合` / `无` |
| `stable_path` | 本场景自身的稳定路径 |

## 5. 重新导入与验证

```powershell
godot --headless --import --path "<项目目录>"
```

验证清单：

- GLB 生成 `.import` 且无导入错误；
- 每个 PackedScene 可独立加载、可实例化；
- 材质数量与分支上限一致，色盘采样正确，自发光不泛白；
- 包围盒、原点、正面方向与 `asset_contract.json` 一致；
- 挂点齐全，位置与朝向与 Blender 一致；
- 语义独立附件不在主模型中，可作为独立节点移动；
- `tier_1` / `tier_2` 的动画可播放，动作名与运行时事件对齐；
- 实际关卡引用同一稳定路径，外观替换成功，不穿地、不重叠。

## 6. 常见故障

| 现象 | 根因 | 处理 |
|---|---|---|
| 替换 GLB 后游戏里没变 | 只改了源没重新导入；或包装场景仍指向旧路径 | 重跑正式导入；核对 Prefab 引用 |
| 模型尺寸不对 | 上游尺寸错误被运行时缩放掩盖 | 回 06 改源，禁止在包装根上缩放 |
| 挂点漂移 | 挂点不在导出集合内，或导出时被烘焙 | 把挂点放 `80_挂点_交互接口`，确认参与导出 |
| 拾取与阻挡互相干扰 | 同一节点兼任两种碰撞 | 拆成 `PickupTrigger` 与 `WorldCollision` |
| 色盘串色或出现网格条纹 | 内嵌了图片、或采样非 `Closest`、或开了 MipMap | 改外链、`Closest`、关 MipMap |
| 近战打不中 | 用单帧静态碰撞盒当命中判定 | 改用 `MeleeHitBase` → `MeleeHitTip` 扫掠 |
| 动画不播放 | 动作名与运行时事件不一致，或骨架未随 GLB 导出 | 对齐事件名；确认 `rig/` 与 `10_骨骼与动画` 参与导出 |
