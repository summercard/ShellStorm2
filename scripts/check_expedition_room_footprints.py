#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""远征关卡01 房型模板「外轮廓 + 多层几何」门禁（纯几何，不需要 Godot）。

真源：
  source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates/*.json

坐标系（由 scripts/render_expedition01_plan_sheet.py 的 door_marker() 反推钉死）：
  frame = "bbox_nw_x_east_y_south"
  顶点 (x, y) 以**包围盒西北角**为原点，x 向东为正、y 向**南**为正。
  ⇒ Godot 房间局部 = (x - w/2, 0, y - d/2)
    （房间局部为 x 东正、z 南正、原点在房间中心；远征设计源 +y = 世界 +z = 南）
  依据：door_marker() 里 side=="north" 取 yy=0.0、side=="south" 取 yy=r["d"]。
  ⚠️ memory/2156 记的「原点 = 包围盒西南角」与 north=0 矛盾，是错的；以本条为准。

判据：
  1. variant_footprints 的 key 集合必须与 variants 完全一致（有则齐，不许多/少）。
  2. 每个轮廓：顶点 >=3、全是数字对、落 grid_unit_m 网格、全在包围盒内、
     包围盒恰好等于 size_m、每条边轴对齐、不自交、面积 > 0。
  3. 逐向算「可开门槽」：wall_lane_table 里的槽，必须**完全落在该向外墙线段上**才可开门；
     缺口处的槽单独列出（运行时裁切与放置约束要消费这份清单）。
     openable_walls 里声明的每一向至少要有 1 个可开门槽。
  4. sunken_pit（若声明）：rect_m 在包围盒内、size_m 与 rect_m 一致、depth_m > 0。
  5. bridge_span（若声明）：rect_m 在包围盒内、且被 sunken_pit 的 rect_m 覆盖。

用法：
  python scripts/check_expedition_room_footprints.py           # 校验并打印槽表
  python scripts/check_expedition_room_footprints.py --quiet   # 只打印结论行
退出码：0 全过 / 1 有失败项。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES_DIR = (
    ROOT
    / "source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates"
)

FRAME_ID = "bbox_nw_x_east_y_south"
EPS = 1e-6
# 门的半宽：槽中心 ±2.5 m 为这一个 5 m lane 的可开区间（与 door_contract 无关，是 lane 粒度）。
LANE_HALF_M = 2.5

SIDES = ("north", "south", "east", "west")


# ----------------------------------------------------------------- 几何工具


def _close(a: float, b: float) -> bool:
    return abs(a - b) <= EPS


def polygon_area(pts: list[tuple[float, float]]) -> float:
    """鞋带公式，返回有符号面积（二倍面积 / 2）。"""
    total = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        total += x1 * y2 - x2 * y1
    return total / 2.0


def axis_edges(
    pts: list[tuple[float, float]],
) -> tuple[list[tuple[float, float, float]], list[tuple[float, float, float]]] | None:
    """拆成轴对齐边。返回 (h_edges, v_edges)；h = [(y, x0, x1)]，v = [(x, y0, y1)]。

    出现非轴对齐边时返回 None（白盒轮廓必须轴对齐）。
    """
    h: list[tuple[float, float, float]] = []
    v: list[tuple[float, float, float]] = []
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        if _close(y1, y2):
            h.append((y1, min(x1, x2), max(x1, x2)))
        elif _close(x1, x2):
            v.append((x1, min(y1, y2), max(y1, y2)))
        else:
            return None
    return h, v


def _seg_intersect(a1, a2, b1, b2) -> bool:
    """线段相交（含端点与共线重叠）。轴对齐线段也适用。"""

    def cross(o, p, q) -> float:
        return (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])

    def on_seg(o, p, q) -> bool:
        return (
            min(o[0], q[0]) - EPS <= p[0] <= max(o[0], q[0]) + EPS
            and min(o[1], q[1]) - EPS <= p[1] <= max(o[1], q[1]) + EPS
        )

    d1 = cross(b1, b2, a1)
    d2 = cross(b1, b2, a2)
    d3 = cross(a1, a2, b1)
    d4 = cross(a1, a2, b2)
    if ((d1 > EPS) != (d2 > EPS)) and ((d3 > EPS) != (d4 > EPS)):
        return True
    if abs(d1) <= EPS and on_seg(b1, a1, b2):
        return True
    if abs(d2) <= EPS and on_seg(b1, a2, b2):
        return True
    if abs(d3) <= EPS and on_seg(a1, b1, a2):
        return True
    if abs(d4) <= EPS and on_seg(a1, b2, a2):
        return True
    return False


def has_self_intersection(pts: list[tuple[float, float]]) -> bool:
    """检查简单多边形是否自交（相邻边共享端点不算）。"""
    n = len(pts)
    for i in range(n):
        a1, a2 = pts[i], pts[(i + 1) % n]
        for j in range(i + 1, n):
            if j == i or (j + 1) % n == i or j == (i + 1) % n:
                continue
            b1, b2 = pts[j], pts[(j + 1) % n]
            if _seg_intersect(a1, a2, b1, b2):
                return True
    return False


def _covered(
    edges: list[tuple[float, float, float]], line: float, a: float, b: float
) -> bool:
    """该向的边界边里，是否存在一条完全覆盖 [a, b] 的线段。"""
    for key, e0, e1 in edges:
        if _close(key, line) and e0 <= a + EPS and e1 >= b - EPS:
            return True
    return False


def on_grid(value: float, unit: float) -> bool:
    return abs(value / unit - round(value / unit)) <= EPS


# ----------------------------------------------------------------- 校验


def _as_point(value, errors: list[str], where: str):
    if not isinstance(value, (list, tuple)) or len(value) != 2:
        errors.append(f"{where}: 顶点必须是 [x, y] 两元素数组，实为 {value!r}")
        return None
    x, y = value
    if not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
        errors.append(f"{where}: 顶点分量必须是数字，实为 {value!r}")
        return None
    return float(x), float(y)


def check_contour(
    template_id: str,
    variant_id: str,
    contour: dict,
    size: tuple[float, float],
    grid_unit: float,
    errors: list[str],
    warnings: list[str],
) -> tuple[list[tuple[float, float]], list, list] | None:
    where = f"{template_id}/{variant_id}"
    if not isinstance(contour, dict):
        errors.append(f"{where}: variant_footprints 的值必须是对象")
        return None
    frame = str(contour.get("frame", ""))
    if frame != FRAME_ID:
        errors.append(
            f"{where}: frame 必须是 {FRAME_ID}（实为 {frame!r}）；"
            "坐标系由 render_expedition01_plan_sheet.py::door_marker 钉死"
        )
    kind = str(contour.get("kind", ""))
    if kind != "polygon":
        errors.append(f"{where}: kind 目前只支持 polygon（实为 {kind!r}）")
    raw = contour.get("vertices_m")
    if not isinstance(raw, list) or len(raw) < 3:
        errors.append(f"{where}: vertices_m 至少 3 个顶点")
        return None
    pts: list[tuple[float, float]] = []
    for index, value in enumerate(raw):
        point = _as_point(value, errors, f"{where} 顶点#{index}")
        if point is None:
            return None
        pts.append(point)

    w, d = size
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    if not (_close(min(xs), 0.0) and _close(max(xs), w)):
        errors.append(
            f"{where}: 轮廓 x 包围盒 [{min(xs)}, {max(xs)}] 必须恰好等于 [0, {w}]"
        )
    if not (_close(min(ys), 0.0) and _close(max(ys), d)):
        errors.append(
            f"{where}: 轮廓 y 包围盒 [{min(ys)}, {max(ys)}] 必须恰好等于 [0, {d}]"
        )
    for index, (x, y) in enumerate(pts):
        if not (0.0 - EPS <= x <= w + EPS and 0.0 - EPS <= y <= d + EPS):
            errors.append(f"{where} 顶点#{index} ({x}, {y}) 超出包围盒 {w}×{d}")
        if not on_grid(x, grid_unit) or not on_grid(y, grid_unit):
            errors.append(
                f"{where} 顶点#{index} ({x}, {y}) 未落在 {grid_unit}m 网格上"
            )

    edges = axis_edges(pts)
    if edges is None:
        errors.append(f"{where}: 存在非轴对齐边（白盒轮廓必须全部轴对齐）")
        return None
    if has_self_intersection(pts):
        errors.append(f"{where}: 轮廓自交")

    area = polygon_area(pts)
    if abs(area) <= EPS:
        errors.append(f"{where}: 轮廓面积为零（顶点顺序或退化成线）")
    elif abs(area) > w * d + EPS:
        errors.append(f"{where}: 轮廓面积 {abs(area)} 大于包围盒 {w * d}")
    else:
        warnings.append(
            f"{where}: 轮廓面积 {abs(area):.1f} m²（包围盒 {w * d:.0f} m²，"
            f"缺 {w * d - abs(area):.1f} m²）"
        )
    h_edges, v_edges = edges
    return pts, h_edges, v_edges


def openable_slots(
    template: dict,
    variant_id: str,
    h_edges: list,
    v_edges: list,
) -> dict[str, dict[str, list[float]]]:
    """逐向把 wall_lane_table 的槽分成「可开门」与「缺口」两类。"""
    size = template["size_m"]
    w, d = float(size[0]), float(size[1])
    lane_table = template.get("wall_lane_table", {}) or {}
    result: dict[str, dict[str, list[float]]] = {}
    for side in SIDES:
        lanes = lane_table.get(side)
        if not isinstance(lanes, list):
            result[side] = {"openable": [], "blocked": []}
            continue
        is_ns = side in ("north", "south")
        span = w if is_ns else d
        line = 0.0 if side in ("north", "west") else (d if is_ns else w)
        edges = h_edges if is_ns else v_edges
        ok: list[float] = []
        blocked: list[float] = []
        for lane_value in lanes:
            lane = float(lane_value)
            center = lane + span / 2.0
            a, b = center - LANE_HALF_M, center + LANE_HALF_M
            if _covered(edges, line, a, b):
                ok.append(lane)
            else:
                blocked.append(lane)
        result[side] = {"openable": ok, "blocked": blocked}
    return result


def check_template(name: str, template: dict, errors: list[str], warnings: list[str]):
    report: dict = {"template": name, "contours": {}, "slots": {}, "pit": None}
    size_raw = template.get("size_m")
    if not isinstance(size_raw, list) or len(size_raw) != 2:
        errors.append(f"{name}: size_m 必须是 [w, d]")
        return report
    size = (float(size_raw[0]), float(size_raw[1]))
    grid_unit = float(template.get("grid_unit_m", 5.0))

    variants = template.get("variants", []) or []
    footprints = template.get("variant_footprints")
    if footprints is None:
        if variants:
            warnings.append(
                f"{name}: 声明了 variants {variants} 但没有 variant_footprints"
                "（若这些变体的外轮廓不是矩形，必须补）"
            )
    else:
        if not isinstance(footprints, dict):
            errors.append(f"{name}: variant_footprints 必须是对象")
        else:
            missing = [v for v in variants if v not in footprints]
            extra = [k for k in footprints if k not in variants]
            if missing:
                errors.append(f"{name}: variant_footprints 缺变体 {missing}")
            if extra:
                errors.append(f"{name}: variant_footprints 多了不属于 variants 的键 {extra}")
            for variant_id in [v for v in variants if v in footprints]:
                checked = check_contour(
                    name, variant_id, footprints[variant_id], size, grid_unit, errors, warnings
                )
                if checked is None:
                    continue
                pts, h_edges, v_edges = checked
                slots = openable_slots(template, variant_id, h_edges, v_edges)
                report["contours"][variant_id] = {"area_m2": abs(polygon_area(pts))}
                report["slots"][variant_id] = slots
                for side in SIDES:
                    if side not in (template.get("openable_walls", []) or []):
                        continue
                    if not slots[side]["openable"]:
                        errors.append(
                            f"{name}/{variant_id}: {side} 在 openable_walls 里，"
                            "但轮廓上没有一个可开门槽（该向外墙全在缺口里）"
                        )

    pit = template.get("sunken_pit")
    if pit is not None:
        if not isinstance(pit, dict):
            errors.append(f"{name}: sunken_pit 必须是对象")
        else:
            rect = pit.get("rect_m", {}) or {}
            xr = rect.get("x")
            yr = rect.get("y")
            if not (isinstance(xr, list) and isinstance(yr, list) and len(xr) == 2 and len(yr) == 2):
                errors.append(f"{name}: sunken_pit.rect_m 需要 x/y 各两元素")
            else:
                w, d = size
                x0, x1 = float(xr[0]), float(xr[1])
                y0, y1 = float(yr[0]), float(yr[1])
                if not (0.0 - EPS <= x0 < x1 <= w + EPS and 0.0 - EPS <= y0 < y1 <= d + EPS):
                    errors.append(
                        f"{name}: sunken_pit.rect_m x[{x0},{x1}] y[{y0},{y1}] 超出包围盒 {w}×{d}"
                    )
                size_m = pit.get("size_m")
                if isinstance(size_m, list) and len(size_m) == 2:
                    if not (_close(float(size_m[0]), x1 - x0) and _close(float(size_m[1]), y1 - y0)):
                        errors.append(
                            f"{name}: sunken_pit.size_m {size_m} 与 rect_m "
                            f"[{x1 - x0}, {y1 - y0}] 不一致"
                        )
                else:
                    errors.append(f"{name}: sunken_pit.size_m 必须是 [w, d]")
                depth = pit.get("depth_m")
                if not isinstance(depth, (int, float)) or float(depth) <= 0.0:
                    errors.append(f"{name}: sunken_pit.depth_m 必须 > 0")
                lower = pit.get("lower_platform") or {}
                if not isinstance(lower, dict) or not str(lower.get("enclosure", "")):
                    errors.append(f"{name}: sunken_pit.lower_platform.enclosure 缺失（下层围合做法）")
                if not isinstance(lower, dict) or not str(lower.get("floor", "")):
                    errors.append(f"{name}: sunken_pit.lower_platform.floor 缺失（坑底做法）")
                if isinstance(lower, dict) and lower.get("accessible") is not False:
                    errors.append(
                        f"{name}: sunken_pit.lower_platform.accessible 必须是 false"
                        "（业主裁决：下层下不去，纯装饰）"
                    )
                report["pit"] = {
                    "rect_m": [x0, x1, y0, y1],
                    "size_m": [x1 - x0, y1 - y0],
                    "depth_m": float(depth),
                }

            span = template.get("bridge_span")
            if span is not None and isinstance(span, dict):
                sx = (span.get("rect_m", {}) or {}).get("x")
                sy = (span.get("rect_m", {}) or {}).get("y")
                if isinstance(xr, list) and isinstance(yr, list) and isinstance(sx, list) and isinstance(sy, list):
                    if not (
                        float(xr[0]) - EPS <= float(sx[0])
                        and float(sx[1]) <= float(xr[1]) + EPS
                        and float(yr[0]) - EPS <= float(sy[0])
                        and float(sy[1]) <= float(yr[1]) + EPS
                    ):
                        errors.append(
                            f"{name}: bridge_span.rect_m x{sx} y{sy} 必须落在 sunken_pit 范围内"
                        )
                    width = span.get("width_m")
                    if isinstance(width, (int, float)) and not _close(float(width), float(sy[1]) - float(sy[0])):
                        errors.append(
                            f"{name}: bridge_span.width_m {width} 与 rect_m 的 y 跨 "
                            f"{float(sy[1]) - float(sy[0])} 不一致"
                        )
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="远征房型模板外轮廓/多层几何门禁")
    parser.add_argument("--quiet", action="store_true", help="只打印结论行")
    parser.add_argument(
        "--templates-dir",
        default=str(TEMPLATES_DIR),
        help="模板目录（默认远征01 的 room_templates；自测用它注入临时副本）",
    )
    args = parser.parse_args()
    templates_dir = Path(args.templates_dir)

    if not templates_dir.is_dir():
        print(f"FAIL: 模板目录不存在 {templates_dir}")
        return 1

    files = sorted(templates_dir.glob("*.json"))
    errors: list[str] = []
    warnings: list[str] = []
    reports: list[dict] = []
    for path in files:
        try:
            template = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            errors.append(f"{path.stem}: JSON 解析失败：{exc}")
            continue
        reports.append(check_template(path.stem, template, errors, warnings))

    contour_count = sum(len(r["contours"]) for r in reports)
    pit_count = sum(1 for r in reports if r["pit"])

    if not args.quiet:
        print(f"模板目录：{templates_dir}")
        print(f"模板数：{len(files)}｜带轮廓的模板：{sum(1 for r in reports if r['contours'])}｜轮廓数：{contour_count}")
        for report in reports:
            if not report["contours"] and not report["pit"]:
                continue
            print(f"\n== {report['template']} ==")
            for variant_id, info in report["contours"].items():
                print(f"  [{variant_id}] 面积 {info['area_m2']:.1f} m²")
                for side in SIDES:
                    slots = report["slots"][variant_id][side]
                    if not slots["openable"] and not slots["blocked"]:
                        continue
                    blocked = "、".join(f"{v:g}" for v in slots["blocked"]) or "—"
                    openable = "、".join(f"{v:g}" for v in slots["openable"]) or "—"
                    print(f"    {side:>5}: 可开 [{openable}]｜缺口 [{blocked}]")
            if report["pit"]:
                pit = report["pit"]
                print(
                    f"  下沉坑 rect {pit['rect_m']} = {pit['size_m'][0]:g}×{pit['size_m'][1]:g} m"
                    f"｜深 {pit['depth_m']:g} m"
                )
        if warnings:
            print("\n提示：")
            for line in warnings:
                print(f"  - {line}")

    if errors:
        print(f"\n失败项（{len(errors)}）：")
        for line in errors:
            print(f"  FAIL: {line}")
        return 1
    print(
        f"\nEXPEDITION_FOOTPRINTS_OK templates={len(files)} contours={contour_count} "
        f"pit_templates={pit_count} frame={FRAME_ID}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
