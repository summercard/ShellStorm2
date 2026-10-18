# UI 与 UX 全局设计及全界面盘点评估

- 关联 FeatureID：`UI-SYSTEM`、`DIALOGUE-SYSTEM`、`COMBAT-HUD`、`INVENTORY-GRID`、`BASE-FACILITY`、`MAIN-ENTRY`、`WARDROBE-3D`、`FATE-TAROT`
- 关联资产账本：`assets/registry/ledgers/ShellStorm2_UI账本_v001.xlsx`（单一真源，当前登记 18 项 `UI-*` 资产）
- 关联专项设计：[对话与战斗信息呈现](对话与战斗信息呈现设计.md)、[装备与棋盘式包裹](装备与棋盘式包裹设计.md)、[基地经济与存档结算](基地经济与存档结算设计.md)、[武器构建链路文本本地化](武器构建链路文本本地化设计.md)
- **关联风格规范（现行生效）**：[UI风格规范_棱镜线框](UI风格规范_棱镜线框.md)（`PRISM-WIREFRAME`）；素材参考：[逃离鸭科夫UI风格对标参考与关键词库](逃离鸭科夫UI风格对标参考与关键词库.md)（第 6 章已废弃）
- 施工对照：[18_技术施工_UI与对话系统](../18_技术施工_UI与对话系统.md)、[16_技术施工_主页面与角色换装](../16_技术施工_主页面与角色换装.md)、[04_技术施工_战斗与局内成长](../04_技术施工_战斗与局内成长.md)、[07_技术施工_基地设施](../07_技术施工_基地设施.md)

---

## 1. 文档定位与架构铁律

本文档承担两项核心职责：
1. **UI/UX 四维深度评估**：从**表现（Presentation）**、**交互（Interaction & UX）**、**美术风格（Art Style）**、**动态效果（Motion & Dynamic Effects）**四个维度，对《弹壳风暴2》（`ShellStorm2`）当前全部 UI 与 UX 实现进行系统性诊断、亮点提炼与风险/缺口定级。
2. **全量 UI 界面主设计清单（Master Inventory）**：将项目中**每一个 UI 界面**（涵盖独立 `.tscn` 场景、脚本自建全屏模态、战局 HUD 组件、动态内嵌弹窗、3D 世界空间 UI、全局过场与调试工具）共 **48 个界面/组件单元**逐一建档，确立层级（`CanvasLayer` / `z_index`）、入口、尺寸锚点、核心交互与设计契约。

### 1.1 UI 架构三铁律
1. **只读投影与职责分离**：UI 层只读消费领域服务（`Inventory`、`BaseManager`、`GameManager`、`DialogueManager`、`HUDPresenter3D`），通过信号或意图命令回调驱动业务，**禁止在 UI 脚本内私自结算货币、修改掉落池或直接写盘存档**。
2. **3D 同源与程序化优先**：除命运塔罗牌面（`UI-ATLAS-FATE-CARD`）与开场视频（`opening_intro.ogv`）外，全游戏 UI 采用**纯代码 StyleBox + `_draw()` 矢量绘制 + 实时 3D `SubViewport` 模型投影（`ItemModelIcon3D`）**，杜绝 2D 物品贴图与 3D 实物模型货不对板。
3. **跨输入设备与模态锁闭环**：任何阻断型 UI 必须接入统一输入锁（`_sync_player_input_lock()`）与 `UiMenuFocus` 手柄安全焦点仲裁；`ESC` / 手柄 `B` 键严格遵循“取消拖拽 → 关闭最上层子弹窗 → 关闭当前主面板 → 唤起暂停菜单”的单向栈序。

---

## 2. UI/UX 四维全面评估（表现 · 交互 · 美术风格 · 动态效果）

| 评估维度 | 综合评级 | 核心优势（已落地亮点） | 核心短板与体验风险（待收敛项） |
|---|---|---|---|
| **2.1 表现（Presentation）** | **A-** | 3D 实物同源渲染（永不切边）、实景无背板 HUD、1920×1080 等比缩放自适应 | 字体单一、部分内嵌代码弹窗未走统一组件库、基地部分旧设施面板信息密度失衡 |
| **2.2 交互（Interaction & UX）** | **A** | 棋盘拖拽+旋转预检极顺滑、手柄安全焦点防误触、ESC 模态栈严密、键鼠/手柄/触屏三端兼容 | 跨容器一键转移快捷键（Shift/Ctrl+左键）缺失、多语言仅覆盖武器链路、部分弹窗缺手柄聚焦 |
| **2.3 美术风格（Art Style）** | **B+** | “冷峻霓虹战术”与“鸭科夫柔和深蓝仓储”双轨明确、纯代码矢量图标精度高 | **视觉存在“三代同堂”割裂感**（战术切角 vs 鸭科夫圆角 vs 早期原生 StyleBox 弹窗） |
| **2.4 动态效果（Motion & FX）** | **A-** | 塔罗牌 Shader 扫光+错相漂浮+翻牌、光圈噪声过场、双层延迟追赶血条、高帧率程序化剪影 | 部分基地二级菜单（保险库/占卜/恢复）开闭为硬切（无淡入/缩放过渡），缺少列表交错入场动效 |

---

### 2.1 表现维度评估（Presentation）

#### 核心亮点
1. **3D 模型同源实时图标（`ItemModelIcon3D`）—— 行业级工程解法**
   - 摒弃传统手工烘焙 PNG 图标管线，背包、商店、工坊、地面掉落预览全部使用独立 `SubViewport`（`own_world_3d = true`）+ 正交相机实时渲染真实 3D 资产。
   - 通过遍历 `MeshInstance3D` 真实顶点计算相机正交平面支撑区间（Support Interval），配合 `FIT_FILL_RATIO = 0.88` 与视口长宽比动态适配，**在数学上证明了无论枪械多细长、配件多微小，在 1×1、2×1、4×2 任意格子里永远居中、占满 88% 留白且绝不切边**。
   - 静态图标采用 `UPDATE_ONCE`（仅脏标记或尺寸变化时渲染 1 帧），旋转预览采用 `UPDATE_WHEN_VISIBLE`，兼顾高保真表现与极低 GPU 开销。
2. **极简“去背板化”实景 HUD（Bare HUD）**
   - 战局与基地 HUD 经历了多轮视觉减法（`_make_bare_hud_panel()`）：移除了早期厚重的深色半透明底板与四角霓虹括号，文字通过 `outline_size = 5` 的高对比黑色描边直接悬浮于 3D 实景画面之上，极大释放了 12m 挑高室内场景与室外云海的视野通透感。
3. **1920×1080 基准等比缩放架构**
   - `Dungeon3D` 与 `InventoryUI` 实现了基于视口尺寸的 `_hud_scale()`（`clampf(min(w/1920, h/1080), 0.72, 1.35)`），所有字号、边距、槽位尺寸均经过 `_hud_px()` / `_hud_int()` 换算，保证在 720p、1080p、2K/4K 及带鱼屏下布局不崩坏、热区不重叠。

#### 现存短板与优化建议
1. **字体层级与排版韵律单一**：目前全局依赖 Godot 默认回退字体，缺乏专属的数字等宽字体（Tabular Nums，用于倒计时、金币、弹药数跳动防抖）与具有废土机械感的标题字体。
2. **UI 资产账本登记存在漏项**：`ShellStorm2_UI账本_v001.xlsx` 目前登记了 18 项核心资产，但近期新增的 `BaseVendingMenu`（自动售货机）、`WardrobeMenu3D`（角色衣柜）、`OpeningMovieScreen3D`（开场影片层）、`ExpeditionLoadingScreen`（远征剪影加载页）、`FateSourceSelectionPanel`（命运来源选择）及 `Dungeon3D` 内嵌的 8 个模态弹窗尚未补录进 UI 账本。

---

### 2.2 交互与 UX 维度评估（Interaction & UX）

#### 核心亮点
1. **高完成度的棋盘式空间包裹交互（`InventoryUI` + `GridInventoryBoard`）**
   - **视觉预检闭环**：拖拽物品悬停在 8×N 网格、保险柜（8×2）、快捷栏（4槽）或武器/配件槽时，实时计算碰撞与可装备性，绘制绿框（可放入/可装配）或红框（占格冲突/不可装入），并支持拖拽中按 `R` 键实时旋转物品朝向（横置/纵置）且同步重算阴影锚点。
   - **直觉化丢弃与拆分**：画面中央留出角色 3D 预览通透区，将物品拖入中央留白区域松手即可直接丢弃到当前 3D 房间地面；选中可堆叠物资后通过底部滑块（`HSlider`）精确拆分数量。
2. **手柄安全焦点仲裁（`UiMenuFocus`）**
   - 针对覆盖式菜单（选关、工坊、图鉴、售货机等），`UiMenuFocus.grab_default()` 会递归搜寻可用按钮，并**强制优先聚焦 `CloseButton` / `SkipButton` / `CancelButton`**，避免玩家在用手柄跑图交互时连按 `A` 键在菜单弹出的第一帧误触“购买”、“合成”或“传送出发”。
3. **严密的模态互斥与 ESC 栈序**
   - `PauseMenu3D.try_consume_pause_input()` 与 `Dungeon3D._unhandled_input()` 建立了清晰的消费优先级：
     `棋盘拖拽中按 ESC（取消拖拽还原物品）` > `命运来源三选一弹窗` > `门后塔罗购卡层` > `M键全屏大地图` > `电梯选层/98F撤退确认/隔离间警告/远征退出警告` > `工作台/局内商人/武器K键页/衣柜/基地设施菜单` > `I键背包` > `ESC 暂停主菜单`。
4. **“幽灵穿透”防挡设计**
   - 3D 实景聊天气泡（`SpeechBubble3D`）显式设置 `mouse_filter = IGNORE`，绝不拦截玩家的鼠标瞄准射线与地面物品点击；屏幕外怪物箭头（`OffscreenEnemyIndicator3D`）严格遵循“未激活不报、隔层（|Δy|>4.5m）不报、伏击隐藏不报”的公平性原则。

#### 现存短板与优化建议
1. **缺少键鼠高频快捷操作（QoL 缺口）**：
   - 在 `InventoryUI`（背包 ↔ 保险柜）、`VaultMenu`（背包 ↔ 基地仓库）、`BaseVendingMenu`（售货机 ↔ 背包）中，目前主要依赖拖拽或点击底部按钮，**缺少 `Shift + 左键`（一键在背包与容器/保险柜间快速转移）与 `右键快捷上下文菜单`（装备/使用/拆分/丢弃）**。
2. **部分内嵌弹窗缺失手柄默认聚焦**：
   - `TowerDescent3D._open_elevator_panel()`（电梯选层面板）和 `_show_expedition_exit_warning()`（远征退出确认框）在动态生成按钮后未调用 `grab_focus()` 或 `UiMenuFocus.bind()`，纯手柄玩家打开电梯面板后无法直接用十字键选层。
3. **本地化覆盖率不均衡**：
   - `GameText` 本地化字典目前已完整覆盖 `WeaponAssemblyTreePanel`、`WorkbenchPanel`、`WorkshopMenu`，但 `InventoryUI`、`PauseMenu3D`、`Dungeon3D` 状态提示及基地大部分菜单仍为硬编码中文字符串。

---

### 2.3 美术风格维度评估（Art Style）

#### 视觉体系现状：三轨并行 + 局部遗留
当前项目在代码层面形成了三套明确的视觉语言，以及少量早期过渡样式：

1. **第一轨：废土霓虹战术风（Tactical Neon）—— 主页面、选关、战斗交互、枪械与命运卡**
   - **色彩规范（`UIPalette`）**：5 级深蓝黑底色（`BG_VOID #020509` → `BG_HIGHLIGHT #182C3E`），搭配高饱和度语义霓虹色：主色调霓虹青（`NEON_CYAN #2EE6F5`）、灵魂金（`SOUL_GOLD #FFC738`）、危险红（`DANGER_RED #FF3847`）、命运紫（`FATE_PURPLE #B85CFF`）。
   - **几何特征**：`NeonFrameControl` 提供的 45° 斜切角外框、四角加粗 L 型战术托架、顶部渐变高光带与横向扫描底纹；`EntryNeonButton` 的六角切角流光边框；`CodeHUDGlyph` 纯代码绘制的 9 种双层辉光矢量图标（心电脉冲、弹药、无线电、撤离信标、骷髅、准星等）。
2. **第二轨：柔和深蓝仓储风（Soft Navy Surface）—— ~~背包、装备、仓库与售货机~~ → 2026-10-17 已并入第三轨**
   - **历史色彩规范**：2026-10-15 确立的仓储专用色板：`INVENTORY_PANEL (#212E42, 94% Alpha)`、`INVENTORY_SURFACE (#182233)`、`INVENTORY_SLOT (#131C2B)`、`INVENTORY_OUTLINE (灰白细描边)`、`INVENTORY_ACTION (#388CE8 浅蓝按钮)`、`INVENTORY_SELECTED (#FA9E32 暖橙选中态)`。
   - **历史几何特征**：圆角矩形（`corner_radius = 8~10px`）、柔和阴影、高可读性浅色描边，通过 `set_meta("ui_style_exempt", true)` 显式豁免 `UIStyleFactory.apply_tactical_tree()` 的霓虹切角覆盖。
   - **⚠️ 边界（仍然有效）**：这条轨道承载**带格子尺寸与空间逻辑**的界面（棋盘包裹 / 装备 / 仓库 / 售货机），**功能逻辑不得改变**。
   - **现状（2026-10-17）**：这一轨的**外观层已全部并入第三轨棱镜线框** —— 但走的是"窄口径"路径（规范 §5.10 C）：
     `make_slot_style` / `make_slot_filled_style` / `make_inventory_surface` 三个格子工厂重定向到棱镜（**与旧版一样不设 `content_margin`**），
     再对已建控件补 `prism_reskin_styleboxes`（只换 `panel` 条目、原样继承 `content_margin`）+ `prism_normalize_label_colors`（只改字色与字体）。
     结论：**格子尺寸、行列数、落位一像素未动**，拖拽预检 / 占格判定 / 装备拆分丢弃逻辑一行未改。
     `ui_style_exempt` meta 保留（它挡住的是**旧战术树皮**，不是棱镜窄口径工具 —— 见规范 §5.10 C 的警告框）。
3. **第三轨（2026-10-16 冻结 · 2026-10-17 全站推广）：棱镜线框（`PRISM-WIREFRAME`）—— 全站统一**
   - **规范文档**：[UI风格规范_棱镜线框](UI风格规范_棱镜线框.md)
   - **色彩规范（`UIPalette.PRISM_*`）**：冷蓝压暗 `PRISM_DIM`；极淡底衬 `PRISM_SURFACE`（alpha `0.42`）/ `PRISM_SURFACE_SOLID`；三级白线 `PRISM_LINE / _SOFT / _FAINT`；近白正文 `PRISM_TEXT` + 钢蓝弱标签 `PRISM_LABEL`；语义色 `PRISM_ACCENT`（天蓝）/ `PRISM_EPIC`（史诗紫，**稀有度专用**）/ `PRISM_DANGER`（平红）/ `PRISM_WARN`（琥珀）/ `PRISM_OK`（青绿，仅瞬时态）；`PRISM_HP_RED / _HP_BG`；`PRISM_KEYCAP_BG / _TEXT`；`PRISM_PRIMARY_BG / _HOVER / _PRESS`。
   - **几何特征**：**不画实心卡片** —— 用 `1px` 白线 + **四角括号选框**（L 形折角、边线中段断开）+ 极淡底衬界定区域；**全方角（radius 0~2）、零辉光、零渐变、零投影堆叠**；贯穿细线承担"列表"结构；白方键帽承担快捷键提示；方角勾选框（选中=实心白块+深墨对勾）与细白线滑条（白方把手）。
   - **排印特征**：`ThemeDB.fallback_font` + `FontVariation.spacing_glyph` 宽字距（**零外部字体依赖**）；两级排印 —— 钢蓝小号弱标签（大写 + 宽字距）+ 近白大字号强数值。
   - **动效特征**：`UIFX.pop_in_modal` 刻意**去掉回弹**（`0.14s / TRANS_CUBIC`），因为线框语言是"切"出来的硬边几何；`UIFX.prism_stagger_in` 行错峰入场仅 tween `scale` + `alpha`（不碰 `position`，放进任何 `Container` 都安全），并支持 `accessibility/reduce_motion` 降级。
   - **推广器械（第二批新增，规范 §5.10）**：旧名工厂重定向（`make_panel_bg` / `make_panel_with_border` / `make_button_style` / `make_progress_*` / `make_tactical_panel` / `make_outline_label` 全部产出棱镜外观，**签名与返回结构不变**）；整棵树皮 `apply_prism_tree`；两个窄口径工具 `prism_reskin_styleboxes` / `prism_normalize_label_colors`；色相归一化 `prism_normalize_color`；内容边距继承 `_prism_adopt_content_margins`。
   - **已接管**：**除业主明确划出的 4 项外全站界面**（包裹 / 装备 / 仓库只改样式；远征情报室 3D 全息城不动）。清单见 §4.0。

#### 风格统一性诊断（“三代同堂”问题）
- **已收敛**：上一轮曾短暂存在的"深蓝圆角胶囊风"（`DUCKOV_*` Token、45° 斜纹标题条、`TRANS_BACK` 回弹）已被**整体否决并全部回退**；第二轨"柔和深蓝仓储风"的外观层也已并入棱镜线框（见上文第 2 条）。
- **割裂点已消除（2026-10-17）**：在同一趟 99F 体验流程中，此前会依次看到"深蓝仓储风 → 霓虹青切角战术风 → 早期原生方框"三种语言；现在全部收敛到同一套**白线 + 白字 + 两级排印**。
- **运维要求**：后续新增界面一律按规范 §10.3 的七条标准动作改造；**禁止新增 `apply_tactical_tree` 调用**，也禁止再引入任何圆角卡片 / 辉光 / 投影 / 回弹（规范 §11 反面清单）。

---

### 2.4 动态效果维度评估（Motion & Dynamic Effects）

#### 核心亮点
1. **命运塔罗牌组全链路动效（`DoorFateOverlay3D` + `FateCardView` + `FateCardFeedback`）**
   - **入场翻牌**：三张卡按 `choice_index * 0.06s` 错峰执行横轴 `scale.x: 1.0 → 0.0 → 1.0` 翻牌，中点揭晓卡面并配合正位/逆位旋转。
   - **常驻呼吸与 Shader 扫光**：`FateCardView` 内置自定义 `canvas_item` 扫光 Shader（斜向流光带 + 边缘辉光脉冲），同时外层容器以 `0.85 rad/s` 做错相正弦上下漂浮（振幅 4.5px）与微倾角摆动（`0.012 rad`）。
   - **悬停与购买反馈**：鼠标/手柄聚焦时 `TRANS_BACK` 弹性放大至 `1.07x`；点击购买时触发 `1.095x → 0.96x → 1.0x` 脉冲，并在屏幕上方展开 `FateCardFeedback` 橫幅（双层辉光描边 + 浮动光尘粒子）。
2. **电影感场景转场体系（`IrisTransition` + `ExpeditionLoadingScreen`）**
   - **光圈噪声遮罩**：全屏 Shader 驱动圆形光圈收缩/展开（`0.42s`），边缘带有双频正弦噪声扰动（`edge_wobble`），彻底消除了生硬黑屏切场。
   - **程序化剪影读取页**：远征加载页无需外部序列帧贴图，通过 `_draw()` 实时驱动兔子剪影骨骼奔跑、耳朵随步伐滞后摆动、地面碎石视差掠过与呼吸省略号，视觉风格独特且零资源加载阻塞。
3. **高响应战斗微反馈**
   - **双层延迟血条**：玩家生命条（平滑速率 `2.6/s`）与 Boss 血条（平滑速率 `1.9/s`）均配备橙红色残影延迟追赶层，单次扣血超过 5% 触发 `UIFX.shake()` 水平衰减震动。
   - **濒死氛围压迫**：HP < 30% 时，`LowHealthVignette` 驱动边缘暗红脉冲遮罩，同时血条高频闪烁。
   - **换弹与倒计时环**：角色身侧的 `HudReloadRing`（黄弧顺时针充能 + 完成绿闪）与右上角 `EncounterCountdownRing`（最后 10 秒变红 + 每秒脉冲缩放 `1.08x`）。

#### 现存短板与优化建议
1. **基地二级菜单开闭缺乏过渡动效**：`VaultMenu`、`BaseRecoveryMenu`、`MonsterArchiveMenu`、`DivinationMenu` 等在 `open_menu()` 时直接 `visible = true`，缺乏 `UIFX.fade_in()` + 轻微缩放（`0.96 → 1.0`）的 0.15s 弹出动效，显得较为生硬。
2. **数字跳动缺少滚动插值（Number Ticker）**：当玩家在售货机大额买卖、死亡结算扣除物资或拾取大量金币时，货币读数直接瞬变，若加入 0.25s 的数值滚动插值与颜色闪烁，爽感反馈将显著提升。

---

## 3. 全局 UI 层级架构（CanvasLayer & Z-Index 总表）

为杜绝全屏遮罩互相穿插、弹窗被 HUD 压住或焦点穿透，全项目 UI 严格运行在以下 **9 级 `CanvasLayer` + `Dungeon3D/$HUD` 内部 12 级 `z_index`** 坐标系中：

### 3.1 全局 `CanvasLayer` 栈序（由底向上）

| CanvasLayer (`layer`) | 挂载位置 / 作用域 | 界面 / 节点名称 | 职责说明 |
|---|---|---|---|
| **Layer 1** (默认) | `Dungeon3D/$HUD` | 战局/塔楼/基地主 HUD 容器 | 承载所有常驻战斗 HUD、背包、工作台、局内弹窗（内部通过 `z_index` 细分，见 3.2） |
| **Layer 60** | `TrainingGround3D` | `TrainingFateBenchPanel` | 独立训练场右侧常驻命运卡与武器构建台 |
| **Layer 90** | `Dungeon3D` / 全局后处理 | `PostfxOverlay` | 全屏胶片颗粒（Grain）与暗部紫青偏移 Shader（`mouse_filter = IGNORE`） |
| **Layer 100** | Autoload (`DialogueUI`) | `DialogueUI` | 底栏叙事对话系统（立绘 + 名字牌 + 打字机正文 + 跳过按钮） |
| **Layer 100** | `TowerDescent3D` (99F 基地) | `RogueMapSelectMenu` / `VaultMenu` / `BaseVendingMenu` / `WorkshopMenu` / `BaseRecoveryMenu` / `MonsterArchiveMenu` / `FateCardCollectionMenu` / `DivinationMenu` / `BaseMenu` | 99F 基地交互设施打开的独立 CanvasLayer 模态菜单 |
| **Layer 110** | `TowerDescent3D` | `MainEntryScreen3D` / `OpeningMovieScreen3D` | 游戏主页面覆盖层 / 新档开场 OGV 视频层（二者互斥，压住底层 HUD 与基地菜单） |
| **Layer 120** | `TowerDescent3D` (99F 基地) | `WardrobeMenu3D` | 角色衣柜换装界面（3D 实景镜头推近 + 右侧部位抽屉卡片） |
| **Layer 128** | Autoload (`MobileInput`) | `MobileInput` | 移动端虚拟双摇杆与动作按钮层 |
| **Layer 128** | `Main.tscn` / 启动期 | `StartupLoadingScreen` | 游戏冷启动分阶段进度条加载页 |
| **Layer 220** | `IrisTransition` 动态挂载 | `ExpeditionLoadingScreen` | 远征/跨场景黑白剪影奔跑读取页 |
| **Layer 240** | Autoload (`IrisTransition`) | `IrisTransition` | 全局最高优先级光圈开合过场遮罩（压住包括 Loading 页在内的所有 UI） |

### 3.2 `Dungeon3D/$HUD` 内部 `z_index` 栈序（由底向上）

| `z_index` | 节点名称 | 界面类型 | 备注 |
|---|---|---|---|
| **0** (默认) | `HudReloadRing` / `InteractionPromptPanel` / `ExtractionProgressPanel` / `RunOutcomePanel` / `TowerCurrentInfoHUD` / `TowerElevatorOverlay` | 常驻反馈与基础面板 | 随状态显隐 |
| **100** | `ReferenceCombatHUD` (`HUDPresenter3D`) | 主战斗 HUD | 生命、弹药、武器卡、快捷栏、状态条、世界时间 |
| **105** | `DungeonMinimap3D` | 局部小地图（默认隐藏） | 逻辑常驻，供 M 键大地图复制已探索房间状态 |
| **110** | `OffscreenEnemyIndicator3D` | 屏外怪物红箭头环 | 仅在激活态同层 50m 内敌人在屏幕外时绘制 |
| **120** | `EncounterCountdownRing` | 遭遇事件倒计时圆环 | 右上角，平时隐藏，触发限时事件时显隐 |
| **210** | `BossHUD3D` | 首领顶栏双层血条 | Boss 激活出场完成后显隐 |
| **220** | `LowHealthVignette` | 濒死全屏红边脉冲遮罩 | HP < 30% 时激活（`mouse_filter = IGNORE`） |
| **350** | `InventoryUI` | 棋盘式包裹与装备主界面 | 按 `I` / `Tab` / `B` 切换 |
| **420** | `WeaponPresentationPage3D` | K 键武器表现与构建树页 | 按 `K` 键切换（含 `WeaponAssemblyTreePanel`） |
| **850** | `ExploredFloorMapOverlay` | M 键全屏已探索战术大地图 | 含 84% 暗化遮罩与 `940×600` 矢量房间拓扑图 |
| **900** | `DoorFateOverlay3D` | 门后命运塔罗三选一购卡层 | 开启未清房门或命运交互时弹出 |
| **930** | `InitialLoopRetreatWarning` / `ExpeditionExitWarning` | 98F 撤退确认 / 远征退出确认框 | 破坏性结算操作的二次确认模态框 |
| **950** | `DeathConfirmationDialog` | 玩家阵亡结算确认弹窗 | 死亡动画播完后弹出，确认后返回 99F 基地 |
| **960** | `SegmentAirlockWarning` | 跨区段隔离间锁定确认框 | 向下进入新五层区段前的不可逆警告 |
| **2100** | `PerformanceOverlay` / `FlashlightColorTweaker` | 性能监控面板（`0`键）/ 灯光后处理调参台（`P`键） | 开发者工具最高层，不被任何游戏内遮罩挡住 |

---

## 4. 全项目 UI 界面完整设计清单（共 48 个界面/组件）

以下按**八大功能域**将《弹壳风暴2》中所有已实现的 UI 界面与世界空间 UI 组件全部列入本设计文档。

### 4.0 风格批次状态（2026-10-17 更新）

第三轨「棱镜线框」已**全站推广**；规范见 [UI风格规范_棱镜线框](UI风格规范_棱镜线框.md)。

| 批次 | 界面条目 | 状态 |
|---|---|---|
| **棱镜线框 · 第一批（定标样板）** | `UI-06` 主战斗 HUD、`UI-07` 塔楼/远征引导 HUD、`UI-08` 权威世界时间 HUD、`UI-28` 98F 新手环路撤退确认、`UI-29` 跨区段隔离间确认、`UI-30` 远征中途退出确认、`UI-31` 玩家阵亡结算确认、`UI-32` 暂停与系统设置主菜单（含画面设置子页 / 操作设置子页 / 复位存档二次确认） | ✅ 已完成并实机截图归档 |
| **棱镜线框 · 第二批（全站推广）** | `UI-01` 启动加载页、`UI-02` 远征读取页、`UI-04` 3D 实景主页面菜单（含两个按钮）、`UI-05` 开场影片层、`UI-12` Boss 血条、`UI-15` 交互提示、`UI-16` 撤离读条、`UI-17` 战局结算板、`UI-18` 棋盘式包裹与装备主界面、`UI-19` 3D 物品缩略图控件、`UI-20` 武器表现与构建树、`UI-21` 局内武器工作台、`UI-22` 局内流浪拾荒商、`UI-23` 门后命运塔罗三选一、`UI-24` 命运卡赋能目标选择框、`UI-25` 命运卡生效横幅、`UI-26` 战术大地图、`UI-27` 电梯选层面板、`UI-34` 基地衣柜、`UI-35` 保险库、`UI-36` 售货机、`UI-37` 枪械工坊、`UI-38` 状态恢复终端、`UI-39` 怪物图鉴、`UI-40` 命运牌组图鉴、`UI-41` 塔罗占卜屋、`UI-42` 叙事对话框、`DEV-02` 性能监控器 | ✅ 已完成（做法规格 §5.10：口径收口到工厂 + 三档窄口径工具） |
| **业主明确划出 · 不改动** | `UI-33` 出发选关与 3D 全息沙盘（`RogueMapSelectMenu` / `HologramCity3D`，远征情报室）。**实测该脚本除 `env.background_color` 外无任何 2D UI 样式，天然满足**。包裹 / 装备 / 仓库（`UI-18` / `UI-35` / `UI-36`）**只改样式，布局与功能一行未动** | ⛔ 见规范 §10.1 |
| **无需改造** | `UI-03` 全局光圈过场（纯遮罩，无 UI 元素） | — |

> **下文各条目中的"布局与视觉"描述记录了改造前的原始实现**，作为界面职责与节点契约的权威说明；
> 凡上表标记为"已改版"的条目，其**视觉层**以 [UI风格规范_棱镜线框](UI风格规范_棱镜线框.md) 为准，
> 节点路径、`signal`、`z_index` 与交互契约**均未变更**。

---

### 4.1 域一：启动流、主页面与全局过场（5 项）

#### UI-01 启动加载页（`StartupLoadingScreen`）
- **场景与脚本**：`scenes/StartupLoadingScreen.tscn` + `scenes/StartupLoadingScreen.gd`
- **账本 ID**：*待补录（建议 `UI-SCREEN-STARTUP-LOADING`）*
- **层级**：`CanvasLayer (layer = 128)`
- **触发与生命周期**：`Main.gd` 冷启动进入游戏时率先挂载，按 `STAGE_WEIGHTS` 分阶段预热着色器与主场景，100% 后自动卸载。
- **布局与视觉**（2026-10-17 主人改版：**色块构成背景 + 名字撑满画幅 + 斜进度条**）：
  - 底色 `#06080B` 只作最底一层，上面压**色块构成背景**（见下条）。画面上没有任何线框、卡片或图形装饰 —— 除背景色块、名字、进度条外无其他内容。
  - 基调沿用主面板棱镜线框语言：近白字、深墨底、方角、零渐变、零卡片；在此之上叠**赛博色散**与**朋克律动**（仅本屏，不进 HUD 体系）。
  - **色块构成背景（黑底 + 多方向碎切 + 逐帧变比例）**：主色四件套 **玫红 `#FF2D7E` / 绿 `#02E676` / 蓝 `#1D6AFF` / 黑 `#06080B`**，**黑是主角**。
    - 十块鲜艳形状 + 两块撞色形状组成形状池（`PIECE_POOL`），角度全部离开名字的 -13°：72° 陡竖切 / -32° 缓横 / -62° 陡对角 / +38° 反斜 / -48° 三角 / -20° 小块 / +15° 扁条 / -55° 尖条 / +80° 小方 / -38° 斜块；撞色是 -17° 长条 + 72° 陡块。**方向互相打断构成紊乱** —— 上一版切线随名字角度会被读成「速度线」（冲刺感），不是要的东西。
    - **八帧，每帧比例不同**（`FRAME_SPECS`，单帧 `FLASH_SECONDS = 0.15 s`，落在业主指定的 0.1–0.2 s 区间，八帧一轮 1.2 s）。实测鲜艳占比与黑占比：
      `f0 25.05/70.00` · `f1 8.33/87.85` · `f2 15.37/83.49` · `f3 6.66/88.38` · `f4 19.44/76.74` · `f5 12.58/83.61` · `f6 11.79/87.07` · `f7 0.00/98.86`。
      **f1 与 f3 低于 10%，f7 是黑场** —— 业主明确要求"部分画面的比例可以鲜艳色彩降到 10% 以下"。**黑每帧都在 70% 以上**，这是"主要颜色还是黑色"的可核对定义。
    - 八帧靠 `FRAME_FLIPS` 镜像换落点，不手写八套顶点：镜像不改变任何碎片面积，配额逐帧恒定；但落点全变，观感是"每次切法都不同"。
    - 面积由 `measure_area_share()` 用鞋带公式逐帧自检，探针每次运行打印 `AREA f0..f7`；改任一顶点或索引都必须重跑核对。
    - **闪切与律动已解耦**：字仍按 138 BPM（每拍 0.435 s）抖动，背景按 0.15 s 换帧。两者是两套节奏叠加 —— 138 BPM 一拍就是 0.435 s，物理上不可能既锁拍又做到 0.1–0.2 s。
  - **名字**「弹壳风暴2」：设计基准 **260 px**、字距 8、weight 800，整串绕自身中心旋转 `-13°`（右端抬高），用 `draw_set_transform` 做绘制级旋转 —— **不是节点 `rotation`**，节点旋转会把子控件排版盒一起带走、破坏与进度条的对齐。
  - **撑满画幅**：260 px 时旋转后的视觉包围盒约 `1302×608`，横向超出 1280 画幅约 22 px —— 左右各切掉约 11 px 笔画边角，**刻意允许出画**。再往上（≈290 px）会真切掉字形、开始牺牲可读性，故 260 是"压满但认得出来"的分寸。
  - **近黑描边（背景多色后的可读性刚需）**：白主体下方先刷 8 方向的 5 px 近黑描边（`#030406`）。没有这层，白字压在亮绿 `#02E676` 上会直接糊掉 —— 这不是装饰，是背景改多色带来的硬约束。
  - **赛博色散**：名字按粉（`#FF3D9D`）左上 / 青（`#22E6FF`）右下三遍叠绘，白主体压中间；偏移 3.6 px（设计基准），色层 alpha 0.88。进度条填充用同法但偏移减半 —— 细长条用满偏移会缝成三条平行线、读不出进度。
  - **朋克律动（字抖，条不抖）**：名字叠三层互不约频率的抖动 —— ① 常驻微颤（0.5 px / 0.10°，73/113/97/149 Hz 正弦）；② 节拍冲击（2.4 px / 0.45°，拍内按 `pow(1-phase, 2.8)` 衰减）；③ 强拍重音（每小节第一拍，额外横向 4.2 px / 0.75°）。入场另有 0.30 s 的 1.09 → 1.0 缩放冲击。色散随节拍由 3.6 px 扩到最高 8.1 px，强拍时左右方向翻转。**抖动方向必须每拍重掷、拍内保持不变**（用确定性哈希而非每帧随机，否则字会变成噪点闪烁而不是"在震"）；**进度条走干净坐标系，不吃抖动** —— 功能件跟着鼓点跳会让读数发飘。
  - **进度条**：**跟名字同角度斜置**（同一旋转坐标系内绘制），宽度取**字块宽度的 34%**、锚字块下中，高 8 px、距字块底沿 36 px。空槽为**不透明近黑衬底（88%）+ 2 px 白描边（72%）** —— 原来是"10% 半透明白底"，那是给纯黑背景设计的，在亮色块上会直接消失。填充为白实心 + 进度头亮块。**无百分比读数**。
  - 原「SHELLSTORM 2 · OPERATION SYSTEM」眉标、「正在准备你的行动」副标题、阶段文案（`STEP_TEXTS`）与「请稍候」提示已全部移除；仅"启动失败"文案保留，且 `visible = false` 兜底，正常路径不占版面。
  - 全部几何按 `DESIGN_SIZE = 1280×720` 用**统一缩放系数**等比缩放（取各轴比值较小者）—— 旋转图形若按 x/y 分轴缩放会把角度拉歪，等比是保住 -13° 的唯一办法。
- **引擎级前置画面（`boot_splash`）**：`project.godot` 的 `boot_splash/image` 指向 `scenes/StartupLoadingSplash.png`，**在 UI-01 之前**由引擎绘制，早于任何脚本。2026-10-17 同步改为**只有一条空进度槽**（1920×1080，近黑底 `#06080B`，槽宽 34%、内底 12% 白 + 42% 白描边）；原眉标/标题/副标题/阶段文案/请稍候全部删除。`boot_splash/bg_color` 同步改为与图同一底色，避免窗口边缘露出色差带；`.png.import` 的 `process/size_limit` 由 1024 改为 0，否则 1920 宽贴图会被压成 1024（旧图正是 1024×576）。
- **核心交互**：纯展示阻断层，无玩家输入。

#### UI-02 远征/场景切换黑白剪影读取页（`ExpeditionLoadingScreen`）
- **场景与脚本**：`scenes/ExpeditionLoadingScreen.tscn` + `scenes/ExpeditionLoadingScreen.gd`
- **账本 ID**：*待补录（建议 `UI-SCREEN-EXPEDITION-LOADING`）*
- **层级**：`CanvasLayer (layer = 220)`（由 `IrisTransition` 托管）
- **触发与生命周期**：从 99F 基地进入远征关卡或跨大场景异步构建期间显示；遵循 `MIN_HOLD_SEC = 0.65s` 最短展示时间，防止闪屏。
- **布局与视觉**：全屏纯黑背景（`#000000`），右下角锚定 `360×132` 绘制区：左侧为纯代码 `_draw()` 驱动的白色剪影兔子奔跑动画（含双耳相位滞后摆动与地面视差碎石），右侧为 `LOADING...` 呼吸字样与當前装配阶段副标题（如“正在装配地图…”）。

#### UI-03 全局光圈过场遮罩（`IrisTransition`）
- **场景与脚本**：Autoload 单例 `src/ui/IrisTransition.gd`
- **账本 ID**：*待补录（建议 `UI-OVERLAY-IRIS-TRANSITION`）*
- **层级**：`CanvasLayer (layer = 240)`（全游戏最高层）
- **视觉与动效**：全屏 `ColorRect` 挂载圆孔噪声 Shader。转场时以屏幕中心（或指定 UV）做半径 `1.25 → 0.0` 收缩闭幕（`0.42s`）与 `0.0 → 1.25` 展开开幕（`0.46s`），孔洞边缘带双频正弦波浪扰动（`edge_wobble = 0.018`）。

#### UI-04 3D 实景主页面覆盖层（`MainEntryScreen3D`）
- **场景与脚本**：`scenes/MainEntryScreen3D.tscn` + `src/ui/main_entry/MainEntryScreen3D.gd`（子组件：`EntryBrand.gd`、`EntryNeonButton.gd`）
- **账本 ID**：`UI-SCREEN-MAIN-MENU`
- **层级**：`CanvasLayer (layer = 110)`
- **触发与生命周期**：进程首次启动且非新档开场影片时挂载于 `TowerDescent3D` 之上；复用 100F 天台真实 3D 场景与角色，将相机拉至专用展示机位（`FOV 38°`）。
- **布局与视觉**：
  - **左侧渐变暗化带**：左浓右透 Shader 遮罩，保证左侧菜单可读且右侧 3D 角色与天台云海完全通透。
  - **左上品牌区（`EntryBrand`）**：纯代码绘制斜切几何字“弹壳风暴” + 霓虹粉发光字“2” + 副标题 `SHELL STORM // PROTOCOL REBORN`。
  - **左中主菜单列**：4 枚 `EntryNeonButton`（`继续游戏`、`新游戏`、`设置`、`退出`），带六角切角、悬停流光扫描、右侧角标（`RESUME` / `RESET` / `CONFIG` / `QUIT`）。
  - **新档二次确认卡（`ConfirmCard`）**：点击“新游戏”时在菜单右侧滑出红色警告面板（提示清空长期档与基地进度），含“确认覆盖”与“取消”。
- **核心交互**：支持鼠标悬停流光与手柄上下导航；点击“继续游戏”平滑归还镜头与 HUD 控制权；点击“设置”原地唤起 `PauseMenu3D` 设置视图。

#### UI-05 新游戏开场影片层（`OpeningMovieScreen3D`）
- **场景与脚本**：`scenes/OpeningMovieScreen3D.tscn` + `src/ui/main_entry/OpeningMovieScreen3D.gd`
- **账本 ID**：*待补录（建议 `UI-SCREEN-OPENING-MOVIE`）*
- **层级**：`CanvasLayer (layer = 110)`（与 `MainEntryScreen3D` 互斥）
- **触发与生命周期**：全新存档（或重置存档后）首次进入时自动播放 `res://assets/video/opening_intro.ogv`；播完或跳过后直接将玩家落位在 **98F 主人办公室** 并触发唤醒剧情。
- **布局与视觉**：全屏黑底 + 16:9 等比居中 `VideoStreamPlayer` + 右下角半透明跳过提示（`任意键 / 点击跳过`）。
- **核心交互**：前 `0.25s` 防误触保护期后，任意键盘按键、手柄按钮或鼠标点击立即跳过视频并交还 98F 游戏控制权。

---

### 4.2 域二：战局与塔楼常驻 HUD（12 项）

#### UI-06 主战斗 HUD（`ReferenceCombatHUD` / `HUDPresenter3D`）
- **场景与脚本**：`src/world3d/Dungeon3D.gd` (`_build_reference_main_hud`) + `src/ui/HUDPresenter3D.gd`
- **账本 ID**：`UI-SCREEN-HUD`
- **层级**：`Dungeon3D/$HUD (z_index = 100)`
- **布局与视觉（全去背板化 Bare HUD，文字 5px 黑描边压实景）**：
  - **左上角 · 生存状态区（`TopLeftStatusPanel`，`18,16` → `468,164`）**：
    - 玩家等级徽章（`Lv.X`）+ 经验细条（`PlayerExpBar`）。
    - 主生命条（`PlayerHealthBar`，高 22px）+ 底层橙红延迟追赶条（`PlayerHealthDelayBar`）+ 右侧精确数值（`HP 100/100`）。
    - 体力条（`PlayerStaminaBar`，高 10px，琥珀黄/青色）+ 耗尽红闪提示。
  - **右上角 · 楼层与状态播报区**：
    - 楼层/关卡标题（`FloorInfoLabel`，右上 `-430, 12`）与种子信息。
    - 实时战况/交互反馈单行状态条（`StatusReadoutLabel`，如拾取提示、门禁状态、波次剩余）。
  - **左下角 · 4 槽快捷消耗品栏（`QuickConsumableBar`，`18, -110`）**：
    - 4 个 `64×64` 快捷槽（对应按键 `1`~`4`），内嵌 `ItemModelIcon3D` 实时 3D 消耗品图标、角标键位与右下堆叠数量。
  - **右下角 · 双武器卡与弹药读数区（`WeaponDeckPanel`，`-430, -168`）**：
    - 主武器（槽位 1）与副武器（槽位 2）切换卡，当前激活武器高亮放大，含 3D 枪械侧视缩略图、枪名、当前弹夹/备弹超大号读数（`AmmoReadoutLabel`）及命运词条数角标。
    - 本局战利品/金币唯一读数行（`RunLootReadout`，灵魂金配色）。

#### UI-07 塔楼/远征行动引导 HUD（`TowerCurrentInfoHUD`）
- **场景与脚本**：`src/world3d/TowerDescent3D.gd` (`_install_tower_hud`)
- **账本 ID**：归属 `UI-SCREEN-HUD` 子组件
- **层级**：`Dungeon3D/$HUD (z_index = 0)`，左上角生命条正下方（`14, 176` → `270, 290`）
- **布局与视觉**：全透明无背板容器 + 4 行 5px 黑描边文字：当前楼层名（如 `楼顶 · 100F` / `基地层 · 99F`）、当前阶段目标引导、电梯解锁状态提示、基地长期金币余额（琥珀金）。

#### UI-08 权威世界时间 HUD（`WorldDateTimeHUD`）
- **场景与脚本**：`src/world3d/TowerDescent3D.gd` (`_install_world_time_hud`)
- **账本 ID**：归属 `UI-SCREEN-HUD` 子组件
- **层级**：`Dungeon3D/$HUD (z_index = 100)`，右上角楼层名正下方（`-292, 48` → `-18, 98`）
- **布局与视觉**：无背板 5px 描边冰青色文字（`2075-01-01  09:00`），绑定 `GameTimeManager.minute_changed` 信号，悬停 Tooltip 提示“20个现实分钟推进一个游戏日”。

#### UI-09 角色身侧换弹进度环（`HudReloadRing`）
- **场景与脚本**：`src/ui/HudReloadRing.gd`
- **账本 ID**：归属 `UI-SCREEN-HUD` 子组件
- **层级**：`Dungeon3D/$HUD (z_index = 0)`
- **布局与动效**：通过相机 `unproject_position()` 实时跟随玩家 3D 胸口偏右屏幕坐标（尺寸 `56×56`）。换弹期间绘制暗底圆环 + 琥珀黄顺时针充能弧线 + 中心剩余秒数；换弹完成瞬间触发 `0.18s` 翠绿高亮扩散闪烁后淡出。

#### UI-10 限时遭遇事件倒计时环（`EncounterCountdownRing`）
- **场景与脚本**：`src/ui/EncounterCountdownRing.gd`
- **账本 ID**：归属 `UI-SCREEN-HUD` 子组件
- **层级**：`Dungeon3D/$HUD (z_index = 120)`，右上角（`-112, 96`，尺寸 `88×88`）
- **布局与动效**：平时隐藏；触发限时防守/猎杀事件时显现。外圈为 60 刻度战术表盘 + 逆时针衰减进度弧，中心显示剩余秒数与事件名。剩余 `≤ 10s` 时切换为危险红（`#FF3847`）并每秒触发一次 `1.08x` 心脏跳动缩放。

#### UI-11 屏幕外激活敌人指示箭头（`OffscreenEnemyIndicator3D`）
- **场景与脚本**：`src/ui/OffscreenEnemyIndicator3D.gd`
- **账本 ID**：归属 `UI-SCREEN-HUD` 子组件
- **层级**：`Dungeon3D/$HUD (z_index = 110)`，全屏透传容器
- **布局与规则**：围绕屏幕中心椭圆轨迹（留出四周 HUD 安全边距），为屏幕外、已唤醒、同层（`|Δy| ≤ 4.5m`）、50m 内的活怪绘制最多 `12` 枚带黑描边的红色指向三角箭头；距离越近箭头越大、越不透明（`alpha 0.42 ~ 0.92`）。

#### UI-12 首领战顶栏双层血条（`BossHUD3D`）
- **场景与脚本**：`src/world3d/Dungeon3D.gd` (`_show_boss_hud` / `_hide_boss_hud`)
- **账本 ID**：归属 `UI-SCREEN-HUD` 子组件
- **层级**：`Dungeon3D/$HUD (z_index = 210)`，屏幕正上方居中（`-330, 52` → `330, 108`）
- **布局与动效**：仅在 Boss 完成出场激活后显示。顶部为居中首领名与阶段号（如 `监控暴君 · 阶段 2`），下方为 `660×16` 双层血条：底层琥珀橙延迟追赶条（`BOSS_BAR_DELAY_SPEED = 1.9`）+ 顶层鲜红实时血条。

#### UI-13 濒死全屏暗红脉冲遮罩（`LowHealthVignette`）
- **场景与脚本**：`src/world3d/Dungeon3D.gd` (`_update_low_health_vignette`)
- **账本 ID**：归属 `UI-SCREEN-HUD` 子组件
- **层级**：`Dungeon3D/$HUD (z_index = 220)`，全屏 `mouse_filter = IGNORE`
- **视觉与动效**：当玩家 HP 比例低于 `30%` 时激活，按正弦波（频率随伤势加剧提升）驱动四周暗红色脉冲压暗，提供无需看左上角即可感知的生存危机感。

#### UI-14 局部雷达小地图组件（`DungeonMinimap3D` — 局部态）
- **场景与脚本**：`src/ui/DungeonMinimap3D.gd`
- **账本 ID**：`UI-WIDGET-MINIMAP`
- **层级**：`Dungeon3D/$HUD (z_index = 105)`
- **当前状态与职责**：右上角小圆盘常驻渲染已按减负要求默认隐藏（`visible = false`），但节点作为**房间探索状态与迷雾记录器**常驻运行，实时记录已揭晓房间、门锁状态、撤离点、商人/工作台图标，为 M 键全屏战术地图提供数据源。

#### UI-15 战局上下文交互提示条（`InteractionPromptPanel`）
- **场景与脚本**：`src/world3d/Dungeon3D.gd` (`_build_hud`)
- **账本 ID**：归属 `UI-SCREEN-HUD` 子组件
- **层级**：`Dungeon3D/$HUD (z_index = 0)`，屏幕中下方
- **职责**：当玩家靠近门禁、搜刮容器、基地设施、地面高价值武器时，显示无背板描边按键引导（如 `[E] 搜索储物柜`、`[F] 开启大门`）。

#### UI-16 撤离信标读条面板（`ExtractionProgressPanel`）
- **场景与脚本**：`src/world3d/Dungeon3D.gd`
- **账本 ID**：归属 `UI-SCREEN-HUD` 子组件
- **层级**：`Dungeon3D/$HUD (z_index = 0)`，屏幕中上方
- **职责**：玩家激活撤离信标并在圈内驻留时显示撤离倒计时进度条与“离开信标区域将中断撤离”警示。

#### UI-17 战局结算总览面板（`RunOutcomePanel`）
- **场景与脚本**：`src/world3d/Dungeon3D.gd`
- **账本 ID**：`UI-MODAL-EXTRACTION-RESULT` / `UI-MODAL-DEATH-SETTLEMENT`
- **层级**：`Dungeon3D/$HUD (z_index = 0)`，居中模态
- **职责**：在纯地牢模式或结算阶段汇总展示本次行动结果（撤离成功 / 行动失败）、击杀数、带出战利品估值、保险柜保留物品与损毁物资明细。

---

### 4.3 域三：背包、装备与武器构建系统（5 项）

#### UI-18 棋盘式包裹与角色装备主界面（`InventoryUI`）
- **场景与脚本**：`scenes/InventoryUI.tscn` + `src/ui/InventoryUI.gd` + `src/ui/GridInventoryBoard.gd` + `src/ui/StorageBoardView.gd` + `src/ui/ItemSlot.gd`
- **账本 ID**：`UI-SCREEN-INVENTORY-3D`（关联组件：`UI-COMP-ITEM-SLOT`、`UI-COMP-STORAGE-SLOT`）
- **层级**：`Dungeon3D/$HUD (z_index = 350)`
- **快捷键**：`I` / `Tab` / `B` 打开或关闭；`R` 键旋转拖拽中物品；`ESC` 优先取消拖拽、其次关闭背包。
- **美术风格**：**鸭科夫柔和深蓝仓储风（Soft Navy Surface）**。
- **三栏式黄金布局**：
  - **左栏 · 武器与配件装配区 + 4 槽快捷栏**：上下并列【主武器 1】与【副武器 2】两张大卡，每把枪下挂 **6 个专属配件槽**（枪口、瞄具、握把、弹匣、枪托、战术挂件）+ 枪械词条预览；底部横排 4 个快捷消耗品槽。
  - **中栏 · 角色 3D 实时预览与丢弃区 + 详情/拆分卡**：顶部显示玩家昵称与负重/等级；中央通透区实时展示 3D 角色全身模型；底部悬浮选中物品详情卡、可堆叠物品数量拆分滑块（`SplitSlider`）及【使用 / 装备 / 拆分 / 丢弃】操作按钮。将物品拖入中央留白松手即丢弃到 3D 地面。
  - **右栏 · 8列连续棋盘背包 + 8×2 保险柜**：
    - 上部为 `GridInventoryBoard`（固定 8 列 × 50px 基准格，支持滚轮浏览多行），不同尺寸物品（1×1 消耗品、2×2 护甲、3×2/4×2 步枪）按真实占格渲染 3D 图标与品质色底边。
    - 下部为 `8×2` 橙金描边**安全保险柜（Insurance Box）**，放入其中的非武器物资在战局阵亡时 100% 保留带回基地。

#### UI-19 实时 3D 物品同源缩略图控件（`ItemModelIcon3D`）
- **场景与脚本**：`src/ui/ItemModelIcon3D.gd`
- **账本 ID**：*待补录（建议 `UI-COMP-ITEM-MODEL-ICON-3D`）*
- **核心契约**：全项目所有物品格（背包、保险库、售货机、工坊、商人、命运来源）共用的底层 3D 渲染组件。支持 `DISPLAY_MODE_STATIC_ICON`（正交斜俯视定格快照，占满格子 88%）与 `DISPLAY_MODE_ROTATING_PREVIEW`（详情区持续自转展示），内置全局网格缓存 `_mesh_ metrics_cache` 避免重复解析 GLB。

#### UI-20 K 键武器表现与构建树全屏页（`WeaponPresentationPage3D` / `WeaponAssemblyTreePanel`）
- **场景与脚本**：`src/world3d/Dungeon3D.gd` (`_toggle_weapon_presentation_page`) + `src/ui/WeaponAssemblyTreePanel.gd`
- **账本 ID**：*待补录（建议 `UI-SCREEN-WEAPON-ASSEMBLY-3D`）*
- **层级**：`Dungeon3D/$HUD (z_index = 420)`
- **快捷键**：`K` 键切换打开/关闭；顶部配备中/英双语切换按钮（绑定 `GameText`）。
- **布局与交互**：
  - **顶部工具栏**：主武器 / 副武器切换 Tab + 语言切换（`中文 / EN`）+ 关闭按钮。
  - **中央 3D 检视与放射状槽位环**：中央大图实时旋转展示当前武器 3D 模型，四周环绕 **6 大配件槽位节点** 与 **命运赋能槽位**，用动态折线连接至枪身对应部位，直观呈现“枪械母体 + 6 配件 + 命运卡”的完整构建树。
  - **右侧属性对比与词条面**：展示伤害、射速、换弹、散布、射程等核心六维数值及当前生效的全部命运塔罗正/逆位修正。

#### UI-21 局内武器改造台 · 5×5 炼金盘（`WorkbenchPanel`）
- **场景与脚本**：`scenes/WorkbenchPanel.tscn` + `src/ui/WorkbenchPanel.gd` + `src/weapons/WeaponForge.gd`
- **账本 ID**：*待补录（建议 `UI-MODAL-WORKBENCH`）*
- **层级**：`Dungeon3D/$HUD` 动态实例化模态框
- **触发方式**：在战局内与 `upgrade` 型服务台（武器改造台）按 `E` 交互打开。
- **两个页签**：`熔炼`（默认）/ `合成目录`。合成目录是"钥匙 → 武器"的九条配方清单，见[合成目录与兴趣曲线](../07.3_玩法系统_合成目录与兴趣曲线.md)；页签用棱镜 1px 下划线标记当前页，不用按钮底色。
- **美术风格**：**棱镜线框（`PRISM-WIREFRAME`）**，与全站一致。不画实心卡片，区域由 1px 白线 + 四角括号界定。
- **核心功能**：**炼金抽卡**。中栏 5×5（25 格，正方形）炼炉按 `grid_size` 占格，**所有物品都能当材料**（武器是蓝本，其余按 `rarity` 折算），并支付金币后熔炼，产出**蓝本、品质（蓝/紫/金）、弹种**全部重新掷骰的新枪实例。三条配方见[玩法系统｜武器改造台](../07.2_玩法系统_武器改造台.md)：单武器 + 材料 ≥3 熔炼值 = 重铸；≥2 把武器 = 融合（蓝本随机 + 弹种从各枪自带弹种随机 + 随机附带配件）；纯材料 ≥6 熔炼值 = 合成。**材料的稀有度直接提升品质**（稀有度分 common 0 / uncommon 1 / rare 2 / epic 4 / legendary 7）。费用 `max(min, ceil(投入估值×rate))`，R1/R2/R3 费率 0.30/0.40/0.50。
- **布局**：
  - 页头：`WEAPON FORGE` 弱标签 + 「武器改造台」强标题；右侧 `COINS` 读数 + `ESC 关闭`。
  - **主体**：中栏炼炉 `ALCHEMY GRID 5 × 5`（格边长 80，正方形，外挂 ghost 括号）；右栏 `INVENTORY`（与 I 键同源 `InventoryModule`，格边长 46、8 列，与 `InventoryModule.GRID_COLUMNS` 一致）。
  - **页脚两行**：第一行 7 栏读数（`PAYLOAD` / `MELT` / `RARITY` / `RECIPE` / `BLUEPRINT` / `GRADE ODDS` / `FEE`）等分铺满；第二行左侧状态文案、右侧 `ESC 关闭` + 「熔 炼」。**按钮与信息全在底部，主体区不夹任何信息行。**
  - **版式实现**：炼炉水平居中、背包贴右，靠 `_layout_body()` 在 `resized` 时手算矩形；用 `HBoxContainer` 只能让整组居中，炼炉会必然偏左。
  - 读数行**一行 7 栏**两级排印（位于页脚第一行）：`PAYLOAD`（N 枪 · M 材料）/ `MELT` / `RARITY`（稀有度分，材料提品质的唯一可见抓手）/ `RECIPE` / `BLUEPRINT`（R2 显示「随机（N 把之一）」）/ `GRADE ODDS` / `FEE`（买不起转危险红）。
  - 底部：状态行 + `primary` 白底实心「熔 炼」+ 一行窄注。
- **视觉硬约束**：
  - 格子只画 1px 白线、不填底色（棋盘 `prism_mode = true`）；I 键背包是棱镜豁免项，保持原样式。
  - 确认层必须**全屏 0.90 压暗 + 近不透明深墨卡片**且 `z_index = 64` —— 棋盘把物品画布提到 `z_index = 4`，确认层留在默认层会被枪械图标盖住；0.42 的棱镜底衬在这层会透出下层文字。
  - 视口基准 1280×720：5 行盘面（格 80）+ 两行页脚必须全部落在 720 内；状态栏空白文案必须压在一行内。
- **交互硬约束**：
  - **任何非空物品都可入场**：武器当蓝本，其余（弹药模块 / 配件 / 消耗品 / 装备 / 蓝图）一律当材料。"不是材料"的唯一判据是空格。
  - 材料块必须 `clip_contents = true`，否则 1×1 格的标题会压到相邻格上。
  - 盘内含武器时点击熔炼必须先二次确认（写明销毁几把枪、付多少金币）。
  - 金币不足时拒绝，盘面与余额逐字节不变。
  - 关面板时盘内物品原样退回背包，放不下则留在盘内，不允许直接销毁。
  - 旧「免费换枪身 / 免费换弹种 / 命运卡三选一」三项能力已随本改造移除。

#### UI-22 局内流浪拾荒商界面（`MerchantUI`）
- **场景与脚本**：`scenes/MerchantUI.tscn` + `src/ui/MerchantUI.gd`
- **账本 ID**：`UI-MODAL-MERCHANT`
- **层级**：`Dungeon3D/$HUD` 动态实例化模态框
- **触发方式**：在战局内与 `merchant` 型 NPC/服务台交互打开。
- **布局与功能**：展示本层随机刷新的战局补给品（医疗包、弹药、随机武器、配件）与命运契约服务，支持消耗本局拾取的金币即时购买并直接入包或落地。

---

### 4.4 域四：命运塔罗牌组与局内战术弹窗（10 项）

#### UI-23 门后命运塔罗三选一购卡层（`DoorFateOverlay3D`）
- **场景与脚本**：`src/world3d/Dungeon3D.gd` (`_build_door_fate_overlay` / `_create_reference_fate_card_view`) + `src/weapons/FateCardView.gd`
- **账本 ID**：`UI-MODAL-FATE-DRAW`（卡面图集：`UI-ATLAS-FATE-CARD`）
- **层级**：`Dungeon3D/$HUD (z_index = 900)`
- **布局与视觉**：
  - 全屏 62% 暗化遮罩，移除冗余顶栏，金币读数直接复用右下角 HUD。
  - 中央横排 **3 列等高塔罗卡列**（每列 `346×694`，间距 `56px`）：上部为 `346×546` 塔罗图卡（正位正常显示，逆位 `180°` 倒置渲染，叠加 `FateCardView` 斜向扫光 Shader 与错相漂浮动画），中部为 92px 规则说明文案，底部为灵魂金购买价格行。
  - 底部正中为 `220×44`【退 出】按钮（支持买完1~3张后手动退出，或一张不买直接按 `ESC` / 手柄 `B` 离开）。

#### UI-24 命运卡赋能目标选择弹窗（`FateSourceSelectionPanel`）
- **场景与脚本**：`src/ui/FateSourceSelectionPanel.gd`
- **账本 ID**：*待补录（建议 `UI-MODAL-FATE-SOURCE-SELECT`）*
- **层级**：挂载于 `DoorFateOverlay3D` 之上
- **触发与交互**：当玩家购买一张作用于“指定武器或配件”的命运卡时弹出。以横向大卡展示当前可选目标（主武器、副武器或已装配件），每张卡内嵌 `132×132` 的 `ItemModelIcon3D` 实时 3D 预览，点击或按数字键 `1~3` 即可将塔罗牌意注入目标装备。

#### UI-25 命运卡生效顶栏横幅反馈（`FateCardFeedback`）
- **场景与脚本**：`src/ui/FateCardFeedback.gd`
- **账本 ID**：归属 `UI-MODAL-FATE-DRAW` 反馈组件
- **层级**：`Dungeon3D/$HUD` 顶层非阻断浮层（`mouse_filter = IGNORE`）
- **动效表现**：购买或触发命运卡瞬间，在屏幕中上方展开霓虹紫/金双层发光横幅，伴随向上漂浮的微光粒子，展示【卡名 · 正/逆位】与核心增益摘要，`1.8s` 后平滑淡出。

#### UI-26 M 键全屏已探索战术大地图（`ExploredFloorMapOverlay`）
- **场景与脚本**：`src/world3d/Dungeon3D.gd` (`_toggle_full_map`) + `src/ui/DungeonMinimap3D.gd` (`set_full_map_mode(true)`)
- **账本 ID**：*待补录（建议 `UI-MODAL-FULL-MAP`）*
- **层级**：`Dungeon3D/$HUD (z_index = 850)`
- **快捷键**：`M` 键切换打开/关闭，右上角配独立 `关闭 · ESC` 按钮。
- **布局与视觉**：84% 深蓝黑暗化背景 + 居中 `940×600` 矢量战术海图。清晰绘制本层**所有已探索房间**的真实几何外轮廓、门连接走廊、房型色彩编码（安全屋绿、战斗房青、精英房橙、Boss 房红、撤离房金）、服务设施图标以及玩家当前精确朝向箭头；未探索房间保持战争迷雾隐藏。

#### UI-27 塔楼电梯选层面板（`TowerElevatorOverlay`）
- **场景与脚本**：`src/world3d/TowerDescent3D.gd` (`_open_elevator_panel`)
- **账本 ID**：*待补录（建议 `UI-MODAL-TOWER-ELEVATOR`）*
- **层级**：`Dungeon3D/$HUD (z_index = 0)`，居中模态（`460×470`）
- **功能与交互**：在塔楼电梯房交互打开，列出 `99F` 基地与所有玩家已亲自点亮的楼层按钮（当前所在层置灰标“当前层”），点击目标楼层立即传送。

#### UI-28 98F 新手环路撤退确认弹窗（`InitialLoopRetreatWarning`）
- **场景与脚本**：`src/world3d/TowerDescent3D.gd` (`_show_initial_loop_retreat_warning`)
- **账本 ID**：*待补录（建议 `UI-MODAL-RETREAT-WARNING`）*
- **层级**：`Dungeon3D/$HUD (z_index = 930)`，居中模态（`540×250`）
- **职责**：玩家在 98F 尝试通过撤离点返回 99F 时弹出琥珀金边框确认框，告知战利品将带回基地，提供【留在当前层】与【确认撤退回 99F】双按钮。

#### UI-29 跨区段隔离间不可逆确认弹窗（`SegmentAirlockWarning`）
- **场景与脚本**：`src/world3d/TowerDescent3D.gd` (`_show_airlock_warning`)
- **账本 ID**：*待补录（建议 `UI-MODAL-AIRLOCK-WARNING`）*
- **层级**：`Dungeon3D/$HUD (z_index = 960)`，居中模态（`560×290`）
- **职责**：玩家进入跨 5 层区段的隔离间下行门前弹出霓虹青/金警示框，明确告知“进入下一区段后本区段房间将封存”，防止误触下潜。

#### UI-30 远征关卡中途退出确认弹窗（`ExpeditionExitWarning`）
- **场景与脚本**：`src/world3d/TowerDescent3D.gd` (`_show_expedition_exit_warning`)
- **账本 ID**：*待补录（建议 `UI-MODAL-EXPEDITION-EXIT`）*
- **层级**：`Dungeon3D/$HUD (z_index = 930)`，居中模态（`540×250`）
- **职责**：在远征关卡中点击暂停菜单“放弃远征”或入口撤离门时弹出危险红边框警告，提示“中途退出按失败结算，未保险物资将遗失”。

#### UI-31 玩家阵亡结算确认弹窗（`DeathConfirmationDialog`）
- **场景与脚本**：`src/world3d/Dungeon3D.gd` (`_show_death_confirmation_dialog`)
- **账本 ID**：归属 `UI-MODAL-DEATH-SETTLEMENT`
- **层级**：`Dungeon3D/$HUD (z_index = 950)`，居中模态（`520×260`）
- **职责**：玩家 HP 归零且倒地死亡动画播放完毕后弹出。红框黑底展示“行动人员已倒下 · 未保险物资将按死亡规则结算”，自动抓取【确认结算并返回基地】焦点，点击后执行死亡结算并经光圈过场送回 99F 基地。

#### UI-32 暂停与系统设置主菜单（`PauseMenu3D`）
- **场景与脚本**：`scenes/PauseMenu3D.tscn` + `src/ui/PauseMenu3D.gd`
- **账本 ID**：`UI-SCREEN-PAUSE-3D`
- **层级**：挂载于当前主场景（天台/基地/塔楼/远征/训练场全地图通用）
- **快捷键**：`ESC` / 手柄 `Start`
- **双视图架构**：
  - **主暂停视图（Main View）**：展示【继续行动】、【画面与操作设置】、【返回 99F 基地 / 放弃本局】、【返回主菜单】、【退出游戏】（根据当前处于基地、战局还是主页面动态裁剪可用项）。
  - **设置子视图（Settings View）**：
    - 画质预设档位切换（低 / 中 / 高 / 极致，联动 `GraphicsSettingsManager`）。
    - 分辨率与全屏/窗口模式切换。
    - 主音量 / BGM / SFX 音量滑块。
    - 手柄灵敏度、震动开关与键位一览。

---

### 4.5 域五：99F 基地设施与养成界面（9 项）

#### UI-33 出发选关与 3D 全息城市沙盘（`RogueMapSelectMenu` + `HologramCity3D`）
- **场景与脚本**：`scenes/RogueMapSelectMenu.tscn` + `scenes/RogueMapSelectMenu.gd` + `src/ui/HologramCity3D.gd`
- **账本 ID**：`UI-SCREEN-LEVEL-SELECT`
- **层级**：`CanvasLayer (layer = 100)`
- **触发方式**：在 99F 基地与出发台/导航终端交互打开。
- **布局与视觉亮点**：
  - **中央 3D 全息城市沙盘（`HologramCity3D`）**：内置独立 3D 视口，以青色全息线框与发光体块实时渲染主塔与周边远征建筑群（塔1~塔4、破败旅馆等），选中不同关卡时全息镜头平滑推向对应建筑并高亮信标。
  - **右侧关卡情报与出发卡**：展示关卡名称（如 `远征关卡01 · 跨塔天桥`、`远征关卡02 · 破败旅馆`）、威胁等级、推荐战力、主要掉落倾向与【立即出发】按钮。

#### UI-34 基地 3D 角色衣柜换装界面（`WardrobeMenu3D`）
- **场景与脚本**：`scenes/WardrobeMenu3D.tscn` + `src/ui/wardrobe/WardrobeMenu3D.gd`
- **账本 ID**：*待补录（建议 `UI-SCREEN-WARDROBE-3D`）*
- **层级**：`CanvasLayer (layer = 120)`
- **触发方式**：在 99F 基地与衣柜设施交互打开；打开时将 3D 场景相机平滑推至角色全身特写机位，支持按住鼠标左右拖拽旋转角色。
- **布局与交互**：左侧通透展示 3D 角色实时换装效果；右侧为霓虹战术风分类标签页（头部/帽子、面部/眼镜、上装、下装、鞋靴、背包外观），网格卡片展示已解锁款式，点击即时替换角色身上对应骨骼挂点的 Mesh 并持久化写入长期档。

#### UI-35 基地个人保险库界面（`VaultMenu`）
- **场景与脚本**：`scenes/VaultMenu.tscn` + `src/ui/VaultMenu.gd`
- **账本 ID**：`UI-SCREEN-BASE-VAULT`
- **层级**：`CanvasLayer (layer = 100)`
- **美术风格**：**鸭科夫柔和深蓝仓储风（Soft Navy Surface）**。
- **布局与功能**：左右双栏对称式大棋盘布局 —— 左侧为玩家随身背包与装备槽，右侧为基地大容量持久化仓库网格（`StorageBoardView`）。支持在随身背包与基地仓库之间自由拖拽存取枪械、配件与战利品，并提供【一键整理】与分类筛选。

#### UI-36 基地自动售货机商店（`BaseVendingMenu`）
- **场景与脚本**：`scenes/BaseVendingMenu.tscn` + `src/ui/BaseVendingMenu.gd`
- **账本 ID**：*待补录（建议 `UI-SCREEN-BASE-VENDING`）*
- **层级**：`CanvasLayer (layer = 100)`
- **美术风格**：**鸭科夫柔和深蓝仓储风（Soft Navy Surface）**。
- **布局与功能**：
  - 左侧为售货机商品货架（按全部 / 武器 / 配件 / 消耗品分类筛选），每格渲染 3D 物品图标、库存角标与售价；
  - 中间为选中商品 3D 旋转检视、详细属性与【买入 / 卖出】数量调节操作区；
  - 右侧直通玩家随身棋盘背包，支持直接点选背包内战利品一键出售换取基地金币。

#### UI-37 基地枪械工坊界面（`WorkshopMenu`）
- **场景与脚本**：`scenes/WorkshopMenu.tscn` + `src/ui/WorkshopMenu.gd`
- **账本 ID**：`UI-SCREEN-BASE-WORKSHOP`
- **层级**：`CanvasLayer (layer = 100)`
- **布局与功能**：基地永久武器养成中心，接入 `GameText` 本地化。支持蓝图解锁、消耗材料制造新武器/高阶配件、以及对已有武器实例进行永久词条校准与部件改装。

#### UI-38 基地生命与状态恢复终端（`BaseRecoveryMenu`）
- **场景与脚本**：`scenes/BaseRecoveryMenu.tscn` + `src/ui/BaseRecoveryMenu.gd`
- **账本 ID**：`UI-MODAL-BASE-RECOVERY`
- **层级**：`CanvasLayer (layer = 100)`
- **功能**：展示玩家当前生命值、体力上限与负面状态，支持免费或消耗微量基地能源/金币一键回满状态。

#### UI-39 怪物生态图鉴界面（`MonsterArchiveMenu`）
- **场景与脚本**：`scenes/MonsterArchiveMenu.tscn` + `src/ui/MonsterArchiveMenu.gd`
- **账本 ID**：`UI-SCREEN-MONSTER-ARCHIVE`
- **层级**：`CanvasLayer (layer = 100)`
- **布局与功能**：按普通怪、精英怪、首领 Boss 分类展示已遭遇敌人的档案卡、击杀统计、弱点抗性说明、行为特征与掉落物清单。

#### UI-40 命运塔罗牌组全图鉴（`FateCardCollectionMenu`）
- **场景与脚本**：`scenes/FateCardCollectionMenu.tscn` + `src/ui/FateCardCollectionMenu.gd`
- **账本 ID**：`UI-SCREEN-FATE-COLLECTION`
- **层级**：`CanvasLayer (layer = 100)`
- **布局与功能**：网格陈列全套大阿卡纳命运塔罗牌（`UI-ATLAS-FATE-CARD`），支持点击放大检视高清卡面美术、切换预览**正位（Upright）**与**逆位（Reversed）**的完整规则文案及历史抽取次数。

#### UI-41 基地塔罗占卜屋界面（`DivinationMenu`）
- **场景与脚本**：`scenes/DivinationMenu.tscn` + `src/ui/DivinationMenu.gd`
- **账本 ID**：`UI-MODAL-DIVINATION`
- **层级**：`CanvasLayer (layer = 100)`
- **功能**：下潜出发前消耗金币进行每日/每局塔罗占卜，为下一局行动预埋起始命运增益或特殊房间倾向。

*(注：另保留 `scenes/BaseMenu.tscn` + `src/ui/BaseMenu.gd` 作为基地早期汇总菜单兼容入口，账本 ID `UI-SCREEN-BASE-HUB`)*

---

### 4.6 域六：叙事对话与 3D 世界空间 UI（5 项）

#### UI-42 底栏叙事对话系统（`DialogueUI`）
- **场景与脚本**：Autoload `scenes/DialogueUI.tscn` + `src/ui/dialogue/DialogueUI.gd`
- **账本 ID**：`UI-OVERLAY-DIALOGUE`
- **层级**：`CanvasLayer (layer = 100)`
- **设计契约**：
  - 仅在 `mode == "dialogue"`（正式剧情演出）时激活。
  - 底部锚定半透明战术底栏，含左侧说话人头像框、左上霓虹青名字牌、打字机逐字输出正文（支持点击瞬间补全当前句）、右下脉冲继续三角标与右上【跳过剧情】按钮（`UiMenuFocus` 默认安全焦点）。

#### UI-43 3D 角色头顶实景漫画气泡（`SpeechBubble3D` + `CharacterBark3D`）
- **场景与脚本**：`src/ui/bubble/SpeechBubble3D.gd` + `src/ui/bubble/CharacterBark3D.gd`
- **账本 ID**：`UI-WORLD-SPEECH-BUBBLE`
- **层级**：3D 世界空间（`SubViewport` + `Sprite3D` Billboard）
- **设计契约**：
  - 用于开关灯自言自语（Bark）、NPC 闲聊、战斗喊话。
  - **纯白圆角底板 + 2px 纯黑描边 + 底部指向说话人头顶的三角尖嘴**（经典漫画气泡风格），与冷色 3D 场景形成极高对比度。
  - **强制非阻断**：`mouse_filter = IGNORE`，不抢焦点、不锁移动、不挡射击射线，按字数自适应停留时长后平滑淡出。

#### UI-44 3D 交互白点与长按读条环（`InteractionDot3D`）
- **场景与脚本**：`src/ui/InteractionDot3D.gd`
- **账本 ID**：`UI-WORLD-INTERACTION-DOT`
- **层级**：屏幕空间投影控件（跟随 3D 交互物锚点）
- **设计契约**：玩家走近可交互容器、开关、门禁时，在目标 3D 坐标处浮现呼吸白点；靠近至可触发半径内展开按键提示圆环，长按交互时圆环顺时针充能。

#### UI-45 地面掉落物 3D 悬浮标签与检视卡（`GroundLootPickup3D` UI）
- **场景与脚本**：`src/world3d/GroundLootPickup3D.gd`
- **账本 ID**：`UI-WORLD-LOOT-LABEL`
- **层级**：3D 世界空间 `Label3D` / 屏幕投影
- **设计契约**：地面物资上方悬浮品质色光柱与物品名称标签；当玩家准星指向或走近地面武器时，可对比显示该武器的品质与核心词条。

#### UI-46 敌人头顶 3D 血条与 AI 警戒感叹号（`Enemy3D` World UI）
- **场景与脚本**：`src/world3d/Enemy3D.gd` + `src/world3d/BaseFacility3D.gd`
- **账本 ID**：`UI-WORLD-ENEMY-STATUS`
- **设计契约**：
  - 普通怪/精英怪受伤后在头顶显示精简 3D 血条；
  - 当怪物从休眠/巡逻态感知到玩家声音或手电光照进入惊觉态时，头顶弹出高对比红色 `!` / 黄色 `?` 警戒标识；
  - 99F 基地设施（`BaseFacility3D`）头顶常驻悬浮设施功能名称牌（如 `【枪械工坊】`、`【个人仓库】`、`【出发终端】`）。

---

### 4.7 域七：跨平台输入与后处理覆盖层（2 项）

#### UI-47 移动端虚拟双摇杆与触控层（`MobileInput`）
- **场景与脚本**：Autoload `scenes/MobileInput.tscn` + `src/ui/MobileInput.gd`
- **账本 ID**：`UI-OVERLAY-MOBILE-INPUT`
- **层级**：`CanvasLayer (layer = 128)`
- **功能**：在触屏设备或开启触控模拟时自动显现：左下角虚拟移动摇杆，右下角瞄准/射击双摇杆及换弹、翻滚、交互、技能快捷触控圆钮；在打开任何全屏菜单时自动隐藏让出触控区。

#### UI-48 全屏胶片颗粒与暗部色调后处理层（`PostfxOverlay`）
- **场景与脚本**：`src/postfx/PostfxOverlay.gd`
- **账本 ID**：*归属后处理系统（参见 `13.1_技术施工_画质设置与后处理.md`）*
- **层级**：`CanvasLayer (layer = 90)`，`mouse_filter = IGNORE`
- **功能**：在 3D 画面之上、主 HUD（若挂载于更高 CanvasLayer）之下叠加动态胶片噪点（Grain）与暗部冷紫/青色偏移，强化废土阴冷质感。

---

### 4.8 域八：训练场与开发者调试 UI（3 项补充建档）

| 编号 | 界面名称 | 脚本路径 | 层级 / 快捷键 | 职责说明 |
|---|---|---|---|---|
| **DEV-01** | 独立训练场命运卡组装台 (`TrainingFateBenchPanel`) | `src/training3d/TrainingFateBenchPanel.gd` | `CanvasLayer (60)` / 训练场常驻 | 提供全量命运塔罗牌自由点选、正逆位切换、一键注入主/副武器或配件的沙盒测试面板 |
| **DEV-02** | 实时性能与热管理监控器 (`PerformanceOverlay`) | `src/ui/PerformanceOverlay.gd` | `$HUD (z=2100)` / 按键 `0` | 实时显示 FPS、Frame Time、Draw Calls、VRAM、活动敌人数与房间流送状态 |
| **DEV-03** | 手电/雾气/后处理实时调参台 (`FlashlightColorTweaker`) | `src/player3d/FlashlightColorTweaker.gd` | `$HUD (z=2100)` / 按键 `P` | 实时拖动滑块调节手电色温、环境光、雾浓度、胶片颗粒并支持一键写盘保存预设 |

---

## 5. 全界面总览速查表（Master Matrix）

| 序号 | 界面代号 | 界面中文名 | 脚本 / 场景入口 | 层级 (`Layer` / `z`) | 美术风格轨 | 手柄焦点 | 账本状态 |
|---|---|---|---|---|---|---|---|
| 01 | `StartupLoadingScreen` | 冷启动分阶段加载页 | `scenes/StartupLoadingScreen.gd` | `L:128` | 棱镜线框 | 无交互 | 待补录 |
| 02 | `ExpeditionLoadingScreen` | 远征黑白剪影读取页 | `scenes/ExpeditionLoadingScreen.gd` | `L:220` | 棱镜线框(深墨底+白线) | 无交互 | 待补录 |
| 03 | `IrisTransition` | 全局光圈开合过场遮罩 | `src/ui/IrisTransition.gd` | `L:240` | 噪声光圈 Shader | 无交互 | 待补录 |
| 04 | `MainEntryScreen3D` | 3D 实景主页面菜单 | `src/ui/main_entry/MainEntryScreen3D.gd` | `L:110` | 棱镜线框 | 已接入 | `UI-SCREEN-MAIN-MENU` |
| 05 | `OpeningMovieScreen3D` | 新档开场影片播放层 | `src/ui/main_entry/OpeningMovieScreen3D.gd` | `L:110` | 棱镜线框(影院黑底保留) | 任意键跳过 | 待补录 |
| 06 | `ReferenceCombatHUD` | 战局主战斗 HUD | `src/world3d/Dungeon3D.gd` + `HUDPresenter3D.gd` | `L:1 / z:100` | 棱镜线框(无背板) | 键位直达 | `UI-SCREEN-HUD` |
| 07 | `TowerCurrentInfoHUD` | 塔楼/基地引导信息卡 | `src/world3d/TowerDescent3D.gd` | `L:1 / z:0` | 棱镜线框(无背板) | 纯展示 | 归属 HUD |
| 08 | `WorldDateTimeHUD` | 权威世界时间读数栏 | `src/world3d/TowerDescent3D.gd` | `L:1 / z:100` | 棱镜线框(无背板) | 纯展示 | 归属 HUD |
| 09 | `HudReloadRing` | 角色身侧换弹进度环 | `src/ui/HudReloadRing.gd` | `L:1 / z:0` | 战术矢量圆环 | 纯展示 | 归属 HUD |
| 10 | `EncounterCountdownRing` | 遭遇事件倒计时圆环 | `src/ui/EncounterCountdownRing.gd` | `L:1 / z:120` | 战术刻度圆环 | 纯展示 | 归属 HUD |
| 11 | `OffscreenEnemyIndicator3D` | 屏外激活怪物红箭头 | `src/ui/OffscreenEnemyIndicator3D.gd` | `L:1 / z:110` | 战术警示矢量 | 纯展示 | 归属 HUD |
| 12 | `BossHUD3D` | 首领战顶栏双层血条 | `src/world3d/Dungeon3D.gd` | `L:1 / z:210` | 棱镜线框(危险红线) | 纯展示 | 归属 HUD |
| 13 | `LowHealthVignette` | 濒死全屏暗红脉冲遮罩 | `src/world3d/Dungeon3D.gd` | `L:1 / z:220` | 氛围暗角遮罩 | 纯展示 | 归属 HUD |
| 14 | `DungeonMinimap3D` | 局部雷达小地图(后台态) | `src/ui/DungeonMinimap3D.gd` | `L:1 / z:105` | 矢量拓扑 | 纯展示 | `UI-WIDGET-MINIMAP` |
| 15 | `InteractionPromptPanel` | 交互按键上下文提示 | `src/world3d/Dungeon3D.gd` | `L:1 / z:0` | 棱镜线框(无背板) | 纯展示 | 归属 HUD |
| 16 | `ExtractionProgressPanel` | 撤离信标驻留读条栏 | `src/world3d/Dungeon3D.gd` | `L:1 / z:0` | 棱镜线框(无背板) | 纯展示 | 归属 HUD |
| 17 | `RunOutcomePanel` | 战局撤离/失败结算板 | `src/world3d/Dungeon3D.gd` | `L:1 / z:0` | 棱镜线框 | 已接入 | `UI-MODAL-EXTRACTION-RESULT` |
| 18 | `InventoryUI` | 棋盘式包裹与装备主界面 | `src/ui/InventoryUI.gd` | `L:1 / z:350` | 棱镜线框(**仅样式**) | 已接入 | `UI-SCREEN-INVENTORY-3D` |
| 19 | `ItemModelIcon3D` | 3D 物品实时正交图标组件 | `src/ui/ItemModelIcon3D.gd` | 子视口组件 | 3D 实物同源 | 组件级 | 待补录 |
| 20 | `WeaponPresentationPage3D` | K 键武器表现与构建树页 | `src/ui/WeaponAssemblyTreePanel.gd` | `L:1 / z:420` | 棱镜线框(双语) | 已接入 | 待补录 |
| 21 | `WorkbenchPanel` | 局内武器改造台（5×5 炼金盘） | `src/ui/WorkbenchPanel.gd` | `L:1 / 模态` | 棱镜线框(双语) | 已接入 | 待补录 |
| 22 | `MerchantUI` | 局内流浪拾荒商界面 | `src/ui/MerchantUI.gd` | `L:1 / 模态` | 棱镜线框 | 已接入 | `UI-MODAL-MERCHANT` |
| 23 | `DoorFateOverlay3D` | 门后命运塔罗三选一购卡 | `src/world3d/Dungeon3D.gd` | `L:1 / z:900` | 棱镜线框+塔罗贴图 | 完整焦点链 | `UI-MODAL-FATE-DRAW` |
| 24 | `FateSourceSelectionPanel` | 命运卡赋能目标选择框 | `src/ui/FateSourceSelectionPanel.gd` | `L:1 / z:910` | 棱镜线框+3D图标 | 数字键/焦点 | 待补录 |
| 25 | `FateCardFeedback` | 命运卡生效顶栏横幅 | `src/ui/FateCardFeedback.gd` | `L:1 / 浮层` | 棱镜线框(单线闪) | 纯展示 | 归属命运卡 |
| 26 | `ExploredFloorMapOverlay` | M 键全屏战术大地图 | `src/world3d/Dungeon3D.gd` | `L:1 / z:850` | 棱镜线框(矢量) | ESC/关闭钮 | 待补录 |
| 27 | `TowerElevatorOverlay` | 塔楼电梯选层面板 | `src/world3d/TowerDescent3D.gd` | `L:1 / z:0` | 棱镜线框 | `UiMenuFocus` | 待补录 |
| 28 | `InitialLoopRetreatWarning` | 98F 撤退回城确认框 | `src/world3d/TowerDescent3D.gd` | `L:1 / z:930` | 棱镜线框(警告琥珀) | 已接入 | 待补录 |
| 29 | `SegmentAirlockWarning` | 跨区段隔离间确认框 | `src/world3d/TowerDescent3D.gd` | `L:1 / z:960` | 棱镜线框 | 已接入 | 待补录 |
| 30 | `ExpeditionExitWarning` | 远征中途退出警告框 | `src/world3d/TowerDescent3D.gd` | `L:1 / z:930` | 棱镜线框(危险红) | 已接入 | 待补录 |
| 31 | `DeathConfirmationDialog` | 阵亡结算返回基地确认框 | `src/world3d/Dungeon3D.gd` | `L:1 / z:950` | 棱镜线框(危险红) | 自动抓焦点 | `UI-MODAL-DEATH-SETTLEMENT` |
| 32 | `PauseMenu3D` | ESC 暂停与画质/操作设置 | `src/ui/PauseMenu3D.gd` | 动态顶层 | 棱镜线框 | 完整支持 | `UI-SCREEN-PAUSE-3D` |
| 33 | `RogueMapSelectMenu` | 出发选关与 3D 全息沙盘 | `scenes/RogueMapSelectMenu.gd` | `L:100` | 棱镜线框+3D全息(**3D段不动**) | `UiMenuFocus` | `UI-SCREEN-LEVEL-SELECT` |
| 34 | `WardrobeMenu3D` | 基地 3D 角色衣柜换装 | `src/ui/wardrobe/WardrobeMenu3D.gd` | `L:120` | 棱镜线框+3D实景 | 已接入 | 待补录 |
| 35 | `VaultMenu` | 基地个人保险库(大仓库) | `src/ui/VaultMenu.gd` | `L:100` | 棱镜线框(**仅样式**) | `UiMenuFocus` | `UI-SCREEN-BASE-VAULT` |
| 36 | `BaseVendingMenu` | 基地自动售货机商店 | `src/ui/BaseVendingMenu.gd` | `L:100` | 棱镜线框(**仅样式**) | `UiMenuFocus` | 待补录 |
| 37 | `WorkshopMenu` | 基地枪械工坊界面 | `src/ui/WorkshopMenu.gd` | `L:100` | 棱镜线框(双语) | `UiMenuFocus` | `UI-SCREEN-BASE-WORKSHOP` |
| 38 | `BaseRecoveryMenu` | 基地状态恢复终端 | `src/ui/BaseRecoveryMenu.gd` | `L:100` | 棱镜线框 | `UiMenuFocus` | `UI-MODAL-BASE-RECOVERY` |
| 39 | `MonsterArchiveMenu` | 怪物生态图鉴界面 | `src/ui/MonsterArchiveMenu.gd` | `L:100` | 棱镜线框 | `UiMenuFocus` | `UI-SCREEN-MONSTER-ARCHIVE` |
| 40 | `FateCardCollectionMenu` | 命运塔罗牌组全图鉴 | `src/ui/FateCardCollectionMenu.gd` | `L:100` | 棱镜线框+塔罗图集 | `UiMenuFocus` | `UI-SCREEN-FATE-COLLECTION` |
| 41 | `DivinationMenu` | 基地塔罗占卜屋界面 | `src/ui/DivinationMenu.gd` | `L:100` | 棱镜线框 | `UiMenuFocus` | `UI-MODAL-DIVINATION` |
| 42 | `DialogueUI` | 底栏叙事打字机对话系统 | `src/ui/dialogue/DialogueUI.gd` | `L:100` | 棱镜线框底栏 | `UiMenuFocus` | `UI-OVERLAY-DIALOGUE` |
| 43 | `SpeechBubble3D` | 3D 角色头顶实景漫画气泡 | `src/ui/bubble/SpeechBubble3D.gd` | `3D Billboard` | 白底黑边漫画风 | 穿透不抢焦 | `UI-WORLD-SPEECH-BUBBLE` |
| 44 | `InteractionDot3D` | 3D 交互白点与读条环 | `src/ui/InteractionDot3D.gd` | `屏幕投影` | 极简呼吸白点 | 纯展示 | `UI-WORLD-INTERACTION-DOT` |
| 45 | `GroundLootPickup3D` | 地面掉落物悬浮名牌 | `src/world3d/GroundLootPickup3D.gd` | `3D Label3D` | 品质色高对比 | 纯展示 | `UI-WORLD-LOOT-LABEL` |
| 46 | `Enemy3D World UI` | 敌人头顶血条与警戒感叹号 | `src/world3d/Enemy3D.gd` | `3D Billboard` | 战术红/黄高对比 | 纯展示 | `UI-WORLD-ENEMY-STATUS` |
| 47 | `MobileInput` | 移动端虚拟双摇杆触控层 | `src/ui/MobileInput.gd` | `L:128` | 半透明矢量摇杆 | 触控专属 | `UI-OVERLAY-MOBILE-INPUT` |
| 48 | `TrainingFateBenchPanel` | 训练场命运卡与武器测试台 | `src/training3d/TrainingFateBenchPanel.gd` | `L:60` | 霓虹战术侧边栏 | 键鼠点选 | 测试专用 |

---

## 6. 后续 UI/UX 迭代路线图（Actionable Roadmap）

基于本次四维评估与全界面盘点，后续 UI/UX 工程按优先级推进以下 4 项收敛工作（**2026-10-17 状态已更新**）：

1. **P0 · 手柄焦点与快捷交互补齐**：
   - ~~为 `TowerElevatorOverlay`（电梯选层）与 `ExpeditionExitWarning`（远征退出确认）补齐 `UiMenuFocus.bind()`~~ → **前一项已修**：`TowerDescent3D._open_elevator_panel()` 现已补 `UiMenuFocus.ensure_focus(_elevator_overlay)`；`ExpeditionExitWarning` 与另两处确认框本就各自 `grab_focus()` 到取消钮（复核后速查表已更正）。
   - 在 `InventoryUI`、`VaultMenu`、`BaseVendingMenu` 中增加 `Shift + 左键` 快速跨容器转移物品与 `右键上下文菜单`。**（待做）**
2. **P1 · 视觉风格收编（消除“三代同堂”）** → **✅ 已完成（2026-10-17）**：
   - ~~MerchantUI 统一到柔和深蓝仓储风~~ → 实际做法改为**全部并入第三轨棱镜线框**（规范 §5.10）。柔和深蓝仓储风作为独立轨道**已取消**，其承载的包裹 / 装备 / 仓库改走窄口径工具并入棱镜（只改外观，布局与功能零改动）。
   - ~~`BaseRecoveryMenu` / `DivinationMenu` / `TowerElevatorOverlay` 接入 `apply_tactical_tree()` + `NeonFrameControl`~~ → `apply_tactical_tree` 已**无任何调用者**，禁止新增；这些界面已改走棱镜 `apply_prism_tree` + 模态外框四角括号。
   - **验收与取证（2026-10-17 完成）**：19 场景批次 12 通过 / 7 失败；把 34 个改动文件整体收起后对同一批 7 个失败场景重跑，得到**逐字一致的失败清单**；最终代码（含基地 HUD 修补）再跑一次，三项结果完全一致 ⇒ 0 回归（明细见规范 §8.1）。实机截图 20 张（编号 11–30）落在 `outputs/prism_ui_redesign_20261016/`，索引见规范 §9.3。
   - **本批实机揪出的一处静默漏改**：基地常驻 HUD 的收口因 `get_node_or_null("HUD") as Control`（`HUD` 实为 `CanvasLayer`）静默变空操作，代码看着改过、截图里还是旧卡片 —— 已修，并记入规范 §11。
3. **P1 · 基地二级菜单开闭动效与数字滚动**：
   - 在 `UIStyleFactory` 或 `UIFX` 中封装统一的 `open_modal_animated(panel)`（`0.14s` 缩放 `0.96 → 1.0` + Alpha 淡入），接入全部基地 `layer = 100` 菜单。
     现状：`UIFX.pop_in_modal` 已是统一口径（**刻意去回弹**，见规范 §6），各基地菜单已在接入。
   - 为金币与结算读数增加 `0.25s` 数字插值滚动反馈。**（待做）**
4. **P2 · UI 资产账本（`ShellStorm2_UI账本_v001.xlsx`）同步扩编**：
   - 按 `06-character-ledger` / `shellstorm2-asset-ledger-row-authoring` 规范，将上表中标注“待补录”的正式玩家可见界面（如 `BaseVendingMenu`、`WardrobeMenu3D`、`WeaponPresentationPage3D`、`ExpeditionLoadingScreen` 等）分批登记入库。**（待做）**
5. **P2 · 待清理死代码（本批遗留）**：
   - `src/ui/NeonFrameControl.gd` 已无调用者（`Dungeon3D` 侧 `_add_neon_frame` 与其常量均已删除）；
   - `UIStyleFactory.apply_tactical_tree()` 已无调用者，保留作历史对照。
     两者在下一轮清理窗口一并移除（见规范 §10.2 / §11）。
