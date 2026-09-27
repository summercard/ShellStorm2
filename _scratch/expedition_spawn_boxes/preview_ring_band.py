"""按业主截图的口径出对照图：每个房一个面板，画
  · 房间 5m 地砖（房色淡填 + 网格线）
  · **禁刷带**（最外一圈地砖，红）
  · 旧机制落点（灰） vs 新机制落点（盒内，按怪种着色）
  · 触发盒（青框）
用来肉眼确认「最外一圈没有新机制落点」。
"""
import json
import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = json.load(open(os.path.join(HERE, "spawn_box_map.json"), encoding="utf-8"))
OUT = os.path.join(HERE, "preview_ring_band.png")
TILE = 5.0
S = 7.0  # px per meter

ROOM_RGB = {"STAIR_LOBBY": (46, 160, 67), "COMBAT": (224, 82, 82), "SCAVENGE": (210, 153, 34),
            "STORAGE": (79, 140, 201), "EVENT": (163, 113, 247), "BOSS": (194, 65, 12),
            "EXTRACTION": (57, 197, 207)}
MON_RGB = {"melee_chaser": (248, 81, 73), "ranged_caster": (163, 113, 247), "ambusher": (46, 160, 67),
           "shielded": (79, 140, 201), "exploder": (255, 158, 100), "summoner": (227, 179, 65),
           "boss": (255, 45, 85), "elite": (242, 204, 96)}


def cells_of(room):
    cells = [(c[0], c[1]) for c in room["tile_cells_local"]]
    if cells:
        return cells
    dx, dz = room["dimensions"]
    nx, nz = int(math.ceil(dx / TILE)), int(math.ceil(dz / TILE))
    return [(-dx * 0.5 + TILE * 0.5 + i * TILE, -dz * 0.5 + TILE * 0.5 + j * TILE)
            for i in range(nx) for j in range(nz)]


def inside_fn(cells):
    xs = sorted({round(c[0], 3) for c in cells})
    zs = sorted({round(c[1], 3) for c in cells})
    x0, z0 = xs[0], zs[0]
    cellset = {(int(round((cx - x0) / TILE)), int(round((cz - z0) / TILE))) for cx, cz in cells}

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


def clearance(inside, x, z, cap=60.0):
    best = cap
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        s = 0.0
        while s < cap:
            s += 0.05
            if not inside(x + dx * s, z + dz * s):
                break
        best = min(best, s)
    return best


rooms = [r for r in DATA["rooms"] if r["placements"]]
COLS, PW, PH = 3, 470, 380
ROWS = int(math.ceil(len(rooms) / COLS))
img = Image.new("RGB", (COLS * PW, ROWS * PH), (13, 17, 23))
dr = ImageDraw.Draw(img)

for idx, room in enumerate(rooms):
    ox, oy = (idx % COLS) * PW, (idx // COLS) * PH
    cells = cells_of(room)
    inside = inside_fn(cells)
    dx, dz = room["dimensions"]
    pad = 6
    sc = min((PW - 2 * pad) / (dx + 4.0), (PH - 2 * pad - 22) / (dz + 4.0))
    cx0, cy0 = ox + PW * 0.5, oy + 22 + (PH - 22) * 0.5
    px = lambda x: cx0 + x * sc
    pz = lambda z: cy0 + z * sc
    col = ROOM_RGB.get(room["room_type"], (136, 136, 136))
    band = set()
    for c in cells:
        r = int(clearance(inside, c[0], c[1]) // TILE)
        fill = tuple(int(v * 0.30) for v in col)
        outline = col
        if r == 0:
            band.add((round(c[0], 3), round(c[1], 3)))
            fill = (70, 26, 26)
            outline = (248, 81, 73)
        dr.rectangle([px(c[0] - 2.5), pz(c[1] - 2.5), px(c[0] + 2.5), pz(c[1] + 2.5)],
                     fill=fill, outline=outline, width=1)
    # 旧机制落点（灰）
    for x, z in room["legacy_points"]:
        dr.ellipse([px(x) - 2, pz(z) - 2, px(x) + 2, pz(z) + 2], outline=(150, 160, 170))
    # 触发盒
    for p in room["placements"]:
        if "error" in p:
            continue
        bx, bz = p["center_landed"]
        sx, sz = p["size"]
        dr.rectangle([px(bx - sx / 2), pz(bz - sz / 2), px(bx + sx / 2), pz(bz + sz / 2)],
                     outline=(57, 197, 207), width=2)
    # 新机制落点
    for w in room["waves"]:
        for e in w:
            x, z = e["local"]
            c = MON_RGB.get(e["type"], (255, 255, 255))
            dr.ellipse([px(x) - 3.5, pz(z) - 3.5, px(x) + 3.5, pz(z) + 3.5], fill=c,
                       outline=(11, 15, 20))
    outer = sum(1 for w in room["waves"] for e in w
                if clearance(inside, e["local"][0], e["local"][1]) < TILE)
    leg_outer = sum(1 for x, z in room["legacy_points"] if clearance(inside, x, z) < TILE)
    dr.text((ox + 8, oy + 5), "%s  %s  %.0fx%.0f m" % (room["room_id"], room["room_type"], dx, dz),
            fill=(230, 237, 243))
    dr.text((ox + 8, PH + oy - 14),
            "box=%d  new_pts=%d  new_in_band=%d | legacy=%d  legacy_in_band=%d"
            % (len(room["placements"]), sum(len(w) for w in room["waves"]), outer,
               len(room["legacy_points"]), leg_outer),
            fill=(248, 81, 73) if outer else (63, 185, 80))

img.save(OUT)
print("wrote %s (%dx%d) rooms=%d" % (OUT, img.size[0], img.size[1], len(rooms)))
