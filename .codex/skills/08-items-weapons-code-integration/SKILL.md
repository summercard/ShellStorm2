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

## 新增一个武器内容 ID（复用既有美术）

新增枪型不总是「做一把新模型」。当新枪复用既有 GLB 时，链路退化成纯代码接线，
但接线点分散在 5 个文件、11 处表格里，**漏一处不会报错，只会静默降级**
（丢视觉、丢姿势、丢配件槽、改名不生效）。按下面的清单逐条过，顺序即依赖顺序。

先定死四个名字，全链路只认它们：

```text
内容ID      weapon_<slug>
装配ID      bp_<slug>
装配节点名  GunBody_<Slug>   ← ASSEMBLY_NODE_ITEM_IDS 的键，也是往返身份的唯一凭据
显示名      <中文名>
```

| # | 位置 | 改什么 |
|---|---|---|
| 1 | `ItemRegistry._register_weapon_drops()` | 武器物品：`id` / `assembly_id` / `name` / `price` / 掉落权重 /（可选）`fate_slot_capacity` |
| 2 | `ItemRegistry._register_gunbody_tier0/1()` | 对应蓝图碎片物品，`id` 用 `bp_<slug>` |
| 3 | `BlueprintRegistry._build_registry()` | `_register_gunbody({item_id, tier, factory, tags, display_name})` |
| 4 | `BlueprintRegistry` 工厂方法 | `_create_gunbody_<slug>()`：`AssemblyNode.new(..., "GunBody_<Slug>")` + `set_base_stats()` |
| 5 | `BlueprintRegistry.ROOT_ATTACHMENT_SUPPORT` | 该节点名开放的配件槽子集 |
| 6 | `BlueprintRegistry.ASSEMBLY_NODE_ITEM_IDS` | `"GunBody_<Slug>": "weapon_<slug>"` ← 漏这条则装配树往返丢身份 |
| 7 | `WeaponModel3D.GUN_VISUAL_SCENES` | `bp_<slug>` → 稳定场景路径。**漏这条会静默退回程序化方块枪** |
| 8 | `WeaponModel3D.GUN_PROFILES` | 长度/枪管/宽/高/颜色。它喂 `get_visual_bounds_hint()`（掉落物与图标的包围盒） |
| 9 | `WeaponModel3D.GUN_NAME_TO_ID` | `"GunBody_<Slug>": "bp_<slug>"` |
| 10 | `PlayerAvatar3D.WEAPON_ANIMATION_PROFILES` | `fire_style` + kick/pitch/roll/lift。漏这条会落回步枪姿势 |
| 11 | `InventoryUI` 的节点名→装配ID表 | 装备判定用；漏了会导致背包高亮不到当前武器 |

**复用同一份美术时不要复制 GLB**：两个内容 ID 可以指向同一个稳定 PackedScene，
但要在测试里显式声明「这个内容 ID 期望解析到哪个 logic_id」，不要把
「内容 ID 与 logic_id 同名」当成契约 —— 那只是当前 1:1 的巧合。

同时必须更新的既有断言（它们硬编码了枪表，新增枪会让它们静默过期）：

- `tests/verification/verify_weapon_instance_contract_matrix.gd`（枪表 + 打印计数）
- `tests/verification/verify_player3d_weapon_pose_collision_flow.gd`（fire_style 表）
- `tests/verification/verify_formal_3d_asset_import.gd`（内容ID → 正式资产 logic_id）
- 任何断言「初始武器是哪把」的探针

## 换掉出厂（白送）枪

新档出生与死亡返城白送的枪**只有一个真源**：

```text
BlueprintRegistry.DEFAULT_STARTING_GUN_ID
  → BlueprintRegistry.get_starting_weapon_tree()
  → Player3D._ensure_weapon_tree()（start_with_weapon = true 时）
```

- 只改这个常量。**不要去改 `Player3D.default_gun_id`** —— 该 export 目前没有被任何代码或
  `.tscn` 读取，改它不会换枪，只会制造第二个假真源。
- 出厂枪的 `tier` 必须能通过 `get_available_gunbodies(0)` 的筛选，否则静默回退到列表首位。
- 命运卡槽容量走物品定义的 `fate_slot_capacity`（默认 8）。白送枪想限制成长就在这里降；
  链路是 `ItemRegistry` → `WeaponInstance.from_item()` → `to_item_dictionary()`，
  **必须验证存档往返不丢这个字段**。
- 出厂枪只给枪不给弹；配套备弹来自 `Dungeon3D.GUARANTEED_LOADOUT_AMMO_ROUNDS`。
  改弹匣容量不用动这个常量，但要确认「满匣 + 备弹」的开局口径仍然成立。
- 留意伤害口径：`WeaponModel3D` 显示的是 `枪身 damage + 子弹模块 bullet_damage` 的合计值，
  不是 `base_stats.damage`。设计给一个数、实机看到另一个数时先查这里。

### 换出厂枪会连带打破的验收项（实测清单，必须同批改）

出厂枪不是"只影响一把枪"——有一批验收项把「默认枪 = 手枪」和「默认 8 个命运槽」当成前提写死了。
改完常量后**先 grep 这两类字面量**，别等跑红才回头找：

```bash
grep -rn "Default pistol\|old pistol\|Old pistol\|weapon_pistol\|does not expose 8 fate slots" tests/verification/
```

| 验收项 | 它写死的前提 | 正确改法 |
|---|---|---|
| `verify_player3d_weapon_pose_collision_flow` | 开头直接量「默认枪」的 `sidearm_hold`；结尾用「不同风格种类数 == 配置表条数」判覆盖 | ① 该段前 **显式 `equip_weapon("bp_pistol", …)`**（验的是手枪姿势路径，不是默认枪）；② 计数改为比对**去重后的风格种类数** |
| `verify_player3d_animation_flow` | 默认枪应为 `sidearm_hold` | 断言前显式装备 `bp_pistol` |
| `verify_3d_inventory_weapon_flow` | 换枪后回背包的是 `weapon_pistol` | 改为按 `DEFAULT_STARTING_GUN_ID` 走「装配ID → 节点名 → 内容ID」**动态解析**；⚠️ 该文件里另一处把枪重置成手枪是**故意的**（它要验"换枪不丢已装模块"，而手枪才有 `mutator`/特性槽），那处别动 |
| `verify_weapon_instance_fate_ownership_flow` | 出厂枪 `fate_slot_capacity == 8`，并把 8 写进 8 处断言与 UI 文案 | 改为**从实际出厂枪读容量**再全程复用；容量本身交给 `verify_starting_weapon_contract` 盯 |
| `probe_death_return_loadout` | 写死 `"bp_pistol"` | 改用 `DEFAULT_STARTING_GUN_ID` |

两条通用教训：

- **测试里的"默认值"是最脆的耦合**。凡是「默认枪/默认容量/默认外观」被写进断言，换一次默认值就红一次，
  而且红的位置和真正改的地方隔得很远。能改成"显式装备 + 动态读值"就不要留隐式依赖。
- **共用数值不等于共用条数**。两把枪刻意共用同一开火风格/同一贴图时，任何 `size() == 表条数`
  的判据都会多算，要改成比对**集合**（去重后的种类）。

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
godot --headless --path "<项目目录>" res://tests/verification/verify_weapon_instance_contract_matrix.tscn
godot --headless --path "<项目目录>" res://tests/verification/verify_starting_weapon_contract.tscn
```

新增或改动任何枪械后，都要把对应门禁登记进 `scripts/run_verification_suite.sh` 的
`core_scenes`，否则它只在你手动跑的那一次生效。

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
- 新增/删除枪型后没有同步硬编码枪表的断言，或没有把新门禁登记进套件 → 失败；
- 出厂枪靠 `Player3D.default_gun_id` 换 → 失败（那是死出口，真源是 `DEFAULT_STARTING_GUN_ID`）；
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
