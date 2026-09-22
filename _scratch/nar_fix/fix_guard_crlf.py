# -*- coding: utf-8 -*-
"""源码守卫必须先归一 CRLF —— 否则跨行 `contains` 永远为假（守卫自己变成永远红）。"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_opening_script_runtime.gd"

OLD = (
    "\t# 源码守卫：这条发放的**唯一**条件必须是「非 test_mode」，不能被「有没有枪」挟持。\n"
    "\tvar d3_source := FileAccess.get_file_as_string(\"res://src/world3d/Dungeon3D.gd\")\n"
)
NEW = (
    "\t# 源码守卫：这条发放的**唯一**条件必须是「非 test_mode」，不能被「有没有枪」挟持。\n"
    "\t# ⚠️ 先把 CRLF 归一：本仓源码是 CRLF，用 `\\n` 搜跨行片段会**永远搜不到** ——\n"
    "\t# 守卫自己就成了「永远红」（2026-09-22 实测踩过这一脚）。\n"
    "\tvar d3_source := FileAccess.get_file_as_string(\n"
    "\t\t\"res://src/world3d/Dungeon3D.gd\"\n"
    "\t).replace(\"\\r\\n\", \"\\n\")\n"
)


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if ".replace(\"\\r\\n\", \"\\n\")" in text and "先把 CRLF 归一" in text:
        print("ALREADY PATCHED")
        return 0
    n = text.count(OLD)
    if n != 1:
        print("ABORT: 锚点命中 %d" % n)
        return 3
    text = text.replace(OLD, NEW)
    data = text.replace("\n", "\r\n").encode("utf-8")
    if data.count(b"\r") != data.count(b"\n") or b"\r\r" in data:
        print("ABORT: 行尾异常")
        return 4
    open(P, "wb").write(data)
    print("OK CR=%d LF=%d" % (data.count(b"\r"), data.count(b"\n")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
