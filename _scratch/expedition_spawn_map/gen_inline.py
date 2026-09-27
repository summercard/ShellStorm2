"""生成内嵌 widget 用的总览 SVG（680 宽，主题中性，透明底）。

数据源：spawn_map.json（Godot headless 探针实测）
输出：inline_overview.svg（每元素一行，便于整体读取）
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
SEED = json.load(open(os.path.join(HERE, "spawn_map.json"), encoding="utf-8"))["seeds"][0]
ROOMS = SEED["rooms"]

# 房型 → 色盘（淡色填充 + 400 中间调描边：明暗两种主题下都可读）
RAMPS = {
    "STAIR_LOBBY": ("#5DCAA5", "#1D9E75"),
    "COMBAT": ("#F09595", "#E24B4A"),
    "SCAVENGE": ("#FAC775", "#BA7517"),
    "STORAGE": ("#85B7EB", "#378ADD"),
    "EVENT": ("#AFA9EC", "#7F77DD"),
    "BOSS": ("#F0997B", "#D85A30"),
    "EXTRACTION": ("#5DCAA5", "#1D9E75"),
}
NAME = {"STAIR_LOBBY": "入口安全屋", "COMBAT": "战斗房", "SCAVENGE": "搜刮房", "STORAGE": "仓储房",
        "EVENT": "事件房", "BOSS": "BOSS 竞技场", "EXTRACTION": "撤离屋"}

pts = []
for room in ROOMS:
    pts += room["tile_cells_world"]
    if not room["tile_cells_world"]:
        dx, dz = room["dimensions"]
        for sx in (-0.5, 0.5):
            for sz in (-0.5, 0.5):
                pts.append([room["origin"][0] + dx * sx, room["origin"][1] + dz * sz])
MINX = min(p[0] for p in pts) - 8
MAXX = max(p[0] for p in pts) + 24
MINZ = min(p[1] for p in pts) - 8
MAXZ = max(p[1] for p in pts) + 14
W = 680.0
S = W / (MAXX - MINX)
H = (MAXZ - MINZ) * S


def X(v):
    return (v - MINX) * S


def Y(v):
    return (v - MINZ) * S


def used_of(room):
    return max([len(w) for w in room["rolled_waves"]] or [0])


out = []
out.append('<svg viewBox="0 0 680 %.0f" width="100%%" role="img" '
           'xmlns="http://www.w3.org/2000/svg">' % H)
out.append('<title>远征关卡01 刷怪落点总览</title>')
out.append('<desc>13 个房间按 5m 地砖实际轮廓绘制，红点为该房刷怪落点（仅标本房最大一波的用量），'
           '橙线为门与主路连接。</desc>')
out.append('<rect x="0" y="0" width="680" height="%.0f" fill="none"/>' % H)

by_id = {r["room_id"]: r for r in ROOMS}
for room in ROOMS:
    for door in room["doors"]:
        other = by_id.get(door["target"])
        if other is None:
            continue
        path = "M%.1f %.1fL%.1f %.1fL%.1f %.1f" % (
            X(room["origin"][0]), Y(room["origin"][1]),
            X(room["origin"][0] + door["local"][0]), Y(room["origin"][1] + door["local"][1]),
            X(other["origin"][0]), Y(other["origin"][1]),
        )
        out.append('<path d="%s" fill="none" stroke="#EF9F27" stroke-opacity="0.5" '
                   'stroke-width="1.5" stroke-dasharray="5 4"/>' % path)

tile = 5.0 * S
for room in ROOMS:
    light, dark = RAMPS.get(room["room_type"], ("#B4B2A9", "#5F5E5A"))
    cells = room["tile_cells_world"]
    if cells:
        # 同行连续格合并成一条 run，减少元素数
        rows = {}
        for cx, cz in cells:
            rows.setdefault(round(cz, 3), []).append(round(cx, 3))
        for cz in sorted(rows):
            xs = sorted(rows[cz])
            start = xs[0]
            span = 1
            for k in range(1, len(xs) + 1):
                if k < len(xs) and abs(xs[k] - xs[k - 1] - 5.0) < 1e-6:
                    span += 1
                    continue
                out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" '
                           'fill-opacity="0.26" stroke="%s" stroke-opacity="0.75" stroke-width="0.5"/>'
                           % (X(start - 2.5), Y(cz - 2.5), span * tile, tile, light, dark))
                if k < len(xs):
                    start = xs[k]
                    span = 1
    else:
        dx, dz = room["dimensions"]
        out.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s" '
                   'fill-opacity="0.26" stroke="%s" stroke-opacity="0.85" stroke-width="0.5"/>'
                   % (X(room["origin"][0] - dx / 2), Y(room["origin"][1] - dz / 2),
                      dx * S, dz * S, light, dark))

for room in ROOMS:
    for door in room["doors"]:
        cx = X(room["origin"][0] + door["local"][0])
        cy = Y(room["origin"][1] + door["local"][1])
        if door["dir"] in ("north", "south"):
            out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#EF9F27" '
                       'stroke-width="3"/>' % (cx - 4, cy, cx + 4, cy))
        else:
            out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#EF9F27" '
                       'stroke-width="3"/>' % (cx, cy - 4, cx, cy + 4))

for room in ROOMS:
    for p in room["spawn_points"][:used_of(room)]:
        out.append('<circle cx="%.1f" cy="%.1f" r="2.6" fill="#E24B4A" '
                   'stroke="currentColor" stroke-opacity="0.45" stroke-width="0.6"/>'
                   % (X(p["world"][0]), Y(p["world"][1])))

for room in ROOMS:
    cx = X(room["origin"][0])
    cy = Y(room["origin"][1])
    used = used_of(room)
    label = {"start": "入口", "boss": "BOSS", "extraction": "撤离"}.get(
        room["room_id"], room["room_id"])
    out.append('<text x="%.1f" y="%.1f" font-size="12" font-weight="500" fill="currentColor" '
               'text-anchor="middle" font-family="system-ui,sans-serif">%s</text>'
               % (cx, cy - 3, label))
    out.append('<text x="%.1f" y="%.1f" font-size="11" fill="currentColor" fill-opacity="0.65" '
               'text-anchor="middle" font-family="system-ui,sans-serif">%s · %d 只</text>'
               % (cx, cy + 11, NAME.get(room["room_type"], room["room_type"]), used))

out.append('</svg>')
with open(os.path.join(HERE, "inline_overview.svg"), "w", encoding="utf-8", newline="\n") as fh:
    fh.write("\n".join(out) + "\n")
print("H=%.0f  lines=%d" % (H, len(out)))
