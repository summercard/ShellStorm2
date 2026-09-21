## 行尾归一：只把"孤立 LF"补成 CRLF，绝不重复转换（防 CRCRLF / Stray carriage return）。
import pathlib

FILES = [
    r"I:\工作项目\shellstrom2\ShellStorm2\src\vfx\VfxEffectBase3D.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\src\vfx\VfxMuzzleFlash3D.gd",
    r"I:\工作项目\shellstrom2\ShellStorm2\src\combat3d\WeaponModel3D.gd",
]

for raw in FILES:
    p = pathlib.Path(raw)
    data = p.read_bytes()
    lone = data.count(b"\n") - data.count(b"\r\n")
    crcrlf = data.count(b"\r\r\n")
    print("%-28s loneLF=%d CRCRLF=%d" % (p.name, lone, crcrlf))
    if crcrlf > 0:
        print("  !! CRCRLF present, refuse to touch")
        continue
    if lone > 0:
        fixed = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        p.write_bytes(fixed)
        print("  -> normalized: loneLF=%d CRCRLF=%d bytes=%d"
              % (fixed.count(b"\n") - fixed.count(b"\r\n"), fixed.count(b"\r\r\n"), len(fixed)))
