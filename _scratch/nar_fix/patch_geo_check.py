# -*- coding: utf-8 -*-
"""① 导演：房间相对偏移走 to_global + 加 point_origin_for_test；② 开场真机验收加真实几何校验。"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
DIRECTOR = os.path.join(ROOT, "src", "narrative", "NarrativeDirector3D.gd")
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


# ---------------- ① 导演 ----------------
D_OLD = (
    T + "var offset: Vector3 = entry.get(\"point_offset\", Vector3.ZERO)\n"
    + T + "var resolved := room.global_position + offset\n"
    + T + "entry[\"point_resolved\"] = resolved\n"
    + T + "return resolved\n"
)
D_NEW = (
    T + "var offset: Vector3 = entry.get(\"point_offset\", Vector3.ZERO)\n"
    + T + "# 走**房间局部系**（to_global）而不是直接加世界位移：房间若带旋转，\n"
    + T + "# 作者写的「往房间 x 方向 14m」应当跟着房间转。\n"
    + T + "var resolved := room.to_global(offset)\n"
    + T + "entry[\"point_resolved\"] = resolved\n"
    + T + "return resolved\n"
)
E_OLD = (
    "## 仅供验收：走一遍真实的位置评估（等价于 _process 里 0.1s 轮询的那一发）。\n"
    "func evaluate_point_for_test() -> void:\n"
    + T + "_evaluate_point()\n"
)
E_NEW = E_OLD + (
    "\n"
    "\n"
    "## 仅供验收：把某条剧本的「位置触发原点」解析出来。房间相对写法必须靠它做真机几何校验\n"
    "## （假世界里的算术对了，不代表真实楼层上的房间位置/朝向也对）。\n"
    "func point_origin_for_test(narrative_id: String) -> Variant:\n"
    + T + "if not _armed.has(narrative_id):\n"
    + T + T + "return null\n"
    + T + "return _resolve_point_origin(_armed[narrative_id])\n"
)
patch(DIRECTOR, [("to-global", D_OLD, D_NEW), ("point-origin-for-test", E_OLD, E_NEW)])

# ---------------- ② 开场真机验收 ----------------
C_OLD = "const OPENING_ROOM_ID := \"floor_01_exit\"\n"
C_NEW = (
    C_OLD
    + "## 第二段：位置触发的真实几何校验用它。\n"
    + "const ZOMBIES_ID := \"nar_tower_opening_02_zombies\"\n"
    + "const ZOMBIES_ROOM_ID := \"floor_01_main_02\"\n"
)
R_OLD = T + "await _phase_d_entry_camera_yield()\n" + T + "_report()\n"
R_NEW = (
    T + "await _phase_d_entry_camera_yield()\n"
    + T + "_phase_e_zombie_trigger_geometry()\n"
    + T + "_report()\n"
)
F_OLD = "func _report() -> void:\n"
F_NEW = (
    "## 第二段触发器是**房间相对**的（`point_room` + `point_offset`）。假世界只能验证算术；\n"
    "## 这里在**真机几何**上验：解出来的点必须落在会议室内部、且**不在**玩家上一个房间（办公室）里\n"
    "## —— 证明「必须真的走进房间、门关上之后才触发」这条约束在真实楼层上成立。\n"
    "func _phase_e_zombie_trigger_geometry() -> void:\n"
    + T + "var rooms: Variant = _tower.get(\"_room_by_id\")\n"
    + T + "if not (rooms is Dictionary):\n"
    + T + T + "_check(false, \"拿不到塔楼房间表（本段几何校验无法进行）\")\n"
    + T + T + "return\n"
    + T + "var room := (rooms as Dictionary).get(ZOMBIES_ROOM_ID) as DungeonRoom3D\n"
    + T + "_check(room != null, \"98F 存在房间 %s\" % ZOMBIES_ROOM_ID)\n"
    + T + "if room == null:\n"
    + T + T + "return\n"
    + T + "var origin: Variant = NarrativeDirector.point_origin_for_test(ZOMBIES_ID)\n"
    + T + "_check(origin is Vector3, \"第二段的位置触发原点可解析（房间相对写法）\")\n"
    + T + "if not (origin is Vector3):\n"
    + T + T + "return\n"
    + T + "var point := origin as Vector3\n"
    + T + "_check(\n"
    + T + T + "room.contains_world_position(point),\n"
    + T + T + "\"触发点落在会议室**内部**（world=%.1f, %.1f, %.1f）\" % [point.x, point.y, point.z],\n"
    + T + ")\n"
    + T + "var office := (rooms as Dictionary).get(OPENING_ROOM_ID) as DungeonRoom3D\n"
    + T + "if office != null:\n"
    + T + T + "_check(\n"
    + T + T + T + "not office.contains_world_position(point),\n"
    + T + T + T + "\"触发点**不在**办公室内（玩家必须真的走进会议室才触发）\",\n"
    + T + T + ")\n"
    + T + "_note(\n"
    + T + T + "\"E 第二段触发点 = (%.1f, %.1f, %.1f)；会议室中心 = (%.1f, %.1f, %.1f)\"\n"
    + T + T + "% [\n"
    + T + T + T + "point.x, point.y, point.z,\n"
    + T + T + T + "room.global_position.x, room.global_position.y, room.global_position.z,\n"
    + T + T + "]\n"
    + T + ")\n"
    + "\n"
    "\n"
    + F_OLD
)
patch(OPENING, [
    ("consts", C_OLD, C_NEW),
    ("ready-call", R_OLD, R_NEW),
    ("phase-e", F_OLD, F_NEW),
])

print("STAGE3_DONE")
