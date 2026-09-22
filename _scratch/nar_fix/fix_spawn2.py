# -*- coding: utf-8 -*-
"""修：① 交错代码缩进补一层；② C2 旧断言（玩家相对）换成房间相对三连断言。"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
D3 = os.path.join(ROOT, "src", "world3d", "Dungeon3D.gd")
TEST = os.path.join(ROOT, "tests", "verification", "verify_narrative_timeline.gd")
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


# ---------- ① 缩进 ----------
t = load(D3)
BAD = (
    T + "var lateral_stagger := stagger * (0.5 if index % 2 == 1 else -0.5)\n"
    + T + "positions.append(\n"
    + T + T + "origin + flat_axis * ((float(index) - row) * spread) + lateral_stagger\n"
    + T + ")\n"
)
GOOD = (
    T + T + "var lateral_stagger := stagger * (0.5 if index % 2 == 1 else -0.5)\n"
    + T + T + "positions.append(\n"
    + T + T + T + "origin + flat_axis * ((float(index) - row) * spread) + lateral_stagger\n"
    + T + T + ")\n"
)
assert t.count(BAD) == 1, "缩进锚点 %d" % t.count(BAD)
t = t.replace(BAD, GOOD)
save(D3, t)

# ---------- ② C2 断言 ----------
t = load(TEST)
MARK = "var fwd_axis := -_player.global_basis.z"
s = t.index(MARK)
s = t.rindex("\n", 0, s) + 1
end_marker = T + T + ")\n"
e = t.index(end_marker, s) + len(end_marker)
old_block = t[s:e]
assert "_check(" in old_block and len(old_block) < 1200, "切片异常"
NEW = (
    T + T + "# 队列用**房间相对**锚点钉住（point_room + point_offset）：触发改成位置触发后，\n"
    + T + T + "# 玩家落点会在一个半径内浮动，玩家相对的站位会跟着抖，钉不住。\n"
    + T + T + "var want_center := PROBE_ROOM_CENTER + Vector3(6.0, 0.0, 0.0)\n"
    + T + T + "_check(\n"
    + T + T + T + "(origin as Vector3).distance_to(want_center) < 0.05,\n"
    + T + T + T + "\"队列钉在房间相对点上（实际 %s，期望 %s）\" % [str(origin), str(want_center)],\n"
    + T + T + ")\n"
    + T + T + "# 排列轴：剧本写的是南北（世界 z）\n"
    + T + T + "var spawn_axis: Vector3 = call.get(\"axis\", Vector3.ZERO)\n"
    + T + T + "_check(\n"
    + T + T + T + "absf(absf(spawn_axis.z) - 1.0) < 0.05 and absf(spawn_axis.x) < 0.05,\n"
    + T + T + T + "\"队列沿**南北**排开（axis=%s）\" % str(spawn_axis),\n"
    + T + T + ")\n"
    + T + T + "# 交错：相邻两只沿垂直方向错开，不是一条笔直的队（实机观感「太整齐」的反向对照）\n"
    + T + T + "var stagger_vec: Vector3 = call.get(\"stagger\", Vector3.ZERO)\n"
    + T + T + "_check(\n"
    + T + T + T + "stagger_vec.length() > 0.1 and absf(stagger_vec.dot(spawn_axis)) < 0.05,\n"
    + T + T + T + "\"相邻两只交错错开且垂直于排列轴（stagger=%s）\" % str(stagger_vec),\n"
    + T + T + ")\n"
)
t = t[:s] + NEW + t[e:]
save(TEST, t)
print("FIX2_DONE")
