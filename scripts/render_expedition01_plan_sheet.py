# -*- coding: utf-8 -*-
"""生成《远征关卡01 平面图集》（自包含 HTML，内嵌 SVG）。

用法：python scripts/render_expedition01_plan_sheet.py
幂等：每次全量重写全部输出文件，不读旧产物。

真源（版图一改就要重跑本脚本）—— **文档即数据源**，房间尺寸 / 定位 / 坐标 / 父房直接解析设计页表格：
  docs/v0.1/design/远征关卡01设计.md            §3.1 总表（编号/中文名/定位/房型/尺寸/面积）
                                                §4.2 坐标草案（中心 x,y / 父房）
  source/art/whitebox/tower_zones/expedition_01/v001/data/level_plan.json
      site 250x250 居中 (2.5, 2.5) / grid_unit_m 5 / floor_height_m 12

输出（图纸是示意稿，几何真源始终是 floor_00.json）：
  docs/v0.1/design/refs/expedition01/远征关卡01平面图集.html   自包含图集（含明细表）
  docs/v0.1/design/refs/expedition01/总平面图.svg             单张总平面图
  docs/v0.1/design/refs/expedition01/plans/00-总平面图.svg     设计页内联用的成套图
  docs/v0.1/design/refs/expedition01/plans/NN-<房名>.svg      每房一张（NN = 01..N，按总表顺序）
"""

import json
import math
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]
OUTDIR = ROOT / "docs/v0.1/design/refs/expedition01"
PLANDIR = OUTDIR / "plans"
DESIGN_MD = ROOT / "docs/v0.1/design/远征关卡01设计.md"
LEVEL_PLAN = ROOT / "source/art/whitebox/tower_zones/expedition_01/v001/data/level_plan.json"

# ---------------------------------------------------------------- 基础工具

def n(v):
    s = f"{float(v):.2f}".rstrip("0").rstrip(".")
    return s if s not in ("", "-0") else "0"


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def rect(x, y, w, h, fill="none", stroke="none", sw=0.5, rx=0, dash=None, op=None):
    a = f'<rect x="{n(x)}" y="{n(y)}" width="{n(w)}" height="{n(h)}"'
    if rx:
        a += f' rx="{n(rx)}"'
    a += f' fill="{fill}" stroke="{stroke}" stroke-width="{n(sw)}"'
    if dash:
        a += f' stroke-dasharray="{dash}"'
    if op is not None:
        a += f' opacity="{n(op)}"'
    return a + "/>"


def poly(pts, fill="none", stroke="none", sw=0.5, dash=None, op=None):
    p = " ".join(f"{n(x)},{n(y)}" for x, y in pts)
    a = f'<polygon points="{p}" fill="{fill}" stroke="{stroke}" stroke-width="{n(sw)}"'
    if dash:
        a += f' stroke-dasharray="{dash}"'
    if op is not None:
        a += f' opacity="{n(op)}"'
    return a + "/>"


def pline(pts, stroke="#334155", sw=0.5, dash=None):
    p = " ".join(f"{n(x)},{n(y)}" for x, y in pts)
    a = f'<polyline points="{p}" fill="none" stroke="{stroke}" stroke-width="{n(sw)}"'
    if dash:
        a += f' stroke-dasharray="{dash}"'
    return a + "/>"


def line(x1, y1, x2, y2, stroke="#334155", sw=0.5, dash=None, marker=None):
    a = (f'<line x1="{n(x1)}" y1="{n(y1)}" x2="{n(x2)}" y2="{n(y2)}" '
         f'stroke="{stroke}" stroke-width="{n(sw)}"')
    if dash:
        a += f' stroke-dasharray="{dash}"'
    if marker:
        a += f' marker-end="url(#{marker})"'
    return a + "/>"


def text(x, y, s, size=12, anchor="middle", fill="#0f172a", weight="400", base="middle"):
    return (f'<text x="{n(x)}" y="{n(y)}" font-size="{n(size)}" font-weight="{weight}" '
            f'text-anchor="{anchor}" dominant-baseline="{base}" fill="{fill}">{esc(s)}</text>')


def circle(cx, cy, r, fill="#ffffff", stroke="#334155", sw=0.5):
    return (f'<circle cx="{n(cx)}" cy="{n(cy)}" r="{n(r)}" fill="{fill}" '
            f'stroke="{stroke}" stroke-width="{n(sw)}"/>')


ARROW_DEFS = """<defs>
<marker id="ar" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
<path d="M2 1L8 5L2 9" fill="none" stroke="context-stroke" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
</marker>
<marker id="ar-s" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="4.5" markerHeight="4.5" orient="auto-start-reverse">
<path d="M2 1L8 5L2 9" fill="none" stroke="context-stroke" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
</marker>
</defs>"""

# ---------------------------------------------------------------- 配色与常量

# 浅色主题（visualizer 色板 50 填充 / 600 描边 / 800 文字）
KIND = {
    "SAFE":    dict(fill="#EAF3DE", stroke="#639922", ink="#27500A", label="特殊 · 安全屋"),
    "COMMON":  dict(fill="#E6F1FB", stroke="#378ADD", ink="#0C447C", label="主路 · 通用房"),
    "BRANCH":  dict(fill="#F3EEFB", stroke="#7F77DD", ink="#3C3489", label="支线 · 通用房"),
    "BOSS":    dict(fill="#FCEBEB", stroke="#E24B4A", ink="#791F1F", label="特殊 · 首领房"),
    "EXTRACT": dict(fill="#FAEEDA", stroke="#EF9F27", ink="#633806", label="特殊 · 撤离屋"),
}
INK = "#0f172a"
MUTED = "#64748b"
DIM = "#475569"
GRID_C = "#e6ebf2"
CONNECT = "#B8B5A9"
ROUTE = "#185FA5"

KIND_BY_ROOM_TYPE = {
    "SAFE_ROOM": "SAFE",
    "COMMON_ROOM": "COMMON",
    "BOSS_ROOM": "BOSS",
    "EXTRACTION_ROOM": "EXTRACT",
}
KEY_WHEN_NO_CODE = {"SAFE_ROOM": "start", "BOSS_ROOM": "boss", "EXTRACTION_ROOM": "extraction"}

# ---------------------------------------------------------------- 数据（从设计页解析）
#
# 文档即数据源：尺寸 / 定位 取自设计页 §3.1 总表，坐标 / 父房 取自 §4.2 坐标草案。
# 改了文档就重跑本脚本，图纸跟着变；解析不出来直接报错退出，不静默出半张图。

_PLAN = json.loads(LEVEL_PLAN.read_text(encoding="utf-8"))
SITE_S = float(_PLAN["site"]["size_m"][0])
SITE_CX, SITE_CY = (float(v) for v in _PLAN["site"]["center_m"])
SITE_X0, SITE_X1 = SITE_CX - SITE_S / 2, SITE_CX + SITE_S / 2   # -122.5 .. 127.5
SITE_Y0, SITE_Y1 = SITE_CY - SITE_S / 2, SITE_CY + SITE_S / 2

WALL_T = 0.30
CORRIDOR_W = 6.0


def _cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def _num(s):
    """把表格里的负数写法（半角 -、U+2212 −、en/em dash、全角 －）归一成 float。"""
    return float(re.sub(r"[\u2212\u2013\u2014\uff0d]", "-", s).replace(" ", ""))


def _is_sep(cells):
    return all(set(c) <= set("-: ") for c in cells if c) and cells


def _block(text, start_marker):
    """取 start_marker 所在小节正文，到下一条 '### ' 或 '## ' 为止。"""
    i = text.index(start_marker) + len(start_marker)
    ends = [p for p in (text.find("\n### ", i), text.find("\n## ", i)) if p != -1]
    return text[i: min(ends)] if ends else text[i:]


def _table_after(text, start_marker, header_keys):
    """取 start_marker 小节里「含 header_keys 的表头」之后的连续表格行（逐行 cells）。

    只吃紧邻的连续表格，所以后面再插别的表也不会被误读。
    """
    lines = _block(text, start_marker).splitlines()
    start = None
    for i, l in enumerate(lines):
        if l.startswith("|") and all(k in l for k in header_keys):
            start = i + 2                      # 跳过表头与分隔行
            break
    if start is None:
        raise SystemExit("%s 里找不到表头（应包含 %s）—— 表结构被改动了？"
                         % (start_marker, "、".join(header_keys)))
    out = []
    for l in lines[start:]:
        if not l.startswith("|"):
            break
        cells = _cells(l)
        if _is_sep(cells):
            continue
        out.append(cells)
    return out


def parse_design_rooms():
    md = DESIGN_MD.read_text(encoding="utf-8")

    # ---- §3.1 总表：编号 / 中文名 / 定位 / 房型 / 尺寸 / 面积 / 参考图
    rows = []
    for cells in _table_after(md, "### 3.1 总表", ("编号", "尺寸", "面积")):
        if len(cells) < 6:
            continue
        code = cells[0].strip("`").strip()
        name, placement, rtype, dims = cells[1], cells[2].strip(), cells[3], cells[4]
        m = re.match(r"(\d+(?:\.\d+)?)\s*[×x]\s*(\d+(?:\.\d+)?)", dims)
        if not m:
            raise SystemExit("§3.1 尺寸列无法解析：%r（行：%s）" % (dims, name))
        if rtype not in KIND_BY_ROOM_TYPE:
            raise SystemExit("§3.1 未知房型 %r（%s）—— 请在 KIND_BY_ROOM_TYPE 里补映射" % (rtype, name))
        kind = "BRANCH" if placement == "支线" else KIND_BY_ROOM_TYPE[rtype]
        area_txt = re.sub(r"[^\d.]", "", cells[5])
        rows.append(dict(
            key=code or KEY_WHEN_NO_CODE[rtype],
            name=name,
            kind=kind,
            room_type=rtype,
            placement=placement,
            w=float(m.group(1)),
            d=float(m.group(2)),
            area=float(area_txt) if area_txt else 0.0,
        ))

    # ---- §4.2 坐标草案：编号 -> 中心 (x, y) / 父房
    centres = {}
    parents = {}
    for cells in _table_after(md, "### 4.2 坐标草案", ("编号", "中心")):
        if len(cells) < 5:
            continue
        rkey = cells[0].strip("`").strip()
        m = re.search(r"\(\s*([^\s,]+)\s*,\s*([^\s)]+)\s*\)", cells[3])
        if m:
            centres[rkey] = (_num(m.group(1)), _num(m.group(2)))
        p = cells[4].strip().strip("`").strip()
        parents[rkey] = None if p in ("—", "-", "") else p

    for i, r in enumerate(rows, 1):
        r["i"] = i
        if r["key"] not in centres:
            raise SystemExit("§4.2 坐标草案里找不到房间「%s」的中心坐标" % r["key"])
        r["cx"], r["cy"] = centres[r["key"]]
        r["parent"] = parents.get(r["key"])
        r["x0"] = r["cx"] - r["w"] / 2.0
        r["x1"] = r["cx"] + r["w"] / 2.0
        r["y0"] = r["cy"] - r["d"] / 2.0
        r["y1"] = r["cy"] + r["d"] / 2.0

    if not rows:
        raise SystemExit("§3.1 未解析到任何房型 —— 表结构可能被改动了")
    for r in rows:
        if r["parent"] and r["parent"] not in {x["key"] for x in rows}:
            raise SystemExit("§4.2 房间「%s」的父房「%s」不在总表里" % (r["key"], r["parent"]))
    return rows


ROOMS = parse_design_rooms()
BY_KEY = {r["key"]: r for r in ROOMS}

# 父子连接（A -> B；方向由坐标决定）
LINKS = [(r["parent"], r["key"]) for r in ROOMS if r["parent"]]

# 主路顺序：入口 → 主路内容房 → 首领 → 撤离
ENTRY_KEY = next((r["key"] for r in ROOMS if r["room_type"] == "SAFE_ROOM"), "start")
BOSS_KEY = next((r["key"] for r in ROOMS if r["room_type"] == "BOSS_ROOM"), "boss")
EXIT_KEY = next((r["key"] for r in ROOMS if r["room_type"] == "EXTRACTION_ROOM"), "extraction")
MAIN_SEQUENCE = ([ENTRY_KEY]
                 + [r["key"] for r in ROOMS if r["placement"] == "主路"]
                 + [BOSS_KEY, EXIT_KEY])
BRANCH_KEYS = [r["key"] for r in ROOMS if r["kind"] == "BRANCH"]

# 子房索引
CHILDREN = {}
for _r in ROOMS:
    if _r["parent"]:
        CHILDREN.setdefault(_r["parent"], []).append(_r["key"])


def neighbor_side(r, other):
    """返回 (side, off)：other 落在 r 的哪面墙、沿该墙相对墙中心的偏移（米）。"""
    dx = other["cx"] - r["cx"]
    dy = other["cy"] - r["cy"]
    if abs(dx) >= abs(dy):
        side = "east" if dx >= 0 else "west"
        return side, (r["cy"] + other["cy"]) / 2.0 - r["cy"]
    side = "north" if dy < 0 else "south"        # 平面 +y = 南；局部 +y = 画面向下 = 南
    return side, (r["cx"] + other["cx"]) / 2.0 - r["cx"]


def doors_for(r):
    out = []
    if r["parent"]:
        out.append(neighbor_side(r, BY_KEY[r["parent"]]))
    for ck in CHILDREN.get(r["key"], []):
        out.append(neighbor_side(r, BY_KEY[ck]))
    return out


# ---------------------------------------------------------------- 总平面图

PAD = 30.0
S = 620.0 / SITE_S          # 2.48 px/m
VW, VH = 680.0, 680.0


def gx(x):
    return PAD + S * (x - SITE_X0)


def gy(y):
    return PAD + S * (y - SITE_Y0)


def build_overview(with_grid=True):
    o = [f'<svg viewBox="0 0 {n(VW)} {n(VH)}" width="100%" xmlns="http://www.w3.org/2000/svg" '
         f'role="img" font-family="system-ui, -apple-system, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif">',
         '<title>远征关卡01 总平面图</title>',
         f'<desc>主路 {len(MAIN_SEQUENCE)} 房墙贴墙 + {len(BRANCH_KEYS)} 间支线房（各挂主路中间 4 房之一）的平面示意，含场地边界、5 米网格与房间连接。</desc>',
         ARROW_DEFS]

    # 场地
    o.append(rect(gx(SITE_X0), gy(SITE_Y0), S * SITE_S, S * SITE_S, "#fbfcfe", "#94a3b8", 0.5, 3))
    if with_grid:
        step = 25.0
        v = SITE_X0
        while v <= SITE_X1 + 1e-6:
            if abs(v % 50) < 1e-6:
                v += step
                continue
            o.append(line(gx(v), gy(SITE_Y0), gx(v), gy(SITE_Y1), GRID_C, 0.5))
            v += step
        v = SITE_Y0
        while v <= SITE_Y1 + 1e-6:
            if abs(v % 50) < 1e-6:
                v += step
                continue
            o.append(line(gx(SITE_X0), gy(v), gx(SITE_X1), gy(v), GRID_C, 0.5))
            v += step
    # 核心区（65x65 居中 2.5,2.5），仅参考
    cx0, cy0 = 2.5 - 32.5, 2.5 - 32.5
    o.append(rect(gx(cx0), gy(cy0), S * 65, S * 65, "none", "#c7b9e8", 0.6, 0, "5 3"))
    o.append(text(gx(2.5), gy(2.5), "核心区 65×65", 10, "middle", "#7F77DD", "500"))
    o.append(text(gx(2.5), gy(2.5) + 13, "本关不避让（enforce_core_exclusion = false）", 9, "middle", "#9a8fd0"))

    # 支线连接（先画，压在房间下）：父房中心 -> 子房中心 的灰色虚线
    for a, b in LINKS:
        ra, rb = BY_KEY[a], BY_KEY[b]
        if a == ENTRY_KEY or b in MAIN_SEQUENCE:
            continue                                   # 主路自己走蓝色实线
        o.append(line(gx(ra["cx"]), gy(ra["cy"]), gx(rb["cx"]), gy(rb["cy"]),
                      CONNECT, 1.0, "5 4"))

    # 主路方向（蓝色实线 + 每段中点一个箭头）
    pts = [(gx(BY_KEY[k]["cx"]), gy(BY_KEY[k]["cy"])) for k in MAIN_SEQUENCE]
    o.append(pline(pts, ROUTE, 1.8))
    for i in range(len(pts) - 1):
        (x1, y1), (x2, y2) = pts[i], pts[i + 1]
        mx, my = (x1 + x2) / 2.0, (y1 + y2) / 2.0
        length = math.hypot(x2 - x1, y2 - y1)
        if length < 1e-6:
            continue
        ux, uy = (x2 - x1) / length, (y2 - y1) / length
        o.append(line(mx - ux * 7, my - uy * 7, mx + ux * 7, my + uy * 7,
                      ROUTE, 1.8, None, "ar"))

    # 房间
    for r in ROOMS:
        k = KIND[r["kind"]]
        o.append(rect(gx(r["x0"]), gy(r["y0"]), S * r["w"], S * r["d"], k["fill"], k["stroke"], 1.2, 2))
        px_w = S * r["w"]
        px_h = S * r["d"]
        cx, cy = gx(r["cx"]), gy(r["cy"])
        if px_w >= 70 and px_h >= 40:
            o.append(text(cx, cy - 9, r["name"], 12.5, "middle", k["ink"], "500"))
            o.append(text(cx, cy + 6, f'{n(r["w"])} × {n(r["d"])} m', 10.5, "middle", k["ink"]))
            o.append(text(cx, cy + 20, f'{r["key"]} · {n(r["w"] * r["d"])} m²', 9.5, "middle", k["ink"]))
        else:
            o.append(text(cx, cy - 3, r["name"], 10.5, "middle", k["ink"], "500"))
            o.append(text(cx, cy + 11, f'{n(r["w"])}×{n(r["d"])}', 9.5, "middle", k["ink"]))
        # 序号角标（窄房放到框外，避免压住房名）
        if px_w >= 75:
            bx, by = gx(r["x0"]) + 9, gy(r["y0"]) + 9
        else:
            bx, by = gx(r["x0"]) - 9, gy(r["y0"]) - 9
        o.append(circle(bx, by, 8, "#ffffff", k["stroke"], 0.8))
        o.append(text(bx, by + 0.5, str(r["i"]), 9.5, "middle", k["ink"], "500"))

    # 标题
    o.append(text(gx(SITE_X0) + 8, gy(SITE_Y0) + 14, "远征关卡01 · 总平面图（示意）", 12, "start", INK, "500"))
    o.append(text(gx(SITE_X0) + 8, gy(SITE_Y0) + 29,
                  f'场地 250×250 m ｜ 5 m 网格 ｜ 层高 12 m ｜ 主路 {len(MAIN_SEQUENCE)} 房墙贴墙 + {len(BRANCH_KEYS)} 支线房（示例版图）',
                  10, "start", MUTED))

    # 指北针（+y = 南 = 画面向下 ⇒ 北在画面向上）
    nx, ny = gx(SITE_X1) - 26, gy(SITE_Y0) + 30
    o.append(line(nx, ny + 14, nx, ny - 8, INK, 1.2, None, "ar"))
    o.append(text(nx, ny + 24, "北", 10, "middle", INK, "500"))

    # 图例
    lx, ly = gx(SITE_X0) + 8, gy(SITE_Y1) - 80
    o.append(rect(lx, ly, 250, 74, "#ffffff", "#cbd5e1", 0.5, 6, None, 0.9))
    o.append(text(lx + 8, ly + 14, "图例", 10.5, "start", INK, "500"))
    order = ["SAFE", "COMMON", "BRANCH", "BOSS", "EXTRACT"]
    for i, kk in enumerate(order):
        k = KIND[kk]
        px = lx + 8 + (i % 2) * 120
        py = ly + 30 + (i // 2) * 18
        o.append(rect(px, py - 5, 11, 10, k["fill"], k["stroke"], 0.8, 2))
        o.append(text(px + 16, py, k["label"], 9.5, "start", DIM))
    o.append(line(lx + 8, ly + 30 + 3 * 18 - 5, lx + 30, ly + 30 + 3 * 18 - 5, ROUTE, 1.8))
    o.append(text(lx + 34, ly + 30 + 3 * 18, "主路", 9.5, "start", DIM))
    o.append(line(lx + 8, ly + 30 + 3 * 18 + 13, lx + 30, ly + 30 + 3 * 18 + 13, CONNECT, 1.0, "5 4"))
    o.append(text(lx + 34, ly + 30 + 3 * 18 + 18, "支线", 9.5, "start", DIM))

    o.append("</svg>")
    return "".join(o)


# ---------------------------------------------------------------- 详图

DS = 6.0          # 详图比例 px/m（各图统一，可直接比大小）
DPAD = 24.0


def door_marker(X, Y, r, side, off, width=4.4):
    """在指定墙面上画门开口（白底 + 虚线），off 为相对墙中心的偏移（米）。"""
    if side in ("north", "south"):
        yy = 0.0 if side == "north" else r["d"]
        xx = r["w"] / 2.0 + off - width / 2.0
        return (line(X(xx), Y(yy), X(xx + width), Y(yy), "#ffffff", 3.6)
                + line(X(xx), Y(yy), X(xx + width), Y(yy), DIM, 0.9, "3 2"))
    xx = 0.0 if side == "west" else r["w"]
    yy = r["d"] / 2.0 + off - width / 2.0
    return (line(X(xx), Y(yy), X(xx), Y(yy + width), "#ffffff", 3.6)
            + line(X(xx), Y(yy), X(xx), Y(yy + width), DIM, 0.9, "3 2"))


def detail_svg(r, inner, doors):
    """r: 房间 dict；inner(X, Y) -> 局部坐标绘制片段；doors: [(side, off)]"""
    cw = r["w"] * DS + DPAD * 2
    ch = r["d"] * DS + DPAD * 2
    k = KIND[r["kind"]]

    def X(vx):
        return DPAD + vx * DS

    def Y(vy):
        return DPAD + vy * DS

    o = [f'<svg width="{n(cw)}" height="{n(ch)}" viewBox="0 0 {n(cw)} {n(ch)}" '
         f'xmlns="http://www.w3.org/2000/svg" '
         f'role="img" font-family="system-ui, -apple-system, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif" '
         f'style="max-width:100%;height:auto">',
         f'<title>{esc(r["name"])} 平面示意</title>',
         f'<desc>{esc(r["name"])}：{n(r["w"])} × {n(r["d"])} 米房型的内部结构平面示意。</desc>',
         ARROW_DEFS]

    # 5 m 网格
    v = 0.0
    while v <= r["w"] + 1e-6:
        o.append(line(X(v), Y(0), X(v), Y(r["d"]), "#eef2f7", 0.5))
        v += 5
    v = 0.0
    while v <= r["d"] + 1e-6:
        o.append(line(X(0), Y(v), X(r["w"]), Y(v), "#eef2f7", 0.5))
        v += 5

    o += inner(X, Y)
    for side, off in doors:
        o.append(door_marker(X, Y, r, side, off))
    o.append("</svg>")
    return "".join(o)


def label(X, Y, x, y, s, size=10, fill=DIM, anchor="middle", weight="400"):
    return text(X(x), Y(y), s, size, anchor, fill, weight)


def build_details():
    """返回 key -> inner(X, Y) 绘制函数（只画房体与内部设施；门由 detail_svg 统一画）。"""
    out = {}

    # ---- 安全屋 15x15
    def safe(X, Y):
        k = KIND["SAFE"]
        g = [rect(X(0), Y(0), 15 * DS, 15 * DS, k["fill"], k["stroke"], 1.2, 2)]
        g.append(circle(X(7.5), Y(9), 5, "#ffffff", k["stroke"], 0.8))
        g.append(label(X, Y, 7.5, 9, "抵达", 8, k["ink"]))
        g.append(line(X(2.2), Y(15), X(9.2), Y(15), "#ffffff", 3.6))     # 弃局门（南墙，示意）
        g.append(line(X(2.2), Y(15), X(9.2), Y(15), DIM, 0.9, "3 2"))
        g.append(label(X, Y, 7.5, 10.8, "15 × 15 m · 双门互垂", 9, MUTED))
        g.append(label(X, Y, 5.7, 13.6, "弃局门", 8.5, k["ink"]))
        return g
    out["entry"] = safe

    # ---- 拐角走廊01 45x40（L 形）
    def c1(X, Y):
        k = KIND["COMMON"]
        walk = [(0, 0), (45, 0), (45, 15), (15, 15), (15, 40), (0, 40)]
        g = [poly([(X(a), Y(b)) for a, b in walk], k["fill"], k["stroke"], 1.2)]
        g.append(pline([(X(15), Y(40)), (X(15), Y(15)), (X(45), Y(15))], k["stroke"], 0.8))
        for i in range(4):
            g.append(rect(X(21 + i * 5.4), Y(0.8), 3.4 * DS * 0.55, 2.2 * DS * 0.55, "#cfe3f7", k["stroke"], 0.6, 1))
        g.append(rect(X(1.2), Y(28), 3.6, 7, "#cfe3f7", k["stroke"], 0.6, 1))
        g.append(label(X, Y, 7.5, 20, "竖臂 15 × 25", 9, k["ink"]))
        g.append(label(X, Y, 29, 7.5, "横臂 45 × 15 · 净宽 15 m", 9, k["ink"]))
        g.append(label(X, Y, 22.5, 38.2, "45 × 40 m · 单拐角 L 形", 9, MUTED))
        return g
    out["room_01"] = c1

    # ---- 拐角走廊02 45x40（凹字形折返）
    def c2(X, Y):
        k = KIND["COMMON"]
        g = [rect(X(0), Y(0), 45 * DS, 40 * DS, "#ffffff", k["stroke"], 1.2, 2)]
        for pts in ([(0, 0), (45, 0), (45, 15), (0, 15)],
                    [(30, 15), (45, 15), (45, 25), (30, 25)],
                    [(0, 25), (45, 25), (45, 40), (0, 40)]):
            g.append(poly([(X(a), Y(b)) for a, b in pts], k["fill"], k["stroke"], 0.8))
        g.append(rect(X(0), Y(15), 30 * DS, 10 * DS, "#f1f5f9", k["stroke"], 1.0))
        g.append(label(X, Y, 15, 20, "内墙岛 30 × 10", 9, DIM))
        g.append(label(X, Y, 22.5, 1.6, "上横臂 45 × 15", 9, k["ink"]))
        g.append(label(X, Y, 37.5, 20, "竖 15×10", 8.5, k["ink"]))
        g.append(label(X, Y, 22.5, 33, "下横臂 45 × 15", 9, k["ink"]))
        g.append(label(X, Y, 22.5, 38.4, "45 × 40 m · 凹字形折返", 9, MUTED))
        return g
    out["room_04"] = c2

    # ---- Boss 竞技场 50x40
    def boss(X, Y):
        k = KIND["BOSS"]
        g = [rect(X(0), Y(0), 50 * DS, 40 * DS, k["fill"], k["stroke"], 1.2, 2)]
        g.append(rect(X(14), Y(1.2), 22 * DS, 3.4 * DS, "#f7c1c1", k["stroke"], 0.8, 1))
        g.append(label(X, Y, 25, 3.4, "主机故障屏", 9, k["ink"]))
        for i in range(3):
            g.append(rect(X(6 + i * 5.6), Y(10), 3.6, 6, "#f2d3d3", k["stroke"], 0.6, 1))
        for i in range(3):
            g.append(rect(X(32 + i * 5.6), Y(24), 3.6, 6, "#f2d3d3", k["stroke"], 0.6, 1))
        g.append(rect(X(20), Y(30), 10 * DS, 5 * DS, "#ffffff", k["stroke"], 0.7, 1))
        g.append(label(X, Y, 25, 32.5, "工作站", 9, k["ink"]))
        g.append(label(X, Y, 25, 19.5, "50 × 40 m · 四墙房间", 10, MUTED))
        g.append(label(X, Y, 25, 7.5, "机柜成组", 9, k["ink"]))
        return g
    out["boss"] = boss

    # ---- 撤离屋 25x25
    def ext(X, Y):
        k = KIND["EXTRACT"]
        g = [rect(X(0), Y(0), 25 * DS, 25 * DS, k["fill"], k["stroke"], 1.2, 2)]
        g.append(circle(X(12.5), Y(12.5), 6, "#ffffff", k["stroke"], 1.0))
        g.append(circle(X(12.5), Y(12.5), 2.4, "#EF9F27", k["stroke"], 0.8))
        g.append(label(X, Y, 12.5, 19.6, "撤离信标", 9, k["ink"]))
        g.append(label(X, Y, 12.5, 23.4, "25 × 25 m · 空房 · 不刷怪", 8.5, MUTED))
        return g
    out["extraction"] = ext

    # ---- 数据库房间01 70x50（不规则：南边中段内凹）
    def db1(X, Y):
        k = KIND["BRANCH"]
        walk = [(0, 0), (70, 0), (70, 40), (42, 40), (42, 50), (22, 50), (22, 40), (0, 40)]
        g = [poly([(X(a), Y(b)) for a, b in walk], k["fill"], k["stroke"], 1.2)]
        for i in range(7):
            g.append(rect(X(3), Y(5 + i * 4.2), 3.4, 3.4, "#cbdcf0", k["stroke"], 0.6, 1))
        for i in range(7):
            g.append(rect(X(12 + i * 4.2), Y(3), 3.4, 3.4, "#cbdcf0", k["stroke"], 0.6, 1))
        g.append(rect(X(48), Y(6), 18 * DS, 14 * DS, "#ffffff", k["stroke"], 0.7, 2, "4 3"))
        g.append(label(X, Y, 57, 13, "检修工位区", 9, k["ink"]))
        g.append(label(X, Y, 32, 46.5, "南边中段内凹 20 × 10", 9, DIM))
        g.append(label(X, Y, 56, 46.5, "70 × 50 m · 不规则", 9, MUTED))
        g.append(label(X, Y, 20, 6.5, "机柜列", 9, k["ink"]))
        return g
    out["room_02"] = db1
    out["branch_01"] = db1

    # ---- 办公室01 60x70
    def off(X, Y):
        k = KIND["BRANCH"]
        g = [rect(X(0), Y(0), 60 * DS, 70 * DS, k["fill"], k["stroke"], 1.2, 2)]
        spots = [(11, 12), (33, 11), (50, 16), (16, 34), (42, 33), (27, 55)]
        for tx, ty in spots:
            g.append(rect(X(tx - 3.5), Y(ty - 2), 7 * DS, 2.4 * DS, "#ffffff", k["stroke"], 0.7, 1))
            g.append(circle(X(tx), Y(ty + 2.1), 2.6, "#ffffff", k["stroke"], 0.7))
        for i in range(5):
            g.append(rect(X(50 + i * 1.8), Y(58 + (i % 2)), 1.5 * DS, 6 * DS * 0.5, "#dbe9f8", k["stroke"], 0.6, 1))
        g.append(rect(X(1), Y(6), 1.8 * DS, 14 * DS * 0.5, "#dbe9f8", k["stroke"], 0.6, 1))
        g.append(label(X, Y, 30, 66.5, "60 × 70 m · 无内墙（最大单间 4200 m²）", 9, MUTED))
        g.append(label(X, Y, 30, 4.2, "工位 6 组", 9, DIM))
        return g
    out["room_03"] = off

    # ---- 数据库房间02 70x50（不规则：左下 + 右下内凹）
    def db2(X, Y):
        k = KIND["BRANCH"]
        walk = [(0, 0), (70, 0), (70, 38), (52, 38), (52, 50), (18, 50), (18, 32), (0, 32)]
        g = [poly([(X(a), Y(b)) for a, b in walk], k["fill"], k["stroke"], 1.2)]
        for row in range(4):
            for col in range(6):
                g.append(rect(X(8 + col * 8.4), Y(9 + row * 5.8), 5.6, 3.4, "#cbdcf0", k["stroke"], 0.6, 1))
        g.append(rect(X(2.2), Y(14), 4.4, 7, "#FAC775", "#BA7517", 0.8, 1))
        g.append(label(X, Y, 4.4, 24, "叉车", 8.5, "#633806"))
        g.append(label(X, Y, 12, 47, "左下内凹 18 × 18", 9, DIM))
        g.append(label(X, Y, 61, 43.5, "右下内凹 18 × 12", 8.5, DIM))
        g.append(label(X, Y, 58, 47.5, "70 × 50 m · 不规则", 9, MUTED))
        g.append(label(X, Y, 35, 24, "货架 · 箱体堆场", 10, k["ink"], "middle", "500"))
        return g
    out["room_06"] = db2

    # ---- 通道桥房间 60x50（含下沉坑与桥）
    def bridge(X, Y):
        k = KIND["BRANCH"]
        g = [rect(X(0), Y(0), 60 * DS, 50 * DS, k["fill"], k["stroke"], 1.2, 2)]
        g.append(rect(X(15), Y(15), 30 * DS, 20 * DS, "#e2e8f0", "#94a3b8", 1.0, 0, "5 3"))
        g.append(label(X, Y, 30, 22, "下沉坑 30 × 20", 9, DIM))
        g.append(label(X, Y, 30, 27.5, "层高内高差（下层内容）", 8.5, DIM))
        g.append(rect(X(15), Y(20), 30 * DS, 5 * DS, "#cfe3f7", k["stroke"], 0.9))
        g.append(label(X, Y, 30, 17.4, "跨桥 5 m", 8.5, k["ink"]))
        for i in range(4):
            g.append(rect(X(17 + i * 7), Y(31), 2.6, 2.6, "#cbd5e1", "#94a3b8", 0.5, 1))
        g.append(line(X(15), Y(14), X(45), Y(14), "#94a3b8", 0.5, "3 2"))
        g.append(label(X, Y, 30, 47.6, "60 × 50 m · 上层通道净宽 15 m（唯一多层房型）", 9, MUTED))
        g.append(label(X, Y, 30, 4.1, "上层平台 · 通道", 9, k["ink"]))
        return g
    out["room_05"] = bridge
    out["branch_04"] = bridge

    # ---- 标准房间 25x25（空房，内容由 RuntimeDetail 流送）
    def std(X, Y):
        k = KIND["BRANCH"]
        g = [rect(X(0), Y(0), 25 * DS, 25 * DS, k["fill"], k["stroke"], 1.2, 2)]
        g.append(label(X, Y, 12.5, 12.5, "空房", 10, DIM))
        g.append(label(X, Y, 12.5, 22.4, "25 × 25 m · 四墙平房", 8.5, MUTED))
        g.append(label(X, Y, 12.5, 3.2, "内容由 RuntimeDetail 流送", 8, DIM))
        return g
    out["branch_02"] = std
    out["branch_03"] = std

    return out


# ---------------------------------------------------------------- HTML

CSS = """
:root{--ink:#0f172a;--dim:#475569;--muted:#64748b;--line:#e2e8f0;--bg:#f7f9fc;--card:#ffffff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);
 font-family:system-ui,-apple-system,"Segoe UI","PingFang SC","Microsoft YaHei",sans-serif;
 font-size:14px;line-height:1.7}
.wrap{max-width:1080px;margin:0 auto;padding:32px 24px 80px}
h1{font-size:22px;font-weight:600;margin:0 0 6px}
h2{font-size:17px;font-weight:600;margin:40px 0 12px;padding-bottom:8px;border-bottom:1px solid var(--line)}
h3{font-size:14px;font-weight:600;margin:0 0 2px}
p{margin:0 0 10px}
.lede{color:var(--dim);margin:0 0 18px}
.meta{display:flex;flex-wrap:wrap;gap:8px 20px;color:var(--muted);font-size:12px;
 padding:12px 16px;background:var(--card);border:1px solid var(--line);border-radius:10px;margin-bottom:8px}
.meta b{color:var(--dim);font-weight:500}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin:0 0 16px}
.card .cap{font-size:12px;color:var(--muted);margin:2px 0 0}
table{border-collapse:collapse;width:100%;font-size:13px;background:var(--card);
 border:1px solid var(--line);border-radius:10px;overflow:hidden}
th,td{padding:8px 10px;text-align:left;border-bottom:1px solid var(--line)}
th{background:#f1f5f9;font-weight:600;font-size:12px;color:var(--dim)}
tr:last-child td{border-bottom:0}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}
code{font-family:ui-monospace,Consolas,monospace;font-size:12px;background:#f1f5f9;
 padding:1px 5px;border-radius:4px}
.tag{display:inline-block;font-size:11px;padding:1px 8px;border-radius:99px;border:1px solid}
.t-safe{background:#EAF3DE;border-color:#639922;color:#27500A}
.t-common{background:#E6F1FB;border-color:#378ADD;color:#0C447C}
.t-branch{background:#F3EEFB;border-color:#7F77DD;color:#3C3489}
.t-boss{background:#FCEBEB;border-color:#E24B4A;color:#791F1F}
.t-extract{background:#FAEEDA;border-color:#EF9F27;color:#633806}
.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(430px,1fr));gap:16px}
.bar-row{display:grid;grid-template-columns:112px 1fr 84px;align-items:center;gap:10px;margin:0 0 6px;font-size:12px}
.bar{height:16px;background:#eef2f7;border-radius:4px;overflow:hidden}
.bar i{display:block;height:100%;background:#85B7EB;border-radius:4px}
.bar i.b-boss{background:#F09595}.bar i.b-safe{background:#97C459}.bar i.b-ext{background:#EF9F27}.bar i.b-branch{background:#AFA9EC}
.bar-val{text-align:right;color:var(--dim);font-variant-numeric:tabular-nums}
ol.flow{list-style:none;padding:0;margin:0;display:flex;flex-wrap:wrap;gap:8px;align-items:center}
ol.flow li{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:6px 12px;font-size:12.5px}
ol.flow li.sep{border:0;background:none;padding:0;color:var(--muted)}
.warn{background:#FAEEDA;border:1px solid #EF9F27;border-radius:10px;padding:12px 16px;font-size:13px;margin:0 0 16px}
.warn b{color:#633806}
.foot{margin-top:48px;padding-top:16px;border-top:1px solid var(--line);color:var(--muted);font-size:12px}
"""

TAG_CLASS = {"SAFE": "t-safe", "COMMON": "t-common", "BRANCH": "t-branch", "BOSS": "t-boss", "EXTRACT": "t-extract"}


def room_card(r, svg, extra=""):
    tag = TAG_CLASS[r["kind"]]
    placement = "· %s" % r["placement"] if r["placement"] else ""
    parent = " · 挂 <code>%s</code>" % r["parent"] if r["parent"] else ""
    return (f'<div class="card"><h3>{r["i"]}. {esc(r["name"])} '
            f'<span class="tag {tag}">{n(r["w"])} × {n(r["d"])} m</span></h3>'
            f'<p class="cap"><code>{r["key"]}</code> {placement}{parent} · 面积 {n(r["w"] * r["d"])} m² · {esc(extra)}</p>'
            f'{svg}</div>')


def build_html():
    dets = build_details()
    ov = build_overview()

    # 明细表
    rows = []
    for r in ROOMS:
        k = KIND[r["kind"]]
        rows.append(
            f'<tr><td class="num">{r["i"]}</td><td>{esc(r["name"])}</td><td><code>{r["key"]}</code></td>'
            f'<td>{esc(r["placement"])}</td><td>{k["label"]}</td><td class="num">{n(r["w"])} × {n(r["d"])}</td>'
            f'<td class="num">{n(r["w"]*r["d"])}</td>'
            f'<td>({n(r["cx"])}, {n(r["cy"])})</td>'
            f'<td>{n(r["x0"])} ~ {n(r["x1"])}</td><td>{n(r["y0"])} ~ {n(r["y1"])}</td></tr>')
    table = ("<table><thead><tr><th class='num'>#</th><th>中文名</th><th>运行时 key</th><th>定位</th><th>房型</th>"
             "<th class='num'>宽×深 (m)</th><th class='num'>面积 (m²)</th><th>中心 (x, y)</th>"
             "<th>占地 x 区间</th><th>占地 y 区间</th></tr></thead><tbody>" + "".join(rows) + "</tbody></table>")

    # 面积条
    tot = sum(r["w"] * r["d"] for r in ROOMS)
    wall = sum((r["w"] + r["d"]) * 2.0 * WALL_T for r in ROOMS)
    corridor = 0.0
    for a, b in LINKS:
        ra, rb = BY_KEY[a], BY_KEY[b]
        dx = abs(rb["cx"] - ra["cx"]); dy = abs(rb["cy"] - ra["cy"])
        clear = (max(0.0, dx - (ra["w"] + rb["w"]) / 2.0) if dx >= dy
                 else max(0.0, dy - (ra["d"] + rb["d"]) / 2.0))
        corridor += clear * CORRIDOR_W
    used = tot + wall + corridor
    avail = SITE_S * SITE_S - SITE_S * 4.0 * WALL_T
    mx = max(r["w"] * r["d"] for r in ROOMS)
    bars = []
    for r in sorted(ROOMS, key=lambda z: -z["w"] * z["d"]):
        cls = {"BOSS": "b-boss", "SAFE": "b-safe", "EXTRACT": "b-ext", "BRANCH": "b-branch"}.get(r["kind"], "")
        bars.append(f'<div class="bar-row"><span>{esc(r["name"])}</span>'
                    f'<div class="bar"><i class="{cls}" style="width:{r["w"]*r["d"]/mx*100:.1f}%"></i></div>'
                    f'<span class="bar-val">{n(r["w"]*r["d"])} m²</span></div>')
    bars_html = "".join(bars)

    # 主路流程条
    flow_items = []
    for idx, key in enumerate(MAIN_SEQUENCE):
        if idx:
            flow_items.append('<li class="sep">→</li>')
        flow_items.append(f'<li><b>{esc(BY_KEY[key]["name"])}</b></li>')
    flow_html = '<ol class="flow">' + "".join(flow_items) + '</ol>'

    # 支线表
    b_rows = []
    for r in ROOMS:
        if r["kind"] != "BRANCH":
            continue
        b_rows.append(f'<tr><td>{r["i"]}</td><td>{esc(r["name"])}</td><td><code>{r["key"]}</code></td>'
                      f'<td><code>{r["parent"]}</code></td><td class="num">{n(r["w"])} × {n(r["d"])}</td></tr>')
    branch_html = ("<table><thead><tr><th class='num'>#</th><th>支线房</th><th>key</th><th>挂在哪</th>"
                   "<th class='num'>尺寸 (m)</th></tr></thead><tbody>" + "".join(b_rows) + "</tbody></table>")

    # 详图卡片
    cards = []
    for r in ROOMS:
        extra = {
            "entry": "特殊房 · 沿用塔楼 v007 安全房壳体",
            "room_01": "主路房 1 · 房型 拐角走廊（房间种类美术已有 121 包）",
            "room_02": "主路房 2 · 房型 数据库房间01 · 支线岔口",
            "room_03": "主路房 3 · 房型 办公室 · 支线岔口 · 最大单间",
            "room_04": "主路房 4 · 房型 拐角走廊 · 支线岔口",
            "room_05": "主路房 5 · 房型 通道桥房间 · 支线岔口 · 唯一多层几何",
            "room_06": "主路房 6 · 房型 数据库房间02 · 主路最后一间内容房",
            "boss": "特殊房 · 白模 + 房间种类美术已有（214 包）",
            "extraction": "特殊房 · 无美术（信标为运行时）",
            "branch_01": "支线房 · 房型 数据库房间01（复用）· 挂主路第 2 房",
            "branch_02": "支线房 · 房型 标准房间 · 挂主路第 3 房",
            "branch_03": "支线房 · 房型 标准房间 · 挂主路第 4 房",
            "branch_04": "支线房 · 房型 通道桥房间 · 唯一多层几何 · 挂主路第 5 房",
        }.get(r["key"], "支线房")
        cards.append(room_card(r, detail_svg(r, dets[r["key"]], doors_for(r)), extra))
    cards_html = "<h2>各房型平面示意</h2><p class='lede'>每张图按同一比例（1 m = 6 px）绘制，可直接横向比较大小。虚线开口表示门位（门槽实际位置由工具计算，不手填）。</p>" + \
                 '<div class="grid2">' + "".join(cards) + "</div>"

    html = f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>远征关卡01 平面图集</title>
<style>{CSS}</style></head><body><div class="wrap">

<h1>远征关卡01 平面图集</h1>
<p class="lede">按《远征关卡01 设计》§3 房型库与 §4 坐标草案绘制的示意图。用于核对房型尺寸、布局、主路与支线连接 —— <b>它不是可施工的几何源</b>，几何真源是设计源 <code>floor_00.json</code>。</p>

<div class="meta">
<span><b>关卡</b> expedition_01 · 远征前哨站</span>
<span><b>场地</b> 250 × 250 m（中心 2.5, 2.5）</span>
<span><b>网格</b> 5 m · 层高 12 m</span>
<span><b>结构</b> 单层 · {len(ROOMS)} 房间 · 主路 {len(MAIN_SEQUENCE)} 房墙贴墙 + {len(BRANCH_KEYS)} 支线房</span>
<span><b>包络</b> {n(max(r["x1"] for r in ROOMS) - min(r["x0"] for r in ROOMS))} × {n(max(r["y1"] for r in ROOMS) - min(r["y0"] for r in ROOMS))} m</span>
<span><b>房间面积</b> {n(tot)} m²</span>
<span><b>估算占用</b> {n(used)} m²（单层可用区 {n(avail)} m² 的 {used / avail * 100:.1f}%）</span>
</div>

<h2>1. 总平面图</h2>
<p class="lede">主路：{' → '.join(BY_KEY[k]["name"] for k in MAIN_SEQUENCE)}。八段衔接<b>全部墙贴墙</b>（净距 0 = 共墙），不再插过渡走廊模块。{len(BRANCH_KEYS)} 间支线房<b>直接挂在主路中间 4 间内容房</b>上（每条支线只有一段、链不再加深）。画面向上为北（平面 +y = 世界 +z = 南）。</p>
<div class="card">{ov}<p class="cap">总平面图 · 含场地边界、25 m 网格、核心区参考框与图例。核心区（65×65 居中）本关 <code>enforce_core_exclusion=false</code>，不避让。蓝色实线 = 主路方向，灰色虚线 = 支线。</p></div>

<h2>2. 主路与支线</h2>
{flow_html}
<p class="lede" style="margin-top:14px">主路 {len(MAIN_SEQUENCE) - 1} 段衔接全部为 <b>墙贴墙（净距 0）</b>；每段走廊的过渡由共享墙上的门洞完成，不再有独立的走廊模块。门数：入口安全屋 <b>2</b>（前门 + 弃局门）；主路中间 4 间（示例版图里是 数据库房间01 / 办公室01 / 拐角走廊02 / 通道桥房间）各 <b>3</b>（进 + 出 + 1 条支线）；主路两端 2 间（示例版图里是 拐角走廊01 / 数据库房间02）各 <b>2</b>；Boss 竞技场 <b>2</b>；撤离屋 <b>1</b>；每间支线房 <b>1</b>。</p>
<h3 style="margin-top:18px">支线房（{len(BRANCH_KEYS)} 间，各挂主路中间 4 房之一）</h3>
{branch_html}

<h2>3. 房间明细</h2>
{table}
<p class="cap" style="margin-top:8px;color:var(--muted);font-size:12px">中心坐标与区间为世界平面坐标（米）。运行时 key 是代码硬依赖：入口房 id 必为 <code>start</code>、首领房靠 <code>role="boss"</code>（key 名不受限）、撤离房 key 必为 <code>extraction</code>；支线房 <code>role="branch"</code>，其余 key 名只被验收脚本按名断言。</p>

<h2>4. 面积构成</h2>
{bars_html}
<p class="cap" style="margin-top:10px;color:var(--muted);font-size:12px">房间面积 {n(tot)} m² ｜ 内墙估算 {n(wall)} m² ｜ 走廊估算 {n(corridor)} m²（墙贴墙 ⇒ 0）｜ 估算占用 <b>{n(used)} m²</b> ｜ 单层可用区 {n(avail)} m²（250² − 外墙）｜ 占用率 <b>{used / avail * 100:.1f}%</b>（门禁口径见设计页 §4.7）。</p>

{cards_html}

<h2>5. 绘制口径与待确认项</h2>
<div class="warn"><b>需要你确认或留意的地方：</b>
<ul style="margin:8px 0 0;padding-left:20px">
<li><b>本图画的是「示例版图」。</b>实跑时每间内容房的房型按种子从池子里抽取（设计页 §3.4），尺寸与整张版图随之改变；<b>不变的是</b>：主路 9 房的存在与顺序、支线 4 间各挂中间 4 房之一、8 个模板的尺寸。</li>
<li><b>Boss 房门位由生成算法定。</b>墙贴墙摆位会给 Boss 房两个贴合方向（进 / 出），美术源的门洞须与生成结果对齐；设计页 §3.3 / §6 记的旧门位（南进西出）以生成结果为准再裁决。</li>
<li><b>通道桥房间的坑尺寸有出入。</b>设计页 §3.3 写"坑约 6 × 6 格"（30 × 30 m），但 60 × 50 m 的房型四边留 15 m 通道后，中央只剩 <b>30 × 20 m</b>（6 × 4 格）。本图按几何自洽的 30 × 20 绘制，建议回头修设计页那句。</li>
<li><b>墙贴墙要靠 <code>edge_policy</code> 放行。</b>{len(LINKS)} 条父子边净距全为 0，校验器默认会报 <code>corridor_too_short</code>；落地时每条边都要写进 <code>floor_00.json</code> 的 <code>edge_policy.allow_zero_length</code>（见设计页 §4.1 / §7 第 6 条）。constrained 路径下生成器会按实算净距自动写这份白名单。</li>
<li><b>安全屋的两扇门方向要对一次。</b>设计源记的是 <code>entry_side = "east"</code> / <code>exit_side = "west"</code>，落设计源时先确认这两个字段在单层关卡里的实际语义。</li>
</ul></div>
<p class="cap" style="color:var(--muted);font-size:12px">图纸为<b>示意</b>：房间形态按参考图判读还原（L 形、凹字形、内凹轮廓、下沉坑与桥），门位只标"在哪面墙"，门槽的精确位置由工具按版图规范算；设施（工位、机柜、货架、叉车、工作站）为数量与分区的示意摆放，不是最终美术摆位。</p>

<div class="foot">
来源：<code>docs/v0.1/design/远征关卡01设计.md</code>（房型库 §3 / 坐标草案 §4）·
<code>source/art/whitebox/tower_zones/expedition_01/v001/data/level_plan.json</code> ·
<code>floor_00.json</code>。参考图见 <code>refs/expedition01/</code>。<br>
生成于 2026-09-24 · 示意图集（画的是<b>示例版图</b>；实跑版图由 <code>FloorPlanGenerator</code> 按种子现算）。
</div>

</div></body></html>"""
    return html


XML_HEAD = '<?xml version="1.0" encoding="UTF-8"?>\r\n'


def main():
    OUTDIR.mkdir(parents=True, exist_ok=True)
    PLANDIR.mkdir(parents=True, exist_ok=True)

    html = build_html()
    hp = OUTDIR / "远征关卡01平面图集.html"
    hp.write_text(html, encoding="utf-8", newline="\r\n")

    overview = build_overview()
    sp = OUTDIR / "总平面图.svg"
    sp.write_text(XML_HEAD + overview, encoding="utf-8", newline="\r\n")

    written = [hp, sp]

    # 设计页内联用：总平面 + 各房型详图，各自独立成文件（改文档 -> 重跑 -> 文档里的图跟着变）
    pv = PLANDIR / "00-总平面图.svg"
    pv.write_text(XML_HEAD + overview, encoding="utf-8", newline="\r\n")
    written.append(pv)

    dets = build_details()
    for r in ROOMS:
        p = PLANDIR / ("%02d-%s.svg" % (r["i"], r["name"]))
        p.write_text(XML_HEAD + detail_svg(r, dets[r["key"]], doors_for(r)), encoding="utf-8", newline="\r\n")
        written.append(p)

    # 清掉旧版残留（房型/顺序一改，文件名就会变），避免目录里混着过期图。
    keep = {p.name for p in written}
    stale = []
    for old in sorted(PLANDIR.glob("*.svg")):
        if old.name not in keep:
            stale.append(old)
    for old in sorted(PLANDIR.glob("*.svg.import")):
        if old.name[:-len(".import")] not in keep:
            stale.append(old)
    for old in stale:
        old.unlink()
        print("removed stale: %s" % old.relative_to(ROOT))

    for p in written:
        b = p.read_bytes()
        crlf = b.count(b"\r\n")
        lf = b.count(b"\n") - crlf
        print("written: %-56s %7.1f KB  CRLF=%d LF-only=%d"
              % (p.relative_to(ROOT), len(b) / 1024, crlf, lf))

    # 自检
    tot = sum(r["w"] * r["d"] for r in ROOMS)
    wall = sum((r["w"] + r["d"]) * 2.0 * WALL_T for r in ROOMS)
    used = tot + wall
    avail = SITE_S * SITE_S - SITE_S * 4.0 * WALL_T
    print("rooms=%d main=%d branch=%d total=%g m2 used=%g avail=%g ratio=%.3f"
          % (len(ROOMS), len(MAIN_SEQUENCE), len(BRANCH_KEYS), tot, used, avail, used / avail))
    xs = [r["x0"] for r in ROOMS] + [r["x1"] for r in ROOMS]
    ys = [r["y0"] for r in ROOMS] + [r["y1"] for r in ROOMS]
    print("envelope x=[%g,%g] y=[%g,%g]  (%g x %g m)  site x=[%g,%g] y=[%g,%g]"
          % (min(xs), max(xs), min(ys), max(ys), max(xs) - min(xs), max(ys) - min(ys),
             SITE_X0, SITE_X1, SITE_Y0, SITE_Y1))
    print("margin: E=%.1f W=%.1f N=%.1f S=%.1f"
          % (SITE_X1 - max(xs), min(xs) - SITE_X0, min(ys) - SITE_Y0, SITE_Y1 - max(ys)))


main()
