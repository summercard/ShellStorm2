---
name: 06-items-weapons-blender-authoring
description: 当需要在 Blender 中制作或修改 ShellStorm2 道具与枪械的原始文件时使用，包括选用模板、建模、绑骨骼与制作局部动画、按契约做集合归类与命名、色盘UV 与材质角色。覆盖道具分支与枪械分支；不用于场景模块与固定设施，不制作角色手部姿势或玩法逻辑。
agent_created: true
metadata:
  display_name_zh: 06 道具与武器 Blender 原始文件制作
---

# 道具与武器 Blender 原始文件制作

从 `05-items-weapons-pipeline-entry` 冻结的 `asset_contract.json` 出发，产出一份可升版、可导出、
可被 Godot 稳定替换的 Blender 原始文件。

## 触发

- `做一件道具的 Blender 源`、`做一把枪的 Blender 源`
- `按模板建道具原始文件`、`给这把枪绑骨骼和动画`
- `按契约整理这个 Blender 文件的集合和命名`
- `用道具模板重建这个源`、`给武器源补上挂点`

必须已有 `asset_contract.json`。没有就先回到 `05-items-weapons-pipeline-entry`；不得凭聊天内容猜尺寸。

## 第一步：从模板起手

复制对应分支的模板，不在空文件里手工搭结构：

```bash
cp assets/art/items_weapons/_templates/prp/prp_template_source_v001.blend \
   assets/art/items_weapons/props/<prop_slug>/source/<资产逻辑名>_source_v001.blend
cp assets/art/items_weapons/_templates/wpn/wpn_template_source_v001.blend \
   assets/art/items_weapons/weapons/<weapon_slug>/source/<资产逻辑名>_source_v001.blend
```

打开后第一件事：把根集合重命名为 `<前缀>_<中文资产名>_中文资产管理`，并**清空模板占位的示例件、
示例挂点与示例骨架**。示例对象只演示契约，不得留在交付文件里。

模板提供的东西：五个子集合、本分支的材质角色、外链公共色盘、PaletteUV 活动层、
本分支的全部挂点空对象、一个最小可演示骨架。模板契约与校验命令见
[assets/art/items_weapons/README.md](../../../assets/art/items_weapons/README.md)。

## 集合契约

```text
<前缀>_<中文资产名>_中文资产管理
├─ 01_制作组件_已统一材质      （默认隐藏、不参与导出）
├─ 02_游戏输出_整合模型        （默认显示、参与导出）
├─ 10_骨骼与动画               （tier_1 / tier_2 才有内容）
├─ 80_挂点_交互接口            （空对象，参与导出）
└─ 90_展示环境_灯光相机        （不参与导出，关闭渲染可见性）
```

- 制作组件保持可编辑、默认隐藏；游戏输出是导出源。
- 一个资产单位对应一份 GLB 和一份包装场景。不得把多件独立资产焊成一个网格。
- 语义独立的附件（弹匣、瞄具、配件、可单独拾取的部件）必须是独立资产，不焊进主体。
- 每个可独立导入、替换、复用或维护的部件建立独立输出根。

## 命名契约

| 对象 | 规则 | 示例 |
|---|---|---|
| 源文件 | `<资产逻辑名>_source_v###.blend`，小写 snake_case | `prp_flare_beacon_source_v001.blend` |
| 根集合 | `<前缀>_<中文资产名>_中文资产管理` | `PRP_信号信标_中文资产管理` |
| 制作组件对象 | `<中文资产名>_制作组件_<部位>` | `信号信标_制作组件_外壳` |
| 输出网格 | `<前缀>_<资产逻辑名>_<材质角色>_<部位>` | `prp_flare_beacon_主体_金属哑光反光` |
| 自发光件 | 独立网格，材质角色为柔和自发光 | `信号信标_UI灯光_柔和自发光` |
| 材质 | 固定材质角色名，禁止 `_v018` / `.001` 类迭代后缀 | `01_精工金属_道具骨架` |
| 挂点 | 项目挂点契约名，不做同义复制 | `ItemRoot` / `GripSocket` |
| 骨骼 | `<部位>` 语义名，全资产唯一 | `bolt` / `mag` / `trigger` |
| 动画动作 | 稳定语义名，与运行时事件对齐 | `reload_eject` / `lid_open` |

文件名与目录名一律不带版本号；`v###` 只出现在 `source/`。
Godot 节点名与资产显示名可以用中文，文件名必须用英文稳定 ID。

## 材质与色盘

- 道具分支最多 4 个材质角色：`01_精工金属_道具骨架`、`02_细腻哑光_道具大面`、
  `03_清漆反光_道具点缀`、`04_柔和自发光_道具UI`。
- 枪械分支最多 3 个：`01_精工金属_枪身骨架`、`02_细腻哑光_枪身大面`、`03_清漆反光_枪身点缀`。
  枪械**不新增自发光材质**；确有发光指示时用清漆反光承担视觉，不突破三材质上限。
- 颜色只由 PaletteUV 控制，颜色变化不得增加材质球。
- 色盘必须外链项目唯一公共色盘 `assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`；
  使用同一图片数据块、`Closest` 采样；导出时 `export_image_format="NONE"`，GLB 不得内嵌图片。
- 自发光网格与主体分离。

## PaletteUV 契约

- 每个输出网格有且只有 `PaletteUV` 一层，不保留 `UVMap` / `UV贴图` 旧层。
- `PaletteUV` 必须同时是**活动编辑层**和**活动渲染层**。
- 每个面的 UV 岛必须有面积，完整落在**单一色格的安全内区**，不能压成点或跨格。
- 底色盘为 10×10 纯色格，第 10 列为冷调灰阶。

## 骨骼与动画

按 `asset_contract.json` 的 `animation_tier` 执行：

**`tier_0_static`** — 不建骨架、不建动画。这一档强行加骨架属于负债，验收会判失败。

**`tier_1_articulated`** — 必须为每个真实可动件建立局部动画：

1. 可动件与固定件分离成独立对象；不要用「整件缩放/旋转」冒充机械动作。
2. 单轴简单件（盖子、折页、按钮滑块）用对象级动画；多轴或有联动关系的（枪机、抛壳、折叠托）用局部骨架。
3. 骨架只包含该资产自己的局部骨骼，**不包含人形骨骼、手臂或手部骨骼**。
4. 每段动画有稳定名称，并与运行时事件对齐。枪械常用事件：
   `fire`、`reload_eject`、`reload_insert`、`reload_chamber`；近战常用：`melee_damage_begin`、`melee_damage_end`。
5. 动画只表达表现时点。伤害、弹药、状态权威由运行时逻辑决定，不得由视觉帧单独决定。

**`tier_2_deform`** — 骨骼 + 蒙皮。只对确需形变的部位建骨骼；蒙皮权重必须可复现，
不把角色身体、手臂或动作烘焙进来。

**不属于本链路**：拾取动作、放入库存、拿起、投掷、角色手势、角色 IK、瞄准姿势、后坐力叠加、状态机。

## 坐标与原点

- 单位米，源文件根缩放恒为 1。
- 道具分支：`ItemRoot` 为稳定根。普通静态/掉落道具以接地或物理平衡点为原点；
  可手持道具另给 `HoldAnchor`，不为迁就手持破坏世界摆放原点。
- 枪械分支：`WeaponRoot` 原点位于主手稳定握持位置；默认右、上、前分别为 `+X`、`+Y`、`-Z`；
  `GripSocket` 默认与 `WeaponRoot` 同位同向。
- 枪口位于真实弹道出口，瞄具锚点位于可用瞄线，近战 `MeleeHitBase` → `MeleeHitTip` 覆盖实际攻击刃/头的扫掠范围。
  挂点是玩法接口，禁止凭网格中心或对象名推测。
- 展示地面、底台、相机、灯光、角色手和场景装饰不进入导出集合。

## 输出与门禁

交付：

- 版本化 `.blend` 源文件，落在 `assets/art/items_weapons/<props|weapons>/<slug>/source/`；
- 根集合重命名完成、模板占位对象已清除；
- 本分支材质角色齐全、色盘外链、PaletteUV 合规；
- `tier_1` / `tier_2` 的骨架与动画（含动画动作清单）；
- 正面/侧面/俯视与游戏视角预览图；
- 范围与自检结果。

门禁（任一失败即停）：

- 集合层级不合契约、模板示例对象残留 → 失败；
- 出现未登记材质、材质后缀、内嵌色盘图片、PaletteUV 非活动层或 UV 岛无面积 → 失败；
- 枪械超过 3 个材质角色、或出现自发光材质 → 失败；
- `tier_1` 及以上没有交付动画，或 `tier_0` 建了骨架 → 失败；
- 挂点缺失、命名与项目契约不一致、或创建了同义第二套挂点 → 失败；
- 根缩放不为 1、用缩放凑尺寸 → 失败；
- 把碰撞体、玩法脚本、角色动作烘进导出集合 → 失败。

详细字段口径、材质参数基线与自检清单见 [references/blender_authoring_contract.md](references/blender_authoring_contract.md)。
源清单结构见 [assets/source_manifest_template.json](assets/source_manifest_template.json)。

通过后交给 `07-items-weapons-godot-prefab-assembly`。
