# 主线开场03：抵达 99F 归航基地（关灯）

日期：2026-10-09；记录ID：`2026-10-09_opening03_base_dark`；功能ID：`NARRATIVE-TRIGGER`；工程版本：0.1.0。
设计依据与修订：[剧情触发 08](../08_技术施工_剧情触发.md) §3/§4/§5/§6 与 §13.9；
[剧情触发语义规范与跨局历史 方案](../design/2026-09-23_剧情触发语义规范与跨局历史_方案.md) §C.3。
代码基线：工作区（含并行会话未提交改动）；交付提交：提交前标记工作区。

## 变更与原因

主人要求制作「主线开场03」：主线进入 99F 基地时，触发点放在基地**东边门**位置；
基地起始为**关灯状态**；角色进门后说「这是哪里？」；镜头移到旁边的灯开关并适当拉近；
系统提示「打开房间的灯光」；镜头拉远回位、结束。所有剧情须经剧情模块，并更新设计文档。

**落地件**

| 件 | 路径 | 说明 |
|---|---|---|
| 剧本 | `data/narrative/nar_tower_opening_03_base_dark.json` | 位置触发 + 7 条 cue，`once=run`，`duration=8.4` |
| 目录登记 | `src/narrative/NarrativeCatalog.gd` | `ENTRIES` 新增第 3 条 |
| 适配器 | `src/narrative/NarrativeAdapter3D.gd` | ① `scene.light` 新增 `persist`；② 修掉该指令读不存在属性 `light_on` 的潜伏缺陷 |
| 真机探针 | `tests/verification/probe_opening03_base_dark_runtime.{gd,tscn}` | 端到端 13 项 |
| 几何探针 | `tests/verification/probe_opening03_base_geometry.{gd,tscn}` | 一次性实测基地几何（东/西门、开关锚点、楼梯路径点） |

**剧本分镜**：0.0 锁输入 + `scene.light facility off persist:true`；0.3 角色说「这是哪里？」；
3.6 `camera.focus pivot:light_switch room_id:facility preferred_entry:east distance:7.5 duration:1.4`；
5.2 系统字幕「打开房间的灯光」auto 2.6；7.0 `camera.restore`；8.4 `flow.end`。

**触发点（实测口径）**：`facility` 房中心 `(0,−12,5)`、无旋转；东墙门洞局部 `x=+15`、门心 `z=−2.5`。
触发点取局部 `(10, 0, −2.5)`、半径 2.5 —— 东门内侧 5m，且**避开** `facility→floor_01_entry` 楼梯的
`path_points[0]`（实测恰在东门门洞 `(15,−12,2.5)`）。放门洞正中会与该点相距恰好 2.5m = 半径而边界命中，
导致 `verify_tower_descent_flow` 在下楼用例里被演出抢输入（`input_locked` 拦掉 `set_test_move_direction`）而卡死。

**新语义（§6.1 的唯一显式豁免）**：`scene.light` 缺省仍是临时策略（收口强制归还）；
`persist: true` 明确声明「世界状态变更，收口不还原」—— 基地关灯要留住，等玩家自己按开关。

**兼容性**：`scene.light` 缺省行为一字未变；`camera.pivot` 新增 `light_switch` 模式属纯扩展。
未改 99F 基地默认灯态（`verify_tower_descent_flow` 断言其默认点亮，是活契约）。

## 验证结果

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| `probe_opening03_base_dark_runtime.tscn` | 独享 `APPDATA=_godot_appdata_nar03_run4`（全新） | **通过 13/13** | `_scratch/nar03/probe6.log` |
| `verify_narrative_timeline.tscn` | 独享 `APPDATA` | **通过 113 项**（EXIT=0） | `_scratch/nar03/verify_timeline2.log` |
| `verify_tower_descent_flow.tscn` | 独享 `APPDATA` | **通过（EXIT=0）** | `_scratch/nar03/verify_tower_descent_flow.log` |
| `verify_opening_script_runtime.tscn` | 独享 `APPDATA` | 122 项 / **1 项红**：`自动装备成功后地面剧情枪被正确接受（剩余 1）` | `_scratch/nar03/verify_opening_script_runtime.log` |

探针实测关键读数：起播即 `light_on=false` 且输入被独占；运镜 `pivot mode/room/entry = light_switch/facility/east`，
`camera→anchor = 7.500 m`（恰为剧本 `distance`）；收口后 `light_on` 仍 `false`（persist 生效）、相机与输入均归还。

**上述 1 项红与本段无关**：那是**开场01 的 `scene.spawn_item auto_equip` 在途改动**（地面剧情枪拾取后未被收掉），
本段未改该链路；`verify_narrative_timeline` 的 `grant/spawn` 机制项与本段自身的 `scene.light` 项均通过。

**执行受阻记录**：本次会话期间并行会话正在编辑 `src/world3d/Dungeon3D.gd`（15:44–15:51 之间一度缺
`_start_fate_card_idle_motion` 定义），该时段 `TowerDescent3D` 无法实例化，真机探针一度无法运行；
并行会话补回该函数后复跑通过。以上结果均取自树可编译之后的复跑。

## 遗留与状态更新

- 未替玩家开灯：剧本只把镜头对准东门侧灯开关并给提示，不写 `scene.light on:true`。
- 镜头只拉近、未改俯角（未给 `elevation_deg`）；观感是否够「看清开关」待在编辑器亲眼确认。
- 触发点取「东门内侧 5m」而非门洞正中，理由见上（避开楼梯口边界命中）。
- 设计文档已更新：[08 技术施工 §5.2 指令表 + 运镜枢轴 + §13.9](../08_技术施工_剧情触发.md)、
  [语义规范方案 §C.3 剧情表格](../design/2026-09-23_剧情触发语义规范与跨局历史_方案.md)。
- 未提交：本工作区改动尚未 commit（工作区内另有并行会话的未提交改动，不宜一并提交）。

## 追加：开场 2.5 —— 楼梯间提前关灯（同日返工）

**人报症状**（主人原话）：「因为我 99F 的基地灯默认是开启的，所以会有个很奇怪的地方，
就是我用剧本3进入基地后，灯光先是亮的，突然变暗，再进入剧情，非常奇怪。」

**根因**：99F 基地**默认点亮**是 `verify_tower_descent_flow` 明写的活契约（不能改），
而剧本 03 在玩家**已站进基地东门内侧**时才关灯 ⇒ 必然先看到一眼亮的基地、再看到它变暗。
不是剧本 03 的缺陷，是「关灯发生得太晚」。

**做法**：新增极短前置剧本 `nar_tower_opening_02_5_stairwell_blackout`
（`data/narrative/nar_tower_opening_02_5_stairwell_blackout.json`，已登记 `NarrativeCatalog.ENTRIES`）：

| 项 | 值 |
|---|---|
| 触发 | 世界坐标 **(42.501, −18.0, −18.5071)**、`radius 2.5`、`once run` |
| 位置 | 98F→99F 楼梯间**中段折角平台正中**（`path_points[04]` 与 `[05]` 的中点） |
| 动作 | 仅 `scene.light room_id:facility on:false persist:true`；**不锁输入、不运镜、不说话** |
| 时长 | 0.3s |

**为什么能写死世界坐标**：实测 4 个种子（990099 / 12345 / 777 / 424242）下 `facility` 固定 `(0,−12,5)`、
`floor_01_entry` 固定 `(27.5,−24,2.5)`、该楼梯 `path_points` **逐字节相同** ⇒ 楼梯几何与种子无关。
**为什么取中点**：抄近道切角时「`[06]` 直切 `[04]`」对中点的最近距离约 1.44m（命中），对顶点 `[05]` 约 2.72m（漏）。
**为什么不干扰玩家**：中段在基地外墙之外、且不在同一楼层，关灯时玩家看不见基地内部；不锁输入。
**剧本03 那行关灯保留**：`set_light_on()` 在已是目标态时 `changed==false`、不触发任何表现 ⇒ 幂等无感。

**验证**（追加）

| 命令/场景 | 环境及存档隔离 | 结果 | 日志/截图证据 |
|---|---|---|---|
| `probe_opening02_5_blackout_runtime.tscn` | 独享 `APPDATA`（全新） | **通过 10/10** | `_scratch/nar03/blackout2.log` |
| `verify_narrative_timeline.tscn` | 独享 `APPDATA` | **通过 113 项**（EXIT=0） | `_scratch/nar03/reg_verify_narrative_timeline.log` |
| `verify_tower_descent_flow.tscn` | 独享 `APPDATA` | **通过（EXIT=0）** | `_scratch/nar03/reg_verify_tower_descent_flow.log` |

探针关键读数：楼梯中段触发 2.5 · **触发后第 1 帧**灯暗 · 输入未被锁；从 2.5 起播到 03 收口
逐帧采样 **509 帧**，「灯亮」出现 **0 次**（无先亮后暗）。

**已知副作用（可接受、已实测）**：`verify_tower_descent_flow` 自身沿这条楼梯下行，因此**它跑动时也会触发 2.5**、
把基地灯关掉。实测该用例仍 EXIT=0 全绿 —— 它对灯态的断言全部发生在下楼**之前**，之后只断言 Boss 房灯态。

## 追加二：开场 2.5 触发点修正（同日，业主真机反馈「用不了」）

**人报**（主人原话）：「剧本2.5好像用不了。」

**根因（几何实测）**：折角平台是个 **8m × 2.887m 的矩形**，两条长边就是两条走法：

| 走法 | 所在边 | 老触发点（外缘 `z=−18.5071`）的最近距离 |
|---|---|---|
| 作者路径 `[06]→[05]→[04]→[03]`（绕外缘） | 外缘 `z=−18.5071` | 0 m ✅ |
| **真人抄近道 `[06]→[03]` 直线**（贴内缘） | 内缘 `z=−15.6203` | **2.887 m > 半径 2.5** ❌ **差 0.387m 不触发** |

初版把触发点放在**外缘中点**。我的验收当时是把玩家**瞬移**到触发点正中测的 —— 必然命中（**假绿**）；
真人抄近道走内缘时永远差 0.387m，症状就是「走到基地，灯还是亮的」。

**改法**：触发点移到平台**几何中心** `(42.501, −18.0, −17.0637)` —— 这是唯一能同时覆盖两条走法的位置（两侧各 1.443m）。

**验证**：探针 `probe_stairwell_walk_blackout.tscn`（**绿**）：

```text
几何：内缘线中点距触发点 1.443m / 外缘线中点距触发点 1.443m （都在半径 2.5 内）
瞬移到「抄近道最不利位置」（内缘线中点）→ 剧本 2.5 真的起播 · 基地灯转暗
```

## 追加三：剧本 02 按 F 后一并关闭系统对话框（同日）

**人报**（主人原话）：「剧本2，按完 F 后，系统对话框也需要一起关闭。」

**根因**：`ui.hint` / `ui.subtitle` / `ui.dialogue` 三条都返回 `_ok()` —— **没登记任何归还项**。
而 §5.2 早就写明 `ui.hint` 的 `auto = 0` 是「保持到显式交互**或剧情收口**」，后半句一直没实现。
剧本 02 那句「打开你身上的手电…」（`auto: 0`）因此在按 F 收口后继续挂在底栏。

**改法**：
- `src/ui/dialogue/DialogueUI.gd`：新增只读查询 `current_run_id()`（当前在播的 run_id，没在播为空串）。
- `src/narrative/NarrativeAdapter3D.gd`：三条 `ui.*` 改为登记改还（`_done(_restore_dialogue)`），并记下最近一次摆上去的 run_id；
  `_restore_dialogue()` **只关自己摆的那条**（`current_run_id()` 与记录一致才关），不误关别的系统后来播报的消息。

**验证**（加进既有真机验收 `verify_opening_script_runtime` 的 J 段，它本来就完整跑「走进会议室 → 等待手电 → 真实 F → flow.end」）：

| 命令/场景 | 结果 | 证据 |
|---|---|---|
| `verify_opening_script_runtime.tscn` | **绿**：126 项中 4 条新增断言全过（等待期提示在播 / 文本含「手电」/ **收口后 is_active=false** / current_run_id 为空） | `_scratch/nar03/final_verify_opening_script_runtime.log` |
| `probe_stairwell_walk_blackout.tscn` | **绿**（触发点覆盖） | `_scratch/nar03/walk3.log` |
| `verify_narrative_timeline.tscn` | **通过 113 项** | `_scratch/nar03/final_verify_narrative_timeline.log` |

⚠️ 该验收仍带**既有**红项 1 条（`自动装备成功后地面剧情枪被正确接受（剩余 1）`，属开场01 的 `auto_equip` 在途改动），
与本次两处修正无关；本次新增断言全部通过。
