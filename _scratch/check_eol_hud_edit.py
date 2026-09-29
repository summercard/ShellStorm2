"""检查改动文件的行尾纯度（本机 grep 判行尾不可靠，按字节数）。只读分析。"""
import os

BASE = r"I:/工作项目/shellstrom2/ShellStorm2"
FILES = [
    "src/world3d/Dungeon3D.gd",
    "src/world3d/TowerDescent3D.gd",
]

for rel in FILES:
    p = os.path.join(BASE, rel.replace("/", os.sep))
    with open(p, "rb") as f:
        b = f.read()
    crlf = b.count(b"\r\n")
    lone_lf = b.count(b"\n") - crlf
    lone_cr = b.count(b"\r") - crlf
    print("%-32s bytes=%8d  CRLF=%6d  lone_LF=%5d  lone_CR=%d"
          % (rel, len(b), crlf, lone_lf, lone_cr))
