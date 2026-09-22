# -*- coding: utf-8 -*-
"""剧情时间轴验收适配开场改动：
① 台词从 1 句变 2 句（「人呢」+「那是主人留下的礼物。。」）；
② 假世界补一个「办公室」FakeRoom —— 剧本 01 新增的 `actor.face` 用房间相对目标点，
   假世界里没有这个房就会降级成 yaw_deg（不报错但也没验到真东西）。
"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_narrative_timeline.gd"

BARK_OLD = '\t_check(_bark.lines == ["人呢"], "台词是『人呢』（实际 %s）" % str(_bark.lines))\n'
BARK_NEW = (
    "\t# 2026-09-22 主人要求：起身后补一段「对着地上的枪说」——台词因此从 1 句变 2 句。\n"
    '\t_check(\n'
    '\t\t_bark.lines == ["人呢", "那是主人留下的礼物。。"],\n'
    '\t\t"台词是『人呢』+『那是主人留下的礼物。。』（实际 %s）" % str(_bark.lines),\n'
    '\t)\n'
)

ROOM_OLD = (
    "\t_probe_room.global_position = PROBE_ROOM_CENTER\n"
)
ROOM_NEW = (
    "\t_probe_room.global_position = PROBE_ROOM_CENTER\n"
    "\t# 开场房（办公室）：剧本 01 尾段用 `actor.face` 的目标点（房间相对）指地上的枪，\n"
    "\t# 假世界里没有这个房就会降级成 yaw_deg —— 不报错，但也没验到那条真路径。\n"
    "\t_opening_room = FakeRoom.new()\n"
    "\t_opening_room.name = \"OpeningRoom\"\n"
    "\t_opening_room.room_id = OPENING_ROOM_ID\n"
    "\tadd_child(_opening_room)\n"
)

VAR_OLD = "var _probe_room: FakeRoom = null\n"
VAR_NEW = "var _probe_room: FakeRoom = null\nvar _opening_room: FakeRoom = null\n"


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    changed = False
    for old, new, label in (
        (BARK_OLD, BARK_NEW, "bark"),
        (VAR_OLD, VAR_NEW, "var"),
        (ROOM_OLD, ROOM_NEW, "room"),
    ):
        if new in text:
            print("%s: already" % label)
            continue
        n = text.count(old)
        if n != 1:
            print("ABORT %s: 锚点命中 %d" % (label, n))
            return 3
        text = text.replace(old, new)
        changed = True

    if not changed:
        print("NO CHANGE")
        return 0
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
