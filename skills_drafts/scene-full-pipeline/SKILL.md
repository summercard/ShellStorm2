---
name: scene-full-pipeline
description: 场景全流程制作编排：从效果图到读取白模，到 Blender 正式美术资产制作，再到资产导入 Godot 并登记正式可用。负责全程定位信息贯穿、阶段门禁、目录与命名约束、各阶段 skill 路由与交接验收；不替代各阶段专用 skill，不制作枪械、近战武器或可拾取道具。
---

# 场景全流程制作编排

把「效果图 → 白模 → Blender 正式资产 → Godot 导入」四段串成一条有门禁的流水线。本 skill 只做**编排、路由、门禁与交接**；每一段的实际制作与验收，落到对应的阶段专用 skill 或项目文档上。

## 适用边界

- **适用**：塔楼区块（`rooftop` 天台 / `base` 基地 / `battle` 战斗区 / `stairs` 楼梯区）内的场景、关卡组件与固定设施。
- **不适用**：枪械与近战武器 → `game-weapon-model-pipeline`；可拾取/可手持/可投掷道具 → `game-prop-model-pipeline`；玩家角色与换装 → `player-avatar-asset-standard`。
- 本 skill 不自己画效果图、不自己捏模型、不自己导出 GLB；它保证这些步骤**按序发生、有定位、有门禁、有验收**。

## 四个阶段总览

```text
阶段0 效果图 / 场景需求            （无专用 skill，以概念稿与主设计为准）
  ↓ 门禁：范围与定位冻结
阶段1 读取白模                     （无专用 skill，读取 tools/3Dgame-design v3 JSON 与白盒 Blender）
  ↓ 门禁：空间可拼、可走、可战斗
阶段2 Blender 正式美术资产         （$blender-game-prop-standard）
  ↓ 门禁：美术验收通过
阶段3 资产导入 Godot               （$godot-model-asset-import-standard）
  ↓ 门禁：独立加载 + 正式场景 + 登记
登记正式可用，保留上一版本回滚
```

每一阶段的产物，是下一阶段的输入。**未过门禁，不得进入下一阶段。**

## 全程固定挂钩（四个阶段都必须携带）

以下定位信息从阶段 0 建立，贯穿到阶段 3 的台账登记，任何阶段丢失即判定失败：

- `block_id`：`rooftop / base / battle / stairs`，定义见 `docs/v0.1/05.1_关卡区块设计.md#3-四区块分布`。
- `floor_range` 与 `design_scope`：具体到楼层、房间、楼梯、设施或模块范围。
- `scene_design_docs`：至少包含 `docs/v0.1/05_技术施工_关卡生成与爬楼.md` 与 `docs/v0.1/05.1_关卡区块设计.md`；基地设施另挂 `docs/v0.1/07_技术施工_基地设施.md`。
- `asset_ledger`：`assets/registry/ledgers/ShellStorm2_场景账本_v001.xlsx` 的 `3D-场景通用` 表及对应 AssetID 条目。账本路径由 `assets/registry/ledger_index.json` 单一声明 —— **不要写死账本文件名**；总目录 `assets/registry/ShellStorm2_美术资产台账_v001.xlsx` 只放索引，不含资产行。旧批次里 `…美术资产台账_v001.xlsx#3D-场景通用` 形式的引用由 `index.resolve_ref()` 解析到场景账本，无需改写。

这些信息不是只写在概念稿里：白盒 JSON 写入字段；风格稿标注范围；Blend 资产包、GLB、PackedScene、导出清单与验收记录均保留 `block_id / AssetID / 场景设计文档 / 台账定位`。**缺少任一定位信息，资产不得进入下一阶段。**

## 目录与命名契约（全流程统一）

本契约在阶段 1 起约束文件落位，阶段 3 结束时全部满足：

```text
source/art/whitebox/<scene_id>/v###/          ← 白模（JSON + Blender + 顶视图渲染）
assets/art/<大类>/<资产套件>/
├─ source/<资产逻辑名>/<资产逻辑名>_source_v###.blend      ← Blender 母版（可维护，版本历史只在这里）
├─ components/<资产逻辑名>/<资产逻辑名>_visual_top3d.glb    ← 视觉 GLB（只视觉，稳定路径）
└─ runtime/<资产逻辑名>/<资产逻辑名>_root_top3d.tscn        ← PackedScene（持元数据/碰撞/挂点，稳定路径）
```

- 白模与正式美术源分目录：白模一律 `source/art/whitebox/`，正式 Blender 母版一律 `assets/art/<大类>/.../source/`。二者不得混放。
- 前缀：环境 `env_`、道具与设施 `prp_`、角色 `chr_`、敌人 `enm_`、武器 `wpn_`。
- `source/` 文件名小写 `snake_case` 且以 `_vNNN` 结尾；`components/` 与 `runtime/` 文件名同样小写 `snake_case` 但**不带版本号**。AssetID 用稳定大写连字符格式，版本变化不改变 AssetID。
- `components/`、`runtime/` 的路径是稳定契约：替换一律覆盖同路径同名文件，不派生新文件、不新建版本目录；Godot 侧引用始终不变。
- `source/**/*.blend` 由 `.gdignore` 排除，不参与 Godot 导入与打包。

**例外——基地设施布局**（`source/art/blender/base_facility_layout/`）是「单源多次导出」型，不走上面三件套：
- 源：`source/v<NNN>/<名>_v<NNN>.blend`（**下划线**连版本号）。
- 导出：`export/v<NNN>/<名>-v<NNN>-<类型>.blend`（**连字符**，版本号必须等于源版本号；类型白名单 `structural / wall_contents / remaining_facilities`）。
- 源升级建新 `v<NNN>` 目录，旧导出随源替代废弃；仅重做导出则覆盖同名文件、不升版本号、不建新目录。

## 阶段细则

### 阶段 0 · 效果图 / 场景需求

- **规范：** 明确本次属于哪个区块，范围写到具体楼层/房间/楼梯/设施，不能只写「做塔楼场景」。区块名称与边界以 `05.1_关卡区块设计.md` 为准。
- **数据：** `scene_id`、中文名、`block_id`、目标楼层、设计范围、涉及房间/楼梯/设施 ID、用途、目标平台、风格关键词、参考图路径、禁止项、场景设计文档与台账定位。
- **交付：** 冻结后的范围说明 + 参考效果图 + 全程固定挂钩（首建）。
- **Skill：** 无专用 skill；以用户概念稿与场景主设计为准。需要生成/修改风格稿图片时用 `$imagegen`。
- **门禁：** `block_id / floor_range / design_scope / scene_design_docs / asset_ledger` 五项齐备，才可进入阶段 1。

### 阶段 1 · 读取白模

- **规范：** 只从当前游戏设计与工程契约提取尺寸，不从旧模型或效果图猜数值。每项数据记录来源文档、章节与读取日期。
- **数据：** 平面网格、场景长宽高、层高、墙高/墙厚、地板厚度、门洞、楼梯起终点、平台高度、玩家/镜头净空、碰撞、导航、拼接插槽、坐标轴与单位。
- **白模 JSON 格式：** 遵循 `tools/3Dgame-design` v3 —— `coordinateSystem=blender-z-up`，距离米、旋转角度；布局在 `groups[]/components[]`，墙/地板用 `surfaceSettings`，楼梯用 `stairSettings`；`projectMetadata` 承载 AssetID、区块、楼层范围、设计文档与输出路径，不得另建不兼容顶层格式。
- **目录：** `source/art/whitebox/<scene_id>/v###/` 固定分 `data/`（可编辑 JSON）、`blender/`（同版本白盒 Blend）、`renders/`（顶视图、无文字图、立面、剖面）。
- **交付：** `whitebox_<scene_id>_v###.json` + 白盒 Blend + 至少一张带标注顶视图、一张同机位无文字顶视图。
- **Blender 入口：** 新场景优先 `tools/blender_addons/shellstorm_level_builder/` 在 Blender 原生视口完成组件添加、吸附摆放、参数冻结、Collection 归类与资产包清单同步。`.blend` 是人工编辑事实所有者；网页工具只做旧白盒数据迁移与兼容读取。
- **Skill：** 无专用 skill；由对应场景的白盒验证入口检查。
- **门禁：** 网格拼接、门洞、楼梯、路线、碰撞、导航、镜头净空均验证通过，才可进入阶段 2。

### 阶段 2 · Blender 正式美术资产

- **规范：** 按白盒 JSON 的尺寸、名字与组合关系制作；每个可独立导入/替换的模块或设施建立独立资产包，不把整片场景焊成一个模型。
- **数据：** AssetID、白盒 JSON 路径与版本、资产包名、尺寸、原点、方向、包围盒、材质角色、公共色盘、输出集合、Blend 版本。
- **Skill：** **`$blender-game-prop-standard`**（Blender 游戏资产制作规范）。所有制作、范围锁定、材质四角色、PaletteUV 色盘、独立资产包、任务级验收都交给它；本 skill 只负责在阶段门禁处接住它的交付并放行。
- **交付：** 可维护 `.blend`、游戏输出集合、独立资产包清单、顶视/近景/完整预览图、Blender 验收结果（含 `scripts/validate_game_prop.py` 通过）。
- **门禁：** 美术验收通过，且每个输出根都有稳定 AssetID、局部原点、尺寸、方向与版本，才可进入阶段 3。

### 阶段 3 · 资产导入 Godot

- **规范：** 从已通过美术验收的游戏输出制作优化派生文件；导出版本化 GLB，建立独立 PackedScene，配置碰撞、材质、交互、标签与正式引用。不得靠 Godot 临时缩放修复上游尺寸错误。
- **数据：** 源 Blend、优化派生 Blend、GLB、PackedScene、版本、尺寸、方向、材质数、碰撞方式、使用场景、正式引用、上一版本回滚路径。
- **Skill：** **`$godot-model-asset-import-standard`**（Godot 模型资产导入规范）。GLB 导出、坐标比例、版本目录、PackedScene、碰撞、引用替换、台账与验收全部交给它。
- **交付：** 优化 Blend、GLB、`.import`、PackedScene、导出清单、资产台账更新、独立加载结果、正式场景截图。
- **门禁：** 独立加载、正式场景、玩法通行、性能与真实渲染验收全部完成，才可登记正式可用。

## 登记正式可用

- 只有阶段 3 全部验收完成，才登记为正式可用；旧版本保留用于回滚。
- 登记字段：AssetID、正式版本、源文件、运行路径、SHA-256、验收命令、退出码、错误、未执行项、回滚版本。
- **Skill：** 沿用 `$godot-model-asset-import-standard`，并执行项目对应的资产与场景专项测试。

## 回退规则

任何一步发现尺寸或组合错误，都退回阶段 1 白盒，在 `tools/blender_addons/shellstorm_level_builder/` 更新组件与布局。历史网页白盒可通过 `tools/3Dgame-design` 读取迁移，但新编辑以 `.blend` 为事实所有者。插件同步的 manifest/catalog/tree 只用于资产包目录镜像，不等于完成 GLB 导出、Godot 接入或阶段 2 美术验收。

## 阶段交接检查清单（快速核对）

| 阶段 | 关键交付 | 门禁（满足才放行） |
|---|---|---|
| 0 效果图 | 范围说明 + 参考图 + 固定挂钩 | 五项定位信息齐备 |
| 1 白模 | `whitebox_<scene_id>_v###.json` + 顶视图 | 可拼、可走、可战斗 |
| 2 Blender | 独立资产包 + 游戏输出 + 验收 | `$blender-game-prop-standard` 美术验收通过 |
| 3 Godot | GLB + PackedScene + 台账 + 截图 | `$godot-model-asset-import-standard` 全项验收通过 |

## 参考文档

- 全流程固定挂钩、阶段规范与白盒 JSON 示例：`docs/v0.1/10.1_3D场景美术生产流程.md`。
- 目录与命名、Prefab 分类账本、环境模块边界：`assets/art/3D模型资产目录与命名规范.md`。
- 资产与内容规范（状态、色盘基线、坐标契约）：`docs/v0.1/10_资产与内容规范.md`。
- 白盒 JSON 数据源与迁移：`tools/3Dgame-design/README.md`。
