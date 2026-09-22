# -*- coding: utf-8 -*-
"""98F 和平区不再产出「房间钥匙」奖励。

根因：`_ensure_room_key_reward()` 自己不判断「本房的门要不要钥匙」，
只信调用方给的 `spawn_key` 形参。而 `_on_room_entered()` 的**重进已探索房间**
分支（L1956）是**无条件**调它的 —— 于是和平区首次进房虽然走了
`_mark_room_cleared(room, false)`（不发钥匙），玩家回头再进同一间，
`cleared == true` 且 room_type 是 COMBAT（不在排除表里）⇒ 地上掉一把钥匙。
"""
import io
import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\src\world3d\Dungeon3D.gd"

HELPER = '''## 本房该不该产出「房间钥匙」奖励。
## 钥匙的唯一用途是开下一扇门；若本房所有门都不消耗钥匙（和平区如 98F 区块00），
## 钥匙就是永远用不掉的垃圾道具 —— 必须一并不发。
## ⛔ 这里必须**自检**，不能只信调用方的 `spawn_key` 形参：
## `_on_room_entered()` 的「重进已探索房间」分支是无条件调用本函数的，
## 于是玩家回头走一趟刚清过的和平区，地上就会掉出一把钥匙（2026-09-22 人报截图）。
func _room_produces_room_key(room: DungeonRoom3D) -> bool:
\tif room == null:
\t\treturn false
\tif room.authored_layout_peaceful:
\t\treturn false
\tvar declared: Dictionary = room.door_policies
\tfor direction in declared.keys():
\t\tif bool((declared[direction] as Dictionary).get("requires_key", true)):
\t\t\treturn true
\treturn declared.is_empty()


'''

ANCHOR = 'func _ensure_room_key_reward(room: DungeonRoom3D) -> void:\n'
GUARD_OLD = '\t\tor not room.cleared\n'
GUARD_NEW = '\t\tor not room.cleared\n\t\tor not _room_produces_room_key(room)\n'


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯 CR=%d LF=%d" % (raw.count(b"\r"), raw.count(b"\n")))
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    if "_room_produces_room_key" in text:
        print("ALREADY PATCHED")
        return 0

    n_anchor = text.count(ANCHOR)
    if n_anchor != 1:
        print("ABORT: 函数锚点命中 %d 次" % n_anchor)
        return 3

    # 守卫只改 _ensure_room_key_reward 里那一段：先按函数边界切片，避免误伤别处的同样行。
    start = text.index(ANCHOR)
    end = text.index("\nfunc ", start + 1)
    body = text[start:end]
    n_guard = body.count(GUARD_OLD)
    if n_guard != 1:
        print("ABORT: 守卫锚点命中 %d 次" % n_guard)
        return 4

    body_new = body.replace(GUARD_OLD, GUARD_NEW)
    text = text[:start] + HELPER + body_new + text[end:]

    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 写回前行尾异常")
        return 5
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
