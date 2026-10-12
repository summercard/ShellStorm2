#!/usr/bin/env python3
"""远征关卡02「破败旅馆」平面图集生成器。

两个真源，各取所长：
  · 房间表（几何）—— 设计页 §4.2；层叠关系 —— §4.3
  · **门位 —— 白盒的 asset_manifest.json**（构建脚本导出，避免门位被手抄两遍、改一处漏一处）

产物：
  docs/v0.1/design/refs/expedition02/plans/00-单层平面图.svg
  docs/v0.1/design/refs/expedition02/plans/01-五层纵剖图.svg
  docs/v0.1/design/refs/expedition02/远征关卡02平面图集.html

用法：python3 scripts/render_expedition02_plan_sheet.py
"""

from __future__ import annotations

import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGN_MD = ROOT / "docs" / "v0.1" / "design" / "远征关卡02设计.md"
MANIFEST = (
    ROOT / "art_source/design/whitebox/tower_zones/expedition_02/v001"
    / "data/component_packages/hotel_floor_01/远征关卡02_白模_第1层_长廊与客房/asset_manifest.json"
)
OUT_DIR = ROOT / "docs" / "v0.1" / "design" / "refs" / "expedition02"
PLANS_DIR = OUT_DIR / "plans"

KIND = {
    "SAFE":    dict(fill="#EAF3DE", stroke="#639922", ink="#27500A"),
    "MAIN":    dict(fill="#E6F1FB", stroke="#378ADD", ink="#0C447C"),
    "BRANCH":  dict(fill="#F3EEFB", stroke="#7F77DD", ink="#3C3489"),
    "BOSS":    dict(fill="#FCEBEB", stroke="#E24B4A", ink="#791F1F"),
    "EXTRACT": dict(fill="#FAEEDA", stroke="#EF9F27", ink="#633806"),
}
# 门三种形态各自的画法
DOOR_STYLE = {
    "door":     dict(stroke="#185FA5", width=2.6, label="标准门 2.2×2.5"),
    "collapse": dict(stroke="#B4342A", width=3.0, label="坍塌门洞 5.0 宽 × 2.5 高"),
    "open":     dict(stroke="#0F6E56", width=3.2, label="5m 通洞（顶到墙顶）"),
}
HOLE = dict(fill="#FDE8E8", stroke="#B4342A", ink="#7B241C")
SLAB = "#94A3B8"
SLAB_FILL = "#CBD5E1"
GRID_C = "#e6ebf2"
INK = "#0f172a"
MUTED = "#64748b"
ROUTE = "#185FA5"

S = 5.0
LAYER_H = 12.0

ROLE_TO_KIND = {
    "stair_entry": "SAFE", "main": "MAIN", "branch": "BRANCH",
    "boss": "BOSS", "extraction": "EXTRACT",
}

STYLE = """
text{font-family:"Microsoft YaHei","PingFang SC",system-ui,sans-serif}
.ttl{font-size:17px;font-weight:700;fill:%(ink)s}
.sub{font-size:12px;fill:%(muted)s}
.rn{font-size:11.5px;font-weight:700}
.rd{font-size:10px;fill:%(muted)s}
.tag{font-size:10px;font-weight:700}
.dim{font-size:9.5px;fill:%(muted)s}
.lay{font-size:12px;font-weight:700;fill:%(ink)s}
.mono{font-family:Consolas,"Cascadia Mono",ui-monospace,monospace;font-size:10px}
""" % dict(ink=INK, muted=MUTED)


def _svg_open(w: float, h: float, title: str) -> list[str]:
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:.0f}" height="{h:.0f}" '
        f'viewBox="0 0 {w:.0f} {h:.0f}" role="img" aria-label="{html.escape(title)}">',
        f"<defs><style>{STYLE}</style>",
        '<pattern id="hatch" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">'
        f'<rect width="6" height="6" fill="{HOLE["fill"]}"/>'
        f'<line x1="0" y1="0" x2="0" y2="6" stroke="{HOLE["stroke"]}" stroke-width="1.4" opacity="0.55"/>'
        "</pattern>",
        '<marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" '
        'orient="auto-start-reverse">'
        f'<path d="M0 1L9 5L0 9" fill="none" stroke="{ROUTE}" stroke-width="1.8" '
        'stroke-linecap="round" stroke-linejoin="round"/></marker>',
        '<marker id="ard" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" '
        'orient="auto-start-reverse">'
        f'<path d="M0 1L9 5L0 9" fill="none" stroke="{HOLE["stroke"]}" stroke-width="1.8" '
        'stroke-linecap="round" stroke-linejoin="round"/></marker>',
        "</defs>",
        f'<rect width="{w:.0f}" height="{h:.0f}" fill="#ffffff"/>',
    ]


# ---------------------------------------------------------------- 解析

def _cells(line: str) -> list[str]:
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _is_sep(cells: list[str]) -> bool:
    return bool(cells) and all(set(c) <= set("-: ") for c in cells if c)


def _block(text: str, start_marker: str) -> str:
    i = text.index(start_marker) + len(start_marker)
    ends = [p for p in (text.find("\n### ", i), text.find("\n## ", i)) if p != -1]
    return text[i:min(ends)] if ends else text[i:]


def _table_after(text: str, start_marker: str, header_keys: tuple[str, ...]) -> list[list[str]]:
    lines = _block(text, start_marker).splitlines()
    start = None
    for i, l in enumerate(lines):
        if l.startswith("|") and all(k in l for k in header_keys):
            start = i + 2
            break
    if start is None:
        raise SystemExit("%s 里找不到表头（应包含 %s）" % (start_marker, "、".join(header_keys)))
    out: list[list[str]] = []
    for l in lines[start:]:
        if not l.startswith("|"):
            break
        cs = _cells(l)
        if _is_sep(cs):
            continue
        out.append(cs)
    return out


def _num(s: str) -> float:
    return float(re.sub(r"[\u2212\u2013\u2014\uff0d]", "-", s).replace(" ", ""))


def _size(s: str) -> tuple[float, float]:
    # 设计页里关键尺寸会加粗（**30 × 15**），解析前先剥掉标记
    s = s.replace("*", "").replace("`", "")
    m = re.match(r"(\d+(?:\.\d+)?)\s*[×x]\s*(\d+(?:\.\d+)?)", s.replace(" ", ""))
    if not m:
        raise SystemExit("尺寸列无法解析：%r" % s)
    return float(m.group(1)), float(m.group(2))


def _xy(s: str) -> tuple[float, float]:
    s = re.sub(r"[\u2212\u2013\u2014\uff0d]", "-", s)
    m = re.search(r"\(\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*\)", s)
    if not m:
        raise SystemExit("中心坐标无法解析：%r" % s)
    return float(m.group(1)), float(m.group(2))


def parse_rooms() -> tuple[list[dict], str]:
    md = DESIGN_MD.read_text(encoding="utf-8")
    rows = _table_after(md, "### 4.2 单层房表", ("key", "中心"))
    rooms: list[dict] = []
    for cs in rows:
        if len(cs) < 8:
            raise SystemExit("§4.2 行少于 8 列：%s" % cs)
        role = cs[3].strip("`").strip()
        if role not in ROLE_TO_KIND:
            raise SystemExit("§4.2 未知角色 %r" % role)
        w, d = _size(cs[4])
        cx, cy = _xy(cs[5])
        parent = cs[6].strip("`").strip()
        rooms.append(dict(
            n=len(rooms) + 1, key=cs[1].strip("`").strip(), name=cs[2], role=role,
            w=w, d=d, cx=cx, cy=cy,
            parent="" if parent in ("—", "-", "") else parent,
            clear=_num(re.sub(r"[^\d.\-]", "", cs[7]) or "0"),
            kind=ROLE_TO_KIND[role],
        ))
    if not rooms:
        raise SystemExit("§4.2 未解析到任何房间")
    return rooms, md


def parse_layers(md: str) -> list[dict]:
    rows = _table_after(md, "### 4.3 五层怎么叠", ("floor_index", "世界"))
    layers: list[dict] = []
    for cs in rows:
        if len(cs) < 6:
            raise SystemExit("§4.3 行少于 6 列：%s" % cs)
        layers.append(dict(label=cs[0], floor_number=int(cs[1]), floor_index=int(cs[2]),
                           world_y=_num(cs[3]),
                           has_tall_hall=("有" in cs[5] and "无" not in cs[5])))
    if not layers:
        raise SystemExit("§4.3 未解析到任何层")
    for i, L in enumerate(layers):
        if abs(L["world_y"] - (-LAYER_H * L["floor_index"])) > 0.001:
            raise SystemExit("§4.3 第 %d 层世界 Y 与 −12×floor_index 不符" % (i + 1))
    return layers


def parse_doors() -> list[dict]:
    """门位真源 = 白盒 manifest（构建脚本导出）。"""
    if not MANIFEST.exists():
        raise SystemExit("找不到白盒 manifest，先跑 build_expedition02_whitebox_v001.py：%s" % MANIFEST)
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    doors = data.get("doors") or []
    if not doors:
        raise SystemExit("manifest 里没有 doors —— 构建脚本的门表导出断了？")
    return doors


# ---------------------------------------------------------------- 单层平面图

def build_plan(rooms, layers, doors) -> str:
    xs = [r["cx"] - r["w"] / 2 for r in rooms] + [r["cx"] + r["w"] / 2 for r in rooms]
    ys = [r["cy"] - r["d"] / 2 for r in rooms] + [r["cy"] + r["d"] / 2 for r in rooms]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)

    m_l, m_t = 60.0, 116.0
    plan_w, plan_h = (x1 - x0) * S, (y1 - y0) * S
    col_w = 336.0
    w = m_l + plan_w + 46 + col_w + 40
    h = m_t + plan_h + 96
    px = lambda v: m_l + (v - x0) * S          # noqa: E731
    py = lambda v: m_t + (v - y0) * S          # noqa: E731  上 = 北（y 小 = 北 ⇒ 最北 y0 在顶部）

    s = _svg_open(w, h, "远征关卡02 单层平面图")
    s.append(f'<text class="ttl" x="{m_l}" y="32">远征关卡02 · 破败旅馆 — 单层平面图（第 1 层）</text>')
    s.append(f'<text class="sub" x="{m_l}" y="52">五层结构相同。本图为第 1 层；纵向上方为北。'
             f'由南向北：图下方 = 南端入口，图上方 = 北端。</text>')
    s.append(f'<text class="sub" x="{m_l}" y="70">1 m = {S:.0f} px ｜ 单层包络 {x1 - x0:.0f} × {y1 - y0:.0f} m ｜ '
             f'净高：挑高前厅 11.9 m ／ 其余 3.0 m ／ 坍塌洞 2.5 m</text>')
    s.append(f'<text class="sub" x="{m_l}" y="88">按地砖 5×5 m 规格；两轴均为 5 m 整数倍，FIXED_TRIM 收边 0 件。'
             f'门位读自白盒 manifest，非手抄。</text>')

    gx = x0
    while gx <= x1 + 0.01:
        s.append(f'<line x1="{px(gx):.1f}" y1="{py(y1):.1f}" x2="{px(gx):.1f}" y2="{py(y0):.1f}" '
                 f'stroke="{GRID_C}" stroke-width="1"/>')
        gx += 5.0
    gy = y0
    while gy <= y1 + 0.01:
        s.append(f'<line x1="{px(x0):.1f}" y1="{py(gy):.1f}" x2="{px(x1):.1f}" y2="{py(gy):.1f}" '
                 f'stroke="{GRID_C}" stroke-width="1"/>')
        gy += 5.0

    by_key = {r["key"]: r for r in rooms}
    for r in rooms:
        k = KIND[r["kind"]]
        rx, ry = px(r["cx"] - r["w"] / 2), py(r["cy"] - r["d"] / 2)
        rw, rh = r["w"] * S, r["d"] * S
        s.append(f'<rect x="{rx:.1f}" y="{ry:.1f}" width="{rw:.1f}" height="{rh:.1f}" '
                 f'fill="{k["fill"]}" stroke="{k["stroke"]}" stroke-width="1.6" rx="3"/>')
        # 平面图上名字要短：15m 房只有 75px 宽，「客房W10（西·外侧）」会溢出撞邻格。
        # 全名仍在右侧清单与 HTML 表格里。
        short = re.sub(r"（.*?）", "", r["name"])
        # T 字横廊的地板里画着破碎空洞，名字居中会压住洞 ⇒ 挪到左段
        lx = (rx + 56.0) if r["key"] == "room_13" else (rx + rw / 2)
        s.append(f'<text class="rn" x="{lx:.1f}" y="{ry + rh / 2 + 2:.1f}" fill="{k["ink"]}" '
                 f'{"text-anchor=\"start\"" if r["key"] == "room_13" else "text-anchor=\"middle\""}>{html.escape(short)}</text>')
        s.append(f'<circle cx="{rx + 13:.1f}" cy="{ry + 13:.1f}" r="9" fill="{k["stroke"]}"/>')
        s.append(f'<text x="{rx + 13:.1f}" y="{ry + 16.5:.1f}" text-anchor="middle" '
                 f'font-size="10.5" font-weight="700" fill="#ffffff">{r["n"]}</text>')

    # 门：真源 = manifest。axis 'v' ⇒ 门在 x=const 的竖墙上，沿墙门心是 y。
    n_door = n_col = n_open = 0
    for d in doors:
        k = str(d["kind"])
        st = DOOR_STYLE[k]
        axis, coord = str(d["axis"]), float(d["line_coord_m"])
        c = float(d["opening_center_m"])
        span = float(d["opening_width_m"])
        if axis == "v":
            cx, cy, horiz = coord, c, False
        else:
            cx, cy, horiz = c, coord, True
        L, T = span * S, st["width"] * 2.6
        if horiz:
            s.append(f'<rect x="{px(cx) - L / 2:.1f}" y="{py(cy) - T / 2:.1f}" width="{L:.1f}" '
                     f'height="{T:.1f}" fill="#ffffff" stroke="{st["stroke"]}" '
                     f'stroke-width="{st["width"]:.1f}"/>')
        else:
            s.append(f'<rect x="{px(cx) - T / 2:.1f}" y="{py(cy) - L / 2:.1f}" width="{T:.1f}" '
                     f'height="{L:.1f}" fill="#ffffff" stroke="{st["stroke"]}" '
                     f'stroke-width="{st["width"]:.1f}"/>')
        if k == "door":
            n_door += 1
        elif k == "collapse":
            n_col += 1
        else:
            n_open += 1
    # 特别标注坍塌洞
    for d in doors:
        if str(d["kind"]) != "collapse":
            continue
        c = float(d["opening_center_m"])
        coord = float(d["line_coord_m"])
        # 标签放门洞正上方（挑高前厅内）—— 那里 y>30，不与下方客房行重叠
        # py 随 y 增大而增大（南在下）⇒ 前厅在 y=30 线的**下方**，标签要 +16 才落在前厅里
        s.append(f'<text class="tag" x="{px(c) + 6:.1f}" y="{py(coord) + 16:.1f}" '
                 f'fill="{HOLE["ink"]}">↑ 坍塌门洞 5.0 宽 × 2.5 高</text>')

    # 主路动线：南端阳台 → 挑高前厅 → 长廊 → T 字路口 → 支廊
    pts = [(by_key["entry"]["cx"], by_key["entry"]["cy"]),
           (by_key["room_01"]["cx"], by_key["room_01"]["cy"]),
           (by_key["room_02"]["cx"], by_key["room_02"]["cy"]),
           (by_key["room_13"]["cx"], by_key["room_13"]["cy"])]
    d = "M " + " L ".join(f"{px(a):.1f} {py(b):.1f}" for a, b in pts)
    s.append(f'<path d="{d}" fill="none" stroke="{ROUTE}" stroke-width="2.4" stroke-dasharray="8 5" '
             f'opacity="0.7" marker-end="url(#ar)"/>')

    # 破碎空洞（待定）—— 标在 T 字横廊里
    hy = -50.0
    s.append(f'<rect x="{px(-5):.1f}" y="{py(hy + 5):.1f}" width="{10 * S:.1f}" height="{10 * S:.1f}" '
             f'fill="url(#hatch)" stroke="{HOLE["stroke"]}" stroke-width="2.2" stroke-dasharray="6 4"/>')
    hlx = px(5.0) + 12
    s.append(f'<text class="tag" x="{hlx:.1f}" y="{py(hy) - 6:.1f}" '
             f'fill="{HOLE["ink"]}">破碎空洞</text>')
    s.append(f'<text class="dim" x="{hlx:.1f}" y="{py(hy) + 9:.1f}" '
             f'fill="{HOLE["ink"]}">位置 / 尺寸待定</text>')
    s.append(f'<text class="dim" x="{hlx:.1f}" y="{py(hy) + 23:.1f}" '
             f'fill="{HOLE["ink"]}">↓ 落 −12 m 到第 2 层</text>')

    # 指北针
    ax, ay = m_l + plan_w + 22, m_t + 26
    s.append(f'<line x1="{ax:.1f}" y1="{ay + 26:.1f}" x2="{ax:.1f}" y2="{ay - 12:.1f}" '
             f'stroke="{INK}" stroke-width="2"/>')
    s.append(f'<path d="M{ax:.1f} {ay - 20:.1f} L{ax - 6:.1f} {ay - 6:.1f} L{ax + 6:.1f} {ay - 6:.1f} Z" '
             f'fill="{INK}"/>')
    s.append(f'<text class="lay" x="{ax:.1f}" y="{ay + 42:.1f}" text-anchor="middle">北</text>')

    # 右侧清单
    cx0 = m_l + plan_w + 64
    s.append(f'<text class="lay" x="{cx0:.1f}" y="{m_t + 6:.1f}">房间清单（{len(rooms)} 间）</text>')
    s.append(f'<line x1="{cx0:.1f}" y1="{m_t + 16:.1f}" x2="{cx0 + col_w:.1f}" y2="{m_t + 16:.1f}" '
             f'stroke="{SLAB}" stroke-width="1"/>')
    for i, htxt in enumerate(["#", "key", "尺寸", "中心", "净高"]):
        s.append(f'<text class="dim" x="{cx0 + [0.0, 24.0, 118.0, 176.0, 272.0][i]:.1f}" '
                 f'y="{m_t + 30:.1f}">{htxt}</text>')
    for j, r in enumerate(rooms):
        yy = m_t + 46 + j * 30
        s.append(f'<line x1="{cx0:.1f}" y1="{yy - 11:.1f}" x2="{cx0 + col_w:.1f}" y2="{yy - 11:.1f}" '
                 f'stroke="{GRID_C}" stroke-width="1"/>')
        s.append(f'<text class="rd" x="{cx0:.1f}" y="{yy:.1f}" font-weight="700" '
                 f'fill="{KIND[r["kind"]]["ink"]}">{r["n"]}</text>')
        s.append(f'<text class="rd" x="{cx0 + 24:.1f}" y="{yy:.1f}" fill="{INK}">'
                 f'{html.escape(r["name"])}</text>')
        s.append(f'<text class="dim" x="{cx0 + 118.0:.1f}" y="{yy:.1f}">{r["w"]:g}×{r["d"]:g}</text>')
        s.append(f'<text class="dim" x="{cx0 + 176.0:.1f}" y="{yy:.1f}">'
                 f'({r["cx"]:g}, {r["cy"]:g})</text>')
        s.append(f'<text class="dim" x="{cx0 + 272.0:.1f}" y="{yy:.1f}">{r["clear"]:g}</text>')

    ly0 = m_t + plan_h + 28
    s.append(f'<text class="dim" x="{m_l:.1f}" y="{ly0:.1f}">'
             f'图例：绿 = 阳台安全屋 ｜ 蓝 = 主路（前厅 / 长廊 / 横廊 / 支廊） ｜ 紫 = 客房（支线） ｜ '
             f'斜纹 = 破碎空洞（层间通道）</text>')
    s.append(f'<text class="dim" x="{m_l:.1f}" y="{ly0 + 16:.1f}">'
             f'门：蓝框 = 标准门 2.2×2.5（{n_door} 处） ｜ 红框 = 坍塌门洞 5.0 宽 × 2.5 高（{n_col} 处） ｜ '
             f'绿框 = 5m 通洞、顶到墙顶（{n_open} 处，用于长廊↔横廊、横廊↔两条支廊）</text>')
    s.append(f'<text class="dim" x="{m_l:.1f}" y="{ly0 + 32:.1f}">'
             f'门槽取自 RoomDoorLane.lane_offsets()：10 m → ±2.5；15 m → 0；30 m → ±2.5/±7.5；'
             f'45 m → ±15/±10/±5/0；60 m → ±22.5…±2.5；75 m → ±30…±5。画面上方为北（平面 +y = 世界 +z = 南）。</text>')
    s.append("</svg>")
    return "\n".join(s)


# ---------------------------------------------------------------- 五层纵剖图

def build_section(rooms, layers) -> str:
    by_key = {r["key"]: r for r in rooms}
    # 剖面沿 x = 0，切到的房间：阳台 / 挑高前厅 / 长廊 / T 字横廊
    cut = [by_key[k] for k in ("entry", "room_01", "room_02", "room_13")]

    m_l, m_t, m_r, m_b = 128.0, 166.0, 150.0, 100.0
    band = LAYER_H * S
    w = 160 * S + m_l + m_r
    h = m_t + len(layers) * band + m_b
    ux = lambda v: m_l + (60.0 - v) * S        # noqa: E731  左 = 南（y=+60）→ 右 = 北（y=−70）

    s = _svg_open(w, h, "远征关卡02 五层纵剖图")
    s.append(f'<text class="ttl" x="{m_l}" y="32">远征关卡02 · 破败旅馆 — 五层纵剖图（沿 x = 0，向东看）</text>')
    s.append(f'<text class="sub" x="{m_l}" y="52">整关是一个空间，五层上下叠放、层间隔 {LAYER_H:.0f} m，'
             f'像 98F 与 99F 的关系；层间靠地板破洞贯通，不用楼梯。走廊沿南→北。</text>')
    s.append(f'<text class="sub" x="{m_l}" y="70">横轴 = 平面南北向（160 m，左南右北），切过'
             f'「阳台 → 挑高前厅 → 长廊 → T 字横廊」这条主轴。</text>')
    s.append(f'<text class="sub" x="{m_l}" y="88">第 1 层挑高前厅通高 11.9 m；第 2–5 层没有挑高前厅，全层 3.0 m。</text>')
    s.append(f'<text class="sub" x="{m_l}" y="106">长廊两侧 10 间 + 两条支廊两侧 10 间，共 20 间客房垂直于本剖面（见单层平面图）。横轴最右段（y = −55…−100）只有两条 45 m 支廊，它们位于 x = ±20、垂直于本剖面，故此处留白。</text>')

    for i, L in enumerate(layers):
        top = m_t + i * band
        floor = top + band
        if i % 2 == 0:
            s.append(f'<rect x="{m_l - 16:.1f}" y="{top:.1f}" width="{160 * S + 32:.1f}" '
                     f'height="{band:.1f}" fill="#f8fafc"/>')

        for room in cut:
            a = room["cy"] - room["d"] / 2
            b = room["cy"] + room["d"] / 2
            hgt = room["clear"] if L["has_tall_hall"] or room["key"] != "room_01" else 3.0
            dashed = not L["has_tall_hall"] and room["key"] == "room_01"
            k = KIND[room["kind"]]
            dash = ' stroke-dasharray="4 3"' if dashed else ""
            op = 0.5 if dashed else 0.96
            la, lb = ux(b), ux(a)
            s.append(f'<rect x="{la:.1f}" y="{floor - hgt * S:.1f}" width="{lb - la:.1f}" '
                     f'height="{hgt * S:.1f}" fill="{k["fill"]}" stroke="{k["stroke"]}" '
                     f'stroke-width="1.4"{dash} opacity="{op}"/>')
            label = f'{room["name"]} {hgt:g} m'
            if hgt * S < 34 or (lb - la) < 78:
                s.append(f'<text class="rd" x="{la + 5:.1f}" y="{floor - hgt * S + 12:.1f}">{label}</text>')
            else:
                s.append(f'<text class="rd" x="{la + 7:.1f}" y="{floor - hgt * S + 16:.1f}">'
                         f'{room["name"]} ｜ 净高 {hgt:g} m</text>')

        s.append(f'<rect x="{ux(60.0):.1f}" y="{floor:.1f}" width="{160 * S:.1f}" height="5.0" '
                 f'fill="{SLAB_FILL}" stroke="{SLAB}" stroke-width="1.2"/>')
        # 破洞（待定）在 T 字横廊
        hy = -50.0
        ha, hb = ux(hy + 5.0), ux(hy - 5.0)
        s.append(f'<rect x="{ha:.1f}" y="{floor - 1:.1f}" width="{hb - ha:.1f}" height="6.8" '
                 f'fill="{HOLE["fill"]}" stroke="{HOLE["stroke"]}" stroke-width="1.8" '
                 f'stroke-dasharray="5 3"/>')
        if i < len(layers) - 1:
            mid = (ha + hb) / 2
            s.append(f'<line x1="{mid:.1f}" y1="{floor + 7:.1f}" x2="{mid:.1f}" '
                     f'y2="{floor + band - 12:.1f}" stroke="{HOLE["stroke"]}" stroke-width="2.6" '
                     f'marker-end="url(#ard)"/>')
            s.append(f'<text class="tag" x="{mid + 7:.1f}" y="{floor + 20:.1f}" '
                     f'fill="{HOLE["ink"]}">破洞 落 −{LAYER_H:.0f} m</text>')

        gx = m_l - 118
        gy = top + band / 2
        s.append(f'<text class="lay" x="{gx:.1f}" y="{gy - 10:.1f}">{html.escape(L["label"])}</text>')
        s.append(f'<text class="dim" x="{gx:.1f}" y="{gy + 5:.1f}">'
                 f'floor_number {L["floor_number"]} / index {L["floor_index"]}</text>')
        s.append(f'<text class="dim" x="{gx:.1f}" y="{gy + 19:.1f}">世界 Y = {L["world_y"]:g} m</text>')
        s.append(f'<text class="dim" x="{gx:.1f}" y="{gy + 33:.1f}">'
                 f'{"有挑高 11.9 m" if L["has_tall_hall"] else "全层 3.0 m"}</text>')

    by = m_t + len(layers) * band + 28
    s.append(f'<text class="tag" x="{m_l:.1f}" y="{by:.1f}" fill="{HOLE["ink"]}">'
             f'第 5 层（底层）：主轴之后接 Boss 房 → 撤离点（位置待裁决 L02-10）。</text>')
    s.append(f'<text class="dim" x="{m_l:.1f}" y="{by + 18:.1f}">'
             f'用户 2026-10-12：「下面的层级不会有挑高层，都是 3 米高的房间和走廊」。</text>')
    s.append(f'<text class="dim" x="{m_l:.1f}" y="{by + 34:.1f}">'
             f'每层封顶；楼顶封板与破洞挡光是「全楼不受日照」的前置条件（见设计页 §5.2）。</text>')
    s.append("</svg>")
    return "\n".join(s)


# ---------------------------------------------------------------- HTML

def build_html(plan_svg, section_svg, rooms, layers) -> str:
    rw = "".join(
        f'<tr><td>{r["n"]}</td><td><code>{html.escape(r["key"])}</code></td>'
        f'<td>{html.escape(r["name"])}</td><td><code>{html.escape(r["role"])}</code></td>'
        f'<td>{r["w"]:g} × {r["d"]:g}</td><td>({r["cx"]:g}, {r["cy"]:g})</td>'
        f'<td>{r["w"] * r["d"]:g}</td><td>{r["clear"]:g}</td>'
        f'<td>{html.escape(r["parent"]) or "—"}</td></tr>' for r in rooms)
    lw = "".join(
        f'<tr><td>{html.escape(L["label"])}</td><td>{L["floor_number"]}</td>'
        f'<td>{L["floor_index"]}</td><td>{L["world_y"]:g}</td>'
        f'<td>{"有（11.9 m）" if L["has_tall_hall"] else "无（全 3.0 m）"}</td></tr>' for L in layers)
    return f"""<!DOCTYPE html>
<html lang="zh-CN"><meta charset="utf-8">
<title>远征关卡02 平面图集</title>
<style>
 body{{margin:0;padding:28px 32px 56px;background:#f6f8fb;color:{INK};
      font-family:"Microsoft YaHei","PingFang SC",system-ui,sans-serif}}
 h1{{font-size:22px;margin:0 0 6px}}
 h2{{font-size:16px;margin:34px 0 10px;border-left:4px solid {ROUTE};padding-left:10px}}
 p.note{{color:{MUTED};font-size:13px;margin:4px 0 0;line-height:1.7}}
 .card{{background:#fff;border:1px solid #e2e8f0;border-radius:12px;padding:18px;margin-top:14px;overflow:auto}}
 svg{{display:block;max-width:100%;height:auto}}
 table{{border-collapse:collapse;font-size:13px;width:100%}}
 th,td{{border:1px solid #e2e8f0;padding:6px 9px;text-align:left}}
 th{{background:#eef3f9}} code{{background:#eef3f9;padding:1px 5px;border-radius:4px}}
</style>
<h1>远征关卡02 · 破败旅馆 — 平面图集</h1>
<p class="note">五层垂直下行。单层 = 阳台安全屋 → 挑高前厅（横置 30×15）→ 坍塌门洞 → 旅馆长廊（10×75，独立房间、贯通）
→ 东西两侧各 5 间客房 → 北端 T 字路口（40 m 横廊，两端各向北折 15 m）→ 支廊外侧各 1 间客房。</p>
<p class="note"><b>房间表来自设计页 §4.2、层叠关系来自 §4.3、<u>门位读自白盒 manifest</u></b>；
由 <code>scripts/render_expedition02_plan_sheet.py</code> 生成，改表就重跑。</p>

<h2>一 · 单层平面图（第 1 层）</h2>
<div class="card">{plan_svg}</div>

<h2>二 · 五层纵剖图（沿 x = 0）</h2>
<div class="card">{section_svg}</div>

<h2>三 · 单层房表</h2>
<div class="card"><table>
<tr><th>#</th><th>key</th><th>中文名</th><th>角色</th><th>尺寸 宽×深 (m)</th>
<th>中心 (x, y)</th><th>面积 (m²)</th><th>净高 (m)</th><th>父房</th></tr>
{rw}</table></div>

<h2>四 · 五层叠放</h2>
<div class="card"><table>
<tr><th>层</th><th>floor_number</th><th>floor_index</th><th>世界 Y</th><th>挑高前厅</th></tr>
{lw}</table></div>

<h2>五 · 绘制口径</h2>
<div class="card"><p class="note">
① 坐标单位米，平面 <code>+y</code> = 南、<code>−y</code> = 北；画面上方为北。<br>
② 尺寸比例 1 m = {S:.0f} px；房间按外轮廓矩形绘制，未画内墙与陈设。<br>
③ 破洞位置与尺寸<b>待定</b>，图中为示意占位。<br>
④ 门槽取自 <code>RoomDoorLane.lane_offsets()</code>；<b>门位数值读自白盒 manifest</b>，不在本脚本里手抄。<br>
⑤ 楼层世界 Y = −{LAYER_H:.0f} × <code>floor_index</code>（层高为全局常量）。<br>
⑥ 剖面横轴切过主轴 4 间房；长廊两侧 10 间 + 支廊两侧 10 间，共 20 间客房垂直于剖面。
</p></div>
</html>
"""


def main() -> int:
    rooms, md = parse_rooms()
    layers = parse_layers(md)
    doors = parse_doors()

    PLANS_DIR.mkdir(parents=True, exist_ok=True)
    plan_svg = build_plan(rooms, layers, doors)
    sect_svg = build_section(rooms, layers)

    outs = {
        PLANS_DIR / "00-单层平面图.svg": plan_svg,
        PLANS_DIR / "01-五层纵剖图.svg": sect_svg,
        OUT_DIR / "远征关卡02平面图集.html": build_html(plan_svg, sect_svg, rooms, layers),
    }
    for p in list(PLANS_DIR.glob("*.svg")) + list(PLANS_DIR.glob("*.svg.import")):
        if p not in outs:
            p.unlink()
    for path, text in outs.items():
        path.write_bytes(text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8"))
    for path in outs:
        b = path.read_bytes()
        if b.count(b"\r\n") != b.count(b"\n") or b.count(b"\r") != b.count(b"\r\n"):
            raise SystemExit("行尾不纯（应为纯 CRLF）：%s" % path)

    kinds = {}
    for d in doors:
        kinds[str(d["kind"])] = kinds.get(str(d["kind"]), 0) + 1
    print("EXPEDITION02_PLAN_SHEET_OK rooms=%d layers=%d doors=%s files=%d"
          % (len(rooms), len(layers), kinds, len(outs)))
    for p in outs:
        print("  %s" % p.relative_to(ROOT).as_posix())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
