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


def text(x, y, s, size=12, anchor="middle", fill="#0f172a", weight="400", base="middle",
         outline=False):
    """outline=True 时给文字加白色描边 —— 窄房的名字会溢出到相邻房间上，靠描边保证可读。"""
    extra = ' paint-order="stroke" stroke="#ffffff" stroke-width="3" stroke-linejoin="round"' if outline else ""
    return (f'<text x="{n(x)}" y="{n(y)}" font-size="{n(size)}" font-weight="{weight}" '
            f'text-anchor="{anchor}" dominant-baseline="{base}" fill="{fill}"{extra}>{esc(s)}</text>')


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
# 多层房型的「下沉区」专用色：**比上层平台明显更深**（深 = 低）。
# 别用 #dbeafe 这类跟 COMMON 平台色（#E6F1FB）只差一点点的蓝 —— 屏幕上分不出哪块是能走的、哪块是掉的。
SUNKEN = dict(fill="#BFD6F2", stroke="#2A6BB5", ink="#14417A")
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

# 业主 2026-09-25 裁定：**支线整体取消** —— 本关不再有 branch_01..04，图纸只画主路 9 房。
# 设计页的支线设计已作废（§2 顶部裁定 / §3.3 / §5.1），主路目标口径加深到 13 房
# （10 间内容房），新房型分配与坐标待实际制作时重排。
# 这个开关现在已无支线可过滤（设计页 §3.1 总表里不再有「定位 = 支线」的行），
# 保留是为了其它关卡 / 将来复用；总平面图、详图、明细表、面积条都会一起过滤 BRANCH。
SHOW_BRANCH_ROOMS = False

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
        r["parent"] = parents.get(r["key"])
        if r["key"] not in centres:
            # 支线房不需要坐标（设计页 §4.2 的支线行已移除）；保留该分支是为将来
            # 其它关卡 / 复用场景 —— 支线不绘制时不给它算区域。
            if r["kind"] == "BRANCH" and not SHOW_BRANCH_ROOMS:
                r["cx"] = r["cy"] = r["x0"] = r["x1"] = r["y0"] = r["y1"] = None
                continue
            raise SystemExit("§4.2 坐标草案里找不到房间「%s」的中心坐标" % r["key"])
        r["cx"], r["cy"] = centres[r["key"]]
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

# 绘制集合：默认剔掉支线房（见 SHOW_BRANCH_ROOMS 的说明；本关已无支线行 ⇒ 恒等于全集）。
# 序号 r["i"] 按 §3.1 总表原始序（本关 1..9 即主路）。
DRAWN_ROOMS = [r for r in ROOMS if SHOW_BRANCH_ROOMS or r["kind"] != "BRANCH"]
DRAWN_KEYS = {r["key"] for r in DRAWN_ROOMS}
BY_KEY = {r["key"]: r for r in ROOMS}

# 父子连接（A -> B；方向由坐标决定）—— 只收绘制集合内的边
LINKS = [(r["parent"], r["key"]) for r in DRAWN_ROOMS if r["parent"]]

# 主路顺序：入口 → 主路内容房 → 首领 → 撤离
ENTRY_KEY = next((r["key"] for r in ROOMS if r["room_type"] == "SAFE_ROOM"), "start")
BOSS_KEY = next((r["key"] for r in ROOMS if r["room_type"] == "BOSS_ROOM"), "boss")
EXIT_KEY = next((r["key"] for r in ROOMS if r["room_type"] == "EXTRACTION_ROOM"), "extraction")
MAIN_SEQUENCE = ([ENTRY_KEY]
                 + [r["key"] for r in ROOMS if r["placement"] == "主路"]
                 + [BOSS_KEY, EXIT_KEY])
BRANCH_KEYS = [r["key"] for r in DRAWN_ROOMS if r["kind"] == "BRANCH"]

# 子房索引（只收绘制集合内的，图纸不给未绘制的房间留门位）
CHILDREN = {}
for _r in DRAWN_ROOMS:
    if _r["parent"]:
        CHILDREN.setdefault(_r["parent"], []).append(_r["key"])

# ---------------------------------------------------------------- 非矩形轮廓
#
# 局部坐标（原点 = 房间西北角，+x 向东、+y 向南），顶点一律落 5 m 网格。
# 总平面图与详图**共用这套顶点**，避免两处各写一份对不上。
# ⚠️ 2026-09-25：`room_02` / `room_05` / `room_06` 的尺寸按业主指示改画，
# 与 `room_templates/*.json` 的 `variant_footprints` **暂不一致**（本轮只动图纸）；
# 落实跑口径时两处要一起改（门禁 `check_expedition_room_footprints.py` 校 JSON）。
OUTLINES = {
    # 拐角走廊 L 形：横臂 45×15 + 竖臂 15×25
    "room_01": [(0, 0), (45, 0), (45, 15), (15, 15), (15, 40), (0, 40)],
    # 拐角走廊 凹字形折返：上下横臂 45×15 + 右侧竖 15×10
    "room_04": [(0, 0), (45, 0), (45, 40), (0, 40), (0, 25), (30, 25), (30, 15), (0, 15)],
    # 数据库房间01 40×30：主体 40×25 + 南侧中段外凸 10×5
    "room_02": [(0, 0), (40, 0), (40, 25), (25, 25), (25, 30), (15, 30), (15, 25), (0, 25)],
    # 数据库房间02 50×30：主体 50×25 + 南中段外凸 20×5；左下缺 15×10、右下缺 15×5
    "room_06": [(0, 0), (50, 0), (50, 25), (35, 25), (35, 30), (15, 30), (15, 20), (0, 20)],
    # 通道桥房间 30×60 工字型：南北两端 30×15 上层平台 + 中间 10 m 宽跨桥（x 10~20）
    "room_05": [(0, 0), (30, 0), (30, 15), (20, 15), (20, 45),
                (30, 45), (30, 60), (0, 60), (0, 45), (10, 45), (10, 15), (0, 15)],
}


def poly_area(pts):
    """鞋带公式算多边形面积（绝对值为正；顶点须按序给出）。"""
    s = 0.0
    for i in range(len(pts)):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % len(pts)]
        s += x1 * y2 - x2 * y1
    return abs(s) / 2.0


for _r in DRAWN_ROOMS:
    _pts = OUTLINES.get(_r["key"])
    _r["outline"] = _pts
    _r["area_outline"] = poly_area(_pts) if _pts else _r["w"] * _r["d"]

# 轮廓房的标签锚点（局部坐标）—— 不能用包围盒中心：L 形 / 凹字形 / 工字形的包围盒
# 中心往往落在**缺口或窄腰**上，文字会溢出到房间外。这里给每间轮廓房挑一块**实心且够宽**
# 的区域放文字（room_01 取横臂、room_04 取上横臂、room_05 取北端平台、room_06 取满宽带）。
OUTLINE_LABEL = {
    "room_01": (22.5, 7.5),
    "room_04": (22.5, 7.5),
    "room_02": (20.0, 12.5),
    "room_06": (25.0, 10.0),
    "room_05": (15.0, 7.5),
}


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
#
# 画幅按「实际房间包络 ∪ 场地参考框」自动适配，**不再钉死 250×250**：
# 场地外边界自 2026-09-25 起退出判据（05.2 §3.7），房间可以整块探出场地框，
# 若仍按场地定比例就会把探出的房间裁掉（曾发生：包络 190×320 被裁到只剩中段）。
PAD = 40.0
# 图例盒固定占左下角；顶部另留标题带（房间可能顶到最北边，标题不能与它同高）。
TOP_BAND = 56.0
LEGEND_W, LEGEND_H = 250.0, 140.0
# 画幅装进「房间包络 ∪ 场地参考框」：场地框已不是判据（05.2 §3.7），但仍作坐标
# 参照画出来 —— 装进来才不会出现「只露一个角」的半截框（那反而像画错了）。
# 画幅取竖长方形，贴合本关「主路沿 y 铺开」的长链形状。
OVERVIEW_MARGIN = 0.0


def _overview_bounds():
    """返回需要装进画幅的矩形 (x0, y0, x1, y1)：房间包络 ∪ 场地参考框。"""
    x0 = min(SITE_X0, min(r["x0"] for r in DRAWN_ROOMS)) - OVERVIEW_MARGIN
    y0 = min(SITE_Y0, min(r["y0"] for r in DRAWN_ROOMS)) - OVERVIEW_MARGIN
    x1 = max(SITE_X1, max(r["x1"] for r in DRAWN_ROOMS)) + OVERVIEW_MARGIN
    y1 = max(SITE_Y1, max(r["y1"] for r in DRAWN_ROOMS)) + OVERVIEW_MARGIN
    return x0, y0, x1, y1


BX0, BY0, BX1, BY1 = _overview_bounds()
# 画幅的可用像素区（左右各 PAD，顶部让出标题带，底部让出图例盒）。
# 画幅取「竖长方形」—— 本关主路是一条沿 y 铺开的长链，竖向多给的像素能直接换成
# 更大的房间和更清楚的字（方画幅下高度是唯一瓶颈，横向留白白白浪费）。
_FIT_W = 620.0
_FIT_H = 700.0
S = min(_FIT_W / max(BX1 - BX0, 1e-6), _FIT_H / max(BY1 - BY0, 1e-6))
VW = (BX1 - BX0) * S + PAD * 2
VH = (BY1 - BY0) * S + PAD * 2 + TOP_BAND + LEGEND_H + 10.0


def gx(x):
    return PAD + S * (x - BX0)


def gy(y):
    return PAD + TOP_BAND + S * (y - BY0)


def build_overview(with_grid=True):
    o = [f'<svg viewBox="0 0 {n(VW)} {n(VH)}" width="100%" xmlns="http://www.w3.org/2000/svg" '
         f'role="img" font-family="system-ui, -apple-system, Segoe UI, PingFang SC, Microsoft YaHei, sans-serif">',
         '<title>远征关卡01 总平面图</title>',
         f'<desc>主路 {len(MAIN_SEQUENCE)} 房墙贴墙的平面示意（支线已取消、无支线房），含场地参考框、25 米网格、房间真实轮廓与主路行进方向箭头。</desc>',
         ARROW_DEFS]

    # 场地（细实线框，只作坐标参照，不作判据）
    o.append(rect(gx(SITE_X0), gy(SITE_Y0), S * SITE_S, S * SITE_S, "#fbfcfe", "#94a3b8", 0.6, 3))
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
    # 核心区（65x65 居中 2.5,2.5），仅参考。文字放到框**右侧**（该处为空）——
    # 本关核心框内压着 room_04，框内或框上都会与房间文字打架。
    cx0, cy0 = 2.5 - 32.5, 2.5 - 32.5
    o.append(rect(gx(cx0), gy(cy0), S * 65, S * 65, "none", "#c7b9e8", 0.6, 0, "5 3"))
    o.append(text(gx(cx0 + 65) + 6, gy(cy0 + 32.5) - 3, "核心区 65×65", 10, "start", "#7F77DD", "500"))
    o.append(text(gx(cx0 + 65) + 6, gy(cy0 + 32.5) + 10, "（本关不避让）", 9, "start", "#9a8fd0"))

    # 非主路连接（先画，压在房间下）：父房中心 -> 子房中心 的灰色虚线
    # 本关支线已取消 ⇒ 本循环无命中（主路自己走蓝色实线）
    for a, b in LINKS:
        ra, rb = BY_KEY[a], BY_KEY[b]
        if a == ENTRY_KEY or b in MAIN_SEQUENCE:
            continue                                   # 主路自己走蓝色实线
        o.append(line(gx(ra["cx"]), gy(ra["cy"]), gx(rb["cx"]), gy(rb["cy"]),
                      CONNECT, 1.0, "5 4"))

    # 主路行进方向：**不画穿房长线**（墙贴墙时房间之间没有缝隙，线要么被盖住、
    # 要么压在房间名上）。改为在**每对相邻房的接缝处**画一个横向箭头 ——
    # 箭头位置正是门上沿，一眼能看出「从这面墙穿过去」，也不与房内文字打架。
    for i in range(len(MAIN_SEQUENCE) - 1):
        ra, rb = BY_KEY[MAIN_SEQUENCE[i]], BY_KEY[MAIN_SEQUENCE[i + 1]]
        mx_px = (gx(ra["cx"]) + gx(rb["cx"])) / 2.0
        my_px = (gy(ra["cy"]) + gy(rb["cy"])) / 2.0
        dx_px, dy_px = gx(rb["cx"]) - gx(ra["cx"]), gy(rb["cy"]) - gy(ra["cy"])
        ln = math.hypot(dx_px, dy_px)
        if ln < 1e-6:
            continue
        ux, uy = dx_px / ln, dy_px / ln
        o.append(line(mx_px - ux * 9, my_px - uy * 9, mx_px + ux * 9, my_px + uy * 9,
                      ROUTE, 2.4, None, "ar"))

    # 房间（矩形或真实轮廓 + 文字 + 序号角标）
    for r in DRAWN_ROOMS:
        k = KIND[r["kind"]]
        if r["outline"]:
            o.append(poly([(gx(r["x0"] + vx), gy(r["y0"] + vy)) for vx, vy in r["outline"]],
                          k["fill"], k["stroke"], 1.2))
        else:
            o.append(rect(gx(r["x0"]), gy(r["y0"]), S * r["w"], S * r["d"], k["fill"], k["stroke"], 1.2, 2))
        px_w = S * r["w"]
        px_h = S * r["d"]
        if r["key"] in OUTLINE_LABEL:
            lx_v, ly_v = OUTLINE_LABEL[r["key"]]
            cx, cy = gx(r["x0"] + lx_v), gy(r["y0"] + ly_v)
        else:
            cx, cy = gx(r["cx"]), gy(r["cy"])
        # 三行文字（名字 / 尺寸 / key·面积）。窄房只给两行，避免第三行溢到房间外。
        o.append(text(cx, cy - 8, r["name"], 11.5, "middle", k["ink"], "500", "middle", True))
        o.append(text(cx, cy + 6, f'{n(r["w"])} × {n(r["d"])} m', 9.5, "middle", k["ink"], "400", "middle", True))
        if px_w >= 105:
            _a = (f'轮廓 {n(r["area_outline"])} m²' if r["outline"] else f'{n(r["w"] * r["d"])} m²')
            o.append(text(cx, cy + 19, f'{r["key"]} · {_a}', 8.5, "middle", k["ink"], "400", "middle", True))
        # 序号角标（窄房放到框外；无论内外都不许越进顶部标题带）
        floor_y = PAD + TOP_BAND + 8
        if px_w >= 75:
            bx, by = gx(r["x0"]) + 9, gy(r["y0"]) + 9
        else:
            bx, by = gx(r["x0"]) - 9, gy(r["y0"]) - 9
        by = max(by, floor_y)
        o.append(circle(bx, by, 8, "#ffffff", k["stroke"], 0.8))
        o.append(text(bx, by + 0.5, str(r["i"]), 9.5, "middle", k["ink"], "500"))

    # 标题（画幅顶部标题带 —— 与房间区物理隔开）
    o.append(text(PAD, PAD + 12, "远征关卡01 · 总平面图（示意）", 12, "start", INK, "500"))
    o.append(text(PAD, PAD + 29,
                  f'示例版图 ｜ 5 m 网格 ｜ 主路 {len(MAIN_SEQUENCE)} 房墙贴墙'
                  + (f' + {len(BRANCH_KEYS)} 支线房' if BRANCH_KEYS else '（无支线）'),
                  10, "start", MUTED))

    # 指北针（画幅右上角标题带内）
    nx, ny = VW - PAD - 14, PAD + 20
    o.append(line(nx, ny + 14, nx, ny - 8, INK, 1.2, None, "ar"))
    o.append(text(nx, ny + 24, "北", 10, "middle", INK, "500"))

    # 图例（画幅左下角，与房间区之间已预留 LEGEND_H 高度）
    lx, ly = PAD + 4, VH - LEGEND_H - 6
    o.append(rect(lx, ly, LEGEND_W, LEGEND_H, "#ffffff", "#cbd5e1", 0.5, 6, None, 0.9))
    o.append(text(lx + 8, ly + 14, "图例", 10.5, "start", INK, "500"))
    # 只列**本图画到的**房类：支线已取消 ⇒ 图例里不该出现支线色块（KIND["BRANCH"] 仅备用）。
    order = [k for k in ["SAFE", "COMMON", "BRANCH", "BOSS", "EXTRACT"]
             if k != "BRANCH" or BRANCH_KEYS]
    for i, kk in enumerate(order):
        k = KIND[kk]
        px = lx + 8 + (i % 2) * 120
        py = ly + 30 + (i // 2) * 18
        o.append(rect(px, py - 5, 11, 10, k["fill"], k["stroke"], 0.8, 2))
        o.append(text(px + 16, py, k["label"], 9.5, "start", DIM))
    o.append(line(lx + 8, ly + 84, lx + 30, ly + 84, ROUTE, 2.4, None, "ar"))
    o.append(text(lx + 34, ly + 84, "主路行进方向（①→⑨ 穿墙）", 9.5, "start", DIM))
    # 场地参考框（浅色细框，只作坐标参考，不作判据）
    o.append(rect(lx + 8, ly + 97, 22, 11, "#fbfcfe", "#94a3b8", 0.6, 1))
    o.append(text(lx + 34, ly + 103, "场地参考框 250×250（不作判据）", 9.5, "start", DIM))
    o.append(line(lx + 8, ly + 118, lx + 30, ly + 118, "#c7b9e8", 0.9, "5 3"))
    o.append(text(lx + 34, ly + 118, "核心区 65×65（本关不避让）", 9.5, "start", DIM))

    o.append("</svg>")
    return "".join(o)


# ---------------------------------------------------------------- 详图

DS = 6.0          # 详图比例 px/m（各图统一，可直接比大小）
DPAD = 34.0       # 四周留白（底部要放一行说明文字，太窄会贴边）


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
    ch = r["d"] * DS + DPAD * 2
    k = KIND[r["kind"]]

    # 先空跑一次 inner：只为拿到它登记在图外的说明行文本，好把画幅加宽到装得下最宽那一行。
    # 窄房（如 30 m 宽的桥房）按房宽定的画幅装不下「尺寸 · 形态」那一行，会被裁字。
    del _FOOT[:]
    inner(lambda vx: DPAD + vx * DS, lambda vy: DPAD + vy * DS)
    cw = max(r["w"] * DS + DPAD * 2, max([_text_px(s) for s in _FOOT] or [0.0]) + 18.0)
    x0 = (cw - r["w"] * DS) / 2.0          # 画幅加宽后房体仍居中

    def X(vx):
        return x0 + vx * DS

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


_FOOT = []         # 当前详图登记在图外（房体下方）的说明行，供 detail_svg 定画幅宽度


def _text_px(s, size=9.0):
    """粗估一串文字在 SVG 里的像素宽（全角按 size、其余按 0.56 × size）。"""
    w = 0.0
    for ch in s or "":
        w += size * (1.0 if ord(ch) > 0x2000 else 0.56)
    return w


def foot_label(X, Y, r, s, size=9, fill=MUTED):
    """房体**下方外侧**的统一说明行（尺寸 + 形态）。放框内会压住轮廓边线与设施。"""
    _FOOT.append(s)
    return label(X, Y, r["w"] / 2.0, r["d"] + 4.6, s, size, fill)


def foot_note(X, Y, r, s, size=8.5, dy=1.6, fill=MUTED):
    """说明行之上再加一行（房体下方外侧）。同样登记进 _FOOT，画幅才会为它让出宽度。"""
    _FOOT.append(s)
    return label(X, Y, r["w"] / 2.0, r["d"] + 4.6 - dy, s, size, fill)


def build_details():
    """返回 key -> inner(X, Y) 绘制函数（只画房体与内部设施；门由 detail_svg 统一画）。

    ⚠️ **详图配色按「房型类别」定，不按「主路 / 支线」定。**
    支线曾是**一条边的属性**、不是房型的属性 —— `content_template_pool` 里那 5 个内容房型
    （`corridor_45x40` / `db_70x50` / `office_60x70` / `bridge_60x50` / `std_25x25`）
    既可能落在主路上、也可能被抽去当支线房，同一个详图因此必须只有一种颜色。
    所以这里**一律不出现 `KIND["BRANCH"]`**（该色块只保留在配色表里备用）。
    注：支线已于 2026-09-25 取消，本关已无支线房；这条规则对将来复用该脚本的关卡仍成立。
    """
    out = {}

    # ---- 安全屋 15x15
    def safe(X, Y):
        k = KIND["SAFE"]
        g = [rect(X(0), Y(0), 15 * DS, 15 * DS, k["fill"], k["stroke"], 1.2, 2)]
        g.append(circle(X(7.5), Y(8.6), 4.4, "#ffffff", k["stroke"], 0.8))
        g.append(label(X, Y, 7.5, 8.6, "抵达", 8, k["ink"]))
        g.append(line(X(2.2), Y(15), X(9.2), Y(15), "#ffffff", 3.6))     # 弃局门（南墙，示意）
        g.append(line(X(2.2), Y(15), X(9.2), Y(15), DIM, 0.9, "3 2"))
        g.append(label(X, Y, 5.7, 13.4, "弃局门", 8.5, k["ink"]))
        g.append(foot_label(X, Y, dict(w=15, d=15), "15 × 15 m · 双门互垂"))
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
        g.append(label(X, Y, 7.5, 29, "竖臂 15 × 25", 9, k["ink"]))
        g.append(label(X, Y, 22.5, 7.5, "横臂 45 × 15 · 净宽 15 m", 9, k["ink"]))
        g.append(foot_label(X, Y, dict(w=45, d=40), "45 × 40 m · 单拐角 L 形"))
        return g
    out["room_01"] = c1

    # ---- 拐角走廊02 45x40（凹字形折返）
    def c2(X, Y):
        k = KIND["COMMON"]
        # 与 room_templates/corridor_45x40.json 的 variant_footprints.u_turn **逐值一致**
        # （外轮廓 = 上横臂 45×15 + 右竖 15×10 + 下横臂 45×15 的并集；西侧中部 30×10 是实体）。
        walk = [(0, 0), (45, 0), (45, 40), (0, 40), (0, 25), (30, 25), (30, 15), (0, 15)]
        g = [poly([(X(a), Y(b)) for a, b in walk], k["fill"], k["stroke"], 1.2)]
        g.append(rect(X(0), Y(15), 30 * DS, 10 * DS, "#f1f5f9", k["stroke"], 1.0))
        g.append(label(X, Y, 15, 20, "内墙岛 30 × 10", 9, DIM))
        g.append(label(X, Y, 22.5, 7.5, "上横臂 45 × 15", 9, k["ink"]))
        g.append(label(X, Y, 37.5, 20, "竖 15×10", 8.5, k["ink"]))
        g.append(label(X, Y, 22.5, 33, "下横臂 45 × 15", 9, k["ink"]))
        g.append(foot_label(X, Y, dict(w=45, d=40), "45 × 40 m · 凹字形折返"))
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
        g.append(label(X, Y, 25, 19.5, "机柜成组", 10, k["ink"]))
        g.append(foot_label(X, Y, dict(w=50, d=40), "50 × 40 m · 四墙房间（终局战斗）"))
        return g
    out["boss"] = boss

    # ---- 撤离屋 25x25
    def ext(X, Y):
        k = KIND["EXTRACT"]
        g = [rect(X(0), Y(0), 25 * DS, 25 * DS, k["fill"], k["stroke"], 1.2, 2)]
        g.append(circle(X(12.5), Y(12.5), 6, "#ffffff", k["stroke"], 1.0))
        g.append(circle(X(12.5), Y(12.5), 2.4, "#EF9F27", k["stroke"], 0.8))
        g.append(label(X, Y, 12.5, 19.8, "撤离信标", 9, k["ink"]))
        g.append(foot_label(X, Y, dict(w=25, d=25), "25 × 25 m · 空房 · 不刷怪"))
        return g
    out["extraction"] = ext

    # ---- 数据库房间01 40×30（不规则：主体 40×25 + 南侧中段外凸 10×5，**无缺角**）
    # ⚠️ 2026-09-25 按业主指示改画（原 db_01 的包围盒是 70×50）——轮廓顶点全部落 5 m 网格。
    # ⚠️ db_01 **不是缺角形态**：原模板是「主体 70×40 + 南中段外凸 20×10（x∈[25,45] 居中）」，
    #    四个角都是直角；别照着 db_02（缺角）去写它的说明。room_templates/db_70x50.json 的
    #    variant_footprints **尚未同步本尺寸**（本轮只动图纸），落实跑口径时要一起改。
    def db1(X, Y):
        k = KIND["COMMON"]
        walk = [(0, 0), (40, 0), (40, 25), (25, 25), (25, 30), (15, 30), (15, 25), (0, 25)]
        g = [poly([(X(a), Y(b)) for a, b in walk], k["fill"], k["stroke"], 1.2)]
        for i in range(5):                       # 西墙机柜列
            g.append(rect(X(3), Y(4 + i * 4.4), 3.4, 3.4, "#cbdcf0", k["stroke"], 0.6, 1))
        for i in range(6):                       # 北墙机柜列
            g.append(rect(X(10 + i * 4.4), Y(3), 3.4, 3.4, "#cbdcf0", k["stroke"], 0.6, 1))
        g.append(rect(X(28), Y(9), 10 * DS, 8 * DS, "#ffffff", k["stroke"], 0.7, 2, "4 3"))
        g.append(label(X, Y, 33, 13, "检修工位", 8.5, k["ink"]))
        g.append(label(X, Y, 12.5, 7, "机柜列", 8.5, k["ink"]))
        g.append(foot_label(X, Y, dict(w=40, d=30), "40 × 30 m · 不规则（南中段外凸 10 × 5）"))
        return g
    out["room_02"] = db1

    # ---- 办公室01 30x40（方厅，无内墙）
    def off(X, Y):
        k = KIND["COMMON"]
        g = [rect(X(0), Y(0), 30 * DS, 40 * DS, k["fill"], k["stroke"], 1.2, 2)]
        spots = [(8.5, 11), (21.5, 11), (8.5, 25), (21.5, 25)]
        for tx, ty in spots:
            g.append(rect(X(tx - 3.2), Y(ty - 1.8), 6.4 * DS, 2.2 * DS, "#ffffff", k["stroke"], 0.7, 1))
            g.append(circle(X(tx), Y(ty + 2), 2.4, "#ffffff", k["stroke"], 0.7))
        for i in range(4):                       # 西墙文件柜
            g.append(rect(X(1), Y(4 + i * 2.2), 1.8 * DS, 5 * DS * 0.5, "#dbe9f8", k["stroke"], 0.6, 1))
        g.append(label(X, Y, 15, 6, "工位 4 组", 8.5, DIM))
        g.append(foot_label(X, Y, dict(w=30, d=40), "30 × 40 m · 无内墙（开放办公）"))
        return g
    out["room_03"] = off

    # ---- 数据库房间02 50x30（不规则：左下缺 15×10 + 右下缺 15×5，南中段外凸 20×5）
    # ⚠️ 2026-09-25 按业主指示改画（原 db_02 是 70×50），同上：轮廓是等比缩小版、
    # 顶点落 5 m 网格，模板 JSON 尚未同步。
    def db2(X, Y):
        k = KIND["COMMON"]
        walk = [(0, 0), (50, 0), (50, 25), (35, 25), (35, 30), (15, 30), (15, 20), (0, 20)]
        g = [poly([(X(a), Y(b)) for a, b in walk], k["fill"], k["stroke"], 1.2)]
        for row in range(3):
            for col in range(5):
                g.append(rect(X(6 + col * 8.6), Y(4 + row * 6.2), 5.4, 3.2, "#cbdcf0", k["stroke"], 0.6, 1))
        g.append(rect(X(1.2), Y(9), 3.6, 6, "#FAC775", "#BA7517", 0.8, 1))
        g.append(label(X, Y, 3, 17, "叉车", 8, "#633806"))
        g.append(label(X, Y, 25, 11, "货架 · 箱体堆场", 9.5, k["ink"], "middle", "500"))
        g.append(foot_label(X, Y, dict(w=50, d=30),
                            "50 × 30 m · 不规则（左缺 15×10 · 右缺 15×5 · 南中段外凸 20×5）"))
        return g
    out["room_06"] = db2

    # ---- 通道桥房间 30x60 工字型（南北两端上层平台 + 中央跨桥，桥两侧为下层）
    # ⚠️ 2026-09-25 按业主指示改画：上层平台俯视呈「工」字 ——
    #   北端 30×15 平台（y 0~15）＋ 中间 10 m 宽跨桥（x 10~20，y 15~45）＋ 南端 30×15 平台（y 45~60）；
    #   桥东西两侧各 10×30（x 0~10 / 20~30，y 15~45）是**下层**（下沉，画成蓝色）。
    #   整块轮廓面积 = 30×15 + 10×30 + 30×15 = 1200 m²（占位包围盒 30×60 = 1800 m²）。
    #   门只开在南北两块短板（桥跨向两端，进出同轴）⇒ 没有第三个门位。
    # 原 bridge_60x50 的 60×50 本体与 50×60 转置姿态都不再用；模板 JSON 尚未同步本形态。
    def bridge(X, Y):
        k = KIND["COMMON"]
        g = []
        for _lx in (0, 20):                      # 下层（先铺底）
            g.append(rect(X(_lx), Y(15), 10 * DS, 30 * DS, SUNKEN["fill"], SUNKEN["stroke"], 1.1))
            # 斜线填充：图纸惯例的「下沉 / 非通行面」记号，让它一眼区别于上层平台
            for _i in range(9):
                _yy = 16.5 + _i * 3.4
                g.append(line(X(_lx + 0.6), Y(_yy), X(_lx + 9.4), Y(_yy + 2.6),
                              "#8fb6e0", 0.6))
            for _i in range(2):                  # 下层设备示意
                g.append(rect(X(_lx + 3.4), Y(21 + _i * 8.0), 3.2, 3.0,
                              "#e2e8f0", "#94a3b8", 0.6, 1))
        # 上层平台（工字外轮廓）
        walk = [(0, 0), (30, 0), (30, 15), (20, 15), (20, 45),
                (30, 45), (30, 60), (0, 60), (0, 45), (10, 45), (10, 15), (0, 15)]
        g.append(poly([(X(a), Y(b)) for a, b in walk], k["fill"], k["stroke"], 1.3))
        for _i in range(5):                      # 桥面纹理
            g.append(line(X(10.8), Y(19 + _i * 5.5), X(19.2), Y(19 + _i * 5.5), "#94a3b8", 0.5, "3 2"))
        g.append(label(X, Y, 15, 6.4, "上层平台 · 通道", 9, k["ink"]))
        g.append(label(X, Y, 15, 11.4, "30 × 15", 8.5, k["ink"]))
        g.append(label(X, Y, 15, 26.5, "跨桥（上层）", 8.5, k["ink"]))
        g.append(label(X, Y, 15, 31.5, "10 m 宽", 8.5, k["ink"]))
        g.append(label(X, Y, 15, 36.5, "沿 y 跨", 8, k["ink"]))
        for _lx, _cx in ((0, 5), (20, 25)):
            g.append(label(X, Y, _cx, 24.0, "下 层", 8.5, SUNKEN["ink"], "middle", "500"))
            g.append(label(X, Y, _cx, 29.0, "（下沉）", 8, SUNKEN["ink"]))
            g.append(label(X, Y, _cx, 34.0, "10 × 30", 8, SUNKEN["ink"]))
        g.append(label(X, Y, 15, 49, "上层平台 · 通道", 9, k["ink"]))
        g.append(label(X, Y, 15, 54, "30 × 15", 8.5, k["ink"]))
        # 两层读法：进门在水平方向上是同一位置，差别只在高度 ⇒ 单独给一行图注
        g.append(foot_note(X, Y, dict(w=30, d=60),
                           "浅色 = 上层可通行　深色斜纹 = 下层（下沉，掉落区）"))
        g.append(foot_label(X, Y, dict(w=30, d=60),
                            "30 × 60 m · 工字型上层平台 · 门只开短板（北 / 南墙）· 唯一多层房型"))
        return g

    # room_05 是本关唯一的桥房实例。
    out["room_05"] = bridge

    # 注：`std_25x25`（标准房间）曾是支线房的专用详图（已随支线取消移除）；
    #     它仍是 §3.4 房型池的候选，若将来主路抽到它，需要在这里补回一份绘制函数。

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
    for r in DRAWN_ROOMS:
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
    tot = sum(r["w"] * r["d"] for r in DRAWN_ROOMS)
    wall = sum((r["w"] + r["d"]) * 2.0 * WALL_T for r in DRAWN_ROOMS)
    corridor = 0.0
    for a, b in LINKS:
        ra, rb = BY_KEY[a], BY_KEY[b]
        dx = abs(rb["cx"] - ra["cx"]); dy = abs(rb["cy"] - ra["cy"])
        clear = (max(0.0, dx - (ra["w"] + rb["w"]) / 2.0) if dx >= dy
                 else max(0.0, dy - (ra["d"] + rb["d"]) / 2.0))
        corridor += clear * CORRIDOR_W
    used = tot + wall + corridor
    avail = SITE_S * SITE_S - SITE_S * 4.0 * WALL_T
    mx = max(r["w"] * r["d"] for r in DRAWN_ROOMS)
    bars = []
    for r in sorted(DRAWN_ROOMS, key=lambda z: -z["w"] * z["d"]):
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

    # 详图卡片
    cards = []
    for r in DRAWN_ROOMS:
        extra = {
            "entry": "特殊房 · 沿用塔楼 v007 安全房壳体",
            "room_01": "主路房 1 · 房型 拐角走廊 L 形（房间种类美术已有 121 包）",
            "room_02": "主路房 2 · 房型 数据库房间01（40 × 30 改版，南中段外凸 10 × 5）",
            "room_03": "主路房 3 · 房型 办公室（30 × 40 改版，无内墙）",
            "room_04": "主路房 4 · 房型 拐角走廊 凹字折返",
            "room_05": "主路房 5 · 房型 通道桥房间（30 × 60 工字型，本版改画）· 两扇门是桥的两端 · 唯一多层几何",
            "room_06": "主路房 6 · 房型 数据库房间02（50 × 30 缺角改版）· 示例版图最后一间内容房",
            "boss": "特殊房 · 白模 + 房间种类美术已有（214 包）",
            "extraction": "特殊房 · 无美术（信标为运行时）",
        }.get(r["key"], "主路内容房")
        cards.append(room_card(r, detail_svg(r, dets[r["key"]], doors_for(r)), extra))
    cards_html = "<h2>各房型平面示意</h2><p class='lede'>每张图按同一比例（1 m = 6 px）绘制，可直接横向比较大小。虚线开口表示门位（门槽实际位置由工具计算，不手填）。</p>" + \
                 '<div class="grid2">' + "".join(cards) + "</div>"

    html = f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>远征关卡01 平面图集</title>
<style>{CSS}</style></head><body><div class="wrap">

<h1>远征关卡01 平面图集</h1>
<p class="lede">按《远征关卡01 设计》§3 房型库与 §4 坐标草案绘制的示意图。用于核对房型尺寸、布局与主路连接 —— <b>它不是可施工的几何源</b>，几何真源是设计源 <code>floor_00.json</code>。</p>

<div class="meta">
<span><b>关卡</b> expedition_01 · 远征前哨站</span>
<span><b>场地</b> 250 × 250 m（中心 2.5, 2.5）· 仅作坐标参照</span>
<span><b>网格</b> 5 m · 层高 12 m</span>
<span><b>结构</b> 单层 · 主路 {len(MAIN_SEQUENCE)} 房墙贴墙（支线已取消，无支线房）</span>
<span><b>包络</b> {n(max(r["x1"] for r in DRAWN_ROOMS) - min(r["x0"] for r in DRAWN_ROOMS))} × {n(max(r["y1"] for r in DRAWN_ROOMS) - min(r["y0"] for r in DRAWN_ROOMS))} m</span>
<span><b>房间面积</b> {n(tot)} m² <i>（只报数据，不设上限）</i></span>
<span><b>估算占用</b> {n(used)} m² <i>（含内墙，仅供对照）</i></span>
</div>

<h2>1. 总平面图</h2>
<p class="lede">主路：{' → '.join(BY_KEY[k]["name"] for k in MAIN_SEQUENCE)}。八段衔接<b>全部墙贴墙</b>（净距 0 = 共墙），不再插过渡走廊模块。<b>支线已取消</b>（业主 2026-09-25 裁定）—— 场上不再有支线房，图纸只画这条主路；主路目标口径为 13 房（10 间内容房），新房型分配与坐标待实际制作时重排（设计页 §2 顶部裁定）。画面向上为北（平面 +y = 世界 +z = 南）。</p>
<div class="card">{ov}<p class="cap">总平面图 · 含场地参考框（250×250，<b>不再是判据</b>）、25 m 网格、核心区参考框与图例。核心区（65×65 居中）本关 <code>enforce_core_exclusion=false</code>，不避让。蓝色实线 = 主路方向，箭头 = 行进方向。</p></div>

<h2>2. 主路与门数</h2>
{flow_html}
<p class="lede" style="margin-top:14px">主路 {len(MAIN_SEQUENCE) - 1} 段衔接全部为 <b>墙贴墙（净距 0）</b>、共轴偏移最大 <b>2.5 m</b>；每段走廊的过渡由共享墙上的门洞完成，不再有独立的走廊模块。门数：入口安全屋 <b>2</b>（前门 + 弃局门）；<b>主路内容房每间 2</b>（进 + 出）—— 支线取消后本关不再有 3 门房；Boss 竞技场 <b>2</b>；撤离屋 <b>1</b>。图上只标每条主路边的门位。</p>

<h2>3. 房间明细</h2>
{table}
<p class="cap" style="margin-top:8px;color:var(--muted);font-size:12px">中心坐标与区间为世界平面坐标（米）。运行时 key 是代码硬依赖：入口房 id 必为 <code>start</code>、首领房靠 <code>role="boss"</code>（key 名不受限）、撤离房 key 必为 <code>extraction</code>；其余 key 名只被验收脚本按名断言。</p>

<h2>4. 面积构成</h2>
{bars_html}
<p class="cap" style="margin-top:10px;color:var(--muted);font-size:12px">房间面积 {n(tot)} m² ｜ 内墙估算 {n(wall)} m² ｜ 走廊估算 {n(corridor)} m²（墙贴墙 ⇒ 0）｜ 估算占用 <b>{n(used)} m²</b>。上列为<b>主路 9 房</b>的数字（支线已取消，场上无支线房）。<b>面积自 2026-09-25 起全项目只报数据、不设上限</b>（场地外边界同时退出判据）—— 这些数字仅供对照，不参与准入判定，见设计页 §4.7。</p>

{cards_html}

<h2>5. 绘制口径与待确认项</h2>
<div class="warn"><b>需要你确认或留意的地方：</b>
<ul style="margin:8px 0 0;padding-left:20px">
<li><b>本图画的是「示例版图」。</b>实跑时每间内容房的房型按种子从池子里抽取（设计页 §3.4），尺寸与整张版图随之改变；<b>不变的是</b>：主路房的存在与顺序、8 个模板的尺寸、门数规则（主路内容房各 2 门）。</li>
<li><b>⚠️ 本版尺寸是「图纸先行」。</b>`room_02` / `room_03` / `room_05` / `room_06` 四间的尺寸与形态（含桥房工字型）按业主指示改画，<b>房型模板 JSON（<code>room_templates/*.json</code>）与 <code>floor_00.json</code> 尚未同步</b> —— 实跑口径要等模板与设计源同轮改完才生效。</li>
<li><b>通道桥房改成 30 × 60 工字型、只在短边开门。</b>南北两端各 15 m 是上层平台（通道），中间 30 m 段中央留 10 m 宽跨桥（沿 y 跨），桥两侧各 10 m 宽 × 30 m 进深是下层。门只能开在桥跨向两端墙（30 m 短板），最多 2 个连接且必须同轴。主路在 <code>room_05</code> 处正是「北进南出」的一根竖轴（设计页 §3.2 / §4.4、05.2 §3.6 第 8 条）。</li>
<li><b>Boss 房门位由生成算法定。</b>墙贴墙摆位会给 Boss 房两个贴合方向（进 / 出）；本图按坐标草案记的是<b>西进南出</b>（西接数据库房间02、南接撤离屋），美术源的门洞须与生成结果对齐。</li>
<li><b>墙贴墙要靠 <code>edge_policy</code> 放行。</b>主路 {len(LINKS)} 条父子边净距全为 0，校验器默认会报 <code>corridor_too_short</code>；落地时每条边都要写进 <code>floor_00.json</code> 的 <code>edge_policy.allow_zero_length</code>（见设计页 §4.1 / §7 第 6 条）。constrained 路径下生成器会按实算净距自动写这份白名单。</li>
<li><b>安全屋的两扇门方向要对一次。</b>设计源记的是 <code>entry_side = "east"</code> / <code>exit_side = "west"</code>，落设计源时先确认这两个字段在单层关卡里的实际语义。</li>
</ul></div>
<p class="cap" style="color:var(--muted);font-size:12px">图纸为<b>示意</b>：房间形态按参考图判读还原（L 形、凹字形、缺角轮廓、工字型平台与跨桥），门位只标"在哪面墙"，门槽的精确位置由工具按版图规范算；设施（工位、机柜、货架、叉车、工作站）为数量与分区的示意摆放，不是最终美术摆位。</p>

<div class="foot">
来源：<code>docs/v0.1/design/远征关卡01设计.md</code>（房型库 §3 / 坐标草案 §4）·
<code>source/art/whitebox/tower_zones/expedition_01/v001/data/level_plan.json</code> ·
<code>floor_00.json</code>。参考图见 <code>refs/expedition01/</code>。<br>
生成于 2026-09-25 · 示意图集（画的是<b>示例版图</b>；实跑版图由 <code>FloorPlanGenerator</code> 按种子现算）。本版：四房缩尺 + 桥房改工字型 + 支线取消（图纸只画主路）。
</div>

</div></body></html>"""
    return html


# ⚠️ 本文件的 XML 声明用 **\n** 收尾，不要写成 \r\n —— write_text(newline="\r\n") 会把 \n 再换成 \r\n，
#    拼出 \r\r\n（CRCRLF）。旧版就是这么来的，10 张图各带 1 处，肉眼看不出来、只在字节级核验里现形。
XML_HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n'


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
    for r in DRAWN_ROOMS:
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

    eol_bad = []
    for p in written:
        b = p.read_bytes()
        crlf = b.count(b"\r\n")
        lf = b.count(b"\n") - crlf
        cr = b.count(b"\r") - crlf          # 孤立 CR：多为 CRCRLF 的前半个，肉眼看不出
        if lf or cr:
            eol_bad.append((p, lf, cr))
        print("written: %-56s %7.1f KB  CRLF=%d LF-only=%d CR-only=%d"
              % (p.relative_to(ROOT), len(b) / 1024, crlf, lf, cr))
    if eol_bad:
        print("\n!! 行尾不纯（应为全 CRLF、无 BOM）：")
        for p, lf, cr in eol_bad:
            print("   %s  LF-only=%d  CR-only=%d" % (p.relative_to(ROOT), lf, cr))
        raise SystemExit(1)

    # 自检
    tot = sum(r["w"] * r["d"] for r in DRAWN_ROOMS)
    wall = sum((r["w"] + r["d"]) * 2.0 * WALL_T for r in DRAWN_ROOMS)
    used = tot + wall
    avail = SITE_S * SITE_S - SITE_S * 4.0 * WALL_T
    print("rooms=%d main=%d branch=%d total=%g m2 used=%g avail=%g ratio=%.3f"
          % (len(DRAWN_ROOMS), len(MAIN_SEQUENCE), len(BRANCH_KEYS), tot, used, avail, used / avail))
    xs = [r["x0"] for r in DRAWN_ROOMS] + [r["x1"] for r in DRAWN_ROOMS]
    ys = [r["y0"] for r in DRAWN_ROOMS] + [r["y1"] for r in DRAWN_ROOMS]
    print("envelope x=[%g,%g] y=[%g,%g]  (%g x %g m)  site x=[%g,%g] y=[%g,%g]"
          % (min(xs), max(xs), min(ys), max(ys), max(xs) - min(xs), max(ys) - min(ys),
             SITE_X0, SITE_X1, SITE_Y0, SITE_Y1))
    print("margin: E=%.1f W=%.1f N=%.1f S=%.1f"
          % (SITE_X1 - max(xs), min(xs) - SITE_X0, min(ys) - SITE_Y0, SITE_Y1 - max(ys)))


main()
