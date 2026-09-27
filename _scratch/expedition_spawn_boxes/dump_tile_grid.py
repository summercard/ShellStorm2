#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""从探针产物 spawn_box_map.json 生成每房砖格 ASCII 图（内缩标注 + 门位）。

判据与 DungeonRoom3D.snap_box_center_to_tile 一致：
  内缩 want 圈 ⇔ 以该砖心为心、边长 2*(5*want+0.01) 的正方形全被地砖覆盖。
  want=1 即该砖的 3x3 邻域（含对角）全在。
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TILE = 5.0
EPS = 0.01


def key(x, z):
    return (round(x, 1), round(z, 1))


def recess_ok(cells, x, z, want):
    if want <= 0:
        return True
    r = TILE * want + EPS
    # 正方形 [x-r, x+r] x [z-r, z+r] 全被砖覆盖 ⇔ 邻域每块砖的格心都在 cells 里
    n = int(want)
    for ix in range(-n, n + 1):
        for iz in range(-n, n + 1):
            if key(x + TILE * ix, z + TILE * iz) not in cells:
                return False
    return True


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "spawn_box_map.json")
    data = json.load(open(path, encoding="utf-8"))
    print("seed=%s level=%s" % (data["seed"], data["level_id"]))
    for room in data["rooms"]:
        cells_raw = room.get("tile_cells_local") or []
        if not cells_raw:
            print("\n== %s == (无砖：和平房/不可达) dim=%s" % (room["room_id"], room["dimensions"]))
            continue
        cells = set(key(c[0], c[1]) for c in cells_raw)
        xs = sorted(set(k[0] for k in cells))
        zs = sorted(set(k[1] for k in cells))
        doors = set()
        for d in room.get("doors", []):
            doors.add(key(d["local"][0], d["local"][1]))
        print("\n== %s == dim=%s yaw=%s tiles=%d  x:%s..%s  z:%s..%s"
              % (room["room_id"], room["dimensions"], room.get("yaw_deg"),
                 len(cells), xs[0], xs[-1], zs[0], zs[-1]))
        # 表头（列 = x 砖心）
        head = "        " + "".join("%7.1f" % x for x in xs)
        print(head)
        for z in zs:
            row = "%7.1f " % z
            for x in xs:
                if key(x, z) not in cells:
                    ch = "   .   "
                else:
                    marks = ""
                    if recess_ok(cells, x, z, 1):
                        marks += "o"
                    if recess_ok(cells, x, z, 2):
                        marks += "O"
                    if key(x, z) in doors:
                        marks += "D"
                    ch = ("%6s " % (marks if marks else "-"))
                row += ch
            print(row)
        # 可用盒心清单（内缩 1 圈）
        ok1 = [(x, z) for z in zs for x in xs
               if key(x, z) in cells and recess_ok(cells, x, z, 1)]
        ok2 = [(x, z) for z in zs for x in xs
               if key(x, z) in cells and recess_ok(cells, x, z, 2)]
        print("  内缩1圈可选(%d): %s" % (len(ok1), ["(%g,%g)" % p for p in ok1]))
        print("  内缩2圈可选(%d): %s" % (len(ok2), ["(%g,%g)" % p for p in ok2]))


if __name__ == "__main__":
    main()
