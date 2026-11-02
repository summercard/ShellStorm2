# 2026-11-02 99F 基地 NPC（全绿皮肤）

工程 0.1.0；FeatureID `BASE-NPC`；设计修订 r4。来源：用户要求「在 99F 基地里增加一个 npc，先用主角的模型换上全绿色的皮肤。放在场景中，会自己移动。可以对话。按照 npc 的系统制作，完成后更新设计文档和账本」。同轮两次纠正：① 「99f 基地为什么背景是这个，不是我的基地里头吗？」② 「还有绿色直接从我的可以更换的衣柜里去找，可以直接用的」。

r4（同日第三轮，气泡与提示）：

| # | 原话 | 改法 |
|---|---|---|
| 7 | 对话框会遮住整个角色，往上放一些 | 气泡中心 2.05 → 2.80 → **3.40**（俯角压缩，两轮才够；屏幕间隙 3~4px → 33px） |
| 8 | 黑色背景半透明 | `fill_color` 改 `Color(0.012,0.018,0.026,0.55)`；底板走 alpha 混合、文字改 `ALPHA_CUT_DISABLED` 并靠 priority 排在底板之后 |
| 9 | 这个白色的交谈和白点不要了 | NPC 列进 `DOT_EXCLUDED_PROVIDER_SCRIPTS` ⇒ 控制器**不创建**圆点节点，白色「(e) 交谈」彻底消失 |

r3（同日晚些时候，六条观感返工，都是业主看着实机截图提的）：

| # | 原话 | 改法 |
|---|---|---|
| 1 | 为什么是自发光的绿色？荧光感太强了 | `NpcCatalog.SKIN_EMISSION` 0.30 → **0**，材质不再 `emission_enabled`，完全靠场景光 |
| 2 | 头要和角色一样大，现在大了很多 | 补上 `Player3D.DEFAULT_BASE_SIZE_MULTIPLIER`（0.8）—— 第一版漏了玩家运行时那一步缩放，NPC 大 25% |
| 3 | 对话框也太小了 / 大一倍先 | 气泡 `pixel_size` 0.0042 → **0.0084**；`wrap_width_px` **保持 560**（跟着翻倍会变成 8.27m 宽横跨屏幕的单行横幅） |
| 4 | e 交谈这个提示要接近才出来 | 交互半径 2.4m → **1.5m**，热区中心 0.9 → 0.6 |
| 5 | 上面的白点去掉 / 名字也去掉 | 名字牌/身份牌撤除；白点见第 9 条（第一版只做淡出，不够） |
| 6 | 点击交谈后，角色要立刻停下来，面对角色 | 新增 `_talk_engaged`：按 E 即刻停步 + 朝向瞬时吸附到玩家，直到玩家离开范围才解除 |

「行走的时候会有残影」与第 1 条同源：99F 的 `WorldEnvironment` 开着 `glow`（bloom 档，`glow_intensity 0.72`），自发光体移动时会在身后拖一圈光晕。关掉自发光后一起消失。

## 现状核对（动手前）

- 仓库里**没有正式的 NPC 系统**。唯一相关实现是 `src/world3d/ThemedNPC3D.gd`：胶囊体拼的主持人 + `Label3D` 台词，2026-09 的占位表现，只在 `Player3DStateGallery` 三态预览里用，**没有进过任何正式场景**。
- 对话侧只有两种载体：底栏 `DialogueUI`（系统/画外音）、头顶 `SpeechBubble3D` + `CharacterBark3D`（有实体说话人）。按 18 号文档 §1.1，NPC 属有实体 → 用气泡。
- 玩家交互已是单一入口 `PlayerInteractionController3D`（provider 协议），新 NPC 必须实现那四件套，不能自读 E 键。
- **两个"99F 基地"要分清**（第一版就栽在这里）：
  - `scenes/BaseWorld3D.tscn` —— 「基地与荒野」旧兼容场景，破败公路广场 + 4 个路边副本入口 + 8 个占位设施。**不是室内基地**。
  - `scenes/TowerDescent3D.tscn` 的 `facility` 房间 —— 正式 99F 室内基地（12m 层高、地板 `y=-12`、8 个正式设施模型、中央全息平台）。**这才是主人说的"我的基地里头"**。

## 改动

| 文件 | 内容 |
|---|---|
| `src/npc/NpcCatalog.gd`（新） | 内容目录：`npc_base99_green` → 绿苔 / 99F 基地看守 / 4 句台词；皮肤只存**衣柜变体 ID** `suit_green` |
| `src/npc/NpcCharacter3D.gd`（新） | NPC 实体。模型装配（含玩家同口径 0.8 缩放）、衣柜绿 `material_override`（无自发光）、面饰补挂、巡逻、搭话定住并转向、待机/步态关节动画、黄色 `[E] 交谈` 提示、气泡对话、provider 交互协议、快照 |
| `scenes/BaseNpc3D.tscn`（新） | 根 `Node3D` + 脚本，其余全代码构建 |
| `src/world3d/TowerDescent3D.gd` | 新增 `_install_base_npc()`（只装 99F、远征跳过）+ 只读投影 `get_npc_count() / get_npc_snapshots() / find_npc()` |
| `assets/art/environments/tower_zones/base/runtime/zone_base.tscn` | 新增两个巡逻锚点 `99层基地NPC起点锚点` / `99层基地NPC巡逻终点锚点`（作者可挪） |
| `src/player3d/PlayerAvatar3D.gd` | `CUSTOMIZATION_OPTIONS["body"]` 加 `suit_green`；`BODY_COLORS["suit_green"]` |
| `src/player3d/customization/AvatarCustomizationCatalog.gd` | `VARIANT_LABELS` / `VARIANT_COLORS` 同步「苔绿作业服」 |
| `src/player3d/Player3DStateGallery.gd` | 三态预览的槽位名单同步 |
| `tests/verification/verify_base_npc_flow.gd/.tscn`（新） | A01–A26（含 A13b 体型、A14b 无自发光、A20b 提示时机、A20c 白点退役、A22b/c 搭话定住、A24b 气泡尺寸、A25b 恢复巡逻），注册在 `core_scenes` |
| `tests/verification/capture_base99_npc.gd`（新） | 真实渲染截图脚本 |
| `docs/v0.1/20_技术施工_基地NPC.md`（新） | 功能契约全文 |
| `scripts/register_base_npc_ledger.py`（新） | 新增 `CHR-PLY-BUNNY01-NPC-GREEN` 行 + 总览/下拉区间 + 日志 `v0.1.27` + 基线补录 |
| `scripts/register_wardrobe_suit_green_ledger.py`（新） | bunny01 行补 `suit_green` 记法 + 日志 `v0.1.28` + 该行基线指纹刷新 |
| `src/base3d/BaseWorld3D.gd`、`scenes/BaseWorld3D.tscn` | **回到原样**（第一版加的 NPC 与三个查询方法已全部撤除） |

## 两轮返工（主人当场指出）

### 第一轮：装错场景

第一版把 NPC 挂在 `scenes/BaseWorld3D.tscn`，截图背景是破败公路广场 + 两个橙色箱子 + 白色小兔子（就是兼容场景的 `Dungeon01..04` 广告牌与占位设施）。主人一眼看出「这不是我的基地里头」。

- 撤除：`BaseWorld3D.tscn` 的 `NPCs/BaseNpc99F` 节点、`10_npc` 预加载、`load_steps` 回退 13→12；`BaseWorld3D.gd` 的 `get_npc_count / get_npc_snapshots / find_npc` 三个方法。
- 改挂：`TowerDescent3D._install_base_npc()`，父级 `Art`（布置层），`is_expedition()` 直接跳过。
- 位置不再写死，读布置层两个锚点（世界 `(-4,-12,1.5)` ↔ `(-4,-12,-2)`）。锚点值由探针实测的**空位扫描**确定：在 `y=-12` 上以 0.34r × 1.5h 胶囊做 `intersect_shape`，482 个空位、离出生点 4.0m 环带内 160 个，选中的两点距最近设施（MEDICAL 柜 / SUPPLY24H）均 > 2.4m。
- 验收 A02 现在会**同时**断言两件事：NPC 在 `facility` 房间内、且旧 `BaseWorld3D` 场景**不含** NPC —— 再装回去当场变红。

### 第二轮：绿色必须是衣柜里的

第一版把 `Color(0.16, 0.68, 0.30)` 硬写进 `NpcCatalog`。主人要求「直接从可以更换的衣柜里去找，可以直接用的」。

- 衣柜新增身体槽变体 `suit_green`（中文名「苔绿作业服」），色值与第一版相同，但**唯一真源在 `PlayerAvatar3D.BODY_COLORS`**。
- `NpcCatalog` 不再存色值，只存变体 ID；`get_skin_albedo()` 转调 `AvatarCustomizationCatalog.get_variant_color()`。
- 取不到时 `push_warning` + 返回 `Color.MAGENTA`，不悄悄回退成另一个绿。
- 玩家现在可以在衣柜里选同一档绿；NPC 与玩家共用一个色源。
- 验收 A09 断言三方一致：`NPC 材质 albedo == 衣柜目录色 == PlayerAvatar3D.BODY_COLORS`。

## 另外两个实现上的坑

1. **不能直接 preload 玩家模型场景。** 第一版把 `.../v021/runtime/chr_bunny01_root_v021.tscn` 写成 `preload` 常量，`check_asset_runtime_naming.py` 当场红：`带版本引用计数上升：gd 23 → 24`。该门的债务快照只允许缩小，不允许新增。改为 `load("res://scenes/Player3D.tscn")` 取 `Avatar3D/VisualRoot` —— 引用不带版本号，且语义更对（玩家模型升级时 NPC 自动跟随）。
2. **`SpeechBubble3D` 以自身中心为原点**（`_relayout` 的 `half`），不是从锚点向上长。最终分层：身份 1.62 / 名字 1.86 / 圆点 2.16 / 气泡 2.62，A14 断言算出来的实际间隙。


## 实拍又抓到五个问题（都是数值断言抓不到的）

机器验收 first pass 就绿了，但**真实渲染器拍图后发现五处肉眼可见的缺陷**，逐个修：

1. **气泡把整个屏幕糊了。** `SpeechBubble3D` 默认 48px / `pixel_size 0.0055` ⇒ 世界字高 0.264m、底板 3.4m 宽，挂在 1.5m 角色头上直接铺满半屏。
   - ❌ 第一次只改 `bubble_scale = 0.5`：底板缩小了、**文字没变小**，字全溢出到气泡外面。原因是 `bubble_scale` 只参与底板几何的 `unit = pixel_size × bubble_scale` 换算，Label3D 的 `pixel_size` 没动。
   - ✅ 改 `Text.pixel_size = 0.0026` + `wrap_width_px = 460`：这两项同时是底板换算与文字渲染的输入，一处改、两者同步。
2. **交互圆点把名字和身份各啃掉一半。** 第一版名字 1.80 / 身份 1.66 / 圆点 1.58，`DOT_RADIUS_M = 0.16`（直径 0.32m）的常驻圆点正好卡在两行之间。
   - ✅ 当时重排成四层：身份 1.62 → 名字 1.86 → 圆点 2.16 → 气泡 2.62。A14 从"常量大小关系"改成断言**算出来的实际间隙 ≥ 0.02m**。
   - ⚠️ **r3 已把这些层全删了**（名字/身份/圆点都不再画），现在头顶只剩"黄色提示 + 气泡"两层。这一段保留作历史记录：分层思路仍然适用于任何后续要往头顶挂第三样东西的场合。
3. **NPC 没有脸。** bunny01 的头部几何**本身没有眼睛**，主角的脸全部来自默认面饰 `electronic_mask`（`PlayerAvatar3D._ready()` 实例化到 `HeadJoint/FaceAccessorySocket`）。NPC 只摘 `VisualRoot`、不跑玩家脚本 ⇒ 一个纯绿无五官的圆球。
   - ✅ 自己补挂 `chr_bunny01_electronic_mask_root.tscn` 到 `HeadJoint`（与玩家同位）。
4. **面具被一起染绿了。** 全量 `material_override` 把面具的深色面板和蓝色发光眼一起吃掉，等于白补。
   - ✅ 皮肤只涂**本体几何**，面饰按祖先名 `ElectronicMask` 排除。「全绿皮肤」指头壳/躯干/耳/手/脚；面饰不是皮肤。
   - 验收 A08 因此拆成两半：本体每件必须涂绿、面饰一件都不许涂绿，且面饰网格数 ≥ 1。
5. **夜里绿皮读成近黑。** 自发光 0.06 不够；22:00 实拍几乎看不清。
   - ⚠️ 当时抬到 **0.30** —— **r3 已归零**：这样虽然解决了"夜里看不见"，但整只泛荧光，业主直接否掉（「荧光感太强了」）。终态是"不发光、夜里偏暗但仍是干净的绿"，见上面的 r3 表。

三张图留在 `docs/v0.1/audits/evidence/2026-11-02_base99_npc/`：`base99_npc_noon.png` / `base99_npc_night.png` / `base99_npc_closeup.png`（真实 Forward+ 渲染，非无头，**已换成正式 99F 室内基地**的背景）。

## 验证

| 项 | 命令 | 结果 |
|---|---|---|
| NPC 专项 | `godot --headless res://tests/verification/verify_base_npc_flow.tscn` | **退出 0**，`BASE_NPC_FLOW_OK`（r3 口径：体型同玩家 / 衣柜绿无自发光 / 头顶无名字牌无白点 / 按 E 定住转向 / 巡逻恢复） |
| 换装回归 | `verify_player3d_diy_flow` | 退出 0，`PLAYER3D_DIY_FLOW_OK`（`suit_green` 重建后仍通过） |
| 衣柜回归 | `verify_wardrobe_preview_fill_flow` | 退出 0，`WARDROBE_PREVIEW_FILL_FLOW_OK` |
| 账本结构 | `check_asset_registry.py --scope structure` | 退出 0，`ASSET_REGISTRY_CHECK_OK assets=1418 ledgers=9` |
| 角色域全量 | `check_asset_registry.py --scope full --ledger characters` | 退出 0，`assets=26` |
| 账本拆分/基线 | `verify_ledger_split.py` | 退出 0，`LEDGER_SPLIT_VERIFY_OK assets=1418` |
| 运行资产命名 | `check_asset_runtime_naming.py` | 退出 0，回到基线 `gd=23 / tscn=93`（无新增欠账） |
| 功能追溯 | `check_feature_traceability.py` | 退出 0，`FEATURE_TRACEABILITY_OK features=44` |
| 关卡解耦 | `check_level_decoupling.py` | 退出 0 |
| 文档契约 | `check_documentation_contracts.py` | 退出 1，17 条**全是既有红项**，逐条筛过后**没有一条**指向 NPC 相关文件 |
| 气泡专项（r4 改口径） | `verify_speech_bubble_3d` | 退出 0。原断言"底板必须不透明 + 文字 `ALPHA_CUT_DISCARD`"已按新口径改写为"底板 `TRANSPARENCY_ALPHA` + 文字 `ALPHA_CUT_DISABLED` + 底板 priority < 文字" |
| 圆点表现（r4 回归） | `verify_interaction_dot_presentation` | 退出 0 |

## r4 追加的四个坑

1. **俯视角下"抬 1 米"只等于屏幕上 0.6 米**。基地相机俯角 53°，`cos53° ≈ 0.60`。要"看得出空隙"，世界间隙至少 ≈ **1.3 倍角色身高**。第一次从 2.05 抬到 2.80（世界间隙 0.98m）自认为够了，实拍屏幕间隙只有 0.34 个角色高、气泡下缘还压着黄色提示。**验收要按屏幕等效量守门，不能只比世界米数。**
2. **半透明底板的连锁反应：文字必须改走透明队列**。`Label3D.alpha_cut = ALPHA_CUT_DISCARD` 是为了让文字进不透明管线（拿正确运动矢量防 TAA 拖影），代价是**不透明永远先渲染**；底板一旦半透明、叠在文字之上，0.55 的黑会把白字压到 45% 亮度。改 `ALPHA_CUT_DISABLED` + `render_priority`（底板 0 / 文字 2）才对。
3. **估透明度不能单点算**。`result = (1-a)·bg + a·fill` 有两个未知量，必须用两个亮度不同的背景点联立。单点会得出 `a≈0.12` 的错误结论（把 `fill` 误当成近黑 `(3,5,7)`）。正解：`bg/result = 78/59` 与 `54/46` 联立 ⇒ `fill≈36`、`a≈0.46`（配置 0.55，差值是 tonemap/glow）。
4. **"淡出"不等于"没有"**。`is_interaction_dot_visible() = false` 只是把圆点插值淡出，插值期间白点和白色「(e) 交谈」会闪 —— 业主两轮都在说这个。正解是把脚本路径列进 `DOT_EXCLUDED_PROVIDER_SCRIPTS`，控制器**根本不建节点**（基地设施走的就是这条路）。
   - 顺带：说话时黄色提示也要收，条件必须是 `_talk_engaged or _dialogue_visible` —— `advance_dialogue()` 可以绕过 `perform_interaction` 直接推进（剧情/测试路径），光看 `_talk_engaged` 会让提示压在气泡下缘上。

## 既有红项（与本次无关）

- `verify_base_world_flow.tscn` 仍是 5 条红：入口不是 TowerDescent3D、节点数超 500、设施 8→7、玩家八态、训练场入口。2026-09 的旧基线，本次改动**反而让它少了一条**（第一版加的 NPC 已从该场景撤除、节点数回落）。**没有为了让它变绿而放宽阈值。**
- `check_verification_registry.py` 退出 1：`verify_base_lamp_dynamics` / `verify_base_lamp_visual` / `verify_stairwell_turn_rail` 三个历史场景未登记。本次新增的 `verify_base_npc_flow` **已登记**在 `core_scenes`，不在失败列表。

## 未执行 / 未覆盖

- 真实渲染拍了 12:00 / 22:00 两个时段、一张正面近景、一张 `[E] 交谈` 提示、一张**说话帧**（r4 新增，用来量气泡间隙与半透明）。第三方时段（黄昏逆光等）与移动端 Compatibility 后端未验。
- ⚠️ 截图脚本必须 `APPDATA=<临时目录>` 隔离用户数据目录：正式档里有另一个进程在写 `BaseManager` revision，抢写会 `Refusing stale save` 并把截图进程**卡死到超时**（r4 期间卡了两次，各十分钟）。
- 导航寻路与避障、对话选项/分支、任务与商店挂钩、多 NPC 管理、非平面地面贴地采样、面饰表情接入表情系统 —— 均未实现，已在设计文档 §12 明确保留。
- 未跑完整的 `core` 套件（一次完整套件要整份复制约 5 GB 导入缓存、耗时数十分钟）；只跑了本功能专项 + 换装/衣柜两条回归 + 账本/命名/追溯/解耦门禁。
- 预期故障注入未执行。**例外是遇到过一次意外故障注入**：并行会话把 `suit_green` 回滚后，NPC 按设计渲染成 `Color.MAGENTA`（紫），画面上一眼可辨 —— 这条失败语义被真实触发并验证了。

## 一条并发写冲突的教训（r3 期间实际发生）

本轮做到一半时，另一个会话把这批改动**整批回滚到 HEAD**：`TowerDescent3D` 的 `_install_base_npc()` 与三个只读方法、`suit_green` 衣柜变体、角色账本第 31 行、`MODULE_INDEX` / `feature_registry` / `CHANGELOG` 条目、`run_verification_suite.sh` 注册，全部消失。

发现它靠的是**真实渲染截图**：NPC 变成洋红色 —— 那正是 `NpcCatalog.get_skin_albedo()` 取不到衣柜变体时的设计行为（宁可醒目失败，也不悄悄回退成某个绿）。如果没有截图只看 `git status`，这条会漏过去（文件本身还在，只是被"撤销"了）。

重建后补了一个小工具 `scripts/refresh_ledger_baseline_npc_polish.py`：只重算基线逐列指纹、补新行，不走 `register_base_npc_ledger.py` 的"新增集合必须恰好是 NEW_ID"校验（重跑时那个断言必挂）。

**结论**：多会话并行时，改动清单要按"文件是否仍是 HEAD 版本"复核一遍，不能只看 `git status` 里有没有出现改动 —— 被回滚的文件是**干净**的。

## 状态

`BASE-NPC` = **partial**：逻辑链完整、专项通过、真实渲染四张（正式 99F 室内 + 提示）对照通过；NPC 系统的多项扩展能力未做。

账本：角色账本第 31 行 `CHR-PLY-BUNNY01-NPC-GREEN`（`原型已接入`，路径 `scenes/BaseNpc3D.tscn`），日志 `v0.1.27`；bunny01 根变体行补 `suit_green` 记法，日志 `v0.1.28`；基线均只刷新对应行与列指纹。
