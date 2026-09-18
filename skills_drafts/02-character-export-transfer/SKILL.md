---
name: 02-character-export-transfer
description: 角色类表现资产链路第 2 段。把 Blender 双母版导出为纯视觉 GLB，覆盖稳定路径，并生成机器可校验的严格中转台账；覆盖只导出目标 AssetID、重算骨架签名、SHA-256 登记、动作时长/循环/轨道核对、过期机制与状态推进到 exported_pending_godot_validation。不用于制模与契约反推（用 01-character-contract-authoring）、Godot 场景包装（用 03-character-godot-import）、运行时映射（用 04-character-state-binding）、验收（用 05-character-verification）、台账推进（用 06-character-ledger）。
---

# S2 · 导出与严格中转

```text
账本 → S1 契约反推 · 双母版 → 【S2 导出中转】 → S3 Godot 包装 → S4 状态映射 → S5 验收 → S6 台账推进
```

**入口**：S1 交接的两个 `.blend` + 契约记录，账本行 `制作状态 = authored`。
**出口**：`components/` 下的视觉 GLB（已覆盖稳定路径）+ 一份严格中转 JSON，`制作状态 = exported_pending_godot_validation`。

**动手前必读** [references/naming-and-storage-contract.md](../01-character-contract-authoring/references/naming-and-storage-contract.md) 的 §3.3（文件名模板）、§3.4（版本号落点）、§3.5（禁止项）。

## 边界

- **只负责**：Blender → GLB 的导出、骨架签名重算、哈希与元数据登记、中转 JSON 生成、过期标记。
- **不负责**：Godot 场景包装、碰撞、挂点节点化、状态映射、验收、台账写入。
- GLB 内**不得**出现碰撞体、脚本、玩法逻辑、展示地面、相机、灯光、预览武器。

## 第 1 步 · 定导出目标

1. 从账本行取 `AssetID`、`逻辑ID/源键`、`版本`。
2. **只导出目标 AssetID** 对应的游戏输出集合；不从零散制作组件、展示集合或整屋场景直接导出。
3. 确认输出路径按契约 §3.3：

   ```text
   components/<slug>/<slug>_visual_top3d.glb          ← 稳定路径，不带版本号（新增资产）
   ```
   部件件名追加槽位：`<slug>_<槽>_visual_top3d.glb`。
   > 存量资产（玩家 `variants/`、`bosses_v01/`、`elite_3d/` 现有件）按 D3 冻结，**保持原路径原文件名**，不要顺手去版本化。

## 第 2 步 · 重算骨架签名

1. 重新计算模型母版与动作母版两边的骨架签名，**逐项比对**：骨架 ID、骨名、父子关系、静止姿势、单位。
2. 不一致必须回到 S1 修复，**禁止带着签名差异导出**。
3. 签名结果写入中转 JSON，作为本次导出的事实记录。

## 第 3 步 · 生成严格中转 JSON

输出 `<slug>_transfer_ledger_v<NNN>.json`，**至少**包含：

| 字段组 | 内容 |
|---|---|
| 源 | 模型母版路径、动作母版路径、各自 SHA-256、骨架 ID 与签名 |
| 部件 | 部件/样式清单、`slot_id`、`variant_id` |
| 输出 | 每个 GLB 的路径与 SHA-256、字节数 |
| 动作 | 每个剪辑的名称、时长、循环标记、轨道数 |
| 消费者 | 正式 PackedScene、控制脚本、状态机、验收入口 |
| 版本 | 版本号、生成时间、生成者 |
| 回滚 | 回滚位置（git 引用） |

ShellStorm2 侧：GLB 去版本后，**`manifest` + Prefab 根节点 `metadata/asset_version` + 账本「版本」列**是唯一的三处溯源入口，缺一即视为丢失溯源，门禁应拦下。

## 第 4 步 · 资产复核

1. 校验包围盒、材质、正面、底面与节点契约。
2. 确认 **GLB 不含碰撞与脚本**。
3. 确认展示地面、相机、灯光、玩家碰撞体、武器与道具**未进入** GLB。动作文件里的预览武器即使位于链接 Collection、父级 Empty 或非当前场景，也必须在导出副本中**物理剔除**——不能只依赖 `use_selection` 或隐藏标记。
4. 用 Godot 正式导入命令刷新 GLB；运行包装场景、关卡布局与代码映射继续引用**同一稳定路径**。

## 第 5 步 · 过期机制（这一段最容易被忽略）

> **重新编辑任一源文件，原导出即视为过期。**

- 源或输出的哈希一旦变化，中转 JSON 中对应的 `validated` 结论立即作废，状态回退到 `exported_pending_godot_validation`。
- 过期资产**不得**继续被当作已验收资产引用。
- 工作区**不留 `.bak_*`**；旧版回滚一律靠 `git revert` / `git checkout`。

## 交接给 S3 的东西

1. `components/` 下的视觉 GLB（稳定路径已覆盖）
2. 严格中转 JSON（含骨架签名与全部 SHA-256）
3. 已更新的账本行：`文件路径`、`SHA-256`、`版本`、`制作状态 = exported_pending_godot_validation`

## 自检清单

- [ ] 只导出了目标 AssetID，未夹带其它部件或展示物
- [ ] `components/` 路径按契约（新增不带版本号 / 存量保持冻结命名）
- [ ] 骨架签名两文件比对通过
- [ ] 中转 JSON 字段齐全，SHA-256 与实际文件一致
- [ ] GLB 无碰撞、无脚本、无预览武器
- [ ] 源改动导致的过期已被标记，未留 `.bak_*`
