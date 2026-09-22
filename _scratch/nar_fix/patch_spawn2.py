# -*- coding: utf-8 -*-
"""scene.spawn 支持房间相对锚点 + 排列轴 + 交错；并加钥匙修复的源码守卫。"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
ADAPTER = os.path.join(ROOT, "src", "narrative", "NarrativeAdapter3D.gd")
D3 = os.path.join(ROOT, "src", "world3d", "Dungeon3D.gd")
JSON02 = os.path.join(ROOT, "data", "narrative", "nar_tower_opening_02_zombies.json")
TEST = os.path.join(ROOT, "tests", "verification", "verify_narrative_timeline.gd")
OPENING = os.path.join(ROOT, "tests", "verification", "verify_opening_script_runtime.gd")
T = "\t"


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


# ================= ① 适配器：整函数替换 _spawn_layout =================
TU = T
NEW_LAYOUT = (
    "## 剧情刷怪的站位。返回 {\"origin\": 队列中心, \"axis\": 展开轴, \"stagger\": 交错向量}。\n"
    "##\n"
    "## 两种锚法：\n"
    "##   · **房间相对**（`point_room` + `point_offset`）：队列钉在房间里的固定点。触发改成位置\n"
    "##     触发后，玩家落点会在一个半径内浮动 ⇒ 玩家相对的站位跟着抖，要钉住就得用这种。\n"
    "##   · 玩家相对（默认）：`origin = 玩家 + 右×distance + 前×forward_m`（老行为，逐值不变）。\n"
    "##\n"
    "## `axis`：队列沿哪个方向排开 —— `\"forward\"`（默认，沿玩家视线）/ `\"x\"`（东西）/ `\"z\"`（南北）。\n"
    "## `stagger_m`：相邻两只沿**排列轴的垂直方向**交替错开，别站成一条笔直的队。\n"
    "func _spawn_layout(params: Dictionary) -> Dictionary:\n"
    + TU + "var player := player_node()\n"
    + TU + "if player == null:\n"
    + TU + TU + "return {}\n"
    + TU + "var forward := -player.global_basis.z\n"
    + TU + "forward.y = 0.0\n"
    + TU + "if forward.length_squared() <= 0.000001:\n"
    + TU + TU + "forward = Vector3.FORWARD\n"
    + TU + "forward = forward.normalized()\n"
    + TU + "var right := forward.cross(Vector3.UP).normalized()\n"
    + TU + "var origin := Vector3.ZERO\n"
    + TU + "var anchor_room := str(params.get(\"point_room\", \"\"))\n"
    + TU + "if not anchor_room.is_empty():\n"
    + TU + TU + "var room := room_node(anchor_room)\n"
    + TU + TU + "if room == null:\n"
    + TU + TU + TU + "return {}\n"
    + TU + TU + "var offset := Vector3.ZERO\n"
    + TU + TU + "var offset_raw: Variant = params.get(\"point_offset\", null)\n"
    + TU + TU + "if offset_raw is Array and (offset_raw as Array).size() == 3:\n"
    + TU + TU + TU + "offset = Vector3(\n"
    + TU + TU + TU + TU + "float((offset_raw as Array)[0]),\n"
    + TU + TU + TU + TU + "float((offset_raw as Array)[1]),\n"
    + TU + TU + TU + TU + "float((offset_raw as Array)[2])\n"
    + TU + TU + TU + ")\n"
    + TU + TU + "origin = room.to_global(offset)\n"
    + TU + "else:\n"
    + TU + TU + "var side := str(params.get(\"side\", \"right\"))\n"
    + TU + TU + "var distance := float(params.get(\"distance\", 3.6))\n"
    + TU + TU + "var lateral := right if side == \"right\" else -right\n"
    + TU + TU + "var forward_m := maxf(0.0, distance * 0.5)\n"
    + TU + TU + "if params.get(\"forward_m\", null) != null:\n"
    + TU + TU + TU + "forward_m = maxf(0.0, float(params.get(\"forward_m\")))\n"
    + TU + TU + "origin = player.global_position + lateral * distance + forward * forward_m\n"
    + TU + "var axis := forward\n"
    + TU + "match str(params.get(\"axis\", \"forward\")):\n"
    + TU + TU + "\"x\":\n"
    + TU + TU + TU + "axis = Vector3.RIGHT\n"
    + TU + TU + "\"z\":\n"
    + TU + TU + TU + "axis = Vector3.BACK\n"
    + TU + "if axis.length_squared() <= 0.000001:\n"
    + TU + TU + "axis = forward\n"
    + TU + "axis = axis.normalized()\n"
    + TU + "var stagger_axis := axis.cross(Vector3.UP).normalized()\n"
    + TU + "if stagger_axis.length_squared() <= 0.000001:\n"
    + TU + TU + "stagger_axis = right\n"
    + TU + "# 队列沿 `axis` 展开（镜头转到侧面看过去时，这条队形在画面里是横排）。\n"
    + TU + "return {\n"
    + TU + TU + "\"origin\": origin,\n"
    + TU + TU + "\"axis\": axis,\n"
    + TU + TU + "\"stagger\": stagger_axis * maxf(0.0, float(params.get(\"stagger_m\", 0.0))),\n"
    + TU + "}\n"
)

t = load(ADAPTER)
start = t.index("func _spawn_layout(")
head = t.rindex("\n\n\n", 0, start) + 3
end = t.index("\n\n\n", start)
old_fn = t[head:end]
assert "_spawn_layout" in old_fn and "forward_override" in old_fn, "切片没套住老函数"
assert "func _scene_despawn" not in old_fn, "切片越界"
t = t[:head] + NEW_LAYOUT + t[end:]

# 调用点
A_CALL_OLD = (
    T + "var side := str(params.get(\"side\", \"right\"))\n"
    + T + "# `forward_m` = 沿视线方向的**额外前推**（米）。不写则沿用旧的 distance*0.5。\n"
    + T + "var layout := _spawn_layout(\n"
    + T + T + "side, float(params.get(\"distance\", 3.6)), params.get(\"forward_m\", null)\n"
    + T + ")\n"
    + T + "var origin: Vector3 = layout[\"origin\"]\n"
    + T + "var axis: Vector3 = layout[\"axis\"]\n"
    + T + "var result: Variant = dungeon.call(\n"
    + T + T + "\"narrative_spawn_enemies\", room_id, kind, count, origin, axis,\n"
    + T + T + "float(params.get(\"spread\", 1.5))\n"
    + T + ")\n"
)
A_CALL_NEW = (
    T + "var layout := _spawn_layout(params)\n"
    + T + "if layout.is_empty():\n"
    + T + T + "return _degraded(\n"
    + T + T + T + "\"scene.spawn：房间相对锚点『%s』解不出，本次刷怪跳过。\" % str(params.get(\"point_room\", \"\"))\n"
    + T + T + ")\n"
    + T + "var origin: Vector3 = layout[\"origin\"]\n"
    + T + "var axis: Vector3 = layout[\"axis\"]\n"
    + T + "var result: Variant = dungeon.call(\n"
    + T + T + "\"narrative_spawn_enemies\", room_id, kind, count, origin, axis,\n"
    + T + T + "float(params.get(\"spread\", 1.5)), layout.get(\"stagger\", Vector3.ZERO)\n"
    + T + ")\n"
)
assert t.count(A_CALL_OLD) == 1, "调用点锚点 %d" % t.count(A_CALL_OLD)
t = t.replace(A_CALL_OLD, A_CALL_NEW)
save(ADAPTER, t)

# ================= ② Dungeon3D：交错 =================
patch(D3, [
    (
        "spawn-sig",
        "func narrative_spawn_enemies(\n"
        + T + "room_id: String, kind: String, count: int, origin: Vector3,\n"
        + T + "axis: Vector3 = Vector3.RIGHT, spread: float = 1.6\n"
        + ") -> int:\n",
        "func narrative_spawn_enemies(\n"
        + T + "room_id: String, kind: String, count: int, origin: Vector3,\n"
        + T + "axis: Vector3 = Vector3.RIGHT, spread: float = 1.6,\n"
        + T + "stagger: Vector3 = Vector3.ZERO\n"
        + ") -> int:\n",
    ),
    (
        "spawn-pos",
        T + "positions.append(origin + flat_axis * ((float(index) - row) * spread))\n",
        T + "# 交错：相邻两只沿垂直方向往两边让开一点，别站成一条笔直的队。\n"
        + T + "var lateral_stagger := stagger * (0.5 if index % 2 == 1 else -0.5)\n"
        + T + "positions.append(\n"
        + T + T + "origin + flat_axis * ((float(index) - row) * spread) + lateral_stagger\n"
        + T + ")\n",
    ),
])

# ================= ③ 剧本 02 =================
patch(JSON02, [
    (
        "json-spawn",
        "      \"kind\": \"melee_chaser\",\n"
        "      \"count\": 5,\n"
        "      \"side\": \"right\",\n"
        "      \"distance\": 5.6,\n"
        "      \"forward_m\": 4.8,\n"
        "      \"spread\": 1.5\n",
        "      \"kind\": \"melee_chaser\",\n"
        "      \"count\": 5,\n"
        "      \"point_room\": \"floor_01_main_02\",\n"
        "      \"point_offset\": [6.0, 0.0, 0.0],\n"
        "      \"axis\": \"z\",\n"
        "      \"spread\": 1.6,\n"
        "      \"stagger_m\": 1.4\n",
    ),
])

# ================= ④ 测试假地牢签名 =================
patch(TEST, [
    (
        "fake-spawn-sig",
        "func narrative_spawn_enemies(\n"
        + T + "room_id: String, kind: String, count: int,\n"
        + T + "origin: Vector3, axis: Vector3 = Vector3.RIGHT, spread: float = 1.6\n"
        + ") -> int:\n",
        "func narrative_spawn_enemies(\n"
        + T + "room_id: String, kind: String, count: int,\n"
        + T + "origin: Vector3, axis: Vector3 = Vector3.RIGHT, spread: float = 1.6,\n"
        + T + "stagger: Vector3 = Vector3.ZERO\n"
        + ") -> int:\n",
    ),
    (
        "fake-spawn-record",
        T + T + "\"origin\": origin, \"axis\": axis, \"spread\": spread,\n",
        T + T + "\"origin\": origin, \"axis\": axis, \"spread\": spread, \"stagger\": stagger,\n",
    ),
])

# ================= ⑤ 钥匙：源码接线守卫 =================
GUARD = (
    T + "# 源码级守卫：门**开启路径**必须走 `_door_policy_towards`（会读房间声明的策略）。\n"
    + T + "# 退回 `_door_policy_for_edge` 就是那个「98F 每扇门都要钥匙」的老 bug —— 运行时零报错，\n"
    + T + "# 只有人报才会发现，所以必须能断言。\n"
    + T + "var d3_source := FileAccess.get_file_as_string(\"res://src/world3d/Dungeon3D.gd\")\n"
    + T + "var open_marker := \"func _try_open_room_door(target_room_id: String) -> bool:\"\n"
    + T + "var open_start := d3_source.find(open_marker)\n"
    + T + "_check(open_start >= 0, \"Dungeon3D 有 _try_open_room_door（开门路径）\")\n"
    + T + "if open_start >= 0:\n"
    + T + T + "var open_body := d3_source.substr(open_start, 900)\n"
    + T + T + "_check(\n"
    + T + T + T + "open_body.contains(\"_door_policy_towards(\"),\n"
    + T + T + T + "\"开门路径读房间声明的门策略（老 bug：读硬编码默认 ⇒ 98F 每扇门都要钥匙）\",\n"
    + T + T + ")\n"
    + "\n"
    + "\n"
    + "func _report() -> void:\n"
)
patch(OPENING, [("source-guard", "func _report() -> void:\n", GUARD)])

print("SPAWN_CORE_DONE")
