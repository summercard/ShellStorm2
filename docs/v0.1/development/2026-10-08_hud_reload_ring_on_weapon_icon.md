# 换弹环搬到 HUD 武器图标上 + 图标弹跳

FeatureID：PLAYER-STATE（换弹表现的当前载体）/ UI-HUD（武器图标所在面板）。2026-10-08，游戏版本 0.1.0 不变，资产不动。

## 用户诉求（原话）

> 就是我换子弹的那个提示圈，帮我换到图片中的枪械图标的位置来，然后大小跟我红圈一样大。完成后，枪械的图标要放大缩小的弹一下。

## 改了什么

**换弹环从世界空间搬到 HUD 层的武器图标上。** 新增 `src/ui/HudReloadRing.gd`（`Control`，`_draw()` 里画 2D 圆环），由 `Dungeon3D` 建在 `ReferenceCombatHUD` 下，每帧把环心对齐到 `CurrentWeaponModelIcon3D` 的**控件矩形中心**。

为什么不能"把 3D 环挪到图标的屏幕位置上"：`CanvasLayer` 恒在 3D 之上，图标本体是不透明网格，会把它下面的 3D 环压住，只有漏在图标外的部分看得见 —— 做不到"套在图标上"。

**尺寸取主人标注图的实测值，不取手感值。** 标注图 1280×720，而 `window/stretch/mode = canvas_items` + `aspect = expand` 在 1280×720 窗口下缩放因子恰为 1.0 ⇒ 该图里 **canvas px == 屏幕 px**。程序化量红笔像素得：外径 **75 px**、圈心 **(1066.0, 675.5)**；再由「内容右对齐」反算武器图标控件矩形 = 屏幕 x `1041.6..1092.8`，矩形中心 **(1067.2, 676.4)** —— 与红圈圈心差 **1.2 px**。

⇒ **环心 = 图标矩形中心**（结构量），外径 **75 px**（`HUD_RELOAD_RING_OUTER_DIAMETER_DESIGN = 93.75`，走既有的 `_hud_size()` × `HUD_UI_SCALE 0.80` 口径）。取结构量的好处：换分辨率、挪面板、改图标尺寸时环自动跟随，不会脱钩。

**视觉语言与刚退役的世界环同源**，不另起一版：线宽比 `THICKNESS_RATIO = 0.2226`（= 交互读条环的 `0.059/0.265` = 世界环的 `RELOAD_RING_THICKNESS_RATIO`）、起点 12 点顺时针（与 `RingProgressGeometry.START_ANGLE` 同一约定，只是 2D 画布 y 向下所以取 −π/2）、首尾不淡出（这是"填充量"，淡出会读成"没走完"）。颜色真源仍是 prefab 里 `MatReloadFill` 的 albedo/emission，逐字抄进常量并注明来源。

**图标弹跳。** 主人要求「枪械的图标要放大缩小的弹一下」。做成**纯函数** `Dungeon3D.hud_weapon_icon_pop_scale(t)`：三段曲线（起跳 22% 三次缓出 → 回落 40% 平滑 → 收尾 38%），`t=0` 与 `t=1` **精确归 1**，峰值 `1 + 0.30 = 1.30`，回落最低 `1 − 0.30×0.35 = 0.895`（回弹感）。总时长 0.42 s，比一次换弹（约 2 s）短一档 —— 它标的是"扣下换弹键"那一下，不是整个装填过程。触发点是**本轮换弹的第一次** `reload_progress_changed`，不是每帧。缩放围绕控件中心（设 `pivot_offset`），否则会朝右下角"长"出去、看着像整块 HUD 在抖。

**世界空间换弹环退役。** `PlayerAvatar3D` 新增 `RELOAD_RING_IN_WORLD := false`，`_setup_reload_ring()` 不再建 mesh，`_update_reload_progress_bar()` 把它按住不许亮。prefab 里的 `ReloadProgress3D/Track|Fill` **节点不删**（资产层不动、不升版、不动台账），那一族 `RELOAD_RING_*` 常量（半径 0.21 / 横向让位 0.979 / 锚点 0.25 / 朝向与深度测试）**保留**——它们是这个开关的另一半，改回 `true` 即恢复。换弹进度本身照旧供 `CharacterMotionLibrary3D` 驱动角色换弹动作，与本环显隐无关。

## 验收

- **`verify_3d_reload_state_flow`**（core）：世界环的四条几何复核助手（弧带半径 / 环面正对镜头 / 世界半径随角色缩放 / 相机平面里判压人）随环一起下线。原断言不是删掉、而是**换成反向钉子**：`reload_ring_in_world` 必须为 false、`reload_bar_visible` 在换弹中必须为 false、`Fill` 网格三角面数在换弹开始与半程两个采样点都必须为 0。理由：HUD 环一切正常**完全挡不住**"世界环又被打开"（两圈会同时在画面上），必须由这里挡。退出 0。
  - 过程中修掉一处自造的引擎错误：退役后 `Fill.mesh` 是 prefab 里的 `QuadMesh`（非空、但 cast 不成 `ArrayMesh`），旧写法 `fill.mesh == null or (fill.mesh as ArrayMesh).get_surface_count()` 会在 null 上调方法、把错误写进日志（日志门禁判红）。已改为先 `as ArrayMesh` 再判空。
- **`verify_reference_hud_fate_visual`**（visual）：新增 HUD 环契约 —— 外径 = 75.0 ± 0.5 px、未换弹时不显示、环心与图标矩形中心偏差 ≤ 1.0 px；弹跳曲线逐点断言（起止归 1、峰值落在 1.2..1.5、回落不低于 0.85）；真跑一次换弹：环显形（进度 0 = 空环）→ 步进 0.42 s 采样图标缩放（峰值 ≥ 1.2、回落 ≥ 0.85、收尾精确回 1.0 且 `pivot_offset` 归零）→ 半程进度与武器计时器一致（±0.02）→ 结束即收。渲染截图 `outputs/verification/hud_reload_ring.png`（半程 50%）。
  - 截图前补了 `await RenderingServer.frame_post_draw`：`_capture` 直接读视口纹理，中间不 await 拿到的还是"换弹开始前"那一帧 —— 实测新旧两张 PNG **逐字节相同、差异 bbox 为空**。一张看不出环的"证据"比没有证据更糟。
  - ⚠️ 本场景**当前为红**，原因与本条无关：并行会话的逆位命运卡文字改动（`UIStyleFactory.apply_tarot_orientation` / `WorkbenchPanel` / `DivinationMenu` / FateCardCollectionMenu）在本工作区留下 48 处引擎错误，星币牌翻面与文字层因此不成立。**已做基线对照**：把本场景的验收脚本还原到 HEAD 重跑，错误集合逐条相同（含 `'tarot_button'` meta 缺失 6 次、`Fate overlay is missing text: 星星命运` 等）。本条新增的判据在本轮**零报错**。
- **回归**：`verify_finite_ammo_flow` / `verify_hud_presenter_3d` / `verify_tactical_inventory_minimap_flow` 直跑均退出 0、日志门禁 0。武器面板尺寸契约（250..312 × 44..59）与快捷栏面板未动。
- **渲染复核**：`hud_reload_ring.png` 程序化量 —— 环心 y = 676.0，与图标中心一致；填充弧外径 ≈ 77 px（含抗锯齿/外发光，目标 75）、线宽约 8 px。人眼复核 `_scratch/crop_hud_reload_ring2.png`。

## 隔离套件（batch）首次运行：红在**资源导入阶段**，与本次改动无关

`scripts/run_verification_suite.sh batch verify_3d_reload_state_flow verify_finite_ammo_flow verify_hud_presenter_3d verify_reference_hud_fate_visual` 退出码 **3**，`VERIFICATION_IMPORT_LOG_FAILED` —— 红在**隔离工程的 `--import` 前置步骤**，**四枚场景一枚都没跑到**。

日志里是 **205** 行

```
ERROR: Condition "f.is_null()" is true. Continuing.
   at: get_multiple_md5 (core/io/file_access.cpp:1002)
```

全部聚在同一件资产上：`assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png`（`[ 0% ] reimport | 设施低亮多巴胺色盘…` 之后整段都是它）。`get_multiple_md5` 打不开被 md5 的文件 ⇒ 该资产此刻正被**并发改写**。

现场证据（全部只读）：

| 证据 | 值 |
|---|---|
| `.import` 改写时间 | `2026-10-09 00:29`（套件的导入窗口 23:40–00:25，紧挨着） |
| `.import` 语义变化 | `uid://b76h10o6xeuiq → uid://dtuahqaj31kp2`；`compress/mode 2 → 0`；`vram_texture true → false`；`mipmaps true → false` |
| 同目录备份 | `设施低亮多巴胺色盘_10x10_512.png.import.bak_pre_standard_fix` |
| 原子写残留 | 同目录 **348 个** `*.import~RF*.TMP`（其中一批时间戳 = 00:22，正在套件的导入窗口内） |

属**并行会话的「色盘 UID / 标准修正」工作**（工作区里另有它们的 `outputs/palette_uid_20261008/`、`_import_tex512.log`）。

归属判定：本次改动只有 GDScript（`HudReloadRing.gd`、`Dungeon3D.gd`、`PlayerAvatar3D.gd`）+ 验收脚本 + 文档，**不碰任何资产**，不具备让某张 PNG 的 `get_multiple_md5` 打不开文件的能力。

🔴 **一条值得记下的工具特性（不是本次的错，但会反复咬人）**：这套套件把真实工程的顶层目录（`assets/`、`src/`、`scenes/`…）**软链**进隔离工程，所以它 reimport 时会把 `.import` 写回**真实资产树**。⇒ **多会话并行时，一边改资产、一边跑套件，必然互相踩**。要跑隔离套件，先确认没有会话在动资产。

处置：等写入停止（复查已无 Godot 进程、无新写入）后**原样重跑一次**，结果见下。

### 重跑结果（2026-10-09 00:33–01:14）：导入阶段干净，四枚场景 3 绿 1 红（红的那枚不是本次改动）

| 场景 | 结果 |
|---|---|
| 隔离工程 `--import` 前置 | **通过**（`f.is_null` / `VERIFICATION_IMPORT_LOG_FAILED` 出现 **0** 次）⇒ 坐实上一轮的红是并发改写色盘所致，与本次改动无关 |
| `verify_3d_reload_state_flow` | **OK** |
| `verify_finite_ammo_flow` | **OK** |
| `verify_hud_presenter_3d` | **OK** |
| `verify_reference_hud_fate_visual` | **FAILED** —— 全部是并行会话的逆位命运卡问题（tarot meta 缺失 ×6、文字层缺失 ×6、卡太小 ×3、翻面未完成 ×3、`Fate overlay is missing text: 星星命运` 等），另加两条 `Failed loading resource: ui_fate_card_reinforce_v001.png / ui_fate_card_mark_enemy_v001.png`（ctex 打不开，同样是那批资产在导入中）。**本次新增的 HUD 环判据零报错。** |

套件自身末行 `VERIFICATION_SUITE_FAILED suite=batch count=4 failed=1` / `FAILED_SCENE verify_reference_hud_fate_visual:1`；外壳退出码 1（上面那条场景失败）。

⚠️ 另外外壳还报了一条**环境层**的红（不是场景红）：`临时工作区未被清理` —— `_scratch/.verify_ws/` 下积了 4 个残留工作区（我这两轮留下的 `6spFpV` / `9MqOz1`，加上别的会话 09:36 / 09:42 留下的陈旧 `Ffl2Tu` / `Gc0Q4L`，后两个合计约 **9.27 GB**）。套件自带的清理脚本对它们判 `REFUSED`（**含 70 个 reparse point ⇒ 拒绝删除**，那正是隔离工程的软链），加上本环境的批量删除确认护栏，所以自清不了。**未擅自删**，等主人定。

## 追加（2026-10-09）：主人返工「太粗了 细一点」

线宽比 `THICKNESS_RATIO` 由 **0.2226 → 0.13**，发光同批收紧（`GLOW_WIDTH_RATIO 2.6 → 1.8`、`GLOW_COLOR.a 0.50 → 0.38`）。

**0.13 是把主人的红笔当标尺量出来的**，不是手感值。对标注图里那一圈红像素按「到圈心的半径」分桶（该图 canvas px == 屏幕 px）：

```
半径 r:   34   35   36   37   38   39   40
红像素数: 56  120  204  220  164  112   27
```

⇒ **核心亮带 = r 35..39 = 5 px**，按像素加权的平均半径 36.84（红笔圈的中径）。外半径按水平 span 取 37.5 ⇒ **笔宽 ÷ 外半径 = 5 / 37.5 = 0.1333**。取 0.13 ⇒ 本环主干 = 37.5 × 0.13 = **4.875 px**。

（改之前是 0.2226 ⇒ 8.35 px，`8.35 / 4.875 ≈ 1.71` —— 就是主人说的"太粗"。）

**"看着粗"有一半出在发光上**，所以必须同批收：旧参数下发光 = 主干 8.35 px × 2.6 = **21.7 px 宽的半透明绿**，主干缩细也救不回来。现在 = 4.875 × 1.8 = **8.8 px**。⭐ 因此验收同时钉三条：`thickness_px ∈ 4.0..5.8`、`glow_width_px ≤ 10.5`、`glow_color.a ≤ 0.45` —— 只钉主干会放过"主干细了、发光还铺 20 px"这种"看着仍然粗"的形态，而那正是这次返工的原始症状。

⚠️ 此处**主动放弃**"与世界环线宽同值"这条旧口径：世界环已退役（画面上只剩本环），没有再对齐它的必要。世界环那边 `PlayerAvatar3D.RELOAD_RING_THICKNESS_RATIO` 保持 0.2226 不动，两处不再同值是**有意**的，已在两边注释写明原因，免得日后有人"顺手对齐"。

### 反向验证 + 渲染复核（这次只变细，没动尺寸与位置）

把比例临时改回 0.2226 重建一版截图 ⇒ 该枚验收立即判红（`EXIT=1`）；改回 0.13 ⇒ 绿（`EXIT=0`，且本轮该场景**整枚全绿** —— 并行会话那批命运卡资源已修好）。

同一判据量两张截图：

| | 外径 | 环心 | 径向视觉厚度（中位） |
|---|---|---|---|
| 粗版（被否） | 77 px | (1092, 676) | **10 px** |
| 细版（交付） | 77 px | (1092, 676) | **7 px（70%）** |
| 主人红笔（对照） | 75 px | (1066.0, 675.5) | 核心亮带 5 px |

外径与环心完全不变 ⇒ **只变细、没缩尺寸也没挪位**。对照图：`outputs/hud_reload_ring_thickness_20261009.png`（粗/细并排）、`outputs/hud_reload_ring_vs_master_20261009.png`（红笔/成品并排）。

## 未做 / 边界
- 未改用例的 `preview_reload_ring.{gd,tscn}`（世界环专用预览探针）：它按 `TowerDescent3D` 相机姿态拍角色身侧的环，退役后拍不到东西了。它是手动探针、不注册进套件，故本轮**保留未动**，等世界环的开关若真被改回 true 时它才有用。
- 未动资产、未升版、未改台账；未改换弹时长、弹药逻辑、存档 schema、输入。
- 未跑全项目套件、移动端与正式场景完整操作。
