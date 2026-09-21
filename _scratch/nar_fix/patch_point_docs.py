# -*- coding: utf-8 -*-
"""文档 08 + skill 10：房间相对位置触发 + 项数更新。"""
import os

DOC = r"I:\工作项目\shellstrom2\ShellStorm2\docs\v0.1\08_技术施工_剧情触发.md"
SKILL = r"C:\Users\zhuangmenghong\.workbuddy\skills\10-narrative-timeline-authoring\SKILL.md"


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


def patch(p, pairs):
    t = load(p)
    for label, a, b in pairs:
        n = t.count(a)
        assert n == 1, "锚点『%s』命中 %d 次：%s" % (label, n, os.path.basename(p))
        t = t.replace(a, b)
    save(p, t)


# ================= 文档 08 =================
D_ROW_OLD = "| **位置** | 剧本 `trigger.kind = \"point\"` | \"走到这块地方\" |"
D_ROW_NEW = (
    "| **位置** | 剧本 `trigger.kind = \"point\"`（+ `point` 世界坐标，或 `point_room` + `point_offset` 房间相对） "
    "| \"走到这块地方\" |"
)
D_NOTE_ANCHOR = (
    "`height_tolerance` 默认 `2.0`m —— 防止\"在楼上走过、脚下正下方就是触发点\"时误触发。"
    "判定用**水平距离 + 垂直带**两个条件，而不是纯球形距离。\n"
)
D_NOTE = (
    "\n"
    "**房间相对写法（2026-09-21 新增）**：`point` 要写世界坐标，而房间是**运行时生成**的 —— 把坐标写死，"
    "换布局 / 换楼层后会**静默失效**（症状是「剧情永不触发」）。所以位置触发也支持房间相对：\n"
    "\n"
    "```json\n"
    "\"trigger\": {\n"
    "  \"kind\": \"point\",\n"
    "  \"point_room\": \"floor_01_main_02\",\n"
    "  \"point_offset\": [-14.0, 0.0, 0.0],\n"
    "  \"radius\": 2.5,\n"
    "  \"once\": \"run\"\n"
    "}\n"
    "```\n"
    "\n"
    "`point_offset` 是**相对房间中心**的偏移，世界坐标 = `room_node(room_id).to_global(point_offset)`；"
    "由导演在运行期**惰性解析**（`arm()` 那一刻房间还不存在）并缓存。两种写法二选一，`point_room` 优先。\n"
    "\n"
    "**实测（真机几何，`verify_opening_script_runtime` E 段）**：`floor_01_main_02`（会议室 40×15，"
    "西门在房间最西端）房间中心 world = `(−5.0, −24.0, 2.5)`，`point_offset = [-14, 0, 0]` "
    "⇒ 触发点 `(−19.0, −24.0, 2.5)` = **进门 6m 处**。E 段断言「触发点在房间内部、且不在上一个房间里」。\n"
    "\n"
    "**用法建议**：`room_entered` 在玩家**刚跨进门**那一刻就发 —— 那时门还没关、人还站在门口，"
    "一切「基于玩家位置」的刷怪与运镜都会贴着门口。要让演出发生在**进门之后**，就换成位置触发"
    "（`point_room` + 一个进深 offset）：玩家走进来、门自动关上，才起跑。\n"
)
D_C1_OLD = "三层 **101 项**检查"
D_C1_NEW = "三层 **103 项**检查"
D_C2_OLD = "**25 项**检查。真 `TowerDescent3D` + 真 `MainEntryScreen3D`，盯四个真机缺陷（§13.5）"
D_C2_NEW = (
    "**29 项**检查。真 `TowerDescent3D` + 真 `MainEntryScreen3D`，盯四个真机缺陷（§13.5）"
    "+ 第二段**房间相对位置触发器**的真机几何校验（E 段）"
)
patch(DOC, [
    ("row", D_ROW_OLD, D_ROW_NEW),
    ("note", D_NOTE_ANCHOR, D_NOTE_ANCHOR + D_NOTE),
    ("count1", D_C1_OLD, D_C1_NEW),
    ("count2", D_C2_OLD, D_C2_NEW),
])

# ================= skill 10 =================
S_ROW_OLD = "| **位置** | 剧本 `trigger` 里写 `kind: \"point\"` + `point` + `radius` | \"走到这块地方\" |"
S_ROW_NEW = (
    "| **位置** | `kind: \"point\"` + `point_room` + `point_offset`（**首选**，房间相对）或 `point`（世界坐标）+ `radius` "
    "| \"走到这块地方\" |"
)
S_ANCHOR = (
    "**垂直带**：`point` 的 `y` 会与玩家高度比，默认容差 `2.0`m —— 防止楼上楼下误触发。"
    "写 `point` 时**要填真实世界坐标的 y**，不要一律写 `0`。\n"
)
S_NOTE = (
    "\n"
    "**位置触发优先用房间相对写法。** `point` 要写世界坐标，而房间是运行时生成的 —— 写死坐标在换布局后会\n"
    "**静默失效**（症状是「剧情永不触发」）。改用 `point_room: \"<房间id>\"` + `point_offset: [dx,dy,dz]`\n"
    "（相对**房间中心**），世界坐标由导演运行期用 `room.to_global(offset)` 解出。\n"
    "实测：会议室中心 `(−5, −24, 2.5)` + offset `[-14, 0, 0]` ⇒ 进门 6m 处的触发点。\n"
    "\n"
    "**什么时候该换位置触发**：`room_entered` 在玩家**刚跨进门**那一刻就发 —— 那时门还没关、人还站在门口，\n"
    "一切「基于玩家位置」的刷怪与运镜都会贴着门口（第二段「怪刷在门口」就是这么来的）。要演出发生在\n"
    "**进门之后**，就换成位置触发 + 一个进深 offset（玩家走进来、门自动关上，才起跑）。\n"
)
patch(SKILL, [("row", S_ROW_OLD, S_ROW_NEW), ("note", S_ANCHOR, S_ANCHOR + S_NOTE)])

print("DOCS_DONE")
