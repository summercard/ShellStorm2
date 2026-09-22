# -*- coding: utf-8 -*-
"""H 段补一条：和平区的 HUD 目标文案不许提钥匙。"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_opening_script_runtime.gd"

ANCHOR = (
    '\tvar total := get_tree().get_nodes_in_group("room_key_pickup_3d").size()\n'
    '\t_note("H \u672c\u5c42\u5730\u4e0a\u7684\u623f\u95f4\u94a5\u5319\u603b\u6570 = %d" % total)\n'
    '\t_check(total == 0, "98F \u5168\u5c42\u5730\u4e0a\u6ca1\u6709\u623f\u95f4\u94a5\u5319\uff08\u5b9e\u9645 %d \u9897\uff09" % total)\n'
)

ADD = '''
\t# HUD 目标文案（主人截图里那行「用钥匙开门选择路线」）靠的是同一声明：
\t# 只看「我有没有钥匙」、不看「这扇门要不要钥匙」就会写出假提示。
\tvar saved_room_id := str(_tower.get("_current_room_id"))
\t_tower.set("_current_room_id", OPENING_ROOM_ID)
\tvar objective := str(_tower.call("_journey_objective", 98))
\t_tower.set("_current_room_id", saved_room_id)
\t_check(
\t\tnot objective.contains("钥匙"),
\t\t"和平区的 HUD 目标文案不提钥匙（实际「%s」）" % objective,
\t)
\t_note("H 和平区 HUD 目标文案 = %s" % objective)
'''


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    if "HUD 目标文案不提钥匙" in text:
        print("ALREADY PATCHED")
        return 0

    n = text.count(ANCHOR)
    if n != 1:
        print("ABORT: 锚点命中 %d 次" % n)
        return 3
    text = text.replace(ANCHOR, ANCHOR + ADD)

    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
