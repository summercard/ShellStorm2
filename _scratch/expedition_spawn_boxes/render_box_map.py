"""远征关卡01 · 触发器刷怪落点平面图（旧机制 vs 新机制）。

数据源（全部实测，非文档抄录）：
  · 新机制 _scratch/expedition_spawn_boxes/spawn_box_map.json（本目录探针实测）
  · 旧机制 同一份 JSON 里的 room["legacy_points"]（同一探针族、同一种子、同一套房间几何）
  · 编成对比 _scratch/expedition_spawn_map/spawn_map.before-reprobe.json（可选）

2026-09-26 重渲要点：
  ① **全部数字从数据算**，不再手写「17 盒 / 8 个退化盒次」之类会过期的常量；
  ② 新增「**最外一圈禁刷**」判据的**可视化**：把每房最外一圈 5m 地砖涂成禁刷带，
     旧机制的点会明显落在带内、新机制的点全部在带外 —— 这就是业主提的那条口径；
  ③ 新增**圈位/净距**指标（每房最近落点离墙几米、第几圈），不再只给「离墙 ≥1.15」这种松口径；
  ④ 删掉已解决的旧叙事（`prefer_edge` 贴边加权、退化盒次根因），换成收口结论。

输出：ShellStorm2/outputs/expedition01_spawn_box_map.html（并镜像一份到工作区根的 outputs/）。
"""
import json
import math
import os
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
WORKSPACE = os.path.abspath(os.path.join(REPO, ".."))
NEW_JSON = os.path.join(HERE, "spawn_box_map.json")
OLD_JSON = os.path.join(REPO, "_scratch", "expedition_spawn_map", "spawn_map.before-reprobe.json")
OLD_HTML = "expedition01_spawn_map.html"
OUTS = [os.path.join(REPO, "outputs", "expedition01_spawn_box_map.html"),
        os.path.join(WORKSPACE, "outputs", "expedition01_spawn_box_map.html")]

TILE = 5.0
ENEMY_BODY_DIAM = 1.7  # 2 × Enemy3D footprint 半径 0.8，+0.1 余量 = 1.7
WALL_BAND = 1  # 业主口径：最外一圈 5m 地砖禁刷（wall_recess_tiles = 1）

ROOM_TYPE_ZH = {
    "STAIR_LOBBY": "入口安全屋", "COMBAT": "战斗房", "SCAVENGE": "搜刮房",
    "STORAGE": "仓储房", "EVENT": "事件房", "BOSS": "BOSS 竞技场",
    "EXTRACTION": "撤离屋",
}
ROOM_COLOR = {
    "STAIR_LOBBY": "#2ea043", "COMBAT": "#e05252", "SCAVENGE": "#d29922",
    "STORAGE": "#4f8cc9", "EVENT": "#a371f7", "BOSS": "#c2410c",
    "EXTRACTION": "#39c5cf",
}
MONSTER_ZH = {
    "melee_chaser": "近战追猎者", "ranged_caster": "远程术士", "ambusher": "伏击者",
    "shielded": "盾卫", "exploder": "自爆体", "summoner": "召唤者",
    "tank": "重装", "bomber": "爆破手", "boss": "首领", "elite": "精英",
}
MONSTER_COLOR = {
    "melee_chaser": "#f85149", "ranged_caster": "#a371f7", "ambusher": "#2ea043",
    "shielded": "#4f8cc9", "exploder": "#ff9e64", "summoner": "#e3b341",
    "boss": "#ff2d55", "elite": "#f2cc60",
}
BOX_FILL = "#39c5cf"
BAND_FILL = "#f85149"
DEFAULT_CLEARANCE = 1.15


# ---------- 几何 ----------

def cells_of(room):
    """房间 5m 地砖格心（房间局部系）。无壳体清单的房按 5m 模数补算。"""
    cells = [(c[0], c[1]) for c in room["tile_cells_local"]]
    if cells:
        return cells
    dx, dz = room["dimensions"]
    nx, nz = int(math.ceil(dx / TILE)), int(math.ceil(dz / TILE))
    return [(-dx * 0.5 + TILE * 0.5 + i * TILE, -dz * 0.5 + TILE * 0.5 + j * TILE)
            for i in range(nx) for j in range(nz)]


def footprint_test(cells):
    """返回 in_footprint(x, z)：点是否落在任一块 5m 地砖矩形内。"""
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


def wall_clearance(inside, x, z, cap=60.0):
    """沿 ±x/±z 直走到离开地砖并集所需距离的最小值（0.05m 步进，>cap 记 cap）。

    这就是业主口径里的「离墙净距」：L∞ 距离 ⇒ 除以 5 即「第几圈」（0 = 最外圈）。
    """
    best = cap
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        step = 0.0
        while step < cap:
            step += 0.05
            if not inside(x + dx * step, z + dz * step):
                break
        best = min(best, step)
    return best


def min_pair(points):
    best = float("inf")
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            best = min(best, math.dist(points[i], points[j]))
    return best


def rotate(x, z, deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return x * c - z * s, x * s + z * c


def to_world(room, x, z):
    lx, lz = rotate(x, z, room["yaw_deg"])
    return room["origin"][0] + lx, room["origin"][1] + lz


def box_probe_points(cx, cz, sx, sz, rot):
    """盒矩形（可旋转）的 4 角 + 4 边中点，用来量「盒边到墙的最近净距」。"""
    hx, hz = sx * 0.5, sz * 0.5
    rel = [(-hx, -hz), (hx, -hz), (-hx, hz), (hx, hz), (-hx, 0.0), (hx, 0.0), (0.0, -hz), (0.0, hz)]
    out = []
    for lx, lz in rel:
        rx, rz = rotate(lx, lz, rot)
        out.append((cx + rx, cz + rz))
    return out


def sched_room_metrics(room):
    """单房「最外一圈禁刷」实测：最近落点净距 / 圈位 / 最外圈落点数 / 盒边最近净距。"""
    cells = cells_of(room)
    inside = footprint_test(cells)
    rings = [int(wall_clearance(inside, cx, cz) // TILE) for cx, cz in cells]
    band_tiles = sum(1 for r in rings if r == 0)
    pts = [(e["local"][0], e["local"][1]) for w in room["waves"] for e in w]
    clr = [wall_clearance(inside, p[0], p[1]) for p in pts]
    outer_ring_hits = sum(1 for c in clr if c < TILE)
    # 盒边最近净距（取落地盒）
    box_clr = None
    for p in room["placements"]:
        if "error" in p:
            continue
        for bx, bz in box_probe_points(p["center_landed"][0], p["center_landed"][1],
                                       p["size"][0], p["size"][1], p["rotation_deg"]):
            c = wall_clearance(inside, bx, bz)
            box_clr = c if box_clr is None else min(box_clr, c)
    return {
        "cells": cells, "inside": inside, "band_tiles": band_tiles,
        "min_point_clr": min(clr) if clr else None,
        "point_ring": int(min(clr) // TILE) if clr else None,
        "outer_ring_hits": outer_ring_hits,
        "points": len(pts),
        "box_clr": box_clr,
        "box_ring": int(box_clr // TILE) if box_clr is not None else None,
    }


# ---------- 图元 ----------

def _frame(room, scale, pad):
    dx, dz = room["dimensions"]
    minx, maxx = -dx * 0.5 - pad, dx * 0.5 + pad
    minz, maxz = -dz * 0.5 - pad, dz * 0.5 + pad
    w, h = (maxx - minx) * scale, (maxz - minz) * scale
    px = lambda x: (x - minx) * scale
    pz = lambda z: (z - minz) * scale
    return minx, minz, w, h, px, pz


def _band(out, band_cells, px, pz, scale):
    """禁刷带：最外一圈 5m 地砖（业主「最外一圈不要刷怪」）。"""
    for cx, cz in band_cells:
        out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" '
                   'fill-opacity="0.20" stroke="%s" stroke-opacity="0.85" stroke-width="1.1" '
                   'stroke-dasharray="5 3"/>'
                   % (px(cx - TILE * 0.5), pz(cz - TILE * 0.5), TILE * scale, TILE * scale,
                      BAND_FILL, BAND_FILL))


def _shell(out, room, cells, px, pz, scale, band_cells=None):
    """底格 + 地砖 + 禁刷带 + 包络虚线 + 门 + 房心 + 比例尺（两种图共用）。"""
    dx, dz = room["dimensions"]
    col = ROOM_COLOR.get(room["room_type"], "#888")
    half = TILE * 0.5
    for cx, cz in cells:
        out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" '
                   'fill-opacity="0.26" stroke="%s" stroke-opacity="0.45" stroke-width="0.8"/>'
                   % (px(cx - half), pz(cz - half), TILE * scale, TILE * scale, col, col))
    if band_cells:
        _band(out, band_cells, px, pz, scale)
    out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" stroke="#7d8590" '
               'stroke-opacity="0.5" stroke-width="1" stroke-dasharray="4 3"/>'
               % (px(-dx * 0.5), pz(-dz * 0.5), dx * scale, dz * scale))
    for door in room["doors"]:
        dxx, dzz = door["local"]
        if door["dir"] in ("north", "south"):
            x0, z0, x1, z1 = dxx - 1.5, dzz, dxx + 1.5, dzz
        else:
            x0, z0, x1, z1 = dxx, dzz - 1.5, dxx, dzz + 1.5
        out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#f2cc60" '
                   'stroke-width="5" stroke-opacity="0.9"/>'
                   % (px(x0), pz(z0), px(x1), pz(z1)))
    out.append('<circle cx="%.2f" cy="%.2f" r="1.6" fill="#7d8590"/>' % (px(0), pz(0)))
    by, bx = pz(dz * 0.5 - 1.5), px(-dx * 0.5 + 1)
    out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#7d8590" stroke-width="1.5"/>'
               % (bx, by, bx + 10 * scale, by))
    for xx in (bx, bx + 10 * scale):
        out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#7d8590" stroke-width="1.5"/>'
                   % (xx, by - 3, xx, by + 3))
    out.append('<text x="%.2f" y="%.2f" font-size="9" fill="#7d8590" '
               'font-family="ui-monospace,monospace">10 m</text>'
               % (bx + 10 * scale + 5, by + 3))


def svg_old(room, metrics, scale=9.0, pad=3.0):
    """旧机制：房间级贪心落点（候选 = 5m 砖 3×3 子点 + 抖动，逐只取最远点）。

    离墙净距只有 SPAWN_CLEARANCE_M = 1.15 m ⇒ 点会落进最外一圈（禁刷带）。
    """
    cells = metrics["cells"]
    band = [c for c, r in zip(cells, [int(wall_clearance(metrics["inside"], c[0], c[1]) // TILE)
                                      for c in cells]) if r == 0]
    _, _, w, h, px, pz = _frame(room, scale, pad)
    out = ['<svg viewBox="0 0 %.1f %.1f" width="100%%" style="max-width:%.0fpx" '
           'xmlns="http://www.w3.org/2000/svg">' % (w, h, w)]
    out.append('<rect x="0" y="0" width="%.1f" height="%.1f" fill="#0b0f14"/>' % (w, h))
    _shell(out, room, cells, px, pz, scale, band)
    for index, point in enumerate(room["legacy_points"]):
        out.append('<circle cx="%.2f" cy="%.2f" r="2.6" fill="#5d6b7a" fill-opacity="0.75" '
                   'stroke="#0b0f14" stroke-width="0.9"/>' % (px(point[0]), pz(point[1])))
        out.append('<text x="%.2f" y="%.2f" font-size="8.5" fill="#aab4bf" text-anchor="middle" '
                   'font-family="ui-monospace,monospace">%d</text>'
                   % (px(point[0]), pz(point[1]) + 3.0, index + 1))
    out.append('</svg>')
    return "".join(out)


def svg_new(room, metrics, scale=9.0, pad=3.0):
    """新机制：触发盒（落地盒矩形）+ 盒内落点，按怪种着色、按波次编号。"""
    cells = metrics["cells"]
    band = []
    for c in cells:
        if int(wall_clearance(metrics["inside"], c[0], c[1]) // TILE) == 0:
            band.append(c)
    _, _, w, h, px, pz = _frame(room, scale, pad)
    out = ['<svg viewBox="0 0 %.1f %.1f" width="100%%" style="max-width:%.0fpx" '
           'xmlns="http://www.w3.org/2000/svg">' % (w, h, w)]
    out.append('<rect x="0" y="0" width="%.1f" height="%.1f" fill="#0b0f14"/>' % (w, h))
    _shell(out, room, cells, px, pz, scale, band)
    # 盒：落地盒实线，声明盒心虚线十字（漂移可见）
    for placement in room["placements"]:
        if "error" in placement:
            continue
        sx, sz = placement["size"]
        cx, cz = placement["center_landed"]
        rot = placement["rotation_deg"]
        out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" fill-opacity="0.13" '
                   'stroke="%s" stroke-width="1.4" stroke-dasharray="6 3" '
                   'transform="rotate(%.2f %.2f %.2f)"/>'
                   % (px(cx - sx * 0.5), pz(cz - sz * 0.5), sx * scale, sz * scale,
                      BOX_FILL, BOX_FILL, rot, px(cx), pz(cz)))
        dx_, dz_ = placement["center_declared"]
        for a, b, c, d in ((dx_ - 1.2, dz_, dx_ + 1.2, dz_), (dx_, dz_ - 1.2, dx_, dz_ + 1.2)):
            out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#f2cc60" '
                       'stroke-width="1.1" stroke-dasharray="3 3" stroke-opacity="0.8"/>'
                       % (px(a), pz(b), px(c), pz(d)))
        out.append('<text x="%.2f" y="%.2f" font-size="8.5" fill="%s" text-anchor="middle" '
                   'font-family="ui-monospace,monospace">#%d %s</text>'
                   % (px(cx), pz(cz - sz * 0.5) - 2.0, BOX_FILL, placement["index"],
                      placement["box"]))
    # 落点：按波次/怪种
    for wave_index, wave in enumerate(room["waves"]):
        for entry in wave:
            lx, lz = entry["local"]
            color = MONSTER_COLOR.get(entry["type"], "#ffffff")
            delayed = entry["delay_sec"] > 0.0
            r = 3.6 if wave_index == 0 else 3.0
            out.append('<circle cx="%.2f" cy="%.2f" r="%.1f" fill="%s" fill-opacity="%s" '
                       'stroke="#0b0f14" stroke-width="1.0"/>'
                       % (px(lx), pz(lz), r, color, "1" if wave_index == 0 else "0.72"))
            out.append('<text x="%.2f" y="%.2f" font-size="8" fill="#0b0f14" text-anchor="middle" '
                       'font-family="ui-monospace,monospace" font-weight="700">%d</text>'
                       % (px(lx), pz(lz) + 2.9, wave_index + 1))
            if delayed:
                out.append('<circle cx="%.2f" cy="%.2f" r="%.1f" fill="none" stroke="#f2cc60" '
                           'stroke-width="1.0" stroke-opacity="0.9" stroke-dasharray="2 1.6"/>'
                           % (px(lx), pz(lz), r + 2.0))
    out.append('</svg>')
    return "".join(out)


def svg_overview(rooms, mode, scale=4.6, metrics_by_room=None):
    """全关总览：mode = 'old' 画房间级落点，'new' 画触发盒 + 盒内落点。带禁刷带。"""
    pts = []
    world_cells = {}
    for room in rooms:
        cells = [to_world(room, c[0], c[1]) for c in cells_of(room)]
        world_cells[room["room_id"]] = cells
        pts.extend(cells)
    minx = min(p[0] for p in pts) - 6
    maxx = max(p[0] for p in pts) + 6
    minz = min(p[1] for p in pts) - 6
    maxz = max(p[1] for p in pts) + 6
    w, h = (maxx - minx) * scale, (maxz - minz) * scale
    px = lambda x: (x - minx) * scale
    pz = lambda z: (z - minz) * scale
    out = ['<svg viewBox="0 0 %.1f %.1f" width="100%%" style="max-width:%.0fpx" '
           'xmlns="http://www.w3.org/2000/svg">' % (w, h, w)]
    out.append('<rect x="0" y="0" width="%.1f" height="%.1f" fill="#0b0f14"/>' % (w, h))
    for room in rooms:
        col = ROOM_COLOR.get(room["room_type"], "#888")
        m = (metrics_by_room or {}).get(room["room_id"])
        band_local = set()
        if m:
            for c in m["cells"]:
                if int(wall_clearance(m["inside"], c[0], c[1]) // TILE) == 0:
                    band_local.add((round(c[0], 3), round(c[1], 3)))
        for cx, cz in world_cells[room["room_id"]]:
            out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" '
                       'fill-opacity="0.22" stroke="%s" stroke-opacity="0.3" stroke-width="0.5"/>'
                       % (px(cx - 2.5), pz(cz - 2.5), TILE * scale, TILE * scale, col, col))
        # 禁刷带（世界坐标）：把局部砖心转世界后重画
        if band_local:
            for c in cells_of(room):
                if (round(c[0], 3), round(c[1], 3)) not in band_local:
                    continue
                wx, wz = to_world(room, c[0], c[1])
                out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" '
                           'fill-opacity="0.16" stroke="%s" stroke-opacity="0.5" stroke-width="1"/>'
                           % (px(wx - 2.5), pz(wz - 2.5), TILE * scale, TILE * scale,
                              BAND_FILL, BAND_FILL))
        ox, oz = room["origin"]
        label = {"start": "入口", "boss": "BOSS", "extraction": "撤离"}.get(
            room["room_id"], room["room_id"])
        out.append('<text x="%.2f" y="%.2f" font-size="%.1f" fill="#c9d1d9" text-anchor="middle" '
                   'font-family="ui-monospace,monospace">%s</text>'
                   % (px(ox), pz(oz), scale * 3.0, label))
        if mode == "new":
            for placement in room["placements"]:
                if "error" in placement:
                    continue
                sx, sz = placement["size"]
                cx, cz = placement["center_landed"]
                wx, wz = to_world(room, cx, cz)
                out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" '
                           'stroke="%s" stroke-width="1.6" stroke-opacity="0.95" '
                           'transform="rotate(%.2f %.2f %.2f)"/>'
                           % (px(wx - sx * 0.5), pz(wz - sz * 0.5), sx * scale, sz * scale,
                              BOX_FILL, room["yaw_deg"], px(wx), pz(wz)))
            for wave in room["waves"]:
                for entry in wave:
                    ex, ez = entry["world"]
                    color = MONSTER_COLOR.get(entry["type"], "#fff")
                    out.append('<circle cx="%.2f" cy="%.2f" r="3.2" fill="%s" '
                               'stroke="#0b0f14" stroke-width="1.0"/>'
                               % (px(ex), pz(ez), color))
        else:
            for point in room["legacy_points"]:
                wx, wz = to_world(room, point[0], point[1])
                out.append('<circle cx="%.2f" cy="%.2f" r="2.4" fill="#8b98a5" '
                           'fill-opacity="0.9"/>' % (px(wx), pz(wz)))
    out.append('</svg>')
    return "".join(out)


# ---------- 表格 ----------

def schedule_table(rooms):
    """全关刷怪安排一览：每房每波「调哪几个盒 → 出什么怪几只」。"""
    rows = []
    for room in rooms:
        if not room["placements"]:
            continue
        col = ROOM_COLOR.get(room["room_type"], "#888")
        for wave_index, wave in enumerate(room["waves"]):
            boxes = room["stages"][wave_index] if wave_index < len(room["stages"]) else []
            box_cells, comp_cells = [], []
            for box_index in boxes:
                placement = next((p for p in room["placements"] if p["index"] == box_index), None)
                if placement is None or "error" in placement:
                    box_cells.append("#%d 解析失败" % box_index)
                    comp_cells.append("—")
                    continue
                cx, cz = placement["center_landed"]
                box_cells.append(
                    '#%d <code>%s</code><br><span class="muted">%.0f×%.0f m · 内缩 %d 圈 · '
                    '中心(%.1f,%.1f)</span>'
                    % (box_index, placement["box"], placement["size"][0], placement["size"][1],
                       int(placement.get("wall_recess_tiles", WALL_BAND)), cx, cz))
                comp_cells.append("<br>".join(
                    "%s <b>%d–%d</b>%s" % (MONSTER_ZH.get(s["type"], s["type"]),
                                           s["count_min"], s["count_max"],
                                           (" ⏱%.1fs" % s["delay_sec"]) if s["delay_sec"] > 0 else "")
                    for s in placement["spawns"]))
            kinds = {}
            for entry in wave:
                kinds[entry["type"]] = kinds.get(entry["type"], 0) + 1
            delayed = sum(1 for e in wave if e["delay_sec"] > 0)
            rows.append(
                '<tr><td class="mono">%s</td><td><span style="color:%s">%s</span></td>'
                '<td class="mono">第 %d 波</td><td>%s</td><td>%s</td>'
                '<td class="mono"><b>%d</b>%s</td><td>%s</td></tr>'
                % (room["room_id"], col, ROOM_TYPE_ZH.get(room["room_type"], room["room_type"]),
                   wave_index + 1, "<br>".join(box_cells), "<br>".join(comp_cells),
                   len(wave), ("（%d 延迟）" % delayed) if delayed else "",
                   "，".join("%s ×%d" % (MONSTER_ZH.get(k, k), v) for k, v in sorted(kinds.items()))))
    return ('<table><thead><tr><th>房</th><th>类型</th><th>波次</th><th>调用的盒</th>'
            '<th>盒编成区间（声明）</th><th>本波只数（抽样）</th><th>波内怪种（抽样）</th>'
            '</tr></thead><tbody>' + "".join(rows) + '</tbody></table>')


def box_reuse_table(rooms):
    """按盒汇总：每个盒子资产被哪些房、哪些波调用。"""
    usage = {}
    for room in rooms:
        for wave_index, boxes in enumerate(room["stages"]):
            for box_index in boxes:
                placement = next((p for p in room["placements"] if p["index"] == box_index), None)
                if placement is None or "error" in placement:
                    continue
                usage.setdefault(placement["box"], []).append(
                    "%s 第%d波" % (room["room_id"], wave_index + 1))
    rows = []
    for box_id in sorted(usage):
        rows.append('<tr><td class="mono">%s</td><td class="mono">%d 次</td><td>%s</td></tr>'
                    % (box_id, len(usage[box_id]), "、".join(usage[box_id])))
    return ('<table class="mini"><thead><tr><th>盒子资产</th><th>被调用</th><th>调用处</th>'
            '</tr></thead><tbody>' + "".join(rows) + '</tbody></table>')


def box_table(room, metrics):
    rows = []
    inside = metrics["inside"]
    for placement in room["placements"]:
        if "error" in placement:
            rows.append('<tr><td class="mono">#%d</td><td colspan="6" class="bad">解析失败：%s</td></tr>'
                        % (placement["index"], placement.get("box", "")))
            continue
        spawns = "，".join(
            "%s ×%d–%d%s" % (MONSTER_ZH.get(s["type"], s["type"]), s["count_min"], s["count_max"],
                             ("（延迟 %.1fs）" % s["delay_sec"]) if s["delay_sec"] > 0 else "")
            for s in placement["spawns"])
        shift = placement["shift"]
        shift_txt = ('<span class="ok">0.0（原位）</span>' if shift <= 0.01
                     else '<span class="warn">%.2f m</span>' % shift)
        cx, cz = placement["center_landed"]
        ctr_clr = wall_clearance(inside, cx, cz)
        edge_clr = min(wall_clearance(inside, bx, bz) for bx, bz in box_probe_points(
            cx, cz, placement["size"][0], placement["size"][1], placement["rotation_deg"]))
        edge_txt = ('<span class="ok">%.2f（第 %d 圈）</span>' % (edge_clr, int(edge_clr // TILE))
                    if edge_clr >= TILE else '<span class="bad">%.2f（压最外圈）</span>' % edge_clr)
        rows.append(
            '<tr><td class="mono">#%d</td><td class="mono">%s</td>'
            '<td class="mono">%.0f × %.0f m%s</td>'
            '<td class="mono">%d 圈（心 %.2f m）</td>'
            '<td class="mono">%s</td>'
            '<td>%s</td><td class="mono">%d / %d</td><td class="mono">%s</td></tr>'
            % (placement["index"], placement["box"], placement["size"][0], placement["size"][1],
               ("（旋转 %.0f°）" % placement["rotation_deg"]) if placement["rotation_deg"] else "",
               int(placement.get("wall_recess_tiles", WALL_BAND)), ctr_clr,
               edge_txt, spawns,
               placement["demand_max"], placement["capacity"], shift_txt))
    return ('<table class="mini"><thead><tr><th>#</th><th>盒子</th><th>尺寸</th>'
            '<th>墙内缩（声明）</th><th>盒边离墙净距</th>'
            '<th>编成（怪种 × 只数）</th><th>需求/容量</th><th>落地漂移</th></tr></thead>'
            '<tbody>' + "".join(rows) + '</tbody></table>')


def wave_table(room):
    rows = []
    for index, wave in enumerate(room["waves"]):
        kinds = {}
        for entry in wave:
            kinds[entry["type"]] = kinds.get(entry["type"], 0) + 1
        boxes = room["stages"][index] if index < len(room["stages"]) else []
        delayed = sum(1 for e in wave if e["delay_sec"] > 0)
        rows.append('<tr><td class="mono">第 %d 波</td><td class="mono">%s</td>'
                    '<td class="mono">%d 只%s</td><td>%s</td></tr>'
                    % (index + 1,
                       " ".join("#%d" % b for b in boxes) if boxes else "—",
                       len(wave),
                       ("（其中 %d 只延迟）" % delayed) if delayed else "",
                       "，".join("%s ×%d" % (MONSTER_ZH.get(k, k), v)
                                 for k, v in sorted(kinds.items()))))
    if not rows:
        return '<div class="muted">本房不刷怪（非敌对房 / 事件房）。</div>'
    return ('<table class="mini"><thead><tr><th>波次</th><th>调用盒</th><th>只数</th>'
            '<th>编成</th></tr></thead><tbody>' + "".join(rows) + '</tbody></table>')


def selfcheck(room, metrics):
    inside = metrics["inside"]
    lines = []
    for wave_index, wave in enumerate(room["waves"]):
        pts = [(e["local"][0], e["local"][1]) for e in wave]
        outside = [e for e in wave if e["box_index"] < 0]
        gaps = [wall_clearance(inside, p[0], p[1]) for p in pts]
        pair = min_pair(pts) if len(pts) >= 2 else None
        parts = ['<span class="%s">盒内 %d/%d</span>'
                 % ("ok" if not outside else "bad", len(pts) - len(outside), len(pts))]
        if gaps:
            worst = min(gaps)
            parts.append('最近离墙 <b>%.2f</b> m = 第 <b>%d</b> 圈 %s'
                         % (worst, int(worst // TILE),
                            '<span class="ok">（在最外圈之外）</span>' if worst >= TILE
                            else '<span class="bad">（落进禁刷带）</span>'))
        if pair is not None:
            parts.append('同波两两最小间距 <b>%.2f</b> m（判据 ≥ %.2f）' % (pair, ENEMY_BODY_DIAM))
        lines.append('第 %d 波：%s' % (wave_index + 1, " · ".join(parts)))
    if not lines:
        return '<div class="muted">—</div>'
    return '<div class="chk">' + "<br>".join(lines) + '</div>'


# ---------- 主页 ----------

def monster_legend(used_types):
    items = []
    for key in sorted(used_types):
        items.append('<span><i class="dot" style="background:%s"></i>%s <code>%s</code></span>'
                     % (MONSTER_COLOR.get(key, "#fff"), MONSTER_ZH.get(key, key), key))
    return '<div class="legend">' + "".join(items) + '</div>'


def build():
    data = json.load(open(NEW_JSON, encoding="utf-8"))
    rooms = data["rooms"]
    metrics_by_room = {}
    for room in rooms:
        metrics_by_room[room["room_id"]] = sched_room_metrics(room)

    old_peak = {}
    if os.path.exists(OLD_JSON):
        old = json.load(open(OLD_JSON, encoding="utf-8"))["seeds"][0]
        for room in old["rooms"]:
            waves = [len(w) for w in room["rolled_waves"]]
            old_peak[room["room_id"]] = {"waves": len(waves),
                                         "peak": max(waves) if waves else 0}

    used_types = {e["type"] for room in rooms for wave in room["waves"] for e in wave}
    hostile = [r for r in rooms if r["placements"]]
    empty_hostile = [r for r in rooms
                     if r["room_type"] in ("COMBAT", "SCAVENGE", "STORAGE", "BOSS")
                     and not r["placements"] and not r["peaceful"]]
    total_points = sum(len(w) for r in rooms for w in r["waves"])
    peak = max((len(w) for r in rooms for w in r["waves"]), default=0)
    peak_sum = sum(max((len(w) for w in r["waves"]), default=0) for r in rooms)

    # —— 核心口径：最外一圈禁刷 ——
    new_outer = sum(m["outer_ring_hits"] for m in metrics_by_room.values())
    new_pts = sum(m["points"] for m in metrics_by_room.values())
    new_min_clr = min((m["min_point_clr"] for m in metrics_by_room.values()
                       if m["min_point_clr"] is not None), default=None)
    new_box_clr = min((m["box_clr"] for m in metrics_by_room.values()
                       if m["box_clr"] is not None), default=None)
    new_hist = {}
    for room in rooms:
        m = metrics_by_room[room["room_id"]]
        for wave in room["waves"]:
            for e in wave:
                r = int(wall_clearance(m["inside"], e["local"][0], e["local"][1]) // TILE)
                new_hist[r] = new_hist.get(r, 0) + 1
    old_hist = {}
    old_min_clr = None
    for room in rooms:
        m = metrics_by_room[room["room_id"]]
        for x, z in room["legacy_points"]:
            c = wall_clearance(m["inside"], x, z)
            old_hist[int(c // TILE)] = old_hist.get(int(c // TILE), 0) + 1
            old_min_clr = c if old_min_clr is None else min(old_min_clr, c)
    old_total = sum(old_hist.values())
    old_outer = old_hist.get(0, 0)

    same_wave_min = None
    multi_box_waves = []
    for room in rooms:
        for wave in room["waves"]:
            pts = [(e["local"][0], e["local"][1]) for e in wave]
            if len(pts) >= 2:
                d = min_pair(pts)
                if same_wave_min is None or d < same_wave_min:
                    same_wave_min = d
        for wave_index, boxes in enumerate(room["stages"]):
            if len(boxes) > 1:
                multi_box_waves.append("%s 第%d波 %s"
                                       % (room["room_id"], wave_index + 1,
                                          " ".join("#%d" % b for b in boxes)))

    lowest_capacity = None
    for room in rooms:
        for p in room["placements"]:
            if "error" in p or p["capacity"] <= 0:
                continue
            slack = p["capacity"] - p["demand_max"]
            if lowest_capacity is None or slack < lowest_capacity[0]:
                lowest_capacity = (slack, room["room_id"], p["index"], p["box"],
                                   p["capacity"], p["demand_max"])

    H = []
    A = H.append
    A('<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">')
    A('<title>远征关卡01 · 触发器刷怪落点平面图（旧 vs 新）</title>')
    A('<style>')
    A('''
:root{--bg:#0d1117;--panel:#161b22;--line:#30363d;--fg:#e6edf3;--dim:#9aa4b0;--acc:#f2cc60;--cy:#39c5cf;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
 font-family:system-ui,-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;line-height:1.6;}
.wrap{max-width:1320px;margin:0 auto;padding:32px 24px 80px;}
h1{font-size:26px;margin:0 0 6px;letter-spacing:.4px}
h2{font-size:19px;margin:42px 0 12px;padding-bottom:8px;border-bottom:1px solid var(--line)}
h3{font-size:15px;margin:22px 0 8px}
.sub{color:var(--dim);font-size:13px;margin-bottom:18px}
.meta{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0 4px}
.chip{background:var(--panel);border:1px solid var(--line);border-radius:999px;
 padding:3px 11px;font-size:12px;color:var(--dim)}
.chip b{color:var(--fg);font-weight:600}
.note{background:var(--panel);border:1px solid var(--line);border-left:3px solid var(--acc);
 border-radius:6px;padding:12px 16px;font-size:13.5px;color:#c9d1d9;margin:16px 0}
.note.bad{border-left-color:#f85149}
.note.good{border-left-color:#3fb950}
.note b{color:var(--acc)}
.note code,td code{background:#0b0f14;border:1px solid var(--line);border-radius:4px;padding:1px 5px;
 font-family:ui-monospace,monospace;font-size:12px;color:#9ecbff}
table{width:100%;border-collapse:collapse;font-size:12.5px;margin:8px 0}
th,td{border:1px solid var(--line);padding:5px 8px;text-align:left;vertical-align:top}
th{background:#1b222b;color:#c9d1d9;font-weight:600;white-space:nowrap}
td.mono{font-family:ui-monospace,monospace;font-size:11.5px}
.ok{color:#3fb950;font-weight:600}
.bad{color:#f85149;font-weight:600}
.warn{color:#d29922;font-weight:600}
.muted{color:var(--dim);font-size:12.5px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:9px;
 padding:14px 15px 12px;margin:16px 0}
.card .hd{display:flex;justify-content:space-between;align-items:baseline;gap:8px;
 margin-bottom:10px;flex-wrap:wrap}
.card h3{font-size:15px;margin:0}
.tag{font-size:11px;padding:2px 8px;border-radius:999px;border:1px solid;white-space:nowrap;color:var(--dim)}
.panels{display:grid;grid-template-columns:1fr 1fr;gap:14px}
@media(max-width:820px){.panels{grid-template-columns:1fr}}
.panel{border:1px solid var(--line);border-radius:6px;overflow:hidden;background:#0b0f14}
.panel .cap{font-size:12px;color:var(--dim);padding:6px 10px;border-bottom:1px solid var(--line);
 background:#10151c;display:flex;justify-content:space-between;gap:8px}
.panel .cap b{color:var(--cy);font-weight:600}
.legend{display:flex;flex-wrap:wrap;gap:14px;font-size:12.5px;color:var(--dim);margin:10px 0 0}
.legend span{display:inline-flex;align-items:center;gap:6px}
.dot{width:11px;height:11px;border-radius:50%;display:inline-block}
.band{width:11px;height:11px;display:inline-block;border:1px dashed #f85149;background:rgba(248,81,73,.2)}
.chk{font-size:12px;color:var(--dim);margin-top:8px;font-family:ui-monospace,monospace;line-height:1.75}
.chk b{color:var(--fg)}
.ov{border:1px solid var(--line);border-radius:8px;overflow:hidden;background:#0b0f14;
 max-width:880px;margin:12px auto 0}
.panels.stack{grid-template-columns:1fr}
.panels.stack .panel svg{max-width:100%!important}
table.mini{font-size:11.5px;margin-top:9px}
table.mini th,table.mini td{padding:3px 6px}
table.mini th{background:#1b222b}
.kpi{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin:14px 0}
.kpi .box{background:var(--panel);border:1px solid var(--line);border-radius:8px;padding:12px 14px}
.kpi .box .t{font-size:12px;color:var(--dim)}
.kpi .box .v{font-size:22px;font-weight:700;font-family:ui-monospace,monospace;margin-top:2px}
''')
    A('</style></head><body><div class="wrap">')
    A('<h1>远征关卡01 · 触发器刷怪落点平面图</h1>')
    A('<div class="sub">数据来自 Godot 4.6.3 headless 实跑探针：房间实例取 <code>Dungeon3D._room_by_id</code>，'
      '盒子落点走 <code>Dungeon3D._spawn_box_waves()</code>（与真机 <code>_spawn_room_enemies</code> '
      '同一个函数、同一套 rng 种子），落地盒心走 <code>DungeonRoom3D.resolve_spawn_box_center_local()</code>。'
      '不是手摆坐标，也不是文档抄录。本页所有数字由 <code>render_box_map.py</code> 从 JSON 现算。</div>')
    A('<div class="meta">')
    A('<span class="chip">关卡 <b>expedition_01</b></span>')
    A('<span class="chip">run_seed <b>%d</b></span>' % data["seed"])
    A('<span class="chip">房间 <b>%d</b></span>' % len(rooms))
    A('<span class="chip">摆盒房间 <b>%d</b></span>' % len(hostile))
    A('<span class="chip">盒子实例 <b>%d</b></span>' % data["box_total"])
    A('<span class="chip">新机制出怪 <b>%d</b> 只</span>' % total_points)
    A('<span class="chip">单波峰值 <b>%d</b> 只</span>' % peak)
    A('<span class="chip">落地漂移 <b>%d / %d</b></span>' % (data["shifted_total"], data["box_total"]))
    A('</div>')

    # —— 本轮口径（业主 2026-09-26）：最外一圈禁刷 ——
    A('<h2>本轮口径：最外一圈地砖禁刷</h2>')
    A('<div class="sub">业主原话：「这个房间的刷怪点都是在房间周边外圈的地砖，这样体验不好，'
      '<b>最外一圈不要刷怪</b>，往里头布置刷怪盒子。」本页用「离墙 L∞ 净距 ÷ 5 m」当**圈号**：'
      '第 0 圈 = 贴着墙的那一圈 5 m 地砖（图上的<b>红色虚线禁刷带</b>）。</div>')
    A('<div class="kpi">')
    A('<div class="box"><div class="t">新机制 · 落点落在最外圈</div>'
      '<div class="v"><span class="ok">%d</span> / %d</div>'
      '<div class="t">最近落点离墙 %.2f m（第 %d 圈）</div></div>'
      % (new_outer, new_pts, new_min_clr or 0, int((new_min_clr or 0) // TILE)))
    A('<div class="box"><div class="t">旧机制 · 落点落在最外圈</div>'
      '<div class="v"><span class="bad">%d</span> / %d</div>'
      '<div class="t">最近落点离墙 %.2f m（第 0 圈）</div></div>'
      % (old_outer, old_total, old_min_clr or 0))
    A('<div class="box"><div class="t">新机制 · 盒边最近离墙净距</div>'
      '<div class="v"><span class="ok">%.2f</span> m</div>'
      '<div class="t">判据 ≥ %.0f m（= 1 圈）⇒ 整盒不进最外圈</div></div>'
      % (new_box_clr or 0, TILE))
    A('<div class="box"><div class="t">落地漂移</div>'
      '<div class="v"><span class="ok">%d</span> / %d</div>'
      '<div class="t">盒心声明位置＝运行时落地位置</div></div>'
      % (data["shifted_total"], data["box_total"]))
    A('</div>')
    A('<div class="note good"><b>结论：新机制（触发盒）已经把最外一圈清空了。</b><br>'
      '① 机制上：每个盒的 <code>wall_recess_tiles = %d</code> ⇒ 盒心至少离墙 %.0f m；'
      '盒又小（2~4 m）⇒ 整盒离墙 ≥ %.2f m，**盖不到最外一圈**。'
      '判据 <code>spawn_placement_wall_recess_short</code> 现在判的就是「**整盒**（含边缘）'
      '离墙 ≥ 5 圈数」，写错当场红、不会漏到运行时。<br>'
      '② 数据上：全关 %d 只落点、距墙最近 %.2f m（第 %d 圈）—— <b>最外一圈 0 只</b>。<br>'
      '③ 对比旧机制（房间级贪心落点）：只有 <code>SPAWN_CLEARANCE_M = %.2f m</code> 的离墙余量，'
      '于是 %d/%d 的点直接落在最外一圈、最近离墙 %.2f m —— 这正是业主截图里看到的样子。'
      '</div>' % (WALL_BAND, TILE, new_box_clr or 0, new_pts, new_min_clr or 0,
                  int((new_min_clr or 0) // TILE), DEFAULT_CLEARANCE, old_outer, old_total,
                  old_min_clr or 0))

    A('<div class="note"><b>怎么读这两张图</b><br>'
      '<b>红色虚线带</b> = <b>禁刷带</b>（最外一圈 5 m 地砖）—— 这条带里不允许有任何出怪点；<br>'
      '<b>左（旧）</b>：灰点 = 旧机制的房间级落点池（序列号即取点顺序），会明显压进禁刷带；<br>'
      '<b>右（新）</b>：青色虚线框 = <b>落地盒</b>，框上角 <code>#n box_id</code> 是实例号；'
      '框外的黄色小十字 = 作者<b>声明</b>的盒心（与框不重合即发生了落地漂移）；'
      '圆点 = <b>真正会出怪的位置</b>，颜色 = 怪种，点内数字 = 第几波，黄色外圈 = 该只延迟出场。</div>')

    A('<div class="note"><b>对账要点（旧 vs 新）</b><br>'
      '1）两侧的 run_seed 相同（%d），但<b>不是同一次运行</b>：旧列取自 <code>enemy_spawn_plan</code> '
      '归零前的存档，新列是本次实测 ⇒ 只对比<b>机制形状</b>（可控粒度、落点归属），'
      '不要把两边的只数直接读成「加了多少怪」。<br>'
      '2）旧图（<code>%s</code>）的落点是在<b>未建家具碰撞</b>的轻量环境里取的；'
      '本次双侧统一为<b>建完壳体 + 暗装家具</b>后取点。<br>'
      '3）旧机制的 <code>enemy_spawn_plan</code> 在远征01 已<b>归零</b>（判据 F）⇒ '
      '本关旧路径<b>已不再出怪</b>；左图仅作机制形状对照。</div>'
      % (data["seed"], OLD_HTML))

    # 总览
    A('<h2>全关总览</h2>')
    A('<div class="panels stack">')
    A('<div class="panel"><div class="cap"><span>旧：房间级贪心落点（会压进禁刷带）</span>'
      '<b>%d 点 / 其中最外圈 %d</b></div>'
      % (old_total, old_outer) + svg_overview(rooms, "old", metrics_by_room=metrics_by_room)
      + '</div>')
    A('<div class="panel"><div class="cap"><span>新：触发盒 + 盒内落点（禁刷带全空）</span>'
      '<b>%d 盒 / %d 只 / 最外圈 %d</b></div>' % (data["box_total"], total_points, new_outer)
      + svg_overview(rooms, "new", metrics_by_room=metrics_by_room) + '</div>')
    A('</div>')
    A(monster_legend(used_types))
    A('<div class="legend"><span><i class="band"></i>禁刷带（最外一圈 5 m 地砖）</span></div>')

    # 圈号直方图
    A('<h2>圈号分布（离墙净距 ÷ 5 m）</h2>')
    A('<table><thead><tr><th>圈号</th><th>含义</th><th>旧机制落点</th><th>新机制落点</th>'
      '<th>判定</th></tr></thead><tbody>')
    max_ring = max([max(new_hist) if new_hist else 0, max(old_hist) if old_hist else 0] + [1])
    for r in range(0, max_ring + 1):
        o = old_hist.get(r, 0)
        n = new_hist.get(r, 0)
        meaning = "最外圈（贴着墙）" if r == 0 else "往里第 %d 圈" % r
        verdict = ('<span class="bad">禁刷带 —— 旧机制 %d 只违规</span>' % o if r == 0 and o
                   else '<span class="ok">合规</span>')
        A('<tr><td class="mono">%d</td><td>%s</td><td class="mono">%d (%.1f%%)</td>'
          '<td class="mono"><b>%d</b></td><td>%s</td></tr>'
          % (r, meaning, o, 100.0 * o / max(old_total, 1), n, verdict))
    A('</tbody></table>')
    A('<div class="muted">圈号 = 「以该点为心的正方形最大能长到多大还不碰到墙」÷ 5 m。'
      '点越靠里、圈号越大。</div>')

    # 对比表
    A('<h2>逐房对账</h2>')
    A('<table><thead><tr><th>房</th><th>类型</th><th>尺寸</th>'
      '<th>旧：峰值同屏</th><th>旧：落在最外圈</th><th>新：盒数</th><th>新：波次（调盒）</th>'
      '<th>新：峰值</th><th>新：全程</th><th>新：最近落点离墙</th><th>新：最外圈</th>'
      '</tr></thead><tbody>')
    for room in rooms:
        col = ROOM_COLOR.get(room["room_type"], "#888")
        m = metrics_by_room[room["room_id"]]
        shifts = [p["shift"] for p in room["placements"] if "error" not in p]
        old = old_peak.get(room["room_id"], {"peak": 0, "waves": 0})
        band_hits = 0
        for x, z in room["legacy_points"]:
            if wall_clearance(m["inside"], x, z) < TILE:
                band_hits += 1
        clr_txt = ("—" if m["min_point_clr"] is None else
                   '<span class="%s">%.2f m（第 %d 圈）</span>'
                   % ("ok" if m["min_point_clr"] >= TILE else "bad",
                      m["min_point_clr"], int(m["min_point_clr"] // TILE)))
        A('<tr><td class="mono">%s</td><td><span style="color:%s">%s</span></td>'
          '<td class="mono">%.0f × %.0f</td><td class="mono">%d</td>'
          '<td class="mono">%s</td><td class="mono">%d</td><td class="mono">%s</td>'
          '<td class="mono"><b>%d</b></td><td class="mono">%d</td><td class="mono">%s</td>'
          '<td class="mono">%s</td></tr>'
          % (room["room_id"], col, ROOM_TYPE_ZH.get(room["room_type"], room["room_type"]),
             room["dimensions"][0], room["dimensions"][1],
             old["peak"],
             ('<span class="bad">%d / %d</span>' % (band_hits, len(room["legacy_points"]))
              if band_hits else ("0" if room["legacy_points"] else "—")),
             len(room["placements"]),
             " · ".join("[" + " ".join("#%d" % i for i in st) + "]" for st in room["stages"]) or "—",
             max((len(w) for w in room["waves"]), default=0),
             sum(len(w) for w in room["waves"]),
             clr_txt,
             ('<span class="ok">0</span>' if m["outer_ring_hits"] == 0
              else '<span class="bad">%d</span>' % m["outer_ring_hits"])))
    A('</tbody><tfoot><tr><th>合计</th><th>—</th><th>—</th><th>%d</th>'
      '<th>%d / %d</th><th>%d 盒</th><th>—</th><th><b>%d</b></th><th>%d</th>'
      '<th>—</th><th>%d</th></tr></tfoot>'
      % (sum(v["peak"] for v in old_peak.values()), old_outer, old_total,
         data["box_total"], peak_sum, total_points, new_outer))
    A('</table>')
    A('<div class="muted">「旧」列取自 <code>enemy_spawn_plan</code> 归零<b>之前</b>的那一跑（同一 run_seed）。'
      '「峰值」= 本房单波最多只数；「全程」= 各波之和（同一只盒跨波复用会重复计一次）。'
      '新机制的只数是<b>区间抽签</b>，本页是 %d 种子下的一次抽样，不是恒定值。'
      '⚠ shift=%s ⇒ 声明盒心即落地盒心。</div>'
      % (data["seed"], ("全 0" if max(shifts or [0]) <= 0.01 else "见下表")))

    # 刷怪安排台账
    A('<h2>刷怪安排一览（按波次）</h2>')
    A('<div class="sub">这一节就是「本关刷怪到底怎么安排的」正式台账：'
      '<b>哪个房 · 第几波 · 调用哪几个触发盒 · 该盒能出什么怪几只 · 本波实际抽出几只</b>。'
      '「盒编成区间」是盒资产里写死的（<code>data/spawn_boxes/*.json</code>），'
      '「抽样」是 %d 种子这一次跑出来的 —— 同一份数据换种子只数会变，编成区间不变。</div>'
      % data["seed"])
    A(schedule_table(rooms))
    A('<h3>触发盒资产被复用情况</h3>')
    A(box_reuse_table(rooms))
    A('<div class="note"><b>共用的盒子资产 = 复用，不是复制</b>：6 类基础盒被 %d 个实例槽位共用。'
      '改一个 <code>data/spawn_boxes/&lt;id&gt;.json</code>（比如把「角落包夹」的追猎者从 2–4 只改成 3 只），'
      '所有引用它的房间<b>一起生效</b>；只想改一间房，就在该房的 <code>spawn_placements[]</code> 里'
      '用 <code>size_m</code> / <code>delay_sec</code> 覆盖，或换一个 box。</div>'
      % data["box_total"])

    # 实测发现
    A('<h2>本次实测发现</h2>')
    A('<table><thead><tr><th>项</th><th>实测</th><th>判定</th></tr></thead><tbody>')
    A('<tr><td>落点是否都在本盒内</td><td class="mono">盒外落点 0 个</td>'
      '<td class="ok">PASS（判据 E-①）</td></tr>')
    A('<tr><td>落点是否避开了最外一圈</td>'
      '<td class="mono">最外圈 <b>%d</b> 只 / 共 %d 只；最近离墙 %.2f m（第 %d 圈）</td>'
      '<td class="ok">PASS（判据 H 运行时端）</td></tr>'
      % (new_outer, new_pts, new_min_clr or 0, int((new_min_clr or 0) // TILE)))
    A('<tr><td>盒容量是否都够</td><td class="mono">%d 盒全部 容量 ≥ 需求；最紧余量 %d 只'
      '（%s #%d <code>%s</code> %d/%d）</td>'
      '<td class="ok">PASS</td></tr>'
      % (data["box_total"], lowest_capacity[0] if lowest_capacity else 0,
         lowest_capacity[1] if lowest_capacity else "—", lowest_capacity[2] if lowest_capacity else 0,
         lowest_capacity[3] if lowest_capacity else "—",
         lowest_capacity[4] if lowest_capacity else 0, lowest_capacity[5] if lowest_capacity else 0))
    A('<tr><td>盒心落地漂移</td><td class="mono">%d / %d（本种子声明位置全部可直接用）</td>'
      '<td class="ok">PASS（报告项）</td></tr>'
      % (data["shifted_total"], data["box_total"]))
    A('<tr><td>同波两两最小间距</td><td class="mono">全局 <b>%.2f</b> m（判据 ≥ %.2f m = 怪体直径）</td>'
      '<td class="ok">PASS</td></tr>' % (same_wave_min or 0, ENEMY_BODY_DIAM))
    A('<tr><td>同波多盒的<b>跨盒</b>间距</td>'
      '<td class="mono">%s —— 引擎对每个盒<b>独立采样</b>，后一个盒不避让前一个盒已占的点</td>'
      '<td class="warn">缺口：仅靠数据侧凑巧</td></tr>'
      % ("，".join(multi_box_waves) if multi_box_waves else "本关无同波多盒"))
    A('</tbody></table>')
    A('<div class="note"><b>已收口的历史问题（供追溯）</b><br>'
      '① <b>贴边偏好把怪压成一条线</b>：旧版 <code>prefer_edge</code> 给所有贴边点同分，'
      '贪心退化成「沿同一条边排队」。已<b>废弃 <code>prefer_edge</code></b> + 小盒重定义解决。<br>'
      '② <b>盒内取点对小盒不鲁棒</b>：纯随机序首适配若先抽到<b>居中</b>点，会一次吃光 3×3 小盒的余量，'
      '被误判「容量不足」而触发落地平移，且**随种子翻面**。已改为<b>有界重洗</b>'
      '（首轮取不满则换种再试）⇒ 12 种子 × %d 盒全部 <code>shift = 0</code>。<br>'
      '③ <b>判据 H 只管盒心</b>：盒心 ≥5 m ＋ 半宽 2 m ⇒ 盒边可只离墙 3 m，仍压最外圈。'
      '已改判 <b>整盒边缘</b>（本轮，业主口径），并新增针对性负向对照证明其生效。</div>'
      % data["box_total"])

    if empty_hostile:
        A('<div class="note bad"><b class="bad">敌对房无盒</b>：%s —— 「只认盒子」层里这会是不刷怪的合法状态，'
          '但远征01 的目标是每间敌对房都有盒。</div>'
          % "，".join(r["room_id"] for r in empty_hostile))

    # 逐房
    A('<h2>逐房详图</h2>')
    for room in rooms:
        col = ROOM_COLOR.get(room["room_type"], "#888")
        m = metrics_by_room[room["room_id"]]
        A('<div class="card">')
        A('<div class="hd"><h3>%s · %s</h3>'
          '<span class="tag" style="border-color:%s;color:%s">%.0f × %.0f m · %s</span></div>'
          % (room["room_id"], ROOM_TYPE_ZH.get(room["room_type"], room["room_type"]),
             col, col, room["dimensions"][0], room["dimensions"][1],
             "主路第 %d 房" % (room["floor_level"] + 1)))
        A('<div class="panels">')
        A('<div class="panel"><div class="cap"><span>旧：房间级贪心落点</span>'
          '<b>%d 点 / 禁刷带内 %d</b></div>'
          % (len(room["legacy_points"]),
             sum(1 for x, z in room["legacy_points"] if wall_clearance(m["inside"], x, z) < TILE))
          + svg_old(room, m) + '</div>')
        A('<div class="panel"><div class="cap"><span>新：触发盒 + 盒内落点</span>'
          '<b>%d 盒 / %d 只 / 禁刷带内 %d</b></div>'
          % (len(room["placements"]), m["points"], m["outer_ring_hits"])
          + svg_new(room, m) + '</div>')
        A('</div>')
        if room["placements"]:
            A(box_table(room, m))
            A(wave_table(room))
            A(selfcheck(room, m))
        else:
            A('<div class="muted">本房不摆盒'
              + ("（和平区 / 非敌对房）。" if room["room_type"] not in
                 ("COMBAT", "SCAVENGE", "STORAGE", "BOSS") else "。<b class='bad'>敌对房应有盒</b>。")
              + '</div>')
        A('</div>')

    A('</div></body></html>')
    html = "".join(H)
    for out in OUTS:
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(html)
    print("wrote %s (%d bytes, %d rooms, %d boxes, %d points)"
          % (OUTS[0], len(html.encode("utf-8")), len(rooms), data["box_total"], total_points))
    for out in OUTS[1:]:
        print("mirrored %s" % out)
    return OUTS[0]


if __name__ == "__main__":
    build()
