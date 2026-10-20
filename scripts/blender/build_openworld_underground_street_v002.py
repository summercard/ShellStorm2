"""地下街区 v002 —— 大世界 open_world 地下街区（编号 02）Blender 原始文件构建器。

参考图：用户提供的赛博朋克街区概念图（HOTEL / 藥 / BAR / SECTOR 07 東區）。
定位：与 v001 同属「大世界 open_world 地下街区」，是**同一地下空间里的另一段街区**：
      52×52m 岩腔不变，但主街改为南北向 10m 窄谷、两侧建筑满铺到穹顶下、路口改在街心，
      镜头语言从 v001 的「四十五度看十字广场」换成「沿街纵深 + 前景机房顶」。

组件口径（遵守 02 号规范的三道判据）：
  * 归并键 / 几何指纹：v001 已按归并键做过归并，本版**不再复制几何**——
    直接 import v001 的组件生成器（同一函数体），几何零漂移；
    只有 4 件是本版新生产（蒸汽排风口 / 窄巷店面 / 悬臂信号灯杆 / 售货机柜组）。
  * 唯一组件 48 ≤ 50；同族最大 2 ≤ 3。
  * 组件母版仍是「一份几何 + N 个 Collection Instance」，正式摆位归后续 Godot TSCN。

运行（无头）：
    blender --background --python build_openworld_underground_street_v002.py
"""

from __future__ import annotations

import json
import math
import os
import sys

# 让 v001 模块只当「组件生成器库」被 import，不触发它自己的 main()。
os.environ.setdefault("UG_STREET_BUILD_LIB_ONLY", "1")

import bpy  # noqa: E402

PROJECT = r"I:\工作项目\shellstrom2\ShellStorm2"
sys.path.insert(0, os.path.join(PROJECT, "scripts", "blender"))

import ug_street_lib_v001 as L  # noqa: E402
import build_openworld_underground_street_v001 as V1  # noqa: E402

SUITE = "underground_street"
VERSION = "v002"
OUT_DIR = os.path.join(PROJECT, "art_source", "environments", "open_world", "source", SUITE, VERSION)
BLEND_PATH = os.path.join(OUT_DIR, "env_%s_source_%s.blend" % (SUITE, VERSION))
ASSET_ID_ROOT = "ENV-OPENWORLD-UNDERGROUND-STREET-02"

# ---------------------------------------------------------------- 尺寸常量
SLAB_HALF = 26.0          # 基底 52×52（与 v001 同一岩腔）
WALL_Z = 25.7             # 围护墙中心线
CEIL_BOTTOM = 28.6
ROAD_HALF = 5.0           # 主街半宽 5m（双黄线居中，单车道双向）
WALK_OUTER = 10.0         # 人行道外沿 / 建筑立面线
FACADE_X = 15.0           # 建筑体量中心 X（进深 10m）


# ================================================================ 本版新增组件
# 这 4 件是 v001 里被压掉的「参考图标志性元素」：
# 地面蒸汽、窄巷店面、悬臂信号灯、售货机柜。全部只服务地下街区，故 scope=suite_local。

# ---------------------------------------------------------------- 暗部邻近色族
# 色盘实测 sRGB（不是线性值；Blender 的 image.pixels 对本色盘返回的就是 sRGB 编码）。
# 业主 2026-10-20 指定：不要再堆一堆跳跃色；亮暗之间可以拉大，暗部一律用邻近色或同暗度色。
# 下面 8 格全部在 lum 6–30 的暗区间，色相锁在 240°–275° 的蓝紫带里，靠**色相微差 + 出挑阴影**
# 分层，不靠明度跳。亮部（自发光）才允许跳色。
N_INK = (0, 9)      # #05050C  lum  6  窗洞/门洞内腔、结构阴影缝
N_NIGHT = (1, 6)     # #0A1126  lum 17  主体墙基色
N_NIGHT2 = (2, 9)    # #16153A  lum 24  主体墙分段次色
N_STONE = (2, 6)     # #0E1A3E  lum 26  基座/墙裙
V_SEAM = (0, 7)      # #15072D  lum 13  凹缝、背光面
V_BAND = (2, 7)      # #220D43  lum 21  腰线
V_TRIM = (3, 7)      # #290F52  lum 25  线脚/金属框（主金属色）
V_TRIM2 = (4, 7)     # #311262  lum 30  檐口受光面
T_GLASS = (3, 9)     # #0A232D  lum 30  玻璃暗态（同暗度的青，破一点色相）
T_DARK = (0, 5)      # #041A1A  lum 21  深青金属
# 亮部（自发光，允许跳跃）
E_COLD = (9, 9)      # #C5CED8  橱窗冷白
E_ICE = (9, 5)       # #5D6E82  招牌冷青边框
E_TEAL = (8, 5)      # #4A6D71  招牌面板
E_WARM = (6, 2)      # #71421B  门头暖光
E_PINK = (6, 8)      # #6A2045  一点玫红（只做小面积）
E_DIM = (5, 5)       # #145F56  窗内暗亮


def _fx_frame(g, x0, x1, y0, y1, z0, z1, w, role, cell):
    """X 向立面上的矩形窗/门框：上下左右四条边，框宽 w。"""
    g.box(x0, x1, y0, y1, z1 - w, z1, role, cell)
    g.box(x0, x1, y0, y1, z0, z0 + w, role, cell)
    g.box(x0, x1, y0, y0 + w, z0 + w, z1 - w, role, cell)
    g.box(x0, x1, y1 - w, y1, z0 + w, z1 - w, role, cell)


def _slats(g, x0, x1, y0, y1, z0, z1, n, role, cell, gap=0.34):
    """横向帘片 / 百叶：沿 Z 均匀排 n 片，片间留缝。"""
    step = (z1 - z0) / n
    for i in range(n):
        zz = z0 + i * step
        g.box(x0, x1, y0, y1, zz + step * gap * 0.5, zz + step * (1.0 - gap * 0.5), role, cell)


def _vpipe(g, x, y, z0, z1, r, role, cell, clamps=5, cell_clamp=None):
    """竖向管道 + 卡箍。"""
    g.cyl(x, y, z0, z1, r, role, cell, seg=8)
    for i in range(clamps):
        zz = z0 + (z1 - z0) * (i + 0.5) / clamps
        g.cyl(x, y, zz, zz + 0.09, r * 1.55, role, cell_clamp or cell, seg=8)


def _bolt_x(g, x0, x1, y, z, r, role, cell):
    """朝 +X 的短圆柱螺栓头。"""
    g.cyl_x(x0, x1, y, z, r, role, cell, seg=6)


# ================================================================ 药店楼（远景颗粒度版）

# 主体控制线（正面 = +X，局部坐标）
PH_X0, PH_X1 = -5.0, 5.0         # 进深 10m
PH_Y0, PH_Y1 = -4.0, 4.0         # 面宽 8m
PH_TOP = 7.50                    # 屋面标高
PH_BASE = 0.52                   # 基座顶
PH_BELT0, PH_BELT1 = 3.05, 3.34  # 腰线（厚 0.29）
PH_F2Z0, PH_F2Z1 = 5.30, 6.80    # 二层窗（窗高 1.50m）
PH_CORNICE = (6.86, 7.10, 7.34)  # 三级檐口
PH_PARA = 8.20                   # 女儿墙顶
PH_SKIN = 0.40                   # 表皮厚 = 窗洞进深
SEAM = 0.06

# 一层开间（局部 y）：橱窗 / 窄展窗 / 卷帘 / 员工门 / 实墙
PH_BAY = {
    "shop":   (-3.62, -1.14),
    "narrow": (-0.72, 0.00),
    "shut":   (0.34, 1.74),
    "door":   (2.02, 2.86),
}
# 一层壁柱（局部 y）
PH_PIERS1 = [(-4.00, -3.62), (-1.14, -0.72), (0.00, 0.34), (1.74, 2.02), (2.86, 3.30)]
# 二层壁柱
PH_PIERS2 = [(-4.00, -3.58), (-1.10, -0.68), (0.94, 1.34), (2.90, 3.28)]
# 二层窗（y 中心, 是否亮灯）
PH_WIN2 = [(-0.20 + 0.22, True), (2.11, False)]   # (-0.68..0.94) 与 (1.34..2.90) 的中线

# 暗部单色相梯度（色盘 R6 列 #051128→#425972，色相锁蓝紫 235–245°，亮度 16→86）
# 业主口径：暗部只走邻近色/同暗度，色相不跳；亮暗可以拉开；跳色只留给自发光。
# 业主口径「暗部走邻近色、亮暗可以跳跃」的落法：
# 色相全部压在 #051128–#425972 这一列（蓝紫 235–245°），只动亮度；
# 立面跨度按 9 → 86 排（洞内 9 / 墙 26–35 / 线脚 43–56 / 压顶受光 70–86），
# 不再像上一版全挤在 17–30 —— 那种排布在暗部等于同一个色，任何线脚都不出形。
N_INK = (0, 0)      # #090813    9  洞内最暗 / 结构阴影
N_D0 = (0, 6)       # #051128   16  背光面
N_D1 = (1, 6)       # #0A1126   17  背光墙 / 深槽
N_D2 = (2, 6)       # #0E1A3E   26  墙分级 / 基座石
N_D3 = (3, 6)       # #0D2361   35  壁柱 / 柱身
N_D4 = (4, 6)       # #112D6A   43  腰线 / 线脚
N_D5 = (5, 6)       # #1B3B6F   56  受光线脚
N_D6 = (6, 6)       # #2B4A71   70  金属高光
N_D7 = (7, 6)       # #425972   86  最亮面（檐口上口 / 压顶 / 窗台顶）
V_SEAM = (0, 7)     # #15072D   13  凹缝
V_BAND = (2, 7)     # #220D43   21  门楣
V_TRIM = (3, 7)     # #290F52   25  金属框
V_TRIM2 = (4, 7)    # #311262   30  框受光
T_GLASS = (3, 9)    # #0A232D   30  玻璃暗态
T_DARK = (0, 5)     # #041A1A   21  深青金属
# 自发光（允许跳色）
E_COLD = (9, 9)     # #C5CED8  冷白（橱窗 / 亮窗 / 字）
E_ICE = (9, 5)      # #5D6E82  冷青灰（小字 / 反射条）
E_TEAL = (8, 5)     # #4A6D71  招牌面板
E_WARM = (6, 2)     # #71421B  门头暖光
E_PINK = (6, 8)     # #6A2045  天线顶灯（极小面积）
E_DIM = (5, 5)      # #145F56  窗内暗亮


def _wall_holes(g, x0, x1, y0, y1, z0, z1, holes, role, cell):
    """在 y–z 立面上开矩形洞：按洞的 z 边切横带，再按洞的 y 跨度切竖段。

    这是本文件唯一能"真正开洞"的做法：之前窗/门都是画在实心墙**里面**的盒子，
    玻璃和发光面被墙体自己挡死（实测整个立面只剩窗框可见）。用带洞拆分后，
    洞的四壁自然成为 0.40 进深的侧壁，斜俯视时有阴影，正面看有厚度。
    """
    zs = sorted({z0, z1} | {h[2] for h in holes} | {h[3] for h in holes})
    zs = [z for z in zs if z0 - 1e-6 <= z <= z1 + 1e-6]
    for i in range(len(zs) - 1):
        za, zb = zs[i], zs[i + 1]
        if zb - za < 1e-5:
            continue
        zc = (za + zb) * 0.5
        segs = [(y0, y1)]
        for (hy0, hy1, hz0, hz1) in holes:
            if not (hz0 - 1e-6 <= zc <= hz1 + 1e-6):
                continue
            out = []
            for (a, b) in segs:
                if hy1 <= a + 1e-6 or hy0 >= b - 1e-6:
                    out.append((a, b))
                    continue
                if hy0 > a + 1e-6:
                    out.append((a, hy0))
                if hy1 < b - 1e-6:
                    out.append((hy1, b))
            segs = out
        for (a, b) in segs:
            if b - a > 1e-4:
                g.box(x0, x1, a, b, za, zb, role, cell)


def _wall_holes_y(g, y0, y1, x0, x1, z0, z1, holes, role, cell):
    """同上，但开在 x–z 立面上（±Y 侧立面）。holes = (hx0, hx1, hz0, hz1)。"""
    zs = sorted({z0, z1} | {h[2] for h in holes} | {h[3] for h in holes})
    zs = [z for z in zs if z0 - 1e-6 <= z <= z1 + 1e-6]
    for i in range(len(zs) - 1):
        za, zb = zs[i], zs[i + 1]
        if zb - za < 1e-5:
            continue
        zc = (za + zb) * 0.5
        segs = [(x0, x1)]
        for (hx0, hx1, hz0, hz1) in holes:
            if not (hz0 - 1e-6 <= zc <= hz1 + 1e-6):
                continue
            out = []
            for (a, b) in segs:
                if hx1 <= a + 1e-6 or hx0 >= b - 1e-6:
                    out.append((a, b))
                    continue
                if hx0 > a + 1e-6:
                    out.append((a, hx0))
                if hx1 < b - 1e-6:
                    out.append((hx1, b))
            segs = out
        for (a, b) in segs:
            if b - a > 1e-4:
                g.box(a, b, y0, y1, za, zb, role, cell)


# 藥 字笔画表。坐标归一：u∈[-0.5,0.5]（×w），v∈[0,1]（×h，0 在字脚）。
# 结构 = 艹 / (幺 白 幺) / 木，三段之间各留 ~0.045 缺口。
# 上一版有两处结构错误，导致整字读不出来：
#   ① 艹 的两根竖画没穿过横画 → 读成「工」；本版竖画上下各出 0.10；
#   ② 幺 只有两横一竖 → 读成字母「I」；本版用「上短横 + 斜笔 + 下短横」的 Z 形折。
GLYPH_YAO_BOX = [
    # ---- 艹（0.78–1.00）：长横 + 两根穿过的竖画
    (-0.440, 0.440, 0.905, 0.975),
    (-0.315, -0.245, 0.800, 1.000),
    (0.245, 0.315, 0.800, 1.000),
    # ---- 白（0.335–0.775）：外框 + 中横
    (-0.185, 0.185, 0.715, 0.775),
    (-0.185, -0.125, 0.335, 0.775),
    (0.125, 0.185, 0.335, 0.775),
    (-0.185, 0.185, 0.335, 0.395),
    (-0.125, 0.125, 0.545, 0.605),
    # ---- 左 幺（-0.475..-0.300）：上横 / 下横（斜笔另列）
    (-0.475, -0.300, 0.665, 0.720),
    (-0.475, -0.300, 0.415, 0.470),
    # ---- 右 幺
    (0.300, 0.475, 0.665, 0.720),
    (0.300, 0.475, 0.415, 0.470),
    # ---- 木（0.00–0.290）：一横 + 一竖（两撇捺另列）
    (-0.470, 0.470, 0.225, 0.290),
    (-0.045, 0.045, 0.000, 0.290),
]

# 斜笔：(u0,v0) → (u1,v1)，笔宽（归一，按 w 缩放）
GLYPH_YAO_DIAG = [
    # 左 幺：右上一笔斜向左下（Z 形折的下折）
    (-0.322, 0.692, -0.452, 0.494),
    # 右 幺
    (0.322, 0.692, 0.452, 0.494),
    # 木 的撇 / 捺
    (-0.020, 0.205, -0.330, 0.052),
    (0.020, 0.205, 0.330, 0.052),
]


def _slant(g, axis, a0, a1, p0, p1, wdt, role, cell):
    """平面内的一笔斜画（平行四边形棱柱）。

    axis="x"：平面法线 ±X，p 为 (y,z)；axis="y"：法线 ±Y，p 为 (x,z)。
    """
    (pa, qa), (pb, qb) = p0, p1
    dy, dz = pb - pa, qb - qa
    ln = math.hypot(dy, dz) or 1.0
    ny, nz = -dz / ln * wdt * 0.5, dy / ln * wdt * 0.5
    v = []
    if axis == "x":
        for x in (a0, a1):
            v += [(x, pa - ny, qa - nz), (x, pa + ny, qa + nz),
                  (x, pb + ny, qb + nz), (x, pb - ny, qb - nz)]
    else:
        for y in (a0, a1):
            v += [(pa - ny, y, qa - nz), (pa + ny, y, qa + nz),
                  (pb + ny, y, qb + nz), (pb - ny, y, qb - nz)]
    f = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    g.raw(v, f, role, cell)


def _glyph(g, axis, a0, a1, u0, v0, w, h, role, cell):
    """把 藥 字铺到一张轴对齐平面上（横竖用盒子，斜笔用梁）。

    axis="x"：法线 ±X，横轴为 y；axis="y"：法线 ±Y，横轴为 x。
    beam 的 w 沿世界 x（即平面法线），t 才是平面内的笔宽 —— 两个参数别搞反，
    反了就是"一道从墙里插出来的扁片"。
    """
    for (uu0, uu1, vv0, vv1) in GLYPH_YAO_BOX:
        p0, p1 = u0 + uu0 * w, u0 + uu1 * w
        q0, q1 = v0 + vv0 * h, v0 + vv1 * h
        if axis == "x":
            g.box(a0, a1, p0, p1, q0, q1, role, cell)
        else:
            g.box(p0, p1, a0, a1, q0, q1, role, cell)
    for (ua, va, ub, vb) in GLYPH_YAO_DIAG:
        pa, pb = u0 + ua * w, u0 + ub * w
        qa, qb = v0 + va * h, v0 + vb * h
        _slant(g, axis, a0, a1, (pa, qa), (pb, qb), 0.070 * w, role, cell)


def _win_panel(g, y0, y1, z0, z1, lit, mullions=2, transom=True):
    """正立面 +X 上的一樘窗（用于**已开洞**的墙，不再需要自带暗腔）。

    层叠顺序从外到内：外框(F..F+0.06) → 窗格(F-0.20) → 玻璃/发光面(F-0.30)。
    发光面在最里，靠 0.30 的洞口进深框住，读成"窗内透出的光"而不是"贴一张白纸"。
    """
    F = PH_X1
    # 玻璃 / 发光面（最里层）
    if lit:
        # 亮窗用 E_ICE(#5D6E82) 而不是 E_COLD(#C5CED8)：材质自发光强度是全局 2.4，
        # 纯冷白在 1.5m 高的整片窗面上直接过曝成一块白板（实测正面机位纯白）。
        # 窗内要读成"透过玻璃的冷光"，不是一盏灯。
        g.box(F - 0.31, F - 0.27, y0 + 0.03, y1 - 0.03, z0 + 0.03, z1 - 0.03,
              L.ROLE_EMIT, E_ICE)
        # 窗内顶部一条更亮的灯带，保留"窗是亮的"的判读
        g.box(F - 0.31, F - 0.27, y0 + 0.06, y1 - 0.06, z1 - 0.16, z1 - 0.06,
              L.ROLE_EMIT, E_COLD)
    else:
        g.box(F - 0.31, F - 0.27, y0 + 0.03, y1 - 0.03, z0 + 0.03, z1 - 0.03,
              L.ROLE_GLOSS, T_GLASS)
        # 暗窗也要有一道冷反射，否则整块死黑
        g.box(F - 0.31, F - 0.27, y0 + 0.10, y1 - 0.36, z0 + 0.10, z0 + 0.22,
              L.ROLE_EMIT, E_ICE)
    # 窗格（在中层，压住发光面边缘）
    xf0, xf1 = F - 0.20, F - 0.15
    if mullions:
        step = (y1 - y0) / float(mullions)
        for i in range(1, mullions):
            c = y0 + step * i
            g.box(xf0, xf1, c - 0.035, c + 0.035, z0, z1, L.ROLE_METAL, V_TRIM)
    if transom:
        tz = z0 + (z1 - z0) * 0.68
        g.box(xf0, xf1, y0, y1, tz - 0.032, tz + 0.032, L.ROLE_METAL, V_TRIM)
    # 外框（贴在墙外皮，出挑 0.06）
    for (a0, a1, b0, b1) in ((y0, y1, z1 - 0.07, z1), (y0, y1, z0, z0 + 0.07),
                             (y0, y0 + 0.07, z0, z1), (y1 - 0.07, y1, z0, z1)):
        g.box(F - 0.02, F + 0.06, a0, a1, b0, b1, L.ROLE_METAL, V_TRIM)
    # 窗台（两级 + 上表面最亮）
    g.box(F - 0.02, F + 0.20, y0 - 0.10, y1 + 0.10, z0 - 0.14, z0 - 0.02,
          L.ROLE_METAL, V_TRIM2)
    g.box(F + 0.14, F + 0.20, y0 - 0.10, y1 + 0.10, z0 - 0.14, z0 - 0.02,
          L.ROLE_METAL, N_D7)
    g.box(F + 0.14, F + 0.20, y0 - 0.10, y1 + 0.10, z0 - 0.21, z0 - 0.14,
          L.ROLE_MATTE, V_SEAM)
    # 过梁（出挑 0.10，下面压一道阴影）
    g.box(F - 0.02, F + 0.10, y0 - 0.07, y1 + 0.07, z1, z1 + 0.13, L.ROLE_METAL, V_TRIM)
    g.box(F + 0.08, F + 0.10, y0 - 0.07, y1 + 0.07, z1 - 0.06, z1, L.ROLE_MATTE, V_SEAM)
    # 窗下降雨痕（三道，比墙暗一级）
    for k in (0.22, 0.52, 0.80):
        ww = y0 + (y1 - y0) * k
        g.box(F, F + 0.005, ww - 0.035, ww + 0.035, z0 - 0.62, z0 - 0.21,
              L.ROLE_MATTE, N_D0)


def c_pharmacy_block_detail(g):
    """低矮药店商业楼 10×8×7.5m（正立面 +X），编号02 细颗粒版。

    外壳 = 0.40 厚表皮（带洞）+ 内退暗核，窗都是真洞；一层四开间
    （橱窗 / 窄展窗 / 卷帘 / 员工门）按 1:1.2:1.6:0.85 排，避免"一排等宽盒子"。
    立面竖向节奏：基座 0.52 → 橱窗 2.74 → 雨棚 3.02 → 腰线 3.34 → 招牌 3.36–5.76
    → 二层窗 5.30–6.80 → 三级檐口 7.34 → 女儿墙 8.20。
    """
    MATTE, METAL, GLOSS, EMIT = L.ROLE_MATTE, L.ROLE_METAL, L.ROLE_GLOSS, L.ROLE_EMIT
    F = PH_X1
    S = PH_SKIN

    # ============================================ 0. 外壳：暗核 + 四面带洞表皮
    # 暗核（内退 0.40）：所有洞的"背板"，也给侧壁一个深色对比
    g.box(PH_X0 + S, F - S, PH_Y0 + S, PH_Y1 - S, 0.0, PH_TOP, MATTE, N_INK)
    # 一层商铺内腔：向西再掏 0.95m，让橱窗有真实进深（货架能退进去）
    yS0, yS1 = PH_BAY["shop"]
    g.box(F - 1.35, F - S, yS0 - 0.10, yS1 + 0.10, 0.24, 2.90, MATTE, N_INK)

    # 正立面表皮：分三段（基座 / 一层 / 二层），各自带洞
    shop_h = (yS0, yS1, PH_BASE, 2.74)
    nar_h = (PH_BAY["narrow"][0], PH_BAY["narrow"][1], PH_BASE, 2.74)
    shut_h = (PH_BAY["shut"][0], PH_BAY["shut"][1], 0.0, 2.62)
    door_h = (PH_BAY["door"][0], PH_BAY["door"][1], 0.0, 2.18)
    # 基座段（0..0.52）：卷帘与员工门落地，必须开口
    _wall_holes(g, F - S, F, PH_Y0, PH_Y1, 0.0, PH_BASE,
                [(shut_h[0], shut_h[1], 0.0, PH_BASE), (door_h[0], door_h[1], 0.0, PH_BASE)],
                MATTE, N_D2)
    # 一层墙段（0.52..3.05）
    _wall_holes(g, F - S, F, PH_Y0, PH_Y1, PH_BASE, PH_BELT0,
                [shop_h, nar_h, (shut_h[0], shut_h[1], PH_BASE, shut_h[3]),
                 (door_h[0], door_h[1], PH_BASE, door_h[3])],
                MATTE, N_D1)
    # 二层墙段（3.34..6.86）：两樘窗
    win2 = []
    for (cy, _lit) in PH_WIN2:
        win2.append((cy - 0.78, cy + 0.78, PH_F2Z0, PH_F2Z1))
    # 墙体压在 17–26 两档，**只让凸出构件亮**（43/56/70/86）：靠大反差出层次。
    # 上一版把墙抬到 35 又加洗墙光，整面刷成浅蓝，反而没有明暗。
    _wall_holes(g, F - S, F, PH_Y0, PH_Y1, PH_BELT1, PH_CORNICE[0], win2, MATTE, N_D2)

    # 侧立面（±Y）：0.40 厚，带 2 樘窗
    for (yy, sgn) in ((PH_Y1 - S, 1), (PH_Y0, -1)):
        g.box(PH_X0, PH_X0 + S, yy, yy + S, 0.0, PH_TOP, MATTE, N_D1)  # 转角柱基
    _wall_holes_y(g, PH_Y1 - S, PH_Y1, PH_X0 + S, F - S, 0.0, PH_TOP,
                  [(-2.10, -0.90, 5.30, 6.60), (1.90, 3.10, 5.30, 6.60),
                   (-2.10, -0.90, 1.10, 2.50)], MATTE, N_D1)
    _wall_holes_y(g, PH_Y0, PH_Y0 + S, PH_X0 + S, F - S, 0.0, PH_TOP,
                  [(0.40, 1.70, 5.30, 6.60), (-1.60, -0.40, 1.10, 2.50)], MATTE, N_D1)
    # 背立面
    _wall_holes(g, PH_X0, PH_X0 + S, PH_Y0 + S, PH_Y1 - S, 0.0, PH_TOP,
                [], MATTE, N_D1)
    # 屋面顶板（外壳封顶）
    g.box(PH_X0, F, PH_Y0, PH_Y1, PH_TOP, PH_TOP + 0.08, MATTE, N_D2)

    # ============================================ 1. 基座（石砌 + 深度分缝 + 压顶）
    g.box(F - 0.02, F + 0.09, PH_Y0 - 0.09, PH_Y1 + 0.09, 0.0, PH_BASE, MATTE, N_D3)
    yy = PH_Y0
    while yy < PH_Y1 - 0.02:
        g.box(F + 0.07, F + 0.115, yy, yy + SEAM, 0.05, PH_BASE - 0.05, MATTE, V_SEAM)
        # 错缝：偶数块中间再切一刀
        g.box(F + 0.07, F + 0.115, yy + 0.46, yy + 0.52, 0.05, PH_BASE - 0.05,
              MATTE, V_SEAM)
        yy += 0.94
    # 压顶（两级，上表面最亮）
    g.box(F - 0.06, F + 0.17, PH_Y0 - 0.12, PH_Y1 + 0.12, PH_BASE - 0.09, PH_BASE, METAL, N_D6)
    g.box(F + 0.12, F + 0.17, PH_Y0 - 0.12, PH_Y1 + 0.12, PH_BASE - 0.09, PH_BASE, METAL, N_D7)
    g.box(F + 0.12, F + 0.17, PH_Y0 - 0.12, PH_Y1 + 0.12, PH_BASE - 0.16, PH_BASE - 0.09,
          MATTE, V_SEAM)

    # ============================================ 2. 一层壁柱（柱身凹槽 + 柱头柱础）
    for (ya, yb) in PH_PIERS1:
        g.box(F - 0.02, F + 0.19, ya, yb, PH_BASE, PH_BELT0, MATTE, N_D3)
        # 柱身三道凹槽（竖向，读成"有棱的石柱"）
        span = yb - ya
        for k in (0.28, 0.50, 0.72):
            yc = ya + span * k
            g.box(F + 0.17, F + 0.225, yc - 0.032, yc + 0.032, PH_BASE + 0.30,
                  PH_BELT0 - 0.34, MATTE, V_SEAM)
        # 侧棱缝
        g.box(F + 0.17, F + 0.225, ya, ya + SEAM, PH_BASE, PH_BELT0, MATTE, V_SEAM)
        g.box(F + 0.17, F + 0.225, yb - SEAM, yb, PH_BASE, PH_BELT0, MATTE, V_SEAM)
        # 柱础 / 柱头（出挑 0.10）
        g.box(F - 0.02, F + 0.28, ya - 0.045, yb + 0.045, PH_BASE, PH_BASE + 0.14, METAL, N_D5)
        g.box(F - 0.02, F + 0.28, ya - 0.045, yb + 0.045,
              PH_BELT0 - 0.15, PH_BELT0, METAL, N_D5)
        g.box(F + 0.23, F + 0.28, ya - 0.045, yb + 0.045,
              PH_BELT0 - 0.15, PH_BELT0, METAL, N_D7)
        # 柱头下的托块
        g.box(F + 0.10, F + 0.24, ya + span * 0.5 - 0.07, ya + span * 0.5 + 0.07,
              PH_BELT0 - 0.30, PH_BELT0 - 0.15, METAL, N_D4)

    # ============================================ 3. 一层：橱窗（真进深 + 货架）
    # 洞内壁压光（洞口侧壁比墙亮一级，读得到厚度）
    for (a0, a1, b0, b1) in ((yS0, yS0 + 0.05, PH_BASE, 2.74), (yS1 - 0.05, yS1, PH_BASE, 2.74),
                             (yS0, yS1, 2.69, 2.74), (yS0, yS1, PH_BASE, PH_BASE + 0.05)):
        g.box(F - S, F - 0.02, a0, a1, b0, b1, MATTE, N_D3)
    # 店内：顶光 / 地台 / 后墙货架
    g.box(F - 1.30, F - 0.30, yS0 + 0.05, yS1 - 0.05, 2.62, 2.72, EMIT, E_COLD)   # 顶灯带
    g.box(F - 1.30, F - 0.28, yS0 + 0.04, yS1 - 0.04, PH_BASE, PH_BASE + 0.06,
          MATTE, N_D1)                                                          # 地台
    for zz in (0.86, 1.34, 1.82, 2.28):
        g.box(F - 1.22, F - 0.62, yS0 + 0.10, yS1 - 0.10, zz, zz + 0.05, METAL, N_D4)  # 隔板
        for k in range(7):
            yy2 = yS0 + 0.18 + k * (yS1 - yS0 - 0.36) / 6.0
            hh = 0.16 + 0.06 * ((k * 7 + int(zz * 10)) % 3)
            g.box(F - 1.16, F - 0.72, yy2 - 0.055, yy2 + 0.055, zz + 0.05, zz + 0.05 + hh,
                  MATTE, N_D5 if k % 2 else N_D2)                                # 货盒
    # 玻璃 + 竖梃（玻璃在洞内 0.26 处）
    g.box(F - 0.28, F - 0.24, yS0 + 0.04, yS1 - 0.04, PH_BASE + 0.06, 2.62, GLOSS, T_GLASS)
    for k in (1, 2, 3):
        yc = yS0 + (yS1 - yS0) * k / 4.0
        g.box(F - 0.30, F - 0.10, yc - 0.045, yc + 0.045, PH_BASE + 0.06, 2.66, METAL, V_TRIM)
    g.box(F - 0.30, F - 0.10, yS0, yS1, 2.36, 2.44, METAL, V_TRIM)   # 上亮子横档
    # 外框 + 内窗台
    for (a0, a1, b0, b1) in ((yS0, yS1, 2.66, 2.74), (yS0, yS1, PH_BASE, PH_BASE + 0.06),
                             (yS0, yS0 + 0.06, PH_BASE, 2.74), (yS1 - 0.06, yS1, PH_BASE, 2.74)):
        g.box(F - 0.02, F + 0.07, a0, a1, b0, b1, METAL, V_TRIM)
    g.box(F - 0.10, F + 0.16, yS0 - 0.06, yS1 + 0.06, PH_BASE + 0.06, PH_BASE + 0.13, METAL, N_D6)

    # ============================================ 4. 一层：窄展窗（0.72 宽，竖三格）
    n0, n1 = PH_BAY["narrow"]
    for (a0, a1, b0, b1) in ((n0, n0 + 0.05, PH_BASE, 2.74), (n1 - 0.05, n1, PH_BASE, 2.74),
                             (n0, n1, 2.69, 2.74), (n0, n1, PH_BASE, PH_BASE + 0.05)):
        g.box(F - S, F - 0.02, a0, a1, b0, b1, MATTE, N_D3)
    g.box(F - 0.28, F - 0.24, n0 + 0.05, n1 - 0.05, PH_BASE + 0.06, 2.60, EMIT, E_DIM)
    for zz in (1.12, 1.86):
        g.box(F - 0.30, F - 0.14, n0, n1, zz - 0.035, zz + 0.035, METAL, V_TRIM)
    g.box(F - 0.30, F - 0.14, (n0 + n1) / 2 - 0.03, (n0 + n1) / 2 + 0.03,
          PH_BASE + 0.06, 2.60, METAL, V_TRIM)
    for (a0, a1, b0, b1) in ((n0, n1, 2.60, 2.74), (n0, n1, PH_BASE, PH_BASE + 0.06),
                             (n0, n0 + 0.06, PH_BASE, 2.74), (n1 - 0.06, n1, PH_BASE, 2.74)):
        g.box(F - 0.02, F + 0.06, a0, a1, b0, b1, METAL, V_TRIM)

    # ============================================ 5. 一层：卷帘（帘片 + 卷轴箱 + 导轨）
    s0, s1 = PH_BAY["shut"]
    g.box(F - S, F - 0.06, s0, s1, 0.0, 2.62, MATTE, N_D0)
    zz = 0.10
    k = 0
    while zz < 2.30:
        g.box(F - 0.10, F + 0.01, s0 + 0.06, s1 - 0.06, zz, zz + 0.085,
              METAL, N_D5 if k % 2 else N_D3)
        zz += 0.105
        k += 1
    g.box(F - 0.10, F + 0.01, s1 - 0.62, s1 - 0.14, 0.42, 1.02, MATTE, N_D2)   # 检修口
    g.box(F + 0.01, F + 0.035, s1 - 0.10, s1 - 0.06, 0.20, 1.90, METAL, V_SEAM)
    for yy2 in (s0, s1):
        g.box(F - 0.06, F + 0.11, yy2 - 0.055, yy2 + 0.055, 0.0, 2.80, METAL, V_TRIM)
        g.box(F + 0.11, F + 0.16, yy2 - 0.055, yy2 + 0.055, 0.0, 2.80, MATTE, V_SEAM)
    # 卷轴箱（顶到门楣）
    g.box(F - 0.10, F + 0.20, s0 - 0.12, s1 + 0.12, 2.62, 2.92, METAL, N_D4)
    g.box(F + 0.16, F + 0.20, s0 - 0.12, s1 + 0.12, 2.66, 2.88, MATTE, V_SEAM)
    g.box(F - 0.10, F + 0.20, s0 - 0.12, s1 + 0.12, 2.92, 3.02, METAL, N_D6)
    # 门楣下的射灯（两只）
    for yy2 in (s0 + 0.34, s1 - 0.34):
        g.cyl_x(F + 0.14, F + 0.24, yy2, 2.90, 0.058, METAL, V_TRIM, seg=8)
        g.box(F + 0.22, F + 0.25, yy2 - 0.045, yy2 + 0.045, 2.865, 2.895, EMIT, E_WARM)

    # ============================================ 6. 一层：员工门（门套 + 玻璃 + 把手 + 台阶）
    d0, d1 = PH_BAY["door"]
    g.box(F - S, F - 0.10, d0, d1, 0.0, 2.18, MATTE, N_D1)
    g.box(F - 0.14, F - 0.05, d0 + 0.04, d1 - 0.04, 0.02, 2.14, METAL, N_D4)
    g.box(F - 0.09, F - 0.05, d0 + 0.12, d1 - 0.12, 0.86, 1.92, GLOSS, T_GLASS)
    g.box(F - 0.09, F - 0.06, d0 + 0.16, d1 - 0.16, 0.90, 1.60, EMIT, E_DIM)
    for (a0, a1, b0, b1) in ((d0, d1, 2.14, 2.18), (d0, d1, 0.0, 0.04),
                             (d0, d0 + 0.04, 0.0, 2.18), (d1 - 0.04, d1, 0.0, 2.18)):
        g.box(F - 0.05, F + 0.07, a0, a1, b0, b1, METAL, V_TRIM)
    g.cyl_x(F + 0.02, F + 0.10, d1 - 0.16, 1.02, 0.026, METAL, N_D7, seg=6)
    g.box(F - 0.05, F + 0.13, d0 - 0.05, d1 + 0.05, 2.18, 2.30, METAL, N_D5)
    # 台阶 + 防滑条
    g.box(F + 0.02, F + 0.46, d0 - 0.10, d1 + 0.10, 0.0, 0.09, MATTE, N_D2)
    g.box(F + 0.38, F + 0.46, d0 - 0.10, d1 + 0.10, 0.06, 0.09, METAL, V_TRIM2)

    # ============================================ 7. 腰线（厚 0.29 + 三道线脚 + 檐下阴影）
    g.box(F - 0.06, F + 0.14, PH_Y0 - 0.06, PH_Y1 + 0.06, PH_BELT0, PH_BELT1, METAL, N_D4)
    g.box(F + 0.10, F + 0.14, PH_Y0 - 0.06, PH_Y1 + 0.06, PH_BELT0, PH_BELT1, METAL, N_D6)
    g.box(F - 0.04, F + 0.20, PH_Y0 - 0.02, PH_Y1 + 0.02, PH_BELT0 - 0.09, PH_BELT0, METAL, N_D5)
    g.box(F + 0.16, F + 0.20, PH_Y0 - 0.02, PH_Y1 + 0.02, PH_BELT0 - 0.09, PH_BELT0, METAL, N_D7)
    g.box(F + 0.16, F + 0.20, PH_Y0 - 0.02, PH_Y1 + 0.02, PH_BELT0 - 0.16, PH_BELT0 - 0.09,
          MATTE, V_SEAM)

    # ============================================ 8. 二层窗（2 樘，双扇 + 上亮子）
    for (cy, lit) in PH_WIN2:
        _win_panel(g, cy - 0.78, cy + 0.78, PH_F2Z0, PH_F2Z1, lit, mullions=2, transom=True)

    # ============================================ 9. 藥 招牌（扁平灯箱，2.40×2.40）
    Y0, Y1 = -3.54, -1.14
    Z0, Z1 = PH_BELT1 + 0.02, PH_BELT1 + 2.42
    # 背板 + 四侧板（构成 0.34 厚灯箱腔，腔口朝 +X）
    g.box(F + 0.02, F + 0.08, Y0, Y1, Z0, Z1, METAL, N_D1)
    for (a0, a1, b0, b1) in ((Y0, Y1, Z1 - 0.08, Z1), (Y0, Y1, Z0, Z0 + 0.08),
                             (Y0, Y0 + 0.08, Z0, Z1), (Y1 - 0.08, Y1, Z0, Z1)):
        g.box(F + 0.02, F + 0.34, a0, a1, b0, b1, METAL, N_D4)
    # 面板：暗蓝紫（与墙面同族，不跳色）。上一版是青绿 #4A6D71，
    # 放在这条街的蓝紫暗部里是明显的杂色；亮的只留字本身。
    g.box(F + 0.26, F + 0.30, Y0 + 0.10, Y1 - 0.10, Z0 + 0.10, Z1 - 0.10, GLOSS, N_D3)
    g.box(F + 0.255, F + 0.262, Y0 + 0.14, Y1 - 0.14, Z0 + 0.14, Z1 - 0.14, MATTE, N_INK)
    # 面板四周一圈冷青描边，给暗底一个边界（面积 <2%，不构成跳色）
    for (a0, a1, b0, b1) in ((Y0 + 0.10, Y1 - 0.10, Z0 + 0.10, Z0 + 0.135),
                             (Y0 + 0.10, Y1 - 0.10, Z1 - 0.135, Z1 - 0.10),
                             (Y0 + 0.10, Y0 + 0.135, Z0 + 0.10, Z1 - 0.10),
                             (Y1 - 0.135, Y1 - 0.10, Z0 + 0.10, Z1 - 0.10)):
        g.box(F + 0.258, F + 0.268, a0, a1, b0, b1, EMIT, E_ICE)
    # 藥 字（方形 1.95，居中偏上，下面留小字带）
    gy = (Y0 + Y1) / 2.0
    # 字 1.52 见方、居中（上下各留 0.35 边距）。
    # 三条硬约束：① 字号必须给足边距，否则笔画缝被自发光溢出糊平；② 笔画色降到
    # E_ICE(#5D6E82) 而不是纯冷白，暗底 + 中亮笔画才有硬边；③ 下方不放"小字带"，
    # 那四块短横在 20m 外读成噪点，反而破坏字形。
    _glyph(g, "x", F + 0.262, F + 0.310, gy, Z0 + 0.42, 1.52, 1.52, EMIT, E_ICE)
    # 外框（出挑最远，压住面板边缘）
    for (a0, a1, b0, b1) in ((Y0, Y1, Z1 - 0.12, Z1), (Y0, Y1, Z0, Z0 + 0.12),
                             (Y0, Y0 + 0.12, Z0, Z1), (Y1 - 0.12, Y1, Z0, Z1)):
        g.box(F + 0.30, F + 0.40, a0, a1, b0, b1, METAL, N_D6)
    # 四角螺栓
    for by in (Y0 + 0.19, Y1 - 0.19):
        for bz in (Z0 + 0.20, Z1 - 0.20):
            g.cyl_x(F + 0.40, F + 0.435, by, bz, 0.036, METAL, N_D7, seg=6)
    # 顶部遮雨檐（出挑 0.22，下面压阴影）
    g.box(F + 0.02, F + 0.62, Y0 - 0.07, Y1 + 0.07, Z1, Z1 + 0.09, METAL, N_D6)
    g.box(F + 0.56, F + 0.62, Y0 - 0.07, Y1 + 0.07, Z1 - 0.09, Z1, MATTE, V_SEAM)
    # 挂装：两根水平臂 + 斜撑 + 吊杆
    for by in (Y0 + 0.34, Y1 - 0.34):
        g.beam((F - 0.02, by, Z0 + 0.52), (F + 0.08, by, Z0 + 0.52), 0.075, 0.075, METAL, V_TRIM)
        g.beam((F - 0.02, by, Z0 + 0.12), (F + 0.10, by, Z0 + 0.50), 0.055, 0.055, METAL, V_TRIM)
        g.cyl_y(by - 0.030, by + 0.030, F + 0.04, Z0 - 0.05, 0.030, METAL, V_SEAM, seg=5)

    # ============================================ 10. 雨棚（腰线下，出挑 0.86）
    # 出挑从 0.86 收到 0.58：0.86 时从 20m 外 18° 斜俯视，雨棚把整排橱窗盖死
    # （实测街口机位一层全黑）。0.58 既保留遮雨语义，又留出看橱窗的角度。
    A0, A1 = -3.66, -1.06
    AZ = PH_BELT0 - 0.10
    g.prism([(F - 0.02, A0), (F + 0.58, A0), (F + 0.58, A1), (F - 0.02, A1)],
            AZ, AZ + 0.08, MATTE, N_D3)
    g.box(F + 0.50, F + 0.60, A0, A1, AZ - 0.20, AZ + 0.08, MATTE, N_D2)
    g.box(F + 0.56, F + 0.60, A0, A1, AZ - 0.20, AZ + 0.08, MATTE, V_SEAM)
    # 底面加劲肋（5 道，斜俯视能看出"棚下是有骨架的"）
    for k in range(5):
        yy2 = A0 + 0.16 + k * (A1 - A0 - 0.32) / 4.0
        g.beam((F + 0.02, yy2, AZ + 0.05), (F + 0.58, yy2, AZ + 0.01), 0.05, 0.05,
               METAL, N_D5)
        g.beam((F + 0.04, yy2, AZ + 0.01), (F + 0.34, yy2, AZ + 0.34), 0.045, 0.045,
               METAL, N_D5)
    # 棚下灯带
    g.box(F + 0.46, F + 0.56, A0 + 0.16, A1 - 0.16, AZ - 0.19, AZ - 0.13, EMIT, E_WARM)

    # ============================================ 11. 二层广告位（北端 0.72 宽小灯箱）
    g.box(F + 0.02, F + 0.22, 3.32, 3.98, 4.55, 6.15, METAL, N_D4)
    g.box(F + 0.20, F + 0.235, 3.38, 3.92, 4.61, 6.09, GLOSS, T_GLASS)
    for k in range(5):
        g.box(F + 0.235, F + 0.255, 3.42, 3.88, 4.72 + k * 0.26, 4.80 + k * 0.26,
              EMIT, E_ICE if k % 2 else E_DIM)

    # ============================================ 12. 空调外机 × 2（挂窗下）+ 冷凝水管
    for cy in (-0.20 + 0.22, 2.11):
        ax0, ax1 = F, F + 0.66
        ay0, ay1 = cy - 0.52, cy + 0.52
        az0 = 4.28
        # 支架（三角撑）
        for yy2 in (ay0 + 0.14, ay1 - 0.14):
            g.beam((F + 0.02, yy2, az0 - 0.02), (ax1 - 0.08, yy2, az0 + 0.10), 0.06, 0.06,
                   METAL, V_TRIM)
            g.beam((F + 0.02, yy2, az0 - 0.52), (ax1 - 0.10, yy2, az0), 0.05, 0.05,
                   METAL, V_SEAM)
        g.box(ax0 + 0.05, ax1, ay0, ay1, az0, az0 + 0.72, METAL, N_D3)
        # 正面格栅
        zz = az0 + 0.08
        while zz < az0 + 0.66:
            g.box(ax1, ax1 + 0.045, ay0 + 0.09, ay1 - 0.09, zz, zz + 0.035, METAL, N_D5)
            zz += 0.07
        g.box(ax1 + 0.045, ax1 + 0.075, ay0 + 0.09, ay1 - 0.09, az0 + 0.08, az0 + 0.66,
              MATTE, V_SEAM)
        # 侧面散热片 + 铭牌 + 运行灯
        for k in range(6):
            g.box(ax0 + 0.10 + k * 0.085, ax0 + 0.14 + k * 0.085, ay1, ay1 + 0.03,
                  az0 + 0.12, az0 + 0.60, MATTE, N_D1)
        g.box(ax1 + 0.02, ax1 + 0.05, ay0 + 0.12, ay0 + 0.40, az0 + 0.50, az0 + 0.60,
              MATTE, N_D2)
        g.box(ax1 + 0.05, ax1 + 0.065, ay0 + 0.14, ay0 + 0.20, az0 + 0.53, az0 + 0.57,
              EMIT, E_WARM)
        # 冷凝水管（落到底）
        g.cyl(F + 0.20, ay1 - 0.10, 0.10, az0 - 0.02, 0.026, METAL, N_D6, seg=6)

    # ============================================ 13. 立管（2 根）+ 横向桥架 + 落水斗
    for yy2 in (PH_Y0 + 0.20, PH_Y1 - 0.20):
        _vpipe(g, F + 0.26, yy2, 0.085, PH_PARA - 0.18, 0.095, METAL, N_D5,
               clamps=6, cell_clamp=N_D7)
        g.beam((F + 0.26, yy2, 0.10), (F + 0.52, yy2, 0.02), 0.12, 0.12, METAL, N_D5)
        g.box(F + 0.20, F + 0.34, yy2 - 0.09, yy2 + 0.09, 0.02, 0.16, METAL, N_D6)
    # 横向桥架（腰线上沿走一圈）—— 必须让开藥字招牌的 y 跨度(-3.54..-1.14)，
    # 上一版整条横穿招牌下三分之一，把木字底和横画全挡了（正交实测）。
    for (a0, a1) in ((PH_Y0 + 0.10, -3.60), (-1.08, PH_Y1 - 0.10)):
        g.box(F + 0.14, F + 0.32, a0, a1, 4.02, 4.16, METAL, N_D4)
        g.box(F + 0.30, F + 0.34, a0, a1, 3.99, 4.19, MATTE, V_SEAM)
    for yy2 in (-3.86, 0.4, 1.2, 2.0, 2.8, 3.6):
        g.box(F + 0.32, F + 0.36, yy2, yy2 + 0.06, 3.98, 4.20, METAL, N_D6)
    # 桥架上的电缆束（细圆柱 + 下垂段）
    for k in range(3):
        zz = 4.06 + k * 0.035
        g.cyl_x(F + 0.16, F + 0.30, PH_Y0 + 0.14, zz, 0.018, METAL, N_D1, seg=5)
    # 落水斗（腰线上一个，女儿墙下一个）
    for zz in (PH_BELT1 + 0.30, PH_PARA - 0.42):
        g.box(F + 0.22, F + 0.42, PH_Y0 + 0.12, PH_Y0 + 0.34, zz, zz + 0.34, METAL, N_D5)
        g.box(F + 0.40, F + 0.44, PH_Y0 + 0.16, PH_Y0 + 0.30, zz + 0.04, zz + 0.30,
              MATTE, V_SEAM)

    # ============================================ 14. 檐口（三级叠涩 + 托块 + 檐下阴影）
    g.box(F - 0.10, F + 0.22, PH_Y0 - 0.10, PH_Y1 + 0.10,
          PH_CORNICE[0], PH_CORNICE[1], METAL, N_D5)
    g.box(F + 0.16, F + 0.22, PH_Y0 - 0.10, PH_Y1 + 0.10,
          PH_CORNICE[0], PH_CORNICE[1], METAL, N_D7)
    g.box(PH_X0 - 0.22, F + 0.36, PH_Y0 - 0.22, PH_Y1 + 0.22,
          PH_CORNICE[1], PH_CORNICE[2], METAL, N_D6)
    g.box(F + 0.30, F + 0.36, PH_Y0 - 0.22, PH_Y1 + 0.22,
          PH_CORNICE[1], PH_CORNICE[2], METAL, N_D7)
    g.box(F - 0.02, F + 0.04, PH_Y0, PH_Y1, PH_CORNICE[0] - 0.24, PH_CORNICE[0],
          MATTE, N_INK)
    yy = PH_Y0 + 0.18
    while yy < PH_Y1 - 0.28:
        g.box(F + 0.04, F + 0.21, yy, yy + 0.15, PH_CORNICE[0] - 0.28, PH_CORNICE[0],
              METAL, N_D4)
        g.box(F + 0.17, F + 0.21, yy, yy + 0.15, PH_CORNICE[0] - 0.28, PH_CORNICE[0],
              METAL, N_D6)
        yy += 1.12

    # ============================================ 15. 女儿墙（4 面 + 压顶 + 分仓缝）
    for (x0, x1, y0, y1) in ((F - 0.34, F, PH_Y0, PH_Y1), (PH_X0, PH_X0 + 0.34, PH_Y0, PH_Y1),
                             (PH_X0, F, PH_Y0, PH_Y0 + 0.34), (PH_X0, F, PH_Y1 - 0.34, PH_Y1)):
        g.box(x0, x1, y0, y1, PH_CORNICE[2], PH_PARA, MATTE, N_D2)
    g.box(F - 0.42, F + 0.06, PH_Y0 - 0.08, PH_Y1 + 0.08, PH_PARA, PH_PARA + 0.10, METAL, N_D6)
    g.box(F - 0.02, F + 0.06, PH_Y0 - 0.08, PH_Y1 + 0.08, PH_PARA, PH_PARA + 0.10, METAL, N_D7)
    g.box(PH_X0 - 0.08, PH_X0 + 0.42, PH_Y0 - 0.08, PH_Y1 + 0.08, PH_PARA, PH_PARA + 0.10,
          METAL, N_D6)
    g.box(PH_X0 - 0.08, F + 0.06, PH_Y0 - 0.08, PH_Y0 + 0.42, PH_PARA, PH_PARA + 0.10,
          METAL, N_D6)
    g.box(PH_X0 - 0.08, F + 0.06, PH_Y1 - 0.42, PH_Y1 + 0.08, PH_PARA, PH_PARA + 0.10,
          METAL, N_D6)
    yy = PH_Y0 + 1.45
    while yy < PH_Y1 - 0.2:
        g.box(F + 0.01, F + 0.07, yy, yy + SEAM, PH_CORNICE[2], PH_PARA, MATTE, V_SEAM)
        yy += 1.45
    # 女儿墙顶部避雷带
    g.box(F - 0.36, F - 0.31, PH_Y0 + 0.30, PH_Y1 - 0.30, PH_PARA + 0.10, PH_PARA + 0.16,
          METAL, N_D7)

    # ============================================ 16. 屋面（分区缝 + 上翻泛水）
    g.box(PH_X0 + 0.30, F - 0.34, PH_Y0 + 0.30, PH_Y1 - 0.30, PH_TOP, PH_TOP + 0.06,
          MATTE, N_D3)
    g.box(F - 0.42, F - 0.34, PH_Y0 + 0.30, PH_Y1 - 0.30, PH_TOP + 0.06, PH_TOP + 0.24,
          METAL, N_D5)
    x = PH_X0 + 2.6
    while x < F - 0.6:
        g.box(x, x + 0.05, PH_Y0 + 0.30, PH_Y1 - 0.30, PH_TOP + 0.06, PH_TOP + 0.09,
              MATTE, V_SEAM)
        x += 2.5
    yy = PH_Y0 + 1.6
    while yy < PH_Y1 - 0.4:
        g.box(PH_X0 + 0.30, F - 0.40, yy, yy + 0.05, PH_TOP + 0.06, PH_TOP + 0.09,
              MATTE, V_SEAM)
        yy += 1.7

    # ============================================ 17. 屋顶水箱（支腿 + 筒身 + 箍 + 爬梯 + 进出水管）
    TX, TY, TR = -1.55, 1.55, 1.02
    TZ0 = PH_TOP + 0.06
    TZ1 = TZ0 + 1.60
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        g.box(TX + sx * 0.64 - 0.065, TX + sx * 0.64 + 0.065,
              TY + sy * 0.64 - 0.065, TY + sy * 0.64 + 0.065, TZ0, TZ0 + 0.62, METAL, N_D5)
        g.box(TX + sx * 0.64 - 0.10, TX + sx * 0.64 + 0.10,
              TY + sy * 0.64 - 0.10, TY + sy * 0.64 + 0.10, TZ0, TZ0 + 0.06, METAL, N_D6)
    g.cyl(TX, TY, TZ0 + 0.60, TZ1, TR, METAL, N_D3, seg=14)
    for zz in (TZ0 + 0.78, TZ0 + 1.08, TZ1 - 0.14):
        g.cyl(TX, TY, zz, zz + 0.07, TR + 0.045, METAL, N_D6, seg=14)
    g.cyl(TX, TY, TZ1, TZ1 + 0.18, TR * 0.98, METAL, N_D6, seg=14, r2=TR * 0.48)
    g.cyl(TX + 0.28, TY, TZ1 + 0.18, TZ1 + 0.34, 0.22, METAL, N_D5, seg=8)
    # 爬梯
    for sx in (-0.19, 0.19):
        g.cyl(TX - TR - 0.14 + sx, TY - 0.34, TZ0, TZ1 + 0.24, 0.030, METAL, N_D6, seg=5)
    for k in range(8):
        zz = TZ0 + 0.08 + k * 0.235
        g.box(TX - TR - 0.20, TX - TR - 0.02, TY - 0.375, TY - 0.305, zz, zz + 0.032,
              METAL, N_D7)
    g.cyl(TX + TR + 0.10, TY + 0.32, TZ0, TZ1 - 0.28, 0.048, METAL, N_D1, seg=6)
    g.cyl(TX + TR + 0.10, TY + 0.32, TZ1 - 0.28, TZ1 - 0.24, 0.062, METAL, N_D6, seg=6)

    # ============================================ 18. 屋顶排风机 × 2
    for (fx, fy) in ((2.50, -2.02), (2.50, 1.10)):
        g.box(fx - 0.76, fx + 0.76, fy - 0.64, fy + 0.64, PH_TOP + 0.06, PH_TOP + 0.70,
              METAL, N_D3)
        g.box(fx - 0.76, fx + 0.76, fy - 0.64, fy + 0.64, PH_TOP + 0.62, PH_TOP + 0.70,
              METAL, N_D5)
        g.cyl(fx, fy, PH_TOP + 0.70, PH_TOP + 0.80, 0.44, METAL, N_D6, seg=11)
        g.cyl(fx, fy, PH_TOP + 0.80, PH_TOP + 0.85, 0.34, EMIT, E_DIM, seg=11)
        # 百叶
        zz = PH_TOP + 0.14
        while zz < PH_TOP + 0.56:
            g.box(fx - 0.70, fx + 0.70, fy + 0.64, fy + 0.685, zz, zz + 0.032, METAL, N_D1)
            zz += 0.065
        for sx in (-1, 1):
            g.box(fx + sx * 0.62 - 0.055, fx + sx * 0.62 + 0.055,
                  fy - 0.52, fy - 0.42, PH_TOP + 0.06, PH_TOP + 0.24, METAL, N_D6)

    # ============================================ 19. 屋顶楼梯间（门 + 门灯 + 出屋面管）
    SX0, SX1 = PH_X0 + 0.36, PH_X0 + 2.66
    SY0, SY1 = PH_Y0 + 0.36, PH_Y0 + 2.26
    SZ1 = PH_TOP + 1.52
    g.box(SX0, SX1, SY0, SY1, PH_TOP + 0.06, SZ1, MATTE, N_D1)
    g.box(SX0 - 0.08, SX1 + 0.08, SY0 - 0.08, SY1 + 0.08, SZ1, SZ1 + 0.09, METAL, N_D6)
    g.box(SX1, SX1 + 0.05, SY0 + 0.52, SY1 - 0.52, PH_TOP + 0.06, PH_TOP + 0.98, METAL, N_D4)
    for (a0, a1, b0, b1) in ((SY0 + 0.50, SY1 - 0.50, PH_TOP + 0.98, PH_TOP + 1.03),
                             (SY0 + 0.50, SY1 - 0.50, PH_TOP + 0.06, PH_TOP + 0.11),
                             (SY0 + 0.50, SY0 + 0.55, PH_TOP + 0.06, PH_TOP + 1.03),
                             (SY1 - 0.55, SY1 - 0.50, PH_TOP + 0.06, PH_TOP + 1.03)):
        g.box(SX1 + 0.02, SX1 + 0.07, a0, a1, b0, b1, METAL, N_D6)
    g.cyl_x(SX1 + 0.05, SX1 + 0.11, SY1 - 0.60, PH_TOP + 0.58, 0.028, METAL, N_D7, seg=6)
    g.box(SX1 + 0.04, SX1 + 0.13, SY0 + 0.76, SY1 - 0.76, PH_TOP + 1.10, PH_TOP + 1.17,
          EMIT, E_WARM)
    for k in range(3):
        g.box(SX1 + 0.02, SX1 + 0.05, SY0 + 0.10, SY1 - 0.10,
              PH_TOP + 0.20 + k * 0.28, PH_TOP + 0.22 + k * 0.28, MATTE, V_SEAM)

    # ============================================ 20. 屋顶桥架 + 天线 + 电缆下垂
    g.box(PH_X0 + 0.44, F - 0.46, PH_Y1 - 0.66, PH_Y1 - 0.52, PH_TOP + 0.06, PH_TOP + 0.22,
          METAL, N_D4)
    for x in (-3.0, -0.2, 2.4):
        g.box(x, x + 0.07, PH_Y1 - 0.69, PH_Y1 - 0.49, PH_TOP + 0.06, PH_TOP + 0.29,
              METAL, N_D6)
    g.cyl(3.05, -3.26, PH_TOP + 0.06, PH_TOP + 2.55, 0.048, METAL, N_D6, seg=6)
    for zz in (PH_TOP + 1.24, PH_TOP + 1.80, PH_TOP + 2.26):
        g.box(2.80, 3.30, -3.28, -3.24, zz, zz + 0.032, METAL, N_D7)
    g.cyl(3.05, -3.26, PH_TOP + 2.55, PH_TOP + 2.66, 0.085, EMIT, E_PINK, seg=6)
    # 从天线到楼梯间的悬垂电缆（3 段折线近似）
    for k in range(3):
        y0c = -3.24 + k * 0.06
        g.beam((3.05, y0c, PH_TOP + 2.30), (1.60, y0c, PH_TOP + 1.70), 0.022, 0.022,
               METAL, N_D1)
        g.beam((1.60, y0c, PH_TOP + 1.70), (0.30, y0c, PH_TOP + 2.05), 0.022, 0.022,
               METAL, N_D1)

    # ============================================ 21. 街面：台阶 / 格栅 / 地垫 / 雨水口
    for (z0, z1, out) in ((0.0, 0.09, 0.52), (0.09, 0.18, 0.32)):
        g.box(F + 0.16, F + 0.16 + out, yS0 - 0.14, yS1 + 0.14, z0, z1, MATTE, N_D3)
    g.box(F + 0.18, F + 0.68, yS0 - 0.08, yS1 + 0.08, 0.18, 0.21, METAL, N_D6)
    for k in range(9):
        yy2 = yS0 + 0.04 + k * 0.28
        g.box(F + 0.20, F + 0.64, yy2, yy2 + 0.06, 0.21, 0.235, MATTE, N_D1)
    g.box(F + 0.60, F + 0.86, yS0 + 0.10, yS1 - 0.10, 0.18, 0.215, MATTE, V_SEAM)
    # 地垫（细横条）
    for k in range(12):
        g.box(F + 0.62, F + 0.84, yS0 + 0.16 + k * 0.10, yS0 + 0.22 + k * 0.10,
              0.215, 0.235, METAL, N_D4)
    # 排水格栅 + 雨水口
    g.box(F + 0.90, F + 1.20, yS1 + 0.24, yS1 + 0.86, 0.0, 0.055, METAL, N_D4)
    for k in range(6):
        g.box(F + 0.94, F + 1.16, yS1 + 0.28 + k * 0.10, yS1 + 0.33 + k * 0.10,
              0.04, 0.065, MATTE, N_INK)

    # ============================================ 22. 实墙段（y 3.30..4.00）：配电箱 / 表箱 / 护角
    g.box(F + 0.02, F + 0.20, 3.34, 3.94, 1.06, 2.06, METAL, N_D3)
    g.box(F + 0.18, F + 0.205, 3.38, 3.90, 1.10, 2.02, METAL, N_D5)
    g.box(F + 0.20, F + 0.225, 3.40, 3.60, 1.14, 1.98, MATTE, V_SEAM)
    g.box(F + 0.20, F + 0.228, 3.66, 3.74, 1.70, 1.76, EMIT, E_WARM)   # 带电指示灯
    # 表箱（小，两只并排）
    for k in range(2):
        g.box(F + 0.02, F + 0.13, 3.40 + k * 0.26, 3.62 + k * 0.26, 0.74, 1.02, METAL, N_D4)
        g.box(F + 0.125, F + 0.14, 3.44 + k * 0.26, 3.58 + k * 0.26, 0.80, 0.96, GLOSS, T_GLASS)
    # 明装线管（从表箱上到腰线）
    g.cyl(F + 0.10, 3.52, 1.02, 3.05, 0.024, METAL, N_D5, seg=6)
    g.cyl(F + 0.10, 3.78, 1.02, 3.05, 0.020, METAL, N_D5, seg=6)
    for zz in (1.30, 1.90, 2.55):
        g.box(F + 0.07, F + 0.13, 3.48, 3.82, zz, zz + 0.055, METAL, N_D6)
    # 墙角护角
    g.box(F + 0.02, F + 0.10, 3.92, 4.00, 0.0, 3.05, METAL, N_D4)
    for zz in (0.40, 1.20, 2.00, 2.80):
        g.box(F + 0.10, F + 0.13, 3.90, 4.00, zz, zz + 0.09, METAL, N_D6)

    # ============================================ 23. 侧立面（±Y）窗内衬 + 背立面小窗
    # +Y 立面（世界 y=-5 侧）三樘
    for (cx0, cx1, lit) in ((-2.10, -0.90, True), (1.90, 3.10, False), (-2.10, -0.90, None)):
        if lit is None:
            continue
        yy = PH_Y1 - 0.31 if lit else PH_Y1 - 0.31
        cell = E_COLD if lit else T_GLASS
        g.box(cx0 + 0.04, cx1 - 0.04, PH_Y1 - 0.31, PH_Y1 - 0.27, 5.34, 6.56,
              EMIT if lit else GLOSS, cell)
        g.box((cx0 + cx1) / 2 - 0.032, (cx0 + cx1) / 2 + 0.032, PH_Y1 - 0.34, PH_Y1 - 0.10,
              5.30, 6.60, METAL, V_TRIM)
        g.box(cx0, cx1, PH_Y1 - 0.34, PH_Y1 - 0.10, 6.08, 6.14, METAL, V_TRIM)
        for (a0, a1, b0, b1) in ((cx0, cx1, 6.53, 6.60), (cx0, cx1, 5.30, 5.37),
                                 (cx0, cx0 + 0.07, 5.30, 6.60), (cx1 - 0.07, cx1, 5.30, 6.60)):
            g.box(a0, a1, PH_Y1 - 0.04, PH_Y1 + 0.05, b0, b1, METAL, V_TRIM)
    # -Y 立面（世界 y=-13 侧）两樘
    for (cx0, cx1, lit) in ((0.40, 1.70, False), (-1.60, -0.40, True)):
        g.box(cx0 + 0.04, cx1 - 0.04, PH_Y0 + 0.27, PH_Y0 + 0.31, 5.34, 6.56,
              EMIT if lit else GLOSS, E_ICE if lit else T_GLASS)
        g.box((cx0 + cx1) / 2 - 0.032, (cx0 + cx1) / 2 + 0.032, PH_Y0 + 0.10, PH_Y0 + 0.34,
              5.30, 6.60, METAL, V_TRIM)
        g.box(cx0, cx1, PH_Y0 + 0.10, PH_Y0 + 0.34, 6.08, 6.14, METAL, V_TRIM)
        for (a0, a1, b0, b1) in ((cx0, cx1, 6.53, 6.60), (cx0, cx1, 5.30, 5.37),
                                 (cx0, cx0 + 0.07, 5.30, 6.60), (cx1 - 0.07, cx1, 5.30, 6.60)):
            g.box(a0, a1, PH_Y0 - 0.05, PH_Y0 + 0.04, b0, b1, METAL, V_TRIM)
    # 背立面三樘（只给一点点暗亮，远看不见也不浪费）
    for cx in (-2.30, 0.40, 2.60):
        g.box(cx - 0.55, cx + 0.55, PH_X0 + 0.26, PH_X0 + 0.30, 1.30, 2.50, GLOSS, T_GLASS)
        g.box(cx - 0.55, cx + 0.55, PH_X0 + 0.26, PH_X0 + 0.30, 1.90, 1.94, METAL, V_TRIM)


def _octagon(r, cx=0.0, cy=0.0, rot=0.0):
    return [(cx + r * math.cos(rot + math.pi * 2 * i / 8),
             cy + r * math.sin(rot + math.pi * 2 * i / 8)) for i in range(8)]


def _blob(g, cx, cy, cz, r, cell, rot=0.0):
    """一颗汽团 = 三段圆台（0.55r → r → 0.55r）叠成的近球体，外加一颗偏置小团。

    踩过的两个坑：
    ① 一摞等宽薄盘 → 斜俯视读成「石柱 / 一摞盘子」；
    ② 单段圆台（下宽上尖）→ 近景读成「白色尖锥水晶」。
    只有「下窄-中宽-上窄」的三段在任意角度都像一个团。
    纯几何近似：四角色材质里没有 alpha 可依赖（色盘 + Closest）。
    """
    ca, sa = math.cos(rot), math.sin(rot)
    parts = ((0.00, 0.00, 0.00, 0.62), (0.46, -0.22, 0.34, 0.40))
    for k, (dx, dy, dz, sc) in enumerate(parts):
        rr = r * sc
        if rr < 0.06:
            continue
        px, py = dx * ca - dy * sa, dx * sa + dy * ca
        cell_k = cell if k == 0 else L.C_BLACK
        g.cyl(cx + px, cy + py, cz + dz, cz + dz + rr * 0.55,
              rr * 0.55, L.ROLE_MATTE, cell_k, seg=9, r2=rr)
        g.cyl(cx + px, cy + py, cz + dz + rr * 0.55, cz + dz + rr * 1.15,
              rr, L.ROLE_MATTE, cell_k, seg=9, r2=rr * 0.55)


def c_steam_vent(g):
    """地面蒸汽排风口 + 上升汽柱（参考图左右两侧最抢眼的白色蒸汽）。"""
    # 铸铁格栅底座
    g.box(-0.9, 0.9, -0.9, 0.9, 0.0, 0.14, L.ROLE_METAL, L.C_PURPLE)
    for i in range(7):
        g.box(-0.74, 0.74, -0.62 + i * 0.21, -0.52 + i * 0.21, 0.14, 0.19, L.ROLE_METAL, L.C_BLACK)
    # 黄黑警示包边
    for sx in (-1, 1):
        for i in range(4):
            g.box(sx * 0.86, sx * 0.99, -0.86 + i * 0.48, -0.48 + i * 0.48, 0.0, 0.09,
                  L.ROLE_MATTE, L.C_AMBER2 if i % 2 else L.C_BLACK)
    # 汽柱：7 层，每层是一簇碎团；逐层放大并向 +X / +Y 漂移
    plume = (
        (0.10, 0.26, 0.00, 0.00, 0.00),
        (0.46, 0.32, 0.10, -0.06, 0.35),
        (0.84, 0.38, -0.10, 0.08, 0.70),
        (1.24, 0.46, 0.16, 0.16, 1.05),
        (1.66, 0.52, -0.18, 0.26, 1.40),
        (2.10, 0.46, 0.24, 0.36, 1.75),
        (2.52, 0.38, -0.26, 0.46, 2.10),
    )
    for k, (z, r, dx, dy, rot) in enumerate(plume):
        _blob(g, dx, dy, z, r, L.C_COAL if k % 2 else L.C_VAPOR_HIGH, rot)
    # 汽柱根部被顶光打亮的一小圈
    g.cyl(0.0, 0.0, 0.19, 0.24, 0.62, L.ROLE_EMIT, L.C_VAPOR_HIGH, seg=12)


def c_alley_shophouse(g):
    """窄巷小店面 4.3 × 9.0 × 13.0m：底层卷帘 + 灯箱，二层铁窗，屋顶水箱。"""
    # 主体（正面 +X = x=+2.0）
    g.box(-2.0, 2.0, -4.5, 4.5, 0.0, 13.0, L.ROLE_MATTE, L.C_NAVY2)
    g.box(-2.1, 2.1, -4.6, 4.6, 0.0, 0.36, L.ROLE_MATTE, L.C_GREY_COOL)
    for z in (3.1, 6.9, 10.7):
        g.box(-2.14, 2.14, -4.62, 4.62, z, z + 0.24, L.ROLE_METAL, L.C_INDIGO)
    # 底层橱窗（-Y 半侧）+ 卷帘（+Y 半侧）
    g.box(2.0, 2.1, -4.0, 0.2, 0.5, 2.75, L.ROLE_EMIT, L.C_TEAL)
    for i in range(4):
        g.box(2.1, 2.2, -3.9 + i * 1.05, -3.82 + i * 1.05, 0.5, 2.75, L.ROLE_METAL, L.C_PURPLE)
    g.box(2.0, 2.12, 0.6, 3.9, 0.0, 3.0, L.ROLE_METAL, L.C_PURPLE2)
    for i in range(9):
        g.box(2.12, 2.2, 0.7, 3.8, 0.24 + i * 0.3, 0.36 + i * 0.3, L.ROLE_GLOSS, L.C_PURPLE)
    # 雨棚
    g.prism([(2.1, -2.4), (3.5, -2.4), (3.5, 2.6), (2.1, 2.6)], 3.0, 3.16, L.ROLE_MATTE, L.C_CRIMSON)
    g.box(3.4, 3.52, -2.4, 2.6, 2.94, 3.02, L.ROLE_EMIT, L.C_CRIMSON)
    # 灯箱招牌（挑出街面）
    g.box(2.14, 2.34, -2.0, 1.0, 3.4, 5.4, L.ROLE_METAL, L.C_BLACK)
    g.box(2.34, 2.4, -1.85, 0.85, 3.55, 5.25, L.ROLE_EMIT, L.C_CRIMSON)
    for i in range(3):
        g.box(2.4, 2.44, -1.7, 0.7, 3.7 + i * 0.52, 3.9 + i * 0.52, L.ROLE_EMIT, L.C_AMBER)
    # 二层铁窗
    for k, z in enumerate((4.4, 8.2)):
        for i in range(3):
            cy = -3.4 + i * 2.7
            g.box(2.0, 2.08, cy - 0.75, cy + 0.75, z, z + 1.5, L.ROLE_MATTE, L.C_BLACK)
            g.box(2.04, 2.1, cy - 0.68, cy + 0.68, z + 0.08, z + 1.42,
                  L.ROLE_EMIT if (i + k) % 2 else L.ROLE_MATTE,
                  L.C_AMBER2 if (i + k) % 2 else L.C_INDIGO)
    # 女儿墙 + 屋顶水箱
    for (x0, x1, y0, y1) in ((-2.0, 2.0, 4.2, 4.5), (-2.0, 2.0, -4.5, -4.2),
                             (-2.0, -1.7, -4.5, 4.5), (1.7, 2.0, -4.5, 4.5)):
        g.box(x0, x1, y0, y1, 13.0, 13.6, L.ROLE_METAL, L.C_PURPLE)
    g.cyl(0.0, 2.4, 13.0, 15.4, 0.95, L.ROLE_METAL, L.C_PURPLE2, seg=12)
    g.cyl(0.0, 2.4, 15.4, 15.55, 1.0, L.ROLE_METAL, L.C_INDIGO, seg=12)
    g.cyl(0.0, 2.4, 15.55, 15.9, 0.12, L.ROLE_METAL, L.C_BLACK, seg=8)


def c_traffic_mast(g):
    """悬臂交通信号灯杆：6.4m 立杆 + 4.6m 横臂 + 三灯头 + 行人灯（横臂朝 +X）。"""
    g.cyl(0.0, 0.0, 0.0, 0.55, 0.3, L.ROLE_METAL, L.C_PURPLE, seg=12)
    for i in range(6):
        a = math.pi * 2 * i / 6
        g.box(math.cos(a) * 0.24 - 0.05, math.cos(a) * 0.24 + 0.05,
              math.sin(a) * 0.24 - 0.05, math.sin(a) * 0.24 + 0.05, 0.0, 0.2,
              L.ROLE_METAL, L.C_BLACK)
    g.cyl(0.0, 0.0, 0.55, 6.4, 0.12, L.ROLE_METAL, L.C_PURPLE2, seg=10)
    # 横臂 + 斜撑
    g.beam((0.0, 0.0, 6.05), (4.7, 0.0, 6.05), 0.17, 0.17, L.ROLE_METAL, L.C_PURPLE2)
    g.beam((0.0, 0.0, 4.6), (2.6, 0.0, 6.0), 0.1, 0.1, L.ROLE_METAL, L.C_INDIGO)
    # 三灯头（横臂下挂）
    for k, cx in enumerate((2.55, 3.5, 4.45)):
        g.box(cx - 0.17, cx + 0.17, -0.22, 0.22, 4.5, 5.98, L.ROLE_METAL, L.C_BLACK)
        g.box(cx - 0.13, cx + 0.13, -0.28, -0.2, 4.62, 5.1, L.ROLE_EMIT,
              (L.C_CRIMSON, L.C_AMBER, L.C_TEAL)[k])
        g.box(cx - 0.2, cx + 0.2, -0.2, 0.2, 5.98, 6.06, L.ROLE_METAL, L.C_PURPLE)
    # 行人灯 + 控制箱
    g.box(0.16, 0.62, -0.26, 0.26, 2.6, 3.5, L.ROLE_METAL, L.C_PURPLE)
    g.box(0.24, 0.54, -0.32, -0.24, 2.72, 3.38, L.ROLE_EMIT, L.C_CRIMSON)
    g.box(-0.5, -0.14, -0.3, 0.3, 1.5, 2.4, L.ROLE_METAL, L.C_PURPLE2)
    g.box(-0.47, -0.17, -0.36, -0.3, 1.7, 2.2, L.ROLE_EMIT, L.C_AMBER)
    # 灯杆警示环
    for z in (1.1, 1.35):
        g.cyl(0.0, 0.0, z, z + 0.16, 0.15, L.ROLE_EMIT, L.C_AMBER2, seg=10)


def c_vending_bank(g):
    """售货机 / 取货柜组：3 台并排，正面 +X，面板自发光。"""
    cells = (L.C_TEAL, L.C_CRIMSON, L.C_AMBER)
    for i in range(3):
        cy = -1.4 + i * 1.4
        g.box(-0.48, 0.46, cy - 0.64, cy + 0.64, 0.0, 2.1, L.ROLE_METAL, L.C_PURPLE2)
        g.box(0.46, 0.5, cy - 0.56, cy + 0.56, 0.32, 1.9, L.ROLE_EMIT, cells[i])
        # 货道横条
        for k in range(4):
            g.box(0.5, 0.53, cy - 0.5, cy + 0.5, 0.55 + k * 0.42, 0.62 + k * 0.42,
                  L.ROLE_MATTE, L.C_BLACK)
        # 取货口 / 投币面板
        g.box(0.46, 0.53, cy - 0.42, cy + 0.42, 0.04, 0.3, L.ROLE_METAL, L.C_BLACK)
        g.box(0.5, 0.55, cy + 0.2, cy + 0.5, 1.84, 2.0, L.ROLE_EMIT, L.C_GREY_MID)
        g.box(-0.48, 0.46, cy - 0.66, cy - 0.6, 2.02, 2.1, L.ROLE_METAL, L.C_INDIGO)
    # 顶部雨檐 + 支架
    g.box(-0.6, 0.66, -2.16, 2.16, 2.1, 2.2, L.ROLE_METAL, L.C_PURPLE)
    g.box(0.6, 0.7, -2.12, 2.12, 2.06, 2.12, L.ROLE_EMIT, L.C_CRIMSON)
    for i in range(3):
        cy = -1.4 + i * 1.4
        g.box(-0.56, 0.5, cy - 0.7, cy + 0.7, 0.0, 0.06, L.ROLE_MATTE, L.C_BLACK)


# ================================================================ 组件登记

REUSED_FROM = "art_source/environments/open_world/source/underground_street/v001"
FRONT_AXIS = {
    "neon_sign_hotel_vertical_01": "-Y",
    "neon_sign_pharmacy_kanji_02": "-Y",
    "neon_sign_bar_vertical_03": "-Y",
    "skybridge_sign_sector07_04": "-Y",
    "neon_blade_sign_cluster_05": "-Y",
    "hotel_arch_window_bay_02": "-Y",
    "hotel_shutter_shopfront_03": "-Y",
    "steam_vapor_vent_02": "+Z",
}
FIXED_ROT = {"retro_cyber_sedan_car_01": [0, 180]}

# v001 里 wet_asphalt_film_10x10_02 的实例数就是 0：它是 9.8×9.8 的贴地反光膜，
# 顶面 0.008m 落在车道面层 0..0.012m 之内会被完全盖住，抬到标线之上又会与双黄线抢面。
# 按「必要性判据：删掉该定义仍能高保真拼回」→ 本版不纳入计划，不做无用定义。
EXCLUDED = {"wet_asphalt_film_10x10_02", "neon_sign_pharmacy_kanji_02"}

# 细化覆盖：药店楼体本轮做到参考图的颗粒度（12 个盒子 → 300+ 零件）。
# 藥 字招牌按 02 号规范「房间装饰优先并入宿主结构组件」并入药店本体，
# 因此独立的 neon_sign_pharmacy_kanji_02 不再实例化（实例数 0 → 剔除定义），
# 避免同一位置两个灯箱叠在一起抢面。
DETAIL_OVERRIDE = {
    "pharmacy_shop_block_10x8_01": c_pharmacy_block_detail,
}

COMPONENTS: list[dict] = []
for _e in V1.COMPONENTS:
    if _e["slug"] in EXCLUDED:
        continue
    COMPONENTS.append(dict(
        slug=_e["slug"], name_zh=_e["name_zh"], family=_e["family"],
        category=_e["category"],
        builder=DETAIL_OVERRIDE.get(_e["slug"], _e["builder"]),
        note=_e.get("note", "") or "",
        reused_from=REUSED_FROM,
        detailed=_e["slug"] in DETAIL_OVERRIDE,
    ))

NEW = [
    dict(slug="steam_vapor_vent_02", name_zh="地面蒸汽排风口与上升汽柱_02",
         family="street_vapor", category="facility", builder=c_steam_vent,
         note="参考图左右两侧的白色蒸汽；格栅底座 + 7 段错位汽团，纯几何无半透明",
         reused_from=None),
    dict(slug="narrow_alley_shophouse_02", name_zh="窄巷小店面_4x9x13m_02",
         family="alley_shophouse", category="structural", builder=c_alley_shophouse,
         note="填补 v001 缺失的窄面宽小店面；卷帘/橱窗/挑出灯箱/屋顶水箱",
         reused_from=None),
    dict(slug="traffic_signal_mast_02", name_zh="悬臂交通信号灯杆_6.4m_02",
         family="traffic_mast", category="facility", builder=c_traffic_mast,
         note="横臂伸向街心的三灯头信号杆；v001 只有灯杆上的侧挂小灯",
         reused_from=None),
    dict(slug="vending_machine_bank_02", name_zh="售货机与取货柜组_02",
         family="vending_bank", category="facility", builder=c_vending_bank,
         note="人行道靠墙的 3 台自发光售卖机；补街面生活感",
         reused_from=None),
]
COMPONENTS.extend(NEW)


# ================================================================ 布局实例
# 主街沿 Y（南北向）：车道 x∈[-5,5]，人行道 |x|∈[5,10]，立面线 x=±10。
# 相机在南端内侧高处向北看 —— 与 v001 的四十五度十字广场是两种镜头语言。
LAYOUT: list[dict] = []
SW = 5.0


def inst(slug, group, x, y, z=0.0, rz=0.0):
    LAYOUT.append(dict(slug=slug, group=group, loc=(x, y, z), rz=rz))


def build_layout():
    LAYOUT.clear()
    A, B, C, D, E = ("03A_街区基底与道路", "03B_主体建筑与霓虹", "03C_跨街高架与地下围护",
                     "03D_街道设施与车辆", "03E_吊顶结构与管线")

    # ---------------- A 路面 / 人行道 ----------------
    # 十字路口在原点：南北主街 x∈[-5,5]，东西横街 y∈[-5,5]，人行道到 |x|/|y| = 10
    for y in (-20.0, -10.0, 10.0, 20.0):
        inst("wet_asphalt_lane_10x10_01", A, 0.0, y)
    for x in (-20.0, -10.0, 10.0, 20.0):
        inst("wet_asphalt_lane_10x10_01", A, x, 0.0, 0.0, 90.0)
    inst("wet_asphalt_intersection_10x10_03", A, 0.0, 0.0)
    for (x, y, rz) in ((0.0, -7.5, 0.0), (0.0, 7.5, 0.0), (-7.5, 0.0, 90.0), (7.5, 0.0, 90.0)):
        inst("wet_asphalt_crosswalk_10x5_02", A, x, y, 0.0, rz)
    for x in (-7.5, 7.5):
        rz = 0.0 if x < 0 else 180.0
        for y in (-22.5, -17.5, -12.5, -7.5, 7.5, 12.5, 17.5, 22.5):
            inst("sidewalk_tile_5x5_01", A, x, y, 0.0, rz)
    for y in (-7.5, 7.5):
        rz = 90.0 if y < 0 else -90.0
        for x in (-22.5, -17.5, -12.5, 12.5, 17.5, 22.5):
            inst("sidewalk_tile_5x5_01", A, x, y, 0.0, rz)
    for (x, y, rz) in ((-2.9, -12.6, 12), (3.1, 3.4, -40), (-3.3, 11.6, 78),
                       (8.4, -2.6, 25), (-9.2, 2.4, -15), (2.4, 18.4, 8)):
        inst("puddle_reflect_patch_04", A, x, y, 0.0, rz)
    for (x, y, rz) in ((-3.4, -13.2, 0), (-3.2, -2.4, 0), (3.0, 12.0, 0),
                       (-8.0, -8.4, 90), (8.0, 6.4, 90), (2.2, 18.6, 0)):
        inst("wet_reflect_streak_05", A, x, y, 0.0, rz)
    for (x, y) in ((-4.1, -14.2), (4.0, 6.2), (-4.0, 18.4), (14.0, 4.2)):
        inst("drain_manhole_grate_set_01", A, x, y)

    # ---------------- B 建筑体量 ----------------
    # 立面线 x=±10；西侧自南向北：前景机房顶 → 药店 → 酒店 → 窄巷店面
    inst("foreground_service_roof_15x15_01", B, -20.0, -20.0, 0.0, 0.0)
    inst("pharmacy_shop_block_10x8_01", B, -15.0, -9.0, 0.0, 0.0)
    inst("hotel_brick_tower_core_10x12_01", B, -15.0, 5.5, 0.0, 0.0)
    inst("narrow_alley_shophouse_02", B, -12.0, 17.0, 0.0, 0.0)
    # 东侧自南向北：前景机房顶 → 背景楼 → 酒吧 → 背景楼
    inst("foreground_service_roof_15x15_01", B, 22.0, -19.0, 0.0, 180.0)
    # 酒吧楼占据东侧最先被看到的体量（画面右），南立面朝向街口
    inst("industrial_bar_building_10x12_01", B, 15.0, -6.5, 0.0, 0.0)
    inst("backdrop_tower_block_10x7_01", B, 15.0, 4.0, 0.0, 180.0)
    inst("backdrop_tower_block_10x7_01", B, 15.0, 19.0, 0.0, 180.0)
    inst("backdrop_tower_block_10x7_01", B, -15.0, 22.5, 0.0, 0.0)
    # 酒店东立面拱窗（5 层 × 3 列，朝 +X）
    for z in (4.1, 9.1, 14.1, 19.1, 23.7):
        for i in range(3):
            inst("hotel_arch_window_bay_02", B, -9.96, 1.4 + 2.93 * i, z, 90.0)
    inst("hotel_shutter_shopfront_03", B, -9.94, 0.4, 0.0, -90.0)
    # 霓虹（正面 -Y 的标识 rz=+90 朝 +X / rz=-90 朝 -X）
    inst("neon_sign_hotel_vertical_01", B, -9.66, 1.6, 10.4, 90.0)
    inst("neon_sign_bar_vertical_03", B, 9.72, -10.2, 15.2, -90.0)

    for (x, y, z, rz) in ((-9.88, -1.6, 3.4, 0.0), (-9.88, 8.6, 5.2, 0.0),
                          (9.88, 2.0, 5.6, 180.0), (9.88, 10.6, 3.0, 180.0),
                          (9.88, 14.6, 4.4, 180.0), (-9.88, 15.0, 5.0, 0.0)):
        inst("neon_blade_sign_cluster_05", B, x, y, z, rz)

    # ---------------- C 跨街高架与地下围护 ----------------
    # 跨街桥横在路口北侧上空（画面右上），不压 HOTEL 主招牌
    inst("skybridge_truss_span_21m_01", C, 0.0, 13.5, 0.0, 0.0)
    inst("skybridge_hazard_pillar_02", C, -8.8, 13.5, 0.0, 0.0)
    inst("skybridge_hazard_pillar_02", C, 8.8, 13.5, 0.0, 0.0)
    inst("skybridge_sign_sector07_04", C, -1.5, 11.62, 12.95, 0.0)
    for x in (-20.0, -10.0, 10.0, 20.0):
        inst("cavern_wall_module_10x30_01", C, x, WALL_Z, 0.0, 0.0)
        inst("cavern_wall_module_10x30_01", C, x, -WALL_Z, 0.0, 180.0)
    for y in (-20.0, -10.0, 10.0, 20.0):
        inst("cavern_wall_module_10x30_01", C, WALL_Z, y, 0.0, -90.0)
        inst("cavern_wall_module_10x30_01", C, -WALL_Z, y, 0.0, 90.0)
    inst("tunnel_portal_arch_10m_01", C, 0.0, 25.65, 0.0, 0.0)
    inst("tunnel_portal_arch_10m_01", C, 0.0, -25.65, 0.0, 180.0)
    inst("tunnel_portal_arch_10m_01", C, 25.65, 0.0, 0.0, -90.0)
    inst("tunnel_portal_arch_10m_01", C, -25.65, 0.0, 0.0, 90.0)
    inst("cavern_base_slab_52x52_01", C, 0.0, 0.0)
    inst("cavern_ceiling_slab_52x52_01", C, 0.0, 0.0)
    for y in (-20.0, -10.0, 0.0, 10.0, 20.0):
        inst("ceiling_truss_rib_52m_01", C, 0.0, y)
    for (x, y) in ((-22.5, -22.5), (22.5, -22.5), (-22.5, 22.5), (22.5, 22.5)):
        inst("cavern_support_column_30m_01", C, x, y)

    # ---------------- D 街道设施与车辆 ----------------
    # 灯杆沿两侧人行道交替，双臂横过街心
    for (x, y, rz) in ((-8.4, -19.0, 0.0), (-8.4, -2.0, 0.0), (-8.4, 12.0, 0.0), (-8.4, 20.0, 0.0),
                       (8.4, -16.0, 180.0), (8.4, 4.0, 180.0), (8.4, 17.0, 180.0),
                       (14.0, -7.2, 90.0), (-14.0, 7.2, -90.0), (-18.0, 7.2, -90.0)):
        inst("industrial_street_lamp_pole_01", D, x, y, 0.18, rz)
    for (x, y) in ((-5.8, -10.6), (-5.8, -4.4), (5.8, -10.6), (5.8, 4.4),
                   (10.6, -4.4), (-10.6, 4.4), (-5.8, 15.4), (5.8, 9.4)):
        inst("glowing_hazard_bollard_02", D, x, y)
    for (x, y, rz) in ((-8.6, -20.0, 0.0), (-8.6, -15.0, 0.0), (8.6, 15.0, 0.0),
                       (12.0, -10.6, 90.0), (-12.0, 10.6, 90.0), (8.6, 7.0, 0.0)):
        inst("street_guardrail_fence_4m_01", D, x, y, 0.18, rz)
    for (x, y, rz) in ((-9.0, -8.6, 0.0), (9.2, 8.4, 180.0), (20.0, -8.6, -90.0),
                       (-20.0, 8.2, 90.0), (-9.0, 16.6, 0.0)):
        inst("street_utility_cabinet_02", D, x, y, 0.18, rz)
    for (x, y, rz) in ((-2.6, -16.0, 0.0), (2.7, 16.5, 180.0), (16.0, 1.6, 90.0),
                       (-2.4, 2.8, 0.0)):
        inst("retro_cyber_sedan_car_01", D, x, y, 0.02, rz)
    # 立面附着（空调 / 竖管 / 横管 / 消防梯）—— 只挂在酒店与酒吧两栋主立面上
    for (x, y, z, rz) in ((-9.55, 2.2, 6.2, 90.0), (-9.55, 5.4, 11.0, 90.0), (-9.55, 8.2, 16.0, 90.0),
                          (-9.55, 10.4, 21.0, 90.0), (9.55, 2.4, 6.4, -90.0), (9.55, 5.6, 11.2, -90.0),
                          (9.55, 8.4, 15.4, -90.0), (-9.55, -7.4, 4.4, 90.0),
                          (-9.55, -2.6, 5.6, 90.0), (9.55, 10.2, 20.4, -90.0)):
        inst("wall_ac_outdoor_unit_03", D, x, y, z, rz)
    for (x, y, rz) in ((-9.7, 9.4, 0.0), (-9.7, 0.0, 0.0), (9.7, 1.4, 0.0),
                       (9.7, 9.8, 0.0), (-9.7, -3.2, 0.0), (9.7, 12.4, 0.0)):
        inst("facade_pipe_cluster_vertical_01", D, x, y, 0.0, rz)
    for (x, y, z, rz) in ((-9.7, 3.6, 4.6, 0.0), (-9.7, 6.9, 1.2, 0.0),
                          (9.7, 4.0, 3.4, 180.0), (9.7, 8.0, 6.0, 180.0)):
        inst("facade_pipe_elbow_horizontal_02", D, x, y, z, rz)
    inst("metal_fire_stair_walkway_03", D, -9.2, 8.9, 5.6, -90.0)
    inst("metal_fire_stair_walkway_03", D, 9.2, 9.6, 9.2, 90.0)
    # 屋顶设备（前景机房顶 7.62 / 酒店顶 26.3 / 酒吧顶 18.3 / 药店顶 7.5）
    for (x, y, z, rz) in ((-22.0, -20.0, 7.62, 15.0), (-14.0, -21.0, 7.62, -30.0),
                          (-17.0, 4.4, 26.3, 10.0), (13.2, -20.4, 7.62, 15.0)):
        inst("rooftop_twin_fan_chiller_01", D, x, y, z, rz)
    for (x, y, z, rz) in ((-24.0, -13.5, 7.62, 0.0), (-18.5, -13.0, 7.62, 90.0),
                          (-11.0, -20.0, 7.62, 0.0), (17.2, 4.0, 18.3, 45.0),
                          (-13.0, -13.0, 7.5, 0.0), (16.4, -20.2, 7.62, 0.0)):
        inst("rooftop_exhaust_vent_box_02", D, x, y, z, rz)
    for (x, y, rz) in ((-20.0, 3.4, 30.0), (4.4, 21.5, -20.0), (-8.6, 3.2, 0.0)):
        inst("street_rock_rubble_pile_04", D, x, y, 0.0, rz)
    # 本版新增：蒸汽 / 售货机柜 / 悬臂信号杆
    for (x, y, rz) in ((-3.2, 4.4, 12.0), (4.0, -13.0, -8.0), (-9.0, -6.0, 22.0)):
        inst("steam_vapor_vent_02", D, x, y, 0.0, rz)
    inst("vending_machine_bank_02", D, -9.1, -8.4, 0.0, 0.0)
    inst("vending_machine_bank_02", D, 9.1, -3.4, 0.0, 180.0)
    inst("traffic_signal_mast_02", D, -6.4, -6.2, 0.0, 0.0)
    inst("traffic_signal_mast_02", D, 6.4, 6.2, 0.0, 180.0)

    # ---------------- E 吊顶结构与管线 ----------------
    # 风管束只在街道两端（y=±20）：原来放在 y=-14/4 时，正好横在参考机位的高度上，
    # 把画面上沿整条糊住（实测），挪到两端既保留吊顶管线语义又不挡主街。
    for y in (-20.0, 20.0):
        inst("ceiling_duct_bundle_20m_01", E, 0.0, y, 21.2, 90.0)
    for x in (-14.0, 14.0):
        inst("ceiling_duct_bundle_20m_01", E, x, 0.0, 24.0, 0.0)
    for y in (-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0):
        inst("hanging_lamp_industrial_01", E, 0.0, y, 18.9)
    for (x, y) in ((-14.0, 0.0), (14.0, 0.0)):
        inst("ceiling_exhaust_fan_3x3_01", E, x, y, 27.9)
    # 跨街电缆只保留远端一根：近端那根在参考构图的机位上正好横切画面上沿，
    # 把 HOTEL 招牌的顶部切掉（实测），挪到街北端既保留电缆语义又不挡主招牌。
    inst("sky_cable_span_24m_01", E, 0.0, 19.0, 0.0, 0.0)


build_layout()

GROUP_ORDER = ["03A_街区基底与道路", "03B_主体建筑与霓虹", "03C_跨街高架与地下围护",
               "03D_街道设施与车辆", "03E_吊顶结构与管线"]


# ================================================================ 主流程

def main():
    L.purge_scene()
    mats = L.ensure_materials()
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0

    root_src = L.new_collection("01_制作组件_按组件拆分_%s" % VERSION, hide=True)
    root_pkg = L.new_collection("02_游戏输出_独立资产包_%s" % VERSION, hide=True)
    root_layout = L.new_collection("03_场景拼装_实例布局_%s" % VERSION)
    root_disp = L.new_collection("90_展示与动态_灯光相机")

    groups = {g: L.new_collection(g, root_layout) for g in GROUP_ORDER}

    records = []
    pkg_colls = {}
    z_offsets = {}
    for entry in COMPONENTS:
        slug = entry["slug"]
        gpkg = L.Geo()
        entry["builder"](gpkg)
        min_z = min(v[2] for v in gpkg.verts)
        if abs(min_z) > 1e-6:
            gpkg.verts = [(v[0], v[1], v[2] - min_z) for v in gpkg.verts]
        z_offsets[slug] = min_z
        pkg = L.new_collection("资产包_%s" % slug, root_pkg)
        L.link_mesh(pkg, entry["name_zh"], gpkg, mats)
        pkg_colls[slug] = pkg
        gsrc = L.Geo()
        entry["builder"](gsrc)
        gsrc.verts = [(v[0], v[1], v[2] - min_z) for v in gsrc.verts]
        src_coll = L.new_collection("组件源_%s" % slug, root_src)
        L.link_mesh(src_coll, "源_%s" % entry["name_zh"], gsrc, mats)
        b = L.bounds_of(gpkg)
        records.append(dict(
            entry=entry,
            dims=(b[1] - b[0], b[3] - b[2], b[5] - b[4]),
            polys=L.poly_count(gpkg),
            z_offset=min_z,
            objects=[o.name for o in pkg.objects],
            src_objects=[o.name for o in src_coll.objects],
        ))

    inst_records = []
    for i, item in enumerate(LAYOUT):
        pkg = pkg_colls[item["slug"]]
        emp = bpy.data.objects.new("inst_%s_%03d" % (item["slug"], i + 1), None)
        emp.instance_type = "COLLECTION"
        emp.instance_collection = pkg
        emp.empty_display_type = "PLAIN_AXES"
        emp.empty_display_size = 0.6
        world_z = item["loc"][2] + z_offsets.get(item["slug"], 0.0)
        emp.location = (item["loc"][0], item["loc"][1], round(world_z, 6))
        emp.rotation_euler = (0.0, 0.0, math.radians(item["rz"]))
        groups[item["group"]].objects.link(emp)
        inst_records.append(dict(name=emp.name, slug=item["slug"], group=item["group"],
                                 loc=[item["loc"][0], item["loc"][1], round(world_z, 6)],
                                 rz=item["rz"]))

    # 场景总包络（从实例化后的真实包围盒求并集，供账本/审计引用）
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    for it in inst_records:
        emp = bpy.data.objects[it["name"]]
        for obj in pkg_colls[it["slug"]].all_objects:
            if obj.type != "MESH":
                continue
            for corner in obj.bound_box:
                w = emp.matrix_world @ obj.matrix_world @ __import__("mathutils").Vector(corner)
                for k in range(3):
                    lo[k] = min(lo[k], w[k])
                    hi[k] = max(hi[k], w[k])

    # ---------------- 灯光 / 相机 / 世界 ----------------
    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.010, 0.013, 0.024, 1.0)
        bg.inputs[1].default_value = 1.0

    def add_light(name, kind, loc, energy, color, rot=(0, 0, 0), size=None, spot=None):
        data = bpy.data.lights.new(name, kind)
        data.energy = energy
        data.color = color
        if kind == "AREA" and size:
            data.size = size
        if kind == "SPOT" and spot:
            data.spot_size = spot
            data.spot_blend = 0.45
        obj = bpy.data.objects.new(name, data)
        obj.location = loc
        obj.rotation_euler = rot
        root_disp.objects.link(obj)
        return obj

    add_light("补光_顶棚主光", "AREA", (0, 0, 26.6), 3200, (0.60, 0.71, 1.0), (0, 0, 0), size=30)
    add_light("补光_街心冷光", "AREA", (0, 0, 14.0), 1200, (0.52, 0.66, 1.0), (0, 0, 0), size=16)
    add_light("霓虹_酒店粉", "POINT", (-7.8, 3.2, 12.4), 380, (1.0, 0.16, 0.34))
    # 药店洗墙光：**必须朝 -X（对着立面）**，不是朝 +X。
    # 上一版写的是 (58, 0, -90)，按 Rz·Rx 分解这指向 +X —— 光照的是街心那块湿地，
    # 立面没被照亮、水洼反而被打成一块白板（实测街口机位底部一个大白块）。
    # 这里的欧拉角是按「灯位 → 立面目标点」反算的：Rx 抬角 / Rz 偏航。
    # 功率再降一档并改成掠射（灯贴近墙面、几乎平行于墙），只擦亮凸出的线脚：
    # 820W 时整面立面被刷成浅蓝一片，暗部梯度全丢（实测）。掠射才是"洗墙"该有的做法。
    add_light("药店洗墙_主", "AREA", (-8.5, -9.2, 8.6), 42, (0.62, 0.74, 1.0),
              (math.radians(58), 0, math.radians(90)), size=6)
    add_light("药店洗墙_补", "AREA", (-8.7, -12.4, 2.4), 16, (0.58, 0.70, 1.0),
              (math.radians(72), 0, math.radians(90)), size=4)
    add_light("霓虹_药店青", "POINT", (-8.4, -9.6, 5.0), 200, (0.20, 0.90, 0.86))
    add_light("霓虹_酒吧红", "POINT", (8.4, -10.2, 15.4), 400, (1.0, 0.2, 0.28))
    add_light("霓虹_高架橙", "POINT", (-1.0, 8.6, 12.4), 220, (1.0, 0.62, 0.18))
    add_light("街口射灯", "SPOT", (5.0, -14.0, 12.0), 480, (0.72, 0.82, 1.0),
              (math.radians(60), 0, math.radians(-24)), spot=math.radians(70))
    add_light("酒店门头暖光", "SPOT", (-8.0, 3.2, 3.8), 280, (1.0, 0.55, 0.3),
              (math.radians(74), 0, math.radians(-90)), spot=math.radians(60))
    add_light("蒸汽逆光", "SPOT", (-1.0, 4.4, 6.0), 240, (0.75, 0.86, 1.0),
              (math.radians(96), 0, math.radians(-150)), spot=math.radians(46))
    # 贴地色光：给湿路面一点霓虹回光，参考图里路面是被招牌染色的
    add_light("地面回光_酒店粉", "POINT", (-6.0, 4.0, 1.2), 120, (1.0, 0.22, 0.40))
    add_light("地面回光_药店青", "POINT", (-6.4, -6.0, 1.0), 90, (0.16, 0.92, 0.86))
    add_light("地面回光_酒吧红", "POINT", (6.6, 8.0, 1.2), 110, (1.0, 0.24, 0.30))
    add_light("地面回光_桥底橙", "POINT", (0.0, 12.0, 1.4), 80, (1.0, 0.62, 0.20))

    from mathutils import Vector
    # 与参考图同一镜头语言：东南侧高处斜俯视路口，HOTEL 在左、BAR 在右、跨街桥在右上
    cam_data = bpy.data.cameras.new("CAM_参考构图")
    cam_data.lens = 30
    cam_obj = bpy.data.objects.new("CAM_参考构图", cam_data)
    cam_obj.location = (11.5, -23.5, 18.5)
    root_disp.objects.link(cam_obj)
    d = Vector((-8.0, 5.0, 12.0)) - cam_obj.location
    cam_obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam_obj

    top_data = bpy.data.cameras.new("CAM_俯视正交")
    top_data.type = "ORTHO"
    top_data.ortho_scale = 54
    top_cam = bpy.data.objects.new("CAM_俯视正交", top_data)
    top_cam.location = (0, 0, 70)
    root_disp.objects.link(top_cam)

    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.film_transparent = False
    eevee = getattr(scene, "eevee", None)
    if eevee is not None:
        if hasattr(eevee, "taa_render_samples"):
            eevee.taa_render_samples = 48
        if hasattr(eevee, "use_raytracing"):
            eevee.use_raytracing = True
    names = [v.name for v in scene.view_settings.bl_rna.properties["view_transform"].enum_items]
    scene.view_settings.view_transform = "Filmic" if "Filmic" in names else "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.6

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, check_existing=False)
    try:
        bpy.ops.file.make_paths_relative()
        bpy.ops.wm.save_mainfile()
    except Exception as exc:  # 相对路径失败不应中断交付
        print("WARN make_paths_relative:", exc)

    write_catalogs(records, inst_records, lo, hi)
    print(json.dumps({
        "blend": BLEND_PATH,
        "components": len(records),
        "instances": len(inst_records),
        "polygons": sum(r["polys"] for r in records),
        "scene_bounds_m": [round(lo[k], 3) for k in range(3)] + [round(hi[k], 3) for k in range(3)],
        "materials": [m.name for m in bpy.data.materials],
    }, ensure_ascii=False))


def write_catalogs(records, inst_records, lo, hi):
    os.makedirs(OUT_DIR, exist_ok=True)
    pkg_root = os.path.join(OUT_DIR, "component_packages")
    if os.path.isdir(pkg_root):
        import shutil
        shutil.rmtree(pkg_root)
    os.makedirs(pkg_root, exist_ok=True)
    count_by_slug = {}
    for it in inst_records:
        count_by_slug[it["slug"]] = count_by_slug.get(it["slug"], 0) + 1

    catalog_components = []
    for rec in records:
        e = rec["entry"]
        slug = e["slug"]
        dims = [round(v, 3) for v in rec["dims"]]
        man = {
            "schema": "shellstorm2.openworld.asset_manifest",
            "schema_version": 1,
            "asset_id": "%s-%s" % (ASSET_ID_ROOT, slug.upper()),
            "package_id": slug,
            "slug": slug,
            "name_zh": e["name_zh"],
            "suite": SUITE,
            "version": VERSION,
            "district": "地下街区",
            "category": e["category"],
            "family_id": e["family"],
            "variant_axis": None,
            "variant_value": None,
            "variant_reason": None,
            "serves_districts": ["地下街区"],
            "scope": "suite_local",
            "source_blend": os.path.relpath(BLEND_PATH, PROJECT).replace("\\", "/"),
            "reused_from": e.get("reused_from"),
            "geometry_source": ("build_openworld_underground_street_v001.py::%s" % e["builder"].__name__
                                if e.get("reused_from") else
                                "build_openworld_underground_street_v002.py::%s" % e["builder"].__name__),
            "blender_collection": "资产包_%s" % slug,
            "source_collection": "组件源_%s" % slug,
            "objects": rec["objects"],
            "source_objects": rec["src_objects"],
            "pivot_rule": "bottom_center_z0",
            "local_origin": [0.0, 0.0, 0.0],
            "source_z_offset_m": round(rec["z_offset"], 4),
            "front_axis": FRONT_AXIS.get(slug, "+X"),
            "allowed_rotations_y_deg": FIXED_ROT.get(slug, [0, 90, 180, 270]),
            "dimensions_m": dims,
            "polygon_count": rec["polys"],
            "instance_count": count_by_slug.get(slug, 0),
            "material_roles": sorted({L.ROLE_METAL, L.ROLE_MATTE, L.ROLE_GLOSS}),
            "emissive_split": any("UI灯光自发光" in n for n in rec["objects"]),
            "palette": "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png",
            "uv_layer": "PaletteUV",
            "collision": "none（Blender 源阶段；碰撞归后续 Godot 包装）",
            "export": {"glb": None, "exported": False},
            "note": e.get("note", ""),
        }
        d = os.path.join(pkg_root, slug)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "asset_manifest.json"), "w", encoding="utf-8") as f:
            json.dump(man, f, ensure_ascii=False, indent=2)
        catalog_components.append({
            "component_id": "comp_%s" % slug,
            "slug": slug,
            "display_name": e["name_zh"],
            "family_id": e["family"],
            "category": e["category"],
            "dimensions_m": dims,
            "pivot_rule": "bottom_center_z0",
            "source_z_offset_m": round(rec["z_offset"], 4),
            "output_collection": "资产包_%s" % slug,
            "mesh_objects": rec["objects"],
            "polygon_count": rec["polys"],
            "instance_count": count_by_slug.get(slug, 0),
            "reused_from": e.get("reused_from"),
        })

    scene_bounds = [round(lo[k], 3) for k in range(3)] + [round(hi[k], 3) for k in range(3)]
    catalog = {
        "schema": "shellstorm2.openworld.component_catalog",
        "schema_version": 1,
        "suite_name": SUITE,
        "asset_id_root": ASSET_ID_ROOT,
        "version": VERSION,
        "block_id": "open_world",
        "district": "地下街区",
        "street_number": 2,
        "unique_component_count": len(catalog_components),
        "total_instance_count": len(inst_records),
        "reused_component_count": len([c for c in catalog_components if c["reused_from"]]),
        "new_component_count": len([c for c in catalog_components if not c["reused_from"]]),
        "scene_bounds_m": scene_bounds,
        "components": catalog_components,
    }
    with open(os.path.join(OUT_DIR, "component_catalog.json"), "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)

    with open(os.path.join(OUT_DIR, "component_instances.json"), "w", encoding="utf-8") as f:
        json.dump({
            "schema": "shellstorm2.openworld.component_instances",
            "schema_version": 1,
            "suite_name": SUITE,
            "version": VERSION,
            "total_instance_count": len(inst_records),
            "note": "仅初始化与追溯；正式摆位由后续 Godot TSCN 拥有",
            "instances": inst_records,
        }, f, ensure_ascii=False, indent=2)

    plan = {
        "schema": "shellstorm2.openworld.component_plan",
        "schema_version": 1,
        "suite_name": SUITE,
        "version": VERSION,
        "street_number": 2,
        "component_budget": {"limit": 50, "unique": len(catalog_components),
                             "reused": catalog["reused_component_count"],
                             "new": catalog["new_component_count"]},
        "family_budget": "同族常规 ≤3、有明确状态轴 ≤5",
        "families": {},
        "layout_groups": GROUP_ORDER,
        "reuse_policy": "复用 v001 组件生成器函数（同一函数体，几何零漂移），不复制几何到第二份母版维护",
    }
    for c in catalog_components:
        plan["families"].setdefault(c["family_id"], []).append(c["slug"])
    with open(os.path.join(OUT_DIR, "component_plan.json"), "w", encoding="utf-8") as f:
        json.dump(plan, f, ensure_ascii=False, indent=2)

    lines = ["%s (%s) - 大世界 地下街区 编号02 · 路口居中·双侧满铺" % (SUITE, VERSION),
             "├── 01_制作组件_按组件拆分_%s (%d Master Components)" % (VERSION, len(records)),
             "├── 02_游戏输出_独立资产包_%s (%d Output Packages, Body/Emissive Split)"
             % (VERSION, len(records)),
             "├── 03_场景拼装_实例布局_%s (%d Collection Instances)" % (VERSION, len(inst_records)),
             "└── 90_展示与动态_灯光相机 (Cameras, Neon Lights)", "",
             "复用 v001 生成器：%d 件 / 本版新生产：%d 件"
             % (catalog["reused_component_count"], catalog["new_component_count"]), "Components:"]
    for rec in records:
        c = rec["entry"]
        d = " × ".join("%.2f" % v for v in rec["dims"])
        lines.append("  - [comp_%s] %s | %s m | polys=%d | instances=%d%s"
                     % (c["slug"], c["name_zh"], d, rec["polys"], count_by_slug.get(c["slug"], 0),
                        "  (reuse v001)" if c.get("reused_from") else "  (NEW)"))
    with open(os.path.join(OUT_DIR, "component_tree.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


# v003 复用本文件的组件生成器与布局，import 时不能执行 main()（main 第一句是
# L.purge_scene()，会把当前场景清空）。守卫写法与 v001 一致。
if os.environ.get("UG_STREET_BUILD_LIB_ONLY") != "1":
    try:
        main()
    except Exception as exc:
        import traceback
        traceback.print_exc()
        print("BUILD_FAILED:", exc)
        raise
