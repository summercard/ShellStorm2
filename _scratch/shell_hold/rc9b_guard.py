# -*- coding: utf-8 -*-
"""RC9b：把滚动阻尼调小，让飞行段吃满寿命 —— 验证 ③「停留 ≥ 观感下限」这条守卫真会红
（RC9 只让它绿，那还证明不了它是活的守卫）。

用法：python rc9b_guard.py break | restore
"""
import sys

PATH = r"I:\工作项目\shellstrom2\ShellStorm2\src\vfx\VfxShellCasing3D.gd"
LIVE = "const ROLL_DAMPING := 3.4"
BROKEN = "const ROLL_DAMPING := 0.2"

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
