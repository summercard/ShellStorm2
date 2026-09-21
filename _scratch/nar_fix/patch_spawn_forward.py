# -*- coding: utf-8 -*-
"""给 scene.spawn 加 forward_m（沿视线额外前推），并把第 02 段队列推离西门。"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
ADAPTER = os.path.join(ROOT, "src", "narrative", "NarrativeAdapter3D.gd")
JSON02 = os.path.join(ROOT, "data", "narrative", "nar_tower_opening_02_zombies.json")
DOC = os.path.join(ROOT, "docs", "v0.1", "08_技术施工_剧情触发.md")
SKILL = r"C:\Users\zhuangmenghong\.workbuddy\skills\10-narrative-timeline-authoring\SKILL.md"


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


def patch(path, pairs):
    t = load(path)
    for label, a, b in pairs:
        n = t.count(a)
        assert n == 1, "锚点『%s』命中 %d 次：%s" % (label, n, os.path.basename(path))
        t = t.replace(a, b)
    save(path, t)


T = "\t"

# ---------------- 1) 适配器 ----------------
A1_OLD = (
    T + "var side := str(params.get(\"side\", \"right\"))\n"
    + T + "var layout := _spawn_layout(side, float(params.get(\"distance\", 3.6)))\n"
)
A1_NEW = (
    T + "var side := str(params.get(\"side\", \"right\"))\n"
    + T + "# `forward_m` = 沿视线方向的**额外前推**（米）。不写则沿用旧的 distance*0.5。\n"
    + T + "var layout := _spawn_layout(\n"
    + T + T + "side, float(params.get(\"distance\", 3.6)), params.get(\"forward_m\", null)\n"
    + T + ")\n"
)

A2_OLD = (
    "## 玩家左右侧站位。返回 {\"origin\": 队列中心, \"axis\": 展开轴}。\n"
    "## 用玩家朝向而不是房间朝向 —— 「画面的右边」在俯视角下就等于角色的右手边，\n"
    "## 这样不需要为每个房间预写方位，房间换了构图也不会错。\n"
    "func _spawn_layout(side: String, distance: float) -> Dictionary:\n"
)
A2_NEW = (
    "## 玩家左右侧站位。返回 {\"origin\": 队列中心, \"axis\": 展开轴}。\n"
    "## 用玩家朝向而不是房间朝向 —— 「画面的右边」在俯视角下就等于角色的右手边，\n"
    "## 这样不需要为每个房间预写方位，房间换了构图也不会错。\n"
    "## `forward_override`（= cue 的 `forward_m`）：沿视线额外前推的米数；" + "null" + " = 用旧的 distance*0.5。\n"
    "func _spawn_layout(side: String, distance: float, forward_override: Variant = null) -> Dictionary:\n"
)

A3_OLD = (
    T + "# 队列沿**视线方向**展开：镜头转向侧面看过去时，这条队形在画面里是横排。\n"
    + T + "return {\n"
    + T + T + "\"origin\": player.global_position + lateral * distance + forward * maxf(0.0, distance * 0.5),\n"
    + T + T + "\"axis\": forward,\n"
    + T + "}\n"
)
A3_NEW = (
    T + "# 前向分量：默认 distance*0.5（原行为）。触发通常发生在玩家**刚跨进门**那一刻，\n"
    + T + "# 那时玩家还站在门口 ⇒ 默认值会把整条队列留在门口（实测最后一只几乎踩在门线上）。\n"
    + T + "# 房间进深大、或想让怪「在房间里侧」时，用 cue 的 `forward_m` 显式前推。\n"
    + T + "# ⚠️ 前推会同时拉大相机到队列的距离（运镜构图随之变化）——它是**作者的构图旋钮**。\n"
    + T + "var forward_m := maxf(0.0, distance * 0.5)\n"
    + T + "if forward_override != null:\n"
    + T + T + "forward_m = maxf(0.0, float(forward_override))\n"
    + T + "# 队列沿**视线方向**展开：镜头转向侧面看过去时，这条队形在画面里是横排。\n"
    + T + "return {\n"
    + T + T + "\"origin\": player.global_position + lateral * distance + forward * forward_m,\n"
    + T + T + "\"axis\": forward,\n"
    + T + "}\n"
)

patch(ADAPTER, [
    ("scene_spawn-call", A1_OLD, A1_NEW),
    ("spawn_layout-sig", A2_OLD, A2_NEW),
    ("spawn_layout-body", A3_OLD, A3_NEW),
])

# ---------------- 2) 剧本 02：把队列推出西门 ----------------
J_OLD = "      \"distance\": 4.6,\n"
J_NEW = "      \"distance\": 4.6,\n      \"forward_m\": 8.0,\n"
patch(JSON02, [("json-forward-m", J_OLD, J_NEW)])

# ---------------- 3) 文档 / skill 参数表 ----------------
D_OLD = "| `scene.spawn` | `room_id` / `kind` / `count` / `side` / `distance` / `spread` |"
D_NEW = "| `scene.spawn` | `room_id` / `kind` / `count` / `side` / `distance` / `forward_m` / `spread` |"
patch(DOC, [("doc-param", D_OLD, D_NEW)])

S_OLD = "| `scene.spawn` | `room_id` / `kind` / `count` / `side` / `distance` / `spread` |"
S_NEW = "| `scene.spawn` | `room_id` / `kind` / `count` / `side` / `distance` / `forward_m` / `spread` |"
patch(SKILL, [("skill-param", S_OLD, S_NEW)])

print("PATCH_DONE")
