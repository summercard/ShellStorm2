import os

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
     """**用户如果要求"击败某个 Boss 后演一段"**：""",
     """<span style="color:#791F1F">**⚠️ 开场演出（冷启动第一章）必须挂 `gameplay_started`，不能挂 `room_entered`。**</span>

`room_entered` 在场景 `_ready()` 里就发，那一刻开场页还在接管相机与输入。挂上去会出现四个**全都不报错**的症状：
① 一开场玩家能操控（开场页随后把输入锁写回"可操作"）；
② 镜头不俯冲（抢到的基准是**近景机位**俯角 24.6°，不是玩法机位 69.4°）；
③ 中间错乱（开场页与剧情逐帧互写同一台相机、鼠标还能改写剧情摆好的朝向）；
④ 收工后键盘与开枪全废、鼠标还能转（收口把开场页写进去的 `true` 当"原值"写回）。

⇒ **`room_entered` 只用于"进到某个房间演一段"（玩法已经在跑的时候）。开场一律 `gameplay_started`。**

**用户如果要求"击败某个 Boss 后演一段"**："""),

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

print("SKILL10 PATCHED")
