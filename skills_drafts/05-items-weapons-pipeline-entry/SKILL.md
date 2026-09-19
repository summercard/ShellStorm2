---
name: 05-items-weapons-pipeline-entry
description: 当用户说“做一件道具”“做一把枪”“道具接入 Godot”“武器资产落地”，或要求把 ShellStorm2 的道具/枪械从账本要求做到可用的运行时资产时使用。负责路由到本链路四个专职阶段 Skill、从资产账本取真实尺寸与功能并冻结资产契约；只处理美术与资产链路，不修改玩法、数值与掉落规则。
agent_created: true
metadata:
  display_name_zh: 05 道具与武器链路总入口
---

# 道具与武器链路总入口

## 路由职责

本 Skill 是道具（ITM/PRP）与武器（WPN）资产链路的入口。先判断目标处于哪一阶段，再加载对应专职 Skill，
不把多个阶段混在一次执行里。

| 用户意图 | 路由 Skill |
|---|---|
| 从账本取尺寸与功能、冻结资产契约、判断动画档位 | 本 Skill（继续执行「资产契约冻结」） |
| 在 Blender 中制作原始文件、绑骨骼与动画、集合归类命名 | `06-items-weapons-blender-authoring` |
| 导出 GLB、组装正式 PackedScene、碰撞与挂点分离 | `07-items-weapons-godot-prefab-assembly` |
| 内容ID ↔ 资产ID 映射、功能代码引用、验收与台账转正 | `08-items-weapons-code-integration` |

底层技术规范不重复定义，直接沿用：

- `blender-game-prop-standard`：Blender 制作、四材质角色、公共色盘、PaletteUV、范围锁定。
- `godot-model-asset-import-standard`：GLB 导出、坐标比例、稳定路径、PackedScene、重导入与验收。
- `game-prop-model-pipeline`：道具的拾取、手持、物理与库存包装契约。
- `game-weapon-model-pipeline`：武器的挂点、局部动画与命中扫掠契约。

出现歧义时停止并列出候选，不猜 AssetID、不猜尺寸、不替用户决定做哪一件。

## 链路

```text
资产账本条目（尺寸 / 功能 / 子类 / 状态）
  ↓ 本 Skill：解析并冻结资产契约（asset_contract.json）
Blender 原始文件（模板 → 建模 → 骨骼与动画 → 集合归类命名）
  ↓ $06-items-weapons-blender-authoring
GLB + 正式 PackedScene（稳定路径，碰撞与挂点分离）
  ↓ $07-items-weapons-godot-prefab-assembly
功能代码引用 + 验收 + 台账转正
  ↓ $08-items-weapons-code-integration
```

链路只处理美术与资产落地。武器数值、子弹行为、掉落表、命运卡、库存事务、伤害权威仍由各自功能/规则代码拥有；
本链路不得修改它们，只能按已存在的接口对接。

## 双分支

同一条链路服务两类资产，契约差异只在锚点、材质预算与动画：

| 维度 | 道具分支（`ITM` / `PRP`） | 枪械分支（`WPN`） |
|---|---|---|
| 稳定根 | `ItemRoot` | `WeaponRoot`（原点=握把） |
| 手持挂点 | `HoldAnchor`（仅可手持道具创建） | `GripSocket`（必需，与根同位同向） |
| 其他挂点 | 按需 | `MuzzleSocket`、`SupportHandSocket`、`MuzzleAttachmentSocket`、`ScopeSocket`、`MagazineSocket`、`StockSocket`、`TacticalSocket`、`MutatorSocket` |
| 近战专用 | — | `MeleeHitBase`、`MeleeHitTip`（连续扫掠两端） |
| 材质角色上限 | 4（金属 / 哑光 / 反光 / 自发光） | 3（金属 / 哑光 / 反光，不含自发光） |
| 源目录 | `assets/art/items_weapons/props/<slug>/` | `assets/art/items_weapons/weapons/<slug>/` |
| 账本 | 道具账本 | 武器账本 |

挂点名称以**项目实际契约**为准（`GripSocket` / `MuzzleSocket` / 角色侧 `WeaponSocket`），
不要创建 `GripAnchor` / `MuzzleAnchor` 这类同义的第二套命名。

## 资产契约冻结

开工前必须产出 `asset_contract.json`，把所有后续阶段要读的事实一次定死。字段与账本取数规则见
[references/pipeline_contract.md](references/pipeline_contract.md)，结构见
[assets/asset_contract_template.json](assets/asset_contract_template.json)。

冻结内容至少包含：

```text
asset_id            账本《资产主表》A 列，版本升级不变
display_name_zh     账本《资产主表》B 列
category / subclass 账本 C / D 列，决定分账本与分支
domain_ledger       由 ledger_index.json 解析，不写死文件名
logical_id          账本 E 列（内容ID / 源键），供 08 做代码映射
dimensions_m        结构化尺寸，来源见契约文档
collision_intent    碰撞开关 / 归属 / 方式（账本 3D 分页）
animation_tier      动画档位（见下）
source_collection   账本《资产主表》X 列「源编号（Blender collection）」
anchor_contract     本分支的挂点清单
material_roles      本分支允许的材质角色
source_dir / stable_glb / stable_prefab  本资产的新根路径
```

缺任一必填字段就停止，报告缺哪一项、在账本的哪个分页、当前值是什么。**不得用「先做着看」绕过**。

## 从账本取尺寸与功能

账本的规则是：

- 身份与状态读**所属域分账本的《资产主表》**（道具账本 / 武器账本），路径经
  `assets/registry/ledger_index.json` 解析，不写死文件名、不假定分页还在总目录里。
- 尺寸、功能、碰撞、Prefab 与 GLB 路径读该账本对应的 **3D 分页**（`3D-道具` / `3D-物品` / `3D-武器`）。
- 尺寸以米为单位写成 `宽×深×高m`；`原点与朝向` 列必须给出原点位置与 local 正面方向。
- 对尺寸缺失或仍写自由文本的条目，先补齐账本再开工；补齐属于登记动作，不改资产本身。

解析命令与字段口径见 [references/pipeline_contract.md](references/pipeline_contract.md)。

## 动画档位判定

按子类判定，不做无意义的骨骼：

| 档位 | 判定 | Blender 要求 |
|---|---|---|
| `tier_0_static` | 钥匙、子弹、消耗品、容器、纯装饰件，没有任何可动结构 | 不建骨架、不建动画 |
| `tier_1_articulated` | 有自身可动件：盖子、折页、按钮、机械机关、枪机、弹匣、扳机、折叠托、抛壳件 | 必须做该可动件的局部动画；简单件用对象动画，多轴或需要传递的用局部骨骼 |
| `tier_2_deform` | 需要形变、软体或与角色动作联动的部位 | 骨骼 + 蒙皮 |

判定结果写入 `animation_tier`，并在账本《资产主表》「状态/动画」列留痕。
`tier_1` 及以上若最终没有交付动画，视为未完成；`tier_0` 若强行建骨架，视为引入无意义负债。
角色的手臂姿势、手部 IK、全身动作、拾取手势**不属于**本链路，不要烘焙进资产。

## 输出与门禁

交付：

- 冻结后的 `asset_contract.json`；
- 路由结论与下一步 Skill；
- 账本取数记录（读了哪本、哪个分页、哪些列、取到什么值）。

门禁：

- 找不到 AssetID、找不到所属分账本或 3D 分页 → 失败；
- 尺寸、功能、原点朝向缺任一项 → 失败；
- 资产已存在且状态为正式可用，但用户要求的是「制作新版」→ 先确认替换意图，不直接覆盖；
- 用户要求在本链路内改玩法、数值、掉落或存档 → 拒绝并指出应由哪套规则流程负责。
