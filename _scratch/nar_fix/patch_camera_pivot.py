# -*- coding: utf-8 -*-
"""给叙事运镜加「枢轴」：默认玩家，可 last_spawn / room_center / pivot_m，平滑平移过去。"""
import os

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\narrative\NarrativeAdapter3D.gd"
T = "\t"


def load():
    raw = open(P, "rb").read()
    crlf = raw.count(b"\r\n")
    lf = raw.count(b"\n")
    assert crlf and crlf == lf, "行尾不纯 CRLF=%d LF=%d" % (crlf, lf)
    return raw.decode("utf-8").replace("\r\n", "\n")


def save(text):
    data = text.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(P, "wb").write(data)
    print("wrote CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))


t = load()
EDITS = []

# ---- 1) 类头注释：焦点不再"完全继承" ----
EDITS.append((
    "header",
    "## 叙事只改「距离」「绕玩家竖轴的方位」与「俯角」，焦点完全继承，\n"
    "## 这样叙事镜头与玩法镜头永远同一套构图语言。\n",
    "## 叙事只改「距离」「绕枢轴的方位」「俯角」与「枢轴点」，相对构图完全继承，\n"
    "## 这样叙事镜头与玩法镜头永远同一套构图语言。\n"
    "## 枢轴默认 = 玩家（焦点钉在主角身上）。要「脱开主角、整台机位平移过去拍别处」，\n"
    "## 给 camera.focus / camera.pan 写 `pivot: last_spawn|room_center` 或 `pivot_m: [x,y,z]`。\n",
))

# ---- 2) 状态变量 ----
EDITS.append((
    "state",
    "var _camera_rest_elevation_deg := 0.0  # 接管前那套俯角（度），elevation_deg 的缺省值\n",
    "var _camera_rest_elevation_deg := 0.0  # 接管前那套俯角（度），elevation_deg 的缺省值\n"
    "\n"
    "# —— 运镜枢轴（2026-09-21）：默认钉在玩家身上，可脱开去拍别处 ——\n"
    "var _camera_pivot_channel := {}   # 枢轴通道（Vector3）{from, to, t, duration, value}\n"
    "var _camera_pivot_mode := \"player\"  # player / last_spawn / room_center / point\n"
    "var _camera_pivot_point := Vector3.ZERO  # mode=point（pivot_m）时的显式坐标\n"
    "var _camera_pivot_room_id := \"\"  # mode=room_center 时用哪个房间\n"
    "var _has_last_spawn := false      # 是否已经有过 scene.spawn\n"
    "var _last_spawn_origin := Vector3.ZERO  # 最近一次剧情刷怪的队列中心\n",
))

# ---- 3) tick：推进枢轴通道 ----
EDITS.append((
    "tick",
    T + "if _camera_override_active:\n"
    + T + T + "_advance_channel(_camera_channel, delta)\n"
    + T + T + "_advance_channel(_camera_yaw_channel, delta)\n"
    + T + T + "_advance_channel(_camera_elev_channel, delta)\n"
    + T + T + "_apply_camera_pose()\n",
    T + "if _camera_override_active:\n"
    + T + T + "_advance_channel(_camera_channel, delta)\n"
    + T + T + "_advance_channel(_camera_yaw_channel, delta)\n"
    + T + T + "_advance_channel(_camera_elev_channel, delta)\n"
    + T + T + "var pivot_done := _advance_vector_channel(_camera_pivot_channel, delta)\n"
    + T + T + "# 枢轴平滑落回玩家后清空通道 ⇒ 焦点重新「实时跟随玩家」，与接管前一字不差\n"
    + T + T + "# （否则会钉在那一刻的玩家位置快照上）。\n"
    + T + T + "if pivot_done and _camera_pivot_mode == \"player\":\n"
    + T + T + T + "_camera_pivot_channel = {}\n"
    + T + T + "_apply_camera_pose()\n",
))

# ---- 4) 向量通道推进（_advance_channel 只吃 float） ----
EDITS.append((
    "vector-channel",
    "func _advance_channel(channel: Dictionary, delta: float) -> bool:\n",
    "## 与 _advance_channel 同构，但值是 Vector3 —— 枢轴要能做空间位移，不能只 lerpf。\n"
    "func _advance_vector_channel(channel: Dictionary, delta: float) -> bool:\n"
    + T + "if channel.is_empty():\n"
    + T + T + "return false\n"
    + T + "var duration := float(channel.get(\"duration\", 0.0))\n"
    + T + "var elapsed := float(channel.get(\"t\", 0.0)) + delta\n"
    + T + "channel[\"t\"] = elapsed\n"
    + T + "var to: Vector3 = channel.get(\"to\", Vector3.ZERO)\n"
    + T + "if duration <= 0.0:\n"
    + T + T + "channel[\"value\"] = to\n"
    + T + T + "return true\n"
    + T + "var weight := clampf(elapsed / duration, 0.0, 1.0)\n"
    + T + "var from: Vector3 = channel.get(\"from\", Vector3.ZERO)\n"
    + T + "channel[\"value\"] = from.lerp(to, weight)\n"
    + T + "return weight >= 1.0\n"
    "\n"
    "\n"
    "func _advance_channel(channel: Dictionary, delta: float) -> bool:\n",
))

# ---- 5) 接管起点：枢轴复位 ----
EDITS.append((
    "override-start",
    T + "_camera_override_active = true\n" + T + "return true\n",
    T + "_camera_pivot_channel = {}\n"
    + T + "_camera_pivot_mode = \"player\"\n"
    + T + "_camera_override_active = true\n"
    + T + "return true\n",
))

# ---- 6) focus / pan 读枢轴 ----
FOCUS_OLD = (
    T + "var duration := maxf(0.0, float(params.get(\"duration\", 0.6)))\n"
    + T + "_camera_channel = {\n"
    + T + T + "\"from\": _camera_distance(), \"to\": target_distance, \"t\": 0.0, \"duration\": duration,\n"
    + T + T + "\"value\": _camera_distance(),\n"
    + T + "}\n"
)
FOCUS_NEW = (
    T + "var duration := maxf(0.0, float(params.get(\"duration\", 0.6)))\n"
    + T + "_apply_camera_pivot_params(params, duration)\n"
    + T + "_camera_channel = {\n"
    + T + T + "\"from\": _camera_distance(), \"to\": target_distance, \"t\": 0.0, \"duration\": duration,\n"
    + T + T + "\"value\": _camera_distance(),\n"
    + T + "}\n"
)
EDITS.append(("focus-pivot", FOCUS_OLD, FOCUS_NEW))

PAN_OLD = (
    T + "var duration := maxf(0.0, float(params.get(\"duration\", 0.6)))\n"
    + T + "_camera_yaw_channel = {\n"
)
PAN_NEW = (
    T + "var duration := maxf(0.0, float(params.get(\"duration\", 0.6)))\n"
    + T + "_apply_camera_pivot_params(params, duration)\n"
    + T + "_camera_yaw_channel = {\n"
)
EDITS.append(("pan-pivot", PAN_OLD, PAN_NEW))

# ---- 7) restore：枢轴一起带回玩家 ----
RESTORE_OLD = (
    T + "var duration := maxf(0.0, float(params.get(\"duration\", 0.6)))\n"
    + T + "_camera_channel = {\n"
    + T + T + "\"from\": _camera_distance(), \"to\": _camera_rest_offset.length(),\n"
)
RESTORE_NEW = (
    T + "var duration := maxf(0.0, float(params.get(\"duration\", 0.6)))\n"
    + T + "# 回镜必须把**枢轴**也带回玩家：否则机位会绕着一个远处的点收镜，最后再「跳」回玩家。\n"
    + T + "var restore_player := player_node()\n"
    + T + "if restore_player != null:\n"
    + T + T + "var pivot_from := _current_camera_pivot(restore_player)\n"
    + T + T + "_camera_pivot_mode = \"player\"\n"
    + T + T + "_camera_pivot_channel = {\n"
    + T + T + T + "\"from\": pivot_from, \"to\": restore_player.global_position, \"t\": 0.0,\n"
    + T + T + T + "\"duration\": duration, \"value\": pivot_from,\n"
    + T + T + "}\n"
    + T + "_camera_channel = {\n"
    + T + T + "\"from\": _camera_distance(), \"to\": _camera_rest_offset.length(),\n"
)
EDITS.append(("restore-pivot", RESTORE_OLD, RESTORE_NEW))

# ---- 8) 解析函数（插在 _camera_elev_deg 之后 / _apply_camera_pose 之前） ----
PIVOT_FUNCS = (
    "## 从 cue 里读枢轴声明。三个字段都没给 ⇒ 沿用当前枢轴（默认玩家）。\n"
    "##   `pivot`：\"player\"（默认）/ \"last_spawn\" / \"room_center\"\n"
    "##   `room_id`：仅 \"room_center\" 用\n"
    "##   `pivot_m`：[x, y, z] 显式世界坐标（最优先，压过 pivot）\n"
    "func _apply_camera_pivot_params(params: Dictionary, duration: float) -> void:\n"
    + T + "var player := player_node()\n"
    + T + "if player == null:\n"
    + T + T + "return\n"
    + T + "if params.has(\"pivot_m\"):\n"
    + T + T + "var raw: Variant = params.get(\"pivot_m\")\n"
    + T + T + "if raw is Array and (raw as Array).size() == 3:\n"
    + T + T + T + "_camera_pivot_point = Vector3(\n"
    + T + T + T + T + "float((raw as Array)[0]), float((raw as Array)[1]), float((raw as Array)[2])\n"
    + T + T + T + ")\n"
    + T + T + T + "_camera_pivot_mode = \"point\"\n"
    + T + T + T + "_start_camera_pivot_move(player, duration)\n"
    + T + T + "else:\n"
    + T + T + T + "_warn(\"camera.pivot_m 必须是 [x, y, z] 三个数，本镜头枢轴未变。\")\n"
    + T + T + "return\n"
    + T + "if not params.has(\"pivot\"):\n"
    + T + T + "return\n"
    + T + "var mode := str(params.get(\"pivot\", \"player\"))\n"
    + T + "if mode not in [\"player\", \"last_spawn\", \"room_center\"]:\n"
    + T + T + "_warn(\n"
    + T + T + T + "\"camera.pivot『%s』未知（可选 player / last_spawn / room_center，或直接用 pivot_m），本镜头退回玩家。\"\n"
    + T + T + T + "% mode\n"
    + T + T + ")\n"
    + T + T + "mode = \"player\"\n"
    + T + "_camera_pivot_mode = mode\n"
    + T + "if mode == \"room_center\":\n"
    + T + T + "_camera_pivot_room_id = str(params.get(\"room_id\", \"\"))\n"
    + T + "_start_camera_pivot_move(player, duration)\n"
    "\n"
    "\n"
    "## 把枢轴从当前位置平滑移到「当前声明」解析出的目标点。\n"
    "func _start_camera_pivot_move(player: Node3D, duration: float) -> void:\n"
    + T + "var from := _current_camera_pivot(player)\n"
    + T + "var target := _resolve_camera_pivot(player)\n"
    + T + "_camera_pivot_channel = {\n"
    + T + T + "\"from\": from, \"to\": target, \"t\": 0.0,\n"
    + T + T + "\"duration\": maxf(0.0, duration), \"value\": from,\n"
    + T + "}\n"
    "\n"
    "\n"
    "## 当前枢轴世界坐标：有通道走通道值，否则按声明实时解析。\n"
    "func _current_camera_pivot(player: Node3D) -> Vector3:\n"
    + T + "if not _camera_pivot_channel.is_empty():\n"
    + T + T + "return _camera_pivot_channel.get(\"value\", player.global_position)\n"
    + T + "return _resolve_camera_pivot(player)\n"
    "\n"
    "\n"
    "## 按 `_camera_pivot_mode` 解析枢轴目标点。拿不到就**告警并退回玩家**（不静默）。\n"
    "func _resolve_camera_pivot(player: Node3D) -> Vector3:\n"
    + T + "match _camera_pivot_mode:\n"
    + T + T + "\"point\":\n"
    + T + T + T + "return _camera_pivot_point\n"
    + T + T + "\"last_spawn\":\n"
    + T + T + T + "if _has_last_spawn:\n"
    + T + T + T + T + "return _last_spawn_origin\n"
    + T + T + T + "_warn(\"camera.pivot=last_spawn，但本段还没有 scene.spawn，退回玩家。\")\n"
    + T + T + "\"room_center\":\n"
    + T + T + T + "var room := room_node(_camera_pivot_room_id)\n"
    + T + T + T + "if room != null:\n"
    + T + T + T + T + "# 房间节点原点即房间中心（DungeonRoom3D 的 ±dimensions/2 约定）。\n"
    + T + T + T + T + "return room.global_position\n"
    + T + T + T + "_warn(\"camera.pivot=room_center，但找不到房间『%s』，退回玩家。\" % _camera_pivot_room_id)\n"
    + T + "return player.global_position\n"
    "\n"
    "\n"
    "func _apply_camera_pose() -> void:\n"
)
EDITS.append((
    "pivot-funcs",
    "func _apply_camera_pose() -> void:\n",
    PIVOT_FUNCS,
))

# ---- 9) _apply_camera_pose 用枢轴 ----
EDITS.append((
    "pose-pivot",
    T + "# 相机绕玩家做**刚体轨道**：先把「接管前那条 玩家→相机 轴」绕水平轴抬/压到目标俯角，\n"
    + T + "# 再绕玩家竖轴转方位角。位置与朝向同步旋转，所以焦点始终钉在玩家身上，\n"
    + T + "# 俯角变化 = 镜头真的从上方压下来，而不是沿同一条轴滑动。\n"
    + T + "var pivot := _camera_elevation_pivot()\n",
    T + "# 相机绕**枢轴**做刚体轨道：先把「接管前那条 枢轴→相机 轴」绕水平轴抬/压到目标俯角，\n"
    + T + "# 再绕枢轴竖轴转方位角。位置与朝向同步旋转，所以焦点恒在枢轴上 ——\n"
    + T + "# 枢轴默认 = 玩家（焦点钉在主角身上，老行为一字不变）；显式给 pivot 时枢轴移到别处，\n"
    + T + "# 整台相机就「平移过去」并对准新焦点。\n"
    + T + "# 俯角变化 = 镜头真的从上方压下来，而不是沿同一条轴滑动。\n"
    + T + "var elev_pivot := _camera_elevation_pivot()\n",
))

EDITS.append((
    "pose-use",
    T + "var offset := orbit * pivot * _camera_rest_offset\n"
    + T + "if offset.length_squared() <= 0.000001:\n"
    + T + T + "return\n"
    + T + "var distance := maxf(CAMERA_MIN_DISTANCE_M, _camera_distance())\n"
    + T + "_camera.global_transform = Transform3D(\n"
    + T + T + "orbit * pivot * _camera_rest_basis,\n"
    + T + T + "player.global_position + offset.normalized() * distance\n"
    + T + ")\n",
    T + "var offset := orbit * elev_pivot * _camera_rest_offset\n"
    + T + "if offset.length_squared() <= 0.000001:\n"
    + T + T + "return\n"
    + T + "var distance := maxf(CAMERA_MIN_DISTANCE_M, _camera_distance())\n"
    + T + "var center := _current_camera_pivot(player)\n"
    + T + "_camera.global_transform = Transform3D(\n"
    + T + T + "orbit * elev_pivot * _camera_rest_basis,\n"
    + T + T + "center + offset.normalized() * distance\n"
    + T + ")\n",
))

# ---- 10) 归还时清枢轴 ----
EDITS.append((
    "release-pivot",
    T + "_camera_channel = {}\n"
    + T + "_camera_yaw_channel = {}\n"
    + T + "_camera_elev_channel = {}\n",
    T + "_camera_channel = {}\n"
    + T + "_camera_yaw_channel = {}\n"
    + T + "_camera_elev_channel = {}\n"
    + T + "_camera_pivot_channel = {}\n"
    + T + "_camera_pivot_mode = \"player\"\n"
    + T + "_camera_pivot_point = Vector3.ZERO\n"
    + T + "_camera_pivot_room_id = \"\"\n",
))

# ---- 11) scene.spawn 记下队列中心 ----
EDITS.append((
    "spawn-cache",
    T + "if result is int and int(result) > 0:\n"
    + T + T + "# 刷新出来的怪是**已发生的效果**，收口时不回滚（08 文档 §6.4）：\n"
    + T + T + "# 玩家看完这句就要自己动手清场，怪在这里消失才是 bug。\n"
    + T + T + "return _ok()\n",
    T + "if result is int and int(result) > 0:\n"
    + T + T + "# 记下队列中心：相机枢轴 `pivot: \"last_spawn\"` 用它（作者不用写坐标）。\n"
    + T + T + "_has_last_spawn = true\n"
    + T + T + "_last_spawn_origin = origin\n"
    + T + T + "# 刷新出来的怪是**已发生的效果**，收口时不回滚（08 文档 §6.4）：\n"
    + T + T + "# 玩家看完这句就要自己动手清场，怪在这里消失才是 bug。\n"
    + T + T + "return _ok()\n",
))

for label, a, b in EDITS:
    n = t.count(a)
    assert n == 1, "锚点『%s』命中 %d 次" % (label, n)
    t = t.replace(a, b)

save(t)
print("ADAPTER_PATCH_DONE edits=%d" % len(EDITS))
