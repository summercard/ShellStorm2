---
name: 01-character-contract-authoring
description: 角色类表现资产链路第 1 段。制作玩家、NPC、怪物、Boss 的表现资产前，先从项目代码、场景、测试与 Blender 源反推运行时契约，再在 Blender 建立模型/动作双母版；覆盖账本先行登记、骨架 ID 与签名、槽位与挂点、部件 Collection、动画消费方式判定。不用于导出与中转（用 02-character-export-transfer）、Godot 包装（用 03-character-godot-import）、运行时状态映射（用 04-character-state-binding）、验收（用 05-character-verification）、台账推进（用 06-character-ledger）；不用于武器、道具与场景设施。
---

# S1 · 契约反推与母版制作

```text
账本 → 【S1 契约反推 · 双母版】 → S2 导出中转 → S3 Godot 包装 → S4 状态映射 → S5 验收 → S6 台账推进
```

**入口**：账本中一条 `制作状态 = design_only` 的资产行，或一条需要重制的已登记资产。
**出口**：一对共享骨架的 Blender 母版 + 一份契约记录，`制作状态 = authored`。

**动手前必读** [references/naming-and-storage-contract.md](references/naming-and-storage-contract.md)——命名、存放路径、AssetID 与骨架 ID 格式的唯一权威。
ShellStorm2 的具体证据链与已知约定见 [references/shellstorm2-reverse-contract.md](references/shellstorm2-reverse-contract.md)。

## 边界

- **适用**：玩家外观与换装件、NPC、普通怪、精英、Boss 的视觉资产与其骨架/挂点/动作母版。
- **不适用**：枪械与近战武器（用 `game-weapon-model-pipeline`）；可拾取道具（用 `game-prop-model-pipeline`）；场景、关卡组件与固定设施（用 `blender-game-prop-standard` + `godot-model-asset-import-standard`）。
- **所有权边界**：本段只产出**表现**。角色控制器保留移动、主碰撞、HP、输入、AI、状态机、攻击判定与存档权威。母版里出现这些内容即为越界。

## 第 0 步 · 账本先行（不可跳过）

未登记的资产不得开工。顺序严格如下：

1. 读 `assets/registry/ledger_index.json`，用 `scripts/ledger_registry.py` 解析：属于哪个域、哪个大类、哪个 `art_root`、哪个责任 skill。
   ```python
   from ledger_registry import LedgerIndex
   index = LedgerIndex.load(project_root)
   index.domain_for_category("角色")        # -> characters 域
   index.domain_for_category("敌人")        # -> enemies 域
   index.path_for_category("角色")          # -> ledgers/ShellStorm2_角色账本_v001.xlsx
   ```
2. 在**该域分账本**的《资产主表》新增行，按契约 §5 填齐字段；NPC 走《角色账本》，怪物走《敌人账本》。
3. **查重**：`查重结果` 列必须为 `唯一`。为 `重复` 时禁止制作，先合并或建立变体父子关系。
4. 按契约 §2 形态 A（NPC / 怪物）展开目录，路径写回《资产主表》「文件路径」列。
   > 玩家沿用形态 B（`production/vNNN/`），**不要给 NPC 或怪物套用形态 B**。

## 第 1 步 · 反推运行时契约

每次创建或替换前，先建立该资产的**简短契约记录**，随后它随中转 JSON 一起交接给 S2：

1. **找消费者**：正式 PackedScene、控制脚本、动画/状态机、换装代码、碰撞拥有者、针对该资产的验证测试。找不到消费者资产即为孤儿，不得制作。
2. **找版本链**：目标 `.blend`、对应 GLB、包装场景、manifest、台账行。运行项目提供的 Blender 审计/验证脚本；**没有 Blender 可执行文件时只能记录「源文件未审计」**，不得拿截图或 manifest 冒充 Blender 验证。
3. **逐项确认**：根节点、单位、原点、前向、运行时缩放、真实包围盒、碰撞归属、动画形态、骨架/节点名称、槽位、挂点。
4. **两个尺寸分开记**：创作尺寸（母版里量出来的）与运行时展示尺寸（游戏里实际可见的）分别登记，不允许混为一谈。
5. **冲突处理**：`.blend`、manifest、代码、测试不一致时，**以目标运行时消费者 + 对应验收测试为基准**，记录差异。禁止用隐藏缩放或单件脚本补偿来掩盖冲突。

## 第 2 步 · Blender 双母版

1. 从已审计母版或目标源的新版本开始；**不覆盖母版、不覆盖旧版本**。
2. **模型与动作分成两个 `.blend`**：共享同一骨架 ID、同一骨名、同一父子关系、同一静止姿势、同一单位。动作文件预览关联模型几何。
3. 骨架 ID 形态 `SKEL-<族码><NN>-<NNN>`，独立编号，被两个文件共同引用。任何骨名、层级或重定向改动**必须同步修改运行时消费者与测试**。
4. 导出前重算两文件的**骨架签名**并比对；不一致先修复，不许带着差异往下走。

**各域骨架基准**

| 域 | 骨架 ID | 基准 |
|---|---|---|
| 玩家 | `SKEL-BUNNY01-004` | 现役，v021 在跑 |
| NPC | `SKEL-NPC<NN>-<NNN>` | 新建独立骨架，**不复用玩家骨架** |
| 普通怪 / 精英 | 独立编号 | 由生态套件 `ENM-ECOSYSTEM-KIT-3D` 派生 |
| Boss | 独立编号 | 三阶段共用同一主体骨架 |

## 第 3 步 · 结构与槽位

1. 模型集合采用「**部件 / 配件名称**」两级 Collection；配件名本身也是集合，容纳该样式的多个网格。
2. 用 `slot_id` / `variant_id` 登记；**颜色变体优先共用几何**，不为每个颜色复制整套结构。
3. 可换装件只在**运行时已支持的槽位**内拆分。槽位名以项目代码为准：

   `Body` · `Head` · `Hands` · `Feet` · `Hat` · `Glasses` · `LowerBody`

   **NPC 首版只需 `body` + `head`**；其余槽位名预先占用以留扩展口，但不建空壳。
4. 角色侧只维护已定义的 `WeaponSocket`、背负/背包/服装/饰品 socket。**武器握点属于武器资产**，角色侧不新增每件资产专用的补偿。
5. 展示地面、相机、灯光、玩家碰撞体、武器与道具**不进入角色 GLB**；预览环境与共享骨架各自分组，预览物不得导出。

## 第 4 步 · 动画消费方式判定

先判定消费方式，再决定动作怎么产：

- **骨骼角色**：保留已验证的 Armature、骨名、父子关系、静止姿势、权重、剪辑与根运动约定。
- **节点驱动角色**：保留功能节点与挂点层级，用固定骨名→表现节点映射消费 Blender 评估动作。确需迁移时，可**一次性**采样原表现建立可编辑骨骼基线；之后 Blender 动作文件即创作源，不再反复从程序覆盖美术关键帧。

**各域状态集（各不相同，不得互相套用）**

| 域 | 状态集 | 数量 |
|---|---|---|
| 玩家 `Player3D` | `idle / moving / dashing / hurt / locked / falling / landing / dead` + `walking / armed_*` 变体 | 8 + 4 |
| 怪物 `Enemy3D.VALID_STATES` | `dormant / idle / patrol / alert / chase / search / return / telegraph / attack / recovery / stagger / dead` | 12 |
| NPC `ThemedNPC3D` | `idle` + `talk` | 2（本期，未来可扩展） |

怪物状态 ID **逐字取自 `src/enemy3d/Enemy3D.gd`**，不得在美术侧另起名字。状态集变更属于运行时系统改动，需同时改消费者与测试。

面向动画的部件必须在**目标待机、移动、受击、攻击、装备与换装姿势**中检查穿插与枢轴。动画只驱动已确认的骨架/节点；事件与伤害判定仍归状态机。

## 出手前自检

- [ ] 《资产主表》已登记，查重结果 `唯一`，目录落位与「文件路径」列逐字一致
- [ ] 模型母版与动作母版是**两个文件**，骨架 ID 一致，签名比对通过
- [ ] 单位、原点、前向、根缩放已记录；创作尺寸与运行时尺寸分开登记
- [ ] 槽位名与项目代码一致；NPC 未偷用玩家骨架
- [ ] 状态集名称与代码逐字一致，未自造
- [ ] 母版内不含碰撞、脚本、展示物、相机与灯光
- [ ] 契约记录已写，可交接给 S2

## 交接给 S2 的东西

1. 已审计的模型 `.blend` 与动作 `.blend`（含骨架 ID 与签名）
2. 契约记录：消费者、尺寸、原点/前向、槽位、挂点、状态集、骨骼/节点契约
3. 已登记的账本行（`AssetID`、`逻辑ID/源键`、`组件槽`、`变体父ID`、`版本`、`制作状态 = authored`）
