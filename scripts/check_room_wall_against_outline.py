"""把设计轮廓映射到房间帧，逐面比对实测墙位 —— 找出「哪一面墙错位」。

用法：
    python scripts/check_room_wall_against_outline.py \
        --data _scratch/wall01.json _scratch/wall08.json \
        --out outputs/room_wall_overlay/wall_vs_outline.png

为什么要这么比：`probe_room_wall_audit` 只能回答「这间房的墙和它自己的地板对不对」，
两间房都自洽就答不出业主说的「一边墙错位」。真正的判据是**设计轮廓**
（`room_templates/corridor_45x40.json` 的 `variant_footprints`）—— 轮廓说这一面
该有墙到哪儿，实测墙就必须到哪儿。

⚠️ 三个坐标系必须先对齐，否则结论全是假的：
  ① 设计轮廓用 `bbox_nw_x_east_y_south` 帧（NW 原点、+x 东、+y 南）；
  ② 房间帧是中心原点、+x 东、+z 南；
  ③ 美术按 `template_rotation_deg` 整体转过 —— room_01 是 90°、room_08 是 0°，
     所以**不能**用同一份顶点直接比，必须各自按自己的角度反算。

手性：`l_turn` 是 L 形，镜像和旋转是两回事。脚本对「原样 / 镜像」× 4 个直角
共 8 个候选全试一遍，用 **room_01（业主认可的那间）** 标定出本项目实际使用的
那一组（写进 `CALIBRATION`），再把这同一组套到其它房间上比 —— 只有同一把尺子
量出来的差异才算「这间房错了」。
"""

from __future__ import annotations

import argparse
import json
import math
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE_DIR = os.path.join(ROOT, "data", "level_plans", "expedition_01", "room_templates")

FONT_CANDIDATES = [
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/simhei.ttf",
    "C:/Windows/Fonts/simsun.ttc",
]

# 允许的墙面偏差（m）。半墙厚 0.15 + 建模误差，0.6 已经很宽松。
TOLERANCE_M = 0.6
# 逐面覆盖统计的分格宽度。
BIN_M = 0.5


def load_font(size: int):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def load_footprint(room_key: str, template_id: str, variant: str):
    path = os.path.join(TEMPLATE_DIR, "%s.json" % template_id)
    if not os.path.exists(path):
        return None, None
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    footprints = data.get("variant_footprints", {})
    entry = footprints.get(variant)
    if entry is None:
        return None, None
    size = data.get("size_m", [0.0, 0.0])
    return [(float(x), float(y)) for x, y in entry["vertices_m"]], (float(size[0]), float(size[1]))


def base_rotation_of(room, template_size):
    """房间相对模板的**基础**旋转：尺寸与模板同向 ⇒ 0°，宽深互换 ⇒ 90°。

    这个量不用读 `template_rotation_deg`：那个字段是生成器按端口配对现算的，
    与「美术壳实际转了多大」不是同一件事（本次实测就差了 90°）。用尺寸反推更可靠：
    45×40 的模板放进 40×45 的房间，只能是转了 90°。
    """
    tw, th = template_size
    rw, rh = room["dims"]
    if abs(rw - tw) <= 1.0 and abs(rh - th) <= 1.0:
        return 0.0
    if abs(rw - th) <= 1.0 and abs(rh - tw) <= 1.0:
        return 90.0
    return 0.0


def place_in_room(verts, template_size, room_dims, rotation_deg, flip_y: bool):
    """设计轮廓（NW 帧）→ 房间帧（中心帧）。"""
    tw, th = template_size
    pts = [((x - tw / 2.0), (y - th / 2.0)) for x, y in verts]
    if flip_y:
        # 设计帧的 +y 是「南」，房间帧的 +z 也是「南」，但美术源在 Blender 里
        # 是 +Y 北 —— 这一支用来试「设计表用的是另一套 y 符号」的假设。
        pts = [(x, -z) for x, z in pts]
    rad = math.radians(rotation_deg)
    cos, sin = math.cos(rad), math.sin(rad)
    return [(x * cos + z * sin, -x * sin + z * cos) for x, z in pts]


def boundary_segments(verts, room_dims):
    """轮廓上**落在包围盒四条边**的线段：{side: [(a, b), ...]}（沿墙区间）。"""
    w, h = room_dims
    hx, hz = w / 2.0, h / 2.0
    eps = 0.25
    out = {"north": [], "south": [], "east": [], "west": []}
    for index in range(len(verts)):
        x1, z1 = verts[index]
        x2, z2 = verts[(index + 1) % len(verts)]
        if abs(z1 + hz) <= eps and abs(z2 + hz) <= eps:
            out["north"].append((min(x1, x2), max(x1, x2)))
        elif abs(z1 - hz) <= eps and abs(z2 - hz) <= eps:
            out["south"].append((min(x1, x2), max(x1, x2)))
        elif abs(x1 - hx) <= eps and abs(x2 - hx) <= eps:
            out["east"].append((min(z1, z2), max(z1, z2)))
        elif abs(x1 + hx) <= eps and abs(x2 + hx) <= eps:
            out["west"].append((min(z1, z2), max(z1, z2)))
    return out


def measured_segments(room):
    """实测**贴边**墙段：{side: [(a, b), ...]}。"""
    w, h = room["dims"]
    hx, hz = w / 2.0, h / 2.0
    out = {"north": [], "south": [], "east": [], "west": []}
    for piece in room["pieces"]:
        offset = piece["offset"]
        if abs(offset) > 1.0:
            continue
        side = piece["side"]
        out[side].append((piece["along_min"], piece["along_max"]))
    return out


def span_of(side, room_dims):
    w, h = room_dims
    return w if side in ("north", "south") else h


def coverage(segments, span):
    """把区间表铺成 0.5 m 的布尔向量。"""
    count = max(1, int(round(span / BIN_M)))
    flags = [False] * count
    for a, b in segments:
        lo = max(0, int(math.floor((a + span / 2.0) / BIN_M)))
        hi = min(count, int(math.ceil((b + span / 2.0) / BIN_M)))
        for index in range(lo, hi):
            flags[index] = True
    return flags


def door_span(room, side):
    lane = room.get("door_lanes", {}).get(side)
    if lane is None or side not in room.get("doors", []):
        return None
    return (lane - 1.2, lane + 1.2)


def compare(room, design_segments):
    """逐面：设计要墙、实测没墙 = 缺；实测有墙、设计不该有 = 多。"""
    w, h = room["dims"]
    report = {}
    for side in ("north", "south", "east", "west"):
        span = span_of(side, room["dims"])
        want = coverage(design_segments[side], span)
        have = coverage(measured_segments(room)[side], span)
        door = door_span(room, side)
        missing, extra = [], []
        for index in range(len(want)):
            center = index * BIN_M - span / 2.0 + BIN_M / 2.0
            if door is not None and door[0] <= center <= door[1]:
                continue  # 门洞处不该有实墙，跳过
            if want[index] and not have[index]:
                missing.append(center)
            elif have[index] and not want[index]:
                extra.append(center)
        report[side] = {
            "span": span,
            "want": want,
            "have": have,
            "missing": _runs(missing, span),
            "extra": _runs(extra, span),
        }
    return report


def _runs(values, span):
    if not values:
        return []
    out = []
    start = values[0]
    prev = values[0]
    for value in values[1:]:
        if abs(value - prev - BIN_M) > 1e-6:
            out.append((start, prev + BIN_M / 2.0))
            start = value
        prev = value
    out.append((start, prev + BIN_M / 2.0))
    return out


def calibrate(rooms, template):
    """用业主认可的基准房（room_01）标定「镜像与否 + 角度」，返回标定结果。"""
    verdicts = []
    for flip_y in (False, True):
        for rotation in (0.0, 90.0, 180.0, 270.0):
            verts = place_in_room(template["verts"], template["size"], rooms[0]["dims"], rotation, flip_y)
            segs = boundary_segments(verts, rooms[0]["dims"])
            report = compare(rooms[0], segs)
            bad = sum(len(v["missing"]) + len(v["extra"]) for v in report.values())
            verdicts.append((bad, flip_y, rotation))
    verdicts.sort(key=lambda item: item[0])
    return verdicts[0]


def draw(room, design_segments, report, title, footer) -> Image.Image:
    px = 13
    pad = 26
    head = 58
    foot = 30
    w, h = room["dims"]
    img = Image.new(
        "RGB", (int(w * px) + pad * 2, int(h * px) + pad * 2 + head + foot), (247, 248, 250)
    )
    draw_ctx = ImageDraw.Draw(img)

    def sx(x):
        return pad + (x + w / 2.0) * px

    def sz(z):
        return head + pad + (z + h / 2.0) * px

    draw_ctx.text((pad, 8), title, fill=(20, 22, 26), font=load_font(18))
    draw_ctx.text((pad, 32), footer, fill=(90, 96, 104), font=load_font(12))

    # 房间边界
    draw_ctx.rectangle([sx(-w / 2), sz(-h / 2), sx(w / 2), sz(h / 2)], outline=(150, 156, 164))

    # 设计「该有墙」的边界段
    for side, segments in design_segments.items():
        for a, b in segments:
            if side == "north":
                draw_ctx.rectangle([sx(a), sz(-h / 2) - 2, sx(b), sz(-h / 2) + 2], fill=(60, 150, 75))
            elif side == "south":
                draw_ctx.rectangle([sx(a), sz(h / 2) - 2, sx(b), sz(h / 2) + 2], fill=(60, 150, 75))
            elif side == "east":
                draw_ctx.rectangle([sx(w / 2) - 2, sz(a), sx(w / 2) + 2, sz(b)], fill=(60, 150, 75))
            else:
                draw_ctx.rectangle([sx(-w / 2) - 2, sz(a), sx(-w / 2) + 2, sz(b)], fill=(60, 150, 75))

    # 实测墙（黑）
    hx, hz = w / 2.0, h / 2.0
    for piece in room["pieces"]:
        offset = piece["offset"]
        if abs(offset) > 1.0:
            continue
        a, b = piece["along_min"], piece["along_max"]
        side = piece["side"]
        if side in ("north", "south"):
            z = -hz + offset if side == "north" else hz + offset
            draw_ctx.rectangle([sx(a), sz(z) - 3, sx(b), sz(z) + 3], fill=(30, 32, 36))
        else:
            x = -hx + offset if side == "west" else hx + offset
            draw_ctx.rectangle([sx(x) - 3, sz(a), sx(x) + 3, sz(b)], fill=(30, 32, 36))

    # 设计要墙 / 实测没有 = 红；实测有 / 设计不该有 = 橙
    for side, data in report.items():
        for a, b in data["missing"]:
            if side in ("north", "south"):
                z = -hz if side == "north" else hz
                draw_ctx.rectangle([sx(a), sz(z) - 6, sx(b), sz(z) + 6], fill=(214, 48, 49))
            else:
                x = -hx if side == "west" else hx
                draw_ctx.rectangle([sx(x) - 6, sz(a), sx(x) + 6, sz(b)], fill=(214, 48, 49))
        for a, b in data["extra"]:
            if side in ("north", "south"):
                z = -hz if side == "north" else hz
                draw_ctx.rectangle([sx(a), sz(z) - 6, sx(b), sz(z) + 6], outline=(240, 150, 20), width=2)
            else:
                x = -hx if side == "west" else hx
                draw_ctx.rectangle([sx(x) - 6, sz(a), sx(x) + 6, sz(b)], outline=(240, 150, 20), width=2)
    return img


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", nargs="+", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--template", default="corridor_45x40")
    parser.add_argument("--variant", default="l_turn")
    parser.add_argument("--baseline", default="room_01", help="用来标定坐标变换的基准房 key")
    args = parser.parse_args()

    rooms = []
    for path in args.data:
        with open(path, encoding="utf-8") as handle:
            rooms.append(json.load(handle))

    verts, size = load_footprint("", args.template, args.variant)
    if verts is None:
        print("模板 %s 没有变体 %s 的轮廓" % (args.template, args.variant))
        return
    template = {"verts": verts, "size": size}

    baseline = next((r for r in rooms if r["room"] == args.baseline), rooms[0])
    baseline_base = base_rotation_of(baseline, size)

    # 标定：对基准房把 8 个候选全试一遍，取偏差最小的那一组。
    # 只标定「镜像」与「补偿角」两项；每间房自己的基础旋转由尺寸反推、各自加上去。
    best = None
    for flip_y in (False, True):
        for extra in (0.0, 90.0, 180.0, 270.0):
            rotation = baseline_base + extra
            verts_t = place_in_room(verts, size, baseline["dims"], rotation, flip_y)
            segs = boundary_segments(verts_t, baseline["dims"])
            rep = compare(baseline, segs)
            bad = sum(len(v["missing"]) + len(v["extra"]) for v in rep.values())
            if best is None or bad < best[0]:
                best = (bad, flip_y, extra)
    _, flip_y, extra = best
    print(
        "标定（基准 %s，尺寸 %.0f×%.0f，基础旋转 %.0f°）：镜像=%s，补偿角 %+.0f°；基准房误差 %d 处"
        % (
            baseline["room"], baseline["dims"][0], baseline["dims"][1], baseline_base,
            flip_y, extra, best[0],
        )
    )
    print()

    panels = []
    for room in rooms:
        rotation = base_rotation_of(room, size) + extra
        verts_t = place_in_room(verts, size, room["dims"], rotation, flip_y)
        segs = boundary_segments(verts_t, room["dims"])
        rep = compare(room, segs)
        total = sum(len(v["missing"]) + len(v["extra"]) for v in rep.values())
        print("== %s（%.0f×%.0f，轮廓按 %.0f° 摆）与设计轮廓差 %d 处" % (
            room["room"], room["dims"][0], room["dims"][1], rotation, total,
        ))
        for side in ("north", "south", "east", "west"):
            data = rep[side]
            if not data["missing"] and not data["extra"]:
                continue
            for a, b in data["missing"]:
                print("    %-5s 设计要墙 %.1f~%.1f（%.1f m）实测没有 ← 缺墙" % (side, a, b, b - a))
            for a, b in data["extra"]:
                print("    %-5s 实测有墙 %.1f~%.1f（%.1f m）设计不该有 ← 多墙" % (side, a, b, b - a))
        if not total:
            print("    ✅ 四面与设计轮廓一致")
        print()
        title = "%s（%s %s）" % (room["room"], args.template, args.variant)
        footer = "绿=设计要墙　黑=实测墙　红=该有却没有　橙框=不该有却有　门 %s" % "/".join(
            room.get("doors", [])
        )
        panels.append(draw(room, segs, rep, title, footer))

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
    print("已生成 %s" % out_path)


if __name__ == "__main__":
    main()
