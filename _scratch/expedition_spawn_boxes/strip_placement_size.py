"""归一 floor_00.json 的放置层尺寸：删掉与盒子资产默认逐值相同的内联 `size_m` 覆盖。

- 只动**放置层**内联形如 `, "size_m": [5.0, 5.0]` 的键（单行）；
- 房级 `size_m`（多行、顶格 6 空格）是房间尺寸蓝图，**保留不动**；
- 保留 CRLF；改完复验 JSON 合法、盒数不变、无残留覆盖。
"""

import json
import re
import sys

PATH = "source/art/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json"

with open(PATH, "rb") as fh:
    raw = fh.read()
crlf_before = raw.count(b"\r\n")
lone_before = raw.count(b"\n") - crlf_before
stray_before = raw.count(b"\r") - crlf_before
text = raw.decode("utf-8")

# 放置层内联覆盖：前导 ", " + "size_m": [x, y]，且 x/y 同一行内闭合。
pat = re.compile(r', "size_m": \[[0-9]+(?:\.[0-9]+)?, [0-9]+(?:\.[0-9]+)?\]')
text_new, n = pat.subn("", text)
print("inline size_m overrides removed =", n)

# 前后 JSON 结构核验
before = json.loads(text)
after = json.loads(text_new)


def _walk(doc):
    placements = 0
    inline = 0
    room_level = 0
    for room in doc["rooms"]:
        if "size_m" in room and isinstance(room["size_m"], list):
            room_level += 1
        for pl in room.get("spawn_placements", []) or []:
            placements += 1
            if "size_m" in pl:
                inline += 1
    return placements, inline, room_level


pb, ib, rb = _walk(before)
pa, ia, ra = _walk(after)
print("before: rooms_with_size_m=%d placements=%d inline_overrides=%d" % (rb, pb, ib))
print("after : rooms_with_size_m=%d placements=%d inline_overrides=%d" % (ra, pa, ia))

assert n == ib == 39, "删掉条数应与原内联覆盖数一致"
assert ia == 0, "改后不应残留放置层内联 size_m"
assert pa == pb == 39, "盒数必须不变"
assert ra == rb == 13, "房级 size_m 必须原样保留"
# 逐盒 box_id / center_m / rotation_deg 保真
for r0, r1 in zip(before["rooms"], after["rooms"]):
    for p0, p1 in zip(r0.get("spawn_placements", []) or [], r1.get("spawn_placements", []) or []):
        assert p0.get("box") == p1.get("box")
        assert p0.get("center_m") == p1.get("center_m")
        assert p0.get("rotation_deg") == p1.get("rotation_deg")
print("per-placement box/center_m/rotation_deg preserved OK")

data = text_new.encode("utf-8")
crlf_after = data.count(b"\r\n")
lone_after = data.count(b"\n") - crlf_after
stray_after = data.count(b"\r") - crlf_after
print("CRLF before=%d loneLF=%d strayCR=%d" % (crlf_before, lone_before, stray_before))
print("CRLF after =%d loneLF=%d strayCR=%d" % (crlf_after, lone_after, stray_after))
assert lone_after == 0 and stray_after == 0, "行尾必须保持纯 CRLF"

with open(PATH, "wb") as fh:
    fh.write(data)
print("WROTE", PATH)
