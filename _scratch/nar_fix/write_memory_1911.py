# -*- coding: utf-8 -*-
"""1911 事务：第二段刷怪队列推离门口（scene.spawn 新增 forward_m）。"""
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory"
DAY = os.path.join(MEM, "2026-09-21")
TX_PATH = os.path.join(DAY, "1911_刷怪队列推离门口_forward_m.md")
INDEX_PATH = os.path.join(DAY, "_INDEX.md")
PB_PATH = os.path.join(MEM, "MEMORY-playbooks.md")


def load(path):
    raw = open(path, "rb").read()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    assert crlf and crlf == lf, "行尾不纯 %s CRLF=%d LF=%d" % (path, crlf, lf)
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(path, text):
    data = text.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(path, "wb").write(data)
    print("  wrote %s CR=%d LF=%d" % (os.path.basename(path), data.count(b"\r"), data.count(b"\n")))


TX = """# 第二段刷怪队列推离门口 · `scene.spawn` 新增 `forward_m`

> 类型：体验修复（几何测算 + 新增参数 + 参数扫描 + 回归断言）
> 关联：**1539**（两条开场剧本）、**1641**（开场挂 `gameplay_started`）

## 现象（主人）
「剧情第二段刷怪的位置离门口太近了，往房间的右边靠一下…现在离左侧的门太近了」

## 几何测算（真源：`block_00_master_office_layout_v002.layout.json`）
- `meeting_room` = 运行时 `floor_01_main_02`（第 02 段的触发房）：`x∈[−25,15]`（**40m 长**）、
  `y∈[−5,10]`（15m 深，Blender Y=北）；门 **西 x=−25 / 东 x=15**，都在 `y=2.5`。
- 新游戏开场落 `floor_01_exit`（办公室 `x∈[−40,−25]`）⇒ 玩家**向东**走、从**西门**进会议室。
- `room_entered` 在玩家**刚跨进房间矩形**那一刻发（`TowerDescent3D._find_containing_room_on_floor`）
  ⇒ 触发时玩家还站在门口。刷怪站位是**相对这个"门口的玩家"**算的。
- `NarrativeAdapter3D._spawn_layout`：
  `origin = 玩家 + 右×distance + 前×(distance*0.5)`；队列沿**前向**展开（`axis=forward`，
  `spread=1.5`×5 只 ⇒ ±3.0m）。
- 旧值 `distance=4.6` ⇒ 队列中心在门口前 **2.3m**、右 4.6m ⇒ **最后一只在 −0.70m（玩家身后 = 门线上）**
  —— 正是主人看到的现象。

## 关键判断（为什么不能只改 distance）
- 横向（右）**平行于进门那面墙** ⇒ 加大 `distance` 对「离门」**毫无帮助**；只有**前向**分量能把队列推离门口。
- 但前推有代价：队列是沿视线前推的 ⇒ 在相机里**移向画面正中**（实测偏角 16.5°→2.3°），
  与「队列在画面右侧」（构图偏角带 12~24°）冲突；同时拉大相机到队列的距离（深度带 8~13.5m）。
  **深度上界才是真正的瓶颈**。

## 改法
1. `NarrativeAdapter3D._scene_spawn` / `_spawn_layout` 新增可选 **`forward_m`**（沿视线额外前推米数）。
   **不写 = 旧行为**（`distance*0.5`），向后兼容；cue 参数无白名单校验，加参数不需改 schema。
2. 剧本 02 定稿 `distance 4.6 → 5.6`、`forward_m: 4.8`（前推与横向同时加，才既离门又留在画面右侧）。

## 参数扫描（须同时满足：偏角 12~24°、深度 8~13.5m）
| forward_m / distance | 画面偏角 | 相机前深度 | 结果 |
|---|---|---|---|
| 2.3 / 4.6（旧） | 16.5° | 10.6m | 绿，但**最后一只在 −0.70m（门线上）** |
| **4.8 / 5.6（定稿）** | **12.5°** | **13.18m** | **绿，最后一只 +1.80m** |
| 5.5 / 6.2 | 12.7° | 14.01m | 深度超带 |
| 5.5 / 5.2 | 9.4° | 13.60m | 偏角+深度双超 |
| 8.0 / 4.6 | 2.3° | 15.45m | 跑到画面正中 |

⇒ **现有镜头的构图带宽把「离门」最多锁在约 2.5m**。要再往前推必须改相机
（减小 `camera.pan` 或换机位）——那是**重拍**，需主人拍板；本次不擅自改构图契约。

## 验收
- `verify_narrative_timeline` 新增 C2 断言：**队列最后一只也在玩家前方 >1.0m** ⇒ **91 → 92 项**，全绿。
- **反向对照**：参数退回旧值（2.3 / 4.6）⇒ 恰好 **1 条**红：
  `队列最后一只也在玩家前方 -0.70m（不贴门口，须 >1.0m）` —— **主人症状原样复现**；还原后逐字节干净。
- `verify_opening_script_runtime` 25 项仍绿。
- 文档 08 参数表加 `forward_m`、验收项数 91→92；skill 10 §3.2 加参数 + 新增**坑 21**（四副本已同步 `skills=28 files=82`）。

## 一句话
第二段队列贴门 = `scene.spawn` 触发在门口 + 前向分量被写死成 `distance*0.5`（=2.3m）。
新增 `forward_m` 后定稿 4.8 / 5.6：最后一只从**门线上**移到玩家前方 **1.80m**，
且仍在「队列在画面右侧」的构图带宽内取到最大值。
"""

save(TX_PATH, TX)

# ---------------- 索引行 ----------------
NEW_ROW = (
    "| 19:11 | [第二段刷怪队列推离门口 · `scene.spawn` 新增 `forward_m`](1911_刷怪队列推离门口_forward_m.md) "
    "| **体验修复（几何测算 + 新参数 + 扫描 + 断言）** "
    "| 主人报「第二段刷怪离门口太近，往房间右边靠」。根因：`room_entered` 在玩家**刚跨进门**时发，"
    "而 `_spawn_layout` 前向分量写死 `distance*0.5` ⇒ 旧值 4.6 时队列中心只在门口前 2.3m、"
    "**最后一只在 −0.70m（玩家身后=门线上）**。横向平行于西墙、改了也没用 ⇒ 新增可选 **`forward_m`**"
    "（不写=旧行为）。剧本 02 定稿 `distance 5.6 / forward_m 4.8` ⇒ 偏角 12.5°、深度 13.18m、最后一只 **+1.80m**。"
    "⚠️ 前推会移向画面正中：构图带宽 (12~24° / 8~13.5m) 把「离门」锁在 ~2.5m，再推需改相机（重拍，未擅自改）。"
    "验收 91→**92 项**；**反向对照**退回旧值 ⇒ 恰好 1 红（`-0.70m`）原样复现；开场真机验收 25 项仍绿 |"
)
t = load(INDEX_PATH)
assert sum(1 for l in t.split("\n") if l.startswith("| 19:11 |")) == 0, "19:11 行已存在"
out = []
hit = 0
for l in t.split("\n"):
    out.append(l)
    if l.startswith("| 18:48 |"):
        out.append(NEW_ROW)
        hit += 1
assert hit == 1, "18:48 锚点命中 %d" % hit
save(INDEX_PATH, "\n".join(out))

# ---------------- playbooks 追加小节 ----------------
PB = """### 剧情 · `scene.spawn` 站位（触发在门口 + 前向分量）
- `room_entered` 在玩家**刚跨进房间矩形**那一刻发 ⇒ 剧情刷怪的站位是相对「站在门口的玩家」算的。
- 站位 `origin = 玩家 + 右×distance + 前×(distance*0.5)`；队列沿**前向**展开（±(count−1)/2×spread）。
  ⇒ `distance` 只控**横向**，而横向**平行于进门那面墙**，**不能**把怪推离门口；要离门必须让 cue 写 **`forward_m`**。
- ⚠️ 前推 = 沿视线推 ⇒ 队列在相机里**移向画面正中**，并把相机距离拉大 ⇒ 会撞 `verify_narrative_timeline` 的
  构图带宽（偏角 **12~24°**、深度 **8~13.5m**）。**别硬放宽带宽迁就参数** —— 那是构图契约。
- 定稿值：`floor_01_main_02`（会议室 40×15，玩家自西门进）`distance 5.6 / forward_m 4.8`
  ⇒ 偏角 12.5°、深度 13.18m、最后一只在玩家前方 **1.80m**（旧值 −0.70m）。
- 回归断言：`verify_narrative_timeline` C2「队列最后一只也在玩家前方 >1.0m」（92 项）。"""
t = load(PB_PATH)
save(PB_PATH, t.rstrip("\n") + "\n\n" + PB + "\n")

print("ALL_DONE")
