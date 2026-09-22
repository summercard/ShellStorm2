# -*- coding: utf-8 -*-
"""F 段追加：门**节点**上也要落下和平区策略（门口提示语就是它渲的）。"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_opening_script_runtime.gd"

ANCHOR = (
    '\t\t\t\t"%s \u2192 %s \u7684\u5f00\u95e8\u7b56\u7565\u653e\u884c\uff08\u8001 bug\uff1a\u8fd9\u4e00\u8df3\u8bfb\u7684\u662f\u786c\u7f16\u7801\u9ed8\u8ba4\uff09"\n'
    "\t\t\t\t% [room_id, neighbour],\n"
    "\t\t\t)\n"
)

ADD = '''
\t# 门**节点**上也必须落下放行策略 —— 门口那句提示语就是它渲的：
\t# `requires_key` 为真时显示「[E] 使用房间钥匙」，等于给玩家一个假提示。
\tfor room_id in BLOCK00_ROOM_IDS:
\t\tvar room := (rooms as Dictionary).get(room_id) as DungeonRoom3D
\t\tif room == null:
\t\t\tcontinue
\t\tvar doors := 0
\t\tfor direction in room.door_targets.keys():
\t\t\tvar door := room.get_door_node(str(direction))
\t\t\tif door == null:
\t\t\t\tcontinue
\t\t\tdoors += 1
\t\t\t_check(
\t\t\t\tnot door.requires_key,
\t\t\t\t"%s 的 %s 门节点不要求钥匙（否则门口会写「使用房间钥匙」）"
\t\t\t\t% [room_id, str(direction)],
\t\t\t)
\t\t\t_check(
\t\t\t\tnot door.get_interaction_prompt_text().contains("钥匙"),
\t\t\t\t"%s 的 %s 门提示语不提钥匙（实际「%s」）"
\t\t\t\t% [room_id, str(direction), door.get_interaction_prompt_text()],
\t\t\t)
\t\t_check(doors > 0, "%s 至少有一扇门节点参与策略校验（实际 %d）" % [room_id, doors])
'''


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    if "门节点不要求钥匙" in text:
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
