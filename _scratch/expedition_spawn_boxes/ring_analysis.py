"""落点「第几圈」实测：对每个出怪点算它离地砖并集边界的净距（0.05 m 步进），
除以 5 m 得「圈号」（0 = 最外圈地砖，1 = 往里一圈 …）。

同时打印每盒声明/落地盒心、尺寸，以及**盒矩形**离墙最近距离 —— 用来区分
「点贴外圈」是盒本身压在外圈，还是盒靠里但点被推到盒外沿。
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TILE = 5.0

RAW = sys.argv[1] if len(sys.argv) > 1 else "spawn_box_map.json"
PATH = os.path.join(HERE, RAW)


def cells_of(room):
    return [(c[0], c[1]) for c in room["tile_cells_local"]]


def footprint_test(cells):
    xs = sorted({round(c[0], 3) for c in cells})
    zs = sorted({round(c[1], 3) for c in cells})
    x0, z0 = xs[0], zs[0]
    cellset = set()
    for cx, cz in cells:
        cellset.add((int(round((cx - x0) / TILE)), int(round((cz - z0) / TILE))))

    def inside(x, z):
        fx, fz = (x - x0) / TILE, (z - z0) / TILE
        for ix in (math.floor(fx + 0.5), math.floor(fx), math.ceil(fx)):
            for jz in (math.floor(fz + 0.5), math.floor(fz), math.ceil(fz)):
                if (ix, jz) not in cellset:
                    continue
                if abs(x - (x0 + ix * TILE)) <= TILE * 0.5 + 1e-6 and \
                   abs(z - (z0 + jz * TILE)) <= TILE * 0.5 + 1e-6:
                    return True
        return False

    return inside


def wall_clearance(inside, x, z, cap=40.0):
    best = cap
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        step = 0.0
        while step < cap:
            step += 0.05
            if not inside(x + dx * step, z + dz * step):
                break
        best = min(best, step)
    return best


def main():
    data = json.load(open(PATH, encoding="utf-8"))
    print("seed=%s boxes=%d shifted=%d" % (data["seed"], data["box_total"], data["shifted_total"]))
    ring_hist = {}
    offenders = []
    for room in data["rooms"]:
        cells = cells_of(room)
        if not cells or not room["placements"]:
            continue
        inside = footprint_test(cells)
        xs = [c[0] for c in cells]
        zs = [c[1] for c in cells]
        dx, dz = room["dimensions"]
        print("\n== %-9s %-9s decl=%.0f×%.0f  tiles=%d  tilebbox x[%.1f,%.1f] z[%.1f,%.1f]" %
              (room["room_id"], room["room_type"], dx, dz, len(cells),
               min(xs), max(xs), min(zs), max(zs)))
        for p in room["placements"]:
            if "error" in p:
                print("   #%d ERROR %s" % (p["index"], p.get("box")))
                continue
            sx, sz = p["size"]
            dcx, dcz = p["center_declared"]
            lcx, lcz = p["center_landed"]
            half = (sx * 0.5, sz * 0.5)
            # 盒矩形四边离地砖并集边界的最近距离 = 盒四角/四边中点各自净距（保守取最小）
            probe = [(lcx - half[0], lcz - half[1]), (lcx + half[0], lcz - half[1]),
                     (lcx - half[0], lcz + half[1]), (lcx + half[0], lcz + half[1]),
                     (lcx - half[0], lcz), (lcx + half[0], lcz),
                     (lcx, lcz - half[1]), (lcx, lcz + half[1])]
            box_clr = min(wall_clearance(inside, px_, pz_) for px_, pz_ in probe)
            ctr_clr = wall_clearance(inside, lcx, lcz)
            print("   #%d %-20s %.0f×%.0f decl=(%.1f,%.1f) landed=(%.1f,%.1f) shift=%.2f "
                  "ctr_clr=%.2f(ring=%d) box_clr=%.2f(ring=%d) fits=%s cap=%d/%d pool=%d" %
                  (p["index"], p["box"], sx, sz, dcx, dcz, lcx, lcz, p["shift"],
                   ctr_clr, int(ctr_clr // TILE), box_clr, int(box_clr // TILE),
                   p.get("declared_fits"), p["capacity"], p["demand_max"], p["pool_count"]))
        for wi, wave in enumerate(room["waves"]):
            for e in wave:
                x, z = e["local"]
                clr = wall_clearance(inside, x, z)
                r = int(clr // TILE)
                ring_hist[r] = ring_hist.get(r, 0) + 1
                if r == 0:
                    offenders.append((room["room_id"], wi + 1, e["type"], x, z, clr))
    total = sum(ring_hist.values())
    print("\n---- 新机制·盒内落点 圈号直方图（0 = 最外圈地砖；共 %d 点）----" % total)
    for r in sorted(ring_hist):
        print("  ring %d: %4d (%.1f%%)" % (r, ring_hist[r], 100.0 * ring_hist[r] / total))

    # 旧机制（房间级贪心）落点：同一份探针数据里的 legacy_points
    leg_hist = {}
    leg_min = None
    for room in data["rooms"]:
        cells = cells_of(room)
        if not cells:
            continue
        inside = footprint_test(cells)
        for x, z in room.get("legacy_points", []):
            clr = wall_clearance(inside, x, z)
            r = int(clr // TILE)
            leg_hist[r] = leg_hist.get(r, 0) + 1
            leg_min = clr if leg_min is None else min(leg_min, clr)
    leg_total = sum(leg_hist.values())
    print("\n---- 旧机制·房间级落点 圈号直方图（共 %d 点，最近离墙 %.2f m）----"
          % (leg_total, leg_min if leg_min is not None else -1))
    for r in sorted(leg_hist):
        print("  ring %d: %4d (%.1f%%)" % (r, leg_hist[r], 100.0 * leg_hist[r] / leg_total))

    print("\n---- 新机制落在最外圈（ring 0）的点：%d 个 ----" % len(offenders))
    for o in offenders[:40]:
        print("  %-9s 第%d波 %-14s local=(%.1f,%.1f) clr=%.2f" % o)


if __name__ == "__main__":
    main()
