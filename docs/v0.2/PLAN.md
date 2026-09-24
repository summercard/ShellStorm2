# 0.2 版本计划 · 变更登记册

状态：**只记录，不定稿**。本册是主人提出修改时的登记入口 —— 不是设计主源、不是排期承诺、不是验收结论。

建立日期：2026-09-24。登记口径修订：r2。

工程版本：`project.godot` 仍为 `0.1.0`。**本册不提升工程版本号**，只登记目标落在 0.2 的修改意向；版本发布另按[文档驱动开发规范](../DOCUMENTATION_STANDARD.md) §4 执行。

归属基准：[v0.1 模块索引](../v0.1/MODULE_INDEX.md) 的 **19 个模块 ID** 与 **37 个 FeatureID**。本册不自建第二套编号，也不另立实现状态源。

---

## 0. 不可修改规则（本册的物理约束）

1. 已写入的**条目正文永久冻结**：不改写、不删除、不重排、不合并、不"顺手优化措辞"。
2. 只允许三种追加动作：
   - 在所属**模块槽**内追加新的条目块；
   - 在既有条目块**末尾**追加「追记」行（带日期，不得改动原句）；
   - 在 §3 追加式索引表**末尾**追加一行。
3. 需要推翻旧记录时：**新记一条**，并在新条目的「追记」里写「本条取代 `<旧ID>`」。旧条目一个字都不动。
4. 本册不承载设计细节。条目里出现的判断只作为**意图留档**；正式规则仍写进对应 Owner 的设计文档。

> 说明：本册的"不修改"针对**条目**。§1/§2/§5 是口径区，口径本身需要变更时，按 r2、r3 递增修订号，并在下面追加一条「口径修订记录」。

**口径修订记录**

| 修订 | 日期 | 改了什么 |
|---|---|---|
| r1 | 2026-09-24 | 建立本册：模块归属登记原则、条目格式、19 模块槽位、状态词表 |
| r2 | 2026-09-24 | 补齐两条原先隐含的规则：① 受影响的从属槽只写「对接条」（同 ID + 本模块要配合什么），不复制完整条目块；② §3 索引表**一行 = 一个条目**，不按槽位行数计。首次登记（`0.2-PLAYER-001`、`0.2-PRESENTATION-001`）时发现原口径没写清这两点 |

---

## 1. 记录原则

### R1 归属优先 —— 本册的核心

任何一条修改，**先回答"它归哪个模块"，再写字**。找不到归属的事项不登记为条目，先去 [MODULE_INDEX](../v0.1/MODULE_INDEX.md) 补归属。

- **主责模块（Owner）只能有一个**：谁拥有这项修改的最终写入权/规则定义权，就归谁。
- **受影响模块可以有多个**：它们是"要配合什么"的接收方，不是所有者。

### R2 一事多模块 = 同一 ID 多处登记

跨模块修改**不是一条流水账**，而是在**每一个受影响模块的槽位内各写一条同 ID 的记录**，互相链回同一 ID。

写法分两档（见 r2）：

- **主责槽 = 完整条目块**：§2 的 9 个字段全填。
- **受影响的从属槽 = 对接条**：只写 `条目ID · 标题` + 一行「本模块要配合：…」+ 主责槽指向。**不复制完整条目块**，避免同一条内容在 6 个槽里各长一份、日后改一处漏五处。

这样每个模块在自己的分区里就能看到"我这块要配合什么"，不需要翻别人的清单。**这是本册与普通 TODO 列表的全部区别** —— 按模块归属记录，而不是列单条。

### R3 原话留档

「原始诉求」一栏写**主人原话**（引用块），不转述、不润色、不合并同类项。需要解释时另起一行「登记人注」。

### R4 登记 ≠ 生效

登记不等于批准、不等于已排期、不等于已裁决。条目状态只反映**记录动作**本身，不反映工程信心，也不替代 `MODULE_INDEX` / `FEATURE_RELATIONSHIP_MATRIX` 的实现状态。

### R5 冲突时本册让位

设计冲突 → 以 Owner 设计文档为准；实现状态冲突 → 以 `MODULE_INDEX` 与 `feature_registry.json` 为准；交付事实冲突 → 以 `development/CHANGELOG.md` 为准。本册永远不是终审。

---

## 2. 条目格式（冻结）

**ID 规则**：`0.2-<模块ID>-<三位序号>`，例 `0.2-WORLD-003`。
序号在**模块内**自增，不复用、不复位、不因搁置而回收。

| 字段 | 必填 | 说明 |
|---|---|---|
| 提出日期 | 是 | `YYYY-MM-DD` |
| 原始诉求 | 是 | 主人原话，引用块 |
| 主责模块 | 是 | 19 个模块 ID 之一，唯一 |
| 受影响模块 | 视情况 | 无则填 `—` |
| 关联 FeatureID | 是 | 取 [MODULE_INDEX](../v0.1/MODULE_INDEX.md) §2；不明确填 `待定` |
| 变更类型 | 是 | 新增玩法 / 规则修改 / 数值 / 接口契约 / 资产 / 表现 / 文档 |
| 影响面 | 视情况 | 数据链、存档 schema、验收场景、禁令冲突（性能预算、无失败状态、跨局档案） |
| 状态 | 是 | 见 §5 状态词表 |
| 追记 | 追加 | `YYYY-MM-DD · 内容`，只增不改 |

**格式样例（非登记条目，仅供排版参考，不属于任何模块槽）**

```text
### 0.2-XXX-001 · <一句话标题>
- 提出日期：YYYY-MM-DD
- 原始诉求：
  > <主人原话，逐字>
- 主责模块：XXX ｜ 受影响：YYY、ZZZ
- 关联 FeatureID：XXX-YYY ｜ 变更类型：规则修改
- 影响面：<数据链 / 存档 schema / 受影响验收场景 / 禁令冲突>
- 状态：待裁决
- 追记：
  - YYYY-MM-DD · <只增不改>
```

---

## 3. 追加式索引

只追加行、不重排、不回填、不按字母或模块排序。**排列顺序 = 登记顺序**，本身就是时间证据。**一行 = 一个条目**：跨多个模块槽登记的条目仍只占一行。

| 条目ID | 主责模块 | 标题 | 提出日期 | 状态 |
|---|---|---|---|---|
| 0.2-PLAYER-001 | PLAYER | 换弹进度条由头顶横向线形改为半圆形 | 2026-09-24 | 待裁决 |
| 0.2-PRESENTATION-001 | PRESENTATION | 过门与可交互物体统一为一套「白点 + 圆环进度」交互 UI | 2026-09-24 | 待裁决 |

---

## 4. 模块分区登记

分区基准 = [MODULE_INDEX](../v0.1/MODULE_INDEX.md) §1 的 19 个模块 ID。条目在所属槽内按 ID 序号排列；跨模块条目在多个槽内出现，**ID 相同**。

### PLAYER —— 玩家状态、移动、受击、交互仲裁、手电

#### 0.2-PLAYER-001 · 换弹进度条由头顶横向线形改为半圆形

- 提出日期：2026-09-24
- 原始诉求：
  > 换弹的表现，在头顶看不清楚，需要调整成半圆形的。
- 主责模块：PLAYER ｜ 受影响：PRESENTATION、ASSET
- 关联 FeatureID：`PLAYER-STATE`（换弹表现的当前载体）｜ 变更类型：表现
- 影响面：
  - **进度表达要重写，不是换贴图**。现在 `_update_reload_progress_bar()`（`src/player3d/PlayerAvatar3D.gd` L1337）用两行实现：`reload_progress_fill.scale.x = _reload_progress` + `position.x = -RELOAD_FILL_WIDTH * 0.5 * (1.0 - _reload_progress)`（缩放围绕中心，靠平移锁左边缘）。半圆形的填充必须换成**按角度裁切/扇形遮罩**，`scale.x` 这条路走不通。同一个函数里 `reload_progress_root.visible` 也管显隐，一并改。
  - **几何寄居在资产 prefab（⇒ ASSET）**：`ReloadProgress3D/Track` 与 `/Fill` 的 mesh 定义在 `assets/art/characters/player/chr_player_capsule01_3d/chr_player_capsule01_root_top3d_v001.tscn` L351–363 —— `MeshReloadTrack` = QuadMesh `Vector2(1.20, 0.18)`、`MeshReloadFill` = QuadMesh `Vector2(1.06, 0.09)`（青绿 `Color(0.22,0.92,0.76,0.98)` + emission），两个材质都开了 `billboard_keep_scale = true`；运行态版本在 `.../bunny01/production/v021/runtime/chr_bunny01_root_v021.tscn` L108 只 override 了 `position = (0, 1.6727, 0.0364)`。**改半圆 = 改资产** ⇒ 版本升版 + 台账同步。
  - **"看不清楚"有据**：1.20 × 0.18 m 的公告板横条挂在角色原点上方 1.67 m，默认第三人称距离下确实小。**但真实主因是尺寸还是对比度/被自身模型遮挡，未验**——裁决前不要先改数值。
  - **数据源只读，WEAPON 不需要配合**：`WeaponModel3D.reload_progress_changed` → `Player3D._on_weapon_reload_progress_changed`（L1659）→ `PlayerAvatar3D`；半圆的填充速率由该枪 `reload_time` 决定，只读不写，故 WEAPON 不计入受影响模块。
  - **⚠️ 待裁决**：弧角（180° / 240°）、半径、线宽、是否继续 billboard、与精英/Boss 头顶血条及对话气泡的层级避让。**没拍板前不动资产。**
- 登记人注：以上载体、行号、尺寸均为 2026-09-24 实测值，来源是本仓库工作区，不是设计文档口径。
- 状态：待裁决
- 追记：
  - 2026-09-24 · 与 `0.2-PRESENTATION-001` **强耦合**：诉求里那句「所有圈的进度条要统一」同时管到本条。两条的视觉语言必须一起定，**建议同批裁决**，否则会做出"半圆换弹 + 另一种圆环交互"两套皮。

#### 0.2-PRESENTATION-001 · 过门与可交互物体统一为一套「白点 + 圆环进度」交互 UI（对接条）

- 本模块要配合：`PlayerInteractionController3D` 是全 3D 世界**唯一的 `interact` 输入入口**与焦点事实源（`get_focus_snapshot()` L43、candidate 协议 L65）。统一 UI 要能回答"这里有没有东西可交互""交互进行到几成"，前提是本模块在 **candidate / 焦点快照里补字段**——现在只回 `provider / interaction_id / prompt / priority / distance_m`，**没有位置、没有时长、没有进度**，UI 拿不到这些东西。
- 主责槽：§4 PRESENTATION 分区

### WEAPON —— 武器内容、实例、装配树、命中与反馈

_暂无登记。_

### INVENTORY —— 背包、保险、快捷物品、扩容、换装事务

_暂无登记。_

### FATE —— 命运塔罗、牌组、三作用域

_暂无登记。_

### WORLD —— 楼层计划、房间图、区块归属、关卡入口、门与区段

#### 0.2-PRESENTATION-001 · 过门与可交互物体统一为一套「白点 + 圆环进度」交互 UI（对接条）

- 本模块要配合：**「过门」这一半归本模块**。`RoomDoor3D._refresh_prompt()` 目前用一块 `Label3D` 表达 4 种态（覆盖 / `通道开启中…` / `通道关闭中…` / `[E] 关闭通道` / `通道已开启`），统一 UI 上线时必须**逐态给出等价表达**，不能退化成"能开/不能开"两态；门的 `_transitioning → motion_finished`（L140）本身就是**有时长的过程**，是"圆环进度"最自然的第一个落点（对应 `0.2-PRESENTATION-001` 的方案甲）。另需处理 `DungeonEntrance3D`（`[E] 进入 %s`）、`RoomFurniture3D`（`[E] 搜索`）、`RoomLightSwitch3D`、`ExtractionBeacon3D`、`ServiceStation3D` 的 `Label3D` 退役与 candidate 字段补齐。
- 主责槽：§4 PRESENTATION 分区

### ENEMY —— 普通怪 AI、感知、导航、光照

_暂无登记。_

### ELITE —— 唯一精英名册、预约、跨局成长

_暂无登记。_

### BOSS —— Boss 阶段、下行权限

_暂无登记。_

### BASE —— 基地设施、商店、工坊、能源设施侧

#### 0.2-PRESENTATION-001 · 过门与可交互物体统一为一套「白点 + 圆环进度」交互 UI（对接条）

- 本模块要配合：`BaseFacility3D` 自带 `$PromptLabel`（L40）且文案分三档（`[E] 使用 %s` / `[E] %s %s` 动词态 / 不可用时显示 `availability_reason`），统一 UI **必须保留"设施不可用 + 原因"这一态**，否则玩家在设施前看不到为什么不能用。另注意 `BaseFacility3D.get_interaction_candidate()`（L201）与 `DungeonEntrance3D`（L52）都在候选里回填 `prompt_label.text`——退役 Label3D 时**不能只删节点**，要同步这条回填链，否则 candidate 里 `prompt` 变空串、统一 UI 拿到空文案。
- 主责槽：§4 PRESENTATION 分区

### SAVE —— 总档封套、行动快照、结算、复活、迁移

_暂无登记。_

### NARRATIVE —— 剧情触发、时间轴、跨局历史

_暂无登记。_

### TIME —— 权威时间、日夜、能源恢复输入

_暂无登记。_

### POWER —— 基地电力、手电电力、未来基地负载

_暂无登记。_

### ENTRY —— 启动分流、外观、衣柜、脱困

_暂无登记。_

### PRESENTATION —— HUD、VFX、音频、音乐、对话 UI

#### 0.2-PRESENTATION-001 · 过门与可交互物体统一为一套「白点 + 圆环进度」交互 UI

- 提出日期：2026-09-24
- 原始诉求：
  > 过门的时候和可交互物体的时候，需要一个统一的ui，可以使用一个白点。然后交互的时候是一个圈的进度条，所有圈的进度条要统一。
- 主责模块：PRESENTATION ｜ 受影响：PLAYER、WORLD、BASE、TRAINING、ASSET
- 关联 FeatureID：`UI-HUD`（统一 UI 本体）、`PLAYER-INTERACT`（焦点事实源）、`WORLD-GATE`（过门）、`WORLD-ENTRY`（进入关卡）、`WORLD-LOOT`（搜索容器）、`BASE-FACILITY`、`TRAINING-RANGE` ｜ 变更类型：表现 + 接口契约
- 影响面：
  - **现状是"各物体各挂一个 Label3D"，文案/位置/字号/颜色全不统一**（实测 2026-09-24）：
    - `DungeonEntrance3D` L18 `$PromptLabel`，`[E] 进入 %s`（L29）｜`BaseFacility3D` L40 `$PromptLabel`，`[E] 使用 %s`（L127）
    - `RoomDoor3D._refresh_prompt()`：**同一块 `Label3D` 有 4 种文案态**（覆盖提示 / `通道开启中…` / `通道关闭中…` / `[E] 关闭通道` / `通道已开启`），且各态 `modulate` 不同（覆盖 `Color(1.0,0.42,0.28)`、运动中 `Color(0.52,0.88,1.0)`）——统一 UI **必须能表达这 4 态**，不能只做一个静态白点
    - `RoomFurniture3D` `[E] 搜索`｜`RoomLightSwitch3D` `[E] 切换中央灯`｜`ExtractionBeacon3D` `[E] 启动撤离`｜`ServiceStation3D` `[E] %s`｜`TrainingRack3D` / `TrainingExit3D` 同构
    - `ThemedNPC3D` 是**代码建**的：`_make_label("PromptLabel", Vector3(0, 2.00, 0), 27, Color(1.0,0.82,0.32))`（L119）⇒ 三套建法并存（场景挂 / 代码建 / 资产 prefab 内）
  - **焦点事实源缺字段（⇒ PLAYER）**：UI 要"贴在物体上的白点"就需要 candidates 的**世界坐标**，要"圆环进度"就需要**时长与当前进度**。`PlayerInteractionController3D` 目前一个都没给。**这是本条的真正技术门槛，不是画图问题。**
  - 🔴 **交互根本没有"时长"概念，必须先裁决**：`request_interaction()` 只认 `is_action_pressed("interact")` 瞬时触发（L22–L40），全仓没有交互读条时长（`charge_time` 是武器蓄力、`hold_seconds` 是气泡停留，都不是交互）。于是"圈的进度条"有两种解释，**代价差很远**：
    - **(甲) 只给本来就耗时的交互用**：如门板运动 `RoomDoor3D._transitioning`→`motion_finished`、撤离、进关卡加载。改动小，不动输入手感。
    - **(乙) 全面改成按住读条**：所有交互统一"按住 E 走圈"。观感和诉求最贴，但**改的是玩法手感 + 输入契约**，且要处理"松开取消/打断"的失败语义。
    - 我倾向 **(甲) 起步**（不动手感、可增量），但这是主人的裁决项，不替他定。
  - 🔴 **性能预算硬约束**：`verify_3d_performance_budget`（world ≤2480，**total 余量仅 11**，见 [08 §8.2](../v0.1/08_技术施工_剧情触发.md)）。统一 UI 必须做成**单例 + 按需显示**，**绝不能给每个 provider 常驻挂 UI 节点**，否则直接挤爆门禁。
  - **退役各物体自带 Label3D（⇒ ASSET）**：`PromptLabel` 大量挂在**资产 prefab**里，退役它们要动 prefab / 升版本 / 同步台账；`ThemedNPC3D` 那种代码建的则只删代码。
  - **皮肤统一走既有工厂**：自绘 UI 必须带 `ui_style_exempt` meta 才豁免 `UIStyleFactory.apply_tactical_tree`（父 `_ready` 晚于子 `_ready`，子自设 StyleBox 会被父级打回）；白点与圆环若走 Control 层，要按这条来。
  - **纯表现，不进存档**：任何情况下不得写入 `BaseData` / 行动快照。
- 登记人注：文案清单、行号、4 态语义、建法差异均为 2026-09-24 本仓实测。
- 状态：待裁决
- 追记：
  - 2026-09-24 · 与 `0.2-PLAYER-001`（换弹半圆）**强耦合**：那条的「所有圈的进度条要统一」落在本条。**建议同批裁决视觉语言**（圆环几何、线宽、颜色、白点尺寸），否则会分裂成两套。
  - 2026-09-24 · 登记人提醒：本条**跨 6 个模块槽**（PRESENTATION 主责 + PLAYER/WORLD/BASE/TRAINING/ASSET 各一条对接条）。裁决后施工时，**接口那半（candidate 补 `world_position` / `duration` / `progress`）应先落 PLAYER，再让各 provider 填字段，最后才表现层换皮**——顺序反了会出现"UI 等字段、provider 等 UI"的对耗。

#### 0.2-PLAYER-001 · 换弹进度条由头顶横向线形改为半圆形（对接条）

- 本模块要配合：诉求末句「**所有圈的进度条要统一**」把本条也纳进本模块的管辖 —— 换弹半圆与交互圆环必须共用同一套视觉规格（线宽、颜色、底轨透明度、完成瞬间的表现）。本模块是这套规格的所有者，**先出规格再让两端各自实现**；`0.2-PRESENTATION-001` 若最终做成圆环组件，优先考虑把半圆也做成同一个组件的参数（弧角 180° vs 360°），而不是写两份绘圆代码。
- 主责槽：§4 PLAYER 分区

### PERFORMANCE —— 帧预算、流送、长测、画质与后处理

_暂无登记。_

### TRAINING —— 独立靶场与武器预览

#### 0.2-PRESENTATION-001 · 过门与可交互物体统一为一套「白点 + 圆环进度」交互 UI（对接条）

- 本模块要配合：`TrainingRack3D`（`[E] %s`）与 `TrainingExit3D`（`[E] 返回3D基地`）是同一套交互候选协议的第二个使用场。靶场是**可以脱离战局独立启动与验收**的功能（模块索引判为可独立），因此它也是**统一 UI 的独立验收入口** —— 在这里验不需要进关卡、不受性能门禁的战局预算干扰，建议作为首选落地与回归场地。
- 主责槽：§4 PRESENTATION 分区

### ASSET —— 模型、组件、导入、台账与放置

#### 0.2-PLAYER-001 · 换弹进度条由头顶横向线形改为半圆形（对接条）

- 本模块要配合：半圆几何的**承载方式要先定**——(a) 改 prefab 里的 `MeshReloadTrack` / `MeshReloadFill`，或 (b) 由 `PlayerAvatar3D` 代码生成 mesh。选 (a) 则动的是 `chr_player_capsule01_root_top3d_v001.tscn` 与运行态 `chr_bunny01_root_v021.tscn`，要走**资产版本升版 + 分账本登记**（角色属 `characters` 域，不是场景域）；选 (b) 则 prefab 里那两个 SubResource 与节点成为死代码，要一并清掉。**两条路的资产作业量差一档，建议随视觉裁决一起定。**
- 主责槽：§4 PLAYER 分区

#### 0.2-PRESENTATION-001 · 过门与可交互物体统一为一套「白点 + 圆环进度」交互 UI（对接条）

- 本模块要配合：统一 UI 落地必然**退役各物体自带的 `PromptLabel`**，而它们大量挂在**资产 prefab**（`BaseFacility3D` 的 `$PromptLabel`、`DungeonEntrance3D` 的 `$PromptLabel`、`RoomDoor3D` 的 `_prompt` 等），不是代码建的 ⇒ 属**资产改版**：逐件确认 Label3D 是 `index` 化在 prefab 内还是运行时生成的、升版、同步台账。`ThemedNPC3D` 那种 `_make_label()` 代码建的只需删代码，**别当成同一种活**。
- 主责槽：§4 PRESENTATION 分区

### TOOLING —— 验证套件、脚本、文档门禁

_暂无登记。_

---

## 5. 状态词表

本册状态只记录**主人对这条登记的处置口径**，不替代实现状态。

| 状态 | 含义 |
|---|---|
| 待裁决 | 已登记，规则本身还没定，需要主人决定 |
| 待设计 | 归属明确、意图明确，但 Owner 设计文档还没写 |
| 待施工 | 设计已定，代码 / 内容 / 资产还没动 |
| 施工中 | 正在做 |
| 待验收 | 实现完成，验收未过或未跑 |
| 已验收 | 有基线、日期、结果 |
| 已搁置 | 本期不做，保留记录 |
| 已取代 | 被另一条新条目顶掉，见追记 |

---

## 6. 边界：本册不是什么

- 不是设计主源 → [v0.1/design/](../v0.1/design/README.md) 与各 Owner 主题页。
- 不是实现状态索引 → [MODULE_INDEX](../v0.1/MODULE_INDEX.md)、`feature_registry.json`、[37 项跟踪表](../v0.1/FEATURE_RELATIONSHIP_MATRIX.md)。
- 不是交付日志 → [development/CHANGELOG.md](../v0.1/development/CHANGELOG.md)。
- 不是排期表、不是里程碑、不是发布说明。

---

## 附录 A：v0.1 中已挂「v0.2 / 待裁决 / 待施工」标签的既存项

**这是引用区，不是本册条目。** 列出来只是为了主人登记时能直接挑编号（"登记 A3、A7"），避免每次重新考古。

| 编号 | 事项 | 建议主责模块 | 关联 FeatureID | 来源 | 现状口径 |
|---|---|---|---|---|---|
| A1 | 剧情演出改为时间轴模型（按时刻派发、不等信号） | NARRATIVE | NARRATIVE-TRIGGER | [08](../v0.1/08_技术施工_剧情触发.md) §1、§12 | **v0.2 设计已冻结，实现未建立** |
| A2 | 触发条件必填 + 跨局历史落盘（把 v0.2 明确推迟的两件事做掉） | NARRATIVE（受影响：SAVE） | NARRATIVE-TRIGGER | [方案](../v0.1/design/2026-09-23_剧情触发语义规范与跨局历史_方案.md) §0.2 | 待裁决 |
| A3 | `retry/never` 新语义 + 通用条件引擎 | NARRATIVE | NARRATIVE-TRIGGER | [MODULE_INDEX](../v0.1/MODULE_INDEX.md) §2、[12](../v0.1/12_全游戏完成度清单.md) §8 | 待裁决 |
| A4 | `NarrativeCatalog` 剧本索引与稳定剧本 ID | NARRATIVE | NARRATIVE-TRIGGER | [12](../v0.1/12_全游戏完成度清单.md) §8 | 待建 |
| A5 | 对话 UI 契约 6 处差异收敛（队列、`skippable`、BBCode、带参命令） | PRESENTATION | DIALOGUE-UI | [12](../v0.1/12_全游戏完成度清单.md) §8 | 待收敛 |
| A6 | `Dungeon3D` 身份化击杀事件与精英遭遇上行事件 | WORLD（受影响：ENEMY、ELITE） | WORLD-LOOT、ELITE-ROSTER | [08](../v0.1/08_技术施工_剧情触发.md) §4.4 | 独立任务，是 A1 切片的前置 |
| A7 | 新增 30 张塔罗的独立玩法执行器（48 → 78） | FATE | FATE-RULES | [MODULE_INDEX](../v0.1/MODULE_INDEX.md) §2、[12](../v0.1/12_全游戏完成度清单.md) §4 | 待施工 |
| A8 | 多域存档清单与原子事务（基地/精英/剧情不半套成功） | SAVE | SAVE-PROFILE | [12](../v0.1/12_全游戏完成度清单.md) §9 | P0 未闭环 |
| A9 | 卡/精英/剧情/电梯/区段提交的统一版本迁移 | SAVE | SAVE-RUN | [12](../v0.1/12_全游戏完成度清单.md) §9 | P0 未闭环 |
| A10 | `RevivalPolicy` 复活玩法本体 | SAVE | RUN-REVIVE | [MODULE_INDEX](../v0.1/MODULE_INDEX.md) §2 | 契约已建，玩法未实现 |
| A11 | 工坊成本数据外置 + 工坊详情表现 | BASE | BASE-WORKSHOP | [MODULE_INDEX](../v0.1/MODULE_INDEX.md) §2 | 待做 |
| A12 | 局内商人正式表现 | BASE（受影响：INVENTORY） | RUN-MERCHANT | [MODULE_INDEX](../v0.1/MODULE_INDEX.md) §2 | 逻辑已验，表现未验 |
| A13 | 剩余 11 只唯一精英内容投放 | ELITE | ELITE-ROSTER | [12](../v0.1/12_全游戏完成度清单.md) §6 | 当前 1/12 |
| A14 | 基地灯光与设施负载接统一电网（含真实表现） | POWER | POWER-SYSTEM | [MODULE_INDEX](../v0.1/MODULE_INDEX.md) §2 | 开发中 |
| A15 | PostFX 调参转正范围裁决、保存失败结果与真渲染 | PERFORMANCE | GRAPHICS-POSTFX | [MODULE_INDEX](../v0.1/MODULE_INDEX.md) §2 | 待裁决 |
| A16 | 远征 01 走廊白模与 BOSS 房席位 | WORLD | WORLD-PLAN | [远征 01 设计](../v0.1/design/远征关卡01设计.md) | 设计源只有 7 房、无 Boss 房席位 |

挑中哪条，说一句编号即可。我会按 R1/R2 判定主责与受影响模块、生成 `0.2-<模块>-NNN` 正式条目并写入对应槽位，同时在 §3 追加索引行。
