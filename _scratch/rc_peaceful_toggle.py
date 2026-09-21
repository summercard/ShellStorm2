"""反向对照开关：把 Block00MasterOfficeLayout3D.PEACEFUL_ZONE 打开/关闭。

用法： python rc_peaceful_toggle.py off | on
不落 res:// 内的快照（脚本快照纪律），原件备份到 _scratch/。
"""
import sys

TARGET = "src/world3d/Block00MasterOfficeLayout3D.gd"
ON_LINE = b"const PEACEFUL_ZONE := true"
OFF_LINE = b"const PEACEFUL_ZONE := false"

mode = sys.argv[1] if len(sys.argv) > 1 else ""
data = open(TARGET, "rb").read()

if mode == "off":
    if b"\r\n" not in data:
        raise SystemExit("行尾不是 CRLF，拒绝改写")
    if data.count(ON_LINE) != 1:
        raise SystemExit("锚点 PEACEFUL_ZONE := true 不唯一/缺失：%d" % data.count(ON_LINE))
    open("_scratch/Block00_orig.gd", "wb").write(data)
    open(TARGET, "wb").write(data.replace(ON_LINE, b"const PEACEFUL_ZONE := false"))
    print("PEACEFUL_ZONE -> false")
elif mode == "on":
    if data.count(OFF_LINE) != 1:
        raise SystemExit("锚点 PEACEFUL_ZONE := false 不唯一/缺失")
    open(TARGET, "wb").write(data.replace(OFF_LINE, ON_LINE))
    print("PEACEFUL_ZONE -> true")
else:
    raise SystemExit("用法: rc_peaceful_toggle.py off|on")
