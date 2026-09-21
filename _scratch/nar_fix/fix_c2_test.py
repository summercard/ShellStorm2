# -*- coding: utf-8 -*-
"""修：阶段A 触发断言放宽；假相机跟随假玩家；C2 后把玩家放回原点。"""
import os

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_narrative_timeline.gd"
T = "\t"


def load():
    raw = open(P, "rb").read()
    assert raw.count(b"\r\n") == raw.count(b"\n"), "行尾不纯"
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(t):
    data = t.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(P, "wb").write(data)
    print("wrote CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))


t = load()
EDITS = []

# ① 阶段 A：触发形式放宽（event 或 point），但必须点名房间
EDITS.append((
    "phaseA-kind",
    T + T + "_check(\n"
    + T + T + T + "str(script.trigger.get(\"kind\", \"\")) == NarrativeScript3D.TRIGGER_KIND_EVENT,\n"
    + T + T + T + "\"%s 触发类型是 event\" % narrative_id,\n"
    + T + T + ")\n"
    + T + T + "var filter: Dictionary = script.trigger.get(\"filter\", {})\n"
    + T + T + "_check(str(filter.get(\"room_id\", \"\")) != \"\", \"%s 触发带 room_id 过滤\" % narrative_id)\n",
    T + T + "# 触发形式两种都合法：开头戏用**事件**（gameplay_started），第二段用**位置**\n"
    + T + T + "# （要玩家真的走进房间、门关上之后才起跑 —— room_entered 在刚跨进门那一刻就发，太早）。\n"
    + T + T + "# 两种都必须**点名房间**，且房间相对写法不许退化成写死世界坐标。\n"
    + T + T + "var kind := str(script.trigger.get(\"kind\", \"\"))\n"
    + T + T + "_check(\n"
    + T + T + T + "kind in [NarrativeScript3D.TRIGGER_KIND_EVENT, NarrativeScript3D.TRIGGER_KIND_POINT],\n"
    + T + T + T + "\"%s 触发类型是 event 或 point（实际 %s）\" % [narrative_id, kind],\n"
    + T + T + ")\n"
    + T + T + "var room_ref := str(script.trigger.get(\"point_room\", \"\"))\n"
    + T + T + "if kind == NarrativeScript3D.TRIGGER_KIND_EVENT:\n"
    + T + T + T + "room_ref = str((script.trigger.get(\"filter\", {}) as Dictionary).get(\"room_id\", \"\"))\n"
    + T + T + "_check(room_ref != \"\", \"%s 触发点名了房间（room_id / point_room）\" % narrative_id)\n",
))

# ② 假相机跟随假玩家的 helper
EDITS.append((
    "place-helper",
    "## 起一段只跑运镜的测试剧本并等它接管（C6 用）。\n",
    "## 假相机**不会**自己跟着假玩家走 —— 要挪玩家时必须一起挪相机，否则接管瞬间抓到的\n"
    "## 「玩家→相机」位移会变成几十米，运镜断言全线失真（漏掉这步实测得到 25m 的假距离）。\n"
    "func _place_player_and_camera(target: Vector3) -> void:\n"
    + T + "_player.global_position = target\n"
    + T + "_camera.global_position = target + _CAMERA_REST_OFFSET\n"
    + T + "_camera.look_at(target + Vector3(0.0, 1.2, 0.0), Vector3.UP)\n"
    "\n"
    "\n"
    "## 起一段只跑运镜的测试剧本并等它接管（C6 用）。\n",
))

# ③ C2 两处挪玩家改成连相机一起
EDITS.append((
    "c2-outside",
    T + "_player.global_position = TRIGGER_POINT + Vector3(12.0, 0.0, 0.0)\n",
    T + "_place_player_and_camera(TRIGGER_POINT + Vector3(12.0, 0.0, 0.0))\n",
))
EDITS.append((
    "c2-inside",
    T + "# 走进房间、踩到触发点 → 轮询命中\n" + T + "_player.global_position = TRIGGER_POINT\n",
    T + "# 走进房间、踩到触发点 → 轮询命中\n" + T + "_place_player_and_camera(TRIGGER_POINT)\n",
))
EDITS.append((
    "c3-point",
    T + "_player.global_position = TRIGGER_POINT\n" + T + "NarrativeDirector.evaluate_point_for_test()\n",
    T + "_place_player_and_camera(TRIGGER_POINT)\n" + T + "NarrativeDirector.evaluate_point_for_test()\n",
))

# ④ C2 之后把玩家/相机放回原点，避免站在触发点上干扰后续用例（尤其 C5 复位后的轮询）
EDITS.append((
    "c2-restore",
    T + "_note(\n"
    + T + T + "\"C2 构图采样：偏角=%.1f° 深度=%.2fm 峰值 t=%.2f\"\n"
    + T + T + "% [float(framing[\"angle_deg\"]), float(framing[\"depth\"]), float(framing[\"peak_t\"])]\n"
    + T + ")\n",
    T + "_note(\n"
    + T + T + "\"C2 构图采样：偏角=%.1f° 深度=%.2fm 峰值 t=%.2f\"\n"
    + T + T + "% [float(framing[\"angle_deg\"]), float(framing[\"depth\"]), float(framing[\"peak_t\"])]\n"
    + T + ")\n"
    + T + "# 把假玩家/相机放回原点：触发点就在房间中心附近，玩家一直站在上面会让后续用例\n"
    + T + "# （尤其 C5 复位存档后 `once` 归零的那一次轮询）被它误触发。\n"
    + T + "_place_player_and_camera(Vector3.ZERO)\n",
))

for label, a, b in EDITS:
    n = t.count(a)
    assert n == 1, "锚点『%s』命中 %d 次" % (label, n)
    t = t.replace(a, b)

save(t)
print("FIX_DONE edits=%d" % len(EDITS))
