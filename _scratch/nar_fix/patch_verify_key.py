# -*- coding: utf-8 -*-
"""给 verify_opening_script_runtime.gd 加 H 段：和平区不产出房间钥匙。"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_opening_script_runtime.gd"

A_READY = "\t_phase_g_opening_room_light()\n\t_report()\n"
B_READY = (
    "\t_phase_g_opening_room_light()\n"
    "\tawait _phase_h_no_room_key_in_peaceful()\n"
    "\t_report()\n"
)

A_REPORT = "func _report() -> void:\n"

PHASE_H = '''## 98F 和平区**不该产出「房间钥匙」**：钥匙的唯一用途是开下一扇门，
## 而和平区四扇门都 `requires_key: false` —— 掉了就是永远用不掉的垃圾道具。
## ⛔ 真凶不是清房那条路（它本来就传 `spawn_key = false`），而是
## `_on_room_entered()` 的「重进已探索房间」分支**无条件**调 `_ensure_room_key_reward()`：
## 玩家回头再走进同一间，`cleared == true` 且 room_type 是 COMBAT（不在排除表里）
## ⇒ 地上掉一把钥匙。这里就按那条路复现（2026-09-22 人报截图）。
func _phase_h_no_room_key_in_peaceful() -> void:
\tvar rooms: Variant = _tower.get("_room_by_id")
\tif not (rooms is Dictionary):
\t\t_check(false, "拿不到塔楼房间表（钥匙闸口校验无法进行）")
\t\treturn
\tvar table := rooms as Dictionary
\tvar probed := 0
\tfor room_id in BLOCK00_ROOM_IDS:
\t\tvar room := table.get(room_id) as DungeonRoom3D
\t\tif room == null:
\t\t\tcontinue
\t\tprobed += 1
\t\t_check(
\t\t\tnot bool(_tower.call("_room_produces_room_key", room)),
\t\t\t"%s 不该产出房间钥匙（和平区门不消耗钥匙）" % room_id,
\t\t)
\t_check(probed == BLOCK00_ROOM_IDS.size(), "四房都参与了钥匙闸口校验（实际 %d）" % probed)

\t# 端到端复现：把每间都推到「已清房」再走那条无条件调用，地上必须**一颗都没有**。
\tfor room_id in BLOCK00_ROOM_IDS:
\t\tvar room := table.get(room_id) as DungeonRoom3D
\t\tif room == null:
\t\t\tcontinue
\t\tif not room.cleared:
\t\t\t# 和平区首次进房的真实清房路径（spawn_key = false）。
\t\t\t_tower.call("_mark_room_cleared", room, false)
\t\t_check(room.cleared, "%s 已进入已清房状态（重进房分支的前提）" % room_id)
\t\t# 这一句就是 `_on_room_entered()` 重进分支里那一句，一字不差。
\t\t_tower.call("_ensure_room_key_reward", room)
\t\t# `_spawn_room_key` 由 `call_deferred` 触发，等两帧再点。
\t\tawait get_tree().process_frame
\t\tawait get_tree().process_frame
\t\tvar keys := _count_room_keys_in(room)
\t\t_check(
\t\t\tkeys == 0,
\t\t\t"%s 重进后地上没有房间钥匙（老 bug：这里会掉一把）实际 %d 颗" % [room_id, keys],
\t\t)

\tvar total := get_tree().get_nodes_in_group("room_key_pickup_3d").size()
\t_note("H 本层地上的房间钥匙总数 = %d" % total)
\t_check(total == 0, "98F 全层地上没有房间钥匙（实际 %d 颗）" % total)

\t# 源码级守卫：闸口必须**自检**（不能只信调用方的 `spawn_key`），否则重进房那条路会绕过去。
\tvar d3_source := FileAccess.get_file_as_string("res://src/world3d/Dungeon3D.gd")
\tvar guard_marker := "func _ensure_room_key_reward(room: DungeonRoom3D) -> void:"
\tvar guard_start := d3_source.find(guard_marker)
\t_check(guard_start >= 0, "Dungeon3D 有 _ensure_room_key_reward（钥匙补发闸口）")
\tif guard_start >= 0:
\t\tvar guard_body := d3_source.substr(guard_start, 900)
\t\t_check(
\t\t\tguard_body.contains("_room_produces_room_key("),
\t\t\t"钥匙补发闸口自检房间门策略（老 bug：只信调用方 spawn_key ⇒ 重进和平区掉钥匙）",
\t\t)


func _count_room_keys_in(room: DungeonRoom3D) -> int:
\tvar count := 0
\tfor value in get_tree().get_nodes_in_group("room_key_pickup_3d"):
\t\tvar node := value as Node
\t\tif node != null and room.is_ancestor_of(node):
\t\t\tcount += 1
\treturn count


'''


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯 CR=%d LF=%d" % (raw.count(b"\r"), raw.count(b"\n")))
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    if "_phase_h_no_room_key_in_peaceful" in text:
        print("ALREADY PATCHED")
        return 0

    if text.count(A_READY) != 1:
        print("ABORT: _ready 锚点命中 %d" % text.count(A_READY))
        return 3
    if text.count(A_REPORT) != 1:
        print("ABORT: _report 锚点命中 %d" % text.count(A_REPORT))
        return 4

    text = text.replace(A_READY, B_READY)
    text = text.replace(A_REPORT, PHASE_H + A_REPORT)

    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 写回前行尾异常")
        return 5
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
