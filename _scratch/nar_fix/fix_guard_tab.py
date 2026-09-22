# -*- coding: utf-8 -*-
"""把源码守卫的目标行补上缩进 tab（`if not test_mode:` 在 func 体内 ⇒ 前置 1 个 tab）。"""

import sys

P = r"I:\工作项目\shellstrom2\ShellStorm2\tests\verification\verify_opening_script_runtime.gd"

OLD = 'd3_source.contains("if not test_mode:'
NEW = 'd3_source.contains("\\tif not test_mode:'


def main() -> int:
    raw = open(P, "rb").read()
    if raw.count(b"\r\n") != raw.count(b"\n"):
        print("REFUSE: 行尾不纯")
        return 2
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if NEW in text:
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
