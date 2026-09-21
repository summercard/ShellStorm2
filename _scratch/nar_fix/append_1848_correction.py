# -*- coding: utf-8 -*-
"""给 1848 事务追加"修正"小节（C5 改走真实信号 + RC 红名单更新）。CRLF 保留。"""
import os

P = r"I:\工作项目\shellstrom2\.workbuddy\memory\2026-09-21\1848_复位存档后开场剧本不播_本局态归零.md"

ADD = """

## 修正（同会话复跑）
- **C5 的复位改为走真实信号**：`BaseManager.game_save_reset_completed.emit({"success": true})`。
  原先直接调 `NarrativeDirector.reset_run_state()`，**绕过了 `_on_game_save_reset_completed` handler**
  ⇒ 那一环没有覆盖。改后不写 `user://`，只验「信号 → 归零 → 能重触发」这条链，handler 也在其中。
- 因此**断订阅**那组反向对照的红名单更新为**恰好 3 条**：接线断言 + C5
  「复位存档后开场剧本重新触发（实际 `active=`）」+「重触发那次仍按 `flow.end` 正常收口（`[]`）」。
- 验收项数仍为 **91**（改的是实现路径，不是条数）。
"""

raw = open(P, "rb").read()
assert raw.count(b"\r\n") == raw.count(b"\n"), "行尾不纯"
text = raw.decode("utf-8").replace("\r\n", "\n")
if "## 修正（同会话复跑）" in text:
    print("已存在，跳过")
else:
    text = text.rstrip("\n") + "\n" + ADD
    data = text.replace("\n", "\r\n").encode("utf-8")
    assert data.count(b"\r") == data.count(b"\n")
    open(P, "wb").write(data)
    print("appended CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
