"""地下街区 v004 · 建筑颗粒层（在已有建筑几何外面补 0.1m 级零件）。

为什么用「包一层」而不是重写
--------------------------
药店、酒店、酒吧、背景楼在 v002 / v003 已经按颗粒度重写过（3.9k–6.7k 面），
主体结构是对的。审计不过的是 `fine_count`（≤0.20m 的独立零件数）：
酒店 34 / 需要 114，背景楼 2 / 需要 122。也就是说**大体量有了、小零件没有**。

重写一遍造价太大且会破坏已验收的立面。这里在原 builder 之后追加一层「预埋件
与固定件」——这也是真实立面上真实存在的东西：

- 立面锚板 + 膨胀螺栓（每 1.4m × 1.6m 一组，0.12m 见方）
- 女儿墙压顶分仓缝（每 1.2m 一道，0.05m 宽）
- 落水管卡箍（每 2.2m 一个，0.10m）
- 避雷带支架（每 1.5m 一个，0.12m）
- 楼层线脚分块（每 1.6m 一块）

这些都不依赖具体立面的窗洞位置（锚板撒在洞与洞之间的空档上，位置由网格决定），
所以对任何一栋楼都成立，也不会和已验收的窗框打架。
"""

from __future__ import annotations

import math

import ug_street_lib_v001 as L

# V3 已在 v004 里 import 过（环境变量守卫已恢复），这里拿的是同一个模块对象
import build_openworld_underground_street_v001 as V1
import build_openworld_underground_street_v002 as V2
import build_openworld_underground_street_v003 as V3

M0 = (0, 6)
M1 = (1, 6)
M2 = (2, 6)
M3 = (3, 6)
M4 = (4, 6)
M5 = (5, 6)
M6 = (6, 6)
M7 = (7, 6)
M8 = (8, 6)
M9 = (9, 6)

MET = L.ROLE_METAL
MAT = L.ROLE_MATTE
EMT = L.ROLE_EMIT
GLS = L.ROLE_GLOSS
GLASS = (3, 9)   # #0A232D 玻璃暗态
E_COLD = (9, 9)
E_ICE = (9, 5)
E_WARM = (6, 2)
E_AMBER = (7, 3)
E_TEAL = (8, 5)


def _oct(cx, cy, r, rot=0.0):
    return [(cx + r * math.cos(rot + math.pi * 2 * i / 8),
             cy + r * math.sin(rot + math.pi * 2 * i / 8)) for i in range(8)]


def _bounds(g):
    xs = [v[0] for v in g.verts]
    ys = [v[1] for v in g.verts]
    zs = [v[2] for v in g.verts]
    return (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs))


def _anchor(g, x, y, z, axis, out, cell=M7):
    """一块立面预埋锚板（0.12×0.12×0.03）+ 1 颗膨胀螺栓（0.05）

    axis='x' 表示板面法线沿 X（贴在 ±X 立面），out=±1 指定朝外方向。
    """
    if axis == "x":
        g.box(x, x + out * 0.030, y - 0.060, y + 0.060, z - 0.060, z + 0.060, MET, cell)
        cx, cy, cz = x + out * 0.038, y, z
        g.cyl_x(min(cx, cx + out * 0.030), max(cx, cx + out * 0.030), cy, cz,
                0.019, MET, M9, seg=6)
    else:
        g.box(x - 0.060, x + 0.060, y, y + out * 0.030, z - 0.060, z + 0.060, MET, cell)
        cy = y + out * 0.038
        g.cyl_y(min(cy, cy + out * 0.030), max(cy, cy + out * 0.030), x, z,
                0.019, MET, M9, seg=6)


def _grid(g, x0, x1, y0, y1, z0, z1, axis, out, dy=1.60, dz=1.40, cell=M7,
          skip_margin=0.35):
    """在立面矩形区域内按网格撒锚板。洞的位置不参与计算——网格是均匀的，
    真实立面上的预埋件本来也是按结构模数排的。"""
    if axis == "x":
        ny = max(1, int((y1 - y0 - 2 * skip_margin) / dy))
        for i in range(ny):
            yy = y0 + skip_margin + (i + 0.5) * (y1 - y0 - 2 * skip_margin) / ny
            nz = max(1, int((z1 - z0 - 2 * skip_margin) / dz))
            for k in range(nz):
                zz = z0 + skip_margin + (k + 0.5) * (z1 - z0 - 2 * skip_margin) / nz
                _anchor(g, x0 if out < 0 else x1, yy, zz, "x", out, cell)
    else:
        nx = max(1, int((x1 - x0 - 2 * skip_margin) / dy))
        for i in range(nx):
            xx = x0 + skip_margin + (i + 0.5) * (x1 - x0 - 2 * skip_margin) / nx
            nz = max(1, int((z1 - z0 - 2 * skip_margin) / dz))
            for k in range(nz):
                zz = z0 + skip_margin + (k + 0.5) * (z1 - z0 - 2 * skip_margin) / nz
                _anchor(g, xx, y0 if out < 0 else y1, zz, "y", out, cell)


def _parapet_joints(g, x0, x1, y0, y1, z_top, h=0.10, pitch=1.20):
    """女儿墙压顶分仓缝：沿四边每 pitch 一道 0.05 宽暗缝"""
    for (a, b, fixed, axis) in ((y0, y1, x0, "y"), (y0, y1, x1, "y"),
                                (x0, x1, y0, "x"), (x0, x1, y1, "x")):
        n = max(1, int((b - a) / pitch))
        for i in range(n):
            c = a + (i + 0.5) * (b - a) / n
            if axis == "y":
                g.box(fixed - 0.010, fixed + 0.010, c - 0.025, c + 0.025,
                      z_top - h, z_top + 0.010, MAT, M0)
            else:
                g.box(c - 0.025, c + 0.025, fixed - 0.010, fixed + 0.010,
                      z_top - h, z_top + 0.010, MAT, M0)


def _downpipe_clamps(g, x, y, z0, z1, out, pitch=2.20):
    """落水管卡箍：每 pitch 一个（2 半环 + 2 螺栓）"""
    n = max(1, int((z1 - z0) / pitch))
    for i in range(n):
        zz = z0 + (i + 0.5) * (z1 - z0) / n
        g.box(x, x + out * 0.040, y - 0.055, y + 0.055, zz - 0.030, zz + 0.030, MET, M5)
        for sy in (-1, 1):
            g.cyl_x(x + out * 0.040, x + out * 0.058, y + sy * 0.036, zz,
                    0.012, MET, M9, seg=5)


def _lightning_staples(g, x0, x1, y, z, pitch=1.50):
    """避雷带支架：每 pitch 一个（小立板 + 夹口）"""
    n = max(1, int((x1 - x0) / pitch))
    for i in range(n):
        xx = x0 + (i + 0.5) * (x1 - x0) / n
        g.box(xx - 0.012, xx + 0.012, y - 0.014, y + 0.075, z, z + 0.130, MET, M6)
        g.box(xx - 0.020, xx + 0.020, y - 0.020, y + 0.020, z + 0.115, z + 0.145, MET, M8)


# ================================================================ 酒店
def c_hotel_grain(g):
    """酒店楼：v003 主体 + 预埋件层。"""
    V3.c_hotel_tower_detail(g)
    x0, x1, y0, y1, z0, z1 = _bounds(g)
    # 东立面（+X，朝街）与西立面（-X）撒锚板
    _grid(g, x0, x1, y0, y1, 2.2, z1 - 1.2, "x", +1, dy=1.70, dz=1.45)
    _grid(g, x0, x1, y0, y1, 2.2, z1 - 1.2, "x", -1, dy=2.40, dz=2.20, cell=M6)
    # 南立面（-Y）少量
    _grid(g, x0, x1, y0, y1, 2.2, z1 - 1.4, "y", -1, dy=2.40, dz=2.40, cell=M6)
    # 女儿墙分仓缝 + 避雷带支架 + 落水管卡箍
    _parapet_joints(g, x0, x1, y0, y1, z1 - 0.02, h=0.16, pitch=1.15)
    _lightning_staples(g, x0 + 0.4, x1 - 0.4, y1 - 0.06, z1 + 0.02, pitch=1.35)
    _downpipe_clamps(g, x1 + 0.005, y0 + 0.30, 0.6, z1 - 1.0, +1, pitch=2.30)
    _downpipe_clamps(g, x0 - 0.005, y1 - 0.30, 0.6, z1 - 1.0, -1, pitch=2.30)


# ================================================================ 酒吧
def c_bar_grain(g):
    V3.c_bar_building_detail(g)
    x0, x1, y0, y1, z0, z1 = _bounds(g)
    _grid(g, x0, x1, y0, y1, 1.8, z1 - 1.2, "x", -1, dy=1.60, dz=1.35, cell=M7)
    _grid(g, x0, x1, y0, y1, 1.8, z1 - 1.2, "x", +1, dy=2.30, dz=2.10, cell=M6)
    _grid(g, x0, x1, y0, y1, 1.8, z1 - 1.4, "y", +1, dy=2.30, dz=2.10, cell=M6)
    _parapet_joints(g, x0, x1, y0, y1, z1 - 0.02, h=0.12, pitch=1.05)
    _lightning_staples(g, x0 + 0.4, x1 - 0.4, y0 + 0.06, z1 + 0.02, pitch=1.25)
    _downpipe_clamps(g, x0 - 0.005, y1 - 0.26, 0.5, z1 - 1.2, -1, pitch=2.10)


# ================================================================ 背景楼
def c_backdrop_grain(g):
    V3.c_backdrop_tower_detail(g)
    x0, x1, y0, y1, z0, z1 = _bounds(g)
    _grid(g, x0, x1, y0, y1, 1.6, z1 - 1.2, "x", -1, dy=1.55, dz=1.30, cell=M7)
    _grid(g, x0, x1, y0, y1, 1.6, z1 - 1.2, "x", +1, dy=1.55, dz=1.30, cell=M6)
    _grid(g, x0, x1, y0, y1, 1.6, z1 - 1.4, "y", -1, dy=2.00, dz=1.80, cell=M6)
    _grid(g, x0, x1, y0, y1, 1.6, z1 - 1.4, "y", +1, dy=2.00, dz=1.80, cell=M6)
    _parapet_joints(g, x0, x1, y0, y1, z1 - 0.02, h=0.12, pitch=1.10)
    _lightning_staples(g, x0 + 0.4, x1 - 0.4, y1 - 0.06, z1 + 0.02, pitch=1.30)
    _downpipe_clamps(g, x1 + 0.005, y0 + 0.28, 0.5, z1 - 1.0, +1, pitch=2.20)


# ================================================================ 窄巷店面
def c_alley_grain(g):
    V2.c_alley_shophouse(g)
    x0, x1, y0, y1, z0, z1 = _bounds(g)
    _grid(g, x0, x1, y0, y1, 1.4, z1 - 1.6, "x", +1, dy=1.55, dz=1.30, cell=M7)
    _grid(g, x0, x1, y0, y1, 1.4, z1 - 1.6, "x", -1, dy=2.00, dz=1.80, cell=M6)
    _grid(g, x0, x1, y0, y1, 1.4, z1 - 1.6, "y", -1, dy=1.60, dz=1.35, cell=M6)
    _parapet_joints(g, x0, x1, y0, y1, z1 - 0.02, h=0.10, pitch=1.00)
    _lightning_staples(g, x0 + 0.3, x1 - 0.3, y0 + 0.05, z1 + 0.02, pitch=1.20)
    _downpipe_clamps(g, x1 + 0.005, y1 - 0.24, 0.4, z1 - 1.0, +1, pitch=1.90)


# ================================================================ 前景机房
def c_service_roof_grain(g):
    V1.c_foreground_roof(g)
    x0, x1, y0, y1, z0, z1 = _bounds(g)
    _grid(g, x0, x1, y0, y1, 1.2, z1 - 0.8, "x", +1, dy=1.50, dz=1.30, cell=M7)
    _grid(g, x0, x1, y0, y1, 1.2, z1 - 0.8, "x", -1, dy=1.50, dz=1.30, cell=M6)
    _grid(g, x0, x1, y0, y1, 1.2, z1 - 0.8, "y", +1, dy=1.60, dz=1.40, cell=M6)
    _parapet_joints(g, x0, x1, y0, y1, z1 - 0.02, h=0.10, pitch=1.00)
    _lightning_staples(g, x0 + 0.3, x1 - 0.3, y1 - 0.05, z1 + 0.02, pitch=1.15)
    _downpipe_clamps(g, x0 - 0.005, y0 + 0.26, 0.4, z1 - 0.8, -1, pitch=1.90)


# ================================================================ 竖招牌（窄条）
def _sign_edge_bands(g, x, y, z0, z1, pitch=0.55, w=0.10, cell=M7):
    """沿竖招牌两条竖边排压条段 + 螺栓（每段 0.10 宽 × 0.50 高 + 1 颗螺栓）"""
    n = max(1, int((z1 - z0) / pitch))
    for i in range(n):
        zz = z0 + i * (z1 - z0) / n
        hh = min((z1 - z0) / n - 0.04, pitch - 0.05)
        for sy in (-1, 1):
            g.box(x, x + 0.024, y + sy * w - 0.055, y + sy * w + 0.055,
                  zz + 0.02, zz + 0.02 + hh, MET, cell)
            g.cyl_x(x + 0.024, x + 0.046, y + sy * w, zz + 0.02 + hh * 0.5,
                    0.016, MET, M9, seg=6)


def _sign_corners(g, x, y, z0, z1, w=0.10):
    """招牌四角角码 + 2 颗螺栓（每处）"""
    for zz in (z0, z1):
        for sy in (-1, 1):
            g.box(x, x + 0.030, y + sy * w - 0.050, y + sy * w + 0.050,
                  zz - 0.030, zz + 0.030, MET, M5)
            g.cyl_x(x + 0.030, x + 0.050, y + sy * w, zz, 0.014, MET, M9, seg=6)


def c_hotel_sign_grain(g):
    """HOTEL 竖招牌：v003 几何 + 边框分件层。

    v003 的招牌是 12.4m 高的一根窄条，边框是一整根。0.1m 颗粒要求沿高度分件：
    每 0.55m 一段压条 + 1 颗螺栓，两侧共 2 列，12m 高 → 44 段 / 44 颗螺栓。
    """
    V3.c_hotel_sign_detail(g)
    x0, x1, y0, y1, z0, z1 = _bounds(g)
    _sign_edge_bands(g, x1, (y0 + y1) / 2.0, z0 + 0.25, z1 - 0.25, pitch=0.55,
                     w=(y1 - y0) * 0.42)
    _sign_corners(g, x1, (y0 + y1) / 2.0, z0 + 0.10, z1 - 0.10, w=(y1 - y0) * 0.42)
    # 背面与立面的连接件（每 1.4m 一组：2 根斜撑 + 2 螺栓）
    n = max(1, int((z1 - z0) / 1.40))
    for i in range(n):
        zz = z0 + (i + 0.5) * (z1 - z0) / n
        for dz in (-0.16, 0.16):
            g.beam((x0 - 0.02, 0.0, zz + dz), (x0 - 0.20, 0.0, zz + dz * 0.4),
                   0.034, 0.034, MET, M5)
            g.cyl_x(x0 - 0.020, x0, 0.0, zz + dz, 0.012, MET, M9, seg=5)


def c_bar_sign_grain(g):
    """BAR 竖招牌：v003 几何 + 边框分件层（招牌较矮，段距 0.45m）。"""
    V3.c_bar_sign_detail(g)
    x0, x1, y0, y1, z0, z1 = _bounds(g)
    w = (y1 - y0) * 0.42
    n = max(1, int((z1 - z0) / 0.45))
    for i in range(n):
        zz = z0 + i * (z1 - z0) / n
        hh = min((z1 - z0) / n - 0.04, 0.40)
        for sy in (-1, 1):
            g.box(x0 - 0.024, x0, (y0 + y1) / 2.0 + sy * w - 0.052,
                  (y0 + y1) / 2.0 + sy * w + 0.052, zz + 0.02, zz + 0.02 + hh, MET, M7)
            g.cyl_x(x0 - 0.046, x0 - 0.024, (y0 + y1) / 2.0 + sy * w,
                    zz + 0.02 + hh * 0.5, 0.015, MET, M9, seg=6)
    for zz in (z0 + 0.08, z1 - 0.08):
        for sy in (-1, 1):
            g.box(x0 - 0.030, x0, (y0 + y1) / 2.0 + sy * w - 0.048,
                  (y0 + y1) / 2.0 + sy * w + 0.048, zz - 0.028, zz + 0.028, MET, M5)


# ================================================================ 蒸汽
def c_steam_grain(g):
    """地面蒸汽：喷口（结构件）+ 汽团（第 4 版，前 3 版全错，逐条记下）。

    失败记录（同一个坑反复踩，必须写死在这里）
    ------------------------------------------
    ① v002「5 颗等距竖直球团」              → 读成一摞白碗（球面完整、间距相等）
    ② 「逐层放大 + 锥形收尖」                → 读成蘑菇 / 伞（锥体必有轮廓）
    ③ 「低矮扁八边形雾片」                  → 读成悬浮的荷叶（薄片必有边界）

    **共同错误：让汽团彼此分离**。任何一组分离的闭合体在近景都读成"一堆东西"。
    正解是**让它们严重重叠**：相邻球团的重叠量要 > 半径的 50%，这样多颗球在视觉上
    融合成一个轮廓不规则的整体，边界是"毛"的而不是"硬"的。

    颜色也压到最低：M6/M7（lum 70/86），只比周围立面亮 1–2 档。
    之前用 M9（127）在暗场景里直接过曝成纯白，才会那么抢眼。

    另：喷口本身必须做完整 —— 这才是「0.1m 颗粒度」要表达的部分，
    蒸汽的**源头**清楚，汽团哪怕形态不完美也读得懂。
    """
    # ---------------- 喷口（0.1m 级结构件）
    g.prism(_oct(0.0, 0.0, 0.430), 0.0, 0.030, MAT, M2)
    g.prism(_oct(0.0, 0.0, 0.392), 0.030, 0.044, MAT, M3)
    g.cyl(0.0, 0.0, 0.030, 0.066, 0.352, MET, M4, seg=12)
    g.cyl(0.0, 0.0, 0.066, 0.086, 0.312, MET, M5, seg=12)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        px, py = 0.396 * math.cos(a), 0.396 * math.sin(a)
        g.cyl(px, py, 0.030, 0.074, 0.024, MET, M9, seg=6)
        g.cyl(px, py, 0.074, 0.092, 0.032, MET, M7, seg=6)
    g.cyl(0.0, 0.0, 0.086, 0.096, 0.296, MAT, M0, seg=12)
    for k in range(6):
        yy = -0.245 + k * 0.098
        g.box(-0.262, 0.262, yy - 0.017, yy + 0.017, 0.096, 0.112, MET, M6)
        g.box(-0.262, 0.262, yy - 0.017, yy + 0.017, 0.112, 0.118, MET, M8)

    # ---------------- 汽团：520 颗紧凑堆叠的碎粒（第 6 版）
    #   第 5 版的问题：230 颗 + 圆锥收尖 → 读成「一串碎石」。两个原因：
    #   ① 数量不够，粒与粒之间有空隙，能看见背景（雾必须是不透明的整体）；
    #   ② 每颗都有尖顶（r2=sz*0.30），一堆尖顶 = 碎石子。
    #   这一版：数量 ×2.3、去掉尖顶（改成上下都收的圆润碎粒）、
    #   粒径压到 0.05–0.10、间距小于粒径（保证重叠成实心团）。
    N = 520
    for i in range(N):
        t = (i + 0.5) / N
        tt = t ** 0.66
        z = 0.09 + tt * 1.42
        spread = 0.075 + 0.40 * tt ** 1.7
        dx = 0.58 * tt * tt
        dy = 0.32 * tt * tt
        a = i * 2.399963 + tt * 2.2
        rad = spread * math.sqrt((i * 0.6180339887) % 1.0)
        px = dx + rad * math.cos(a) + 0.045 * math.sin(i * 1.7)
        py = dy + rad * math.sin(a) + 0.045 * math.cos(i * 2.3)
        pz = z + 0.040 * math.sin(i * 3.1)
        # 粒径 0.048–0.098：全部落在 0.1m 颗粒度区间内
        sz = 0.048 + 0.050 * ((i * 7) % 5) / 4.0
        sz *= (1.0 - 0.22 * tt)
        cell = M8 if (i % 4 == 0) else (M7 if i % 4 < 2 else M6)
        # 圆润碎粒：上下都收口（0.55s → s → 0.55s），无尖顶
        g.cyl(px, py, pz - sz * 0.55, pz, sz * 0.58, MAT, cell, seg=6, r2=sz)
        g.cyl(px, py, pz, pz + sz * 0.55, sz, MAT, cell, seg=6, r2=sz * 0.58)

    # ---------------- 喷口内侧被顶光打亮的一圈（雾的"源"，也是唯一的亮部）
    g.cyl(0.0, 0.0, 0.096, 0.132, 0.232, L.ROLE_EMIT, E_ICE, seg=10)

    # ---------------- 地面湿渍 8 块
    for k in range(8):
        a = 0.5 + k * 0.80
        rq = 0.62 + 0.30 * (k % 3)
        px, py = 0.18 + rq * math.cos(a), 0.10 + rq * math.sin(a)
        g.prism([(px - 0.105, py - 0.060), (px + 0.095, py - 0.080),
                 (px + 0.120, py + 0.070), (px - 0.085, py + 0.095)],
                0.002, 0.007, GLS, GLASS)
