# -*- coding: utf-8 -*-
"""文档 08 + skill 10：scene.spawn 房间相对锚点 / 排列轴 / 交错 + 项数。"""
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


DOC_ROW_OLD = (
    "| `scene.spawn` | `room_id` / `kind` / `count` / `side` / `distance` / `forward_m` / `spread` "
    "| `Dungeon3D.narrative_spawn_enemies()`（2026-09-21 为剧情开的**正门**） | ✅ |"
)
DOC_ROW_NEW = (
    "| `scene.spawn` | `room_id` / `kind` / `count` / `spread` / **`point_room` + `point_offset`**（房间相对锚点，"
    "与触发器同一套）/ **`axis`** / **`stagger_m`** / `side` / `distance` / `forward_m` "
    "| `Dungeon3D.narrative_spawn_enemies()`（2026-09-21 为剧情开的**正门**） | ✅ |"
)
DOC_NOTE_ANCHOR = "（`point_room` + 一个进深 offset）：玩家走进来、门自动关上，才起跑。\n"
DOC_NOTE = (
    "\n"
    "**刷怪站位也能房间相对（2026-09-22）**：`scene.spawn` 用与触发器同一套锚法 —— "
    "`point_room` + `point_offset` 把队列**钉在房间里的固定点**，不再是「玩家右前方 N 米」。\n"
    "为什么需要：触发器改成位置触发后，玩家落点在一个半径内浮动 ⇒ 玩家相对的站位会跟着抖。\n"
    "另两个排布参数：`axis`（`\"forward\"` 默认沿视线 / `\"x\"` 东西 / `\"z\"` 南北）决定队列**沿哪个方向排开**；"
    "`stagger_m` 让相邻两只沿排列轴的**垂直方向交替错开**，避免一条笔直的队（观感「太整齐」）。\n"
    "实测：会议室中心 `(−5, −24, 2.5)` + `[6, 0, 0]` ⇒ 刷怪点 `(1.0, −24, 2.5)`。\n"
)
DOC_C1_OLD = "三层 **103 项**检查"
DOC_C1_NEW = "三层 **105 项**检查"
DOC_C2_OLD = "**29 项**检查。真 `TowerDescent3D` + 真 `MainEntryScreen3D`，盯四个真机缺陷（§13.5）+ 第二段**房间相对位置触发器**的真机几何校验（E 段）"
DOC_C2_NEW = (
    "**52 项**检查。真 `TowerDescent3D` + 真 `MainEntryScreen3D`，盯四个真机缺陷（§13.5）"
    "+ 真机几何段：E（第二段房间相对位置触发器）/ F（98F 和平区门策略全放行 + 开门路径源码守卫）"
    "/ G（开局第一间房灯默认开 + 第二段刷怪点在房内）"
)
patch(DOC, [
    ("row", DOC_ROW_OLD, DOC_ROW_NEW),
    ("note", DOC_NOTE_ANCHOR, DOC_NOTE_ANCHOR + DOC_NOTE),
    ("count1", DOC_C1_OLD, DOC_C1_NEW),
    ("count2", DOC_C2_OLD, DOC_C2_NEW),
])

SK_ROW_OLD = (
    "| `scene.spawn` | `room_id` / `kind` / `count` / `side` / `distance` / `forward_m` / `spread` "
    "| 只有**和平区/空房**才是必要的；战斗房本来就会自己刷怪 |"
)
SK_ROW_NEW = (
    "| `scene.spawn` | `room_id` / `kind` / `count` / `spread` / **`point_room` + `point_offset`** / "
    "**`axis`** / **`stagger_m`** / `side` / `distance` / `forward_m` "
    "| 只有**和平区/空房**才是必要的；战斗房本来就会自己刷怪 |"
)
SK_NOTE_ANCHOR = "**什么时候该换位置触发**"
SK_NOTE = (
    "**刷怪站位**：`scene.spawn` 也支持房间相对锚点（`point_room` + `point_offset`）—— 位置触发之后玩家落点会浮动，\n"
    "玩家相对的站位跟着抖，要钉住就用房间相对。`axis` 选排列方向（`\"forward\"`/`\"x\"`/`\"z\"`），`stagger_m` 让相邻两只\n"
    "沿垂直方向交错错开，别站成一条笔直的队。\n"
    "\n"
)
patch(SKILL, [
    ("row", SK_ROW_OLD, SK_ROW_NEW),
    ("note", SK_NOTE_ANCHOR, SK_NOTE + SK_NOTE_ANCHOR),
])

print("DOCS_DONE")
