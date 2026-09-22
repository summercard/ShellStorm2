---
name: 10-narrative-timeline-authoring
description: 当用户说「做一段剧情」「加个剧情触发」「这里演一段」「进这个房间说句话」「触发一段演出/对话」时使用。负责把剧情意图落成 ShellStorm2 的**时间轴剧本**（JSON）+ **触发声明**，跑校验并登记。触发器以时间轴为主、可控制几乎所有系统（输入/相机/角色/特效/音效/UI/门/灯/刷怪/道具），配套占用清单强制收口。不实现指令本身（属剧情系统本体）、不改玩法数值、不写存档格式、不擅自编写主线剧情内容。
agent_created: true
metadata:
  display_name_zh: 10 剧情时间轴编排
---

# 10 剧情时间轴编排

把「这里该演一段什么」变成一份可校验的**时间轴剧本**，加一个**触发声明**。

## 路由表

| 用户意图 | 该走 |
|---|---|
| 说「做一段剧情」「加个剧情触发」「这里演一段」「触发对话」 | **本 Skill** |
| 要填剧情设计表、要把剧情意图落成剧本数据 | **本 Skill** |
| 要新写 / 改一个**指令**（剧情系统能干什么） | 不是本 Skill —— 那是剧情系统本体，走 `docs/v0.1/08_技术施工_剧情触发.md` §5 |
| 要加**新的触发事实**（如"击败某个 Boss"） | 不是本 Skill —— 需要先在 `Dungeon3D` 补上行事件，见 §4.2 ⛔ 清单 |
| 改对话 UI 的显示 / 打字机 / 层级 | `docs/v0.1/18_技术施工_UI与对话系统.md` |
| 做关卡几何、房间表、刷怪计划 | `09-level-plan-authoring` |
| 调数值、掉落、存档格式、战斗规则 | **不在本 Skill 范围**，直接说明并拒绝 |

---

## 0. 真相源与落位

### 0.1 权威文档

**唯一权威：** `docs/v0.1/08_技术施工_剧情触发.md`（v0.2）。本 Skill 是它的**操作手册** —— 两处冲突时以文档为准，并回来修正本文件。

对话载体（底栏 / 头顶气泡）的契约在 `docs/v0.1/18_技术施工_UI与对话系统.md`，本 Skill 只调用、不定义。

### 0.2 剧本放哪

| 件 | 路径 | 说明 |
|---|---|---|
| 剧本本体 | `data/narrative/<narrative_id>.json` | `narrative_id` 与文件名同名 |
| 剧本索引 | `src/narrative/NarrativeCatalog.gd` | `id → 路径` 映射 + 存在性校验，沿用本工程既有的 `MusicCatalog` / `EliteContentCatalog` 内容目录写法 |
| 触发脚本（仅特殊情况需要） | 挂在**任意已有节点**上，不新建 Area3D | 见 §4.1 |

**为什么不把剧本写进 `.gd`**：剧本是嵌套有序结构（时间轴 + 每 cue 独立参数），写成 GDScript 字面量既难读也无法被校验器逐值比对。项目已有 JSON 内容先例（关卡布局清单、`asset_manifest.json`）。

### 0.3 当前实现状态（动手前必看）

<div style="color:#2E7D32;background:#E8F5E9;padding:8px 12px;border-radius:8px">

**截至 2026-09-21，剧情系统本体已落地**：`src/narrative/` 四件（解析校验 / 内容目录 / 导演 autoload / 适配器），
剧本在 `data/narrative/*.json`，两条开场剧本已就位。

⇒ 产出剧本后**必须跑验收**，不要只说"应该能跑"：

```bash
# 逐场景验收（不看裸退出码，看 mark + 引擎错误面）
/i/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe \
  --headless --path . res://tests/verification/verify_narrative_timeline.tscn > _scratch/narrative/run.log 2>&1
grep -E "verify_narrative_timeline_(OK|FAIL)" _scratch/narrative/run.log
python scripts/check_verification_log.py _scratch/narrative/run.log \
  tests/verification/expected_errors/verify_narrative_timeline.txt
```

`verify_narrative_timeline` 覆盖：目录登记 / JSON 校验 / radius 与 duration 的反向对照 /
同帧顺序 / 降级不停摆 / 暂停冻结 / 两条真实剧本的「触发 → 接管 → 收口归还」。

**开场类剧本（冷启动第一章）加跑一条真机验收** —— 它跑真塔楼 + 真开场页，普通 headless 验收看不到开场页：

```bash
/i/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe \
  --headless --path . res://tests/verification/verify_opening_script_runtime.tscn > _scratch/narrative/opening.log 2>&1
grep -E "verify_opening_script_runtime_(OK|FAIL)" _scratch/narrative/opening.log
```

它盯四个**不报错**的缺陷：开场是否真的锁死操作 / 镜头是否真的俯冲 / 中间是否被鼠标顶掉 / 收工是否交回键盘与开枪。

</div>

---

## 1. 动手前的必读（按顺序）

1. `docs/v0.1/08_技术施工_剧情触发.md` —— §3 时间轴模型、§5 指令表与状态、§6 收口、§4.4 可用触发事实
2. `docs/v0.1/18_技术施工_UI与对话系统.md` §1.1 —— 底栏 vs 头顶气泡怎么选
3. 现有剧本（有的话）作为格式基线：`data/narrative/`
4. 要调的系统的真实接口 —— **不要凭记忆写参数名**，去读源码（§5 表每行都给了文件与行号）

---

## 2. 剧本 schema（时间轴）

### 2.1 顶层

```json
{
  "narrative_id": "nar_expedition01_room03_intro",
  "schema_version": 1,
  "duration": 8.0,
  "priority": 0,
  "trigger": { "kind": "point", "point": [42.5, 0.0, -12.5], "radius": 5.0, "once": "run" },
  "cues": [ ... ]
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `narrative_id` | ✅ | 稳定 ID，与文件名同名；**改内容不改 ID**（触发脚本与索引都按它引用） |
| `schema_version` | ✅ | 当前 `1` |
| `duration` | — | 总秒数。缺省 = 最后一条 cue 的 `at` |
| `priority` | — | 默认 `0`。强叙事给正数、氛围提示给负数（同一时刻只播一场，见 §6 禁区） |
| `trigger` | — | 缺省 = 只能被代码手动触发 |
| `cues` | ✅ | 按 `at` 升序；同一 `at` 按数组顺序执行 |

### 2.2 cue

```json
{ "at": 3.6, "do": "fx.vfx", "asset_id": "vfx-narrative-glint-3d", "at_actor": "player", "anchor": "head" }
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `at` | ✅ | 相对剧本开始的**绝对秒数**，`>= 0` |
| `do` | ✅ | 指令名，`域.动作`（§3） |
| 其余 | — | 该指令自己的参数 |

**同时发生 = 写同一个 `at`。** 没有"等上一条做完"的机制（那是 v0.1 的旧模型，会永久挂起，已废弃）。

### 2.3 时间排版公式（**必须算，不要拍脑袋**）

时间轴的质量取决于 `at` 排得对不对。一句话的**最小占位**：

```text
打字时长 = 字符数 / chars_per_sec
           · 底栏 DialogueUI：chars_per_sec 默认 30.0
           · 头顶气泡：见 SpeechBubble3D 实现

阅读停留 = 3.0 秒（保守值；气泡默认 hold_seconds = 3.4）

下一句的最小 at = 上一句 at + max(2.5, 打字时长 + 阅读停留)
```

**举例**：`"……这里还有电。"` = 8 个字符 → `8/30 = 0.27s` → `max(2.5, 0.27+3.0) = 3.27` → **下一句至少排在 +3.3s**。

排完要**报给用户核对**：把 `时刻 → 动作` 的清单列出来（像分镜脚本），让他确认节奏。**不要自己定稿就交付。**

**镜头动作单独占时**：`camera.focus` / `camera.restore` 有 `duration`，它自己的过渡时间里不要再压别的动作 —— 否则观众既看不清镜头又读不完字。

---

## 3. 指令表

### 3.1 八域

`flow` / `player` / `camera` / `actor` / `fx` / `ui` / `scene` / `grant`。**权限很大**：输入、相机、角色、特效、音效、UI、门、灯、刷怪、道具、关卡流程都能控。

### 3.2 速查表

> **唯一权威是 `08` §5.2**（含每个接口的文件与行号）。本表是速查，状态会随实现推进变化 —— 冲突时以文档为准。

**✅ 已实装，可直接写：**

| 指令 | 关键参数 |
|---|---|
| `player.lock_input` | `locked` |
| `player.combat` | `enabled` |
| `player.teleport` | `point` / `at_room` |
| `actor.say` | `who` / `text` / `hold` |
| `actor.show` / `actor.hide` | `who` |
| `fx.vfx` | `asset_id` / `at_actor` / `anchor` / `color` / `size` |
| `fx.sfx` | `name` / `volume_db` / `pitch` |
| `fx.music` / `fx.music_push` / `fx.music_restore` | `id` |
| `ui.subtitle` | `speaker` / `text` / `auto` |
| `ui.dialogue` | `lines` / `interrupt` |
| `ui.hint` | `text` |
| `scene.door` | `room_id` / `direction` / `open` |
| `scene.door_policy` | `room_id` / `policy` |
| `scene.light` | `room_id` / `on` |
| `grant.item` | `item_id` / `count` |
| `grant.flag` | `key` / `value` |
| `flow.end` | — |
| `flow.mark` | `key` |

**✅ 2026-09-21 新接通（本表已过期过一次，用前对一下 `08` §5.2）：**

| 指令 | 关键参数 | 备注 |
|---|---|---|
| `player.invulnerable` | `who` / `enabled` | 复用 `Player3D.is_invincible`（**不是新增开关**） |
| `camera.focus` | `distance` / `elevation_deg` / **`pivot`** / `pivot_m` / `room_id` / `duration` | `elevation_deg` **可选**；不给时俯角沿用玩法镜头。`pivot` 默认玩家 |
| `camera.pan` | `yaw_deg` / `elevation_deg` / **`pivot`** / `pivot_m` / `room_id` / `duration` | 绕**枢轴**竖轴甩（可选压俯角）。**正角 = 视线向左摆**（见 §7 坑 13） |
| `camera.restore` | `duration` | 距离 / 方位 / 俯角 / **枢轴**一起回，再放权给玩法镜头 |
| `actor.pose` | `clip` / `phase` / `to_phase` / `duration` / `frozen` | 相位锁。趴↔起身 = `dead` 相位 1.0↔0.0 |
| `actor.face` | `yaw_deg` / `relative` / `duration` | `relative: true` = 在接管前朝向上叠加（张望用） |
| `scene.spawn` | `room_id` / `kind` / `count` / `spread` / **`point_room` + `point_offset`** / **`axis`** / **`stagger_m`** / `side` / `distance` / `forward_m` | 只有**和平区/空房**才是必要的；战斗房本来就会自己刷怪 |
| `scene.despawn` | `room_id` | 只清带 `narrative_spawned` 标记的怪，不动关卡原有的 |

<span style="color:#791F1F">**要"镜头从上往下压"，必须给 `elevation_deg`；只改 `distance` 不叫俯冲。**</span>
只改距离时相机只会沿同一条「玩家→相机」轴滑动，观感是**推近拉远** —— 实测俯角全程 **69.4° 零变化**；
给 `elevation_deg: 34.0` 才真的 69.4° → 34.0°。`elevation_deg` 是相机相对玩家的**世界仰角**
（`atan2(相机高出玩家, 水平距离)`），**不是增量**；不给 = 沿用接管前玩法镜头那套俯角。
数值依赖房间几何，别照抄（见 §7 坑 17）。

**运镜枢轴 `pivot`（可选，默认 `player` = 焦点钉在主角身上）**：要「脱开主角、整台机位平移过去拍别处」就给 ——
`pivot: "last_spawn"`（绕最近一次 `scene.spawn` 的队列中心，**零坐标**）、
`pivot: "room_center"` + `room_id`（绕房间中心）、
`pivot_m: [x, y, z]`（显式世界坐标，最优先）。
枢轴按同一个 `duration` **平滑插值** ⇒ 是平移不是瞬移；`restore` 会把它带回玩家。
拿不到目标点会**告警并退回玩家**；脱开后**不处理遮挡**，取景处自己留空。

**🔶 仍需新增，写了会降级跳过（会告警）：**

`player.heal` · `player.damage` · `player.move_dir`（仅调试）· `camera.shake` ·
`actor.turn_to` · `actor.npc_state` · `ui.letterbox` · `scene.enemy_ai` · `grant.unlock`

**⚠️ 能力受限：**

| 指令 | 限制 |
|---|---|
| `actor.action` | 玩家侧**无具名动作 API**（clip 由状态派生）；敌人侧仅 2 只普通怪有 `AnimationPlayer`。只能做现有 8 态 |
| `fx.vfx` | **定点**，无跟随锚点（v0.2 不做） |

### 3.3 降级语义

任一条降级（指令不存在 / 未实现 / 对象找不到 / 参数不对），**时间轴照走**，后面的 cue 不受影响，剧本仍在 `duration` 结束。

⇒ **不要用"某条一定会执行"来做剧本骨架。** 骨架要用时间轴本身（`duration` 保证结束）。

### 3.4 两条铁律

1. **经适配器，不抓节点路径。** 剧本与触发脚本里**不得**出现 `get_node("../../Player3D")` 这类路径。用稳定 ID：`who = "player"`。
2. **改了独占资源，不用手写还原。** 系统按**占用清单**在结束 / 中断时强制归还（输入锁、相机、战斗开关、免疫、音乐、黑边、门的临时策略）。作者**不要**在最后一条 cue 里手写"还原"—— 但**可以**显式还原来做"演到一半就恢复"的效果。

---

## 4. 触发声明

### 4.1 三种

| 方式 | 写法 | 适用 |
|---|---|---|
| **位置** | `kind: "point"` + `point_room` + `point_offset`（**首选**，房间相对）或 `point`（世界坐标）+ `radius` | "走到这块地方" |
| **事件** | 剧本 `trigger` 里写 `kind: "event"` + `event` + `filter` | "进房 / 清房 / 击杀 / 开门 / 撤离……" |
| **脚本** | 写一个几行的 `NarrativeDirector.arm(...)` 挂到任意已有节点 | **任意特殊情况**（组合条件、自定义判定） |

**位置触发的 `radius` 下限是 `1.0`**（校验器强制）。为什么：判定是 0.1s 轮询不是事件，玩家 8m/s 时单次间隔位移约 0.8m，半径太小会穿过去漏触发。

**垂直带**：`point` 的 `y` 会与玩家高度比，默认容差 `2.0`m —— 防止楼上楼下误触发。写 `point` 时**要填真实世界坐标的 y**，不要一律写 `0`。

**位置触发优先用房间相对写法。** `point` 要写世界坐标，而房间是运行时生成的 —— 写死坐标在换布局后会
**静默失效**（症状是「剧情永不触发」）。改用 `point_room: "<房间id>"` + `point_offset: [dx,dy,dz]`
（相对**房间中心**），世界坐标由导演运行期用 `room.to_global(offset)` 解出。
实测：会议室中心 `(−5, −24, 2.5)` + offset `[-14, 0, 0]` ⇒ 进门 6m 处的触发点。

**刷怪站位**：`scene.spawn` 也支持房间相对锚点（`point_room` + `point_offset`）—— 位置触发之后玩家落点会浮动，
玩家相对的站位跟着抖，要钉住就用房间相对。`axis` 选排列方向（`"forward"`/`"x"`/`"z"`），`stagger_m` 让相邻两只
沿垂直方向交错错开，别站成一条笔直的队。

**什么时候该换位置触发**：`room_entered` 在玩家**刚跨进门**那一刻就发 —— 那时门还没关、人还站在门口，
一切「基于玩家位置」的刷怪与运镜都会贴着门口（第二段「怪刷在门口」就是这么来的）。要演出发生在
**进门之后**，就换成位置触发 + 一个进深 offset（玩家走进来、门自动关上，才起跑）。

### 4.2 可用事实清单（**必须对照**）

<div style="color:#791F1F;background:#FCEBEB;padding:8px 12px;border-radius:8px">

**带 ⛔ 的当前接不上，不要写进剧本。**

</div>

| `event` | 状态 | 备注 |
|---|---|---|
| `point` | ✅ | 本系统自建 |
| `room_entered` | ✅ | 过滤 `room_id`。**开场演出不要用**，见下 ⚠️ |
| `gameplay_started` | ✅ | 开场页动画播完 / 没有开场页时的帧末。**开场类剧本只能挂这个** |
| `room_cleared` | ✅ | |
| `kill_recorded` | ✅ | **不带身份**，只能表达"又杀了一个" |
| `door_motion_finished` | ✅ | |
| `light_toggled` | ✅ | |
| `extraction_started` / `extraction_completed` | ✅ | |
| `run_completed` | ✅ | |
| `hp_ratio_below` | ✅ | 本系统自建（阈值比较） |
| `kill_of_elite` | ⛔ | 无精英"遇见"上行事件 |
| `boss_defeated` | ⛔ | **无法区分击败的是哪一个 Boss** |
| `floor_entered` | ⛔ | 代码中不存在 |
| `item_acquired` | ⛔ | 未确认有上行事件 |

<span style="color:#791F1F">**⚠️ 开场演出（冷启动第一章）必须挂 `gameplay_started`，不能挂 `room_entered`。**</span>

`room_entered` 在场景 `_ready()` 里就发，那一刻开场页还在接管相机与输入。挂上去会出现四个**全都不报错**的症状：
① 一开场玩家能操控（开场页随后把输入锁写回"可操作"）；
② 镜头不俯冲（抢到的基准是**近景机位**俯角 24.6°，不是玩法机位 69.4°）；
③ 中间错乱（开场页与剧情逐帧互写同一台相机、鼠标还能改写剧情摆好的朝向）；
④ 收工后键盘与开枪全废、鼠标还能转（收口把开场页写进去的 `true` 当"原值"写回）。

⇒ **`room_entered` 只用于"进到某个房间演一段"（玩法已经在跑的时候）。开场一律 `gameplay_started`。**

**用户如果要求"击败某个 Boss 后演一段"**：如实说明当前买不到这个事实，需要先补身份化击杀事件（独立任务）；**不要假装已经支持**，也不要绕过 —— 用 `room_cleared` + 房型判断顶替会产生"打任何 Boss 都触发"的错误行为。

---

## 5. 五步流程

### 第 1 步 · 收集剧情意图

要问清楚的（缺哪项就问哪项，**不要猜**）：

| 要确认的 | 为什么问 |
|---|---|
| **演什么** | 台词（逐句）/ 要不要镜头 / 要不要特效音效 / 要不要发东西 |
| **什么时候演** | 位置 / 事件 / 特殊情况；`once`（一次还是每次） |
| **在哪演** | 关卡 id、房间 id、或世界坐标 |
| **谁说话** | 有实体（玩家 / NPC）→ 头顶气泡；无实体（系统 / 旁白）→ 底栏。**一次演出里两种可以混用** |
| **大概多久** | 决定 `duration` |
| **能不能被打断** | 决定 `priority` |

**最少需要用户给的**：演什么 + 在哪 / 什么时候触发。

**不要问用户的**（本 Skill 自己算）：
- `at` 的具体秒数（按 §2.3 公式推，推完给用户核对）
- `duration`（= 最后一条 cue 的 `at`，除非用户指定）
- 还原类 cue（占用清单自动搞定）
- 触发半径（默认 5.0，除非用户指定场地很窄）

### 第 2 步 · 排时间轴（先给分镜，再写文件）

按 §2.3 公式把 `时刻 → 动作` 排成清单，**贴给用户确认**：

```text
0.0s   锁输入 + 禁战斗
1.0s   [气泡] 玩家：……这里还有电。           （打到 1.3s，读到 4.3s）
3.6s   镜头推近（1.2s 过渡）
3.6s   [底栏] 系统：检测到微弱信号源。       （自动消失 3.0s）
6.5s   镜头还原（0.9s）
8.0s   收口（自动：解锁 + 恢复相机 + 恢复战斗 + 摘免疫）
```

用户改完节奏再往下走。

### 第 3 步 · 写剧本 JSON

落 `data/narrative/<narrative_id>.json`：

- **CRLF 行尾**（本工程铁律，`.json` 也不例外）
- 缩进 2 空格
- cue 按 `at` 升序排列
- `narrative_id` 用 `nar_` 前缀 + 语义（`nar_expedition01_room03_intro`）
- `grant.item` 的 `item_id` 必须是**内容 ID**（走 `10_资产与内容规范`），不确定就让用户给

### 第 4 步 · 写触发声明

- 位置 / 事件 → 写进剧本的 `trigger` 字段，**不用写代码**
- 特殊情况 → 写触发脚本（见 §4.1），挂在任意**已有**节点上

**触发脚本只做判定**，判定为真就交棒给时间轴 —— 不要在脚本里执行演出动作。

### 第 5 步 · 登记与报告

- 把剧本加进 `src/narrative/NarrativeCatalog.gd` 索引（**唯一登记点**）
- 若剧本套用了尚未实现的 🔶 指令，**在报告里逐条列出**，说明"这些步骤当前会降级跳过"
- 报告给出：剧本路径、分镜清单、用到的指令及其状态、**没做的事**

---

## 6. 禁区

| 不要做 | 为什么 |
|---|---|
| 用 `get_node("路径")` 抓玩家 / 相机 / UI | 适配器是唯一耦合点。抓路径 = 换场景剧本全废，且验收有正则扫源码会红 |
| 在剧本里写"等对话结束再下一步" | v0.2 没有 `wait_for`。要等就排时间；排不了就拆成两个剧本 |
| 手写"还原输入 / 还原相机"的收尾 cue | 占用清单会强制归还。手写反而可能把"演到一半恢复"的效果覆盖掉 |
| 把 🔶 状态的指令当已实现来设计剧本骨架 | 它们会降级跳过。骨架只能用 ✅ 的指令 + 时间轴本身 |
| 在剧本或脚本里写 `kill_of_elite` / `boss_defeated` | ⛔ 当前接不上（§4.2）。写了不报错但永远不触发 |
| 写"打任何 Boss 后触发"来顶替某个 Boss | 会产生"打错 Boss 也演"的错误行为。如实说明需要补事件 |
| 给触发点建 `Area3D` / `CollisionShape3D` | 性能门禁 `total` 余量只剩 **11 个节点**。位置触发走距离轮询，零新增常驻节点 |
| 把触发半径写到 < 1.0 | 会漏触发（§4.1），校验器直接拒 |
| 同一时刻安排两场剧情 | v0.2 只允许一场在播，新的会被丢弃（除非 `priority` 更高） |
| 编排"主线剧情内容"（角色关系、章节、结局） | 主线未冻结。本 Skill 只做**系统能力与作者规范**，占位内容不得标为最终完成 |
| 让剧情承担**强制系统提示**（如隔离间"无法返回、未拾取物永久丢失"） | 那类提示**不得被剧情跳过或因剧情故障消失**，必须独立于剧情队列；剧情只能在其前后追加氛围 |
| 在剧本里写数值（伤害 / 血量 / 掉率） | 数值真源在各系统。剧情只"喊人干活" |
| 用 `grant.item` 发不确定的 `item_id` | 会静默发不出（降级跳过）。必须走内容规范确认 |

---

## 7. 已知坑

1. **时间轴不冻结世界。** 演出期间敌人照动、玩家照挨打。剧本只要有 `lock_input`，系统会自动挂受击免疫（不掉血）—— **这是默认行为，不用写**。但玩家**能看见**敌人在动，所以重要演出**尽量安排在和平房 / 已清房**，或者用 `scene.enemy_ai` 临时压制（该指令当前是 🔶）。
2. **暂停会冻结剧情，但底栏对话默认不冻。** `DialogueUI` 是 `PROCESS_MODE_ALWAYS`，暂停时它仍在打字并自动推进。系统会调它的暂停入口处理；若你改了对话 UI 的 `process_mode`，**会打破它自己的独立验收**。
3. **气泡与底栏的取舍不是审美问题。** 说话人**有实体**（玩家/NPC/敌人）→ 头顶气泡；**无实体**（系统/旁白/区域播报）→ 底栏。选错的症状是"系统提示挂在角色头上"。
4. **头顶气泡的挂高是常量。** `Dungeon3D.PLAYER_BARK_HEIGHT_M = 2.55`（2026-09-21 从 1.95 提起，因为原高度挡住角色）。相机俯角变化时这个值可能要再调。
5. **气泡/底栏文字不要写超长。** 气泡随文字自适应尺寸，过长会横跨半个屏幕；底栏只有约 122px 高（`PANEL_HEIGHT`），超过 2 行会溢出。**一句话控制在 30 字内**。
6. **`ui.subtitle` 的 `auto` 参数决定要不要玩家按键。** `auto > 0` = 到点自动消失（系统提示用）；`auto = 0` = 等玩家按回车（重要台词用）。**系统提示一律给 `auto`**，否则会卡住跑动的玩家。
7. **行动存档续局会重复触发。** `once: "run"` 是本局内存态，中途存档退出、续局后会再来一次。当前已知并接受；需要严格一次要等跨局历史落地。
8. **`.json` / `.gd` / `.md` 一律 CRLF。** 用别的工具生成常是 LF，不转会让门禁报行尾不纯。
9. **脚本快照不要落 `res://` 内。** 带 `class_name` 的副本会抢注类型、覆盖 `.godot` 类缓存，导致"找不到类型"的假故障。临时文件放项目外或 `_scratch/`（且该目录已有 `.gdignore` 纪律）。
10. **新增 `class_name` 后跑场景前先 `--import`** 刷 `.godot/global_script_class_cache.cfg`，否则报"找不到类型"（假故障）。
11. **不要只信 `*_OK`。** 验收脚本可能有"0 样本空跑照样绿"的假绿形态 —— 每个断言都要打印样本数，0 时告警。
12. **验收会写 `user://`**（`GameTimeManager` 定时刷档）。跑验收**前快照、后还原**用户目录，无论成败。
13. **`camera.pan` 的符号方向是反直觉的。** 运镜是**绕玩家的刚性旋转**（相机位置与朝向被同一个 `orbit` 一起转），
    所以焦点**恒在玩家身上**：**正角把相机甩到玩家右手边 ⇒ 视线向左摆**；要让视线**向右**摆（把玩家右侧的东西
    纳入画面）必须用**负角**。写反了不会报错，只是镜头往反方向转。
14. **调运镜别靠肉眼试，读验收打印的构图数。** 验收会逐帧测僵尸队列的**画面水平偏角**（与 FOV/分辨率无关）：
    `camera.pan / -62` → 队列 0.7°（正中，还被角色挡住）；`camera.pan / -26` → 16.3°（右侧，与角色分离）。
    改 `yaw_deg` → 重跑 → 看 `C2 构图采样` 那一行。
15. **三处"断了也不报错"的接线，改代码时别踩：**
    · `Dungeon3D._sync_player_input_lock()` **每帧重算** `input_locked`，必须让它认演出的输入独占
      （`is_player_input_locked()`），否则剧本写"停住"而玩家照常能动，日志干净得像没事发生；
    · 同一处的**归还**必须走 `refresh_player_input_lock()`（重新裁决），**不能写回接管瞬间的快照** ——
      `input_locked` 是多系统共用的，写回快照 = 替开场页/背包/模态做决定。写错的症状是
      "**收工后键盘与开枪全废、鼠标还能转**"（鼠标瞄准不受 `input_locked` 约束，所以只有"能转向不能开枪"这一个线索）；
    · `NarrativeDirector` 认领"带 `room_entered` 的节点"是靠 `_on_node_added` 自动绑定的 —— 它断了剧情永不触发，
      同样零报错。验收对这几条各有一道源码级 / 运行时守卫。
16. **开场演出挂错触发源，四个症状一个都不报错。** 见 §4.2 的 ⚠️。判据只有真机才测得到 ——
    `_install_main_entry_screen()` 在 `test_mode / headless` 下**直接 return**，所以普通 headless 验收
    **根本看不到开场页**。要验开场必须手工挂 `MainEntryScreen3D.tscn`，并让塔楼走它自己的
    `_defer_gameplay_started()` 真接线（做法见 `tests/verification/verify_opening_script_runtime.gd`）。
17. **`elevation_deg` 的数值依赖房间几何与玩法镜头构图**，不是通用常量。`floor_01_exit` 实测玩法镜头俯角
    69.4°、剧本压到 34.0°。换房间 / 换镜头参数后重跑探针读实测降幅，**别照抄角度**。
18. **`actor.face` 的 `relative: true` 是"相对本条 face 序列的基准"，不是"相对上一帧"。** 写 `+32` → `-32` → `+32`
    才是左右张望；它不会被累加，所以"回头"也只写 ±32。另外**剧情接管朝向期间鼠标瞄准会被有意让位** ——
    别把"剧情里鼠标转不动"当 bug 去查。
19. **姿态锁（`actor.pose`）在相位过渡走完时由系统自动交还角色系统。** 不交还的话角色会**永久僵在倒地剪辑的第一帧**、
    待机动画根本不播，观感是"起身之后硬转身体"，全错。所以 `to_phase` 那条 cue 之后不用（也不该）再写还原。

20. **`once` 只活在「本局内存态」，它的归零点是「复位存档」，不是「重开场景」。** 冷启动开场剧本挂
    `gameplay_started` + `once: run`，靠 `_armed[].fired_count` 记账（08 文档 §9：不进存档）。复位存档走
    `change_scene_to_file`、autoload 存活 ⇒ 少了 `NarrativeDirector.reset_run_state()` 就**永远不再触发**。
    症状是「复位存档、重新开始后开场剧情整个消失」，**零报错**。该复位由 `BaseManager.game_save_reset_completed`
    驱动（已实装）。反面：**中途中存档 → 退出 → 续局，`once` 会重复触发**（08 §8.6，v0.2 明确接受）。
    另：改叙事脚本时**不能**用 `get_node("/root/…")` 取别的 autoload —— `src/narrative/**` 禁路径字面量，
    只能用全局标识（`BaseManager` / `DialogueUI` 同款），否则 `verify_narrative_timeline` 直接变红。

21. **`scene.spawn` 的队列默认贴着玩家 —— 触发发生在你**刚跨进门**那一刻，`forward = distance*0.5` 只有两三米，最后一只甚至压在你身后（门线上）。要「怪在房间里侧」就写 `forward_m`（沿视线额外前推，独立于 `distance`）。⚠️ 两个连带效应：① 前推会把队列推向**画面正中**（相机右移构图被破坏）⇒ 要同时加大 `distance`；② 前推会拉大相机到队列的距离 ⇒ `verify_narrative_timeline` 的构图带宽（偏角 12~24°、深度 8~13.5m）会拦住你，别硬放宽带宽去迁就，先确认是你真的要换构图。

---

## 8. 交付自检

- [ ] 用户给全了"演什么 + 什么时候触发"才动手，没替他猜内容
- [ ] 分镜清单（`时刻 → 动作`）**先给用户核对过**，再写文件
- [ ] `at` 按 §2.3 公式排的（打字时长 + 阅读停留），不是拍脑袋
- [ ] 台词时长与 `duration` 自洽（最后一句读完 → 才收口）
- [ ] 剧本落 `data/narrative/<narrative_id>.json`，已加进 `NarrativeCatalog` 索引
- [ ] 说话人选对了载体（有实体→气泡 / 无实体→底栏）
- [ ] JSON 里出现 `get_node` 一类路径字符串（应为 **0**）
- [ ] 没有写 ⛔ 触发事实（`kill_of_elite` / `boss_defeated` / `floor_entered` / `item_acquired`）
- [ ] 没有手写"还原"收尾 cue
- [ ] 位置触发的 `radius >= 1.0`，且 `point` 的 `y` 是真实高度
- [ ] 用到的 🔶 指令已在报告里逐条列出，说明会降级跳过
- [ ] 报告写明：剧本路径 + 分镜 + 指令状态 + **没做的事** + **验收命令与结果**（mark + 引擎错误面）
- [ ] 真实剧本已跑 `verify_narrative_timeline`，且**红项 ⊆ 已知基线**（跑前先列基线，别把别处的红当自己的）
- [ ] 开场类剧本**加跑** `verify_opening_script_runtime`（真塔楼 + 真开场页；headless 验收看不到开场页）
- [ ] 运镜类剧本看过验收打印的**构图偏角**，不是"我觉得应该对"
- [ ] 要"从上往下压"的镜头写了 `elevation_deg`（只给 `distance` 不叫俯冲）
- [ ] **开场演出挂的是 `gameplay_started`**，不是 `room_entered`
- [ ] 所有文件 CRLF
- [ ] 报告末尾**没有**用计算机术语向用户解释待决策项（说影响，不说字段名 / 内部机制）
