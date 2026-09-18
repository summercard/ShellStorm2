---
name: 03-character-godot-import
description: 角色类表现资产链路第 3 段。把 S2 产出的纯视觉 GLB 导入 Godot，建立或更新稳定路径的 PackedScene 运行包装，登记挂点与元数据，执行 asset_guard 归类，并完成引用替换与导入期验证。不用于制模与契约反推（用 01-character-contract-authoring）、Blender 导出与中转（用 02-character-export-transfer）、状态→动作接线（用 04-character-state-binding）、专项验收（用 05-character-verification）、台账推进（用 06-character-ledger）。
---

# S3 · Godot 导入与包装

```text
账本 → S1 契约反推 · 双母版 → S2 导出中转 → 【S3 Godot 包装】 → S4 状态映射 → S5 验收 → S6 台账推进
```

**入口**：S2 交接的 GLB + 严格中转 JSON，账本行 `制作状态 = exported_pending_godot_validation`。
**出口**：`runtime/` 下的稳定 PackedScene，已被运行时消费者引用；`制作状态 = validated`。

**动手前必读** [references/naming-and-storage-contract.md](../01-character-contract-authoring/references/naming-and-storage-contract.md) 的 §2（三种形态）、§3.5（禁止项）。

## 边界

- **适用**：玩家根/组件、NPC、普通怪、精英、Boss 的表现包装。
- **不适用**：武器（`game-weapon-model-pipeline`）、道具（`game-prop-model-pipeline`）、场景与设施（`godot-model-asset-import-standard`）。
- **包装层职责**：持有挂点、必要子 Prefab、元数据。**不持有**移动、主碰撞、HP、输入、AI、状态机、攻击判定。

## 第 1 步 · 导入 GLB

1. 将 GLB 放入 `components/<slug>/<slug>_visual_top3d.glb`（稳定路径）。
   > 存量资产按 D3 保持原路径；`elite_3d/rift_boar_armed/` 是**怪物侧唯一样板**，新怪照抄。
2. 用 Godot 正式导入命令刷新；`.import` 与 `.uid` **留在原位**。
3. GLB 只负责视觉网格、UV、材质与必要动画——导入后若发现夹带碰撞或脚本，退回 S2。

## 第 2 步 · 建立运行包装

```text
runtime/<slug>/<slug>_root_top3d.tscn
```

1. **根缩放恒为 `1,1,1`**。视觉尺寸有变化回到源文件处理，或在已批准的包装层契约内处理，不得靠隐藏缩放补偿。
2. Prefab 通过 Godot 场景实例组合 GLB、挂点、必要子 Prefab；**不建立自定义 Prefab 格式**，不把内容重新烘焙成一个不可维护的大模型。
3. 在根节点写入元数据：
   ```
   metadata/asset_version = <版本号>
   ```
   这是 GLB 去版本后三处溯源入口之一（另两处：中转 JSON、账本「版本」列）。
4. 挂点用 `Marker3D` 表达；角色侧只维护已定义的 `WeaponSocket`、背负/背包/服装/饰品 socket。
5. 碰撞**默认不放进 Prefab**：由角色控制器拥有时，「碰撞归属」列填 `外部脚本`，并在备注写明所有者。

**各域包装基准**

| 域 | 根节点 | 碰撞归属 | 备注 |
|---|---|---|---|
| 玩家 | `CapsuleAvatar3D (Node3D)` | 无（`Player3D` 拥有） | 玩法根是 `scenes/Player3D.tscn` |
| NPC | `Node3D` / 适配层 | 无（NPC 控制器拥有） | 首版无碰撞需求 |
| 普通怪 / 精英 | 表现根，子节点挂到 `Enemy3D` | `Enemy3D` 拥有 | 复用 `melee_chaser` 的 `CylinderShape3D` 等既有形状 |
| Boss | 表现根 | Boss 控制器拥有 | 三阶段共用同一主体 |

## 第 3 步 · asset_guard 归类（正式导入前必跑）

```bash
python3 scripts/asset_guard.py <版本包目录> --classify <reuse|replacement|version_increment|child_variant>
```

- 同 AssetID 或同哈希**不是自动错误**，但必须明确归类并保留报告。
- **未分类的重复阻断接入。**
- 归类结果写进中转 JSON 与账本备注。

## 第 4 步 · 引用替换

- Godot 运行资产的路径是**稳定契约**：替换只有「**覆盖同路径同名文件**」一种方式。
- 不派生新文件、不新建版本目录、不并存旧版；`.import` 与 `.uid` 留原位。
- `src/**/*.gd` **不得**出现 `_v0NN` 形式的资产路径（`preload()` 指向不存在的路径是**编译期错误**，整个脚本会不可用，不是只丢那一个资产）。
- 台账路径列同样不含版本号（存量例外，按实际路径登记）。

## 第 5 步 · 导入期验证

逐项确认后再交给 S4：

- [ ] 独立加载通过（场景可单独实例化，无解析错误）
- [ ] 节点/骨架契约与 S1 契约记录一致
- [ ] 根缩放 = 1；方向契约一致（Blender `-Y` / Godot `-Z`）
- [ ] 包围盒与账本「标准尺寸」列一致
- [ ] 碰撞**未**被引入表现层；「碰撞归属」列与实际情况相符
- [ ] 挂点位置与数量与契约一致
- [ ] 材质与贴图正确，无丢材质
- [ ] `metadata/asset_version` 已写入，且与账本「版本」列一致
- [ ] 功能场景除 Avatar/Prefab 引用外**没有结构性变化**

## 交接给 S4 的东西

1. `runtime/` 下的稳定 PackedScene（含挂点与元数据）
2. 被更新的消费者引用清单（哪个脚本/场景改了引用）
3. 账本行：`文件路径`（Prefab 与 GLB 两列）、`功能脚本路径`、`碰撞归属`、`标准尺寸`、`原点与朝向`、`制作状态 = validated`
