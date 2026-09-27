"""远征关卡01 · 刷怪位置示意图（**只看新机制 · 以 5m 地砖为单位**）。

业主口径（2026-09-26）：
  · 「不需要旧机制对比，给我新机制下的情况就好了」；
  · 「哪些砖块会刷怪用点标明出来即可」；
  · 「最外一圈不要刷怪」（判据 H 已由判盒心收紧为判盒边）。

图上把每块 5 m 地砖当判定单位，四类格子：
  ① **实际出怪的砖**（本次实测）—— 彩色填充 + **砖心圆点**，点内数字 = 该砖出几只怪；
  ② **刷怪盒范围内的砖** —— 淡青（怪只可能在这些砖上出现，但本次不一定会用满）；
  ③ **最外一圈的砖** —— 淡红，按业主口径 **禁止刷怪**；
  ④ **无地砖处**（结构缺口，如 L 型走廊的转角外）—— 打叉，避免误读成「能走但没刷怪」。

数据源：
  · `spawn_box_map.json`（同目录运行时探针实测，非文档抄录）
  · `floor_00.json`（仅取每房 `template_id` / `template_variant`，用于解释房间轮廓形状）

输出：ShellStorm2/outputs/expedition01_spawn_boxes.html（并镜像到工作区根的 outputs/）。
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
WORKSPACE = os.path.abspath(os.path.join(REPO, ".."))
NEW_JSON = os.path.join(HERE, "spawn_box_map.json")
FLOOR_JSON = os.path.join(REPO, "source", "art", "whitebox", "tower_zones",
                          "expedition_01", "v001", "data", "floors", "floor_00.json")
OUTS = [os.path.join(REPO, "outputs", "expedition01_spawn_boxes.html"),
        os.path.join(WORKSPACE, "outputs", "expedition01_spawn_boxes.html")]

TILE = 5.0
BG = "#0d1117"
PANEL = "#161b22"
LINE = "#30363d"
MUTED = "#8b949e"
TEXT = "#c9d1d9"
HOLE = "#484f58"

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
ROOM_ZH = {"start": "入口安全屋", "boss": "BOSS 竞技场", "extraction": "撤离屋"}
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
# 波次配色（第 1 / 2 / 3 波；同一块砖取最早用到它的那一波上色）
WAVE_COLOR = ["#f0883e", "#58a6ff", "#a371f7", "#3fb950"]
WAVE_DESC = ["第 1 波", "第 2 波", "第 3 波", "第 4 波及以后"]
BOX_STROKE = "#39c5cf"
BAND_STROKE = "#f85149"


# ---------- 几何 ----------

def rotate(x, z, deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return x * c - z * s, x * s + z * c


def cells_of(room):
    """房间 5m 地砖格心（房间局部系）。无实测清单时按 5m 模数补算。"""
    cells = [(float(c[0]), float(c[1])) for c in room["tile_cells_local"]]
    if cells:
        return cells
    dx, dz = room["dimensions"]
    nx, nz = int(math.ceil(dx / TILE)), int(math.ceil(dz / TILE))
    return [(-dx * 0.5 + TILE * 0.5 + i * TILE, -dz * 0.5 + TILE * 0.5 + j * TILE)
            for i in range(nx) for j in range(nz)]


def hole_cells(cells):
    """包络里**没有地砖**的 5m 格（结构缺口，如 L 型走廊转角外）。"""
    xs = sorted({round(c[0], 3) for c in cells})
    zs = sorted({round(c[1], 3) for c in cells})
    have = {(round(cx, 3), round(cz, 3)) for cx, cz in cells}
    return [(x, z) for x in xs for z in zs if (x, z) not in have]


def footprint_test(cells):
    """返回 inside(x, z)：点是否落在任一块 5m 地砖内（L∞ 口径）。"""
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


def wall_clearance(inside, x, z, cap=60.0):
    """到地砖并集边界的 L∞ 净距（0.05m 步进）。÷5 即「第几圈」，0 = 最外圈。"""
    best = cap
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        step = 0.0
        while step < cap:
            step += 0.05
            if not inside(x + dx * step, z + dz * step):
                break
        best = min(best, step)
    return best


def _corners(c, s, deg):
    out = []
    for px, pz in ((s[0] * 0.5, s[1] * 0.5), (-s[0] * 0.5, s[1] * 0.5),
                   (-s[0] * 0.5, -s[1] * 0.5), (s[0] * 0.5, -s[1] * 0.5)):
        wx, wz = rotate(px, pz, deg)
        out.append((c[0] + wx, c[1] + wz))
    return out


def rect_overlap(c1, s1, r1, c2, s2, r2):
    """SAT：两个（可旋转）矩形是否相交。砖用 r=0，盒用 placement 的 rotation_deg。"""
    axes = []
    for deg in (r1, r2):
        a = math.radians(deg)
        axes.append((math.cos(a), math.sin(a)))
        axes.append((-math.sin(a), math.cos(a)))
    p1, p2 = _corners(c1, s1, r1), _corners(c2, s2, r2)
    for ax in axes:
        v1 = [p[0] * ax[0] + p[1] * ax[1] for p in p1]
        v2 = [p[0] * ax[0] + p[1] * ax[1] for p in p2]
        if max(v1) < min(v2) - 1e-9 or max(v2) < min(v1) - 1e-9:
            return False
    return True


def box_probe_points(cx, cz, sx, sz, deg):
    """盒矩形 4 角 + 4 边中点，用来量「盒边到墙的最近净距」。"""
    hx, hz = sx * 0.5, sz * 0.5
    rel = [(-hx, -hz), (hx, -hz), (-hx, hz), (hx, hz), (-hx, 0.0), (hx, 0.0), (0.0, -hz), (0.0, hz)]
    out = []
    for lx, lz in rel:
        rx, rz = rotate(lx, lz, deg)
        out.append((cx + rx, cz + rz))
    return out


def tile_of(cells_key, x, z):
    """点落在哪块砖上（砖心坐标）。"""
    for k in cells_key:
        if abs(x - k[0]) <= TILE * 0.5 + 1e-6 and abs(z - k[1]) <= TILE * 0.5 + 1e-6:
            return k
    return None


# ---------- 单房计算 ----------

def analyze(room):
    cells = cells_of(room)
    inside = footprint_test(cells)
    cells_key = [(round(cx, 3), round(cz, 3)) for cx, cz in cells]
    rings = {k: int(wall_clearance(inside, k[0], k[1]) // TILE) for k in cells_key}
    band = {k for k in cells_key if rings[k] == 0}

    # 盒 index → 最早调用它的波次
    box_wave = {}
    for wave_index, boxes in enumerate(room["stages"]):
        for box_index in boxes:
            box_wave.setdefault(box_index, wave_index)

    # 盒范围覆盖的砖（怪只可能出现在这些砖上）
    box_tiles = set()
    declared_types = set()
    for placement in room["placements"]:
        if "error" in placement:
            continue
        for spawn in placement["spawns"]:
            declared_types.add(spawn["type"])
        center = placement["center_landed"]
        size = (float(placement["size"][0]), float(placement["size"][1]))
        deg = float(placement["rotation_deg"])
        for k in cells_key:
            if k in box_tiles:
                continue
            if rect_overlap(k, (TILE, TILE), 0.0, center, size, deg):
                box_tiles.add(k)

    # 实际落点 → 所在砖（只数 / 最早波次 / 怪种）
    stats = {}
    spawned_types = set()
    for wave_index, wave in enumerate(room["waves"]):
        for entry in wave:
            k = tile_of(cells_key, float(entry["local"][0]), float(entry["local"][1]))
            if k is None:
                continue
            spawned_types.add(entry["type"])
            s = stats.setdefault(k, {"n": 0, "wave": wave_index, "kinds": {}})
            s["n"] += 1
            s["wave"] = min(s["wave"], wave_index)
            s["kinds"][entry["type"]] = s["kinds"].get(entry["type"], 0) + 1

    # 盒边最近净距（判据 H 的运行时口径）
    box_clr = None
    for placement in room["placements"]:
        if "error" in placement:
            continue
        for bx, bz in box_probe_points(placement["center_landed"][0], placement["center_landed"][1],
                                       float(placement["size"][0]), float(placement["size"][1]),
                                       float(placement["rotation_deg"])):
            c = wall_clearance(inside, bx, bz)
            box_clr = c if box_clr is None else min(box_clr, c)

    return {
        "cells": cells_key, "holes": hole_cells(cells_key), "inside": inside,
        "rings": rings, "band": band, "box_tiles": box_tiles, "stats": stats,
        "bad_tiles": [k for k in stats if rings[k] == 0],
        "box_clr": box_clr,
        "declared_types": declared_types, "spawned_types": spawned_types,
        "missing_types": sorted(declared_types - spawned_types),
        "points": sum(len(w) for w in room["waves"]),
        "peak": max((len(w) for w in room["waves"]), default=0),
        "waves": len(room["waves"]),
    }


def load_templates():
    """floor_00.json → {legacy_room_id: (template_id, template_variant)}。"""
    out = {}
    if not os.path.exists(FLOOR_JSON):
        return out
    data = json.load(open(FLOOR_JSON, encoding="utf-8"))
    for room in data.get("rooms", []):
        key = str(room.get("legacy_room_id", ""))
        if key:
            out[key] = (str(room.get("template_id", "")),
                        str(room.get("template_variant", "")))
    return out


# ---------- SVG ----------

def svg_room(room, m, scale=8.5, pad=3.0):
    dx, dz = room["dimensions"]
    has_boxes = bool([p for p in room["placements"] if "error" not in p])
    minx, minz = -dx * 0.5 - pad, -dz * 0.5 - pad
    w, h = (dx + pad * 2) * scale, (dz + pad * 2) * scale
    px = lambda x: (x - minx) * scale
    pz = lambda z: (z - minz) * scale
    half = TILE * 0.5
    out = ['<svg viewBox="0 0 %.1f %.1f" width="100%%" style="max-width:%.0fpx" '
           'xmlns="http://www.w3.org/2000/svg">' % (w, h, w)]
    out.append('<rect x="0" y="0" width="%.1f" height="%.1f" fill="#0b0f14" rx="6"/>' % (w, h))

    def cell(cx, cz, fill, op, stroke="none", sw=0.0, dash="", sop=None):
        out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" '
                   'fill-opacity="%s" stroke="%s" stroke-width="%.1f" '
                   'stroke-opacity="%s"%s/>'
                   % (px(cx - half), pz(cz - half), TILE * scale, TILE * scale,
                      fill, op, stroke, sw,
                      ("%.2f" % sop) if sop is not None else op,
                      (' stroke-dasharray="%s"' % dash) if dash else ""))

    # ① 普通地砖（不与盒相交的那些）—— 描边比填色明显，保证不刷怪的房也看得出砖格
    for k in m["cells"]:
        if k in m["box_tiles"] or k in m["stats"] or (has_boxes and k in m["band"]):
            continue
        cell(k[0], k[1], "#6e7681", "0.18", "#6e7681", 1.0, sop=0.55)
    # ② 刷怪盒范围的砖
    for k in sorted(m["box_tiles"]):
        if k in m["stats"]:
            continue
        cell(k[0], k[1], BOX_STROKE, "0.24", BOX_STROKE, 0.9)
    # ③ 最外一圈（禁止刷怪）—— 只有摆了盒的房才标，避免给不刷怪的房加噪
    if has_boxes:
        for k in sorted(m["band"]):
            if k in m["stats"]:
                continue
            cell(k[0], k[1], BAND_STROKE, "0.16", BAND_STROKE, 1.1, "5 3")
    # ④ 无地砖处（结构缺口）
    for k in m["holes"]:
        cell(k[0], k[1], "none", "0", HOLE, 1.0)
        d = TILE * scale * 0.22
        for sgn in (1, -1):
            out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" '
                       'stroke-opacity="0.8" stroke-width="1.6"/>'
                       % (px(k[0]) - d, pz(k[1]) - sgn * d, px(k[0]) + d, pz(k[1]) + sgn * d, HOLE))

    # 刷怪盒（落地盒，青色虚线框）
    for placement in room["placements"]:
        if "error" in placement:
            continue
        sx, sz = float(placement["size"][0]), float(placement["size"][1])
        cx, cz = placement["center_landed"]
        out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" '
                   'stroke="%s" stroke-width="2.0" stroke-dasharray="8 4" '
                   'transform="rotate(%.2f %.2f %.2f)"/>'
                   % (px(cx - sx * 0.5), pz(cz - sz * 0.5), sx * scale, sz * scale,
                      BOX_STROKE, float(placement["rotation_deg"]), px(cx), pz(cz)))

    # ⑤ 实际出怪的砖：彩色 + 砖心圆点（点内数字 = 只数）
    for k, s in sorted(m["stats"].items(), key=lambda kv: (kv[1]["wave"], kv[0][1], kv[0][0])):
        color = WAVE_COLOR[s["wave"] % len(WAVE_COLOR)]
        cell(k[0], k[1], color, "0.34", color, 2.4)
        r = min(10.5, 6.0 + 2.0 * max(0, s["n"] - 1))
        out.append('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s" stroke="#0b0f14" '
                   'stroke-width="1.6"/>' % (px(k[0]), pz(k[1]), r, color))
        if s["n"] >= 2:
            out.append('<text x="%.2f" y="%.2f" font-size="%.1f" fill="#0b0f14" '
                       'text-anchor="middle" dominant-baseline="central" font-weight="700" '
                       'font-family="ui-monospace,monospace">%d</text>'
                       % (px(k[0]), pz(k[1]), r * 1.15, s["n"]))

    # 房轮廓 + 门
    out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" stroke="#6e7681" '
               'stroke-opacity="0.9" stroke-width="1.8"/>'
               % (px(-dx * 0.5), pz(-dz * 0.5), dx * scale, dz * scale))
    for door in room["doors"]:
        dxx, dzz = float(door["local"][0]), float(door["local"][1])
        if door["dir"] in ("north", "south"):
            a, b, c, d = px(dxx - 1.5), pz(dzz), px(dxx + 1.5), pz(dzz)
        else:
            a, b, c, d = px(dxx), pz(dzz - 1.5), px(dxx), pz(dzz + 1.5)
        out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#f2cc60" '
                   'stroke-width="6" stroke-opacity="0.95" stroke-linecap="round"/>' % (a, b, c, d))

    # 比例尺
    by, bx = pz(dz * 0.5 + pad - 1.0), px(-dx * 0.5)
    out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="1.5"/>'
               % (bx, by, bx + 10 * scale, by, MUTED))
    for xx in (bx, bx + 10 * scale):
        out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="1.5"/>'
                   % (xx, by - 4, xx, by + 4, MUTED))
    out.append('<text x="%.2f" y="%.2f" font-size="10" fill="%s" '
               'font-family="ui-monospace,monospace">10 m</text>'
               % (bx + 10 * scale + 6, by + 4, MUTED))
    out.append('</svg>')
    return "".join(out)


def svg_overview(rooms, metrics, scale=4.4):
    def W(room, x, z):
        lx, lz = rotate(x, z, room["yaw_deg"])
        return room["origin"][0] + lx, room["origin"][1] + lz

    pts = []
    for room in rooms:
        for cx, cz in metrics[room["room_id"]]["cells"]:
            pts.append(W(room, cx, cz))
    minx = min(p[0] for p in pts) - 8
    maxx = max(p[0] for p in pts) + 8
    minz = min(p[1] for p in pts) - 8
    maxz = max(p[1] for p in pts) + 8
    w, h = (maxx - minx) * scale, (maxz - minz) * scale
    px = lambda x: (x - minx) * scale
    pz = lambda z: (z - minz) * scale
    out = ['<svg viewBox="0 0 %.1f %.1f" width="100%%" style="max-width:%.0fpx" '
           'xmlns="http://www.w3.org/2000/svg">' % (w, h, w)]
    out.append('<rect x="0" y="0" width="%.1f" height="%.1f" fill="#0b0f14" rx="6"/>' % (w, h))
    half = TILE * 0.5

    def cell(wx, wz, fill, op, stroke="none", sw=0.0):
        out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" '
                   'fill-opacity="%s" stroke="%s" stroke-width="%.1f"/>'
                   % (px(wx - half), pz(wz - half), TILE * scale, TILE * scale, fill, op, stroke, sw))

    for room in rooms:
        m = metrics[room["room_id"]]
        alive = bool(m["stats"])
        has_boxes = bool([p for p in room["placements"] if "error" not in p])
        for k in m["cells"]:
            if k in m["box_tiles"] or k in m["stats"] or (has_boxes and k in m["band"]):
                continue
            wx, wz = W(room, k[0], k[1])
            cell(wx, wz, "#6e7681", "0.14")
        if has_boxes:
            for k in m["band"]:
                if k in m["stats"]:
                    continue
                wx, wz = W(room, k[0], k[1])
                cell(wx, wz, BAND_STROKE, "0.26")
        for k in m["box_tiles"]:
            if k in m["stats"]:
                continue
            wx, wz = W(room, k[0], k[1])
            cell(wx, wz, BOX_STROKE, "0.30", BOX_STROKE, 0.6)
        for k, s in m["stats"].items():
            wx, wz = W(room, k[0], k[1])
            color = WAVE_COLOR[s["wave"] % len(WAVE_COLOR)]
            cell(wx, wz, color, "1", BG, 0.8)
        lx, lz = W(room, 0.0, 0.0)
        label = ROOM_ZH.get(room["room_id"], room["room_id"])
        out.append('<text x="%.2f" y="%.2f" font-size="%.1f" fill="%s" text-anchor="middle" '
                   'stroke="%s" stroke-width="4.5" paint-order="stroke fill" '
                   'font-family="ui-monospace,monospace" font-weight="700">%s%s</text>'
                   % (px(lx), pz(lz), scale * 3.4, TEXT if alive else MUTED, BG, label,
                      "" if alive else "（不刷怪）"))
    out.append('</svg>')
    return "".join(out)


# ---------- 页面 ----------

CSS = """
*{box-sizing:border-box}
body{margin:0;background:%(bg)s;color:%(text)s;
 font:14px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif}
.wrap{max-width:1200px;margin:0 auto;padding:26px 20px 0}
h1{font-size:23px;margin:0 0 6px;font-weight:650}
.sub{color:%(muted)s;font-size:13px}
h2{font-size:17px;margin:32px 0 12px;padding-bottom:8px;border-bottom:1px solid %(line)s;font-weight:600}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(500px,1fr));gap:16px}
@media(max-width:1080px){.cards{grid-template-columns:1fr}}
.card{background:%(panel)s;border:1px solid %(line)s;border-radius:10px;padding:14px}
.card h3{margin:0 0 2px;font-size:15px;font-weight:650;display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.card .meta{color:%(muted)s;font-size:12px;margin-bottom:10px}
.card .stat{margin-top:11px;font-size:12.5px;color:%(muted)s;display:flex;flex-wrap:wrap;gap:4px 16px}
.card .stat b{color:%(text)s;font-weight:650}
.kpis{display:grid;grid-template-columns:repeat(auto-fill,minmax(180px,1fr));gap:12px}
.kpi{background:%(panel)s;border:1px solid %(line)s;border-radius:10px;padding:13px 15px}
.kpi .k{color:%(muted)s;font-size:12px}
.kpi .v{font-size:25px;font-weight:700;font-family:ui-monospace,monospace;line-height:1.35}
.kpi .n{color:%(muted)s;font-size:11.5px}
.legend{display:flex;flex-wrap:wrap;gap:10px 20px;background:%(panel)s;border:1px solid %(line)s;
 border-radius:10px;padding:13px 16px;font-size:12.5px;align-items:center}
.legend i{display:inline-block;width:15px;height:15px;border-radius:3px;margin-right:7px;
 vertical-align:-3px;border:1px solid transparent}
.legend .dot{border-radius:50%%;border:none}
.legend .box{background:none!important;border:1.8px dashed %(box)s}
.legend .ring{background:%(band)s33!important;border:1px dashed %(band)s}
.legend .cy{background:%(box)s3d!important;border:1px solid %(box)s}
.legend .gray{background:#6e768129!important}
.legend .hole{background:none!important;border:none;position:relative}
.legend .door{background:#f2cc60!important;height:5px;border-radius:3px;border:none}
table{width:100%%;border-collapse:collapse;font-size:12.5px;margin-top:10px}
th,td{padding:7px 9px;border-bottom:1px solid %(line)s;text-align:left}
th{color:%(muted)s;font-weight:600;font-size:11.5px}
.mono{font-family:ui-monospace,monospace}
.tag{display:inline-block;padding:1px 8px;border-radius:20px;font-size:11px;font-weight:600}
.note{color:%(muted)s;font-size:12.5px;margin-top:10px}
.warn{color:#d29922;font-weight:600}
.ok{color:#3fb950;font-weight:600}
.bad{color:#f85149;font-weight:600}
""" % {"bg": BG, "panel": PANEL, "line": LINE, "muted": MUTED, "text": TEXT,
       "box": BOX_STROKE, "band": BAND_STROKE}


def build():
    data = json.load(open(NEW_JSON, encoding="utf-8"))
    rooms = data["rooms"]
    templates = load_templates()
    metrics = {room["room_id"]: analyze(room) for room in rooms}

    alive = [r for r in rooms if metrics[r["room_id"]]["stats"]]
    total_tiles = sum(len(m["cells"]) for m in metrics.values())
    spawn_tiles = sum(len(m["stats"]) for m in metrics.values())
    box_tiles = sum(len(m["box_tiles"]) for m in metrics.values())
    total_points = sum(m["points"] for m in metrics.values())
    total_boxes = sum(len([p for p in r["placements"] if "error" not in p]) for r in rooms)
    total_band = sum(len(m["band"]) for m in metrics.values())
    bad = sum(len(m["bad_tiles"]) for m in metrics.values())
    box_clr = min((m["box_clr"] for m in metrics.values() if m["box_clr"] is not None), default=None)
    peak = max((m["peak"] for m in metrics.values()), default=0)
    used_types = {e["type"] for room in rooms for wave in room["waves"] for e in wave}

    body = []
    body.append('<div class="wrap">')
    body.append('<h1>远征关卡01 · 刷怪位置示意图</h1>')
    body.append('<div class="sub">怪只会从「刷怪盒」里出来，所以把 <b>5 m 地砖</b>当单位：'
                '<b>砖心圆点 = 这块砖会刷怪</b>，点里的数字 = 出几只怪。'
                '最外一圈地砖按业主口径<b>禁止刷怪</b>。数据为运行时实测（seed %s），'
                '与真机同一条刷怪路径。</div>' % data.get("seed"))
    body.append('</div>')

    body.append('<div class="wrap" style="margin-top:18px">')
    body.append('<div class="kpis">')
    for k, v, n, cls in [
        ("刷怪盒", "%d" % total_boxes, "分布在 %d 个房间" % len(alive), ""),
        ("会刷怪的砖", "%d" % spawn_tiles, "房内共 %d 块地砖，占 %.0f%%"
         % (total_tiles, spawn_tiles * 100.0 / max(1, total_tiles)), ""),
        ("怪（本次实测）", "%d" % total_points, "单波同屏峰值 %d 只" % peak, ""),
        ("最外一圈刷怪的砖", "%d" % bad, "全关 %d 块最外圈砖，一块都没刷"
         % total_band, "ok" if bad == 0 else "bad"),
    ]:
        body.append('<div class="kpi"><div class="k">%s</div><div class="v %s">%s</div>'
                    '<div class="n">%s</div></div>' % (k, cls, v, n))
    body.append('</div></div>')

    body.append('<div class="wrap" style="margin-top:16px">')
    body.append('<div class="legend">')
    for i, wd in enumerate(WAVE_DESC[:3]):
        body.append('<span><i class="dot" style="background:%s"></i>%s刷怪的砖</span>'
                    % (WAVE_COLOR[i], wd))
    body.append('<span><i class="cy"></i>刷怪盒范围内（怪只可能出现在这里）</span>')
    body.append('<span><i class="ring"></i>最外一圈地砖 · 禁止刷怪</span>')
    body.append('<span><i class="gray"></i>其它地砖 · 不刷怪</span>')
    body.append('<span><i class="box"></i>刷怪盒边界</span>')
    body.append('<span><i class="door"></i>门</span>')
    body.append('<span>点里的<b>数字</b> = 这块砖出几只怪；点越大怪越多</span>')
    body.append('<span>格内打叉 = 该处没有地砖</span>')
    body.append('</div></div>')

    body.append('<div class="wrap">')
    body.append('<h2>全关总览</h2>')
    body.append(svg_overview(rooms, metrics))
    body.append('<div class="note">橙 / 蓝 / 紫 = 第 1 / 2 / 3 波刷怪的砖；'
                '淡青 = 刷怪盒覆盖范围；暗红 = 最外一圈（不刷怪）。灰底房不刷怪。</div>')
    body.append('</div>')

    body.append('<div class="wrap">')
    body.append('<h2>逐房刷怪砖块</h2>')
    body.append('<div class="cards">')
    for room in rooms:
        m = metrics[room["room_id"]]
        rid = room["room_id"]
        col = ROOM_COLOR.get(room["room_type"], "#888")
        name = ROOM_ZH.get(rid, rid)
        tpl, var = templates.get(rid, ("", ""))
        body.append('<div class="card">')
        body.append('<h3><span class="tag" style="background:%s22;color:%s">%s</span>%s</h3>'
                    % (col, col, ROOM_TYPE_ZH.get(room["room_type"], room["room_type"]), name))
        body.append('<div class="meta">%s · %.0f × %.0f m%s%s</div>'
                    % (rid, room["dimensions"][0], room["dimensions"][1],
                       (" · 模板 %s" % tpl) if tpl else "",
                       (" / %s" % var) if var else ""))
        body.append(svg_room(room, m))
        if m["stats"]:
            kinds = {}
            for wave in room["waves"]:
                for entry in wave:
                    kinds[entry["type"]] = kinds.get(entry["type"], 0) + 1
            body.append('<div class="stat">'
                        '<span>刷怪盒 <b>%d</b></span>'
                        '<span>波次 <b>%d</b></span>'
                        '<span>怪 <b>%d</b> 只</span>'
                        '<span>刷怪的砖 <b>%d</b> / %d 块</span>'
                        '<span>最外圈压线 <b class="%s">%d</b></span>'
                        '</div>'
                        % (len([p for p in room["placements"] if "error" not in p]),
                           m["waves"], m["points"], len(m["stats"]), len(m["cells"]),
                           "bad" if m["bad_tiles"] else "ok", len(m["bad_tiles"])))
            body.append('<div class="stat"><span>出怪：%s</span></div>'
                        % "，".join("%s ×%d" % (MONSTER_ZH.get(k, k), v)
                                    for k, v in sorted(kinds.items())))
            if m["missing_types"]:
                body.append('<div class="note"><span class="warn">⚠ 盒里声明了「%s」，'
                            '但本次实测没有生成</span>（远征关未登记该类内容，'
                            '属已知缺口）。</div>'
                            % "、".join(MONSTER_ZH.get(t, t) for t in m["missing_types"]))
        else:
            body.append('<div class="stat"><span>本房<b>不刷怪</b>%s</span></div>'
                        % ("（安全屋 / 事件房 / 撤离屋，未摆放刷怪盒）"
                           if not room["placements"] else ""))
        body.append('</div>')
    body.append('</div></div>')

    body.append('<div class="wrap">')
    body.append('<h2>逐房数字</h2>')
    rows = []
    for room in rooms:
        m = metrics[room["room_id"]]
        rid = room["room_id"]
        col = ROOM_COLOR.get(room["room_type"], "#888")
        tpl, var = templates.get(rid, ("", ""))
        tpl_txt = tpl + ((" / " + var) if var else "")
        if not m["stats"]:
            rows.append('<tr><td class="mono">%s</td>'
                        '<td><span style="color:%s">%s</span></td>'
                        '<td class="mono">%s</td><td class="mono">—</td><td class="mono">—</td>'
                        '<td class="mono">0 / %d</td><td class="mono">%d</td>'
                        '<td class="mono">—</td></tr>'
                        % (rid, col, ROOM_ZH.get(rid, rid), tpl_txt,
                           len(m["cells"]), len(m["band"])))
            continue
        clr_txt = ("—" if m["box_clr"] is None else
                   '<span class="ok">%.1f m（第 %d 圈）</span>'
                   % (m["box_clr"], int(m["box_clr"] // TILE)))
        rows.append(
            '<tr><td class="mono">%s</td><td><span style="color:%s">%s</span></td>'
            '<td class="mono">%s</td><td class="mono">%d</td><td class="mono">%d</td>'
            '<td class="mono"><b>%d</b> / %d</td><td class="mono">%d</td>'
            '<td class="mono">%s</td></tr>'
            % (rid, col, ROOM_ZH.get(rid, rid), tpl_txt, m["waves"], m["points"],
               len(m["stats"]), len(m["cells"]), len(m["band"]), clr_txt))
    body.append('<table><thead><tr><th>房间</th><th>类型</th><th>房间模板</th><th>波次</th>'
                '<th>怪</th><th>刷怪的砖 / 总砖</th><th>最外圈砖（禁刷）</th>'
                '<th>盒边离墙最近</th></tr></thead><tbody>' + "".join(rows) + '</tbody></table>')
    body.append('<div class="note">盒边离墙最近 = 所有刷怪盒的边到房间墙的最近净距，'
                '判据要求 ≥ 5 m（1 圈），这样盒内取样的怪不可能落进最外一圈。'
                '实测最小 <b>%s</b>。盒覆盖 <b>%d</b> 块砖，本局实际用到 <b>%d</b> 块。</div>'
                % ("—" if box_clr is None else "%.2f m" % box_clr, box_tiles, spawn_tiles))
    body.append('</div>')

    body.append('<div class="wrap" style="padding-bottom:60px">')
    body.append('<h2>怪种</h2>')
    body.append('<div class="legend">')
    for key in sorted(used_types):
        body.append('<span><i class="dot" style="background:%s"></i>%s</span>'
                    % (MONSTER_COLOR.get(key, "#fff"), MONSTER_ZH.get(key, key)))
    body.append('</div>')
    body.append('<div class="note">数据源 <code>_scratch/expedition_spawn_boxes/'
                'spawn_box_map.json</code>（运行时探针实测：真实装配远征01 场景、'
                '建壳体与家具碰撞后取点，走的是真机 <code>Dungeon3D._spawn_room_enemies</code> '
                '同一条路径）。</div>')
    body.append('</div>')

    html = ('<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>远征01 · 刷怪位置示意图</title><style>%s</style></head><body>%s</body></html>'
            % (CSS, "".join(body)))

    for path in OUTS:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(html)
        print("wrote %s (%d bytes)" % (path, len(html.encode("utf-8"))))

    print("SUMMARY rooms=%d alive=%d boxes=%d spawn_tiles=%d box_tiles=%d tiles=%d "
          "points=%d band=%d bad=%d min_box_clr=%s peak=%d missing_types=%s"
          % (len(rooms), len(alive), total_boxes, spawn_tiles, box_tiles, total_tiles,
             total_points, total_band, bad,
             "None" if box_clr is None else "%.2f" % box_clr, peak,
             {r["room_id"]: metrics[r["room_id"]]["missing_types"]
              for r in rooms if metrics[r["room_id"]]["missing_types"]}))

    assert html.count("<svg") == html.count("</svg>"), "svg 标签不配平"
    assert html.count("<div") == html.count("</div>"), \
        "div 不配平 %d vs %d" % (html.count("<div"), html.count("</div>"))
    assert html.count("<table") == html.count("</table>"), "table 不配平"
    assert bad == 0, "有刷怪的砖落在最外圈：%d" % bad
    print("SELFCHECK OK svg/div/table 配平；最外圈违规 0")


if __name__ == "__main__":
    build()
