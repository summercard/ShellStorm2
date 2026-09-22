# -*- coding: utf-8 -*-
"""【临时诊断】在真机探针的 G 段打印办公室东门在房间局部系的位置与房间尺寸。

拿到实测值后本文件对应的那几行会被删掉/改成正式断言（见 patch_*_final）。
"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_opening_script_runtime.gd"
MARK = "\t# [TEMP-DIAG-OFFICE-DOOR] 拿实测值用，定位后删除\n"
BODY = MARK + (
    "\tvar _diag_room := (rooms as Dictionary).get(OPENING_ROOM_ID) as DungeonRoom3D\n"
    "\tif _diag_room != null:\n"
    "\t\t_note(\"DIAG 办公室局部尺寸 = %s\" % str(_diag_room.get_dimensions()))\n"
    "\t\t_note(\"DIAG 办公室门向 = %s\" % str(_diag_room.door_targets))\n"
    "\t\tfor _diag_dir in _diag_room.door_targets.keys():\n"
    "\t\t\tvar _diag_door := _diag_room.get_door_node(str(_diag_dir))\n"
    "\t\t\tif _diag_door == null:\n"
    "\t\t\t\t_note(\"DIAG 门 %s = 无节点\" % str(_diag_dir))\n"
    "\t\t\t\tcontinue\n"
    "\t\t\tvar _dl := _diag_room.to_local(_diag_door.global_position)\n"
    "\t\t\t_note(\n"
    "\t\t\t\t\"DIAG 门 %s 局部 = (%.3f, %.3f, %.3f)\"\n"
    "\t\t\t\t% [str(_diag_dir), _dl.x, _dl.y, _dl.z]\n"
    "\t\t\t)\n"
    "\t\t_note(\"DIAG 玩家出生 world = %s\" % str(_player.global_position))\n"
)

ANCHOR = "\tvar meeting := (rooms as Dictionary).get(ZOMBIES_ROOM_ID) as DungeonRoom3D\n"


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if "[TEMP-DIAG-OFFICE-DOOR]" in text:
        print("ALREADY PATCHED")
        return 0
    n = text.count(ANCHOR)
    if n != 1:
        print("ABORT: 锚点命中 %d" % n)
        return 3
    text = text.replace(ANCHOR, BODY + ANCHOR)
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
