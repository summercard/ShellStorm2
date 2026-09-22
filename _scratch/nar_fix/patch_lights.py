# -*- coding: utf-8 -*-
"""开局第一间房（主人办公室）灯默认开：按房间声明 authored_room_light_on 全链透传。"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
ROOM = os.path.join(ROOT, "src", "world3d", "DungeonRoom3D.gd")
BLOCK = os.path.join(ROOT, "src", "world3d", "Block00MasterOfficeLayout3D.gd")
TOWER = os.path.join(ROOT, "src", "world3d", "TowerDescent3D.gd")
D3 = os.path.join(ROOT, "src", "world3d", "Dungeon3D.gd")
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


# ---------- ① DungeonRoom3D ----------
patch(ROOM, [
    (
        "var",
        "var authored_layout_peaceful := false\n",
        "var authored_layout_peaceful := false\n"
        + "## 本房**初始灯就亮**（不经玩家按开关、不播启动序列）。给「开局第一间房」用 ——\n"
        + "## 玩家一睁眼不该是黑的。默认 false = 老行为（只有 STAIR_LOBBY / BOSS 默认亮）。\n"
        + "var authored_room_light_on := false\n",
    ),
    (
        "config-read",
        T + "authored_layout_peaceful = bool(config.get(\"authored_layout_peaceful\", authored_layout_peaceful))\n",
        T + "authored_layout_peaceful = bool(config.get(\"authored_layout_peaceful\", authored_layout_peaceful))\n"
        + T + "authored_room_light_on = bool(config.get(\"authored_room_light_on\", authored_room_light_on))\n",
    ),
    (
        "starts-on",
        T + T + "var starts_on := room_type in [\"STAIR_LOBBY\", \"BOSS\"]\n",
        T + T + "# 房间声明的「初始灯亮」优先（开局第一间房），其次才是按房型的默认。\n"
        + T + T + "var starts_on := authored_room_light_on or room_type in [\"STAIR_LOBBY\", \"BOSS\"]\n",
    ),
    (
        "state-default",
        T + "var wanted_light_on := bool(_pending_detail_runtime_state.get(\"room_light_on\", false))\n",
        T + T + "# 默认值必须跟着房间声明走：写死 false 会把「初始灯亮」在重建时顶掉。\n"
        + T + "var wanted_light_on := bool(\n"
        + T + T + "_pending_detail_runtime_state.get(\"room_light_on\", authored_room_light_on)\n"
        + T + ")\n",
    ),
])

# ---------- ② 区块00：只有办公室（binding key = exit）灯默认开 ----------
patch(BLOCK, [
    (
        "rooms-append",
        T + T + T + "\"authored_layout_peaceful\": PEACEFUL_ZONE,\n",
        T + T + T + "\"authored_layout_peaceful\": PEACEFUL_ZONE,\n"
        + T + T + T + "# 开局第一间房 = 主人办公室（binding key `exit`）：灯**默认打开**，\n"
        + T + T + T + "# 玩家在开场演出里一睁眼就不是黑的。其余三间仍要手动按开关。\n"
        + T + T + T + "\"authored_room_light_on\": str(binding[\"key\"]) == \"exit\",\n",
    ),
])

# ---------- ③ 塔楼：记录透传 ----------
patch(TOWER, [
    (
        "record",
        T + T + "if bool(spec.get(\"authored_layout_peaceful\", false)):\n"
        + T + T + T + "record[\"authored_layout_peaceful\"] = true\n",
        T + T + "if bool(spec.get(\"authored_layout_peaceful\", false)):\n"
        + T + T + T + "record[\"authored_layout_peaceful\"] = true\n"
        + T + T + "# 初始灯亮：只在房表声明了才落字段，未声明的房间一个字段都不多。\n"
        + T + T + "if bool(spec.get(\"authored_room_light_on\", false)):\n"
        + T + T + T + "record[\"authored_room_light_on\"] = true\n",
    ),
])

# ---------- ④ Dungeon3D：configure 透传 ----------
patch(D3, [
    (
        "configure",
        T + T + T + "\"authored_layout_peaceful\": bool(record.get(\"authored_layout_peaceful\", false)),\n",
        T + T + T + "\"authored_layout_peaceful\": bool(record.get(\"authored_layout_peaceful\", false)),\n"
        + T + T + T + "\"authored_room_light_on\": bool(record.get(\"authored_room_light_on\", false)),\n",
    ),
])

# ---------- ⑤ 真机验收 G 段 ----------
G_FN = (
    "## 开局第一间房（主人办公室 `floor_01_exit`）的灯必须**默认打开** ——\n"
    "## 玩家在开场演出里一睁眼不该是黑的。会议室仍是默认关（反向对照：不是全层都开）。\n"
    "## 顺带把「第二段刷怪点」也按声明在真机上验一遍几何（房间相对锚点解出来必须落在房内）。\n"
    "func _phase_g_opening_room_light() -> void:\n"
    + T + "var rooms: Variant = _tower.get(\"_room_by_id\")\n"
    + T + "if not (rooms is Dictionary):\n"
    + T + T + "_check(false, \"拿不到塔楼房间表（灯与刷怪点校验无法进行）\")\n"
    + T + T + "return\n"
    + T + "var office := (rooms as Dictionary).get(OPENING_ROOM_ID) as DungeonRoom3D\n"
    + T + "_check(office != null, \"有办公室房 %s\" % OPENING_ROOM_ID)\n"
    + T + "if office != null:\n"
    + T + T + "_check(office.authored_room_light_on, \"办公室声明了「灯默认开」\")\n"
    + T + T + "_check(office.is_room_light_on(), \"办公室的灯**确实亮着**（开局不该是黑的）\")\n"
    + T + "var meeting := (rooms as Dictionary).get(ZOMBIES_ROOM_ID) as DungeonRoom3D\n"
    + T + "if meeting != null:\n"
    + T + T + "_check(\n"
    + T + T + T + "not meeting.is_room_light_on(),\n"
    + T + T + T + "\"会议室仍默认关灯（反向对照：不是全层都点亮）\",\n"
    + T + T + ")\n"
    + T + "var zombies := NarrativeScript3D.load_from_id(ZOMBIES_ID)\n"
    + T + "if zombies == null:\n"
    + T + T + "return\n"
    + T + "for cue in zombies.cues:\n"
    + T + T + "if str(cue.get(\"do\", \"\")) != \"scene.spawn\":\n"
    + T + T + T + "continue\n"
    + T + T + "if str(cue.get(\"point_room\", \"\")) != ZOMBIES_ROOM_ID:\n"
    + T + T + T + "continue\n"
    + T + T + "var offset_raw: Variant = cue.get(\"point_offset\", null)\n"
    + T + T + "var room := (rooms as Dictionary).get(ZOMBIES_ROOM_ID) as DungeonRoom3D\n"
    + T + T + "if room == null or not (offset_raw is Array) or (offset_raw as Array).size() != 3:\n"
    + T + T + T + "continue\n"
    + T + T + "var off: Array = offset_raw\n"
    + T + T + "var spawn_point := room.to_global(Vector3(float(off[0]), float(off[1]), float(off[2])))\n"
    + T + T + "_check(\n"
    + T + T + T + "room.contains_world_position(spawn_point),\n"
    + T + T + T + "\"第二段刷怪点落在会议室内部（world=%.1f, %.1f, %.1f）\"\n"
    + T + T + T + "% [spawn_point.x, spawn_point.y, spawn_point.z],\n"
    + T + T + ")\n"
    + T + T + "_note(\n"
    + T + T + T + "\"G 刷怪点 = (%.1f, %.1f, %.1f)\" % [spawn_point.x, spawn_point.y, spawn_point.z]\n"
    + T + T + ")\n"
    + "\n"
    "\n"
    "func _report() -> void:\n"
)
t = load(OPENING)
assert t.count(T + "_phase_f_block00_door_policies()\n") == 1
t = t.replace(
    T + "_phase_f_block00_door_policies()\n" + T + "_report()\n",
    T + "_phase_f_block00_door_policies()\n"
    + T + "_phase_g_opening_room_light()\n"
    + T + "_report()\n",
)
assert t.count("func _report() -> void:\n") == 1
t = t.replace("func _report() -> void:\n", G_FN)
save(OPENING, t)

print("TASK11_DONE")
