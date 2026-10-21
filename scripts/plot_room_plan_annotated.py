"""把 `probe_room_wall_audit` 导出的墙段画成**带方位标注**的平面图，多间房并排。

用途：业主说「有一边墙位置错位」，但逐段数据核查下来几间房互相自洽，
靠数字指不出来 —— 就把图摆正、标好东南西北，让业主直接指哪一边。

`--design 模板:变体` 时最左边多一块**设计图面板**（按模板 `variant_footprints`
自带的顶点与尺寸画），这样「设计要什么形状 / 两张实装长什么样」一眼可比。

口径：
  · 房间帧：+x 东、+z 南、原点在房心；
  · 图上北在上（对应 −z），所以 `sz()` 把 z 正向朝下画；
  · 只画**贴边墙**（|offset| ≤ 1.0 m），内转角墙单独用浅色标出来。
"""

from __future__ import annotations

import argparse
import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE_DIR = os.path.join(ROOT, "data", "level_plans", "expedition_01", "room_templates")
FONT_CANDIDATES = [
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/simhei.ttf",
    "C:/Windows/Fonts/simsun.ttc",
]

PX = 13
PAD = 34
HEAD = 60
FOOT = 30
WALL_TOL_M = 1.0


def load_font(size: int):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def _axes(ctx, sx, sz, w, h, ph):
    """四边方位标注。"""
    blue = (60, 120, 200)
    ctx.text((sx(0) - 6, HEAD + 2), "北", fill=blue, font=load_font(15))
    ctx.text((sx(0) - 6, ph - FOOT - 20), "南", fill=blue, font=load_font(15))
    ctx.text((6, sz(0) - 8), "西", fill=blue, font=load_font(15))
    ctx.text((sx(w / 2.0) + 12, sz(0) - 8), "东", fill=blue, font=load_font(15))


def draw_design(template_id: str, variant: str) -> Image.Image:
    path = os.path.join(TEMPLATE_DIR, "%s.json" % template_id)
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    verts = [(float(x), float(y)) for x, y in data["variant_footprints"][variant]["vertices_m"]]
    w, h = float(data["size_m"][0]), float(data["size_m"][1])
    hx, hz = w / 2.0, h / 2.0

    pw = int(w * PX) + PAD * 2
    ph = int(h * PX) + PAD * 2 + HEAD + FOOT
    img = Image.new("RGB", (pw, ph), (248, 249, 251))
    ctx = ImageDraw.Draw(img)

    def sx(x):
        return PAD + (x + hx) * PX

    def sz(z):
        return HEAD + PAD + (z + hz) * PX

    ctx.text((PAD, 6), "设计图（%s::%s）" % (template_id, variant), fill=(20, 22, 26),
             font=load_font(18))
    ctx.text((PAD, 32), "%.0f 宽 × %.0f 深　凹口应在此角" % (w, h), fill=(96, 102, 110),
             font=load_font(13))

    poly = [(sx(x - hx), sz(y - hz)) for x, y in verts]
    ctx.polygon(poly, fill=(226, 240, 226), outline=(40, 120, 60))
    for i in range(len(poly)):
        ctx.line([poly[i], poly[(i + 1) % len(poly)]], fill=(40, 120, 60), width=3)

    _axes(ctx, sx, sz, w, h, ph)
    ctx.text((PAD, ph - FOOT + 6), "绿 = 设计实心区（墙体该沿这条边界走）",
             fill=(96, 102, 110), font=load_font(11))
    return img


def draw_room(room: dict) -> Image.Image:
    w, h = room["dims"]
    hx, hz = w / 2.0, h / 2.0
    pw = int(w * PX) + PAD * 2
    ph = int(h * PX) + PAD * 2 + HEAD + FOOT
    img = Image.new("RGB", (pw, ph), (248, 249, 251))
    ctx = ImageDraw.Draw(img)
    mono = load_font(13)
    small = load_font(11)
    big = load_font(18)

    def sx(x):
        return PAD + (x + hx) * PX

    def sz(z):
        return HEAD + PAD + (z + hz) * PX

    ctx.text((PAD, 6), room["room"], fill=(20, 22, 26), font=big)
    ctx.text(
        (PAD, 32),
        "%.0f 宽 × %.0f 深｜门 %s" % (w, h, " / ".join(room.get("doors", []))),
        fill=(96, 102, 110),
        font=mono,
    )

    # 房间包围盒（虚线感：四段短线）
    step = 1.0
    for x in range(0, int(w) + 1, 2):
        px0 = sx(-hx + x)
        px1 = sx(-hx + min(x + step, w))
        ctx.line([(px0, sz(-hz)), (px1, sz(-hz))], fill=(176, 182, 190))
        ctx.line([(px0, sz(hz)), (px1, sz(hz))], fill=(176, 182, 190))
    for z in range(0, int(h) + 1, 2):
        pz0 = sz(-hz + z)
        pz1 = sz(-hz + min(z + step, h))
        ctx.line([(sx(-hx), pz0), (sx(-hx), pz1)], fill=(176, 182, 190))
        ctx.line([(sx(hx), pz0), (sx(hx), pz1)], fill=(176, 182, 190))

    pieces = room["pieces"]
    for piece in pieces:
        offset = piece["offset"]
        a, b = piece["along_min"], piece["along_max"]
        side = piece["side"]
        boundary = abs(offset) <= WALL_TOL_M
        colour = (32, 34, 38) if boundary else (150, 170, 200)
        half = 4 if boundary else 2
        if piece["axis"] == "X":
            z = -hz + offset if side == "north" else hz + offset
            ctx.rectangle([sx(a), sz(z) - half, sx(b), sz(z) + half], fill=colour)
        else:
            x = -hx + offset if side == "west" else hx + offset
            ctx.rectangle([sx(x) - half, sz(a), sx(x) + half, sz(b)], fill=colour)

    # 门：橙圈 + lane 数值
    lanes = room.get("door_lanes", {})
    for side in room.get("doors", []):
        lane = float(lanes.get(side, 0.0))
        if side == "north":
            ctx.ellipse([sx(lane) - 10, sz(-hz) - 9, sx(lane) + 10, sz(-hz) + 9],
                        outline=(240, 148, 20), width=3)
            ctx.text((sx(lane) - 8, sz(-hz) - 26), "%+.1f" % lane, fill=(200, 120, 10), font=small)
        elif side == "south":
            ctx.ellipse([sx(lane) - 10, sz(hz) - 9, sx(lane) + 10, sz(hz) + 9],
                        outline=(240, 148, 20), width=3)
            ctx.text((sx(lane) - 8, sz(hz) + 12), "%+.1f" % lane, fill=(200, 120, 10), font=small)
        elif side == "east":
            ctx.ellipse([sx(hx) - 9, sz(lane) - 10, sx(hx) + 9, sz(lane) + 10],
                        outline=(240, 148, 20), width=3)
            ctx.text((sx(hx) + 12, sz(lane) - 6), "%+.1f" % lane, fill=(200, 120, 10), font=small)
        else:
            ctx.ellipse([sx(-hx) - 9, sz(lane) - 10, sx(-hx) + 9, sz(lane) + 10],
                        outline=(240, 148, 20), width=3)
            ctx.text((sx(-hx) - 44, sz(lane) - 6), "%+.1f" % lane, fill=(200, 120, 10), font=small)

    # 方位标注
    _axes(ctx, sx, sz, w, h, ph)

    ctx.text(
        (PAD, ph - FOOT + 6),
        "黑=贴边墙　浅蓝=内转角墙　橙圈=门洞（数字为 lane）",
        fill=(96, 102, 110),
        font=small,
    )
    return img


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", nargs="+", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument(
        "--design",
        default="",
        help="额外在最左加一块设计图面板，写法 `模板:变体`，例如 corridor_45x40:l_turn",
    )
    args = parser.parse_args()

    panels = []
    if args.design:
        template_id, _, variant = args.design.partition(":")
        panels.append(draw_design(template_id, variant or ""))

    rooms = []
    for path in args.data:
        with open(path, encoding="utf-8") as handle:
            rooms.append(json.load(handle))
    rooms.sort(key=lambda r: r["room"])
    panels.extend(draw_room(room) for room in rooms)

    gap = 16
    total_w = sum(p.width for p in panels) + gap * (len(panels) - 1)
    total_h = max(p.height for p in panels)
    canvas = Image.new("RGB", (total_w, total_h), (228, 230, 234))
    x = 0
    for panel in panels:
        canvas.paste(panel, (x, 0))
        x += panel.width + gap
    out = args.out if os.path.isabs(args.out) else os.path.join(ROOT, args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    print("已生成 %s（%d×%d）" % (out, canvas.width, canvas.height))


if __name__ == "__main__":
    main()
