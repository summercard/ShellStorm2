"""几何自检：用 PIL 从 spawn_box_map.json 画总览 PNG，肉眼核对盒位/落点/轮廓。"""
import json
import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "spawn_box_map.json")
OUT = os.path.join(HERE, "preview_box_map.png")

ROOM_RGB = {
    "STAIR_LOBBY": (46, 160, 67), "COMBAT": (224, 82, 82), "SCAVENGE": (210, 153, 34),
    "STORAGE": (79, 140, 201), "EVENT": (163, 113, 247), "BOSS": (194, 65, 12),
    "EXTRACTION": (57, 197, 207),
}
MON_RGB = {
    "melee_chaser": (248, 81, 73), "ranged_caster": (163, 113, 247), "ambusher": (46, 160, 67),
    "shielded": (79, 140, 201), "exploder": (255, 158, 100), "summoner": (227, 179, 65),
    "boss": (255, 45, 85), "elite": (242, 204, 96),
}
S = 5.0
TILE = 5.0

data = json.load(open(DATA, encoding="utf-8"))
rooms = data["rooms"]


def rot(x, z, deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return x * c - z * s, x * s + z * c


def world(room, x, z):
    lx, lz = rot(x, z, room["yaw_deg"])
    return room["origin"][0] + lx, room["origin"][1] + lz


cells_world = {}
pts = []
for room in rooms:
    cl = room["tile_cells_local"] or []
    if not cl:
        dx, dz = room["dimensions"]
        nx, nz = int(math.ceil(dx / TILE)), int(math.ceil(dz / TILE))
        cl = [(-dx * 0.5 + TILE * 0.5 + i * TILE, -dz * 0.5 + TILE * 0.5 + j * TILE)
              for i in range(nx) for j in range(nz)]
    cells_world[room["room_id"]] = [world(room, c[0], c[1]) for c in cl]
    pts.extend(cells_world[room["room_id"]])

minx = min(p[0] for p in pts) - 8
maxx = max(p[0] for p in pts) + 8
minz = min(p[1] for p in pts) - 8
maxz = max(p[1] for p in pts) + 8
W, H = int((maxx - minx) * S), int((maxz - minz) * S)
img = Image.new("RGB", (W, H), (13, 17, 23))
dr = ImageDraw.Draw(img)


def px(x):
    return (x - minx) * S


def pz(z):
    return (z - minz) * S


for room in rooms:
    col = ROOM_RGB.get(room["room_type"], (136, 136, 136))
    for cx, cz in cells_world[room["room_id"]]:
        dr.rectangle([px(cx - 2.5), pz(cz - 2.5), px(cx + 2.5), pz(cz + 2.5)],
                     outline=col, fill=tuple(int(v * 0.28) for v in col))
    ox, oz = room["origin"]
    dr.text((px(ox) - 14, pz(oz) - 6), room["room_id"], fill=(220, 228, 235))
    for placement in room["placements"]:
        if "error" in placement:
            continue
        sx, sz = placement["size"]
        cx, cz = placement["center_landed"]
        wx, wz = world(room, cx, cz)
        corners = []
        for lx, lz in ((-sx / 2, -sz / 2), (sx / 2, -sz / 2), (sx / 2, sz / 2), (-sx / 2, sz / 2)):
            rx, rz = rot(lx, lz, room["yaw_deg"] + placement["rotation_deg"])
            corners.append((px(wx + rx), pz(wz + rz)))
        dr.polygon(corners, outline=(57, 197, 207))
    for wave in room["waves"]:
        for entry in wave:
            ex, ez = entry["world"]
            c = MON_RGB.get(entry["type"], (255, 255, 255))
            dr.ellipse([px(ex) - 3, pz(ez) - 3, px(ex) + 3, pz(ez) + 3], fill=c)
    for lx, lz in room["legacy_points"]:
        wx, wz = world(room, lx, lz)
        dr.ellipse([px(wx) - 2, pz(wz) - 2, px(wx) + 2, pz(wz) + 2], outline=(120, 132, 145))

img.save(OUT)
print("wrote %s (%dx%d)" % (OUT, W, H))
