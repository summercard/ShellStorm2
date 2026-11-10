# 死亡归航的绿苔台词支持点击/空格快速过（2026-11-10）

业主原话：「死亡回到基地后，绿苔的对话也要能点击快速过。」

规则主源：[对话与战斗信息呈现设计 §基地救援演出推进](../design/对话与战斗信息呈现设计.md)；
接口细节见[18 号技术施工 §12.3.2](../18_技术施工_UI与对话系统.md)与[20 号技术施工](../20_技术施工_基地NPC.md)。

## 1. 问题是什么

死亡归航后绿苔那两句由 `Base99Rescue3D` 的协程按 `LINE_HOLD_SECONDS = 3.2` 铺开，**不经过
NarrativeDirector 的时间轴**。因此：

- 导演手里没有载体，`can_advance_mouse_dialogue()` 在「无时间轴演出」分支只查
  `_adapter.free_dialogue_actor()`；
- 那个方法只认 `is_free_bark_active()`，而演出期间 NPC 处于 scripted 状态
  （`_scripted_active` 为真）⇒ 一律 false；
- 于是左键既不进「全显」也不进「下一句」，还会被当成普通玩法输入漏给开火；
- Space 更直接：`_input` 里 `if _active.is_empty(): return`，根本到不了推进。

同一套「先全显、再收句」的语义在三处（底栏、剧情气泡、自由交谈）都已生效，只有这段漏了。

## 2. 改法

| 层 | 改动 | 为什么放在这 |
|---|---|---|
| `Base99Rescue3D` | `_ready` 加入 `rescue_cutscene_3d` 组；新增 `can_advance_rescue_line()` / `advance_rescue_line()` | 句子指针、顺序、停留、起身时机本来就只在这里，推进只能借气泡把「这句」提前收掉，不能在外面另记游标 |
| `NpcCharacter3D` | 新增 `is_scripted_line_progressable()` / `advance_scripted_line()` | 打字进度只归 `CharacterBark3D`，NPC 只做窄转发；与 `is_free_bark_active()` 分开，避免把「脚本演出」误当成「自由交谈」 |
| `NarrativeDirector3D` | 新增 `_rescue_cutscene()`（按组发现）与 `_advance_rescue_dialogue()`；Space 的 `_input` 与鼠标 `can/advance` 都接上 | 输入的唯一入口本来就在导演；按组而不是节点路径，塔楼层级变了也不用改 |

语义与其它三处逐字一致：

- 打字中 → 立刻全显，句子身份不变；
- 已全显 → 只压缩这一句的停留，`_wait_until_line_done()` 的 0.05 s 轮询发现气泡收起后接下一句；
- **不跳句、不跳过整段、不提前起身**；玩家全程趴地、`input_locked` 与 `aim_locked` 照旧；
- 同帧只认一次（复用 `_space_press_frame`），空格与左键同帧按下不会一次跨两句；
- 暂停期间不处理。

## 3. 验收

`verify_base99_rescue`（core，`BASE-RESCUE`）新增 **R17**，独立起一次真实归航，避免干扰
`_check_lines` 的原时序：

| 断言 | 内容 |
|---|---|
| 可推进 | 演出期间 `NarrativeDirector.can_advance_mouse_dialogue()` 必须为真（改前必红） |
| 左键全显 | 真实 `InputEventMouseButton` pressed+released；打字中必须立刻全显、可见字数=总字数、**句子文本不变**（不跳句） |
| 点击被认领 | 按下当帧读 `DialogueUI.is_dialogue_mouse_fire_blocked()`，必须为真 —— 证明底栏确实消费了这次点击，不会漏给开火 |
| 空格收句 | 真实 `InputEventKey`(KEY_SPACE) 按下；0.5 s 内必须换句或收尾，且新句在 `script_lines` 里的下标**只能是原下标 +1** |
| 不提前起身 | 推进后玩家叙事姿态相位仍 1.0、`input_locked` 仍为真 |
| 不卡死 | 演出必须在 30 s 内离开 `cutscene` 阶段 |
| 反向对照 | 演出结束后 `can_advance_mouse_dialogue()` 必须为假 —— 否则说明这个查询是恒真的，上面那条 true 就不值钱 |

### 实跑结果

| 轮次 | 结果 |
|---|---|
| 正向（最终代码） | `BASE99_RESCUE_OK`，exit 0，自然退出；引擎 ERROR / SCRIPT ERROR 计数 **0** |
| 反向对照（关掉导演的救援分支） | exit **1**，R17 精准红 4 条（见 §4） |

意图：这段台词以前对点击完全无感，属于「跨文件隐形契约」——注释写了没用，必须有一条会红的断言盯着。

### 回归（同一份最终代码）

| 专项 | 结果 |
|---|---|
| `verify_base99_rescue`（含 R17） | `BASE99_RESCUE_OK`，exit 0，ERROR/SCRIPT ERROR = 0 |
| `verify_narrative_timeline` | `checks=113`，exit 0 |
| `verify_dialogue_ui_flow` | `DIALOGUE_UI_OK`，exit 0 |
| `verify_speech_bubble_3d` | `SPEECH_BUBBLE_3D_OK`，exit 0 |
| `verify_main_story_performance` | `checks=52 failures=0`，exit 0（`deposit_save` 为既有刻意注入） |

改的是导演的输入分支，所以特意把 113 项旧时间轴与底栏／气泡两个专项都跑了一遍，确认没有把
「无空格路径」和既有鼠标生命周期弄坏。

## 4. 反向对照

临时给 `NarrativeDirector3D` 加了一个仅供对照的开关 `_reverse_control_probe`，打开后退回改前行为
（`can_advance_mouse_dialogue()` 不查救援演出），用**同一个 R17** 跑。实际红的是这四行：

```text
ERROR: R17 演出期间导演仍报「鼠标不可推进」，左键会被漏给开火
ERROR: R17 这次左键没有被底栏认领（没锁住开火），点一下会顺带打出一枪
ERROR: R17 打字中点了左键，还在逐字冒（应当立刻全显）
ERROR: R17 按空格没有推进到下一句（仍停在『啧啧，太危险了，看我把你捞回来了。』）
```

四行分别对应「查询恒假」「点击穿透给武器」「全显无效」「空格推进无效」——
说明 R17 不是靠共用的兜底路径过的，而是真的盯着这条新接缝。

对照跑完即删除该开关（`grep -c _reverse_control_probe` = 0），生产代码里不留任何调试分支；
删完再跑一次正向，结果见 §3。

## 5. 未闭环

- 只覆盖死亡归航的救援演出；3.3 交接、3.2 Boss 对白走时间轴，早已支持。
- 未做真实渲染截图：本轮改的是输入消费与文字节奏，画面表现不变（气泡、镜头、站位都没动）。
- 未在真机上用鼠标连点压力测试；DialogueUI 的按压生命周期规则沿用既有实现，本轮未改。
