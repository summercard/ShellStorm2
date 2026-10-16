# 《弹壳风暴2》UI 风格规范 · 棱镜线框（Prism Wireframe）

- **规范代号**：`PRISM-WIREFRAME`
- **冻结日期**：2026-10-16（第一批定标）/ 2026-10-17（第二批全站推广）
- **状态**：**生效中**（取代 `逃离鸭科夫UI风格对标参考与关键词库.md` 第 6 章提出的「深蓝圆角胶囊风」）；除业主明确划出的 4 项（包裹 / 装备 / 仓库 / 远征情报室 3D 全息城市，见 §10.1）外，**全站界面均已接管**
- **代码唯一真源**：
  - 色彩 Token → `src/ui/UIPalette.gd`（`PRISM_*` 段）
  - 样式工厂 → `src/ui/UIStyleFactory.gd`（`make_prism_*` / `apply_prism_*` / `attach_prism_*` / `prism_normalize_*` / `apply_prism_tree` 段）
  - 动效底座 → `src/ui/UIFX.gd`（`prism_stagger_in` / `prism_sweep` / `pop_in_modal` / `switch_page_fade`）
- **关联文档**：[UI与UX全局设计及全界面清单](UI与UX全局设计及全界面清单.md)、[逃离鸭科夫UI风格对标参考与关键词库](逃离鸭科夫UI风格对标参考与关键词库.md)（已降级为**素材参考库**）

---

## 0. 一句话定义

> **在明亮低多边形实景之上，只画白线与白字；不画卡片，不画渐变，不画辉光。**
> 结构感来自「贯穿细线 + 四角括号选框」，层级感来自「宽字距大写弱标签 / 近白大字强数值」的两级排印。

---

## 1. 风格定位与设计哲学

### 1.1 为什么是「线框」而不是「卡片」

上一轮（鸭科夫方向）走的是"磨砂深板岩色面板 + 圆角 + 内发光"的**实体容器**路线。它在俯视角、以背包为主体的游戏里成立，但在《弹壳风暴2》的**第一人称向下探索**语境下暴露出三个硬伤：

| 问题 | 表现 | 线框方案的解法 |
| --- | --- | --- |
| 遮挡实景 | 大块深色面板压住 3D 场景，玩家看不到身边动静 | 底衬 alpha 压到 `0.40~0.46`，且**大面积不加底衬**，只留线 |
| 视觉噪音 | 每块面板都带边框+圆角+投影，一屏四五个面板就"糊" | 取消面板边框与投影；**一屏只有一到两个"括号选框"**作为视觉重心 |
| 与美术气质打架 | 圆角软壳 vs 硬边低多边形建筑 | 全方角（radius `0~2`）、`0` 描边宽度的硬线；与场景的直线几何同构 |

### 1.2 三条不可违反的铁律

1. **不画实心卡片。** 任何区域都不得以"实色大矩形 + 四边完整边框"的形式出现。区域靠 **1px 白线** 或 **四角括号（L 形折角）** 界定，必要时叠一层 **alpha ≤ 0.50** 的极淡底衬。
2. **零辉光、零渐变、零投影堆叠。** 所有 `StyleBoxFlat` 的 `shadow_size` 一律为 `0`；禁止 `corner_radius > 2`；禁止线性/径向渐变。
3. **两级排印。** 同一屏内，信息只能是两类之一 —— **钢蓝小号弱标签**（大写 + 宽字距）或 **近白大字号强数值**。中间态（中灰、中等字号、无字距）视为违规。

---

## 2. 色彩系统（`UIPalette.PRISM_*`）

### 2.1 令牌全表

| Token | 值（RGBA） | 语义 | 典型用途 |
| --- | --- | --- | --- |
| `PRISM_DIM` | `(0.031, 0.055, 0.086, 0.58)` | 冷蓝压暗 | 模态层全屏遮罩（**不是纯黑**，保留实景冷调） |
| `PRISM_SURFACE` | `(0.055, 0.086, 0.129, 0.42)` | 极淡底衬 | HUD 卡、面板底层 |
| `PRISM_SURFACE_SOLID` | `(0.043, 0.071, 0.110, 0.72)` | 加厚底衬 | 模态面板、需要压过实景的层 |
| `PRISM_LINE` | `(1, 1, 1, 0.86)` | 主线 | 焦点括号、强调竖条 |
| `PRISM_LINE_SOFT` | `(1, 1, 1, 0.34)` | 次线 | 常驻 HUD 卡描边、贯穿细线 |
| `PRISM_LINE_FAINT` | `(1, 1, 1, 0.14)` | 弱线 | 分隔线、次要括号 |
| `PRISM_TEXT` | `(0.949, 0.965, 0.984)` | 近白正文 | 强数值、按钮字 |
| `PRISM_LABEL` | `(0.545, 0.643, 0.784)` | 钢蓝标签 | 小号弱标签（对应 `ARENA` / `THEME`） |
| `PRISM_TEXT_FAINT` | `(0.404, 0.482, 0.600)` | 极弱说明 | 提示行、脚注 |
| `PRISM_INK` | `(0.043, 0.071, 0.110)` | 深墨 | 实心白钮上的文字、白键帽上的字、勾选块上的对勾 |
| `PRISM_ACCENT` | `(0.310, 0.659, 1.0)` | 天蓝强调 | 进度条填充、激活态读数 |
| `PRISM_EPIC` | `(0.720, 0.545, 1.0)` | 史诗紫 | **稀有度专用**第二强调色（背包 / 图鉴 / 命运卡）。见 §5.10 D：稀有度是必须可区分的语义色，蓝紫同槽会让分级失效 |
| `PRISM_DANGER` | `(1.0, 0.420, 0.353)` | 平红危险 | 不可逆操作（`确认撤退` / `确认退出` / 复位存档） |
| `PRISM_WARN` | `(1.0, 0.741, 0.290)` | 琥珀警告 | 需要留意但非毁灭性的确认（`确认进入` 隔离间） |
| `PRISM_OK` | `(0.376, 0.878, 0.588)` | 青绿成功 | 成功态（**静止态不得使用**，避免"永远成功"的假象） |
| `PRISM_HP_RED` | `(0.925, 0.196, 0.227)` | 血量红 | 主 HUD 血条填充（满足验收契约 `r > 0.75 && g < 0.25`） |
| `PRISM_HP_BG` | `(0.086, 0.106, 0.137, 0.72)` | 血条槽 | 血条背景 |
| `PRISM_KEYCAP_BG` | `(0.949, 0.965, 0.984)` | 白方键帽底 | 快捷键提示块 |
| `PRISM_KEYCAP_TEXT` | `(0.043, 0.071, 0.110)` | 键帽深字 | 键帽文字 |
| `PRISM_PRIMARY_BG` | `(0.949, 0.965, 0.984)` | 主行动实心底 | 主行动钮静止态 |
| `PRISM_PRIMARY_BG_HOVER` | `(1, 1, 1)` | 主行动悬停 | 主行动钮悬停 |
| `PRISM_PRIMARY_BG_PRESS` | `(0.780, 0.816, 0.867)` | 主行动按下 | 主行动钮按下 |

### 2.2 色彩禁令

- **禁止纯黑**（`#000`）与**纯白**（`#FFF`）作为大面积底色。最暗处用 `PRISM_DIM`，最亮处用 `PRISM_PRIMARY_BG_HOVER`。
- **彩色只用于语义**（红=危险 / 琥珀=警告 / 青绿=成功 / 天蓝=强调），**不得作为装饰**。一屏内彩色面数建议 ≤ 2。
- **`PRISM_OK` 禁止作为静止态**。它只应出现在"刚刚成功"的瞬时反馈上。

---

## 3. 线条与括号（本风格的签名元素）

### 3.1 四角括号选框（Bracket Frame）

本风格**唯一**的"选中/界定"手段。由 `UIStyleFactory.attach_prism_bracket_frame(target, role, arm, thickness, inset)` 生成：
- 只画**四个 L 形折角**，不画边线中段；
- 折角臂长 `arm`：模态 `26~30`，HUD 卡 `12~16`，小件 `10~12`；
- 线宽 `thickness`：恒为 `2.0`（1px 在 1080p 下过细，会与底衬糊在一起）；
- 独立子 `Control`，`MOUSE_FILTER_IGNORE`，`move_child(frame, 0)` **置到最底层**，不抢输入、不遮文字、不参与布局计算。

**语义表（`role`）**

| role | 线色 | 用在哪 |
| --- | --- | --- |
| `solid` | `PRISM_LINE` | 焦点选框、模态外框、需要最强的界定 |
| `ghost` | `PRISM_LINE_SOFT` | 主菜单行、常驻 HUD 卡 |
| `faint` | `PRISM_LINE_FAINT` | 次要卡、可能长期存在的弱界定 |

悬停 / 聚焦时调 `set_prism_frame_highlight(target, true)` 提亮（**只改颜色，不改尺寸**，避免布局抖动）。

### 3.2 贯穿细线（Rule）

`make_prism_rule(color, thickness)` / `attach_prism_row_rule(btn, alpha)`。
参考图每一行选项的上沿都压一条贯穿细线 —— 这是"列表"这一结构在无卡片语言下的**唯一表达方式**。
- 主菜单行分隔线 alpha `0.22`；
- 触排插入时必须**从后往前**遍历，否则插入动作会挪动后续行的索引。

### 3.3 下折角（Chevron）

`make_prism_chevron(direction, color, box, thickness)` —— 自绘折角，用作"这里还有内容"的指示。
- 页头徽章正下方一枚 `⌄`（`_insert_prism_chevron_below`）；
- 方角箭头钮 `[◀]` / `[▶]`（`make_prism_arrow_button`）：白线方框 + 自绘折角，悬停/按下整体**反相**为白底深折角。

---

## 4. 排版规范

### 4.1 字体与字距

- 字体：`ThemeDB.fallback_font`（Godot 内置，**零外部字体依赖**）；
- 字距：`FontVariation.spacing_glyph`，经 `make_prism_font(spacing)` 带静态缓存生成。

> 实测（Godot 4.6.3）：`HIDDEN TEMPLE`（12 字母）加 `spacing_glyph = 2` 后宽度由 `189px` → `225px`。这是还原参考图"宽字距技术排印"的关键手段。

**字距档位表**

| 场景 | `spacing` |
| --- | --- |
| 主菜单行动行大字 | `5` |
| 模态标题 / 主行动钮 | `4~6` |
| 卡片强数值（关卡名、时间） | `2~3` |
| 弱标签（大写） | `3` |
| 说明 / 提示行 | `1` |

### 4.2 两级排印（Typographic Hierarchy）

| 级别 | Role | 字号 | 字重观感 | 对应参考图 |
| --- | --- | --- | --- | --- |
| **级一：强数值** | `value` | `19~26` | 近白、宽字距 | `HIDDEN TEMPLE` / `STRATOSPHERE` / `CONTINUE` |
| **级二：弱标签** | `label` | `12~13` | 钢蓝、大写、宽字距 | `ARENA` / `THEME` / `GAME MODE` |
| 辅助：说明 | `faint` | `11~12` | 极弱灰蓝 | 脚注 |
| 辅助：语义 | `accent` / `danger` / `warn` | `13~16` | 对应语义色 | 状态读数 |

### 4.3 深色徽章标题（Badge Header）

参考图左上 `NEW GAME` 的形态：**深色底 + 白字胶囊 + 右侧白色细延长线 + 正下方 `⌄` 下折角**。
实现要点（`make_prism_badge` / `make_prism_header`）：
- 复用 `Label` 自带的 `normal` StyleBox 作胶囊底 —— **不新增节点、不改动既有节点树**（这是保住验收契约的关键）；
- `size_flags_horizontal = SIZE_SHRINK_CENTER`，使胶囊贴合文字宽度而非撑满；
- 右侧延长线 `PrismHeaderLine` 为独立 `Control`，`SIZE_EXPAND_FILL` 吃掉剩余宽度。

---

## 5. 组件规范

### 5.1 按钮三型

| 型 | role | 视觉 | 用在哪 |
| --- | --- | --- | --- |
| **主行动** | `primary` | **实心近白底 + 深墨字**；放大、加大字距；外挂四角括号 | 当前默认焦点（`继续行动` / 取消类安全钮） |
| **次行动** | `ghost` | 透明底 + 白字 + 四角括号；悬停时括号提亮 | 主菜单其余行动行 |
| 弱次行动 | `muted` | 同 `ghost`，字色略压 | 低频入口 |
| **危险** | `danger` | 平红字 / 平红细框（`PRISM_DANGER`），**不填充** | 不可逆操作 |
| **警告** | `warn` | 琥珀细框（`PRISM_WARN`） | 需留意但非毁灭性 |
| 极弱 | `faint` | 弱线框 + `faint` 字 | 三级入口 |

**主菜单行式布局（本风格的标志性形态）**：
- 五条行动行**通栏、左对齐大字**，行与行之间由**上方贯穿细线**切开；
- 每行行尾一枚**白色方键帽**（`attach_prism_keycap`），骑在按钮右端 `PRESET_CENTER_RIGHT + 负偏移`，**不改按钮尺寸**；
- 主行动（`继续行动`）不填充，而是**四角括号选框** —— 靠括号表达"这是当前选框"，与参考图底部 `CONTINUE` 位同构。

### 5.2 白方键帽（Keycap）

`make_prism_keycap_badge(key_text, font_size, min_size)` —— 白底 `PRISM_KEYCAP_BG` + 深墨字 `PRISM_KEYCAP_TEXT` + radius `2`。
- 按钮文字里**不再写** `[Esc]` 这类字符（避免撑宽按钮、破坏验收的文本断言）；
- 键帽节点名必须以 `PrismKeycap` 开头，因为 `_prism_outline_exempt()` 靠它把键帽里的深色字排除在描边之外（否则会被描成一坨）。

### 5.3 方角勾选框（CheckButton）

`_prism_check_texture(checked)` 运行时生成 18px 贴图：
- 选中 = **实心白块 + 深墨对勾**；
- 未选 = **白线空框**；
- 零外部资源依赖。

### 5.4 细白线滑条（HSlider）

`apply_prism_slider(slider)`：
- 轨道 = `1px` 白线（`PRISM_LINE_SOFT`），填充 = 白（`0.92`）/ 提亮态 = `PRISM_ACCENT`；
- 把手 = 运行时生成的 14px **白方块**（悬停变天蓝方块），带深墨描边；
- **轨道粗细用 `content_margin` 定义，不用 `expand_margin` 负值** —— Godot 4 中 `expand_margin` 为负会**反向外扩**，会把细线渲染成粗带（已踩坑并修正）。

### 5.5 方角箭头钮（Arrow Button）

`make_prism_arrow_button(direction, box)` + `bind_prism_option_stepping(opt, prev, next)`。
用于 OptionButton 的"上/下一档"步进。**就地插入**到既有 HBox 里（新名字 `PrismPrev` / `PrismNext`），**不移动、不替换** `OptionButton` 本体。

> 注意：`Scroll/Grid` 里的两行是**半栏**（两列网格），塞进箭头会把网格最小宽度从 `890` 撑到 `1236`，直接顶穿 `972` 的面板内宽 —— 因此这两行**只做极简化、不加箭头**，且标签允许折行（`AUTOWRAP_WORD_SMART`），把最小宽度从 `285` 降到"最长词"，网格才能收进面板。

### 5.6 OptionButton / 数值框

- `apply_prism_option_button`：去底、去框，`arrow` 图标换成 `1×1` 全透明贴图（抹掉自带箭头），只留宽字距大写文字；
- `make_prism_value_box_style()`：白线方角数值框，用于滑条右侧读数。

### 5.7 模态确认弹窗（Confirm Modal）

`make_prism_confirm_modal(title, subtitle, detail, buttons_spec, accent, panel_size, dim_alpha)` 返回 `{overlay, dim, panel, box, buttons}`（**不入树**，由调用方 `add_child`）。

结构：
```
Dim (ColorRect, PRISM_DIM)      ← 全屏压暗，非纯黑
└ BracketFrame (四角括号)
  └ Margin
    └ Box (VBox)
      ├ PrismHeader   ← 深色徽章标题 + 副标题 + 延长线 + ⌄
      ├ PrismRule     ← 贯穿细线
      ├ DetailCard    ← 白线框 + 说明文字
      └ Buttons (HBox)← 主行动 + 危险/警告 两钮
```

**默认焦点铁律：安全侧永远是实心白主行动钮。**
- 撤退 / 退出 / 隔离确认：`取消类` = `primary`（实心白、默认焦点）+ 键帽 `ESC`；`确认类` = `danger` / `warn`；
- 死亡结算（无取消项）：唯一确认钮 = `primary`。

### 5.8 `Window` 系弹窗（`ConfirmationDialog` / `AcceptDialog`）

ESC 暂停页的「复位游戏存档二次确认」是 `ConfirmationDialog`（`reset_game_save_dialog`），属**独立子 Viewport**，
不走 `Control` 的样式体系 —— 只覆盖 `panel` 会留下系统灰底与圆角标题栏。统一走
`UIStyleFactory.apply_prism_window_chrome(win, title_font_size, title_height, body_font_size)`。

**关键坑（已踩并解决）**：Godot 对嵌入式 `Window` 会**同时**绘制 `panel`（内容矩形）与
`embedded_border`（含标题条的全窗矩形）。两者都带边框会得到"标题处一条线 + 内容处一个框"的**双线假象**。
因此：
- `panel` → **带 1px `PRISM_LINE_SOFT` 白线**的方角底衬（可见的那个框）；
- `embedded_border` / `embedded_unfocused_border` → **只留底色、不带边框**；
- `close` / `close_pressed` 图标 → `1×1` 全透明贴图（抹掉 ✕，取消钮已承担退出职责）；
- `title_*` → 近白 + 宽字距；
- `AcceptDialog.get_label()` → 改棱镜排印并居中。

**注意**：本引擎版本下 `title_height` **不改变**内容框从窗口顶边下移的距离，故标题稳定地浮在白线框正上方，
形成"带标签的线框"。这是可接受的观感，不必为此再加边框。

**必须保留的契约节点**：`ResetGameSaveDialog` 必须仍是 `ConfirmationDialog`（`verify_pause_game_save_reset_flow`
断言其类型、`visible` 语义与「对话框打开时 ESC 先取消」的行为），**不得替换为 `Control`**。

### 5.9 常驻 HUD：一律无背框（2026-10-17 定案）

**结论先行**：常驻 HUD（战局 / 塔楼）**不使用任何底衬、描边或四角括号**。所有面板外壳一律收敛到
`_make_bare_hud_style()`（全透明 `StyleBoxFlat`，只保留 `PanelContainer` 的布局职责）。

原因：主 HUD 直接压在实景上，任何半透明卡片都是实打实地吃视野（业主原话：「太占位置了」）。
四角括号在**菜单 / 弹窗**里成立（那里本来就有一层压暗，括号承担"选框"语义），但在 HUD 上
它会与实景的建筑边线互相干扰，反而更乱。

| 位置 | 节点 | 现状态 |
|---|---|---|
| 左上 | `HUD/ReferenceCombatHUD/PlayerStatusBlock` | 无背板；血条 / 电芯格属内容，保留 |
| 左下 | `HUD/ReferenceCombatHUD/CurrentInfoPanel` | 无背板（且默认 `visible = false`） |
| 右下 | `HUD/ReferenceCombatHUD/CurrentWeaponPanel` | 无背板 |
| 底部中 | `HUD/ReferenceCombatHUD/QuickItemHUD_0` / `_1` | 无背板 |
| 底部中 | `HUD/ExtractionPanel` | 外壳无背板；进度条本体（background + fill）保留 |
| 左中 | `HUD/TowerCurrentInfoHUD` | 无背板、无括号；**只留左侧 2px 白竖线** |
| 右上 | `HUD/ReferenceCombatHUD/WorldDateTimeHUD` | 无背板、无括号 |

**唯一保留的结构线**：`TowerCurrentInfoHUD` 左侧 `2px` 白竖线（`border_width_left = 2`、
`Color(1, 1, 1, 0.78)`）。它宽仅 2px、不成框，只用来表明"这几行属于同一段引导信息"。

**`_make_prism_hud_card_style` 的现状**：不再是 HUD 外壳的默认口径，只保留给 **HUD 内部的内容件**——
目前唯一调用点是电量电芯格（`_update_hud_battery`，未充能 alpha `0.14` / 已充能 `0.46`）。
它仍受 `clampf(alpha, 0.0, 0.50)` 约束，继续满足 `verify_finite_ammo_flow` 的 `bg_color.a <= 0.51` 契约。

**验收契约不受影响**：`bg_color.a = 0.0 <= 0.51` ✅；各面板的 `size` / `position` 由锚框决定，
与样式盒的 `content_margin` 无关（`_make_bare_hud_style()` 的 margin 同样是全 `0`）✅。

**HUD 文本可读性兜底**：`apply_prism_outline_recursive(root, 4.0, 0.62)` —— 白字在明亮实景（天台白地砖、云海天空）上会直接掉对比度，描边是唯一不破坏"无卡片"原则的解法。以下三类**豁免**（`_prism_outline_exempt`）：
1. `PrismKeycap*` 内的深色字；
2. `PauseOverlay` / `PrismConfirmModal`（自带压暗，不需要）；
3. 任何带 `ui_style_exempt` meta 的子树。

### 5.10 通用树皮与三个"窄口径"工具（第二批推广的核心器械）

第一批（10 个定标界面）是**逐个手改**的。第二批要覆盖几十个界面，其中还夹着
**只准改外观、绝不准动布局**的包裹 / 装备 / 仓库。逐个手改既不安全也追不完，
因此这一批的做法是**把口径收口到工厂函数**，再提供三档由宽到窄的工具。

#### A. 旧名工厂重定向（最宽刀，改一处全站生效）

以下"旧名"工厂**保留原签名与返回结构**，但产出一律是棱镜外观。它们是运行时
（拖拽高亮、悬停框、提示卡、结算弹窗……）构造样式的主要入口，逐调用点改写必然漏：

| 旧名工厂 | 现产出 |
| --- | --- |
| `make_panel_bg(level, r)` | `make_prism_surface(level >= 3)`（方角 2 / 1px 白线） |
| `make_panel_with_border(level, color, r, w)` | 同上 + `prism_normalize_color(color)`；**中性的结构线色不打成强调蓝**（`_is_neutral_line_color`），仍走 `PRISM_LINE_SOFT` |
| `make_button_style(fill, accent)` | 棱镜四态（`normal / hover / pressed / disabled` 键名不变）；`accent` 走归一化，**"出售/丢弃→danger、购买/金币→warn"的语义分工保留** |
| `make_progress_background()` / `make_progress_fill(color)` | `make_prism_progress_*`，颜色走归一化 |
| `make_tactical_panel(accent, …)` | `make_prism_panel`；**内容边距逐值沿用旧规格 `14 / 10`**（调用方按它摆内容） |
| `make_slot_style` / `make_slot_filled_style` / `make_inventory_surface` | 棱镜格子 / 底板（第一批已改）；**与旧版一样不设 `content_margin`** |
| `make_outline_label(text, color)` | 棱镜字体 + 归一化色；**投影改为真描边**（`font_outline_size`）——棱镜禁投影但允许描边（§4.4） |

> `content_margin` 刻意**不设**（保持 `StyleBoxFlat` 默认 `-1` ⇒ 生效值 = 边框宽度），
> 与旧实现同规格 —— **换皮不挪内容**。

#### B. `apply_prism_tree(root, opts)`（整棵树皮，最常用的那一档）

与旧的 `apply_tactical_tree` 对称，但走棱镜 Token。`opts` 支持
`button_role`（含 `"auto"` 语义推断）、`spacing`、`panel_alpha`、`panel_modal`、
`preserve_margins`、`skip_exempt`、`normalize_colors`。

- **面板不自动加括号**：批量树皮一律以 `"none"` 调 `apply_prism_button`。
  一屏几十圈括号会互相粘成乱线 —— 括号只给**唯一的那一个当前选框**（§3.1）。
  需要括号的模态外框（恢复菜单 / 商店 / 电梯面板）**显式**挂一处 `attach_prism_bracket_frame`。
- **Label 分支**：已有 `font_color` 走 `prism_normalize_color`（保留语义分工、收口调色板），
  没有色的按 `prism_label_role_for` 推断。
- **ColorRect 分支**：深色半透（`a > 0.45` 且 `max(r,g,b) < 0.20`）统一成 `PRISM_DIM`。
- `HSlider` 也在接管范围内（`apply_prism_slider`）—— 否则一块棱镜面板里会嵌着一条上一代圆角滑轨。

#### C. 窄口径工具（专供"只准改外观"的界面）

| 工具 | 口径 | 用在 |
| --- | --- | --- |
| `prism_normalize_label_colors(root)` | **只**改文字色与字体；不碰任何 StyleBox、不改尺寸。**只认 `ui_prism_exempt`，不认 `ui_style_exempt`** | 包裹 / 仓库；以及**运行时新建行**的面板（改装树、工坊统计行） |
| `prism_reskin_styleboxes(root)` | 只替换 `PanelContainer / Panel / ScrollContainer` 的 `panel` 条目；**不碰按钮 `normal/hover/pressed`**；原样继承 `content_margin` | 包裹 / 仓库 / 售货机 |
| `prism_normalize_color(Color)` | 把遗留硬编码色按**色相**归到棱镜语义槽（红→danger、金橙→warn、青绿→ok、青天蓝→accent、紫→`PRISM_EPIC`、近白→text、其余→label） | 所有归一化路径 |

> ⚠️ `ui_style_exempt` 与 `ui_prism_exempt` 必须分开：前者是历史标记
> （"别用旧战术树皮刷我"），背包 / 仓库 / 售货机都带着它；若 `prism_normalize_label_colors`
> 也认它，这三个界面就会被静默跳过 —— 这正是初版踩过的坑。

#### D. 新增色槽 `UIPalette.PRISM_EPIC`

`PRISM_EPIC = Color(0.720, 0.545, 1.0)`，**稀有度专用的第二强调色**。
棱镜调色板原本只有"天蓝强调"一个冷色槽，但稀有度（普通 / 稀有 / 史诗 / 传说 / 秘法）
是必须可区分的**语义色**，蓝与紫挤进同一槽会让背包与图鉴失去分级可读性。
它仍是语义色而非装饰色，一屏内继续受"彩色面数 ≤ 2"约束。

---

## 6. 动效规范

| 函数 | 参数 | 说明 |
| --- | --- | --- |
| `UIFX.pop_in_modal(node)` | `0.14s` / `0.985→1.0` / `TRANS_CUBIC` | **刻意去掉回弹** —— 棱镜界面是"切"出来的硬边几何，回弹会立刻回到上一轮的软壳观感 |
| `UIFX.switch_page_fade(node)` | `0.10s` 纯淡入 | 不做上浮位移（避免与容器布局打架） |
| `UIFX.prism_stagger_in(rows, step, duration)` | 默认 `0.035 / 0.16` | 行错峰入场，与参考图选项行"逐条落位"一致。**仅 tween `scale` + `modulate:a`，不碰 `position`** —— 放进任何 `Container` 都安全 |
| `UIFX.prism_sweep(node, duration)` | 默认 `0.32s` | 线扫强调：一条白线从左扫到右（标题条刷新、状态更新确认） |
| `UIFX.attach_button_press(btn, hover, press)` | — | 悬停 `1.014` / 按下 `0.988` |

**动效三条禁令**
1. **禁止回弹（`TRANS_BACK` / `TRANS_ELASTIC`）** —— 与硬边几何冲突。
2. **禁止位移入场** —— `Container` 会覆盖 `position`，一律用 `scale` + `alpha`。
3. **必须支持 `accessibility/reduce_motion` 降级** —— `prism_stagger_in` 已内置。

**错峰入场的挂载时机**：`_ready` 首次构建时控件尺寸还是 `0`，缩放轴心会跑偏。因此错峰必须挂在**"每次打开页面"**（如 `_show_main_page()`），而不是构建期。

---

## 7. 布局规范

### 7.1 屏幕构图（参考图三段式）

1. **顶部**：深色徽章大标题（左上或居中）+ 右侧延长线；
2. **中/左下**：菜单行 / 内容区，**左上区域优先**（不是屏幕正中 —— 参考图的菜单占据左上，给实景留出中心）；
3. **底部**：主行动四角括号选框 + 键帽。

### 7.2 暂停覆盖层实测参数

| 元素 | 值 |
| --- | --- |
| 面板 | `custom_minimum_size = Vector2(1040, 700)`，`make_prism_panel(true, 0.42)`（**不加外框**） |
| 主菜单行 | `custom_minimum_size.y = 52`，`size_flags_horizontal = SIZE_FILL`（通栏） |
| 主行动（继续行动） | `ghost` + `solid` 括号 + `arm 26` + 字号 `26` + 字距 `6` |
| 子页返回钮 | `ghost` + 键帽 `ESC`，文本须含「返回」（验收契约） |
| `AASection/AAOption` | 最小宽度须 ≥ `310`（验收契约），高度 `if < 46.0` 才抬到 `46`（**不得覆盖原 `custom_minimum_size.x`**） |

### 7.3 布局零回归策略

改皮**不得挪动一像素内容**：
- `make_prism_panel` 的 `content_margin` 恒为 `0`；
- **内容边距继承**（`_prism_adopt_content_margins`）：换皮时把**旧样式盒**的
  `content_margin` 逐边搬到新 `StyleBoxFlat` 上 —— 这是"只改外观不挪内容"的机器保证。
  `apply_prism_tree` 在 `preserve_margins = true`（默认）下对
  `PanelContainer / Panel / ScrollContainer / Button` 全部生效；
- 括号框是独立 `Control`，不参与布局计算；
- 键帽用 `PRESET_CENTER_RIGHT` + 负偏移"骑"在按钮上，不改按钮尺寸；
- 徽章复用 `Label` 的 `normal` StyleBox，不新增节点。

#### 7.3.1 "只准改样式"界面的验收口径

包裹 / 装备 / 仓库（`InventoryUI` / `ItemSlot` / `VaultMenu` / `BaseVendingMenu`）改皮后
必须仍然满足：

| 检查项 | 期望 |
| --- | --- |
| 格子数量 / 行列 / 落位 | **逐格不变**（等价于断言 `make_prism_slot_style()` 不设 `content_margin`） |
| 拖拽预检、占格判定、装备 / 拆分 / 丢弃 | **逻辑一行未动** |
| 储物 / 交易事务 | 走 `verify_backpack_equipment_flow` / `verify_grid_inventory_layout` / `verify_workshop_transaction_flow` 全绿 |

---

## 8. 验收契约守护清单（改造全程必须保持）

| 验收脚本 | 不可破坏的断言 |
| --- | --- |
| `verify_finite_ammo_flow` | 所有 gameplay HUD 面板 `panel.bg_color.a <= 0.51`；`CurrentWeaponPanel.size` ∈ `250..312 × 44..59`；`QuickItemHUD_0.size` ≤ `50×48`；`CurrentInfoPanel.position.x <= 20` 且 `.y >= 290`；节点路径 `HUD/ReferenceCombatHUD`、`CurrentInfoPanel`、`CurrentWeaponPanel`、`QuickItemHUD_0` |
| `verify_graphics_settings_ui_flow` | `GraphicsPage/Header/RendererLabel`；`AASection/AAOption`（6 项）；`Scroll/Grid`（10 子节点，除 `Shadows`/`IndirectDiffuse` 外都是 `CheckButton`）；`Shadows/ShadowOption`（3 项）；`IndirectDiffuse/QualityOption`（3 项）；`Footer/BackButton` 文本含「返回」；`PerformanceOverlay/Metrics` 含 FPS / Draw Call / 渲染器；`_show_graphics_page()` / `try_consume_pause_input()` 行为 |
| `verify_pause_game_save_reset_flow` | `ResetGameSaveButton` 存在；点击打开 `ResetGameSaveDialog`；对话框打开时 `ESC` 先取消 |
| `verify_pause_menu_training_range_entry` | 训练靶场入口可用 |
| `verify_gamepad_input_flow` | 13 组手柄绑定；**每个设施菜单打开时有焦点锚点** |
| `verify_expedition_level01_flow` | `HUD/ExpeditionExitWarning` 存在；`HUD/InitialLoopRetreatWarning` **不存在**；按钮文本须含「确认退出」 |
| `verify_arrival_gate_floor_bundle_flow` | `tower.get("_initial_loop_retreat_overlay") != null` |
| `verify_expedition_monitor_boss_flow` | Boss 血条外壳 `bg_color.a == 0` |
| `verify_tactical_inventory_minimap_flow` | 主 HUD 血条 `fill.bg_color.r > 0.75` 且 `.g < 0.25` |

> **注**：`verify_arrival_gate_floor_bundle_flow` 与 `verify_expedition_level01_flow` 目前存在**既有失败**（门碰撞事务链、怪物掉落表行数 16 vs 13）。已用 HEAD 版本做基线对照，**未改版时同样失败**，确认与 UI 改造无因果关系。

### 8.1 第二批的 A/B 基线对照（2026-10-17）

第二批改完后跑 19 场景批次，结果 **12 通过 / 7 失败**。为区分「本次引入」与「既有」，
把本次改动的 **34 个文件整体 `git stash` 收起**（工作区回到未改造状态），对**同一批 7 个失败场景**
再跑一遍，得到逐字一致的失败清单：

| 场景 | 改造后退出码 | 基线退出码 | 结论 |
| --- | --- | --- | --- |
| `verify_backpack_equipment_flow` | 1 | 1 | 既有（艺术品检：材质名 / 三角预算） |
| `verify_finite_ammo_flow` | 3 | 3 | 既有（dummy 渲染器 `Parameter "material" is null.`） |
| `verify_gamepad_input_flow` | 3 | 3 | 同上 |
| `verify_tactical_inventory_minimap_flow` | 1 | 1 | 既有（格子拖拽所有权断言 + dummy 渲染器报错） |
| `verify_main_entry_cinematic_flow` | 1 | 1 | 既有（该场景要求 `ShellStorm2Verification_` 隔离目录，非套件内跑必拒） |
| `verify_training_range_equipment_ui` | 3 | 3 | 既有（同上 dummy 渲染器报错） |
| `verify_tower_facility_inventory_binding` | 1 | 1 | 既有（断言 `"2 / 12"` 带空格，源码格式是 `"2/12"`；且按已退役类名 `BaseStorageSlot` 计数） |

另外把两个基线日志做了逐字节 diff（`base_verify_tactical_inventory_minimap_flow.log` vs 改造后同名日志），
**只差内存地址**（`<RefCounted#-9223...>` / `<Control#...>`），错误行完全一致。

**结论：7 项失败全部为既有问题，棱镜改造引入的回归为 0。**

> 增量注记：`verify_tower_facility_inventory_binding` 与 `verify_base_vending_visual` 里那两条
> 「保险柜格子未完整生成」断言，都是按 `find_children("*", "BaseStorageSlot")` 计数的 ——
> 该类名在全仓已无任何节点使用（`VaultMenu` 走 `StorageBoardView`），断言本身已失效。

---

## 9. 已落地界面（两批）

### 9.1 第一批：定标样板（2026-10-16 / 10-17 冻结）

| # | 界面 | 实现位置 | 截图 |
| --- | --- | --- | --- |
| 1 | 战局常驻 HUD | `Dungeon3D._install_holographic_hud_style()` / `_build_reference_main_hud()` | `01_战局常驻HUD_棱镜线框.png` |
| 2 | ESC 暂停主菜单 | `PauseMenu3D._style_prism_main_page()` | `02_ESC暂停主菜单_棱镜线框.png` |
| 3 | ESC 画面设置子页 | `PauseMenu3D._style_prism_graphics_page()` | `03_ESC画面设置子页面_棱镜线框.png` |
| 4 | ESC 操作设置子页 | `PauseMenu3D._style_prism_controls_page()` | `04_ESC操作设置子页面_棱镜线框.png` |
| 5 | ESC 复位存档二次确认 | `PauseMenu3D._style_prism_reset_dialog()` | `05_ESC复位存档二次确认_棱镜线框.png` |
| 6 | 死亡后结算弹窗 | `Dungeon3D._show_death_confirmation_dialog()` | `06_死亡后结算确认弹窗_棱镜线框.png` |
| 7 | 塔楼与基地常驻 HUD | `TowerDescent3D._install_tower_hud()` / `_install_world_time_hud()` | `07_塔楼与基地常驻HUD_棱镜线框.png` |
| 8 | 98F 安全屋撤退确认 | `TowerDescent3D._show_initial_loop_retreat_warning()` | `08_98F安全屋撤离确认弹窗_棱镜线框.png` |
| 9 | 远征退出确认 | `TowerDescent3D._show_expedition_exit_warning()` | `09_远征退出确认弹窗_棱镜线框.png` |
| 10 | 跨段隔离确认 | `TowerDescent3D._show_airlock_warning()` | `10_跨段隔离确认弹窗_棱镜线框.png` |

截图目录：`outputs/prism_ui_redesign_20261016/`

### 9.2 第二批：全站推广（2026-10-17）

做法见 §5.10 —— **把口径收口到工厂函数 + 三档窄口径工具**，而不是逐界面手改。

| 分组 | 界面 / 文件 | 改动要点 |
| --- | --- | --- |
| **开始游戏主界面** | `MainEntryScreen3D.gd`、`EntryNeonButton.gd`、`EntryBrand.gd`、`scenes/ui/MainEntryScreen3D.tscn` | 六边斜切 + 呼吸霓虹光晕 + 流光扫线 → **棱镜双型自绘按钮**：`StartButton` = 实心近白主行动（深墨字），`SettingsButton` = 透明底 + 八段 L 形角括号的次行动。品牌标题改近白字标 + 天蓝「2」+ 贯穿细线 + 左侧 2px 竖线。**节点路径与 `pressed` 契约不变** |
| **99F 基地设施菜单** | `BaseRecoveryMenu`、`BaseMenu`、`DivinationMenu`、`FateCardCollectionMenu`、`MonsterArchiveMenu`、`MerchantUI`、`WorkshopMenu`、`wardrobe/WardrobeMenu3D` | 整棵树皮 + 模态外框挂一处四角括号；精英档案行按状态给 `PRISM_DANGER` / `PRISM_ACCENT` / 白线 |
| **受约束界面（只改样式）** | `InventoryUI`、`ItemSlot`、`VaultMenu`、`BaseVendingMenu` | `prism_reskin_styleboxes` + `prism_normalize_label_colors`；`ItemSlot` 的拖拽浮层单独上棱镜。**格子 / 布局 / 拖拽 / 交易逻辑一行未动**（§7.3.1） |
| **武器构建** | `WorkbenchPanel`、`WeaponAssemblyTreePanel` | 树皮 + 运行时新建行（树行、统计行）在重建后补窄口径收口；行高亮由"3px 圆角框 + 色带"改 1px 白线 + 归一化淡色带 |
| **局内弹窗与全屏层** | `Dungeon3D`（HUD 弹层 / 模态关闭钮 / 全屏地图 / 塔罗卡背 / 卡反馈）、`TowerDescent3D._open_elevator_panel()` | `_make_hud_style` 保持 `a <= 0.50`；删掉两处 `_add_neon_frame` 调用并**删除该函数与 `NEON_FRAME_SCRIPT` 常量**；塔罗卡背单开一块不透明棱镜板（不受 HUD 半透契约约束）；`FateCardFeedback` 由"三层粗描边叠加"改**单线 1px**（闪的瞬间 2px） |
| **启动流与对话** | `StartupLoadingScreen`、`OpeningMovieScreen3D`、`ExpeditionLoadingScreen`、`dialogue/DialogueUI` | 启动壳/读取页：深墨底 + 白线 + 棱镜进度槽；读取页波浪 `LOADING` 改用**同一个字体对象**量宽（否则棱镜字距会让字母挤在一起）；开场影片保留描边（压在活动画面上）；叙事底栏面板 + 三级排印 |
| **开发者层** | `PerformanceOverlay`、`player3d/FlashlightColorTweaker` | FPS 三档语义色改 `PRISM_OK/WARN/DANGER`；撤掉文字投影（改由面板底衬保可读性）；**滑条纳入 `apply_prism_tree`** |

**开工前需读的坑**（第二批踩到的）：
1. 旧样式盒换成棱镜后 `content_margin` 会从 `-1`（生效值 = 边框宽度）变成 `0`，
   差 1px 就可能挤动密排格子 —— 因此**一律不设 `content_margin`**，或走 `_prism_adopt_content_margins` 继承（§7.3）。
2. `ui_style_exempt` ≠ `ui_prism_exempt`（§5.10 C 的警告框）。
3. 批量树皮必须传 `"none"` 括号，否则一屏括号粘成乱线。
4. 运行时新建的行 / 浮层（拖拽预览、树行、统计行）**不会**被 `_ready` 那一次树皮覆盖，
   必须在对应的 `_refresh_*()` 末尾补一次收口 —— 拖拽浮层是 `set_drag_preview` 的独立节点，连子树都不在，只能就地改。

### 9.3 第二批实机取证（20 张，接第一批编号 11–30）

同目录 `outputs/prism_ui_redesign_20261016/`：

| # | 界面 | 冻结要点 |
| --- | --- | --- |
| 11 | 开始游戏界面（两个按钮） | `开始游戏` = 实心近白主行动；`设置` = 透明底 + 八段 L 形角括号的次行动 |
| 12 | 开始界面设置面板 | 从首页第二个按钮按进去的 `PauseMenu3D`（深色徽章 + 贯穿细线 + 白方键帽） |
| 13 | 冷启动加载页 | 深墨底 + 顶部 1px 次级白线 + 棱镜进度槽（唯一保留的"面"是填充条） |
| 14 | 装备 · 背包 · 仓库 | **受约束界面**：只换皮，格子数 / 网格列数 / 拖拽 / 交易逻辑一行未动 |
| 15 | 仓库格子 | 同上，`VaultMenu` 双列 5×2 方格 |
| 16 | 贩卖机 | 购买 = 实心主行动、出售 = 平红危险（不填充）；容量读数沿用旧格式 |
| 17 | 战术背包与地图 | 局内背包覆盖层，格子与保险格 |
| 18 | 战术小地图 HUD | 压在地图上，**无背框**，只留文字与细线 |
| 19 | 衣柜 | 设施菜单，整棵树皮 + 模态外框一处括号 |
| 20 | 基地常驻 HUD | 场景里三个 8px 圆角卡片换成**无背框**文字 + 描边（§5.9） |
| 21 | 战局战斗 HUD | 第一批判定过的基准，本批复核未回退 |
| 22 | 塔楼常驻 HUD | 同上 |
| 23 | ESC 画面设置子页 | 本批复核未回退 |
| 24 | 性能监控面板 | FPS 三档语义色；撤投影改底衬 + 描边 |
| 25 | 工坊 | `apply_prism_tree` 整棵树皮 |
| 26 | 命运卡图鉴 | 同上；稀有度分色走 `PRISM_ACCENT` / `PRISM_EPIC` |
| 27 | 占卜台（三选一） | 同上；卡面保留插画（内容件），卡框与"当前选框"用括号 |
| 28 | 怪物档案 | 同上；精英行按状态给 `PRISM_DANGER` / `PRISM_ACCENT` / 白线 |
| 29 | 基地回收站 | **本屏唯一一处四角括号**（模态外框，§3.1） |
| 30 | 保险柜（独立入口） | 受约束界面复核：只换皮，双列方格与交易逻辑零改动 |

> 25–30 这六张是用 `_scratch/prism_capture_menus.tscn`（临时脚本，已删）直接
> 把六个菜单场景盖在基地实景上抓的 —— 它们**没有专属视觉验收场景**，
> 而本批吃过"代码改过、实机没生效"的亏，所以必须人工补一次取证。

> **取证方式的坑**：`run_verification_suite.sh` 每轮要在工程外整份复制 `.godot` 导入缓存，
> 本轮在 `--import` 阶段卡住不动（编辑器同时开着、缓存冷启动）。改为**直接在真实工程上跑窗口渲染**，
> 用工程根放一份 `override.cfg`（`application/config/use_custom_user_dir_name`）把 `user://`
> 重定向到 `ShellStorm2Verification_PrismCapture`，既绕开 5 GB 工作区，又**完全不碰业主真实存档**；
> 取证结束必须删掉该文件（已验证它会同时影响编辑器的运行）。
> 另有三个视觉场景不写 `res://outputs/`：`verify_inventory_experience_visual` 认 `INVENTORY_QA_OUTPUT`、
> `verify_reference_hud_fate_visual` 认 `SHELLSTORM_VERIFICATION_OUTPUT`，不传环境变量就会静默丢图。

---

## 10. 本批的边界与未接管项

### 10.1 业主明确划出、**不得改动**的部分

| 项 | 说明 |
| --- | --- |
| 包裹界面 | 布局与功能**绝对不动**，只改样式（§7.3.1） |
| 装备界面 | 同上 |
| 仓库界面（`VaultMenu`） | 同上 |
| 远征情报室的 3D 动态界面 | `RogueMapSelectMenu` / `HologramCity3D`（`mission_operations` 设施的 3D 全息城市）**不动**。实测该脚本除 `env.background_color` 外无任何 2D UI 样式，天然满足 |

### 10.2 仍未接管

| 项 | 现状 |
| --- | --- |
| `IrisTransition` | 黑白光圈过场，本身无 UI 元素（纯遮罩），**无需改造** |
| `NeonFrameControl.gd` | 已无任何调用者（`Dungeon3D` 侧已删）。文件保留但属**待删死代码**，见 §11 |
| `apply_tactical_tree` | 已无任何调用者。保留作为历史对照，**禁止新增调用** |

### 10.3 推广时的标准动作

1. 保留节点路径与 `signal` 不动（验收契约见 §8）；
2. 调 `apply_prism_label` 统一排印；
3. **区分"菜单"与"HUD"两条口径**：
   - **HUD（压在实景上）**：外壳一律 `_make_bare_hud_style()`，**不画底衬、不画边框、不加括号**（见 §5.9）；
   - **菜单 / 弹窗（自带压暗层）**：用 `make_prism_panel` + `attach_prism_bracket_frame` 界定区域；
4. 按钮走 `apply_prism_button`；
5. 模态走 `make_prism_confirm_modal`；
6. 动效统一走 `UIFX` 棱镜档；
7. 带格子 / 空间逻辑的界面走 §5.10 C 的窄口径工具，**不要上整棵树皮**。

---

## 11. 反面清单（改版时必须删除的遗留）

- 所有 `DUCKOV_*` 色彩 Token（深板岩灰蓝、暖橙激活、导航青）；
- `make_duckov_*` / `apply_duckov_*` 系列工厂函数；
- `_apply_duckov_pause_style` / `_make_duckov_hud_card_style`；
- **45° 斜纹警戒分节条**（`make_duckov_section_header` 及斜纹贴图）；
- `8~12px` 圆角、内发光渐变、彩色发光描边、`shadow_size > 0` 的卡片；
- **常驻 HUD 上的卡片背板与四角括号**（2026-10-17 业主否决：太占视野）——
  HUD 只允许**文字 + 细线 + 内容件**；唯一例外是 `TowerCurrentInfoHUD` 的 2px 左侧引导竖线；
- 恢复性回弹动效（`TRANS_BACK`）；
- 面板纯黑底（`#000`）；
- **`_add_neon_frame` 及 `NEON_FRAME_SCRIPT`**（2026-10-17 已从 `Dungeon3D` 删除；
  `NeonFrameControl.gd` 本体已无调用者，属待删死代码）；
- **文字投影**（`shadow_offset_x/y` + `font_shadow_color` 的假描边）——
  棱镜禁投影；HUD 需要可读性时用 `font_outline_size` 真描边替代；
- **一屏多个四角括号**（批量树皮一律 `"none"`）；
- **把 `CanvasLayer` 当 `Control` 取**（`get_node_or_null("HUD") as Control`）——
  `HUD` / `PauseOverlay` / 各个设施菜单根都是 `CanvasLayer`，转型会**静默返回 `null`**，
  后面的收口整段变成空操作，而且不报任何错。2026-10-17 基地常驻 HUD 就是这么漏掉的：
  截图里还是 8px 圆角旧卡片，代码看着却"改过了"。凡是按路径取节点的收口，
  **必须用截图复核**，不要只看代码；
- **指望 `apply_prism_outline_recursive(root, …)` 给 `root` 自己加描边** ——
  它内部是 `find_children("*", …)`，**只扫后代**。传进去的是裸 Label 时得就地补。
