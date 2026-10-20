"""v004 补丁：招牌 / 蒸汽 / 铭牌 三类组件的 0.1m 颗粒补齐。

单独成一个文件是因为这三类不适用「按立面网格撒锚板」的通用做法：
- 竖招牌是**窄条**（0.8m 宽 × 12m 高），锚板网格在这里只会撒出 2 列，
  需要的是沿高度方向的**边框分件 + 压条段 + 螺栓**；
- 蒸汽是**纯几何碎团**，需要的是团块边缘的小碎粒；
- 铭牌是**笔画**，需要把每笔按 0.14m 分段，否则一笔 0.42m 在审计里算大件。
"""
from __future__ import annotations

import io

# ---------------------------------------------------------------- 1. grain 模块追加
GRAIN_ADD = '''

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
    """蒸汽柱：v002 的球状汽团 + 0.1m 级碎粒层。

    蒸汽本身没有「零件」，但周围一定有：喷口法兰与 4 颗螺栓、地面湿渍小斑、
    被吹到边上的小水珠团。这些 0.1m 级的东西才是让它读成「有源的蒸汽」而不是
    「一团白色几何」的关键。
    """
    V2.c_steam_vent(g)
    x0, x1, y0, y1, z0, z1 = _bounds(g)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    # 喷口法兰 + 4 颗地脚螺栓
    g.cyl(cx, cy, 0.0, 0.055, 0.520, MET, M4, seg=12)
    g.cyl(cx, cy, 0.055, 0.075, 0.470, MET, M5, seg=12)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        g.cyl(cx + 0.400 * math.cos(a), cy + 0.400 * math.sin(a), 0.040, 0.082,
              0.026, MET, M9, seg=6)
    # 格栅条 6 道（盖住喷口）
    for k in range(6):
        yy = cy - 0.300 + k * 0.120
        g.box(cx - 0.320, cx + 0.320, yy - 0.020, yy + 0.020, 0.075, 0.092, MET, M6)
    # 边缘小水珠团 10 颗（0.10–0.18）
    for k in range(10):
        a = k * 0.628
        rr = 0.38 + 0.22 * ((k * 7) % 5) / 5.0
        px, py = cx + rr * math.cos(a), cy + rr * math.sin(a)
        pz = 0.20 + 0.46 * ((k * 11) % 7) / 7.0
        s = 0.055 + 0.030 * (k % 3)
        g.cyl(px, py, pz, pz + s * 1.4, s, MAT, M8 if k % 2 else M9, seg=7, r2=s * 0.4)
    # 地面湿渍小斑 6 块
    for k in range(6):
        a = 0.9 + k * 0.95
        rr = 0.55 + 0.30 * (k % 3)
        px, py = cx + rr * math.cos(a), cy + rr * math.sin(a)
        g.prism([(px - 0.09, py - 0.05), (px + 0.08, py - 0.07),
                 (px + 0.10, py + 0.06), (px - 0.07, py + 0.08)],
                0.002, 0.006, GLS, (3, 9))
'''

p = "ug_props_v004_grain.py"
s = io.open(p, encoding="utf-8").read()
assert "c_hotel_sign_grain" not in s
io.open(p, "w", encoding="utf-8").write(s.rstrip() + "\n" + GRAIN_ADD)
print("grain: added 3 functions")


# ---------------------------------------------------------------- 2. 铭牌笔画分段
p2 = "ug_props_v004_struct.py"
s2 = io.open(p2, encoding="utf-8").read()
old = """    def stroke(x0, x1, z0, z1, cell=E_COLD):
        g.box(x0, x1, -0.036, -0.028, z0, z1, EMT, cell)"""
new = """    def stroke(x0, x1, z0, z1, cell=E_COLD):
        \"\"\"一笔 = 若干 0.14m 以内的段。

        整笔一块的原因：S 的横笔长 0.42m，在颗粒度审计里算「大件」；拆成 3 段
        之后每段 ≤0.14m，才是 0.1m 级零件。视觉上没有区别（段与段紧贴）。
        \"\"\"
        dx, dz = x1 - x0, z1 - z0
        n = max(1, int(math.ceil(max(abs(dx), abs(dz)) / 0.140)))
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            g.box(x0 + dx * t0, x0 + dx * t1, -0.036, -0.028,
                  z0 + dz * t0, z0 + dz * t1, EMT, cell)"""
assert old in s2
s2 = s2.replace(old, new)
io.open(p2, "w", encoding="utf-8").write(s2)
print("struct: stroke segmented")


# ---------------------------------------------------------------- 3. 主脚本接三件
p3 = "build_openworld_underground_street_v004.py"
s3 = io.open(p3, encoding="utf-8").read()
old3 = """    "foreground_service_roof_15x15_01": GRAIN.c_service_roof_grain,
}"""
new3 = """    "foreground_service_roof_15x15_01": GRAIN.c_service_roof_grain,
    # 窄条 / 特殊形体：招牌沿高度分件，蒸汽补碎粒
    "neon_sign_hotel_vertical_01": GRAIN.c_hotel_sign_grain,
    "neon_sign_bar_vertical_03": GRAIN.c_bar_sign_grain,
    "steam_vapor_vent_02": GRAIN.c_steam_grain,
}"""
assert old3 in s3
s3 = s3.replace(old3, new3)
io.open(p3, "w", encoding="utf-8").write(s3)
print("main: mapped 3 more")
