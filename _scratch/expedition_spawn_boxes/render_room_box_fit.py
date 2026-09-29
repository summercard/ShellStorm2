# -*- coding: utf-8 -*-
"""把 room_box_fit_map.json 渲染成布点预览图（JSON 设计坐标系，可直接抄进 floor_00.json 的 center_m）。
灰块 = 可行走地砖；红框 = 当前 center_m；绿框 = 求解器推荐 center_m；虚线蓝 = 房间内边界。
图下方表格给出每个盒子的编号、容量、推荐坐标与位移量。
"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "room_box_fit_map.json")
OUT = os.path.join(HERE, "room_box_fit_preview.png")

TILE = 5.0
PX_PER_M = 13
PAD = 40

CUR = (214, 48, 49)
REC = (26, 145, 84)
TILE_FILL = (228, 232, 236)
TILE_LINE = (198, 204, 212)
TEXT = (33, 37, 41)
BG = (255, 255, 255)
DIM = (140, 148, 158)
BAND = (241, 244, 247)
HILITE = (255, 244, 214)


def load_font(size):
    for name in ("msyh.ttc", "msyhbd.ttc", "simhei.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except Exception:
            continue
    return ImageFont.load_default()


def room_extent(room):
    xs = [t[0] for t in room["tiles"]]
    ys = [t[1] for t in room["tiles"]]
    h = TILE / 2.0
    return (min(xs) - h, max(xs) + h, min(ys) - h, max(ys) + h)


def fmt(p):
    return "[%g, %g]" % (round(p[0], 1), round(p[1], 1))


def render_panel(room, font, font_b, font_t, canvas_w):
    x0, x1, y0, y1 = room_extent(room)
    mw = int((x1 - x0) * PX_PER_M) + PAD * 2
    row_h = 26
    tbl_h = 42 + row_h * (len(room["boxes"]) + 1) + 34
    mh = int((y1 - y0) * PX_PER_M) + PAD * 2 - 10

    img = Image.new("RGB", (canvas_w, mh + tbl_h + 46), BG)
    d = ImageDraw.Draw(img)

    title = "%s   rotation=%s°   JSON 设计坐标 (center_m)" % (
        room["key"], room.get("rotation_resolved_deg", 0.0))
    d.text((PAD, 12), title, fill=TEXT, font=font_t)

    ox, oy = PAD + (canvas_w - mw) // 2, PAD + 30

    def sx(x):
        return ox + (x - x0) * PX_PER_M

    def sy(y):
        return oy + (y1 - y) * PX_PER_M

    for tx, ty in room["tiles"]:
        d.rectangle([(sx(tx - TILE / 2), sy(ty + TILE / 2)),
                     (sx(tx + TILE / 2), sy(ty - TILE / 2))],
                    fill=TILE_FILL, outline=TILE_LINE)
    d.rectangle([sx(x0), sy(y1), sx(x1), sy(y0)], outline=(52, 120, 214), width=2)

    rows = []
    for i, bx in enumerate(room["boxes"], start=1):
        w, h = bx["size"]
        ccx, ccy = bx["center_json"]
        rcx, rcy = bx["recommend_json"]
        moved_m = ((ccx - rcx) ** 2 + (ccy - rcy) ** 2) ** 0.5
        moved = moved_m > 0.05

        def rect(cx, cy):
            return [(sx(cx - w / 2), sy(cy + h / 2)), (sx(cx + w / 2), sy(cy - h / 2))]

        d.rectangle(rect(ccx, ccy), outline=CUR, width=3)
        if moved:
            d.rectangle(rect(rcx, rcy), outline=REC, width=3)
            d.line([sx(ccx), sy(ccy), sx(rcx), sy(rcy)], fill=REC, width=2)

        def badge(px, py, txt, color):
            r = 11
            d.ellipse([px - r, py - r, px + r, py + r], fill=color)
            bb = d.textbbox((0, 0), txt, font=font_b)
            d.text((px - (bb[2] - bb[0]) / 2, py - (bb[3] - bb[1]) / 2 - bb[1]),
                   txt, fill=(255, 255, 255), font=font_b)

        badge(sx(ccx), sy(ccy), str(i), CUR)
        if moved:
            badge(sx(rcx), sy(rcy), str(i), REC)

        rows.append((i, bx["box"].replace("box_", ""), bx["cap"], bx["recommend_cap"],
                     fmt(bx["center_json"]), fmt(bx["recommend_json"]), moved_m,
                     bx["size"], room.get("rotation_resolved_deg", 0.0)))

    ty = mh + 14
    d.rectangle([0, ty, canvas_w, ty + tbl_h - 34], fill=BAND)
    cols = [PAD + 4, PAD + 34, PAD + 250, PAD + 302, PAD + 372, PAD + 502, PAD + 636]
    head = ["#", "盒子", "cap", "改后cap", "当前 center_m", "推荐 center_m", "位移(m)"]
    for c, htxt in zip(cols, head):
        d.text((c, ty + 10), htxt, fill=DIM, font=font)
    d.line([PAD, ty + 32, canvas_w - PAD, ty + 32], fill=DIM, width=1)

    for k, (i, name, cap, rcap, cur, rec, moved_m, size, rot) in enumerate(rows):
        ry = ty + 40 + row_h * k
        if moved_m > 0.05:
            d.rectangle([PAD, ry - 3, canvas_w - PAD, ry + row_h - 5], fill=HILITE)
        col = REC if moved_m > 0.05 else TEXT
        vals = [str(i), name, str(cap), str(rcap), cur, rec,
                ("%.2f" % moved_m) if moved_m > 0.05 else "无需移动"]
        for c, v in zip(cols, vals):
            d.text((c, ry), v, fill=col, font=font)

    note = "盒子尺寸 %s m   |   每格地砖 %g m" % (
        " x ".join("%g" % s for s in rows[0][7]) if rows else "-", TILE)
    d.text((PAD, ty + 40 + row_h * len(rows) + 6), note, fill=DIM, font=font)

    return img


def main():
    with open(SRC, "r", encoding="utf-8") as f:
        data = json.load(f)

    font = load_font(14)
    font_b = load_font(12)
    font_t = load_font(18)

    panels = []
    CANVAS_W = 840
    rooms = sorted(data["rooms"], key=lambda r: r["key"])
    for r in rooms:
        panels.append(render_panel(r, font, font_b, font_t, CANVAS_W))

    gap = 22
    W = CANVAS_W
    H = sum(p.height for p in panels) + gap * (len(panels) - 1)
    canvas = Image.new("RGB", (W, H), (250, 251, 252))
    y = 0
    for p in panels:
        canvas.paste(p, (0, y))
        y += p.height + gap
    canvas.save(OUT)
    print("wrote %s  (%dx%d)" % (OUT, canvas.width, canvas.height))


if __name__ == "__main__":
    main()
