#!/usr/bin/env python3
"""把 EGT 壳体导出的实例清单画成俯视平面图。

数据由 `tests/verification/export_egt_shell.gd` 真实跑
`assemble_flow → EgtPlanBridge.to_block → build_block` 产生 —— 也就是**会进游戏的那批几何**
（墙 / 门洞 / L 角件 / 地砖），不是房间表。

这张图专门回答三件事，逻辑断言都答不了：
1. 每面墙是不是都补齐了（缺一格就是一条能走出去的缝）；
2. 门洞是不是正好对着相邻房间的门洞（差一格就是空气墙）；
3. 走廊拐角是不是真的连通（两段矩形共墙处必须各有一个门洞）。

运行：
    python3 scripts/render_egt_shell_layouts.py
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "docs/art/egt_shell_layouts/shells.json"
OUT_DIR = ROOT / "docs/art/egt_shell_layouts"

GRID = 5.0
## 墙的**视觉**厚度。真实件是 0.3m，在整层俯视图上不足 2px，看不出缺墙；
## 这里放大到 1.1m 只为可读，不改变任何几何判定（缺墙靠 `wall_gaps` 断言，不靠眼睛）。
WALL_THICK_M = 1.1

COLOR_BG = (250, 250, 251)
COLOR_FLOOR_A = (232, 236, 240)
COLOR_FLOOR_B = (223, 228, 234)
COLOR_CORRIDOR_FLOOR = (228, 220, 206)
COLOR_WALL = (58, 64, 72)
COLOR_DOOR_WALL = (58, 64, 72)
COLOR_DOOR_LEAF = (226, 148, 32)
COLOR_CORNER = (96, 104, 114)
COLOR_ROOM_EDGE = (150, 158, 168)


def wall_rect(item: dict) -> tuple[float, float, float, float]:
    """一面 5m 墙 → 轴对齐矩形（世界坐标 x0, y0, x1, y1）。"""
    px, py = item["pos"]
    rot = int(round(item["rot"])) % 180
    half_l = GRID / 2.0
    half_t = WALL_THICK_M / 2.0
    if rot == 0:
        return (px - half_l, py - half_t, px + half_l, py + half_t)
    return (px - half_t, py - half_l, px + half_t, py + half_l)


def corner_rects(item: dict) -> list[tuple[float, float, float, float]]:
    """L 角件的两条臂，各占 1 个 lane（各 5m）。"""
    px, py = item["pos"]
    rot = int(round(item["rot"])) % 360
    # CORNER_ROTATION_DEG: SW 0 / SE 90 / NE 180 / NW -90；臂沿本地 +X / +Y。
    import math

    out = []
    for local in ((1.0, 0.0), (0.0, 1.0)):
        # Blender Z-up、rotation_z_deg 逆时针；本地 +X 臂、本地 +Y 臂。
        c = math.cos(math.radians(rot))
        s = math.sin(math.radians(rot))
        dx = local[0] * c - local[1] * s
        dy = local[0] * s + local[1] * c
        arm_cx = px + dx * GRID / 2.0
        arm_cy = py + dy * GRID / 2.0
        if abs(dx) > abs(dy):
            out.append((arm_cx - GRID / 2, arm_cy - WALL_THICK_M / 2,
                        arm_cx + GRID / 2, arm_cy + WALL_THICK_M / 2))
        else:
            out.append((arm_cx - WALL_THICK_M / 2, arm_cy - GRID / 2,
                        arm_cx + WALL_THICK_M / 2, arm_cy + GRID / 2))
    return out


def render(case: dict, out: Path) -> None:
    from PIL import Image, ImageDraw

    rooms = case.get("rooms") or []
    if not rooms:
        return
    xs, ys = [], []
    for room in rooms:
        xs += room["bounds_x"]
        ys += room["bounds_y"]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    span_x = max(1.0, max_x - min_x)
    span_y = max(1.0, max_y - min_y)

    target = 1500
    scale = min(target / span_x, target / span_y)
    pad = 60
    size = (int(span_x * scale) + pad * 2, int(span_y * scale) + pad * 2 + 30)
    im = Image.new("RGB", size, COLOR_BG)
    dr = ImageDraw.Draw(im)

    def X(x: float) -> float:
        return pad + (x - min_x) * scale

    def Y(y: float) -> float:
        # Blender y 向北；屏幕上北在上 ⇒ 纵向取反。
        return pad + 22 + (max_y - y) * scale

    def box(rect: tuple[float, float, float, float], fill, outline=None, width: int = 0):
        x0, y0, x1, y1 = rect
        dr.rectangle([X(min(x0, x1)), Y(max(y0, y1)), X(max(x0, x1)), Y(min(y0, y1))],
                     fill=fill, outline=outline, width=width)

    # ① 房间轮廓（浅色底），用来判断"这个房间有没有被墙围起来"。
    corridor_ids = {r["room_id"] for r in rooms if r.get("is_corridor")}
    for room in rooms:
        bx0, bx1 = room["bounds_x"]
        by0, by1 = room["bounds_y"]
        is_cor = room["room_id"] in corridor_ids
        box((bx0, by0, bx1, by1), COLOR_CORRIDOR_FLOOR if is_cor else (242, 244, 246))

    # ② 地砖：棋盘格，用来确认地面是满铺的（凹口/缺角就是没铺到）。
    for item in case.get("floors") or []:
        px, py = item["pos"]
        is_c01 = int(px // GRID + py // GRID) % 2 == 0
        box((px - GRID / 2, py - GRID / 2, px + GRID / 2, py + GRID / 2),
            COLOR_FLOOR_A if is_c01 else COLOR_FLOOR_B)

    # ③ L 角件
    for item in case.get("corners") or []:
        for rect in corner_rects(item):
            box(rect, COLOR_CORNER)

    # ④ 墙（实体墙 + 门墙的画法一致：门洞由 ⑤ 的橙色门扇标出）
    for item in case.get("walls") or []:
        box(wall_rect(item), COLOR_WALL)

    # ⑤ 门扇
    for item in case.get("doors") or []:
        px, py = item["pos"]
        rot = int(round(item["rot"])) % 180
        if rot == 0:
            rect = (px - 1.1, py - 0.45, px + 1.1, py + 0.45)
        else:
            rect = (px - 0.45, py - 1.1, px + 0.45, py + 1.1)
        box(rect, COLOR_DOOR_LEAF)

    stats = case.get("stats") or {}
    title = "%s%s ｜ seed=%s  房间 %d + 走廊 %d 段  墙 %d  门 %d  地砖 %d" % (
        ("%s → " % case["label"]) if case.get("label") else "",
        case["flow_id"], case["seed"],
        len(rooms) - len(corridor_ids),
        int(stats.get("corridor_count", 0)),
        len(case.get("walls") or []), len(case.get("doors") or []),
        len(case.get("floors") or []))
    dr.text((pad, 6), title, fill=(28, 32, 36))

    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out)


def main() -> int:
    if not SRC.exists():
        print("缺少 %s —— 先跑 export_egt_shell.gd" % SRC)
        return 1
    payload = json.loads(SRC.read_text(encoding="utf-8"))
    rendered = 0
    for case in payload["cases"]:
        if not case.get("ok") or case.get("build_errors"):
            print("SKIP %s（ok=%s errors=%s）" % (
                case["flow_id"], case.get("ok"), case.get("build_errors")))
            continue
        name = "%s%s.png" % (case["label"] + "_" if case.get("label") else "", case["flow_id"])
        render(case, OUT_DIR / name)
        rendered += 1
    print("rendered %d shells -> %s" % (rendered, OUT_DIR.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
