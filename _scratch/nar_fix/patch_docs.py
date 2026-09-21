import os

DOC = r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\08_技术施工_剧情触发.md"
SKILL = r"C:\Users\zhuangmenghong\.workbuddy\skills\10-narrative-timeline-authoring\SKILL.md"


def patch(path, label, edits):
    raw = open(path, "rb").read().decode("utf-8")
    crlf = "\r\n" in raw
    text = raw.replace("\r\n", "\n")
    for name, old, new in edits:
        n = text.count(old)
        if n != 1:
            raise SystemExit("ANCHOR FAIL %s :: %s count=%d" % (label, name, n))
        text = text.replace(old, new, 1)
    out = (text.replace("\n", "\r\n") if crlf else text).encode("utf-8")
    open(path, "wb").write(out)
    print("patched %-22s CR=%d LF=%d" % (label, out.count(b"\r"), out.count(b"\n")))


# =====================================================================
# 08 文档
# =====================================================================
patch(DOC, "08_doc", [
    # --- 4.4 事件清单 ---
    ("add-event-row",
     """| `room_entered` | ✅ | `DungeonRoom3D.player_entered`（L6），过滤 `room_id` |
""",
     """| `room_entered` | ✅ | `DungeonRoom3D.player_entered`（L6），过滤 `room_id`。**开场演出不许用，见下 ⚠️** |
| `gameplay_started` | ✅ 本系统自建（2026-09-21） | `TowerDescent3D.gameplay_started(room_id)`：开场页动画播完（点了开始 / 跳过之后）；**没有开场页时 = 场景 `_ready` 的帧末**。开场类剧本**只能**挂这个 |
"""),

    ("opening-trigger-rule",
     "**结论（影响范围，请作者知悉）**：",     """<span style="color:#791F1F">**开场演出（冷启动第一章）必须挂 `gameplay_started`，不能挂 `room_entered`。**</span>

`room_entered` 是在场景 `_ready()` 里就发的 —— 那一刻 `MainEntryScreen3D` 还在接管相机与输入。
剧情挂上去会在**菜单背后空跑**，并与开场页互相顶。四个症状**一个都不报错**，只能靠真机验收抓：

| 症状 | 机理 |
|---|---|
| 一开场玩家就能操控 | 开场页 `present()` 比剧情首帧晚跑，剧情先锁输入 ⇒ 开场页 `_finish_transition()` 又写回 `_previous_input_locked=false` |
| 镜头不"从上往下压" | 剧情抢到的相机基准是**近景机位**（俯角 24.6°），不是玩法机位（69.4°），后续运镜全建在错的基准上 |
| 中间错乱 | 开场页与剧情逐帧互写同一台 `Camera3D`（开场页 `_process` 钉近景、剧情 `_apply_camera_pose` 写叙事位姿） |
| 收工后键盘与开枪全废、鼠标还能转 | 收口把"接管瞬间的快照"写回 —— 那个快照是开场页刚写进去的 `true`（见 §6.1） |

⇒ **真机验收在 `tests/verification/verify_opening_script_runtime.tscn`**（§13.5）。

**结论（影响范围，请作者知悉）**："""),

    # --- 5.2 camera 指令表 ---
    ("camera-table",
     """| `camera.focus` | `target` / `distance` / `duration` / `hold` | 无独立服务。**照抄 `MainEntryScreen3D` 的既有模式**：存 `_gameplay_camera_transform` / `_gameplay_fov`（L31-32）→ `interpolate_with(target, eased)`（L66）→ 结束还原 | 🔶 需提炼 |
| `camera.shake` | `strength` / `duration` | 无先例 | 🔶 |
| `camera.restore` | `duration` | 同 `focus` | 🔶 |
| `camera.side` | `mode` | 无 | 🔶 v0.2 不做 |
""",
     """| `camera.focus` | `distance` / **`elevation_deg`** / `duration` | 无独立服务。**接管瞬间抓一次真实位姿当基准**，之后做**绕玩家的刚体轨道**：先绕水平轴把「玩家→相机」那条轴压到目标俯角，再绕玩家竖轴转方位 —— 位置与朝向同步旋转，焦点恒在玩家身上 | ✅ |
| `camera.pan` | `yaw_deg` / **`elevation_deg`（可选）** / `duration` | 同上，只是不改距离。不给 `elevation_deg` 时纯绕竖轴甩（老行为一字不变） | ✅ |
| `camera.restore` | `duration` | 距离 + 方位 + **俯角**一起回，再放权给玩法镜头 | ✅ |
| `camera.shake` | `strength` / `duration` | 无先例 | 🔶 |
| `camera.side` | `mode` | 无 | 🔶 v0.2 不做 |

<span style="color:#791F1F">**要"镜头从上往下压"，必须给 `elevation_deg`；只改 `distance` 不叫俯冲。**</span>
相机只会沿同一条「玩家→相机」轴滑动，观感是**推近拉远**。实测老实现（只改距离）俯角全程 **69.4° 零变化**；
新实现 `elevation_deg: 34.0` 才真的 69.4° → 34.0°。
`elevation_deg` 是**世界仰角**（`atan2(相机高出玩家, 水平距离)`），**不是增量**；不给时沿用接管前玩法镜头那套俯角。
⚠️ 它的绝对数值**依赖房间几何与玩法镜头构图**，换房间要重测（见 §13.5 末）。
"""),

    # --- 6.1 输入锁归还语义 ---
    ("input-return",
     """| 玩家输入 | 原始锁状态 | 还原为原始值 |
""",
     """| 玩家输入 | **只登记「叙事持有输入」**，不记原始值 | 交回独占权后请地牢**重新裁决**一次（`Dungeon3D.refresh_player_input_lock()`）—— 不写回快照 |
"""),

    ("input-return-why",
     """**归还时机**（四个都要做，一个都不能漏）：
""",
     """<span style="color:#791F1F">**输入锁的归还绝不能"写回快照"。**</span>
`input_locked` 是**多方共用**的：模态 / 背包 / 开场页各自都会改它。把接管瞬间读到的值当"原值"存下来、
收口再写回去，等于**替别的系统做决定**。实测反例：冷启动时开场页先锁 ⇒ 剧情登记 `before=true` ⇒
收口写回 `true` ⇒ 玩家**永久锁死：键盘与开枪全废、鼠标仍能转向**，且运行时零报错。
正确做法是交回独占权后**重新裁决**一次（`_has_exclusive_modal() or inventory_open or _narrative_holds_player_input()`），
这也是 `refresh_player_input_lock()` 必须是**函数调用**而不是字段赋值的原因。

**归还时机**（四个都要做，一个都不能漏）：
"""),

    # --- 13.1 落地件 ---
    ("landed-table",
     """| 验收 | `tests/verification/verify_narrative_timeline.{gd,tscn}` | 三层 80 项检查 |
""",
     """| 验收（假世界 · 机制） | `tests/verification/verify_narrative_timeline.{gd,tscn}` | 三层 **85 项**检查。最小"假玩家 + 假相机"世界：能测裁决 / 降级 / 收口 / 运镜机制，**看不到开场页** |
| 验收（真机 · 开场） | `tests/verification/verify_opening_script_runtime.{gd,tscn}` | **25 项**检查。真 `TowerDescent3D` + 真 `MainEntryScreen3D`，盯四个真机缺陷（§13.5） |
"""),

    # --- 13.5 新增小节 ---
    ("sec-135",
     """⇒ 调运镜不要靠肉眼试；改 `yaw_deg` → 重跑验收 → 读 `C2 构图采样` 那一行。
""",
     """⇒ 调运镜不要靠肉眼试；改 `yaw_deg` → 重跑验收 → 读 `C2 构图采样` 那一行。

### 13.5 开场剧本的真机缺陷与修复（2026-09-21 晚）

<span style="color:#791F1F">**背景：`verify_narrative_timeline` 当时 80 项全绿，真机一跑开场却四个问题。**</span>
根因是**验收世界与真机世界的差**：`TowerDescent3D._install_main_entry_screen()` 在
`test_mode / headless` 下**直接 return**，所以假世界验收里**根本不存在开场页** ——
而四个缺陷全部出在「剧情 × 开场页 × 玩家」的三方争用上。

| # | 真机症状 | 根因 | 修复 |
|---|---|---|---|
| 1 | 一开场玩家就能操控，没被锁死 | 剧本 01 挂 `room_entered`，在场景 `_ready` 里就起跑；开场页 `present()` / `_finish_transition()` 随后把 `input_locked` 写回 `false` | 剧本 01 改挂 `gameplay_started`（`TowerDescent3D` 新增该信号，排到 `transition_finished` 之后；无开场页时 `call_deferred`）—— §4.4 |
| 2 | 镜头不"从上往下压" | `_apply_camera_pose()` 只沿「玩家→相机」轴缩放距离 = 纯 dolly；实测俯角全程 **69.4° 零变化** | 新增 `elevation_deg` 通道 + `_camera_elevation_pivot()`（绕水平轴转那条轴）；`camera.focus` / `camera.pan` 都支持 —— §5.2 |
| 3 | 中间"错乱"（左右张望只朝一边、鼠标一抖就顶掉） | ① `actor.face` 的 `relative` 按**当前值**累加，`+32/−32` 退化成单向漂移；② 开场页在剧情期间仍逐帧写近景机位；③ `_update_aim_from_mouse()` 不看 `input_locked`，鼠标能随时改写朝向 | ① face 序列改用**序列基准** `_facing_base_yaw` 锚定；② 开场页 `_process` / `_finish_transition` 让位 `_narrative_holds_presentation()`；③ `Player3D._update_aim_from_mouse()` 让位 `is_actor_facing_overridden()`；④ 姿态相位过渡走完必须 `clear_narrative_pose()`，否则角色僵在倒地剪辑第一帧、待机不播 |
| 4 | 第 4 步完成后没交回键盘，鼠标能转但不能开枪 | 收口把"接管前的快照"写回 —— 那个快照是**开场页刚写进去的 `true`** | 归还改为交回独占权 + `Dungeon3D.refresh_player_input_lock()` 重新裁决 —— §6.1 |

**为什么必须新增一个真机验收**：上面四条**没有一条会报错**，假世界也一条都测不到。
`verify_opening_script_runtime` 的做法是把开场页实例**提前塞进塔楼自己的 `_main_entry_screen`**，
于是塔楼走它自己的 `_defer_gameplay_started()` **真接线**，时序与冷启动逐帧一致：

```text
开场页 present()（锁输入、钉近景）→ 点开始 → 转场 1.15s → transition_finished
  → gameplay_started → 开场剧本起跑 → 收口归还
```

实测判据（`_scratch/nar_diag/probe2.log`，25 项全绿）：

```text
[A] 点开始之前 展开 剧情未起跑（挂 room_entered 会在这里就空跑）
[B] 874 帧逐帧 input_locked == true，违例 0
[B] 俯角 69.4° → 34.0°（降幅 35.4°，剧本写的就是 34.0°）
[C] 收口后 input_locked=false、相机 / 免疫 / 朝向全部归还、开枪四道闸门全通
[D] 剧情演到一半硬把开场页 present 起来 → 相机仍在叙事俯角 30.0°（近景机位是 24.6°）
```

**三项反向对照**（改坏 → 必须变红 → 还原后逐字节一致）：

| 改坏什么 | 变红的判据 |
|---|---|
| 剧本 01 改回挂 `room_entered` | `[A] 开场页还在时剧情未起跑` + `俯角到达 34.0°`（实测最低 24.8° = 近景机位赢了） |
| `_camera_elevation_pivot()` 退化成单位阵（= 老实现） | `镜头真的从上往下压：69.4° → 69.4°（降幅 0.0°）` 等 3 项 |
| 归还时改用"写回快照（锁定）" | `收口后玩家输入真的解锁（缺陷①④）` |

<span style="color:#1565C0">**遗留提醒**：`elevation_deg` 的绝对数值依赖房间几何与玩法镜头构图，本版 `34.0°` 是对着 `floor_01_exit`
实测调的。换房间 / 换镜头参数后应当重跑 §13.5 的探针读实测降幅，**不要照抄角度**。
镜头"从上往下压"的**观感**最终仍需在编辑器里亲眼确认一次 —— 本探针证明的是角度真的在变、且落到剧本值，不是"看着好看"。</span>
"""),
])


# =====================================================================
# Skill 10-narrative-timeline-authoring
# =====================================================================
patch(SKILL, "skill10", [
    ("03-acceptance",
     """`verify_narrative_timeline` 覆盖：目录登记 / JSON 校验 / radius 与 duration 的反向对照 /
同帧顺序 / 降级不停摆 / 暂停冻结 / 两条真实剧本的「触发 → 接管 → 收口归还」。
""",
     """`verify_narrative_timeline` 覆盖：目录登记 / JSON 校验 / radius 与 duration 的反向对照 /
同帧顺序 / 降级不停摆 / 暂停冻结 / 两条真实剧本的「触发 → 接管 → 收口归还」。

**开场类剧本（冷启动第一章）加跑一条真机验收** —— 它跑真塔楼 + 真开场页，普通 headless 验收看不到开场页：

```bash
/i/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe \\
  --headless --path . res://tests/verification/verify_opening_script_runtime.tscn > _scratch/narrative/opening.log 2>&1
grep -E "verify_opening_script_runtime_(OK|FAIL)" _scratch/narrative/opening.log
```

它盯四个**不报错**的缺陷：开场是否真的锁死操作 / 镜头是否真的俯冲 / 中间是否被鼠标顶掉 / 收工是否交回键盘与开枪。
"""),

    ("camera-table",
     """| `camera.focus` | `distance` / `duration` | 只改"离玩家多远"，俯角与焦点构图继承玩法镜头 |
| `camera.pan` | `yaw_deg` / `duration` | 绕玩家竖轴的方位平移。**正角 = 视线向左摆**（见 §7 坑 13） |
""",
     """| `camera.focus` | `distance` / `elevation_deg` / `duration` | `elevation_deg` **可选**；不给时俯角沿用玩法镜头 |
| `camera.pan` | `yaw_deg` / `elevation_deg` / `duration` | 绕玩家竖轴甩（可选压俯角）。**正角 = 视线向左摆**（见 §7 坑 13） |
| `camera.restore` | `duration` | 距离 / 方位 / 俯角一起回，再放权给玩法镜头 |
"""),

    ("camera-elev-note",
     """**🔶 仍需新增，写了会降级跳过（会告警）：**

`player.heal` · `player.damage` · `player.move_dir`（仅调试）· `camera.shake` · `camera.restore` ·
""",
     """<span style="color:#791F1F">**要"镜头从上往下压"，必须给 `elevation_deg`；只改 `distance` 不叫俯冲。**</span>
只改距离时相机只会沿同一条「玩家→相机」轴滑动，观感是**推近拉远** —— 实测俯角全程 **69.4° 零变化**；
给 `elevation_deg: 34.0` 才真的 69.4° → 34.0°。`elevation_deg` 是相机相对玩家的**世界仰角**
（`atan2(相机高出玩家, 水平距离)`），**不是增量**；不给 = 沿用接管前玩法镜头那套俯角。
数值依赖房间几何，别照抄（见 §7 坑 17）。

**🔶 仍需新增，写了会降级跳过（会告警）：**

`player.heal` · `player.damage` · `player.move_dir`（仅调试）· `camera.shake` ·
"""),

    ("event-row",
     """| `room_entered` | ✅ | 过滤 `room_id` |
""",
     """| `room_entered` | ✅ | 过滤 `room_id`。**开场演出不要用**，见下 ⚠️ |
| `gameplay_started` | ✅ | 开场页动画播完 / 没有开场页时的帧末。**开场类剧本只能挂这个** |
"""),

    ("opening-rule",
     """**用户如果要求"击败某个 Boss 后演一段"**：
""",
     """<span style="color:#791F1F">**⚠️ 开场演出（冷启动第一章）必须挂 `gameplay_started`，不能挂 `room_entered`。**</span>

`room_entered` 在场景 `_ready()` 里就发，那一刻开场页还在接管相机与输入。挂上去会出现四个**全都不报错**的症状：
① 一开场玩家能操控（开场页随后把输入锁写回"可操作"）；
② 镜头不俯冲（抢到的基准是**近景机位**俯角 24.6°，不是玩法机位 69.4°）；
③ 中间错乱（开场页与剧情逐帧互写同一台相机、鼠标还能改写剧情摆好的朝向）；
④ 收工后键盘与开枪全废、鼠标还能转（收口把开场页写进去的 `true` 当"原值"写回）。

⇒ **`room_entered` 只用于"进到某个房间演一段"（玩法已经在跑的时候）。开场一律 `gameplay_started`。**

**用户如果要求"击败某个 Boss 后演一段"**：
"""),

    ("pit-16",
     """15. **两处"断了也不报错"的接线，改代码时别踩：**
    · `Dungeon3D._sync_player_input_lock()` **每帧重算** `input_locked`，必须让它认演出的输入独占
      （`is_player_input_locked()`），否则剧本写"停住"而玩家照常能动，日志干净得像没事发生；
    · `NarrativeDirector` 认领"带 `room_entered` 的节点"是靠 `_on_node_added` 自动绑定的 —— 它断了剧情永不触发，
      同样零报错。验收对这两条各有一道源码级 / 运行时守卫。
""",
     """15. **三处"断了也不报错"的接线，改代码时别踩：**
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
"""),

    ("selfcheck",
     """- [ ] 运镜类剧本看过验收打印的**构图偏角**，不是"我觉得应该对"
""",
     """- [ ] 运镜类剧本看过验收打印的**构图偏角**，不是"我觉得应该对"
- [ ] 要"从上往下压"的镜头写了 `elevation_deg`（只给 `distance` 不叫俯冲）
- [ ] **开场演出挂的是 `gameplay_started`**，不是 `room_entered`
"""),

    ("selfcheck-2",
     """- [ ] 真实剧本已跑 `verify_narrative_timeline`，且**红项 ⊆ 已知基线**（跑前先列基线，别把别处的红当自己的）
""",
     """- [ ] 真实剧本已跑 `verify_narrative_timeline`，且**红项 ⊆ 已知基线**（跑前先列基线，别把别处的红当自己的）
- [ ] 开场类剧本**加跑** `verify_opening_script_runtime`（真塔楼 + 真开场页；headless 验收看不到开场页）
"""),
])

print("DOC+S CHEDULED PATCHED")
