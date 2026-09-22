# -*- coding: utf-8 -*-
"""修 98F 门钥匙：门策略优先读房间按方向声明的 door_policies（和平区靠它全放行）。"""
import os

ROOT = r"I:\工作项目\shellstrom2\ShellStorm2"
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


# ---------------- Dungeon3D ----------------
D_OLD = (
    T + "var edge := _edge_key(_current_room_id, target_room_id)\n"
    + T + "var policy := _door_policy_for_edge(_current_room_id, target_room_id)\n"
)
D_NEW = (
    T + "var edge := _edge_key(_current_room_id, target_room_id)\n"
    + T + "# 门策略优先读**房间按方向声明的** `door_policies` —— 和平区（区块00）就是靠它把\n"
    + T + "# 「清房 / 钥匙 / 命运卡」三项全部关掉的。只有房间没声明该方向时才回落到默认策略。\n"
    + T + "# ⛔ 老实现直接调 `_door_policy_for_edge()`（硬编码三项全 true），于是和平区那句\n"
    + T + "# 「门只做普通开关」是**空承诺**：98F 每扇门都要清房 + 消耗房间钥匙（2026-09-22 人报）。\n"
    + T + "var policy := _door_policy_towards(_current_room_id, target_room_id)\n"
)
D_FN = (
    "## 取「从 `room_id` 走向 `target_room_id` 这扇门」的策略：**优先房间声明的那份**，\n"
    "## 缺失才回落到 `_door_policy_for_edge()`。`door_policies` 是按**门方向**存的，\n"
    "## 所以这里先用 `door_targets` 把目标房反查回方向。\n"
    "func _door_policy_towards(room_id: String, target_room_id: String) -> Dictionary:\n"
    + T + "var room := _room_by_id.get(room_id) as DungeonRoom3D\n"
    + T + "if room != null:\n"
    + T + T + "var declared: Dictionary = room.door_policies\n"
    + T + T + "var targets: Dictionary = room.door_targets\n"
    + T + T + "for direction in targets.keys():\n"
    + T + T + T + "if str(targets[direction]) != target_room_id:\n"
    + T + T + T + T + "continue\n"
    + T + T + T + "if declared.has(direction):\n"
    + T + T + T + T + "return declared[direction]\n"
    + T + "return _door_policy_for_edge(room_id, target_room_id)\n"
    "\n"
    "\n"
    "func _try_open_room_door(target_room_id: String) -> bool:\n"
)
patch(D3, [
    ("policy-lookup", D_OLD, D_NEW),
    ("policy-fn", "func _try_open_room_door(target_room_id: String) -> bool:\n", D_FN),
])

# ---------------- 真机验收：加 F 段（门策略全放行） ----------------
C_OLD = "const ZOMBIES_ROOM_ID := \"floor_01_main_02\"\n"
C_NEW = (
    C_OLD
    + "## 98F 区块00 四房（和平区）：门策略必须三项全放行，否则每扇门都要清房+钥匙。\n"
    + "const BLOCK00_ROOM_IDS: Array[String] = [\n"
    + "\t\"floor_01_entry\", \"floor_01_hub\", \"floor_01_main_02\", \"floor_01_exit\",\n"
    + "]\n"
)
R_OLD = T + "_phase_e_zombie_trigger_geometry()\n" + T + "_report()\n"
R_NEW = (
    T + "_phase_e_zombie_trigger_geometry()\n"
    + T + "_phase_f_block00_door_policies()\n"
    + T + "_report()\n"
)
F_FN = (
    "## 98F 区块00 是**和平区**：门只做普通开关（不清房 / 不要钥匙 / 不弹命运卡）。\n"
    "## 这里在真机上验门策略真的全放行了 —— 老实现门开启走的是硬编码默认策略，\n"
    "## 那句「门只做普通开关」是空承诺（人报「98 层每个房间都有钥匙」）。\n"
    "func _phase_f_block00_door_policies() -> void:\n"
    + T + "var rooms: Variant = _tower.get(\"_room_by_id\")\n"
    + T + "if not (rooms is Dictionary):\n"
    + T + T + "_check(false, \"拿不到塔楼房间表（门策略校验无法进行）\")\n"
    + T + T + "return\n"
    + T + "var checked := 0\n"
    + T + "var leaked := 0\n"
    + T + "for room_id in BLOCK00_ROOM_IDS:\n"
    + T + T + "var room := (rooms as Dictionary).get(room_id) as DungeonRoom3D\n"
    + T + T + "if room == null:\n"
    + T + T + T + "continue\n"
    + T + T + "checked += 1\n"
    + T + T + "_check(\n"
    + T + T + T + "room.authored_layout_peaceful,\n"
    + T + T + T + "\"%s 带和平区标记（否则门策略会退回默认）\" % room_id,\n"
    + T + T + ")\n"
    + T + T + "var policies: Dictionary = room.door_policies\n"
    + T + T + "for direction in policies.keys():\n"
    + T + T + T + "var policy: Dictionary = policies[direction]\n"
    + T + T + T + "if (\n"
    + T + T + T + T + "bool(policy.get(\"requires_clear\", true))\n"
    + T + T + T + T + "or bool(policy.get(\"requires_key\", true))\n"
    + T + T + T + T + "or bool(policy.get(\"triggers_fate\", true))\n"
    + T + T + T + "):\n"
    + T + T + T + T + "leaked += 1\n"
    + T + T + "_check(\n"
    + T + T + T + "leaked == 0,\n"
    + T + T + T + "\"%s 门策略全放行（实际有 %d 个方向仍要清房/钥匙/命运卡）\" % [room_id, leaked],\n"
    + T + T + ")\n"
    + T + "_check(checked == BLOCK00_ROOM_IDS.size(), \"四房全部在本层（实际 %d）\" % checked)\n"
    + T + "# 关键：门**开启路径**读到的策略必须也是放行的（老 bug 就出在这一跳）。\n"
    + T + "for room_id in BLOCK00_ROOM_IDS:\n"
    + T + T + "var room := (rooms as Dictionary).get(room_id) as DungeonRoom3D\n"
    + T + T + "if room == null:\n"
    + T + T + T + "continue\n"
    + T + T + "for direction in room.door_targets.keys():\n"
    + T + T + T + "var neighbour := str(room.door_targets[direction])\n"
    + T + T + T + "if neighbour.is_empty():\n"
    + T + T + T + T + "continue\n"
    + T + T + T + "var policy: Dictionary = _tower.call(\"_door_policy_towards\", room_id, neighbour)\n"
    + T + T + T + "_check(\n"
    + T + T + T + T + "not bool(policy.get(\"requires_clear\", true))\n"
    + T + T + T + T + "and not bool(policy.get(\"requires_key\", true))\n"
    + T + T + T + T + "and not bool(policy.get(\"triggers_fate\", true)),\n"
    + T + T + T + T + "\"%s → %s 的开门策略放行（老 bug：这一跳读的是硬编码默认）\"\n"
    + T + T + T + T + "% [room_id, neighbour],\n"
    + T + T + T + ")\n"
    + "\n"
    + "\n"
    + "func _report() -> void:\n"
)
patch(OPENING, [
    ("consts", C_OLD, C_NEW),
    ("ready-call", R_OLD, R_NEW),
    ("phase-f", "func _report() -> void:\n", F_FN),
])

print("TASK9_DONE")
