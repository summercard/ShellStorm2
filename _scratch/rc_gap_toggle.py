"""反向对照开关：把「立面环让位」临时打开/关闭，用于证明 verify_stair_entry_clearance 不是假绿。

用法：
    python rc_gap_toggle.py off   # 关掉让位（回到修复前行为）→ 测试应变红
    python rc_gap_toggle.py on    # 还原让位 → 测试应变绿
"""
import sys

PATH = "src/world3d/TowerFloorStage3D.gd"

GUARDED = b"\tif side not in facade_gap_sides:"
BROKEN = b"\tif true or side not in facade_gap_sides:"

mode = sys.argv[1] if len(sys.argv) > 1 else ""
data = open(PATH, "rb").read()

if mode == "off":
    n = data.count(GUARDED)
    assert n == 1, "expected exactly 1 guarded anchor, found %d" % n
    data = data.replace(GUARDED, BROKEN, 1)
elif mode == "on":
    n = data.count(BROKEN)
    assert n == 1, "expected exactly 1 broken anchor, found %d" % n
    data = data.replace(BROKEN, GUARDED, 1)
else:
    raise SystemExit("usage: rc_gap_toggle.py off|on")

open(PATH, "wb").write(data)
print("gap toggle ->", mode, "| bytes", len(data))
