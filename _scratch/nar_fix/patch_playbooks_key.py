# -*- coding: utf-8 -*-
"""playbooks「开局 · 98F」节补一条：钥匙产出闸口必须自检。"""

import sys

P = r"I:\工作项目\shellstrom2\.workbuddy\memory\MEMORY-playbooks.md"

ANCHOR = "- \u5b88\u536b\uff1a\u771f\u673a\u9a8c\u6536\u91cc F \u6bb5\u5e26**\u6e90\u7801\u7ea7\u5b88\u536b**"

ADD = """- ⛔ **「和平区不发钥匙」必须写在产出闸口里自证，不能靠调用方传 `spawn_key=false`**：钥匙的**唯一**产出闸口是
  `Dungeon3D._ensure_room_key_reward()`，而它有三个调用方 —— `_mark_room_cleared(room, spawn_key)`（带语义）、
  `_on_room_entered()` 的**重进已探索房间**分支（`spawn_key` 缺省、**无条件调**）、`_repair_room_progress` 兜底。
  只看 `spawn_key` 的写法必然漏：和平区首次进房走 `_mark_room_cleared(room, false)` 不发钥匙，
  玩家**回头再进同一间**（`cleared == true` 且房型是 COMBAT，不在排除表里）就掉一把，**每间各掉 1 颗**。
  现由 `_room_produces_room_key(room)` 自检：`authored_layout_peaceful` → false；否则该房**任一**方向声明的
  `door_policies[dir].requires_key == true` 才算产出（非和平区逐值不变）。
  判据：真机 H 段「重进后地上 0 颗」+ 全层计数 + 源码守卫（闸口函数体必须含 `_room_produces_room_key(`）。
  反向对照：摘掉那一行 → 四房各 1 颗、全层 4 颗，`failures=6`。
- **`door_policies` 一路双落**：策略既进 `RoomDoor3D.set_access_policy()`（`_refresh_prompt()` 据 `requires_key`
  渲门口提示语），又供开门路径读。所以「策略对但提示语假」不会发生——但门**节点**是否真拿到策略要单独断言
  （真机 F 段已加：四房各门 `not door.requires_key` + 提示语不含「钥匙」，实测 `[E] 开启通道`）。

"""


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")

    if "_room_produces_room_key" in text:
        print("ALREADY PATCHED")
        return 0

    n = text.count(ANCHOR)
    if n != 1:
        print("ABORT: 锚点命中 %d 次" % n)
        return 3
    text = text.replace(ANCHOR, ADD + ANCHOR)

    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
