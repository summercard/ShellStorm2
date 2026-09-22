# -*- coding: utf-8 -*-
"""RC9 反向对照：把弹壳寿命退回上一版 4.7（即撤销本轮缩短），验证新断言确实会变红。

用法：python rc9_shorten.py break | restore
"""
import sys

PATH = r"I:\工作项目\shellstrom2\ShellStorm2\src\vfx\VfxShellCasing3D.gd"
LIVE = "const DEFAULT_LIFETIME := 3.7"
BROKEN = "const DEFAULT_LIFETIME := 4.7"

mode = sys.argv[1] if len(sys.argv) > 1 else "break"
old, new = (LIVE, BROKEN) if mode == "break" else (BROKEN, LIVE)

data = open(PATH, "rb").read()
o = (old + "\r\n").encode("utf-8")
n = (new + "\r\n").encode("utf-8")
found = data.count(o)
if found != 1:
    print("FAIL 命中 %d 处（期望 1）：%s" % (found, old))
    sys.exit(1)
open(PATH, "wb").write(data.replace(o, n))
chk = open(PATH, "rb").read()
print("%s -> %s  crcrlf=%d lone_lf=%d"
      % (old, new, chk.count(b"\r\r\n"), chk.count(b"\n") - chk.count(b"\r\n")))
