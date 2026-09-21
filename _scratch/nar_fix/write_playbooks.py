# -*- coding: utf-8 -*-
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory"
PB = os.path.join(MEM, "MEMORY-playbooks.md")
M = os.path.join(MEM, "MEMORY.md")

PB_BLOCK = """

## 剧情系统 · 开场演出与镜头（2026-09-21 真机缺陷修复）

> 事务档案：`2026-09-21/1539_剧情本体落地与两条开场剧本.md`（本体落地）· `2026-09-21/1641_开场剧本真机缺陷修复与真机验收探针.md`（本轮修复）。设计真源：`docs/v0.1/08_技术施工_剧情触发.md` §4.4/§5.2/§6.1/§13.5；作者手册：skill `10-narrative-timeline-authoring`。

### 剧情 · 开场演出必须挂 `gameplay_started`，不能挂 `room_entered`
`room_entered` 在场景 `_ready()` 里就发，那一刻 `MainEntryScreen3D` 还在接管相机与输入。开场剧本挂上去会在菜单背后空跑，并被开场页 `_finish_transition()` 把 `input_locked` 写回 `false`。四个症状（开场没锁操作 / 镜头不俯冲 / 中间错乱 / 收工键盘与开枪全废）**一个都不报错**。
正解：`TowerDescent3D.gameplay_started(room_id)` —— 有开场页时排到转场 `transition_finished` 之后，没有开场页时 `call_deferred` 到帧末。**`room_entered` 只用于「玩法已在跑时进房演一段」。**

### 剧情 · 「镜头从上往下压」必须给 `elevation_deg`；只改 `distance` 是纯 dolly
`_apply_camera_pose()` 是**绕玩家的刚体轨道**：先把「玩家→相机」那条轴压到目标俯角（`_camera_elevation_pivot()`），再绕竖轴转方位。不给 `elevation_deg` 就只缩放距离 ⇒ 观感是「推近拉远」，**俯角全程 69.4° 零变化**。
- 塔楼玩法镜头是固定装置：`TowerDescent3D.CAMERA_HEIGHT_M=10.719009` + 后移 `4.037671`，`atan2` ≈ **69.4°**（**全塔同值**，与房间无关）。
- `elevation_deg` 是**世界仰角**（`atan2(相机高出玩家, 水平距离)`），**不是增量**；`camera.focus` / `camera.pan` 都吃它，`camera.restore` 连俯角一起回。
- ⚠️ 绝对值依赖房间几何与镜头构图 ⇒ **别照抄角度**（换房间重跑探针读实测降幅）。
- ⚠️ 若给某段加了俯角，**收口前必须补 `camera.restore`**，否则 `flow.end` 瞬间相机从叙事俯角猛跳回 69.4°（探针不测观感、抓不到）。剧本 02 是 pan-only 且 `yaw` 回 0 ⇒ 释放天然无缝，**不需要**。

### 剧情 · 输入独占的归还必须「重新裁决」，绝不写回接管瞬间的快照
`input_locked` 是**多系统共用**的（模态 / 背包 / 开场页都改它）。把接管瞬间读到的值当「原值」存下、收口写回 = 替别的系统做决定。冷启动实测反例：开场页先锁 ⇒ 剧情登记 `before=true` ⇒ 收口写回 `true` ⇒ **玩家永久锁死：键盘与开枪全废、鼠标仍能转向**，运行时零报错。
正解：交回独占权后调 `Dungeon3D.refresh_player_input_lock()` **重算**（`_has_exclusive_modal() or inventory_open or _narrative_holds_player_input()`）。鼠标瞄准**不受** `input_locked` 约束 —— 所以「能转向不能开枪」是这条缺陷的唯一线索。

### 剧情 · 验开场必须真机世界；真机探针的关键手法
`TowerDescent3D._install_main_entry_screen()` 在 `test_mode / headless` 下**直接 return** ⇒ 假世界与普通 headless **根本没有开场页**，而开场类缺陷全出在「剧情 × 开场页 × 玩家」三方争用上。
手法（`tests/verification/verify_opening_script_runtime.gd`）：起真 `TowerDescent3D`，在 `add_child` **之前**手工 `_tower.set("_main_entry_screen", _entry)` ⇒ 塔楼走它自己的 `_defer_gameplay_started()` 真接线，时序与冷启动逐帧一致。三项反向对照（改回 `room_entered` / 仰角轴退化单位阵 / 归还写回快照）全部变红。

### 剧情 · 演员朝向 / 姿态的两条行为契约
- `actor.face` 的 `relative: true` 是「相对**本条 face 序列的基准**」（`_facing_base_yaw`，序列起点捕获），**不是相对上一帧**；写 `+32`→`-32`→`+32` 才是左右张望，不会被累加。剧情接管朝向期间**鼠标瞄准会被有意让位**（`Player3D._update_aim_from_mouse` 让 `is_actor_facing_overridden()`）—— 别把「剧情里鼠标转不动」当 bug。
- 姿态锁（`actor.pose`）在相位过渡走完时由系统**自动交还**（`clear_narrative_pose()`）；不交还角色会永久僵在倒地剪辑第一帧、待机不播。`to_phase` 之后**不用也不该**再写还原。
"""

M_BLOCK = """

## 剧情系统（Narrative，2026-09-21 落地）
- 本体 `src/narrative/`（`NarrativeScript3D` 解析 / `NarrativeCatalog` 目录 / `NarrativeDirector3D` autoload 导演 / `NarrativeAdapter3D` **唯一耦合点**）；内容 `data/narrative/*.json`；作者手册 skill `10-narrative-timeline-authoring`；设计真源 `docs/v0.1/08_技术施工_剧情触发.md`（§13.5 = 真机缺陷与修复）。
- 硬规则：**开场演出挂 `gameplay_started`**（不是 `room_entered`）；**「从上往下压」必须给 `elevation_deg`**（只改 distance = 纯 dolly，塔楼俯角恒 69.4°）；**输入独占归还必须 `refresh_player_input_lock()` 重算、绝不写回快照**；`NarrativeDirector` 是**不可摘**的 autoload（摘掉 `Dungeon3D`/`TowerDescent3D` 编译失败）。
- 验收两条：机制 `verify_narrative_timeline`（85 项）+ **真机** `verify_opening_script_runtime`（25 项；`_install_main_entry_screen` 在 test_mode 直接 return ⇒ headless 无开场页，必须真机）。细则见 playbooks「剧情系统 · 开场演出与镜头」节。
"""

for path, block in ((PB, PB_BLOCK), (M, M_BLOCK)):
    raw = open(path, "rb").read()
    had_crlf = b"\r\n" in raw
    tail = raw[-2:] if len(raw) >= 2 else raw
    sep = b"" if tail == b"\r\n" else b"\r\n"
    # normalize block to CRLF (or file's ending)
    txt = block.replace("\r\n", "\n")
    enc = (txt.replace("\n", "\r\n") if had_crlf else txt).encode("utf-8")
    with open(path, "ab") as fh:
        fh.write(sep + enc)
    b = open(path, "rb").read()
    print("%-22s appended; CR=%d LF=%d dbl=%d" % (os.path.basename(path), b.count(b"\r"), b.count(b"\n"), b.count(b"\r\r\n")))
