# -*- coding: utf-8 -*-
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-21"
TXN = os.path.join(MEM, "1641_开场剧本真机缺陷修复与真机验收探针.md")
INDEX = os.path.join(MEM, "_INDEX.md")

body = """# 开场剧本真机缺陷修复 + 真机验收探针（续 1539）

时间：2026-09-21 16:41
类型：**故障修复（代码 + 内容 + 文档 + skill + 验收）**
前置：[1539](1539_剧情本体落地与两条开场剧本.md)（两条剧本 + 本体落地，headless 80 项全绿）· [1432](1432_剧情时间轴v0.2与skill.md)

## 1. 主人本轮的指令（真机实测反馈）

> 「检查一下，开场的第一个就有问题，一开始要先锁死操作，玩家没有被锁死，可以操控。然后镜头没有按照从上往下移动。
> 中间也会错乱。第四步完成后没有交换键盘操作，鼠标可以转向，但是不能开枪。」

⚠️ **要点：1539 的验收 80 项全绿，真机却四个问题全中。** 根因是「验收世界 ≠ 真机世界」——
四个缺陷**没有一个会报错**，headless 一条都测不到。

## 2. 四个缺陷的根因与修复

| # | 真机症状 | 根因 | 修复 |
|---|---|---|---|
| ① | 一开场玩家就能操控，没被锁死 | 剧本 01 挂 `room_entered`，在场景 `_ready()` 里就起跑；`MainEntryScreen3D.present()` 随后才跑，`_finish_transition()` 把 `input_locked` 写回 `false` | 新增 `TowerDescent3D.gameplay_started(room_id)` 信号（排到转场 `transition_finished` 之后；无开场页时 `call_deferred` 到帧末）；剧本 01 重挂 `gameplay_started` |
| ② | 镜头不「从上往下压」 | `_apply_camera_pose()` 只沿「玩家→相机」轴缩放距离 = 纯 dolly；实测俯角全程 **69.4° 零变化** | 新增 `elevation_deg` 通道 + `_camera_elevation_pivot()`（绕水平轴把那条轴压到目标俯角）；`camera.focus` / `camera.pan` 都支持，`camera.restore` 连俯角一起回 |
| ③ | 中间「错乱」 | ① `actor.face` 的 `relative` 按**当前值**累加，`+32/−32` 退化成单向漂移；② 开场页在剧情期间仍逐帧写近景机位；③ `_update_aim_from_mouse()` 不看 `input_locked`，鼠标随时改写朝向 | ① face 序列改用**序列基准** `_facing_base_yaw` 锚定；② 开场页 `_process` / `_finish_transition` 让位 `_narrative_holds_presentation()`；③ `Player3D._update_aim_from_mouse()` 让位 `is_actor_facing_overridden()`；④ 姿态相位过渡走完必须 `clear_narrative_pose()`（否则角色僵在倒地剪辑第一帧） |
| ④ | 第 4 步后键盘与开枪全废、鼠标还能转 | 收口把「接管瞬间的快照」写回 —— 那个快照是**开场页刚写进去的 `true`** | 归还改为交回独占权 + `Dungeon3D.refresh_player_input_lock()` **重新裁决**（`_has_exclusive_modal() or inventory_open or _narrative_holds_player_input()`），**绝不写回快照** |

③ 的「只有能转向不能开枪」这一个线索，来自「鼠标瞄准不受 `input_locked` 约束」—— 这是 ④ 唯一的外显特征。

## 3. 为什么 headless 验收一条都测不到

`TowerDescent3D._install_main_entry_screen()` 在 `test_mode / DisplayServer=="headless"` 下**直接 return**
⇒ 假世界与普通 headless 里**根本没有开场页**；而四个缺陷全出在「剧情 × 开场页 × 玩家」三方争用上。
⇒ 验开场必须**真机世界 + 真开场页**。

## 4. 新增真机验收探针（关键手法）

`tests/verification/verify_opening_script_runtime.{gd,tscn}`（25 项检查）：

1. 起真 `TowerDescent3D.tscn`（`test_mode=true, run_seed_override=990098, force_new_game_opening_for_test=true`）；
2. **手工把 `MainEntryScreen3D` 实例提前塞进塔楼自己的 `_main_entry_screen`**（在 `add_child` 之前 `set`），
   绕过 `_install_main_entry_screen` 的 test_mode 早退 ⇒ 塔楼走它**自己的 `_defer_gameplay_started()` 真接线**，
   时序与冷启动逐帧一致：
   `开场页 present()（锁输入、钉近景）→ 点开始 → 转场 1.15s → transition_finished → gameplay_started → 剧本起跑 → 收口归还`；
3. 四段判据：[A] 点开始前剧情不许起跑 / [B] 全程逐帧 `input_locked==true` + 俯角真降 / [C] 收口后输入·相机·免疫·朝向全归还 + 开枪四道闸门全通 / [D] 剧情中强行 present 开场页 → 相机仍在叙事俯角。

**实测（`_scratch/nar_fix/probe3.log`，25/25 全绿）**

```text
[B] 875 帧逐帧 input_locked==true，违例 0
[B] 俯角 69.4° → 34.0°（降幅 35.4°，剧本写的就是 34.0°）
[B] dispatch_log: 0.00 lock_input / 0.00 actor.pose / 0.10 camera.focus / 7.00 actor.pose /
    9.00·9.60·10.30·11.00·11.70 actor.face / 12.00 actor.say / 13.80 camera.restore / 14.70 flow.end
[C] 收口后 input_locked=false；相机/免疫/朝向全归还；开枪四道闸门全通
[D] 让位前 30.0° → 让位后 30.0°（近景机位是 24.6°）
```

**三项反向对照**（`_scratch/nar_fix/reverse_control.py`，改坏 → 必须变红 → 还原逐字节一致）

| 改坏什么 | 变红的判据 |
|---|---|
| 剧本 01 改回挂 `room_entered` | `[A] 开场页还在时剧情未起跑` + `俯角到达 34.0°`（实测最低 24.8° = 近景机位赢了） |
| `_camera_elevation_pivot()` 退化成单位阵（= 老实现） | `镜头真的从上往下压` 等 3 项（降幅 0.0°） |
| 归还时改用「写回快照（锁定）」 | `收口后玩家输入真的解锁（缺陷①④）` |

机制验收同步更新（`verify_narrative_timeline`，85 项）：C1 改由 `gameplay_started` 触发、新增「剧本 01 必须挂 `gameplay_started`」「必须声明 `elevation_deg`」两道静态守卫、C1 增加俯角变化断言。

## 5. 剧本 02 的裁定：**不改**

剧本 02（五只小僵尸，`floor_01_main_02`）在四缺陷里**一条都没中**，逐条核过：

- 触发器 `room_entered` **是对的** —— 它发生在玩家走进下一间房、玩法已经在跑的时候，不涉及开场页（缺陷①只打冷启动）；
- 它是 **pan-only** 且 `yaw` 在 `flow.end` 前已回 0 ⇒ 租约释放时相机位姿 == 接管前位姿 ⇒ **天然无缝**，没有「跳镜」；
- 无 `actor.face` ⇒ 无相对量累加问题；输入归还走的是系统级修好的 `refresh_player_input_lock()`，自动受益。

**实验佐证**（`_scratch/nar_fix/exp_script02.py`）：给它第一段 pan 加 `elevation_deg: 34.0` 后机制验收仍 85/85、
C2 构图 16.5°/10.56m 仍在带内 —— **说明加也能加，但属非必要的观感增强**；若要加，**必须同时补一条 `camera.restore`**，
否则 `flow.end` 瞬间相机从 34° 猛跳回 69.4°（探针不测观感，抓不到）。**本轮决定保持原样**，理由：主人只报第一段；
不改未坏的东西。（已还原，逐字节一致。）

## 6. 文档 / skill 同步

- `docs/v0.1/08_技术施工_剧情触发.md`（590→**665** 行）：§4.4 加 `gameplay_started` 事件行 + ⚠️「开场演出必须挂 `gameplay_started`」症状/机理表；
  §5.2 camera 表改写真值（`focus`/`pan`/`restore` 都 ✅、都吃 `elevation_deg`）+ 「要俯冲必须给 `elevation_deg`」注；
  §6.1 输入归还行改「只登记叙事持有、请地牢重新裁决」+ 归还为何不能写回快照；§13.1 落地表列两条探针；
  新增 **§13.5**（四缺陷表 / 根因 / 探针设计 / 实测输出 / 三项反向对照 / `elevation_deg` 依赖房间几何的遗留提醒）。
- Skill `10-narrative-timeline-authoring`（379→**424** 行）：§0.3 加真机验收命令；§3.2 camera 表加 `elevation_deg`；
  §4.2 加 `gameplay_started` + ⚠️ 开场规则块；§7 坑 15 扩为三处接线（含「归还必须重新裁决」）、新增坑 16（开场触发源）/17（`elevation_deg` 依赖几何）/18（face relative 是序列基准）/19（姿态锁自动归还）；§8 自检加开场项。
  **四副本已全量同步**（`SKILL_MIRROR_CHECK_OK skills=28 files=82`，sha `9309e05b2e3b0b28…`）。

## 7. 未做 / 遗留

- `elevation_deg` 的**绝对角度**依赖房间几何与玩法镜头构图（本塔玩法镜头由 `TowerDescent3D.CAMERA_HEIGHT_M=10.719009` + 后移 `4.037671` 固定，
  `atan2` ≈ **69.4°，全塔同值**）；本版 `34.0°` 是对 `floor_01_exit` 调的，换房间/换镜头参数要重跑探针读实测降幅，**别照抄角度**。
- 镜头「从上往下压」的**观感**最终仍需在编辑器里**亲眼确认一次** —— 探针证明的是角度真在变且落到剧本值，不是「看着好看」。
- ⚠️ 验收日志含**并发会话**在改 VFX 造成的解析错误（`src/vfx/VfxImpact3D.gd` / `VfxMuzzleFlash3D.gd`，工作区 `M`、HEAD 干净、`v002` 升级中）：
  本批 **non-VFX ERROR=0**；这两条 ERROR 会把 `check_verification_log.py` 判成 rc=3，**属并发事务，非本轮引入**（1531 事务已同样备注）。
- 记忆目录曾出现**两份树**（1539 §6）：正本是 `shellstrom2/.workbuddy/memory/`。本轮写入前已确认落在正本。
"""

data = body.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")
open(TXN, "wb").write(data)
print("wrote TXN CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))

# ---- index rows ----
raw = open(INDEX, "rb").read().decode("utf-8")
had_crlf = "\r\n" in raw
lines = raw.replace("\r\n", "\n").split("\n")

row1539 = ("| 15:39 | [剧情系统本体落地 + 两条开场剧本（可验收）](1539_剧情本体落地与两条开场剧本.md) | "
           "**实际改动（代码+内容+文档+skill）** | 本体 `src/narrative/` 四件（解析/内容目录/autoload 导演/适配器）落地；"
           "两条开场剧本可跑（趴着起身张望「人呢」/ 五只小僵尸）；`verify_narrative_timeline` 三层 80 项全绿 + 反向对照。"
           "⛔ 三条零报错缺陷入账：演出输入锁被 `_sync_player_input_lock` 每帧顶掉、触发靠 `_on_node_added` 自动认领（断了永不触发）、"
           "`NarrativeDirector` 是不可摘 autoload。遗留：真机观感待目视确认 → 见 16:41（真机报四缺陷） |")

row1641 = ("| 16:41 | [开场剧本真机缺陷修复 + 真机验收探针](1641_开场剧本真机缺陷修复与真机验收探针.md) | "
           "**故障修复（代码+内容+文档+skill+验收）** | 主人真机跑 1539 的两条剧本报四缺陷（开场没锁操作 / 镜头不俯冲 / 中间错乱 / "
           "收工不交键盘、鼠标能转不能开枪）——headless 80 项全绿却全漏（`_install_main_entry_screen` 在 test_mode 直接 return ⇒ 无开场页）。"
           "四根因：①剧本 01 挂 `room_entered` 在 `_ready` 就起跑、被开场页 `_finish_transition()` 写回 `false`；"
           "②`_apply_camera_pose` 只缩放距离=纯 dolly、俯角恒 69.4°；③`actor.face` 相对量按当前值累加 + 开场页逐帧抢相机 + 鼠标瞄准不看 `input_locked`；"
           "④收口把「接管瞬间快照」写回（快照=开场页写的 `true`）。修法：新增 `gameplay_started` 事件（排到转场后）重挂剧本 01；"
           "新增 `elevation_deg` 通道 + `_camera_elevation_pivot()`（`focus`/`pan` 都支持）；face 锚序列基准 + 开场页/鼠标瞄准让位 + 姿态锁收口归还；"
           "归还改 `refresh_player_input_lock()` 重新裁决。**新增真机验收 `verify_opening_script_runtime`（25 项）**：把开场页实例提前塞进塔楼自己的 "
           "`_main_entry_screen` 走真接线；三项反向对照（改回 `room_entered` / 仰角轴退化单位阵 / 归还写回快照）全变红、还原逐字节一致。"
           "剧本 02 裁定 `room_entered` 正确 + pan-only 回零天然无缝 ⇒ **不改**（实验：加俯角仍 85/85，非必要）。"
           "⚠️ 日志含并发会话 VFX v002 解析错误（本批 non-VFX ERROR=0） |")

# insert 1539 before the 15:47 row
idx = next((i for i, ln in enumerate(lines) if ln.startswith("| 15:47 |")), None)
if idx is None:
    raise SystemExit("FAIL: 15:47 row not found")
lines.insert(idx, row1539)

# append 1641 after the last 16:31 row
last = max(i for i, ln in enumerate(lines) if ln.startswith("| 16:31 |"))
lines.insert(last + 1, row1641)

out = "\n".join(lines)
out = out.replace("\n", "\r\n") if had_crlf else out
b = out.encode("utf-8")
open(INDEX, "wb").write(b)
print("index rows added; CR=%d LF=%d" % (b.count(b"\r"), b.count(b"\n")))
