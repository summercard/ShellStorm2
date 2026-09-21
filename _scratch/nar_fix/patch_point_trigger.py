# -*- coding: utf-8 -*-
"""① 位置触发支持房间相对写法；② 导演惰性解析；③ 剧本 02 改触发+相机。"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
SCRIPT = os.path.join(ROOT, "src", "narrative", "NarrativeScript3D.gd")
DIRECTOR = os.path.join(ROOT, "src", "narrative", "NarrativeDirector3D.gd")
JSON02 = os.path.join(ROOT, "data", "narrative", "nar_tower_opening_02_zombies.json")


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


T = "\t"

# ---------------- ① 校验器 ----------------
V_OLD = (
    "func _validate_point_trigger(declared: Dictionary, source_label: String) -> Dictionary:\n"
    + T + "var point_raw: Variant = declared.get(\"point\", null)\n"
    + T + "if not (point_raw is Array) or (point_raw as Array).size() != 3:\n"
    + T + T + "errors.append(\"%s：point 触发必须提供 point:[x, y, z]。\" % source_label)\n"
    + T + "else:\n"
    + T + T + "var coordinates: Array = point_raw\n"
    + T + T + "declared[\"point\"] = Vector3(\n"
    + T + T + T + "float(coordinates[0]), float(coordinates[1]), float(coordinates[2])\n"
    + T + T + ")\n"
)
V_NEW = (
    "func _validate_point_trigger(declared: Dictionary, source_label: String) -> Dictionary:\n"
    + T + "# 两种写法二选一：绝对世界坐标 `point`，或**房间相对** `point_room` + `point_offset`。\n"
    + T + "# 房间相对的世界坐标由导演在运行期解出 —— 房间/楼层是运行时生成的，把世界坐标写死\n"
    + T + "# 在换布局后会**静默失效**（表现为「剧情永不触发」）。\n"
    + T + "var point_room_id := str(declared.get(\"point_room\", \"\"))\n"
    + T + "if not point_room_id.is_empty():\n"
    + T + T + "declared[\"point_room\"] = point_room_id\n"
    + T + T + "declared.erase(\"point\")\n"
    + T + T + "var offset_raw: Variant = declared.get(\"point_offset\", [0.0, 0.0, 0.0])\n"
    + T + T + "if not (offset_raw is Array) or (offset_raw as Array).size() != 3:\n"
    + T + T + T + "errors.append(\n"
    + T + T + T + T + "\"%s：point_room 的 point_offset 必须是 [x, y, z]（相对房间中心）。\" % source_label\n"
    + T + T + T + ")\n"
    + T + T + "else:\n"
    + T + T + T + "var offsets: Array = offset_raw\n"
    + T + T + T + "declared[\"point_offset\"] = Vector3(\n"
    + T + T + T + T + "float(offsets[0]), float(offsets[1]), float(offsets[2])\n"
    + T + T + T + ")\n"
    + T + "else:\n"
    + T + T + "var point_raw: Variant = declared.get(\"point\", null)\n"
    + T + T + "if not (point_raw is Array) or (point_raw as Array).size() != 3:\n"
    + T + T + T + "errors.append(\n"
    + T + T + T + T + "\"%s：point 触发必须提供 point:[x, y, z] 或 point_room + point_offset。\" % source_label\n"
    + T + T + T + ")\n"
    + T + T + "else:\n"
    + T + T + T + "var coordinates: Array = point_raw\n"
    + T + T + T + "declared[\"point\"] = Vector3(\n"
    + T + T + T + T + "float(coordinates[0]), float(coordinates[1]), float(coordinates[2])\n"
    + T + T + T + ")\n"
)
patch(SCRIPT, [("point-validate", V_OLD, V_NEW)])

# ---------------- ② 导演：惰性解析 ----------------
D_OLD = (
    "func _evaluate_point() -> void:\n"
    + T + "var player := _adapter.player_node()\n"
    + T + "if player == null:\n"
    + T + T + "return\n"
    + T + "var position := player.global_position\n"
    + T + "for narrative_id: String in _armed.keys():\n"
    + T + T + "var entry: Dictionary = _armed[narrative_id]\n"
    + T + T + "if str(entry.get(\"kind\", \"\")) != NarrativeScript3D.TRIGGER_KIND_POINT:\n"
    + T + T + T + "continue\n"
    + T + T + "var origin_value: Variant = entry.get(\"point\", null)\n"
    + T + T + "if not (origin_value is Vector3):\n"
    + T + T + T + "continue\n"
)
D_NEW = (
    "## 位置触发的原点。`point` 直接给世界坐标；`point_room` 用「房间节点原点 + point_offset」。\n"
    "## **惰性解析**：房间是运行时生成的，`arm()` 那一刻它还不存在 —— 解出后缓存进登记表。\n"
    "## 解不出（房间还没建/房间 id 写错）就返回 null，本轮跳过，不误触发。\n"
    "func _resolve_point_origin(entry: Dictionary) -> Variant:\n"
    + T + "if entry.has(\"point\"):\n"
    + T + T + "return entry.get(\"point\")\n"
    + T + "var room_id := str(entry.get(\"point_room\", \"\"))\n"
    + T + "if room_id.is_empty():\n"
    + T + T + "return null\n"
    + T + "var cached: Variant = entry.get(\"point_resolved\", null)\n"
    + T + "if cached is Vector3:\n"
    + T + T + "return cached\n"
    + T + "var room := _adapter.room_node(room_id)\n"
    + T + "if room == null:\n"
    + T + T + "return null\n"
    + T + "var offset: Vector3 = entry.get(\"point_offset\", Vector3.ZERO)\n"
    + T + "var resolved := room.global_position + offset\n"
    + T + "entry[\"point_resolved\"] = resolved\n"
    + T + "return resolved\n"
    "\n"
    "\n"
    "func _evaluate_point() -> void:\n"
    + T + "var player := _adapter.player_node()\n"
    + T + "if player == null:\n"
    + T + T + "return\n"
    + T + "var position := player.global_position\n"
    + T + "for narrative_id: String in _armed.keys():\n"
    + T + T + "var entry: Dictionary = _armed[narrative_id]\n"
    + T + T + "if str(entry.get(\"kind\", \"\")) != NarrativeScript3D.TRIGGER_KIND_POINT:\n"
    + T + T + T + "continue\n"
    + T + T + "var origin_value: Variant = _resolve_point_origin(entry)\n"
    + T + T + "if not (origin_value is Vector3):\n"
    + T + T + T + "continue\n"
)
patch(DIRECTOR, [("point-lazy", D_OLD, D_NEW)])

# ---------------- ③ 剧本 02 ----------------
J1_OLD = (
    "  \"trigger\": {\n"
    "    \"kind\": \"event\",\n"
    "    \"on\": \"room_entered\",\n"
    "    \"filter\": {\n"
    "      \"room_id\": \"floor_01_main_02\"\n"
    "    },\n"
    "    \"once\": \"run\"\n"
    "  },\n"
)
J1_NEW = (
    "  \"trigger\": {\n"
    + "    \"kind\": \"point\",\n"
    + "    \"point_room\": \"floor_01_main_02\",\n"
    + "    \"point_offset\": [-14.0, 0.0, 0.0],\n"
    + "    \"radius\": 2.5,\n"
    + "    \"once\": \"run\"\n"
    + "  },\n"
)
J2_OLD = (
    "      \"at\": 0.1,\n"
    "      \"do\": \"camera.pan\",\n"
    "      \"yaw_deg\": -26.0,\n"
    "      \"duration\": 1.3\n"
)
J2_NEW = (
    "      \"at\": 0.1,\n"
    "      \"do\": \"camera.pan\",\n"
    "      \"pivot\": \"last_spawn\",\n"
    "      \"yaw_deg\": 0.0,\n"
    "      \"duration\": 1.3\n"
)
J3_OLD = (
    "      \"at\": 2.6,\n"
    "      \"do\": \"camera.pan\",\n"
    "      \"yaw_deg\": 0.0,\n"
    "      \"duration\": 1.2\n"
)
J3_NEW = (
    "      \"at\": 2.6,\n"
    "      \"do\": \"camera.pan\",\n"
    "      \"pivot\": \"player\",\n"
    "      \"yaw_deg\": 0.0,\n"
    "      \"duration\": 1.2\n"
)
patch(JSON02, [("json-trigger", J1_OLD, J1_NEW), ("json-pan-over", J2_OLD, J2_NEW), ("json-pan-back", J3_OLD, J3_NEW)])

print("STAGE1_DONE")
