"""把 `probe_room_wall_audit` 导出的墙段画成「设计轮廓 vs 实测墙位」对照图。

用法：
    python scripts/plot_room_wall_overlay.py \
        --data _scratch/wall08.json _scratch/wall01.json \
        --out outputs/room_wall_overlay/l_turn_compare.png

为什么要有这张图：`corridor_45x40::l_turn` 是**手性形状**（L 形，凹口只在一边）。
文字口径说「凹口在东南」很难一眼判断对错，把设计轮廓和实测墙段叠在同一张图上，
哪个朝向、错在哪一边，直接看得出来。

读的口径：
  · 设计轮廓 = `room_templates/corridor_45x40.json` 的 `variant_footprints[l_turn]`，
    原点是 NW 角、+x 东、+y 南；换进房间帧要减去半尺寸。
  · 房间帧 = 房间节点自身（+x 东、+z 南），墙段用 `offset`（离边界多少米）+ `along`
    （沿墙区间）还原。
  · 房间帧与模板帧之间可能差 90° 的整数倍（`template_rotation_deg`），所以四个候选
    各算一次交并比（IoU），取最高者画出来，并把 IoU 打在标题上。
"""

from __future__ import annotations

import argparse
import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(
    ROOT, "data", "level_plans", "expedition_01", "room_templates", "corridor_45x40.json"
)

# PIL 的默认位图字体没有中文字形，标题会全是方块。按顺序找系统里的中文字体。
FONT_CANDIDATES = [
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/msyhl.ttc",
    "C:/Windows/Fonts/simhei.ttf",
    "C:/Windows/Fonts/simsun.ttc",
]


def load_font(size: int):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()

PX_PER_M = 12
PANEL_PAD = 26
HEADER_H = 56
FOOTER_H = 34
DASH = 6


def load_footprint(template_path: str, variant: str) -> list[tuple[float, float]]:
    with open(template_path, encoding="utf-8") as handle:
        data = json.load(handle)
    verts = data["variant_footprints"][variant]["vertices_m"]
    return [(float(x), float(y)) for x, y in verts]


def centered(verts, w, h):
    return [(x - w / 2.0, y - h / 2.0) for x, y in verts]


def rotate(verts, deg):
    """绕 Y 轴旋转（Godot 口径）：(x, z) -> (x·cos + z·sin, -x·sin + z·cos)。"""
    import math

    rad = math.radians(deg)
    cos, sin = math.cos(rad), math.sin(rad)
    return [(x * cos + z * sin, -x * sin + z * cos) for x, z in verts]


def point_in_poly(x, z, verts) -> bool:
    inside = False
    count = len(verts)
    for i in range(count):
        x1, z1 = verts[i]
        x2, z2 = verts[(i + 1) % count]
        if (z1 > z) != (z2 > z):
            x_hit = (x2 - x1) * (z - z1) / (z2 - z1) + x1
            if x < x_hit:
                inside = not inside
    return inside


def wall_mask(room: dict, cell: float = 0.5) -> tuple[set, tuple[float, float], int, int]:
    w, h = room["dims"]
    hx, hz = w / 2.0, h / 2.0
    nx = int(round(w / cell))
    nz = int(round(h / cell))
    mask = set()
    for piece in room["pieces"]:
        offset = piece["offset"]
        a, b = piece["along_min"], piece["along_max"]
        if piece["axis"] == "X":
            z0 = hz + offset if piece["side"] == "south" else -hz + offset
            for i in range(nx):
                x = -hx + (i + 0.5) * cell
                if not (a - 1e-6 <= x <= b + 1e-6):
                    continue
                for j in range(nz):
                    z = -hz + (j + 0.5) * cell
                    if abs(z - z0) <= 1.1:
                        mask.add((i, j))
        else:
            x0 = hx + offset if piece["side"] == "east" else -hx + offset
            for j in range(nz):
                z = -hz + (j + 0.5) * cell
                if not (a - 1e-6 <= z <= b + 1e-6):
                    continue
                for i in range(nx):
                    x = -hx + (i + 0.5) * cell
                    if abs(x - x0) <= 1.1:
                        mask.add((i, j))
    return mask, (-hx, -hz), nx, nz


def solid_mask(verts, cell: float = 0.5) -> tuple[set, tuple[float, float], int, int]:
    xs = [x for x, _ in verts]
    zs = [z for _, z in verts]
    x0, z0 = min(xs), min(zs)
    nx = int(round((max(xs) - x0) / cell))
    nz = int(round((max(zs) - z0) / cell))
    mask = set()
    for i in range(nx):
        for j in range(nz):
            if point_in_poly(x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell, verts):
                mask.add((i, j))
    return mask, (x0, z0), nx, nz


def boundary_of(mask, origin, nx, nz, cell: float = 0.5) -> set:
    """只保留**外轮廓附近**的格子：一个格子在 solid 里，且 3×3 邻域里有空格。"""
    out = set()
    for i, j in mask:
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                if (i + di, j + dj) not in mask:
                    out.add((i, j))
                    break
            else:
                continue
            break
    return out


def iou(a: set, b: set) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / float(len(a | b))


def draw_panel(room: dict, verts_template, title: str) -> Image.Image:
    w, h = room["dims"]
    cell = 0.5
    wall, _, nx, nz = wall_mask(room, cell)

    # 8 个候选（原样/镜像 × 4 个 90° 倍角）。镜像必须一起算 ——
    # `l_turn` 是手性形状，镜像与旋转是两件事，只试旋转会把「镜像错位」
    # 误判成「转了个角度」。
    candidates = []
    for mirrored in (False, True):
        base = [(-x, z) for x, z in verts_template] if mirrored else list(verts_template)
        for deg in (0.0, 90.0, 180.0, 270.0):
            cand = rotate(base, deg)
            xs = [p[0] for p in cand]
            zs = [p[1] for p in cand]
            if abs((max(xs) - min(xs)) - w) > 1.2 or abs((max(zs) - min(zs)) - h) > 1.2:
                continue
            solid, _, _, _ = solid_mask(cand, cell)
            score = iou(wall, boundary_of(solid, None, 0, 0, cell))
            candidates.append((score, deg, mirrored, cand, solid))
    if not candidates:
        candidates = [(0.0, 0.0, False, verts_template, set())]
    candidates.sort(key=lambda item: -item[0])
    score, deg, mirrored, cand, solid = candidates[0]
    upright = next((c for c in candidates if not c[2]), None)
    mirror_best = next((c for c in candidates if c[2]), None)

    pw = int(w * PX_PER_M) + PANEL_PAD * 2
    ph = int(h * PX_PER_M) + PANEL_PAD * 2 + HEADER_H + FOOTER_H
    img = Image.new("RGB", (pw, ph), (247, 248, 250))
    draw = ImageDraw.Draw(img)

    def sx(x):
        return PANEL_PAD + (x + w / 2.0) * PX_PER_M

    def sz(z):
        return HEADER_H + PANEL_PAD + (z + h / 2.0) * PX_PER_M

    draw.text((PANEL_PAD, 8), title, fill=(20, 22, 26), font=load_font(19))
    verdict = "镜像 %d°" % int(deg) if mirrored else "原样 %d°" % int(deg)
    sub = "最优拟合：%s，交并比 %.2f" % (verdict, score)
    if upright and mirror_best:
        sub += "　（原样最好 %.2f / 镜像最好 %.2f）" % (upright[0], mirror_best[0])
    draw.text((PANEL_PAD, 32), sub, fill=(90, 96, 104), font=load_font(13))

    # 设计轮廓填充
    draw.polygon([(sx(x), sz(z)) for x, z in cand], fill=(226, 240, 226))

    # 设计边界（虚线段示意）
    for i in range(len(cand)):
        x1, z1 = cand[i]
        x2, z2 = cand[(i + 1) % len(cand)]
        length = ((x2 - x1) ** 2 + (z2 - z1) ** 2) ** 0.5
        steps = max(1, int(length / 0.8))
        for s in range(steps):
            if s % 2:
                continue
            t1 = s / steps
            t2 = min(1.0, (s + 1) / steps)
            draw.line(
                [
                    (sx(x1 + (x2 - x1) * t1), sz(z1 + (z2 - z1) * t1)),
                    (sx(x1 + (x2 - x1) * t2), sz(z1 + (z2 - z1) * t2)),
                ],
                fill=(70, 150, 80),
                width=3,
            )

    # 实测墙段
    hx, hz = w / 2.0, h / 2.0
    for piece in room["pieces"]:
        offset = piece["offset"]
        a, b = piece["along_min"], piece["along_max"]
        if piece["axis"] == "X":
            z = hz + offset if piece["side"] == "south" else -hz + offset
            draw.rectangle(
                [sx(a), sz(z) - 2, sx(b), sz(z) + 2], fill=(214, 48, 49)
            )
        else:
            x = hx + offset if piece["side"] == "east" else -hx + offset
            draw.rectangle(
                [sx(x) - 2, sz(a), sx(x) + 2, sz(b)], fill=(214, 48, 49)
            )

    # 房间边界 + 门
    draw.rectangle(
        [sx(-w / 2), sz(-h / 2), sx(w / 2), sz(h / 2)], outline=(150, 156, 164), width=1
    )
    for door in room["doors"]:
        if door in ("north", "south"):
            z = -hz if door == "north" else hz
            draw.ellipse([sx(-1.1), sz(z) - 9, sx(1.1), sz(z) + 9], outline=(240, 150, 20), width=3)
        else:
            x = -hx if door == "west" else hx
            draw.ellipse([sx(x) - 9, sz(-1.1), sx(x) + 9, sz(1.1)], outline=(240, 150, 20), width=3)

    foot = "房间 %.0f×%.0f m｜美术根 %+.0f°｜模板旋转 %+.0f°｜门 %s" % (
        w, h, room.get("art_rotation_deg", 0.0), room.get("template_rotation_deg", 0.0),
        "/".join(room["doors"]),
    )
    draw.text((PANEL_PAD, ph - FOOTER_H + 8), foot, fill=(90, 96, 104), font=load_font(13))
    return img


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", nargs="+", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--variant", default="l_turn")
    args = parser.parse_args()

    verts = load_footprint(TEMPLATE, args.variant)
    rooms = []
    for path in args.data:
        with open(path, encoding="utf-8") as handle:
            room = json.load(handle)
        w, h = room["dims"]
        rooms.append((room, centered(verts, 45.0, 40.0)))

    panels = []
    for room, verts_centered in rooms:
        title = "%s（%s）" % (room["room"], args.variant)
        panels.append(draw_panel(room, verts_centered, title))

    gap = 14
    total_w = sum(p.width for p in panels) + gap * (len(panels) - 1)
    total_h = max(p.height for p in panels)
    canvas = Image.new("RGB", (total_w, total_h), (232, 234, 238))
    x = 0
    for panel in panels:
        canvas.paste(panel, (x, 0))
        x += panel.width + gap

    out_path = args.out if os.path.isabs(args.out) else os.path.join(ROOT, args.out)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    canvas.save(out_path)
    print("已生成 %s（%d×%d）" % (out_path, canvas.width, canvas.height))


if __name__ == "__main__":
    main()
