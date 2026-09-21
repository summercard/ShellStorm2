# -*- coding: utf-8 -*-
"""C6 运镜枢轴验收：player 默认 / pivot_m / last_spawn / room_center。"""
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

# ---- ① 常量：房间探针中心 ----
A1 = "const FACING_BASELINE := 0.7\n"
B1 = (
    A1
    + "## room_center 枢轴用的假房间中心（世界坐标）。\n"
    + "const PROBE_ROOM_CENTER := Vector3(-11.0, 0.0, 7.0)\n"
)
assert t.count(A1) == 1, "FACING_BASELINE 锚点 %d" % t.count(A1)
t = t.replace(A1, B1)

# ---- ② FakeRoom 可被 room_node() 索引 ----
A2 = "class FakeRoom:\n\textends Node3D\n\tvar room_id := \"\"\n"
B2 = (
    "class FakeRoom:\n"
    "\textends Node3D\n"
    "\tvar room_id := \"\"\n"
    "\n"
    "\t# 适配器的 room_node() 只认「有 room_id 且带 contains_world_position」的节点。\n"
    "\tfunc contains_world_position(_world_position: Vector3) -> bool:\n"
    "\t\treturn true\n"
)
assert t.count(A2) == 1, "FakeRoom 锚点 %d" % t.count(A2)
t = t.replace(A2, B2)

# ---- ③ 成员 + 世界搭建 ----
A3 = "var _bark: FakeBark = null\n"
B3 = A3 + "var _probe_room: FakeRoom = null\n"
assert t.count(A3) == 1, "成员锚点 %d" % t.count(A3)
t = t.replace(A3, B3)

A4 = (
    T + "_bark = FakeBark.new()\n"
    + T + "_bark.name = \"FakeBark\"\n"
    + T + "add_child(_bark)\n"
)
B4 = (
    A4
    + "\n"
    + T + "# 房间探针：room_center 枢轴用它。\n"
    + T + "_probe_room = FakeRoom.new()\n"
    + T + "_probe_room.name = \"ProbeRoom\"\n"
    + T + "_probe_room.room_id = NEXT_ROOM_ID\n"
    + T + "add_child(_probe_room)\n"
    + T + "_probe_room.global_position = PROBE_ROOM_CENTER\n"
)
assert t.count(A4) == 1, "bark 锚点 %d" % t.count(A4)
t = t.replace(A4, B4)

# ---- ④ C6 用例（接在 C5 之后） ----
C5_END = T + "_check(not NarrativeDirector.is_playing(), \"反向对照：once 未复位时再发一次仍被挡住\")\n"
C6 = C5_END + (
    "\n"
    + T + "# ---- C6 运镜枢轴：默认钉在玩家；显式 pivot 后**整台机位平移过去**（2026-09-21）\n"
    + T + "NarrativeDirector.reset_for_test()\n"
    + T + "await _wait_frames(2)\n"
    + T + "var rest_len := _CAMERA_REST_OFFSET.length()\n"
    + "\n"
    + T + "# (a) 不给 pivot ⇒ 焦点仍在玩家（老行为，反向对照）\n"
    + T + "await _pivot_play([{\"at\": 0.0, \"do\": \"camera.pan\", \"yaw_deg\": 0.0, \"duration\": 0.0}])\n"
    + T + "_check(\n"
    + T + T + "absf(_camera.global_position.distance_to(_player.global_position) - rest_len) < 0.05,\n"
    + T + T + "\"不给 pivot 时机位仍绕玩家（距玩家 %.2fm，期望 %.2fm）\"\n"
    + T + T + "% [_camera.global_position.distance_to(_player.global_position), rest_len],\n"
    + T + ")\n"
    + T + "_check(\n"
    + T + T + "_camera.global_position.distance_to(PROBE_ROOM_CENTER) > 3.0,\n"
    + T + T + "\"不给 pivot 时机位没有跑到别处\",\n"
    + T + ")\n"
    + T + "NarrativeDirector.abort(\"c6a\")\n"
    + T + "await _wait_frames(2)\n"
    + "\n"
    + T + "# (b) pivot_m 显式坐标 ⇒ 脱开玩家、绕那个点\n"
    + T + "await _pivot_play([{\n"
    + T + T + "\"at\": 0.0, \"do\": \"camera.pan\", \"pivot_m\": [-11.0, 0.0, 7.0], \"duration\": 0.0,\n"
    + T + "}])\n"
    + T + "_check(\n"
    + T + T + "absf(_camera.global_position.distance_to(PROBE_ROOM_CENTER) - rest_len) < 0.05,\n"
    + T + T + "\"pivot_m 后机位绕该点（距 %.2fm，期望 %.2fm）\"\n"
    + T + T + "% [_camera.global_position.distance_to(PROBE_ROOM_CENTER), rest_len],\n"
    + T + ")\n"
    + T + "_check(\n"
    + T + T + "_camera.global_position.distance_to(_player.global_position) > 3.0,\n"
    + T + T + "\"pivot_m 后机位真**脱开**了玩家（距玩家 %.2fm）\"\n"
    + T + T + "% _camera.global_position.distance_to(_player.global_position),\n"
    + T + ")\n"
    + T + "NarrativeDirector.abort(\"c6b\")\n"
    + T + "await _wait_frames(2)\n"
    + "\n"
    + T + "# (c) last_spawn ⇒ 绕刚刷出来的那堆怪（作者不写坐标）\n"
    + T + "_spawn_calls.clear()\n"
    + T + "await _pivot_play([\n"
    + T + T + "{\n"
    + T + T + T + "\"at\": 0.0, \"do\": \"scene.spawn\", \"room_id\": NEXT_ROOM_ID,\n"
    + T + T + T + "\"kind\": \"melee_chaser\", \"count\": 5, \"side\": \"right\",\n"
    + T + T + T + "\"distance\": 5.6, \"forward_m\": 4.8,\n"
    + T + T + "},\n"
    + T + T + "{\"at\": 0.0, \"do\": \"camera.pan\", \"pivot\": \"last_spawn\", \"duration\": 0.0},\n"
    + T + "])\n"
    + T + "var spawn_origin: Vector3 = Vector3.ZERO\n"
    + T + "if not _spawn_calls.is_empty():\n"
    + T + T + "spawn_origin = _spawn_calls[0].get(\"origin\", Vector3.ZERO)\n"
    + T + "_check(_spawn_calls.size() == 1, \"last_spawn 用例先刷了一次怪（实际 %d）\" % _spawn_calls.size())\n"
    + T + "_check(\n"
    + T + T + "absf(_camera.global_position.distance_to(spawn_origin) - rest_len) < 0.05,\n"
    + T + T + "\"pivot=last_spawn 后机位绕刷怪点（距 %.2fm，期望 %.2fm）\"\n"
    + T + T + "% [_camera.global_position.distance_to(spawn_origin), rest_len],\n"
    + T + ")\n"
    + T + "_check(\n"
    + T + T + "spawn_origin.distance_to(_player.global_position) > 3.0,\n"
    + T + T + "\"（用例前提）刷怪点确实离玩家够远，脱开看得到\",\n"
    + T + ")\n"
    + T + "NarrativeDirector.abort(\"c6c\")\n"
    + T + "await _wait_frames(2)\n"
    + "\n"
    + T + "# (d) room_center ⇒ 绕房间中心（房间节点原点即中心）\n"
    + T + "await _pivot_play([{\n"
    + T + T + "\"at\": 0.0, \"do\": \"camera.pan\", \"pivot\": \"room_center\",\n"
    + T + T + "\"room_id\": NEXT_ROOM_ID, \"duration\": 0.0,\n"
    + T + "}])\n"
    + T + "_check(\n"
    + T + T + "absf(_camera.global_position.distance_to(PROBE_ROOM_CENTER) - rest_len) < 0.05,\n"
    + T + T + "\"pivot=room_center 后机位绕房间中心（距 %.2fm，期望 %.2fm）\"\n"
    + T + T + "% [_camera.global_position.distance_to(PROBE_ROOM_CENTER), rest_len],\n"
    + T + ")\n"
    + T + "_check(\n"
    + T + T + "_camera.global_position.distance_to(_player.global_position) > 3.0,\n"
    + T + T + "\"pivot=room_center 后机位真脱开了玩家\",\n"
    + T + ")\n"
    + T + "NarrativeDirector.abort(\"c6d\")\n"
    + T + "await _wait_frames(2)\n"
)
assert t.count(C5_END) == 1, "C5 尾锚点 %d" % t.count(C5_END)
t = t.replace(C5_END, C6)

# ---- ⑤ 相机初始位移常量 + _pivot_play helper ----
A5 = "func _emit_gameplay_started(room_id: String) -> void:\n"
B5 = (
    "## 接管前的「玩家→相机」位移（_build_world 里给的真实第三人称位姿）。\n"
    "const _CAMERA_REST_OFFSET := Vector3(0.0, 3.5, 6.0)\n"
    "\n"
    "\n"
    "## 起一段只跑运镜的测试剧本并等它接管（C6 用）。\n"
    "func _pivot_play(cues: Array) -> void:\n"
    + T + "var script := NarrativeScript3D.from_dictionary({\n"
    + T + T + "\"narrative_id\": \"test_camera_pivot\",\n"
    + T + T + "\"schema_version\": 1,\n"
    + T + T + "\"duration\": 30.0,\n"
    + T + T + "\"cues\": cues,\n"
    + T + "})\n"
    + T + "NarrativeDirector.register_script_for_test(\"test_camera_pivot\", script)\n"
    + T + "NarrativeDirector.play(\"test_camera_pivot\")\n"
    + T + "await _wait_frames(3)\n"
    "\n"
    "\n"
    + A5
)
assert t.count(A5) == 1, "_emit_gameplay_started 锚点 %d" % t.count(A5)
t = t.replace(A5, B5)

save(t)
print("TEST_PATCH_DONE")
