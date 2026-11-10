# 对话文字统一底栏 + 头顶说话示意框（2026-11-10）

功能ID：`DIALOGUE-UI`、`NARRATIVE-TRIGGER`、`BASE-NPC`。工程版本 `0.1.0`。

## 1. 业主原话与范围

> 「头顶对话框那个东西太挡角色了。接下来帮我进行调整。我要把头顶对话框只做成说话示意的样子，就是说话的时候固定跳出一个对话框的样子，有点点点的动画。但是真实文字在下方的原来系统对话的那个地方，以后所有对话和系统信息统一在那边。该保留的按钮快速过的功能一并到那去。大小可以小一点，不用原来这么大。参考这个范围，但是字体要能看得清。不要太小了，就用原来的字体和大小。制作前同样先看相关文档和账本，在已有框架下调整。完成后更新设计文档和账本。」

追加：

> 「头顶气泡的说话，还是要保留，在电灯开光，这类自言自语的时候，需要保留。对话变成新的。」

据此冻结的判据（**这是本轮最容易做错的地方**）：

| 语义 | 头顶 | 文字 |
|---|---|---|
| **对话**（剧情台词、Boss 对白、节拍提醒、按 E 交谈、死亡归航） | 示意框（小、固定、三点跳动、无文字） | 底栏字幕 + 说话人署名 |
| **自言自语**（开灯/关灯等 bark 短句） | 原文字气泡（尺寸随字数、打字机） | 同气泡 |
| 系统 / 旁白 | 无 | 底栏字幕（署名“系统”） |

## 2. 根因

改前 `actor.say` 一律把文字写进头顶 `SpeechBubble3D`，尺寸随字数自适应。绿苔身高 1.215 m，一句 20 字台词排成两行后气泡 **4.7 m 宽**，在世界里压在角色头上，投影到屏幕上会糊住半个身子 —— 这就是业主说的“太挡角色”。

同时底栏早已具备打字机、两段快进（空格 / 鼠标左键 / 回车）、三态 outcome，能力是完整的，只是**没被对话使用**。

## 3. 改动（按层）

### 3.1 气泡层：两个互斥形态

`src/ui/bubble/SpeechBubble3D.gd`

- 新增 `say_indicator(hold)`：固定 **0.86×0.46 m** 圆角框 + 底边小三角，内含 **3 个低面数球**（半径 0.05 m），相位差 0.72 rad、正弦上下 0.03 m、波谷变暗。
- 几何复用既有 `_border_band_arrays/_fill_arrays`，**不新增贴图、不新增 shader**。
- 示意态下 `_label.visible=false`、`_full_text=""`，`get_bubble_text()` 返回空串 —— 文字不产生第二份。
- `say()` 会先 `_set_indicator_off()`，`say_indicator()` 会隐藏 Label3D：两态互斥，不会叠着显示。
- 新增 `get_indicator_snapshot()`：`dot_count / dot_radius_m / panel_width_m / panel_height_m / has_tail / label_visible / text_chars`。

**踩坑记录**：`_relayout_indicator()` 第一版把半宽写成 `INDICATOR_WIDTH_M * 0.5 / unit`（多除了一次 `pixel_size`），实测框宽 **156 m**；改为直接给米后回到 0.86 m。归类断言“示意框宽必须在 0.5~1.3 m”正是为了钉住这一次。

### 3.2 挂载层

`src/ui/bubble/CharacterBark3D.gd`

- `say_text()` / `say_bark()` / `say_bark_at()` 前统一调 `_restore_text_height()`（回到 `head_height`），保证自言自语走旧口径。
- 新增 `say_indicator(hold, height)`：默认挂高 `indicator_head_height = 1.86 m`。**不能沿用 `head_height=3.40`** —— 那个值是按两行大字气泡（高 1.21 m）算的，小框挂 3.40 会飘在半空。

`src/world3d/Dungeon3D.gd`：玩家 bark 的 `indicator_head_height` 设为 `PLAYER_BARK_HEIGHT_M=2.55`（新建与复用两条路径都设，避免被 NPC 默认值影响）。

### 3.3 底栏层

`src/ui/dialogue/DialogueUI.gd`

- 宽度由固定 `MARGIN_SIDE=96`（1080 下 82%）改为 **`PANEL_SIDE_RATIO=0.15`**（视口 70%，左右各 15%），贴底 24 px、高 118 px。用 anchor 比例而非像素，换分辨率不变形。
- **字号一个没改**：正文 19 / 署名 15 / 提示 13（业主：「就用原来的字体和大小」）。
- 新增 `show_dialogue_line(text, speaker, auto_sec)` 与 `line_hold_for_text()`（`clamp(1.4 + 字数/12, 1.8, 5.0)`）；新增 `SPEAKER_PLAYER := "主角"`。

### 3.4 NPC 层：对话收口在一个出口

`src/npc/NpcCharacter3D.gd`

- 新增 `_present_dialogue(text, auto_sec)`：`_bark.say_indicator(...)` + `DialogueUI.show_dialogue_line(...)`，署名取 `get_display_name()`。
- **三条内部路径全部改走它**：节拍提醒 `_say_story_line()`、自由交谈 `advance_dialogue()`、演出台词 `say_scripted_line()`。只在 Adapter 接会漏掉前两条。
- `is_speaking()` 改判底栏 run（`_dialogue_run`）：节拍逐句轮播与救援等待循环靠它判断“这句完了没”，必须指向真正的文字载体。
- `dialogue_finished` 回来时只收**自己那条 run** 的示意框并隐藏气泡；底栏是全局单例，可能已被别人顶掉。
- `advance_scripted_line()` / `advance_free_bark()` / `perform_interaction()` 的进度判断改读底栏（`is_typing/reveal_all/finish_current_hold`）。
- 明确保留：`say_bark()`（开灯等）**不走** `_present_dialogue`，仍写头顶文字气泡。

### 3.5 剧情适配层

`src/narrative/NarrativeAdapter3D.gd`

- 新增 `_say_dialogue_on_actor(actor, who, text, hold)`：NPC 走 `say_scripted_line`（由它自己收口三处）；player 或无此方法的演员走 `CharacterBark3D.say_indicator` + `DialogueUI.show_dialogue_line`。
- `_actor_say()` 收口为调它一次；载体句柄由 `bubble` 改为 `subtitle`（指向底栏 run），`_bind_dialogue_carrier(..., "subtitle", text, run_id)`。

`src/narrative/NarrativeDirector3D.gd`

- `_advance_bottom_dialogue()`：无时间轴时**先**查救援演出、再查自由交谈，最后才 `advance_dialogue()`。否则底栏会先就地换行，演出/交谈的指针不动（表现为“第一下全显、第二下没反应”）。
- `can_advance_mouse_dialogue()` / `advance_mouse_dialogue()` 去掉 `if DialogueUI.is_active(): return false` 早退：救援与自由交谈现在也经底栏，早退会把左键漏给开火。

### 3.6 快捷推进

未新增任何按键路径。底栏既有的两段语义天然覆盖对话：**打字中按一下（空格/左键/回车）→ 当前句全显；已全显再按 → 下一句**。示意框不参与推进，也不阻断。

## 4. 验收

### 4.1 生产实现（隔离 APPDATA/LOCALAPPDATA，headless）

| 项 | 结果 | 证据 |
|---|---|---|
| 气泡专项（含 17 条新示意断言） | `checks=98`，exit 0 | `probes/dialogue_bottom_bar/bubble4/` |
| 底栏专项（含布局 + 对话句 + 停留时长 13 条新断言） | `checks=34`，exit 0 | `probes/dialogue_bottom_bar/flow2/` |
| 空格快进 | `checks=44`，`failures=[]`，exit 0 | `probes/dialogue_space_today/` |
| 鼠标快进 | `checks=51`，`failures=[]`，exit 0 | `probes/dialogue_mouse_today/` |
| 鼠标恢复（失焦/丢释放/暂停） | `base=51 added=28`，exit 0 | `probes/dialogue_mouse_recovery_today/` |
| 叙事时间轴（113 项旧断言） | `checks=113`，exit 0 | `probes/dialogue_bottom_bar/verify_narrative_timeline_v3/` |
| 基地救援演出 | exit 0（R15/R17 已改为断言“气泡无字 + 底栏有字”） | `probes/dialogue_bottom_bar/rescue_v4/` |
| 基地 NPC 主流程 | exit 0（A24b 判据已反转为“示意框 0.5~1.3 m + 底栏 70% + 正文字号 ≥19”） | `probes/dialogue_bottom_bar/npcflow2/` |
| 基地 NPC 节拍 | exit 0 | `probes/dialogue_bottom_bar/npcbeat/` |

### 4.2 验收代码的同步修正（不是“改测试让它变绿”）

改的是**判据方向**，因为业主的规则变了：

- `verify_narrative_timeline`：假体 `FakeBark` 只收 `say_text`，而 `actor.say` 已不再走气泡 ⇒ 台词顺序改从 `DialogueUI.dialogue_shown` 收集，并**按署名过滤掉系统提示**（`ui.hint` 也会进底栏，那不是角色台词）。
- `verify_base99_rescue` R15/R17：由“气泡打字 + 气泡文本”改为“底栏打字 + 底栏署名 + 示意框无字且 <1.3 m”。
- `verify_base99_rescue` R17 第三条：**去掉相位数值比较**。相位是演出自己的时间函数，推进让下一句更早开始，演出本来就更早走完（实测 1.00→0.89，跨过旧阈值 0.05）；继续拿数值当判据会把正常推进误判成“提前扶起”。改守三条真判据：阶段仍是 `cutscene`、`input_locked` 仍真、倒地姿态仍 active。
- `verify_base_npc_flow` A24b：由“气泡 ≥3 m”反转为“示意框 0.5~1.3 m + 底栏 anchor 0.15/0.85 + 正文字号 ≥19”。这三条正是业主“小一点但字不能小”的可执行形式。
- `verify_dialogue_space/mouse_fast_forward`：角色台词的进度断言由气泡改读底栏。
- `capture_main_story_chapter` / `verify_base_npc_story_beat`：台词取样由气泡改读底栏。
- `verify_speech_bubble_3d` 新增 `_check_indicator`：三点数量、无文字、尺寸区间、三点相位差 >4 mm（防“整体平移冒充跳动”）、切回 `say()` 后 Label 恢复可见。

### 4.3 主线章节（真渲染 + 专项）

见 §5「本轮复跑结果」。

## 5. 本轮复跑结果

### 5.1 主线章节（真渲染 + 专项）

| 项 | 结果 | 证据 |
|---|---|---|
| 3.1 原生 Forward+ | `checks=34 failures=[]`，exit 0，自然退出 | `outputs/2026-11-10_dialogue_bottom_bar/visual/031/` |
| 3.2 原生 Forward+ | `checks=43 failures=[]`，exit 0，自然退出（303.9s） | `outputs/2026-11-10_dialogue_bottom_bar/visual_032/032/` |
| 3.3 原生 Forward+ | `checks=27 failures=[]`，exit 0，自然退出 | `outputs/2026-11-10_dialogue_bottom_bar/visual/033/` |
| 主线实体表演 | `checks=52 failures=0`，exit 0 | `outputs/2026-11-10_dialogue_bottom_bar/visual/performance/` |
| 主线叙事 基地 / Boss | `checks=328` / `checks=320`，exit 0 | `outputs/2026-11-10_dialogue_bottom_bar/main_story2/` |
| 主线业务集成 | `checks=98`，exit 0 | `outputs/2026-11-10_dialogue_bottom_bar/main_story/` |
| 主线导航 / 进度 / Boss 门闩 | exit 0 | `probes/dialogue_bottom_bar/{navigation,progress,boss_gate}/` |

**一次真实的超时，记在案**：032 首次与其它高负载 Godot 并发时 `timed_out=true`、`exit 1`（480s 上限）。032 历史上单独跑就要 **389s**，本次单独重跑 **303.9s** 通过。不是代码回归，是 runner 超时窗口与并发资源争抢 —— 但**不能把超时当成通过**，所以这里保留两次记录。

### 5.2 画面确认（逐张查看）

- 3.1 `t_005.40`：主角头顶是一个 0.86×0.46 m 小框 + 三点，**框内无文字**；底栏显示「主角 / 你见过我的主人吗？我在找他。」；主角本体完整可见，不再被气泡糊住。
- 3.2 `t_058.60`：与 3.1 同一形态；底栏「主角 / 你一句我也没听懂…」；前方未激活显示器完整可见。
- 3.3 `t_007.15`：绿苔头顶同样是小框 + 三点；底栏「绿苔 / 第一把。接上了。」；嵌件第一孔与台面关系未被遮挡。

### 5.3 静态门禁

| 门禁 | 结果 |
|---|---|
| 功能追溯 / 验收登记 / 关卡解耦 / 资源命名 | exit **0** |
| 文档总门禁 | exit 1，**14 条**既存断链（与本轮改动前同一批，仅行号偏移；新增 0） |
| 媒体资产域 | exit **0**（`ui` 期望行数 20→21 已同步） |
| 分账本无损基线 | exit 1，**227 条**既有失败（enemies 域双等号公式 / 数组公式 / 一条 `row_content_mutated`），**新增 0** |
| 资产结构 | exit 1，**4 类**既有项（同前），**新增 0** |
| 资产 `full --ledger ui` | exit 1，**5 条**历史 SHA 漂移（HUD / VAULT / INVENTORY-3D / PAUSE-3D / FATE-SOURCE 行），**新行不在其中** |

## 6. 账本

UI 账本新增一行：**`UI-SCREEN-DIALOGUE-BAR`「对话底栏与头顶说话示意框」**（`ui` 域，资产主表 26 行，域变更日志 `v0.2.7`）。

- 这是**程序化控件与程序几何**，不是美术文件资产：T 列 SHA 取底栏入口脚本 `DialogueUI.gd` 的哈希，用于“实现未变”的定点核对，**不冒充 TSCN/GLB 资产哈希**。
- 示意框三点与尾巴是同一父资产的内嵌表现，**不另建道具/特效行**（与选关红锁、台座亮环同一口径）。
- 基线只新增该资产记录并重算 25 个内容列摘要与类别计数；`sheet_digests` 保持原值（`ui` 域没有 Prefab 分页）。
- **登记前先做排除性核对**：确认移除任何东西之前，列摘要就已与基线逐列一致；若已漂移则脚本以 exit 2 **拒绝登记**，避免顺手把别域的历史漂移洗进基线（本次结果为 0 漂移，正常登记）。

## 7. 未闭环

- 资源 UID 回退警告（032 单次 1449 条）与 `ObjectDB instances leaked at exit` 告警仍在（本轮新增 0，旧有未清）。
- 资产全局门禁仍有既有红项：`verify_ledger_split` 227 条、`structure` 4 类、`full --ledger ui` 5 条历史 SHA 漂移；**本轮新增 0**（新增前后 issue 集合逐项对比完全一致，新资产 `UI-SCREEN-DIALOGUE-BAR` 不在任何 issue 中）。
- 文档总门禁仍是既存 14 条断链（新增 0）。
- **并发协调**：本轮期间另一会话在改 `src/ui/WorkbenchPanel.gd` + 新增 `src/ui/ForgeMeltVeil.gd`，其未完成状态使 3.1 捕获首帧报 `WorkbenchPanel.gd Compilation failed`（`Identifier "_actor_alpha" not declared`）。该错误**不在本轮改动面上**，但**不在部分某次 031 运行中消失了**——032 单跑时该文件已恢复可编译。这一条**不能记为已解决**，只能记为“与另一会话的改动状态相关”。
- 未做人工真实窗口的两人同框观感确认；示意框的最终观感（大小是否够“示意”、三点速度）建议在真机跑一段回头再定。

## 8. 回滚

- 代码：`NpcCharacter3D._present_dialogue()` 与 `NarrativeAdapter3D._say_dialogue_on_actor()` 各一行改回 `say_text` 即恢复旧的“对话走头顶文字气泡”；气泡几何、底栏控件、示意代码均无需删除。
- 账本：UI 账本删除 `UI-SCREEN-DIALOGUE-BAR` 行、基线删该记录、`check_media_asset_domains` 的 `count` 回 20。
- 备份：改前快照在 `ShellStorm2-backup/2026-11-10_154545_717598_dialogue_to_bottom_bar/before_edits/`（17 个文件，逐文件 SHA 校验一致）。
