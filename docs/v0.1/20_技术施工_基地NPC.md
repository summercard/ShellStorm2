# 技术施工｜基地 NPC v0.1

系统编号：横向（基地域）；功能ID：`BASE-NPC`；工程版本：`0.1.0`；设计修订：r5（2026-11-04）；
来源：<span style="color:#1565C0">**[用户设计]**</span> 2026-11-02 主人要求「在 99F 基地增加一个 NPC，先用主角的模型换上全绿色的皮肤，放在场景中，会自己移动，可以对话，按照 NPC 的系统制作」；同轮追加「绿色直接从可以更换的衣柜里去找，可以直接用的」⇒ 绿皮必须是衣柜里的一个可选项，不许另存一份色值；并指出第一版拍的是「基地与荒野」兼容场景，不是 99F 室内基地 ⇒ 装配点从 `BaseWorld3D` 移到 `TowerDescent3D.facility`。

r2 同日晚些时候的观感返工（同一批口径，逐条落到本文与验收里）：
「为什么是自发光的绿色？荧光感太强了」⇒ 自发光归零；
「头要和角色一样大，现在大了很多」⇒ 体型乘玩家同一倍率；
「对话框也太小了」⇒ 气泡字号 r2 放到 0.0042、r3 再**整体放大一倍**到 0.0084（同轮追加「对话还是需要大一点太小了，大一倍先」）；
「e 交谈这个提示要接近才出来」「上面的白点去掉」「名字也去掉」⇒ 交互半径收到 1.5m、白点退役、名字/身份牌撤除，头顶只留"黄色提示 + 台词气泡"；
「行走的的时候会有残影」⇒ 与自发光同一根因（`glow` 作用在自发光体上）；
「点击交谈后，角色要立刻停下来，面对角色」⇒ 搭话即定住并瞬时转向；
r4（同日再一轮）「对话框会遮住整个角色，往上放一些，黑色背景半透明」⇒ 气泡中心 2.05 → **3.40**（俯角压缩，见 §5.1），底板改 **0.55 alpha 半透明黑**；
「这个白色的交谈和白点不要了」⇒ NPC 列入控制器**圆点排除表**（根本不建节点），白色「(e) 交谈」彻底消失，只留黄色 `[E] 交谈`。

r5（2026-11-04，本轮）<span style="color:#1565C0">**[用户设计]**</span> 主人要求：「我不是增加了一个收租人的精英怪吗，当我第一次遇到精英怪后，我再次回到 99F 基地，我 99F 基地的绿色 NPC，会站在边上，说：你遇到收租人啦？有没有被夺走东西呀？你可以去二楼的档案室里看看它的信息哦。需要按照正常的链路完成这个任务，并且更新设计文档和账本。」
⇒ 本节新增**一次性剧情节拍**（§13）：条件、站位、开口时机、跨局落盘、说完回巡逻；台词由内容目录持有，实体不写台词字面量；落盘复用现有跨局剧情历史，**不新增存档字段**。

状态：<span style="color:#EF6C00">**[部分完成]**</span> 逻辑链、专项验收与真实渲染对照均已通过；未做的部分是导航避障、对话分支、表情系统接入等扩展能力，见 §12。

上级设计：[游戏设计文档](README.md)；相关系统：[基地设施](07_技术施工_基地设施.md)（同在 99F，但两者所有权互不覆盖）、[UI 与对话系统](18_技术施工_UI与对话系统.md)（气泡载体）、[玩家与操作](03_技术施工_玩家与操作.md)（统一交互仲裁）、[资产与内容规范](10_资产与内容规范.md)（台账）。

## 1. 目标与范围

<span style="color:#1565C0">**[用户设计]**</span> 99F 基地里要有一个**真人模样的 NPC**：外形取自主角模型并整体染绿，自己在场地里走动，玩家靠近能搭话。

范围：

| 包含 | 不包含 |
|---|---|
| NPC 内容目录（ID/名称/身份/皮肤/台词） | 任务系统、任务面板、奖励发放 |
| 复用玩家 bunny01 几何 + 运行时全绿材质 | 新增美术母版、新增 GLB、改源模型 |
| 巡逻（多点往返 + 到点停留）、朝向、待机/步行动画 | 导航网格 A*、避障、寻路失败重试 |
| 统一交互协议（`PlayerInteractionController3D` provider） | 新开一套输入或按键 |
| 头顶气泡逐句对话、环回、离场收起 | 分支对话树、选项、立绘、语音 |
| **一次性剧情节拍**：按游戏事实成立 → 站到边上 → 走近自动开口 → 落盘一次（§13） | **新增存档字段**（复用 `narrative_history`，见 §13.5） |
| 基地侧只读投影 `get_npc_count() / get_npc_snapshots() / find_npc()` | 第二个状态所有者；基地不持有 NPC 巡逻状态 |

## 2. 与既有 NPC / 对话系统的分工

`src/world3d/ThemedNPC3D.gd` 是 2026-09 的**占位表现**（胶囊体拼的主持人，台词贴 `Label3D`），目前只被 `Player3DStateGallery` 的三态预览使用，**没有接进任何正式场景**。本次不改造它（它的验收 `verify_player3d_state_gallery_flow` 仍在跑），新系统另立 `src/npc/`。

| 载体 | 谁用 | 状态 |
|---|---|---|
| `NpcCharacter3D`（本文） | **正式基地 NPC** | 已实装 |
| `ThemedNPC3D` | 玩家三态预览里的 NPC 占位 | 保留，不接入正式场景 |
| `SpeechBubble3D` + `CharacterBark3D` | 有实体说话人的台词（本系统消费） | 沿用，未改 |
| `DialogueUI`（底栏，autoload） | 系统/画外音 | 不用于 NPC 台词 |

选气泡不选底栏，依据 [18 §1.1](18_技术施工_UI与对话系统.md)：说话人**有实体**走头顶气泡。NPC 不认识 `DialogueUI`，也不 import 它。

## 3. 内容契约（`src/npc/NpcCatalog.gd`）

内容与实体分离，理由同 `BarkCatalog`：台词只有一个来源，实体只认 `npc_id`。

| 字段 | 类型 | 说明 |
|---|---|---|
| `display_name` | String | 名字。**2026-11-02 起不画在头顶**，只供剧情/日志/快照认人 |
| `role` | String | 身份。同上，不上屏 |
| `skin_variant` | String | **衣柜里的作业服变体 ID**。色值不存本表，转调 `AvatarCustomizationCatalog` |
| `skin_emission` | float | 自发光强度，**当前恒为 0**（见 §5"发光退役"）；保留字段给未来的发光皮 |
| `lines` | Array[String] | 台词，按顺序推进，环回 |

稳定 ID：`npc_base99_green`（99F 常驻，绿皮）。当前条目：

| 字段 | 值 |
|---|---|
| 名字 / 身份 | 绿苔 / 99F 基地看守（**均不上屏**） |
| 皮肤 | 变体 `suit_green`（衣柜「苔绿作业服」）⇒ `Color(0.16, 0.68, 0.30)`，自发光 **0** |
| 台词 | 4 句：回归问候 → 指路全息台 → 指路枪械工坊 → 自述 |

**尚未与内容数据库 xlsx 对表**。台词改这里即生效，不需要动场景。

## 4. 实体契约（`NpcCharacter3D`）

### 4.1 所有权

| 项 | 所有者 |
|---|---|
| 模型实例、皮肤材质、关节姿态 | `NpcCharacter3D` 自己 |
| 巡逻进度（当前目标点、停留计时） | 同上 |
| 对话进度（当前第几句） | 同上；**不写盘**，离场即 `-1` |
| 该不该说话 / 说什么内容 | `NpcCatalog` |
| 交互候选仲裁与圆点 | `PlayerInteractionController3D`（圆点对 NPC 已退役，见 §5.1） |
| 基地层可读性 | `TowerDescent3D` 的三个只读方法（`get_npc_count` / `get_npc_snapshots` / `find_npc`） |

### 4.2 命令 / 查询 / 事件

| 类型 | 名称 | 说明 |
|---|---|---|
| 命令 | `configure(Dictionary)` | 运行期换内容；不改模型与皮肤；会重新求值节拍 |
| 命令 | `advance_dialogue() -> Dictionary` | 推进一句；返回 `spoken/line_index/text/finished_cycle`（循环台词，不含节拍） |
| 命令 | `hide_dialogue()` | 收起气泡并清进度 |
| 命令 | `set_standby_world(point, look_world)` | 迎宾站位（世界坐标）+ 等待时朝向的参考点；由 `TowerDescent3D` 按锚点调用（§13.3） |
| 命令 | `refresh_story_state() -> void` | 重新求值"有没有该播的节拍"；回基地时调一次（§13.4） |
| 命令 | `speak_pending_story_beat() -> bool` | 把第 0 句说出口；正常流程由 `HAIL_RADIUS` 自动触发，此入口供剧情/验收 |
| 查询 | `get_snapshot() -> Dictionary` | 见 4.3 |
| 查询 | `get_pending_story_beat() / get_story_beat_id() / is_story_standby()` | 节拍只读（§13） |
| 查询 | `get_interaction_candidate / get_interaction_dot_anchor / is_interaction_dot_visible` | 统一 provider 协议；`is_interaction_dot_visible()` **恒 false**（白点退役） |
| 查询 | `get_display_name / get_role / get_current_line / get_line_count / is_dialogue_visible / is_speaking` | 只读 |
| 事件 | `interaction_changed(visible, text)` | 气泡开合（节拍台词也走这条，每句一次） |
| 事件 | `configured(npc_id)` | 内容变更 |
| 事件 | `npc_spoke(npc_id, line_index, text, finished_cycle)` | 每推进一句**循环台词**一次；当前无订阅者，留给任务/剧情系统 |
| 事件 | `story_beat_started(npc_id, beat_id, first_line)` | 一次性节拍第一句出口；当前无订阅者 |
| 事件 | `story_beat_finished(npc_id, beat_id)` | 一次性节拍整段说完并已落盘；半路被打断不发 |

### 4.3 快照 schema

`npc_id` / `display_name` / `role` / `line_count` / `line_index` / `in_range` /
`dialogue_visible` / `speaking` / `moving` / `talk_engaged` / `patrol_enabled` / `patrol_target` /
`patrol_point_count` / `dwelling` / `position` / `yaw` / `painted_mesh_count` / `visual_scale` /
`prompt_visible` / `has_name_label` / `has_face_mask` /
`skin_variant` / `skin_albedo` / `skin_emission` / `skin_material_name` / `has_model` /
`story_beat_id` / `story_beat_pending` / `story_beat_delivered` / `story_standby` /
`standby_world` / `hail_radius`。

`line_index = -1` 表示「没在对话中」，不是「第 0 句还没说」以外的第三种状态。
`story_beat_id` 为空字符串表示"当前没有待播节拍"，与 `line_index = -1` 同一种"没有"的写法。

## 5. 模型与全绿皮肤

- **颜色来源：衣柜（2026-11-02 主人要求「绿色直接从可以更换的衣柜里去找，可以直接用的」）**
  - `PlayerAvatar3D.CUSTOMIZATION_OPTIONS["body"]` 新增 `suit_green`，`BODY_COLORS["suit_green"] = Color(0.16, 0.68, 0.30)`；
    `AvatarCustomizationCatalog` 同步 `VARIANT_LABELS["suit_green"] = "苔绿作业服"` 与 `VARIANT_COLORS`。
  - `NpcCatalog` **不再保存色值**，只保存变体 ID `suit_green`；`get_skin_albedo()` 转调 `AvatarCustomizationCatalog.get_variant_color()`。
  - 结果：玩家在衣柜里选「苔绿作业服」拿到的绿，与 NPC 身上的是**同一个色值**，改颜色只需改衣柜一处。
  - 失败语义：变体缺失/被改名 ⇒ `push_warning` + 返回 `Color.MAGENTA`（醒目紫），不悄悄回退成另一个绿，避免"看起来正常但其实取错了色"。验收 A09 同时断言「NPC 色 == 衣柜目录色 == `PlayerAvatar3D.BODY_COLORS`」三者一致。
- **几何来源**：**玩家角色场景本身** `scenes/Player3D.tscn` 的 `Avatar3D`（其内部即 bunny01 运行时装配）。
  - 不直接写 `..._v021.tscn` 版本路径：运行资产命名门禁禁止 `src/**/*.gd` 新增对 `*_vNNN.*` 的引用
    （债务表只允许缩小），而且「NPC 用玩家那份模型」的语义要求玩家模型升级时 NPC 自动跟随。
- **装配方式**：实例化玩家场景 → 取出 `Avatar3D/VisualRoot` → **整只扔掉玩家外壳**（`CharacterBody3D`、相机、手电、视觉代理）→ 把干净的 `VisualRoot` 挂到 NPC 下。必须在 `add_child` 之前完成剥离：`Avatar3D` 挂着 `PlayerAvatar3D` 脚本，一旦进树就会跑整套玩家表现（换装、状态机、换弹环），NPC 会开始播玩家的动作。`src/npc/NpcCharacter3D.gd::_build_visual` 的注释写死了这条顺序。
- **体型必须与玩家同口径（r2 修正）**：`Player3D._initialize_debug_scale_contract()` 把 `Avatar3D.scale` 乘上 `DEFAULT_BASE_SIZE_MULTIPLIER = 0.80`（"旧资产尺寸的 80% 现在定义为角色的新 100%"）。`Player3D.tscn` 里的场景实例是原始尺寸，0.8 是**运行时**乘上去的 —— NPC 不跑 `Player3D`，第一版就漏了这一步，整只比玩家大 25%，头顶那一圈尤其显眼（业主：「头要和角色一样大，现在大了很多」）。
  - 修法：`visual.scale = avatar.scale × Player3D.DEFAULT_BASE_SIZE_MULTIPLIER`。**引用同一个常量**，不另抄 0.8 —— 玩家调基础体型时 NPC 自动跟随。
  - 验收 A13b 同时断言两条：`NPC.VisualRoot.scale == 玩家 Avatar3D.scale`、以及两者可见几何高度比落在 1.0 ± 10%。
- **皮肤**：递归收集 `VisualRoot` 下所有 `MeshInstance3D`，统一 `material_override = StandardMaterial3D{albedo=衣柜绿, metallic=0.04, roughness=0.74}`。
  - 用 `material_override` 而不是改材质资源：原材质是玩家共享的，改资源会把玩家一起染绿。验收 A11 专门盯这条（实例化玩家场景，断言其网格没有 `material_override`）。
  - 隐藏的旧程序化部件（`VisualRoot/Body`、`Head`、`Scarf`、`Hand`、`Feet`，v021 里 `visible=false`）也会被覆盖，但不可见，不构成视觉污染。所以 `painted_mesh_count = 29`（全部本体网格）而**可见本体只有 10 件** —— 验收对这两者只断言「不少于」。
  - **发光退役（r2）**：曾经为兜夜景可读性把 `emission` 开到 0.06→0.30。实机效果是整只泛荧光，并且 99F 的 `WorldEnvironment` 开着 `glow`（`GraphicsSettingsManager` 的 bloom 档，`glow_intensity 0.72`），自发光体在移动时会拖出一圈光晕 —— 业主两条反馈「为什么是自发光？荧光感太强了」「行走的时候会有残影」其实是同一根因。现在 **`emission_enabled = false`（`NpcCatalog.SKIN_EMISSION = 0`）**，可读性改由场景光照 + 衣柜绿本身明度承担。验收 A14b 断言材质没有开自发光、且目录里也不许再声明非零值。
- **面饰单独处理（关键）**：bunny01 的头部几何**本身没有眼睛** —— 主角的脸全部来自默认面饰 `electronic_mask`（`PlayerAvatar3D._ready()` 实例化到 `HeadJoint/FaceAccessorySocket`）。NPC 不跑 `PlayerAvatar3D`，所以必须自己补挂这一件，否则是一个**没有脸的绿色圆球**（实拍确认）。
  - 位置与玩家侧一致：直接挂 `HeadJoint` 下，面具源已按 HeadJoint 静止原点导出、自带偏移。
  - **面饰不染绿**。「全绿皮肤」指头壳/躯干/耳/手/脚这些本体几何；染色会把蓝色发光眼一起吃掉，NPC 又变回无脸。判定按祖先名 `ElectronicMask`（面具网格是 GLB 内嵌的，没有可写死的稳定路径）。
  - 代价：NPC 永久使用 `mask_idle` 表情，不接表情系统 —— 验收 A08 断言「至少存在一件面饰网格、且它没被涂绿、且本体每件都涂了绿」。
- **可见几何实测**：原始尺寸高 **1.519m**、宽 1.033m、深 0.654m；乘 0.8 后 **1.215m / 0.827m / 0.523m**，底边贴 `y=0`。验收 A12/A13 断言 `|min_y| ≤ 0.06`、身高落在 1.05–1.40m（对应 1.519 × 0.8 = 1.215）。

## 5.1 头顶表现（r2 大幅收窄：只剩"黄色提示 + 台词气泡"）

2026-11-02 业主连提三条：「上面的白点去掉」「名字也去掉」「e 交谈这个提示要接近才出来」。终态是**头顶最多一层文字**：

| 时机 | 头顶内容 | 高度（中心） | 依据 |
|---|---|---|---|
| 未接近（> 1.5m） | **什么都没有** | — | 交互候选为空 ⇒ 不聚焦 ⇒ 提示不显示 |
| 站进 1.5m 且被聚焦 | 黄色 `[E] 交谈` | 1.44 | 50 号字 × `pixel_size 0.005` ⇒ 字高 0.25m，底边 1.315 |
| 按下 E 后 | 台词气泡（提示同时收起） | **3.40** | 两行气泡高 1.21m ⇒ 半高 0.605，底边 **2.795**，离头顶 **1.58m** |

- **为什么是 3.40（俯角压缩，两轮实测）**：基地相机俯角约 **53°**，世界里每条 Y 抬升在屏幕上只走 `cos53° ≈ 0.60` 倍。
  - 中心 2.05（底边 1.445，世界间隙 0.23m）⇒ 屏幕 3~4px，气泡直接糊在头上。
  - 中心 2.80（世界间隙 0.98m）⇒ 实拍屏幕间隙只有 **0.34 个角色高**，气泡下缘仍压着头顶、还盖住黄色提示。
  - 中心 **3.40**（世界间隙 1.58m）⇒ 实拍气泡底边 **y=289px**、角色头顶 **y=322px**，屏幕间隙 **33px ≈ 0.7 个角色高**，两者彻底分开。
  - 经验值：俯视角下要"看得出空隙"，**世界间隙至少 ≈ 1.3 倍角色身高**。验收 A14b 按屏幕等效量守门（≥ 0.45 个角色屏幕高），不再只比世界米数 —— 只比米数会放过 2.80 那种"数值够了、看着还贴着"的情况。
- **底板半透明**：`SpeechBubble3D.fill_color` 从 `Color(0.010, 0.032, 0.045, 1.0)`（不透明深青）改为 **`Color(0.012, 0.018, 0.026, 0.55)`**（半透明黑）—— 业主「黑色背景半透明」。能看清气泡背后是谁，文字仍然压得住。
  - **实测校验方法（A/B 同机位）**：拍一张说话的帧、一张同机位不说话的帧，在同一像素上解
    `result = (1-a)·bg + a·fill`。实测两点的 `bg/result` 为 `78/59` 与 `54/46`，联立得 `fill ≈ 36`、`a ≈ 0.46` —— 与配置的 0.55 在同一量级（差值来自 tonemap/glow），**确认 alpha 混合真的生效**，不是"看着像半透明但其实不透明"。
    单点估 alpha 会得出 0.12 的错误结论：因为把 `fill` 误当成 `(3,5,7)` 了。要用两个不同亮度背景点联立。
  - ⚠️ **透明化的连锁改动**：`Panel` 两个 surface 的材质改走 `TRANSPARENCY_ALPHA`；文字 `Label3D.alpha_cut` 必须从 `ALPHA_CUT_DISCARD` 改成 `ALPHA_CUT_DISABLED`，否则文字走**不透明队列**、永远先渲染，随后半透明底板叠上去把白字压到 45% 亮度。改完靠 `render_priority` 排序：底板材质 **0**、文字 **2** ⇒ 先底板、后文字。验收 A24c 三条一起盯（alpha 在 0.15–0.9、填充材质确实是 alpha 混合、底板 priority **小于**文字的）。
  - TAA 风险：工程默认 `anti_aliasing = "taa"`，透明几何不写运动矢量。气泡位移来自父节点、速度很低，且 `_face_camera` 只改朝向不改位置，实测走动帧无可辨拖影。若将来把气泡改成高速跟随，需要重新评估（退回不透明底板，或给文字单独走不透明层）。

- **名字牌 / 身份牌已撤除**：`display_name` 与 `role` 只留在内容目录与快照里（剧情/日志要认人），不再画在头顶。验收 A14 反向断言：NPC 子节点里除 `PromptLabel` 外不许有常驻 `Label3D`，且快照 `has_name_label = false`。
- **白点退役（两道保险）**：控制器给每个 provider 建一枚常驻白点，白色「(e) 交谈」就挂在那枚点上。
  - ① `PlayerInteractionController3D.DOT_EXCLUDED_PROVIDER_SCRIPTS` 里登记 `res://src/npc/NpcCharacter3D.gd` ⇒ 控制器**根本不创建**圆点节点（与基地设施同一套机制）。这是主手段：`is_interaction_dot_visible() = false` 只能让圆点**淡出**，插值期间白点和白字会闪一下 —— 正是业主两轮反馈（「上面的白点去掉」→「这个白色的交谈和白点不要了」）看到的那个闪。
  - ② `is_interaction_dot_visible()` 返回 `false` 作二次兜底：路径那条被改坏时，圆点至少会淡到不可见。
  - 于是 NPC 头顶只剩一块**黄色** `[E] 交谈`（`PromptLabel`，`font_size 50` / `Color(1, 0.82, 0.28)`），与基地设施同款。验收 A20c 断言控制器给 NPC 的圆点快照**为空**（节点不存在）+ 路径确实在排除表里。
- **提示改由自己的 `PromptLabel` 承担**，与基地设施（`BaseFacility3D.PromptLabel`）同款：`font_size 50`、`modulate (1, 0.82, 0.28)`、`outline 8`。"场上的『能按 E』只有一种长相"是这条的唯一理由 —— 不要给 NPC 另调一套黄。- **提示与气泡互斥**：`_refresh_prompt_visibility()` 的条件是 `focused and in_range and not talk_engaged`，所以两层永远不会同时出现 —— 它们在 1.3–1.5m 这段空域几何上有重叠，但画面上不会同时存在。
- **交互半径 2.4m → 1.5m**：旧值在玩家还没走近时就冒出提示。球形热区中心从 `y=0.9` 降到 `0.6`（角色只有 1.2m 高，中心抬太高会让上半球悬在头顶）。
- **气泡字号（r3：整体放大一倍）**：`SpeechBubble3D` 默认 48px / `pixel_size 0.0055` 是给大体型说话人调的；r1 收到 `0.0026`（字高 0.13m）太小，r2 放到 `0.0042`（0.20m）业主仍嫌小。终值 **`pixel_size 0.0084`（字高 0.40m）+ `wrap_width_px 1120`**。
  - 两个数值**同比例**放大才叫"整体大一倍"：`wrap_width_px` 决定每行能放多少像素，只放大 `pixel_size` 会让每行字数变少、台词多折一行、气泡变成又窄又高的竖条。同步 560 → 1120 才能保持每行字数与行数不变，整块等比放大。
  - 验收 A24b 不只比常量，还**实测底板世界宽度 ≥ 3.0m**：常量写对但 `bubble_scale` 被别处改小时，画面上一样变小，只有量世界尺寸才抓得住。
⚠️ **不能只改 `bubble_scale`**：它只参与底板几何的 `unit = pixel_size × bubble_scale` 换算，Label3D 的 `pixel_size` 不变 ⇒ 底板缩小、文字不变，字直接溢出气泡（实拍踩过）。`pixel_size` 同时是底板换算与文字渲染的输入，改它才是同步的。

## 6. 动画口径

模型没有骨骼动画（玩家也是脚本驱动关节），NPC 自己写关节曲线：

| 状态 | 关节 | 参数 |
|---|---|---|
| 待机 | `BodyJoint` | 竖直呼吸 `sin(t·1.7)·0.012m`，侧倾 `sin(t·0.9)·0.012rad` |
| 待机 | `HeadJoint` | 反向微侧倾 `-sin(t·1.7)·0.008rad` |
| 待机 | `EarSocketL/R` | 左右错相 `sin(t·2.2)·0.06rad` / `+1.1` 相位 |
| 步行 | `BodyJoint` | 重心 `lift·0.030m` + 横摆 `wave·0.022m` + 压步 `wave·0.05rad` |
| 步行 | `FootJointL/R` | 前后 `±0.115m` 交替，抬起 `max(0, ±wave)·0.055m` |
| 步行 | `HeadJoint` | 反向稳定 `-wave·0.035rad`，点头 `lift·0.02rad` |

步频 `3.2 Hz` 相位推进（`_gait_phase += delta·3.2`）。**不改缩放**做力度，与角色动画规范一致。

## 7. 巡逻

- 数据：`patrol_offsets: Array[Vector3]`，**相对本节点的局部偏移**。少于 2 个点 ⇒ 原地待机。
- 启动时把偏移换算成世界坐标缓存，并把节点摆到第 0 个点，目标设为第 1 个点（否则第一段会「先走回原点」）。
- 速度 `1.05 m/s`；到点判定 `0.08 m`；到点停留 `1.6s` 后切下一点，**末点回到首点**（环回，不是往复）。
- 朝向：目标 yaw = `atan2(-dir.x, -dir.z)`（Godot 节点前方为 `-Z`），`_yaw` 独立保存后 `lerp_angle(…, delta·7.0)` 追。**不能**从 `rotation.y` 插值 —— 写回后下一帧又从「已转到的值」出发，转速会越插越慢。
- 不参与物理：NPC 是 `Node3D`，没有 `CharacterBody3D`，也不做碰撞。99F `facility` 房间地面是平的（射线实测两个锚点都命中 `FloorSupport` 于 `y=-12.00`，0.40r × 1.30h 胶囊无重叠），这条简化成立；**若以后把 NPC 放上有高差的地面，必须改成贴地采样**，见 §9。
- **搭话定住（r2）**：业主「点击交谈后，角色要立刻停下来，面对角色」。
  - 进入：`perform_interaction` → `_engage_talk()`，立刻 `_moving = false`、清掉停留计时，并把 `_yaw` / `_yaw_target` / `rotation.y` **一次性吸附**到玩家方向（不是插值 —— 按 E 的那一帧就该看到脸）。
  - 维持：`_tick_patrol` 在 `_talk_engaged` 时直接 return（位置不动、也不消耗停留计时）；`_tick_pose` 以 `TALK_TURN_SPEED = 14`（巡逻 7 的两倍）持续对准玩家，玩家绕着走它跟着转。
  - 解除：条件选的是**玩家离开交互范围**，不是"气泡消失" —— 气泡 6 秒后会自动收起，若以气泡为准，NPC 会在玩家还站着的时候自己走开。解除后从当前位置直接走向当前巡逻目标点（可能已偏离路线，但一步就回正）。
  - 验收 A22b/A22c/A25b 三段盯死：按下 E 后 `moving=false`、朝向误差 < 0.15rad、提示收起；把巡逻重新打开并站 0.5s 位移 < 0.02m；玩家走出 8m 后 0.6s 内恢复 `moving=true`。

## 8. 交互与对话

- 交互范围：子 `Area3D`（`collision_layer=0`、`collision_mask=1`、`SphereShape3D` 半径 **1.5m**，中心 `y=0.6`），只检测 `player_3d` 组。半径从 2.4m 收窄是业主口径「e 交谈这个提示要接近才出来」—— 旧值在玩家还没走近时就冒提示；验收 A20b 断言 2.0m 处**不给候选、也不显示提示**。
- provider 协议实现 5 件：`get_interaction_candidate`（`prompt="[E] 交谈"`、`priority=60`、`interaction_id="base_npc:<npc_id>:<instance_id>"`）、`set_interaction_focus`、`is_interaction_dot_visible`（恒 `false`，白点退役）、`get_interaction_dot_anchor`、`perform_interaction`。
- 提示：`PromptLabel`（黄色 `[E] 交谈`）只在 `focused and in_range and not talk_engaged` 时可见，见 §5.1。它和控制器那套白点无关 —— 白点被 `is_interaction_dot_visible=false` 淡出了。
- 推进：首次 → 第 0 句；之后逐句 +1；停在最后一句时不报完成；**再按一次**回第 0 句，那次 `finished_cycle = true`（玩家有时间读完最后一句）。
- 气泡：`CharacterBark3D.say_text(line, 6.0s)`，居中挂高 **`3.40m`**（以气泡**中心**为原点，抬高理由见 §5.1 的俯角换算）。6 秒自动收起，期间按 E 可提前推进。
- 说话期间**黄色提示一并收起**：条件看 `_talk_engaged or _dialogue_visible`，不只 `_talk_engaged` —— 气泡可能由 `advance_dialogue()` 直接推进（剧情/测试），那条路径不经过 `perform_interaction`，光看 `_talk_engaged` 会让提示压在气泡下缘上（2026-11-02 实拍）。
- 离开范围：`hide_dialogue()` → 气泡淡出、`line_index` 回 `-1`、`dialogue_visible=false`，同时解除搭话定住。

## 9. 失败收口与边界

| 情形 | 行为 |
|---|---|
| `npc_id` 不在目录 | `push_warning`，名字退化为节点名，台词为空 ⇒ `advance_dialogue` 返回 `{spoken:false, reason:"no_lines"}`，不抛错 |
| 玩家外观场景缺 `VisualRoot` | `push_error`，`has_model=false`，其余系统照常运行（不会 null 崩溃） |
| 面饰场景加载失败 / 缺 `HeadJoint` | `push_warning`，NPC 无脸但其余照常（不阻塞巡逻与对话） |
| 模型节点缺关节 | 对应关节动画静默跳过，不 push_error（模型升级可能改名，不该把 NPC 变成硬失败） |
| 玩家离开 / 场景卸载 | 气泡收起，无外部残留；NPC 不写 `user://`，不持有存档 |
| 巡逻点全在原点 | `patrol_point_count < 2` ⇒ 待机；不会原地抖动 |
| 未来放到非平面地块 | **当前会浮空/入地**。必须补贴地射线；本文件与 `_tick_patrol` 是唯一改动点 |

## 10. 正式接入

| 层 | 位置 |
|---|---|
| 场景 | `scenes/BaseNpc3D.tscn`（根 `Node3D` + 脚本，其余全代码构建） |
| 装配器 | `TowerDescent3D._install_base_npc()`；**只装 99F 基地**，`is_expedition()` 直接跳过 |
| 父级 | `_facility_art_layout`（即 `Art` 布置层），与 8 个设施同一个父级 ⇒ 房间流送/隐藏时一起走 |
| 位置 | 读布置层锚点 `玩法锚点_只移动不删除/99层基地NPC起点锚点`（局部 `(-10, 0, -2)` ⇒ 世界 `(-10, -12, 3)`）与 `…巡逻终点锚点`（局部 `(-10, 0, 1)` ⇒ 世界 `(-10, -12, 6)`）；**代码不写死坐标**，挪锚点即换位。`Art` 布置层的世界原点在 `(0, -12, 5)`，所以局部 z 与世界 z 差 5m —— 改锚点时按局部值改。 |
| 净空依据 | 起点离最近设施（SUPPLY24H 自动补给机）**6.55m**、终点离最近设施（武器工作台）**5.98m**，均远大于交互半径 1.5m 与 A19 的 2.4m 门槛；两个锚点横向相距 **3.0m**，配 `WALK_SPEED 1.05` 单程约 2.9s + 到点停留 1.6s。 |
| 迎宾锚点（r5） | `玩法锚点_只移动不删除/99层基地NPC迎宾锚点`，局部 `(-3.2, 0, -0.2)` ⇒ 世界 `(-3.2, -12, 4.8)`。选点依据：离归航点 `FACILITY_LOGOUT_SPAWN (0, -11.95, 5)` **3.2m**（落在 `HAIL_RADIUS 4.0` 内 ⇒ 玩家一落回基地就会被招呼），离西侧 MEDICAL/TOOLS 设备墙约 1m 的原空走道上、不挡中央主通道；0.45m 球体物理查询实测重叠 0 件。锚点缺失时装配器 `push_warning` 并退回巡逻起点，**节拍照样会播**（不站定而已）。 |
| 查询 | `TowerDescent3D.get_npc_count()` / `get_npc_snapshots()` / `find_npc(npc_id)` |

⚠️ **不要装到 `scenes/BaseWorld3D.tscn`**。那是「基地与荒野」旧兼容场景（破败公路广场 + 四个路边副本入口），不是 99F 室内基地。
2026-11-02 第一版就装错了地方，主人当场指出「背景是这个，不是我基地里头」——那 8 个 `Facility` 与空地都属兼容场景，正式 99F 基地在 `TowerDescent3D` 的 `facility` 房间。验收 A02 现在会实例化旧场景并断言它**不含** NPC，防止再装回去。

## 11. 验收

| 项 | 内容 |
|---|---|
| 验收入口 | `tests/verification/verify_base_npc_flow.gd` / `.tscn`，注册在 `scripts/run_verification_suite.sh` 的 `core_scenes` |
| 断言组 | A01–A05 真实 99F 基地接入与内容（A02 含「旧 `BaseWorld3D` 不得带 NPC」反向断言）；A06–A14b 模型/衣柜绿/面饰/落地/**体型与玩家同口径**/头顶只剩提示与气泡/无自发光；A15–A18 巡逻与朝向；A19 设施净空；A20–A25b 交互半径与提示时机/白点退役/搭话定住与转向/对话环回与收起/恢复巡逻；A26 塔楼只读投影 |
| 场景口径 | 加载 `scenes/TowerDescent3D.tscn`（正式 99F）。**不是** `BaseWorld3D.tscn` |
| 渲染对照 | `docs/v0.1/audits/evidence/2026-11-02_base99_npc/`：`base99_npc_noon.png`（12:00）、`base99_npc_night.png`（22:00）、`base99_npc_closeup.png`（正面近景，看面饰与哑光绿）、`base99_npc_prompt.png`（站进 1.5m 内的黄色 `[E] 交谈`，确认无白点、无名字牌）、`base99_npc_talk.png`（**说话帧**：气泡抬高后的实际间隙 + 半透明底板 + 无白色「(e) 交谈」）。都是真实渲染器拍的，不是无头。三个脚本：`capture_base99_npc.gd`（正午/夜间/近景）、`capture_base99_npc_prompt.gd`（提示）、`capture_base99_npc_talk.gd`（说话帧 + 打印圆点快照是否为空）。⚠️ 三个脚本都**不要**套 `timeout` —— 本机 Git Bash 的 `timeout` 会吞掉 `NPC_SHOT_*` 环境变量，脚本会退回默认路径/时间。⚠️ 并且要用 `APPDATA=<临时目录>` 隔离用户数据目录：正式存档里另一个进程正在写 `BaseManager` revision，抢写会 `Refusing stale save` 并把截图进程卡住。 |
| 已知未覆盖 | NPC 与玩家/NPC 之间的避让；多 NPC 并发；面饰表情不进表情系统（固定 `mask_idle`） |

### 11.1 一次性剧情节拍（r5）

| 项 | 内容 |
|---|---|
| 验收入口 | `tests/verification/verify_base_npc_story_beat.gd` / `.tscn`，注册在 `scripts/run_verification_suite.sh` 的 `core_scenes`（紧随 `verify_base_npc_flow`） |
| 断言组 | S01 内容契约（全文逐字 == 用户口径、首句、单句 ≤ 24 字以免排到三行）；S02 台词里指路的设施 ID 已登记；S03 未遭遇时**没有**待播节拍、NPC 不站定；S04 **预约不算遇到**、首次生成确认后才成立；S05 回 99F 后站在迎宾锚点上、`moving=false`、待播 ID 正确、1s 内不漂移；S06 玩家走进 4m 自动开口、第一句逐字一致、面向玩家（yaw 误差 < 0.20rad）；S07 第一句放完**自动**接第二句（不要玩家按 E）；S08 整段说完才落盘（`npc_beat:` 命名空间、`has_narrative_completed` 为真）；S09 播完恢复巡逻、不再挂待播；S10 重进基地**不再重复**；S12 台词指向的二楼档案终端真实存在（离地 ≥ 3m，即真在二楼）且档案里能查到收租人 |
| 渲染对照 | `docs/v0.1/audits/evidence/2026-11-04_base_npc_greeting/`：`base99_npc_greeting_standby.png`（合成机位：NPC 站在归航点**边上**、还没开口）、`base99_npc_greeting_talk.png`（玩家自带相机：站在归航点被迎面提醒的那一帧，看气泡是否被画面上缘裁切）。脚本 `capture_base99_npc_greeting.gd`，`NPC_SHOT_GAME=1` 切玩家相机，其余同 §11 的三条注意事项（不要套 `timeout`、要隔离 `APPDATA`、必须真渲染器） |
| 已知未覆盖 | 中途玩家走出去打断 → 下次重播（设计如此，未单独断言）；多节拍排队；真实存档跨进程读档（验收用内存态与一次落盘断言代替） |

## 12. 当前实现事实与未完成项

- 已实装：内容目录、实体、体型与玩家同口径、衣柜绿皮肤（**无自发光**）、巡逻、搭话定住并转向、步态/待机、统一交互、黄色 `[E] 交谈` 提示（白点退役、名字牌撤除）、气泡对话环回、塔楼只读投影、独立验收入口、面饰补挂、真实渲染四张对照图。
- **r5 已实装**：一次性剧情节拍（§13）—— 首遇收租人后回 99F，绿苔站到迎宾锚点、玩家进 4m 自动逐句说明、说完回巡逻、跨局只播一次；台词与"指哪个终端"都在内容目录，落盘复用 `narrative_history`。
- 未实现（明确保留）：导航寻路与避障、对话选项/分支、任务与商店挂钩、多 NPC 管理、贴地采样、面饰表情接入表情系统、**节拍专用的任务面板/日志**（当前只是一句话提醒，不是任务系统）。
- 与 `ThemedNPC3D` 的关系：**并存**，不互相替代。正式基地只用 `NpcCharacter3D`。
- 资产账本：**没有新增美术源文件**（复用玩家 bunny01 几何 + 运行时材质覆盖），但登记了一行可独立加载的 PackedScene：
  `CHR-PLY-BUNNY01-NPC-GREEN`（子类 `player_variant`，制作状态「原型已接入」，路径 `scenes/BaseNpc3D.tscn`，SHA 取该场景）。
  理由：它能在账本里被查到、被追责；不登记的话下次有人改 NPC 外观时账本里没有任何一行告诉他这东西存在。
  变更日志 `v0.1.27`，基线已补录（`scripts/register_base_npc_ledger.py`）。
  同批给角色账本 `CHR-PLY-CAPSULE01-3D-BUNNY01` 行的「状态/动画」与备注补了 `suit_green` 记号，日志 `v0.1.28`。

## 13. 一次性剧情节拍（r5）

### 13.1 目标

<span style="color:#1565C0">**[用户设计 2026-11-04]**</span> 「当我第一次遇到精英怪后，我再次回到 99F 基地，我 99F 基地的绿色 NPC，**会站在边上**，说：『你遇到收租人啦？有没有被夺走东西呀？你可以去二楼的档案室里看看它的信息哦。』」

拆成四条可验收的规则：

| # | 规则 |
|---|---|
| R1 | **条件**：玩家**真正遇见过**收租人（首次生成且确认遭遇），不是"这局抽到了" |
| R2 | **站位**：回到 99F 时 NPC 站在**归航点边上**等，不在巡逻线上自己走 |
| R3 | **开口**：玩家走近就**自动**说，不需要按 E；说完两句（用户原话是一整句，拆成两个气泡，见 13.6）后回巡逻线 |
| R4 | **一次性**：跨存档只播一次；重进基地、重开游戏都不重复 |

这是"提醒"，不是"任务"：没有接取、没有奖励、没有任务面板（明确不做的部分见 §12）。

### 13.2 所有权与分工

| 项 | 所有者 | 说明 |
|---|---|---|
| 说什么 / 靠什么事实成立 / 指哪个终端 | `NpcCatalog.STORY_BEATS`（内容） | 台词、`requires_elite_encountered`、`archive_facility_id` 全在这里；代码里**没有**台词字面量 |
| 该不该说 / 说过没有 | `NpcStoryBeatService`（判定+落盘） | 只读别人的事实（`EliteRosterService` 的遭遇计数、`BaseManager` 的跨局历史），自己不留第二份状态 |
| 站在哪 / 何时开口 / 说完怎么回巡逻 | `NpcCharacter3D`（表现） | 只消费服务的结论；不判断游戏事实、不写存档 |
| 迎宾锚点（世界坐标） | `zone_base.tscn` 的作者锚点 → `TowerDescent3D` 传给 NPC | 代码不写死坐标 |
| 回基地时重新求值 | `TowerDescent3D._on_room_entered()` 的 `facility` 分支 | 同一次塔楼运行里"出去打完再回来"不会重建 NPC，只在 `_ready` 判一次会漏 |

**为什么判定要单独成服务**：`NpcCharacter3D` 是场景节点，把"读精英档案 + 读跨局历史 + 决定说不说"塞进去，等于在表现层里长出一份玩法判定，验收时无法单独跑，也没法给第二个 NPC 复用。与 `EliteRosterService` 同规格：内容在目录、事实在服务、实体只消费。

### 13.3 内容契约（`NpcCatalog.STORY_BEATS`）

`npc_id → beat_id → 节拍定义`。当前只有一条：

| 字段 | 值 |
|---|---|
| npc_id | `npc_base99_green` |
| beat_id | `elite_arms_taker_first_seen` |
| `requires_elite_encountered` | `elite_arms_taker`（夺械者"收租人"） |
| `archive_facility_id` | `monster_archive`（99F 二楼 42 号双屏电脑终端） |
| `lines` | ① `你遇到收租人啦？有没有被夺走东西呀？` ② `你可以去二楼的档案室里看看它的信息哦。` |

- `archive_facility_id` 不是装饰字段：验收 S12 用它去基地里找那个设施，断言"**NPC 让你去看的那个终端真的存在、真的在二楼**"。不登记它，这句话就是一句无法核对的空话。
- `lines` 每句上限按 24 字管（S01 断言）。理由见 13.6。
- 加新节拍 = 在 `STORY_BEATS` 里加一条 + 在 `NpcStoryBeatService._requirements_met()` 里加对应事实分支 + 补验收。不需要动实体。

### 13.4 判定

- **"遇到"的口径**：`EliteRosterService.get_record(elite_id).encounter_count > 0`。
  - 不是 `reserved_encounter_id` 非空 —— 预约发生在**这局抽到它**的时候，人还没见到；拿它判会让刚出发的玩家就收到"你遇到收租人啦"。
  - 不是 `last_encounter_at_unix > 0` —— 残留旧记录可能只剩时间戳。
  - 兜底：老档只有 `escape_count`/`death_count` 而没有 `encounter_count` 时也算遇到过（历史数据不完整，但不该让这句话永远不出现）。
- **求值顺序**：多条节拍按目录书写顺序，先满足条件的先播；一条播完后下次上线才轮到下一条，**不连播**（玩家站在基地里被连续说三段很怪）。
- **重新求值**：`_ready()` 一次、`TowerDescent3D` 每次进入 `facility` 房间一次、`configure()` 一次。

### 13.5 落盘（复用 `narrative_history`，不新增存档字段）

- 键：`npc_beat:<npc_id>:<beat_id>`，写在 `BaseData.narrative_history` 里，走 `BaseManager.commit_narrative_completion(key, "duration")`。
- **为什么不新开字段**：新增 `BaseData` 字段就是存档 schema 变更，收益只是一句迎宾提醒；`narrative_history` 本来就是"跨局剧情事实"的唯一容器（09 号存档文档登记、`once = "run"` 剧本在用）。代价是这张表里会混进非剧本键，因此**键前缀是硬约定**（`NpcStoryBeatService.HISTORY_KEY_PREFIX`），验收 S08 专门断言前缀，文档也在 09 号页登记了这个命名空间。
- **什么时候算"说过"**：整段**播完**（第二句气泡放完）才落盘。半路被玩家走出去或按 E 聊天打断，不算说完 —— 下次进基地会重播一遍。理由：用户要的是"被提醒到"，不是"播放器执行过"。
- **写盘失败**：`mark_beat_played()` 返回 false 并 `push_warning`，但进程内的 `_session_played` 内存表**仍然压住本局重播**；下次启动可能再提醒一次。与 08 号文档对 `once` 剧本的处置同一量级，不静默吞失败。

### 13.6 站位、开口与气泡

| 项 | 值 | 依据 |
|---|---|---|
| 迎宾锚点 | 局部 `(-3.2, 0, -0.2)` ⇒ 世界 `(-3.2, -12, 4.8)` | 离归航点 3.2m、在走道一侧、不挡主通道；0.45m 球体物理查询重叠 0 |
| 停巡 | `_story_standby` 为真时 `_tick_patrol` 直接 return | 站在边上等人，不该自己走开 |
| 朝向 | 持续对准玩家（与搭话同一套 `TALK_TURN_SPEED`） | 玩家绕着走它跟着转 |
| 招呼半径 | `HAIL_RADIUS = 4.0m` | **必须大于交互半径 1.5m**：迎宾是"迎上来"，不该要求贴脸。4m ≈ 3.3 个角色身高，玩家从归航点走两步就进圈，也不会隔空喊话 |
| 找玩家的口径 | 优先交互热区里的 `_player`，否则按 `player_3d` 组取 | `_player` 由 1.5m 热区写入，只在里面才非空 —— 只看它就会退化成"必须贴脸" |
| 气泡 | 复用 `CharacterBark3D` + `SpeechBubble3D`，挂高 **3.40m**、`pixel_size 0.0084`、`wrap_width_px 560` | 与循环台词同一套观感，不另开一套 UI |
| 逐句轮播 | 每句一个气泡，上一句自然放完（6s）自动接下一句 | 见下 |

**为什么不把用户那句话当成一个气泡一次说完**：整句 40 字在 `wrap_width_px 560`（≈11 汉字/行）下排 **4 行**，气泡世界高 1.81m，挂高 3.40m 时顶边顶到画面上缘被裁掉（2026-11-04 真实渲染实测，`base99_npc_greeting_talk.png` 第一版就是那样）。挂高 3.40m 是业主三轮调出来的"两行口径"（§5.1），**不该为了一句台词再抬一次**（再抬就会离开视线中心）。所以内容按两句存、每句两行、连续播放；台词文本与用户原话逐字一致（S01 比对拼接全文）。

**为什么不让玩家连按 E**：连按会把"提醒"变成"手续"。轮播是自动的，玩家站着就能读完两句。

### 13.7 失败收口

| 情形 | 行为 |
|---|---|
| `NpcStoryBeatService` 找不到 `EliteRosterService` / `BaseManager` | 视为"没遇到过 / 没播过"，不崩；`mark_beat_played` 返回 false 并警告 |
| 迎宾锚点缺失 | `TowerDescent3D` `push_warning`，退回巡逻起点；节拍照播（不站定） |
| 节拍 `lines` 为空 | `push_warning`，跳过该节拍并退出站定，不阻塞巡逻 |
| 写盘失败 | 本局内存表压住重播；下次启动可能重复一次，留 warning |
| 玩家走出 4m 前就离开基地 | 没有开口 ⇒ 没有落盘 ⇒ 下次回来还说 |
| 玩家在半路按 E 聊天 | 节拍暂停在站定状态；聊完气泡放完继续；整段结束才落盘 |
| 同一次运行内再次进入 facility | `refresh_story_state()` **不会**清掉进行中的节拍（`_pending_beat` 非空且站定/已开口时直接 return）—— 否则气泡还挂着、人却走回巡逻线 |

### 13.8 新增一条节拍要做什么

1. `NpcCatalog.STORY_BEATS` 加条目（台词、`requires_*`、`archive_facility_id`）。
2. `NpcStoryBeatService._requirements_met()` 加对应事实分支（新增 `requires_*` 字段）。
3. 若需要专属站位，加一个作者锚点并让 `TowerDescent3D` 传入（多条节拍共用同一个迎宾锚点时不用改）。
4. 验收里加断言：内容逐字、条件成立/不成立两侧、站定、开口、落盘、一次性、设施指向。

## 14. 战败归航救援（r6，2026-11-08）

玩法口径（触发条件、台词全集、箱子规则、不做的部分）见[设计页](design/战败归航救援与绿苔台词.md)。本节只写工程契约。

### 14.1 所有权

| 项 | 所有者 | 说明 |
|---|---|---|
| 抽哪几件 / 补哪种补给 / 随机多少件 | `Dungeon3D._plan_rescue_items()` | 在**死亡结算之前**抽（结算会把未保险物资按比例清掉） |
| 暂存与连败计数 | `BaseData.rescue_cache` / `rescue_defeat_streak`，由 `BaseManager.commit_run_settlement()` **随同一次事务**写盘 | 塔楼死亡请求里不带 `rescue_items`，不动这两份数据 |
| 台词 | `NpcCatalog.RESCUE_SCRIPTS`（候选段池，**整段随机**）/ `RESCUE_STREAK_SCRIPTS`（连败专属段） | 代码里没有台词字面量；**没有固定开场白**，见 §14.8 |
| 趴下 / 起身 | `PlayerAvatar3D.set_narrative_pose()`（`dead` 剪辑，相位 1.0 ⇄ 0.0） | 演出方只推相位，不自己摆骨骼 |
| 站位 / 停巡 / 转头 / 逐句气泡 | `NpcCharacter3D.begin_scripted_appearance()` / `say_scripted_line()` / `end_scripted_appearance()` | 新增的三个演出入口，**不进节拍历史、不写盘** |
| 演出时序 / 箱子生命周期 | `src/base3d/Base99Rescue3D.gd`（`BASE-RESCUE`） | 装配点 `TowerDescent3D._install_base_rescue()` |
| 开箱链 | `Dungeon3D._on_chest_open_requested()` | 与普通宝箱同一套：认领 → 冻结 → 砰 → 落地 → 房间账 |
| 输入独占 | `Dungeon3D.set_scripted_input_hold()` | 并入 `_narrative_holds_player_input()`，否则会被逐帧锁同步顶掉；同时置 `Player3D.aim_locked` 停掉鼠标朝向，见 §14.9 |

`Base99Rescue3D` **不写台词、不抽奖励、不碰存档字段**：它只按时间和阶段驱动上面四家。

### 14.2 阶段

`Base99Rescue3D.Phase`：`idle → cutscene → chest_waiting → chest_opened → vanished`
（另有 `skipped`：装配不到位 / 清单转不成奖励）。

- `idle`：没有暂存，什么都不做（99F 每次进基地都会装配一次）。
- `cutscene`：钉住玩家、锁输入、绿苔站定、逐句说完、起身。**起身之后才发 `cutscene_finished`**。
- `chest_waiting`：玩家已可操作，箱子待开。
- `chest_opened`：`TreasureChest3D.opened`（= `commit_opened()`）那一刻清暂存、起 10 秒计时。
- `vanished`：播 `VFX-TELEPORT-OUT-3D` 后同帧 `despawn()`（视觉 + 碰撞 + 交互一起收），1.2s 后释放节点。

### 14.3 站位（相对归航点，不加作者锚点）

| 项 | 偏移 | 依据 |
|---|---|---|
| 绿苔 | `(-1.55, 0, -0.55)` | 归航点侧后方 1.6m，在原有空走道上，玩家趴着抬眼就能看到 |
| 宝箱 | `(-2.45, 0, 0.15)` | 离绿苔约 1.0m（验收 ≤ 1.4m），离归航点 2.5m |

归航点取 `TowerDescent3D.get_facility_spawn_point()`（= `FACILITY_LOGOUT_SPAWN`）。
不新加锚点的理由：这两个点语义上就是「玩家在哪醒来，绿苔就站哪边」，归航点一改它们自动跟随；加锚点会多两个几乎重合的点，还要改场景账本 SHA。

### 14.4 演出参数

| 项 | 值 | 理由 |
|---|---|---|
| 趴下姿势 | `dead` 剪辑相位 1.0（冻结） | 与开场剧本 `nar_tower_opening_01_wake` 同一口径 |
| 起身 | 相位 1.0 → 0.0，1.1s | 开场用 1.5s（慢慢爬起来），这里是"跳起来" |
| 每句停留 | 3.2s | 够读完 26 字，两句 6.4s |
| 台词来源 | `Base99Rescue3D.plan_script_lines(streak)` → `NpcCatalog.get_rescue_script()` | 演出与验收共用同一份实现，验收才抓得住"演出写死某段" |
| 逐字显示 | `SpeechBubble3D` 打字机（默认 30 字/秒，与底栏同速） | 业主 2026-11-08：对话文字要打字机一样顺序出现；口径见 [18 §11.6](18_技术施工_UI与对话系统.md) |
| 每句等待 | `_wait_until_line_done()`：等气泡自己收起（打字 + 停留），上限 `3.2 + 4.0s` | 死等固定秒数会在长句打完之前就把下一句顶上来 |
| 气泡换行 | 演出期间放宽到 **700px**，结束后复位 560 | 26 字在 560px 下排三行会顶出画面上缘；抬高挂点会离开视线中心，改字号会与其他台词不一致 |
| 消失延迟 | 10.0s | 业主口径 |
| 消失特效 | `VFX-TELEPORT-OUT-3D`，尺寸 1.6 | 收租人撤退同一件；1.6 略大于箱体，环把箱子包住 |

### 14.5 救援暂存的数据形状

```text
BaseData.rescue_cache: [
  { kind: "item", item_id: "<item.id>", item: {...}, count: n, rescue_source: "run" | "supply" }
]
```

- `item_id` 必须与 `item.id` 同值：`RewardSink.materialize_ground_items()` 用它做一致性校验，缺一个整批退回（表现为"箱子开了、地上什么都没有"）。
- 开箱前由 `Dungeon3D.build_rescue_chest_grants()` 翻成 grant（`sink: ground`）交给箱子；箱子的 `explicit_grants` 非空时 `_resolve_chest_grants()` **跳过池子解析、也不套命运品质加成**（"捡回来的还是原来那把枪"）。

### 14.6 连败计数

`commit_run_settlement()` 内：`success` ⇒ 归零；`failure` 且请求带 `rescue_items` ⇒ +1；其余（塔楼死亡）⇒ 不变。
与暂存在同一事务内提交，写盘失败一起回滚 —— 台词说的"这是第几次"必须与箱子里装的东西是同一次死亡。

### 14.7 失败收口

| 情形 | 行为 |
|---|---|
| 基地房 / 玩家 / NPC 缺失 | 不演，`skipped`；不 push_error（远征与工具场景本来就没有 99F 基地） |
| 清单转不成 grant | `push_warning` + `skipped`，暂存保留（下次归航再给） |
| 演出被打断（切场景） | `_exit_tree()` 归还输入独占并复位气泡换行 |
| 暂存清空写盘失败 | 内存已清、磁盘仍旧 ⇒ 重启可能重复给一箱，留 warning |
| 箱子生成失败 | `push_error`，暂存保留 |

### 14.8 台词：整段随机，没有固定开场

业主 2026-11-08 二次澄清：「对话并不是一定要出现『啧啧，太危险了……』这句，这句也是随机出现的选择，
不是固定的两句」。

| 档位 | 取法 |
|---|---|
| 连败 2 次 / 3 次 | 只播 `RESCUE_STREAK_SCRIPTS` 对应专属段 |
| 其余（1 次 / ≥ 4 次） | 从 `RESCUE_SCRIPTS` 四段候选里**随机挑一整段** |

- 候选四段：①「啧啧…捞回来了 / 感谢我吧…捞回了点东西」（2 句）②「别泄气…」③「世上无难事…」④「这次还不错…」。
- 掷骰只在 `NpcCatalog.get_rescue_script()` 里发生；演出方与实体都不掷，验收可用 `pick_index` 定值。
- `Base99Rescue3D.plan_script_lines()` 是演出真正调用的入口，**验收也走它** ——
  直接撩 `NpcCatalog` 的断言测不到"演出是不是随机抽的"。

### 14.9 演出期间的操作锁（2026-11-08 r3）

业主：「这个时候需要玩家无法操作，鼠标旋转也不行，这个就是剧情过程」。

| 维度 | 机制 | 为什么不能省 |
|---|---|---|
| 移动/开火/交互 | `input_locked`（既有） | —— |
| 残余速度与物理推移 | `Base99Rescue3D._enforce_hold()` 每帧钉水平位置、清水平速度 | 锁只拦输入，进锁前的速度仍会把人推走几十厘米 |
| 锁掉线 | `set_scripted_input_hold(true, force)` 每帧兜底重锁 | `set_input_locked()` 在 `hp<=0` 时**静默不生效**，而血量回填发生在锁之后 |
| 鼠标朝向 | `Player3D.set_aim_locked(true)` → `_narrative_holds_aim()` 早退 | `input_locked` 按设计**不拦瞄准**（那是给剧本 `actor.face` 留的口子），不补这条玩家晃鼠标就能把趴着的人转过来 |
| 玩法按键 | `Dungeon3D._unhandled_input` 在演出期间整段返回 | 换枪 / 快捷物品 / M 大地图 / K 展示面板都算"操作" |
| 背包 | `InventoryUI._player_control_fully_locked()`（= `input_locked and aim_locked`） | 只锁移动的流程（主页面/衣柜/工坊）不受影响 |
| ESC / 暂停 | **不挡** | 演出万一卡住，玩家仍能呼出菜单退出 |

起身时两个锁一起放开，验收 R14b 实测按键立刻能动。

### 14.10 验收

`tests/verification/verify_base99_rescue.gd` / `.tscn`，注册在 `core_scenes`（紧随 `verify_base_npc_story_beat` 之后）。
断言组 R01–R14：候选段池与连败段逐字、无暂存不演、抽签规则（含保险格排除与实例去重）、塔楼不抽、
趴下+锁输入+站位+浅灰箱、播出的整段必须是候选段之一且逐句按序进气泡、**演出方随机 60 次四段都要出现**、
连败 2 次真实归航走专属段、起身归还、开箱清空并落地、10 秒消失且播出离场特效、连败计数三条边界、
演出期间完全无法操作（鼠标锁 + 按键 24 帧不位移 + 状态机 locked）与起身后恢复。

反向对照（已实测会红）：演出写死第 0 段 → R08c 4 条；去掉鼠标锁（两处都去）→ R14 3 条；
只去掉 hold 那处、保留逐帧兜底 → R14b 1 条（说明兜底真的在起作用）；不调 `set_narrative_pose` → R06 1 条；
去掉浅灰配色 → R06 2 条。
