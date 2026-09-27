"""几何自检：直接从 spawn_map.json 用 PIL 画一张总览 PNG，用于肉眼核对轮廓/落点。"""
import json
import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "spawn_map.json")
OUT = os.path.join(HERE, "preview_overview.png")

ROOM_COLOR = {
    "STAIR_LOBBY": (46, 160, 67),
    "COMBAT": (224, 82, 82),
    "SCAVENGE": (210, 153, 34),
    "STORAGE": (79, 140, 201),
    "EVENT": (163, 113, 247),
    "BOSS": (194, 65, 12),
    "EXTRACTION": (57, 197, 207),
}

with open(DATA, encoding="utf-8") as fh:
    seed = json.load(fh)["seeds"][0]

S = 5.0
pts = [c for r in seed["rooms"] for c in r["tile_cells_world"]]
for r in seed["rooms"]:
    if not r["tile_cells_world"]:
        dx, dz = r["dimensions"]
        for sx in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                pts.append([r["origin"][0] + dx * sx, r["origin"][1] + dz * sz])
minx = min(p[0] for p in pts) - 8
maxx = max(p[0] for p in pts) + 8
minz = min(p[1] for p in pts) - 8
maxz = max(p[1] for p in pts) + 8
W = int((maxx - minx) * S)
H = int((maxz - minz) * S)

img = Image.new("RGB", (W, H), (11, 15, 20))
dr = ImageDraw.Draw(img)
for r in seed["rooms"]:
    col = ROOM_COLOR.get(r["room_type"], (136, 136, 136))
    for cx, cz in r["tile_cells_world"]:
        x0 = (cx - 2.5 - minx) * S
        y0 = (cz - 2.5 - minz) * S
        dr.rectangle([x0, y0, x0 + 5 * S, y0 + 5 * S], fill=tuple(int(v * 0.35) for v in col),
                     outline=col)
    if not r["tile_cells_world"]:
        dx, dz = r["dimensions"]
        x0 = (r["origin"][0] - dx / 2 - minx) * S
        y0 = (r["origin"][1] - dz / 2 - minz) * S
        dr.rectangle([x0, y0, x0 + dx * S, y0 + dz * S], fill=tuple(int(v * 0.35) for v in col),
                     outline=col)
    used = max([len(w) for w in r["rolled_waves"]] or [0])
    for p in r["spawn_points"][: used or 1]:
        x = (p["world"][0] - minx) * S
        y = (p["world"][1] - minz) * S
        dr.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(255, 92, 92), outline=(11, 15, 20))
    lx = (r["origin"][0] - minx) * S
    ly = (r["origin"][1] - minz) * S
    dr.text((lx - 14, ly - 6), r["room_id"], fill=(230, 237, 243))

by_id = {r["room_id"]: r for r in seed["rooms"]}
for r in seed["rooms"]:
    for d in r["doors"]:
        oth = by_id.get(d["target"])
        if oth is None:
            continue
        pts_line = [
            ((r["origin"][0] - minx) * S, (r["origin"][1] - minz) * S),
            ((r["origin"][0] + d["local"][0] - minx) * S, (r["origin"][1] + d["local"][1] - minz) * S),
            ((oth["origin"][0] - minx) * S, (oth["origin"][1] - minz) * S),
        ]
        dr.line(pts_line, fill=(180, 150, 60), width=2)
img.save(OUT)
print("wrote", OUT, img.size)
