"""远征关卡01 刷怪点平面图渲染器。

数据源：_scratch/expedition_spawn_map/spawn_map.json（Godot headless 探针实测产出）
输出：../outputs/expedition01_spawn_map.html
"""
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
DATA = os.path.join(HERE, "spawn_map.json")
OUT = os.path.join(REPO, "outputs", "expedition01_spawn_map.html")

ROOM_TYPE_ZH = {
    "STAIR_LOBBY": "入口安全屋",
    "COMBAT": "战斗房",
    "SCAVENGE": "搜刮房",
    "STORAGE": "仓储房",
    "EVENT": "事件房",
    "BOSS": "BOSS 竞技场",
    "EXTRACTION": "撤离屋",
}
ROOM_COLOR = {
    "STAIR_LOBBY": "#2ea043",
    "COMBAT": "#e05252",
    "SCAVENGE": "#d29922",
    "STORAGE": "#4f8cc9",
    "EVENT": "#a371f7",
    "BOSS": "#c2410c",
    "EXTRACTION": "#39c5cf",
}
MONSTER_ZH = {
    "melee_chaser": "近战追猎者",
    "ranged_caster": "远程术士",
    "ambusher": "伏击者",
    "shielded": "盾卫",
    "exploder": "自爆体",
    "summoner": "召唤者",
    "tank": "重装",
    "bomber": "爆破手",
    "boss": "首领",
}
CLEARANCE = {"BOSS": 2.2}
DEFAULT_CLEARANCE = 1.15
TILE = 5.0


def cells_of(room):
    """房间地砖格心（局部坐标）。无壳体清单的房（入口安全屋）按 5m 模数补算。"""
    cells = [(c[0], c[1]) for c in room["tile_cells_local"]]
    if cells:
        return cells
    dx, dz = room["dimensions"]
    nx, nz = int(math.ceil(dx / TILE)), int(math.ceil(dz / TILE))
    return [(-dx * 0.5 + TILE * 0.5 + i * TILE, -dz * 0.5 + TILE * 0.5 + j * TILE)
            for i in range(nx) for j in range(nz)]


def rotate(x, z, deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return x * c + z * s, -x * s + z * c


def to_world(room, x, z):
    lx, lz = rotate(x, z, room["yaw_deg"])
    return room["origin"][0] + lx, room["origin"][1] + lz


def footprint_test(cells):
    """返回 in_footprint(x, z)：点是否落在任一块 5m 地砖的矩形内。"""
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


def wall_clearance(inside, x, z, cap=12.0):
    """从落点沿 ±x/±z 直走到离开地砖并集所需距离的最小值（0.05m 步进，>cap 记 cap）。"""
    best = cap
    for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        step = 0.0
        while step < cap:
            step += 0.05
            if not inside(x + dx * step, z + dz * step):
                break
        best = min(best, step)
    return best


def min_pair_distance(points):
    best = 1e9
    for i in range(len(points)):
        for j in range(i + 1, len(points)):
            best = min(best, math.dist(points[i], points[j]))
    return best


def svg_room(room, scale, pad, show_index=True, used_upto=0):
    """单房平面图（局部坐标，1 单位 = scale px）。"""
    cells = cells_of(room)
    half = TILE * 0.5
    dx, dz = room["dimensions"]
    minx, maxx = -dx * 0.5 - pad, dx * 0.5 + pad
    minz, maxz = -dz * 0.5 - pad, dz * 0.5 + pad
    w = (maxx - minx) * scale
    h = (maxz - minz) * scale
    col = ROOM_COLOR.get(room["room_type"], "#888")

    def px(x):
        return (x - minx) * scale

    def pz(z):
        return (z - minz) * scale

    out = ['<svg viewBox="0 0 %.1f %.1f" width="100%%" style="max-width:%.0fpx" '
           'xmlns="http://www.w3.org/2000/svg">' % (w, h, w)]
    # 5m 底格
    out.append('<rect x="0" y="0" width="%.1f" height="%.1f" fill="#0b0f14"/>' % (w, h))
    # 地砖
    for cx, cz in cells:
        out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" '
                   'fill-opacity="0.30" stroke="%s" stroke-opacity="0.55" stroke-width="0.8"/>'
                   % (px(cx - half), pz(cz - half), TILE * scale, TILE * scale, col, col))
    # 房间包络（虚线）
    out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="none" stroke="#7d8590" '
               'stroke-opacity="0.5" stroke-width="1" stroke-dasharray="4 3"/>'
               % (px(-dx * 0.5), pz(-dz * 0.5), dx * scale, dz * scale))
    # 门
    for door in room["doors"]:
        dxx, dzz = door["local"]
        side = door["dir"]
        if side in ("north", "south"):
            x0, z0, x1, z1 = dxx - 1.5, dzz, dxx + 1.5, dzz
        else:
            x0, z0, x1, z1 = dxx, dzz - 1.5, dxx, dzz + 1.5
        out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#f2cc60" '
                   'stroke-width="5" stroke-linecap="butt" stroke-opacity="0.9"/>'
                   % (px(x0), pz(z0), px(x1), pz(z1)))
    # 刷怪点
    max_used = max(used_upto, 1)
    for p in room["spawn_points"]:
        lx, lz = p["local"]
        i = p["index"]
        active = i < used_upto
        r = 3.4 if active else 2.6
        fill = "#ff5c5c" if active else "#5d6b7a"
        opacity = "1" if active else "0.55"
        out.append('<circle cx="%.2f" cy="%.2f" r="%.1f" fill="%s" fill-opacity="%s" '
                   'stroke="#0b0f14" stroke-width="0.9"/>'
                   % (px(lx), pz(lz), r, fill, opacity))
        if show_index:
            out.append('<text x="%.2f" y="%.2f" font-size="8.5" fill="%s" '
                       'text-anchor="middle" font-family="ui-monospace,monospace">%d</text>'
                       % (px(lx), pz(lz) + 3.0, "#ffffff" if active else "#aab4bf", i + 1))
    # 房心
    out.append('<circle cx="%.2f" cy="%.2f" r="1.6" fill="#7d8590"/>' % (px(0), pz(0)))
    out.append('<text x="%.2f" y="%.2f" font-size="10" fill="#7d8590" text-anchor="start" '
               'font-family="ui-monospace,monospace">(0,0)</text>' % (px(0) + 5, pz(0) - 4))
    # 比例尺（10 m）
    by = pz(dz * 0.5 - 1.5)
    bx = px(-dx * 0.5 + 1)
    out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#7d8590" stroke-width="1.5"/>'
               % (bx, by, bx + 10 * scale, by))
    out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#7d8590" stroke-width="1.5"/>'
               % (bx, by - 3, bx, by + 3))
    out.append('<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="#7d8590" stroke-width="1.5"/>'
               % (bx + 10 * scale, by - 3, bx + 10 * scale, by + 3))
    out.append('<text x="%.2f" y="%.2f" font-size="9" fill="#7d8590" text-anchor="start" '
               'font-family="ui-monospace,monospace">10 m</text>'
               % (bx + 10 * scale + 5, by + 3))
    out.append('</svg>')
    return "".join(out), w, h


def svg_overview(seed, scale=5.0):
    rooms = seed["rooms"]
    pts = []
    for room in rooms:
        for c in room["tile_cells_world"]:
            pts.append(c)
        if not room["tile_cells_world"]:
            dx, dz = room["dimensions"]
            for sx in (-0.5, 0.5):
                for sz in (-0.5, 0.5):
                    pts.append(to_world(room, dx * sx, dz * sz))
    minx = min(p[0] for p in pts) - 8
    maxx = max(p[0] for p in pts) + 8
    minz = min(p[1] for p in pts) - 8
    maxz = max(p[1] for p in pts) + 8
    w = (maxx - minx) * scale
    h = (maxz - minz) * scale

    def px(x):
        return (x - minx) * scale

    def pz(z):
        return (z - minz) * scale

    out = ['<svg viewBox="0 0 %.1f %.1f" width="100%%" xmlns="http://www.w3.org/2000/svg">' % (w, h)]
    out.append('<rect width="%.1f" height="%.1f" fill="#0b0f14"/>' % (w, h))
    # 主路线：房心 → 门 → 邻房心。
    # 注意：远征01 的 12 段衔接全部「墙贴墙」（净距 0），两房的门坐标重合，
    # 直接连门到门会得到零长度线段 ⇒ 必须走折线才看得见。
    by_id = {r["room_id"]: r for r in rooms}
    for room in rooms:
        for door in room["doors"]:
            other = by_id.get(door["target"])
            if other is None:
                continue
            pts_line = [
                (room["origin"][0], room["origin"][1]),
                (room["origin"][0] + door["local"][0], room["origin"][1] + door["local"][1]),
                (other["origin"][0], other["origin"][1]),
            ]
            d = " ".join("%.1f,%.1f" % (px(x), pz(z)) for x, z in pts_line)
            out.append('<polyline points="%s" fill="none" stroke="#f2cc60" stroke-width="1.4" '
                       'stroke-dasharray="6 4" stroke-opacity="0.6"/>' % d)
    # 门垛刻度
    for room in rooms:
        for door in room["doors"]:
            dx0, dz0 = to_world(room, door["local"][0], door["local"][1])
            x0, y0 = px(dx0), pz(dz0)
            if door["dir"] in ("north", "south"):
                out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#f2cc60" '
                           'stroke-width="4"/>' % (x0 - 4, y0, x0 + 4, y0))
            else:
                out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#f2cc60" '
                           'stroke-width="4"/>' % (x0, y0 - 4, x0, y0 + 4))
    # 房
    for room in rooms:
        col = ROOM_COLOR.get(room["room_type"], "#888")
        cells = room["tile_cells_world"]
        half = TILE * 0.5
        if cells:
            for cx, cz in cells:
                out.append('<rect x="%.2f" y="%.2f" width="%.1f" height="%.1f" fill="%s" '
                           'fill-opacity="0.28" stroke="%s" stroke-opacity="0.45" stroke-width="0.7"/>'
                           % (px(cx - half), pz(cz - half), TILE * scale, TILE * scale, col, col))
        else:
            dx, dz = room["dimensions"]
            out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" fill="%s" '
                       'fill-opacity="0.28" stroke="%s" stroke-opacity="0.6" stroke-width="1"/>'
                       % (px(room["origin"][0] - dx / 2), pz(room["origin"][1] - dz / 2),
                          dx * scale, dz * scale, col, col))
    # 落点
    for room in rooms:
        used = max([len(w) for w in room["rolled_waves"]] or [0])
        for p in room["spawn_points"]:
            if p["index"] >= max(used, 1):
                continue
            out.append('<circle cx="%.2f" cy="%.2f" r="2.6" fill="#ff5c5c" stroke="#0b0f14" '
                       'stroke-width="0.8"/>' % (px(p["world"][0]), pz(p["world"][1])))
    # 标签
    for room in rooms:
        used = max([len(w) for w in room["rolled_waves"]] or [0])
        label = room["room_id"] if room["room_id"] != "start" else "入口"
        if room["room_id"] == "boss":
            label = "BOSS"
        if room["room_id"] == "extraction":
            label = "撤离"
        out.append('<text x="%.1f" y="%.1f" font-size="%d" font-weight="700" fill="#e6edf3" '
                   'text-anchor="middle" font-family="system-ui,sans-serif">%s</text>'
                   % (px(room["origin"][0]), pz(room["origin"][1]) - 6, int(scale * 3.2), label))
        out.append('<text x="%.1f" y="%.1f" font-size="%d" fill="#9aa4b0" text-anchor="middle" '
                   'font-family="ui-monospace,monospace">%s · %d 只</text>'
                   % (px(room["origin"][0]), pz(room["origin"][1]) + 12, int(scale * 2.2),
                      ROOM_TYPE_ZH.get(room["room_type"], room["room_type"]), used))
    # 指北
    out.append('<g transform="translate(%.1f,%.1f)"><line x1="0" y1="0" x2="0" y2="-26" '
               'stroke="#9aa4b0" stroke-width="2"/><polygon points="0,-32 -5,-22 5,-22" fill="#9aa4b0"/>'
               '<text x="0" y="12" font-size="11" fill="#9aa4b0" text-anchor="middle">+Z 南</text></g>'
               % (px(maxx) - 26, pz(maxz) - 34))
    out.append('</svg>')
    return "".join(out)


def build():
    with open(DATA, encoding="utf-8") as fh:
        payload = json.load(fh)
    seed = payload["seeds"][0]
    rooms = seed["rooms"]

    # 自检
    checks = []
    for room in rooms:
        cells = cells_of(room)
        inside = footprint_test(cells)
        clearance = CLEARANCE.get(room["room_type"], DEFAULT_CLEARANCE)
        gaps = [wall_clearance(inside, p["local"][0], p["local"][1]) for p in room["spawn_points"]]
        min_gap = min(gaps) if gaps else 0.0
        pts = [(p["local"][0], p["local"][1]) for p in room["spawn_points"]]
        pair = min_pair_distance(pts) if len(pts) > 1 else 0.0
        used = max([len(w) for w in room["rolled_waves"]] or [0])
        used_gap = min(gaps[:used]) if used else 0.0
        used_pair = min_pair_distance(pts[:used]) if used > 1 else 0.0
        ok = True
        if used:
            ok = used_gap >= clearance - 0.01 and (used <= 1 or used_pair >= clearance * 2.0 - 0.01)
        checks.append({
            "room": room, "cells": len(cells), "area": len(cells) * 25,
            "clearance": clearance, "min_gap": min_gap, "pair": pair,
            "used": used, "used_gap": used_gap, "used_pair": used_pair, "ok": ok,
        })

    minx = min(p["world"][0] for r in rooms for p in r["spawn_points"])
    maxx = max(p["world"][0] for r in rooms for p in r["spawn_points"])
    minz = min(p["world"][1] for r in rooms for p in r["spawn_points"])
    maxz = max(p["world"][1] for r in rooms for p in r["spawn_points"])

    total_pts = sum(len(r["spawn_points"]) for r in rooms)
    hostile = [c for c in checks if c["used"] > 0]

    html = []
    A = html.append
    A('<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">')
    A('<title>远征关卡01 · 刷怪点平面图</title>')
    A('<style>')
    A('''
:root{--bg:#0d1117;--panel:#161b22;--line:#30363d;--fg:#e6edf3;--dim:#9aa4b0;--acc:#f2cc60;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
 font-family:system-ui,-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;line-height:1.6;}
.wrap{max-width:1240px;margin:0 auto;padding:32px 24px 80px;}
h1{font-size:26px;margin:0 0 6px;letter-spacing:.4px}
h2{font-size:19px;margin:40px 0 12px;padding-bottom:8px;border-bottom:1px solid var(--line)}
h3{font-size:15px;margin:0 0 2px}
.sub{color:var(--dim);font-size:13px;margin-bottom:18px}
.meta{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0 4px}
.chip{background:var(--panel);border:1px solid var(--line);border-radius:999px;
 padding:3px 11px;font-size:12px;color:var(--dim)}
.chip b{color:var(--fg);font-weight:600}
.note{background:var(--panel);border:1px solid var(--line);border-left:3px solid var(--acc);
 border-radius:6px;padding:12px 16px;font-size:13.5px;color:#c9d1d9;margin:16px 0}
.note b{color:var(--acc)}
.note code{background:#0b0f14;border:1px solid var(--line);border-radius:4px;padding:1px 5px;
 font-family:ui-monospace,monospace;font-size:12px;color:#9ecbff}
table{width:100%;border-collapse:collapse;font-size:12.5px;margin:8px 0}
th,td{border:1px solid var(--line);padding:5px 8px;text-align:left;vertical-align:top}
th{background:#1b222b;color:#c9d1d9;font-weight:600;white-space:nowrap}
td.mono{font-family:ui-monospace,monospace;font-size:11.5px}
.ok{color:#3fb950;font-weight:600}
.bad{color:#f85149;font-weight:600}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(400px,1fr));gap:18px;margin-top:14px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:9px;padding:14px 15px 12px}
.card .hd{display:flex;justify-content:space-between;align-items:baseline;gap:8px;margin-bottom:8px}
.tag{font-size:11px;padding:2px 8px;border-radius:999px;border:1px solid;white-space:nowrap}
.plan{border:1px solid var(--line);border-radius:6px;overflow:hidden;background:#0b0f14}
.kv{display:grid;grid-template-columns:auto 1fr;gap:2px 10px;font-size:12px;margin-top:9px;color:#c9d1d9}
.kv dt{color:var(--dim);white-space:nowrap}
.kv dd{margin:0;font-family:ui-monospace,monospace;font-size:11.5px}
table.mini{font-size:11.5px;margin-top:9px}
table.mini th,table.mini td{padding:3px 6px}
table.mini th{background:#1b222b}
path.grid{display:none}
.legend{display:flex;flex-wrap:wrap;gap:16px;font-size:12.5px;color:var(--dim);margin:10px 0 0}
.legend span{display:inline-flex;align-items:center;gap:6px}
.dot{width:11px;height:11px;border-radius:50%;display:inline-block}
.ov{border:1px solid var(--line);border-radius:8px;overflow:hidden;background:#0b0f14;
 max-width:760px;margin:0 auto}
details{margin-top:10px}
summary{cursor:pointer;font-size:12.5px;color:var(--dim)}
''')
    A('</style></head><body><div class="wrap">')

    A('<h1>远征关卡01 · 刷怪点平面图</h1>')
    A('<div class="sub">数据来自 Godot 4.6.3 headless 实跑探针：房间实例取 <code>Dungeon3D._rooms</code>，'
      '落点取 <code>DungeonRoom3D.spawn_point_for_index()</code>（与 <code>_spawn_enemy_batch</code> 同一条路径）。'
      '不是手摆坐标，也不是文档抄录。</div>')
    A('<div class="meta">')
    A('<span class="chip">关卡 <b>expedition_01</b></span>')
    A('<span class="chip">run_seed <b>%d</b></span>' % seed["seed"])
    A('<span class="chip">主题 <b>%s</b>（difficulty_rank=%d）</span>' % (seed["theme_id"], seed["difficulty_rank"]))
    A('<span class="chip">layout_id <b>%s</b></span>' % (seed["layout_id"] or "—"))
    A('<span class="chip">兜底样例 <b>%s</b></span>' % ("是" if seed["used_fallback"] else "否（程序化生成成功）"))
    A('<span class="chip">房间 <b>%d</b></span>' % len(rooms))
    A('<span class="chip">刷怪房 <b>%d</b></span>' % len(hostile))
    A('<span class="chip">落点总数 <b>%d</b></span>' % total_pts)
    A('<span class="chip">世界范围 x[%.0f,%.0f] z[%.0f,%.0f] %s</span>'
      % (minx, maxx, minz, maxz, "m"))
    A('</div>')

    A('<div class="note"><b>落点是怎么来的（结论先行）</b><br>'
      '落点<b>不是关卡作者摆的</b>，是运行时按房间几何现算的，三层机制：<br>'
      '① <b>候选</b>：取本房 5m 地砖格心清单（<code>_authored_tile_cells</code>，非矩形房的凹口在摆位阶段就被剔掉），'
      '每个格心再铺 3×3 个点、各带 ±0.65m 抖动；候选点须让「整个 ≥ 安全半径的正方形」被地砖并集覆盖'
      '（<code>_spawn_floor_contains</code>），且不压任何带碰撞的家具（<code>_spawn_obstacle_free</code>，'
      '保守 AABB、支持旋转）；<br>'
      '② <b>打乱</b>：独立随机流 <code>rng.seed = room_seed ^ room_id.hash() ^ 0x53504157</code> 做 Fisher-Yates。'
      '顺序本身承载随机优先级 —— 刻意不用「取最大距离」那种会退化成固定四角的写法；<br>'
      '③ <b>取点</b>：<code>spawn_point_for_index(i)</code> 用<b>贪心最远点</b>逐只挑。'
      '打分为「到已选点的最小距离」，另给<b>贴边加权</b>：'
      '候选点若连「安全半径+3m」的正方形都放不下（即离墙 &lt; 4.15m），且它到已选点距离 ≥ 分离度，'
      '就再加一份分离度。<b>分离度 = max(2×安全半径+0.1m, 房间对角线 × 0.22)</b>。'
      '⇒ 第 1 只必然落在轮廓带里（只有贴边点带加权），之后逐只往「离已有点最远」的地方铺，'
      '所以呈现<b>先贴轮廓、再向房心收</b>的形状；边缘容不下时自动向内退，绝不重叠。<br>'
      '安全半径 <code>SPAWN_CLEARANCE_M=1.15m</code>（普通房）／<code>SPAWN_BOSS_CLEARANCE_M=2.2m</code>（BOSS 房），'
      '单房上限 <code>SPAWN_MAX_POINTS=64</code>。<br>'
      '<b>每波都从 index 0 重取</b>（<code>_spawn_next_room_wave</code> 调 <code>_spawn_enemy_batch</code> 时不传 positions）'
      '⇒ 同一房的多波<b>共用同一组落点</b>，第 N 波只是把前 N 个点再站一遍。因此本图只标到「本房最大一波」的用量。</div>')

    A('<div class="note" style="border-left-color:#39a0ed"><b>避让基准：这 1.15m 到底从哪量？</b><br>'
      '不是「外墙坐标沿法线内缩 1.15m」这种解析算法，而是<b>两条各自独立的判定</b>，基准不同：<br>'
      '① <b>地砖并集覆盖</b>（<code>_spawn_floor_contains</code>）：要求「以候选点为中心、边长 2×安全半径的<b>正方形</b>」'
      '被本房 5m 地砖并集 100% 覆盖，同时落在 <code>Rect2(-dimensions/2, dimensions)</code> 名义包围盒内。'
      '⇒ 基准是<b>地砖铺面边界</b>；判据用<b>轴对齐外扩矩形</b>（<code>Rect2</code>）实现而不是圆形。本关卡的墙与地砖都是轴对齐的，故等效于「沿 ±x 与 ±z 的净距都 ≥ 安全半径」。<br>'
      '② <b>碰撞体避让</b>（<code>_spawn_obstacle_free</code>）：把所有<b>带碰撞代理</b>的实体的水平 AABB 各向外扩一份安全半径，'
      '候选点落进去就判废。⇒ 基准是<b>碰撞体外包矩形</b>，不是墙面几何；旋转过的家具取的是<b>旋转后 AABB 外包</b>（比真实轮廓大），属偏保守。<br>'
      '本图自带探针把两个基准都钉住了：<br>'
      '· 12 个走 authored 外壳的房间，<b>地砖并集外边界与名义房间包围盒逐值完全一致</b>（四向 gap 全 0.00m）—— 地砖铺到墙心线；<br>'
      '· 远征的墙<b>有碰撞代理</b>（全场景 334 件：<code>WallStandardCollision</code> 190 / '
      '<code>WallCollisionLong</code> 49 / <code>WallCollisionShort</code> 49 / <code>WallDoorCollision</code> 42 / '
      '<code>OuterBoundaryCollision</code> 4），每件都<b>精确骑在 5m 网格线上、厚 0.30m（±0.15）</b>；<br>'
      '· 于是一间 25m 房的净空是 [墙心线+0.15, 墙心线-0.15]（净宽 24.7m），而 ② 比 ① 更严：'
      '<b>离墙面净面 >=1.15m 等价于离 5m 墙心线 >=1.30m</b> —— 这正是本图实测最小离墙是 <b>1.35m</b>、而不是贴着 1.15m 的原因。<br>'
      '<b>三个容易踩的点</b>：(a) 判据是<b>轴对齐方形外扩</b>不是圆，凹口要求两个方向同时退让；'
      '(b) 只统计 <b>y 在 [0.05, 2.6m)</b> 的碰撞体（<code>SPAWN_BODY_HEIGHT_M=2.6</code>）—— 天花板、上层楼板、'
      '高处管道都不算障碍，低于地面 5cm 的地板自身也不算；'
      '(c) 障碍收集以<b>整层</b>为范围（<code>root = get_parent()</code>），'
      '所以<b>邻房的共墙、L 角件、邻房家具只要与本房空间相交，同样会把本房落点推开</b>。</div>')
    A('<div class="note" style="border-left-color:#f85149"><b>本轮实测发现：BOSS 竞技场目前不出 BOSS</b><br>'
      '设计源 <code>floors/floor_00.json</code> 的 <code>boss</code> 房<b>没有 <code>boss_content_id</code></b>'
      '（整份文件也不含该字段，亦无 <code>reward_plan</code>），'
      '而 <code>BossContentCatalog.CONTENT</code> 只登记了塔楼 <b>95 / 90 / 85</b> 三层的内容。'
      '<code>TowerDescent3D._append_plan_room_record</code>（L1906–1914）只在 '
      '<code>resolve_profile()</code> 返回非空时才把 <code>boss_content_id</code> / <code>arena_asset_id</code> / '
      '<code>arena_scene</code> 写进记录，所以房间 meta 是空串 ⇒ '
      '<code>_spawn_room_enemies</code> 的 <code>boss_configs</code> 为空，'
      '按项目口径「没写 boss 就是没有 boss」⇒ 本房是<b>合法空房</b>：'
      '不出 BOSS，也不出精英随从（精英只在 <code>boss_configs</code> 非空时才追加），房间立即清空。<br>'
      '探针实测 <code>generate_enemies({type:"boss",…})</code> 返回 0 条，与此口径一致。'
      '该房的美术与落点都是齐的（80 格地砖 / 2000 m²，落点已按 2.2m 安全半径算好），'
      '缺的只是<b>一条 <code>boss_content_id</code> 指派</b>（并在名册里加对应条目）。'
      '注意 <code>CONTENT</code> 的键是<b>塔楼层号</b>，单层远征的 <code>floor_number</code> 取 <code>plan.floor_number=0</code>，'
      '要指远征专属首领需在设计源写 ID、名册加条目。</div>')

    # 总览
    A('<h2>1 · 全关卡总览</h2>')
    A('<div class="sub">房间按 5m 地砖实际轮廓绘制（不是包围盒），黄虚线为门的连接关系，红点为刷怪落点（仅标到本房最大一波的用量）。</div>')
    A('<div class="legend">')
    for key, col in ROOM_COLOR.items():
        A('<span><i class="dot" style="background:%s"></i>%s</span>' % (col, ROOM_TYPE_ZH[key]))
    A('<span><i class="dot" style="background:#ff5c5c"></i>刷怪落点</span>')
    A('<span><i class="dot" style="background:#f2cc60"></i>门 / 衔接</span>')
    A('</div>')
    A('<div class="ov">%s</div>' % svg_overview(seed))

    # 清单
    A('<h2>2 · 房间清单与刷怪编成</h2>')
    A('<div class="sub">「落点用量」= 本房所有波次里最多的一波只数；「编成」为本 run_seed 下 '
      '<code>MonsterInjector.build_waves_from_plan</code> 实际抽出的结果（种子 = run_seed + room_id.hash()）。</div>')
    A('<table><thead><tr><th>#</th><th>房号</th><th>类型</th><th>尺寸 (m)</th><th>地砖</th>'
      '<th>面积 m²</th><th>波次</th><th>每波编成（实抽）</th><th>落点用量</th></tr></thead><tbody>')
    for i, c in enumerate(checks):
        room = c["room"]
        col = ROOM_COLOR.get(room["room_type"], "#888")
        wave_txt = []
        for wi, w in enumerate(room["rolled_waves"]):
            parts = []
            counts = {}
            for e in w:
                counts[e["type"]] = counts.get(e["type"], 0) + 1
            for k, v in counts.items():
                parts.append("%s×%d" % (MONSTER_ZH.get(k, k), v))
            wave_txt.append("第%d波 %d 只：%s" % (wi + 1, len(w), "、".join(parts)))
        if not wave_txt:
            wave_txt = ["—（无 enemy_spawn_plan）"]
        A('<tr><td>%d</td><td><b>%s</b></td>'
          '<td><span class="tag" style="color:%s;border-color:%s">%s</span></td>'
          '<td class="mono">%.0f × %.0f</td><td class="mono">%d 格</td><td class="mono">%d</td>'
          '<td class="mono">%d</td><td>%s</td><td class="mono">%d</td></tr>'
          % (i + 1, room["room_id"], col, col, ROOM_TYPE_ZH.get(room["room_type"], room["room_type"]),
             room["dimensions"][0], room["dimensions"][1], c["cells"], c["area"],
             len(room["rolled_waves"]), "<br>".join(wave_txt), c["used"]))

    A('</tbody></table>')

    # 逐房
    A('<h2>3 · 逐房落点详图</h2>')
    A('<div class="sub">坐标 = <b>房间局部坐标</b>（房心为原点，单位 m，x 向右 / z 向下，与 3D 的 x-z 平面一致）。'
      '编号 = 拾取顺序（第 1 只 → 第 N 只）；<span style="color:#ff5c5c">红色实心</span>为实际会用到的落点，'
      '<span style="color:#5d6b7a">灰色</span>为备用落点。黄色粗线为门洞。</div>')
    A('<div class="grid">')
    for c in checks:
        room = c["room"]
        col = ROOM_COLOR.get(room["room_type"], "#888")
        svg, _w, _h = svg_room(room, scale=6.2, pad=2.0, used_upto=c["used"])
        A('<div class="card">')
        A('<div class="hd"><h3>%s &nbsp;<span style="color:%s;font-size:12px">%s</span></h3>'
          '<span class="tag" style="color:%s;border-color:%s">%s</span></div>'
          % (room["room_id"], col, ROOM_TYPE_ZH.get(room["room_type"], room["room_type"]),
             col, col, room["size_class"]))
        A('<div class="plan">%s</div>' % svg)
        A('<dl class="kv">')
        A('<dt>白盒尺寸</dt><dd>%.0f × %.0f m</dd>' % tuple(room["dimensions"]))
        A('<dt>地砖 / 面积</dt><dd>%d 格 · %d m²</dd>' % (c["cells"], c["area"]))
        A('<dt>世界位置</dt><dd>(%.1f, %.1f) · yaw=%.0f°</dd>'
          % (room["origin"][0], room["origin"][1], room["yaw_deg"]))
        A('<dt>连接</dt><dd>%s</dd>' % ("、".join(
            "%s→%s" % (d["dir"], d["target"] or "（弃局出口）") for d in room["doors"]) or "—"))
        A('<dt>主路序号</dt><dd>第 %d 房 / floor_level=%d</dd>' % (checks.index(c) + 1, room["floor_level"]))
        A('<dt>落点用量</dt><dd>%d / 候选 %d</dd>' % (c["used"], len(room["spawn_points"])))
        A('</dl>')
        if c["used"]:
            A('<table class="mini"><thead><tr><th>波</th><th>编成（实抽）</th><th>落点</th></tr></thead><tbody>')
            for wi, w in enumerate(room["rolled_waves"]):
                counts = {}
                for e in w:
                    counts[e["type"]] = counts.get(e["type"], 0) + 1
                txt = "、".join("%s×%d" % (MONSTER_ZH.get(k, k), v) for k, v in counts.items())
                A('<tr><td class="mono">%d</td><td>%s</td><td class="mono">#1–#%d</td></tr>'
                  % (wi + 1, txt, len(w)))
            A('</tbody></table>')
            A('<details><summary>落点坐标（%d 个）与离墙净距自检</summary>' % len(room["spawn_points"]))
            A('<table class="mini"><thead><tr><th>#</th><th>局部 (x, z)</th><th>世界 (x, z)</th>'
              '<th>离墙净距 m</th><th>与最近已选点 m</th></tr></thead><tbody>')
            pts = [(p["local"][0], p["local"][1]) for p in room["spawn_points"]]
            inside = footprint_test(cells)
            for p in room["spawn_points"]:
                prev = pts[:p["index"]]
                near = min([math.dist(pts[p["index"]], q) for q in prev], default=float("nan"))
                gap = wall_clearance(inside, p["local"][0], p["local"][1])
                near_txt = "—" if math.isnan(near) else "%.2f" % near
                A('<tr><td class="mono">%d</td><td class="mono">(%7.3f, %7.3f)</td>'
                  '<td class="mono">(%7.2f, %7.2f)</td><td class="mono">%.2f</td>'
                  '<td class="mono">%s</td></tr>'
                  % (p["index"] + 1, p["local"][0], p["local"][1],
                     p["world"][0], p["world"][1], gap, near_txt))
            A('</tbody></table></details>')
        else:
            if room["room_type"] == "BOSS":
                A('<div style="font-size:12px;color:#f0a04b;margin-top:8px">'
                  '<b>本房当前不出怪。</b>设计源未写 <code>boss_content_id</code>，'
                  '且 <code>BossContentCatalog</code> 没有单层远征对应条目 ⇒ 无 BOSS 档案，'
                  '也无精英随从；房间开局即视为已清。下面这 %d 个落点（按 2.2m BOSS 安全半径算）随时可用，'
                  '缺的只是一条首领指派。</div>' % len(room["spawn_points"]))
            else:
                A('<div style="font-size:12px;color:var(--dim);margin-top:8px">'
                  '本房无 <code>enemy_spawn_plan</code> ⇒ 不接入设计源刷怪。'
                  '事件房走 <code>_ensure_event_room_objective</code> 的紫色光柱目标，不出敌人。</div>')
        A('</div>')
    A('</div>')

    # 自检
    A('<h2>4 · 落点合法性自检（本图自带断言）</h2>')
    A('<div class="sub">判据：本图量的是「地砖并集边界」（= 5m 墙心线，见上文「避让基准」）—— 实际用到的每个落点，到最近边界的净距 ≥ 安全半径；'
      '两两间距 ≥ 2×安全半径。净距用 0.05m 步进沿 ±x/±z 直走到离开地砖并集测得（离散下界）。</div>')
    A('<table><thead><tr><th>房号</th><th>类型</th><th>安全半径 m</th><th>用量内最小离墙 m</th>'
      '<th>用量内最小间距 m</th><th>全部候选最小离墙 m</th><th>结论</th></tr></thead><tbody>')
    for c in checks:
        room = c["room"]
        if not c["used"]:
            A('<tr><td class="mono">%s</td><td>%s</td><td class="mono">%.2f</td>'
              '<td class="mono">—</td><td class="mono">—</td><td class="mono">%.2f</td>'
              '<td>不适用（本房不刷怪）</td></tr>'
              % (room["room_id"], ROOM_TYPE_ZH.get(room["room_type"], room["room_type"]),
                 c["clearance"], c["min_gap"]))
            continue
        A('<tr><td class="mono">%s</td><td>%s</td><td class="mono">%.2f</td>'
          '<td class="mono">%.2f</td><td class="mono">%s</td><td class="mono">%.2f</td>'
          '<td class="%s">%s</td></tr>'
          % (room["room_id"], ROOM_TYPE_ZH.get(room["room_type"], room["room_type"]), c["clearance"],
             c["used_gap"], ("%.2f" % c["used_pair"]) if c["used"] > 1 else "—",
             c["min_gap"], "ok" if c["ok"] else "bad", "通过" if c["ok"] else "不通过"))
    A('</tbody></table>')

    A('<div class="note" style="margin-top:26px"><b>看图须知</b><br>'
      '· 本图对应 <b>run_seed=%d</b>。远征01 的<b>版图几何每局按种子现算</b>'
      '（<code>FloorPlanGenerator._generate_constrained_floor</code>：房型池洗牌 + 主路贴墙自避走），'
      '所以<b>房间的位置、尺寸、连法每局都不同</b>；本图的<b>落点分布形状</b>（先四角、再沿轮廓、后收心）'
      '是算法的稳定特征，具体坐标随局变化。<br>'
      '· <b>内容类型按房号钉死</b>（<code>room_01</code>…<code>room_10</code> 的 COMBAT/SCAVENGE/STORAGE/EVENT 固定），'
      '<b>房型按种子抽</b>，<b>刷怪编成半钉死</b>（波次数钉死、每波种类与数量按种子抽）。<br>'
      '· 入口安全屋 <code>start</code> 无 <code>enemy_spawn_plan</code>、也无壳体地砖清单，'
      '其落点走「无 authored 地砖 ⇒ 按 5m 模数整铺」分支（<code>_build_spawn_points</code> 的 else 路），'
      '本图已按同一分支补画其 3×3 格。<br>'
      '· 探针以 <code>test_mode=true</code> 启动、只等 12 帧就截图，玩家尚未进房 ⇒ '
      '<code>_alive_by_room</code> 全为 0（<code>_prepare_revealed_hostile_room</code> 还没被触发）。'
      '因此本图的落点是<b>直接问 <code>spawn_point_for_index()</code> 要的</b>，'
      '与「开门时首波会怎么站」是同一条函数，但不依赖是否已经真的刷过怪。</div>' % seed["seed"])

    A('</div></body></html>')

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(html))
    print("wrote", OUT)
    bad = [c["room"]["room_id"] for c in checks if not c["ok"]]
    print("self-check:", "ALL PASS" if not bad else "FAIL %s" % bad)
    for c in checks:
        print("  %-11s used=%d clearance=%.2f min_gap(used)=%.2f min_pair(used)=%.2f"
              % (c["room"]["room_id"], c["used"], c["clearance"], c["used_gap"], c["used_pair"]))


if __name__ == "__main__":
    build()
