# -*- coding: utf-8 -*-
"""1946 事务：剧情运镜枢轴（相机可脱开主角平移过去）。"""
import os

MEM = r"I:\工作项目\shellstrom2\.workbuddy\memory"
DAY = os.path.join(MEM, "2026-09-21")
TX = os.path.join(DAY, "1946_剧情相机枢轴_可脱开主角平移.md")
IDX = os.path.join(DAY, "_INDEX.md")
PB = os.path.join(MEM, "MEMORY-playbooks.md")


def load(p):
    raw = open(p, "rb").read()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    assert crlf and crlf == lf, "行尾不纯 %s" % p
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(p, t):
    data = t.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(p, "wb").write(data)
    print("  wrote %s CR=%d LF=%d" % (os.path.basename(p), data.count(b"\r"), data.count(b"\n")))


BODY = """# 剧情运镜枢轴 · 相机可脱开主角平移过去

> 类型：能力新增（适配器 + 验收 + 文档 + skill）
> 关联：**1641**（`elevation_deg` 通道）、**1911**（同一条 cue 的 `forward_m`）

## 需求（主人）
「剧情的移动摄像机是不是还会锁在角色身上？有些地方可以不锁在主角身上，然后直接**整个平移过去**。」
主人确认：**加**这个能力，且 **`player`（默认）/ `last_spawn` / `room_center` / `pivot_m` 四种都支持**。

## 改动前的边界（回答主人）
`NarrativeAdapter3D._apply_camera_pose()` 把相机摆成
`player.global_position + 旋转后的(接管前「玩家→相机」轴) × distance` —— **绕主角的刚体轨道**，焦点恒在玩家。
只有 3 个自由度：`yaw_deg` / `elevation_deg` / `distance`；**没有平移自由度** ⇒ 做不到"脱开主角平移过去"。
（顺带发现：08 文档 §5.2 老示例里的 `"target": "player"` **实现根本不读**，是空参数。）

## 实现
- `_apply_camera_pose()` 的枢轴由 `player.global_position` 换成 `_current_camera_pivot(player)`，
  其余（接管前相对轴、俯角旋转、距离缩放）**一字不动** ⇒ 不写 pivot 时行为逐值不变。
- 新增**向量通道** `_camera_pivot_channel`：`_advance_channel` 只吃 float（`lerpf`），
  故另写 `_advance_vector_channel` ⇒ 枢轴按同一个 `duration` **平滑插值**，是「平移过去」不是瞬移。
- `camera.focus` / `camera.pan` 新增可选 `pivot` / `pivot_m` / `room_id`；
  `camera.restore` 把枢轴**一起带回玩家**（否则收镜会绕着一个远处的点走、最后再「跳」回玩家）。
- 枢轴四种取值：
  - `player`（默认）—— 焦点钉在主角身上，老行为；
  - `last_spawn` —— 最近一次 `scene.spawn` 的**队列中心**（`_scene_spawn` 成功后缓存），作者**零坐标**；
  - `room_center` + `room_id` —— 房间中心，**复用已有的 `room_node(room_id)`**（`DungeonRoom3D` 节点原点即房间中心）；
  - `pivot_m: [x,y,z]` —— 显式世界坐标（最优先，压过 `pivot`）。
- 拿不到目标点（没刷过怪 / 找不到房间 / `pivot` 写错）→ **告警并退回玩家**，不静默。
- ⚠️ 机位脱开后**不做遮挡处理**：枢轴太远时相机可能穿墙，取景处要作者自己留空（已写进文档）。

## 两个自伤点（已修，值得记）
1. **适配器原本没有 `_warn`**（只有 `_ok/_degraded/_failed/_done`）：新代码调 `_warn(...)` 直接
   `Parse Error: Function "_warn()" not found` ⇒ 适配器编译失败 ⇒ autoload 全 Nil、验收挂死被 timeout 杀。
   已补一个 `push_warning` 版 `_warn`（只用于错用/接线缺口，正常路径一声不响）。
2. `Dictionary.get()` 返回 Variant，**直接 `return` 会撞「警告即错误」** ⇒ 显式 `var value: Vector3 = ...`。
（另：`--check-only` 对 autoload 报 `Identifier not found: VfxPool` 是**已知假阳性**，别当真错。）

## 验收
- `verify_narrative_timeline` 新增 **C6**（4 例）：
  - (a) **不给 pivot** → 机位仍绕玩家 + 没跑到别处（**这就是反向对照**）；
  - (b) `pivot_m` / (c) `last_spawn` / (d) `room_center` → 每例断言 ①机位到**目标点**距离 == 接管前的相机距离
    ②机位到**玩家**距离 > 3m（真脱开）。
- 项数 92 → **101** 全绿；`verify_opening_script_runtime` 25 项仍绿。
- **不写 pivot 时行为与改动前逐值一致**（C1/C2 构图仍是 偏角 12.5° / 深度 13.18m）。
- **反向对照**：把 `_apply_camera_pose` 的枢轴写死回玩家 ⇒ **恰好 3 条红**（三个"绕该点"断言）。
- 文档 08 §5.2 三行参数 + 枢轴说明段 + 验收项数；skill 10 §3.2 三行 + 枢轴说明段；四副本已同步
  （`SKILL_MIRROR_CHECK_OK skills=29 files=83 copies=3`）。

## 观察（非本批）
本轮 `skill-mirror-sync --check` 一度报 `B_drafts missing skills: ['game-character-model-pipeline']` ——
A 侧数量从 28 变 29，是**另一个并发会话**期间新增了该 skill；重跑 `--sync` 后一致。
即：**并发会话在动 skill 正本时，check 可能瞬间报副本落后，属正常补齐，不是误改。**

## 一句话
相机枢轴原本硬编码=玩家；现在 `camera.focus/pan` 可声明 `pivot`（`last_spawn` / `room_center` / `pivot_m`），
枢轴**平滑插值** ⇒ 整台机位能脱开主角平移过去拍别处，`restore` 再把它带回玩家，**默认行为一字不变**。
"""

save(TX, BODY)

# ---- 索引 ----
ROW = (
    "| 19:46 | [剧情运镜枢轴 · 相机可脱开主角平移过去](1946_剧情相机枢轴_可脱开主角平移.md) "
    "| **能力新增（适配器 + 验收 + 文档 + skill）** "
    "| 主人问「运镜是不是还锁在角色身上？能不能不锁主角、整个平移过去拍别处」——答：**是锁着的**，"
    "`_apply_camera_pose` 只绕玩家做刚体轨道（仅 yaw/elevation/distance 三个自由度），无平移自由度。按主人决定**加**："
    "`camera.focus/pan` 新增可选 `pivot`/`pivot_m`/`room_id`，四种取值 `player`（默认）/ `last_spawn`（绕刚刷的怪，零坐标）/ "
    "`room_center`（复用已有 `room_node()`）/ `pivot_m`（显式坐标）；新增**向量通道**做平滑插值（不是瞬移）；"
    "`restore` 把枢轴一起带回玩家。⚠️ 自伤两处已修：**适配器原本没有 `_warn`**（编译失败致 autoload 全 Nil、验收挂死）、"
    "`Dictionary.get()` 直接 return 撞「警告即错误」。验收 92→**101 项**；**反向对照**（枢轴写死回玩家）恰好 3 红；"
    "不写 pivot 时行为逐值不变（12.5°/13.18m）；开场真机验收 25 项仍绿 |"
)
t = load(IDX)
assert sum(1 for l in t.split("\n") if l.startswith("| 19:46 |")) == 0
out, hit = [], 0
for l in t.split("\n"):
    out.append(l)
    if l.startswith("| 19:11 |"):
        out.append(ROW)
        hit += 1
assert hit == 1, "19:11 锚点 %d" % hit
save(IDX, "\n".join(out))

# ---- playbooks ----
NOTE = """### 剧情 · 运镜枢轴（焦点默认钉在主角，可脱开平移过去）
- 叙事相机 = **绕枢轴的刚体轨道**：`枢轴 + 旋转后的(接管前「枢轴→相机」轴) × distance`，位置与朝向同步旋转 ⇒ 焦点恒在枢轴。
  枢轴**默认 = 玩家**，只有 `yaw_deg` / `elevation_deg` / `distance` 三个自由度 —— 想「脱开主角平移过去拍别处」必须声明 `pivot`。
- `camera.focus` / `camera.pan` 可选：`pivot: "last_spawn"`（绕最近一次 `scene.spawn` 的队列中心，**零坐标**）/
  `pivot: "room_center"` + `room_id`（复用适配器已有的 `room_node()`；`DungeonRoom3D` 节点原点即房间中心）/
  `pivot_m: [x,y,z]`（显式坐标，最优先）。枢轴按同一个 `duration` **平滑插值** ⇒ 是平移不是瞬移。
- `camera.restore` 会把枢轴**一起带回玩家**；拿不到目标点一律**告警并退回玩家**；脱开后**不做遮挡处理**（取景处自己留空）。
- 实现坑：适配器的告警口是 `_warn`（`push_warning` 版）—— **原文件只有 `_ok/_degraded/_failed/_done`**，缺 `_warn` 会编译失败
  并拖垮整个 autoload 链（表现为验收挂死被 timeout）。`Dictionary.get()` 取值要**显式定型**（Variant + 「警告即错误」）。"""
t = load(PB)
save(PB, t.rstrip("\n") + "\n\n" + NOTE + "\n")

print("ALL_DONE")
