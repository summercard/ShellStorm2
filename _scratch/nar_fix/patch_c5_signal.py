# -*- coding: utf-8 -*-
"""C5 改为走**真实信号**驱动（BaseManager.game_save_reset_completed），把
_on_game_save_reset_completed 这一环也纳入覆盖（原先直接调 reset_run_state，绕过了 handler）。
"""
import os

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_narrative_timeline.gd"

OLD = "\tNarrativeDirector.reset_run_state()\n"
NEW = (
    "\t# 走**真实信号**（暂停菜单复位存档发的就是这一发），顺带覆盖 _on_game_save_reset_completed；\n"
    "\t# 不实际写 user://（本用例只验证「信号 → 归零 → 能重触发」这条链）。\n"
    "\tBaseManager.game_save_reset_completed.emit({\"success\": true})\n"
)

raw = open(P, "rb").read()
assert raw.count(b"\r\n") == raw.count(b"\n"), "行尾不纯"
text = raw.decode("utf-8").replace("\r\n", "\n")
assert text.count(OLD) == 1, "锚点命中 %d" % text.count(OLD)
text = text.replace(OLD, NEW)
data = text.replace("\n", "\r\n").encode("utf-8")
assert data.count(b"\r") == data.count(b"\n")
open(P, "wb").write(data)
print("patched CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
