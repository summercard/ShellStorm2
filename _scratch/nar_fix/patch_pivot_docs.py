# -*- coding: utf-8 -*-
"""文档 08 + skill 10：补运镜枢轴 pivot/pivot_m/room_id。"""
import os

DOC = r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\08_技术施工_剧情触发.md"
SKILL = r"C:\Users\zhuangmenghong\.workbuddy\skills\10-narrative-timeline-authoring\SKILL.md"


def load(p):
    raw = open(p, "rb").read()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    assert crlf and crlf == lf, "行尾不纯 %s CRLF=%d LF=%d" % (p, crlf, lf)
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(p, t):
    data = t.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(p, "wb").write(data)
    print("  wrote %s CR=%d LF=%d" % (os.path.basename(p), data.count(b"\r"), data.count(b"\n")))


def patch(p, pairs):
    t = load(p)
    for label, a, b in pairs:
        n = t.count(a)
        assert n == 1, "锚点『%s』命中 %d 次：%s" % (label, n, os.path.basename(p))
        t = t.replace(a, b)
    save(p, t)


# ================= 文档 08 =================
DOC_FOCUS_OLD = (
    "| `camera.focus` | `distance` / **`elevation_deg`** / `duration` | 无独立服务。"
    "**接管瞬间抓一次真实位姿当基准**，之后做**绕玩家的刚体轨道**：先绕水平轴把「玩家→相机」那条轴压到目标俯角，"
    "再绕玩家竖轴转方位 —— 位置与朝向同步旋转，焦点恒在玩家身上 | ✅ |"
)
DOC_FOCUS_NEW = (
    "| `camera.focus` | `distance` / **`elevation_deg`** / **`pivot`** / `pivot_m` / `room_id` / `duration` "
    "| 无独立服务。**接管瞬间抓一次真实位姿当基准**，之后做**绕「枢轴」的刚体轨道**：先绕水平轴把「枢轴→相机」"
    "那条轴压到目标俯角，再绕枢轴竖轴转方位 —— 位置与朝向同步旋转，**焦点恒在枢轴上**。"
    "枢轴默认 = **玩家**；给了 `pivot` 就**整台机位平移过去**并对准新焦点（见下） | ✅ |"
)
DOC_PAN_OLD = (
    "| `camera.pan` | `yaw_deg` / **`elevation_deg`（可选）** / `duration` | 同上，只是不改距离。"
    "不给 `elevation_deg` 时纯绕竖轴甩（老行为一字不变） | ✅ |"
)
DOC_PAN_NEW = (
    "| `camera.pan` | `yaw_deg` / **`elevation_deg`（可选）** / **`pivot`** / `pivot_m` / `room_id` / `duration` "
    "| 同上，只是不改距离。不给 `elevation_deg` 时纯绕竖轴甩（老行为一字不变） | ✅ |"
)
DOC_RESTORE_OLD = "| `camera.restore` | `duration` | 距离 + 方位 + **俯角**一起回，再放权给玩法镜头 | ✅ |"
DOC_RESTORE_NEW = (
    "| `camera.restore` | `duration` | 距离 + 方位 + **俯角 + 枢轴**一起回（枢轴必须回玩家，"
    "否则收镜会绕着一个远处的点走、最后再「跳」回来），再放权给玩法镜头 | ✅ |"
)

DOC_NOTE_ANCHOR = (
    "⚠️ 它的绝对数值**依赖房间几何与玩法镜头构图**，换房间要重测（见 §13.5 末）。\n"
)
DOC_NOTE = (
    "\n"
    "**运镜枢轴 `pivot`（2026-09-21 新增）**：默认 `player` —— 焦点钉在主角身上。"
    "要**脱开主角、整台机位平移过去拍别处**：\n"
    "- `pivot: \"last_spawn\"` —— 绕**最近一次 `scene.spawn` 的队列中心**"
    "（作者不写坐标；同一段剧情里要先刷怪）。\n"
    "- `pivot: \"room_center\"` + `room_id` —— 绕**房间中心**"
    "（房间节点原点即中心，见 `DungeonRoom3D` 的 ±dimensions/2 约定）。\n"
    "- `pivot_m: [x, y, z]` —— 显式世界坐标（最优先，压过 `pivot`）。\n"
    "\n"
    "枢轴按同一个 `duration` **平滑插值** ⇒ 是「平移过去」，不是瞬移；`camera.restore` 会把枢轴一起带回玩家。\n"
    "拿不到目标点（没刷过怪 / 找不到房间 / `pivot` 写错）一律**告警并退回玩家**，不静默。\n"
    "⚠️ 机位脱开后**不做遮挡处理**：枢轴离得太远时相机可能穿墙 —— 取景处要自己留空。\n"
)

patch(DOC, [
    ("focus-row", DOC_FOCUS_OLD, DOC_FOCUS_NEW),
    ("pan-row", DOC_PAN_OLD, DOC_PAN_NEW),
    ("restore-row", DOC_RESTORE_OLD, DOC_RESTORE_NEW),
    ("pivot-note", DOC_NOTE_ANCHOR, DOC_NOTE_ANCHOR + DOC_NOTE),
    ("doc-count", "三层 **92 项**检查", "三层 **101 项**检查"),
])

# ================= skill 10 =================
SK_FOCUS_OLD = (
    "| `camera.focus` | `distance` / `elevation_deg` / `duration` | `elevation_deg` **可选**；不给时俯角沿用玩法镜头 |"
)
SK_FOCUS_NEW = (
    "| `camera.focus` | `distance` / `elevation_deg` / **`pivot`** / `pivot_m` / `room_id` / `duration` "
    "| `elevation_deg` **可选**；不给时俯角沿用玩法镜头。`pivot` 默认玩家 |"
)
SK_PAN_OLD = (
    "| `camera.pan` | `yaw_deg` / `elevation_deg` / `duration` | 绕玩家竖轴甩（可选压俯角）。"
    "**正角 = 视线向左摆**（见 §7 坑 13） |"
)
SK_PAN_NEW = (
    "| `camera.pan` | `yaw_deg` / `elevation_deg` / **`pivot`** / `pivot_m` / `room_id` / `duration` "
    "| 绕**枢轴**竖轴甩（可选压俯角）。**正角 = 视线向左摆**（见 §7 坑 13） |"
)
SK_RESTORE_OLD = "| `camera.restore` | `duration` | 距离 / 方位 / 俯角一起回，再放权给玩法镜头 |"
SK_RESTORE_NEW = "| `camera.restore` | `duration` | 距离 / 方位 / 俯角 / **枢轴**一起回，再放权给玩法镜头 |"

SK_NOTE_ANCHOR = "数值依赖房间几何，别照抄（见 §7 坑 17）。\n"
SK_NOTE = (
    "\n"
    "**运镜枢轴 `pivot`（可选，默认 `player` = 焦点钉在主角身上）**：要「脱开主角、整台机位平移过去拍别处」就给 ——\n"
    "`pivot: \"last_spawn\"`（绕最近一次 `scene.spawn` 的队列中心，**零坐标**）、\n"
    "`pivot: \"room_center\"` + `room_id`（绕房间中心）、\n"
    "`pivot_m: [x, y, z]`（显式世界坐标，最优先）。\n"
    "枢轴按同一个 `duration` **平滑插值** ⇒ 是平移不是瞬移；`restore` 会把它带回玩家。\n"
    "拿不到目标点会**告警并退回玩家**；脱开后**不处理遮挡**，取景处自己留空。\n"
)

patch(SKILL, [
    ("sk-focus", SK_FOCUS_OLD, SK_FOCUS_NEW),
    ("sk-pan", SK_PAN_OLD, SK_PAN_NEW),
    ("sk-restore", SK_RESTORE_OLD, SK_RESTORE_NEW),
    ("sk-note", SK_NOTE_ANCHOR, SK_NOTE_ANCHOR + SK_NOTE),
])

print("DOCS_DONE")
