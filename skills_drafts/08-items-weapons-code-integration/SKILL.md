---
name: 08-items-weapons-code-integration
description: 当道具或武器的正式 PackedScene 需要在游戏代码中被引用、需要在运行时验证、或需要把资产状态登记为正式可用时使用。处理内容ID与资产ID映射、稳定路径常量、验收场景与台账转正。不修改数值、掉落、存档或战斗规则。
agent_created: true
metadata:
  display_name_zh: 08 道具与武器功能代码引用
---

# 道具与武器功能代码引用

把 `07-items-weapons-godot-prefab-assembly` 产出的稳定 PackedScene 接进运行时，并完成验收与登记。
这一步是链路的终点：资产从「文件存在」变成「正式可用」。

## 触发

- `把道具接进代码`、`让武器在游戏里显示新模型`
- `更新 GUN_VISUAL_SCENES`、`接进 ItemModelFactory3D`
- `跑资产验收`、`把这件资产登记为正式可用`

## 第一步：找出真实消费者

引用点必须**读代码确认**，不凭印象新增第二套映射表。当前项目已知的消费者：

| 消费者 | 路径 | 职责 |
|---|---|---|
| 道具模型工厂 | `src/world3d/ItemModelFactory3D.gd` | 世界拾取、背包图标、贩卖机卡共用的道具外观 |
| 枪械表现层 | `src/combat3d/WeaponModel3D.gd` | `GUN_VISUAL_SCENES` / `MELEE_VISUAL_SCENES` 内容ID → 场景映射 |
| 近战程序原型 | `src/combat3d/MeleeWeaponVisual3D.gd` | 三把近战的原型网格，待被正式美术替换 |
| 玩家角色 | `src/player3d/Player3D.gd` | 手持/背负表现装配 |
| 训练场 | `src/training3d/TrainingRack3D.gd` | 训练架展示 |

先跑一次检索确认引用面，再动手：

```bash
rg -n "assets/art/(props|weapons|items_weapons)" --glob '*.gd' src scenes
```

## 映射契约

```text
内容ID（BlueprintRegistry / ItemRegistry 的键）
  ↔ 逻辑ID/源键（账本《资产主表》E 列）
  ↔ AssetID（账本《资产主表》A 列）
  ↔ 稳定 PackedScene 路径（不含版本号）
```

规则：

- 映射表集中在一处，用 `const` + `preload` 写成常量表，**不散落 `load("res://...")` 字符串**。
- 一个内容ID只映射一个稳定路径。多个内容ID可以复用同一资产，但复用的是稳定路径，不是复制文件。
- 同一武器实例的**手持、地面、背包图标、商店预览**必须从同一实例快照重建同一模型；
  不同 LOD 场景不能各自指向不同的外观来源。世界掉落物与背包图标共享同一内容ID。
- 尚未接入的内容ID保持占位来源，并在映射表内以注释标明「未接入」，不得指向不存在的路径。

## 稳定引用与断言

- 代码引用一律使用 `res://assets/art/items_weapons/.../<资产逻辑名>_root_top3d.tscn` 这类稳定路径。
- 替换资产时，代码**一行都不改**。若必须改代码才能替换，说明路径契约已经破了，回到 07 修正。
- **跨文件契约必须有一条会失败的断言盯着**：内容ID ↔ 稳定路径 ↔ 文件存在性，三者不一致时要显式失败，
  不能静默跳过或回退到一个旧模型。

## 验收

先跑项目既有资产验收，再补内容专项：

```bash
python scripts/check_asset_registry.py --ledger <道具|武器>
godot --headless --path "<项目目录>" res://tests/verification/verify_formal_3d_asset_import.tscn
godot --headless --path "<项目目录>" res://tests/verification/verify_formal_3d_asset_gallery_visual.tscn
godot --headless --path "<项目目录>" res://tests/verification/verify_player3d_weapon_grip_visual.tscn
```

对照 `docs/v0.1/10_资产与内容规范.md` §9 与 `assets/art/模型资产导入说明_v001.md` 的验收清单，
逐项确认：独立加载、世界摆放、拾取范围、掉落物理、手持对齐、自身动画、材质与真实关卡截图。
修改比例、轴向、色盘或材质后必须重新导出、重新导入并重跑验收。

## 台账转正

只有独立加载、正式引用、玩法通行与真实渲染都通过，才把状态改为「正式可用」。更新**所属域分账本**：

《资产主表》：`制作状态`、`版本`、`文件路径`、`SHA-256`、`源编号（Blender collection）`、
`状态/动画`、`更新时间`。

3D 分页：`Prefab路径`、`GLB模型路径`、`Blender源文件`、`功能说明`、`功能脚本路径`、
`碰撞开关`、`碰撞归属`、`碰撞方式`、`标准尺寸`、`原点与朝向`、`使用位置`、`制作状态`、`版本`。

账本路径经 `assets/registry/ledger_index.json` 解析，不写死文件名，不把资产行写入总目录。

## 输出与门禁

交付：代码引用改动、验收命令与结果、账本更新、未执行项与阻塞原因。

门禁（任一失败即停）：

- 内容ID ↔ 资产ID 映射缺环，或找不到稳定 PackedScene → 失败；
- 新增了第二套并行映射表 → 失败；
- 靠改代码才能完成资产替换 → 失败；
- 手持/地面/背包指向不同外观来源 → 失败；
- 账本状态改「正式可用」但验收未全跑 → 失败；
- 验收套件出现 exit 3 或 exit 4 → 失败；
- 视觉验收用 headless 结构结果代替 → 失败。

报告格式：

```text
已接入：<AssetID> / <内容ID>
稳定路径：<..._root_top3d.tscn>
代码引用：<文件:行>
验收：<命令> → <判据>
台账：<分账本> / <分页> 已更新
未执行：<项及原因>
```

口径细节见 [references/code_integration_contract.md](references/code_integration_contract.md)。
