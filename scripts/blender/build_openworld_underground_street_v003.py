"""大世界 · 地下街区 编号02 · v003（按「硬边写实三维场景提示词模版 v1.1」深化）

本版只做一件事：**把 v002 里仍是"抽象盒子"的三栋主体楼做到参考图颗粒度**，
并把街面缺的四类细节补成独立组件。v002 已经细化过的药店楼原样继承。

深化对象（v002 → v003）：
  · 酒店楼 hotel_brick_tower_core_10x12_01   234 → 约 4.3k 面（外壳真开洞 / 拱窗并入 / 齐缝砖 / 檐口 / 消防梯 / 屋顶水箱）
  · 酒吧楼 industrial_bar_building_10x12_01  240 → 约 2.4k 面（工业肋板 / 铆钉 / 锈痕 / 管束 / 屋顶烟囱 / 消防梯）
  · 背景楼 backdrop_tower_block_10x7_01      194 → 约 0.9k 面（8×3 窄窗 / 竖向壁柱 / 叠涩檐口 / 屋顶设备）
  · 两块竖招牌改为**几何笔画**（HOTEL / BAR 逐字母），v002 里它们是色块

新增组件（4 件，全部 suite_local）：
  · road_paint_dash_run_03    路面标线组（虚线 / 停止线 / 导向箭头 / 井盖圈 / 补丁缝）
  · street_pavement_detail_03 人行道细节层（砖缝 / 排水篦 / 井盖 / 缘石反光条 / 防滑条）
  · street_cable_harness_03   贴墙线束（三束电缆 / 吊环 / 分线盒 / 下垂段）
  · facade_billboard_panel_03 墙面广告灯箱（边框 / 内凹板 / 几何图形 / 支架）

组件预算：46 − 3（并入宿主：拱窗模块 / 卷帘门模块 / 消防梯模块）+ 4 = 47 ≤ 50。

配色口径（业主 2026-10-20 指定）：
  · 暗部只走**邻近色**，亮度按同一色相列拉开；跳色只给自发光。
  · 酒店以砖红为族（色盘 R1 列 #29070E→#724A4F，lum 15→83）；
  · 酒吧与背景楼以蓝紫为族（R7 / R6 列），与药店、街面同族。
  · 立面明暗跨度按 13→85 排；不允许把 5 个暗色挤在 15 个亮度单位以内（那样等于同一个色）。

几何硬约束（v002 药店那一轮踩出来的，本版全套沿用）：
  1. 开洞必须真开：0.40~0.50m 厚表皮 + 内退暗核，不允许在实心体里贴玻璃。
  2. 层叠顺序固定：暗腔 → 玻璃/发光面 → 窗格 → 外框 → 窗台/过梁，逐层向外，绝不互相包住。
  3. 构件互挡要在脚本里显式让开（横梁遇竖招牌断开；雨棚出挑不能盖死橱窗）。
  4. 洗墙光必须朝被照立面（欧拉角按 Rz·Rx 分解核对），低功率掠射，不许整面刷白。
  5. 字必须方形、笔画留缝、笔宽按「目标视距 ≥4px」反算。
"""

from __future__ import annotations

import json
import math
import os
import sys

PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if os.path.join(PROJECT, "scripts", "blender") not in sys.path:
    sys.path.insert(0, os.path.join(PROJECT, "scripts", "blender"))

import bpy  # noqa: E402

import ug_street_lib_v001 as L  # noqa: E402

# 复用 v001 / v002 的组件生成器与布局：必须让它们的 main() 不在 import 时执行。
# 注意：这个环境变量只能覆盖 import 期间，不能留在进程里 —— 否则本文件末尾
# 自己的 `if UG_STREET_BUILD_LIB_ONLY != "1": main()` 也会被跳过（第一次就是这么哑掉的：
# 整次运行只打印了 Blender 版本，什么都没建）。
_PREV_LIB_ONLY = os.environ.get("UG_STREET_BUILD_LIB_ONLY")
os.environ["UG_STREET_BUILD_LIB_ONLY"] = "1"
try:
    import build_openworld_underground_street_v001 as V1  # noqa: E402
    import build_openworld_underground_street_v002 as V2  # noqa: E402
finally:
    if _PREV_LIB_ONLY is None:
        os.environ.pop("UG_STREET_BUILD_LIB_ONLY", None)
    else:
        os.environ["UG_STREET_BUILD_LIB_ONLY"] = _PREV_LIB_ONLY

SUITE = "underground_street"
VERSION = "v003"
OUT_DIR = os.path.join(PROJECT, "art_source", "environments", "open_world", "source", SUITE, VERSION)
BLEND_PATH = os.path.join(OUT_DIR, "env_underground_street_source_%s.blend" % VERSION)
ASSET_ID_ROOT = "ENV-OPENWORLD-UNDERGROUND-STREET-02"

MATTE, METAL, GLOSS, EMIT = L.ROLE_MATTE, L.ROLE_METAL, L.ROLE_GLOSS, L.ROLE_EMIT

# ================================================================ 色板
# 酒店：砖红族（色盘 R1 列，同一色相只动亮度 15→83）
H_D0 = (0, 1)   # #29070E 15  深凹缝 / 窗洞内腔
H_D1 = (1, 1)   # #390D0D 22  墙体暗面
H_D2 = (2, 1)   # #4B0C13 26  墙面主色
H_D3 = (3, 1)   # #5A0E1A 31  壁柱 / 砖层
H_D4 = (4, 1)   # #650D20 33  线脚
H_D5 = (5, 1)   # #6E1C2A 46  受光面
H_D6 = (6, 1)   # #71333C 65  压顶
H_D7 = (7, 1)   # #724A4F 83  檐口上口（最高光）

# 酒吧：青绿族（色盘 R5 列 #041A1A→#2E6870，lum 21→92）。
# 上一版酒吧用的是 R7 紫列，整面立面在渲染里泛紫 —— 业主口径是「暗部走邻近色、
# 不要大面积紫」。R5 青绿与药店/背景楼的 R6 蓝紫互为邻近色，既能区分两栋楼，
# 又不会在画面里冒出第三种色相。
B_D0 = (0, 5)   # #041A1A 21
B_D1 = (1, 5)   # #03231B 28
B_D2 = (2, 5)   # #073532 43
B_D3 = (3, 5)   # #06433D 54
B_D4 = (4, 5)   # #09534B 67
B_D5 = (5, 5)   # #145F56 78
B_D6 = (6, 5)   # #0F5F6B 79
B_D7 = (7, 5)   # #2E6870 92

# 背景楼：蓝紫族（R6 列，与药店同族，只动亮度 16→86）
C_D0 = (0, 6)   # #051128 16
C_D1 = (1, 6)   # #0A1126 17
C_D2 = (2, 6)   # #0E1A3E 26
C_D3 = (3, 6)   # #0D2361 35
C_D4 = (4, 6)   # #112D6A 43
C_D5 = (5, 6)   # #1B3B6F 56
C_D6 = (6, 6)   # #2B4A71 70
C_D7 = (7, 6)   # #425972 86

# 冷色自发光 / 玻璃（与药店同口径）
N_INK = V2.N_INK
T_GLASS = V2.T_GLASS
E_COLD = V2.E_COLD
E_ICE = V2.E_ICE
E_WARM = V2.E_WARM
E_PINK = V2.E_PINK
E_DIM = V2.E_DIM
E_TEAL = V2.E_TEAL

SEAM = 0.06


# ================================================================ 通用几何工具

def _wall_panel(g, axis, t0, t1, w0, w1, z0, z1, holes, role, cell):
    """带洞墙板：按洞的 z 边切横带，再按洞的横向跨度切竖段。

    axis="y"：墙沿 y 展开，t 是 x 方向的厚度；axis="x"：墙沿 x 展开，t 是 y 方向厚度。
    这是"真开洞"的唯一做法 —— 实心体里贴玻璃会被墙自己挡死（v002 药店那一轮的根因）。
    """
    zs = {round(z0, 4), round(z1, 4)}
    for (_, _, hz0, hz1) in holes:
        if z0 - 1e-6 <= hz0 <= z1 + 1e-6:
            zs.add(round(hz0, 4))
        if z0 - 1e-6 <= hz1 <= z1 + 1e-6:
            zs.add(round(hz1, 4))
    zs = sorted(zs)
    for i in range(len(zs) - 1):
        za, zb = zs[i], zs[i + 1]
        if zb - za < 1e-5:
            continue
        zc = (za + zb) * 0.5
        segs = [(w0, w1)]
        for (h0, h1, hz0, hz1) in holes:
            if not (hz0 - 1e-6 <= zc <= hz1 + 1e-6):
                continue
            out = []
            for (a, b) in segs:
                if h1 <= a + 1e-6 or h0 >= b - 1e-6:
                    out.append((a, b))
                    continue
                if h0 > a + 1e-6:
                    out.append((a, h0))
                if h1 < b - 1e-6:
                    out.append((h1, b))
            segs = out
        for (a, b) in segs:
            if b - a <= 1e-4:
                continue
            if axis == "y":
                g.box(t0, t1, a, b, za, zb, role, cell)
            else:
                g.box(a, b, t0, t1, za, zb, role, cell)


def _shell(g, x0, x1, y0, y1, z0, z1, skin, openings, cell_wall, cell_core,
           faces=("+X", "-X", "+Y", "-Y")):
    """带洞外壳：内退暗核 + 四面表皮。openings 元素为 dict(face,a0,a1,z0,z1)。"""
    g.box(x0 + skin, x1 - skin, y0 + skin, y1 - skin, z0, z1, MATTE, cell_core)
    for face in faces:
        hs = [(o["a0"], o["a1"], o["z0"], o["z1"]) for o in openings if o["face"] == face]
        if face == "+X":
            _wall_panel(g, "y", x1 - skin, x1, y0, y1, z0, z1, hs, MATTE, cell_wall)
        elif face == "-X":
            _wall_panel(g, "y", x0, x0 + skin, y0, y1, z0, z1, hs, MATTE, cell_wall)
        elif face == "+Y":
            _wall_panel(g, "x", y1 - skin, y1, x0 + skin, x1 - skin, z0, z1, hs, MATTE, cell_wall)
        elif face == "-Y":
            _wall_panel(g, "x", y0, y0 + skin, x0 + skin, x1 - skin, z0, z1, hs, MATTE, cell_wall)


def _win(g, axis, sgn, plane, a0, a1, z0, z1, lit, cell_lit=None, cell_dark=None,
         mull=1, transom=True, sill=True, arch=0.0, arch_cell=None, frame_cell=None,
         grime=True, band_cell=None, cap_cell=None):
    """一樘已经开洞的窗（axis/sgn/plane 决定朝向，t 向内为正）。

    层叠顺序（由内向外）：暗背板 → 玻璃或发光面 → 竖梃/横档 → 外框 → 窗台 → 过梁/拱。
    所有内层都比外层更靠里，绝不会被下一层包住。
    """
    cell_lit = cell_lit or E_ICE
    cell_dark = cell_dark or T_GLASS
    arch_cell = arch_cell or cell_lit
    frame_cell = frame_cell or B_D6
    band_cell = band_cell or frame_cell
    cap_cell = cap_cell or H_D7

    def put(t0, t1, aa0, aa1, zz0, zz1, role, cell):
        c0, c1 = plane - sgn * t1, plane - sgn * t0
        if axis == "x":
            g.box(c0, c1, aa0, aa1, zz0, zz1, role, cell)
        else:
            g.box(aa0, aa1, c0, c1, zz0, zz1, role, cell)

    # 暗背板
    put(0.30, 0.36, a0, a1, z0, z1, MATTE, N_INK)
    # 玻璃 / 发光面
    if lit:
        put(0.26, 0.30, a0 + 0.03, a1 - 0.03, z0 + 0.03, z1 - 0.03, EMIT, cell_lit)
        put(0.26, 0.30, a0 + 0.06, a1 - 0.06, z1 - 0.18, z1 - 0.06, EMIT, E_COLD)
    else:
        put(0.26, 0.30, a0 + 0.03, a1 - 0.03, z0 + 0.03, z1 - 0.03, GLOSS, cell_dark)
        # 暗窗的冷反射：放在窗高 70~78% 处（不是窗底），否则远看是"窗下一条灯带"，
        # 而且宽度只占窗宽 55%，避免每扇窗都亮同一条。
        rz0 = z0 + (z1 - z0) * 0.70
        put(0.26, 0.30, a0 + (a1 - a0) * 0.12, a0 + (a1 - a0) * 0.67,
            rz0, rz0 + (z1 - z0) * 0.08, EMIT, E_DIM)
    # 窗格
    if mull:
        step = (a1 - a0) / float(mull)
        for i in range(1, mull):
            c = a0 + step * i
            put(0.16, 0.22, c - 0.032, c + 0.032, z0, z1, METAL, frame_cell)
    if transom:
        tz = z0 + (z1 - z0) * 0.68
        put(0.16, 0.22, a0, a1, tz - 0.030, tz + 0.030, METAL, frame_cell)
    # 外框
    f = 0.07
    for (aa0, aa1, zz0, zz1) in ((a0, a1, z1 - f, z1), (a0, a1, z0, z0 + f),
                                 (a0, a0 + f, z0, z1), (a1 - f, a1, z0, z1)):
        put(-0.05, 0.02, aa0, aa1, zz0, zz1, METAL, frame_cell)
    # 窗台（两级 + 上表面最亮）
    if sill:
        put(-0.02, 0.18, a0 - 0.10, a1 + 0.10, z0 - 0.13, z0 - 0.02, METAL, band_cell)
        put(0.14, 0.18, a0 - 0.10, a1 + 0.10, z0 - 0.13, z0 - 0.02, METAL, cap_cell)
        put(0.14, 0.18, a0 - 0.10, a1 + 0.10, z0 - 0.20, z0 - 0.13, MATTE, N_INK)
    # 过梁 / 阶梯拱
    if arch <= 0.0:
        put(-0.02, 0.10, a0 - 0.07, a1 + 0.07, z1, z1 + 0.12, METAL, frame_cell)
    else:
        steps = 6
        put(-0.02, 0.08, a0 - 0.07, a1 + 0.07, z1, z1 + 0.10, METAL, frame_cell)
        for k in range(steps):
            frac = 1.0 - (k + 1.0) / steps
            half = (a1 - a0) * 0.5 * math.sqrt(max(0.0, 1.0 - ((k + 1.0) / steps) ** 2))
            zz0 = z1 + 0.10 + k * (arch / steps)
            zz1 = zz0 + arch / steps + 0.005
            c = (a0 + a1) * 0.5
            put(-0.02, 0.06, c - half - 0.07, c + half + 0.07, zz0, zz1, METAL, frame_cell)
            if k < steps - 1:
                put(0.06, 0.16, c - half + 0.05, c + half - 0.05, zz0, zz1, EMIT, arch_cell)
    # 窗下降雨痕（比墙暗一级，只做三道）
    if grime:
        for k in (0.25, 0.55, 0.82):
            ww = a0 + (a1 - a0) * k
            put(0.0, 0.012, ww - 0.035, ww + 0.035, z0 - 0.62, z0 - 0.20, MATTE, H_D0)


# 字母笔画表（归一 0..1，原点左下）——全部轴对齐，H/O/T/E/L/B/A/R 都够用
STROKES = {
    "H": [(0.00, 0.16, 0.00, 1.00), (0.84, 1.00, 0.00, 1.00), (0.16, 0.84, 0.43, 0.57)],
    "O": [(0.00, 1.00, 0.88, 1.00), (0.00, 1.00, 0.00, 0.12),
          (0.00, 0.14, 0.12, 0.88), (0.86, 1.00, 0.12, 0.88)],
    "T": [(0.00, 1.00, 0.86, 1.00), (0.43, 0.57, 0.00, 0.86)],
    "E": [(0.00, 0.15, 0.00, 1.00), (0.15, 1.00, 0.86, 1.00),
          (0.15, 0.92, 0.43, 0.57), (0.15, 1.00, 0.00, 0.14)],
    "L": [(0.00, 0.15, 0.00, 1.00), (0.15, 1.00, 0.00, 0.14)],
    "B": [(0.00, 0.15, 0.00, 1.00), (0.15, 0.88, 0.84, 1.00),
          (0.15, 0.88, 0.43, 0.57), (0.15, 0.88, 0.00, 0.14),
          (0.84, 1.00, 0.57, 0.84), (0.84, 1.00, 0.14, 0.43)],
    "A": [(0.00, 0.16, 0.00, 0.82), (0.84, 1.00, 0.00, 0.82),
          (0.00, 1.00, 0.82, 1.00), (0.16, 0.84, 0.36, 0.50)],
    "R": [(0.00, 0.15, 0.00, 1.00), (0.15, 0.88, 0.84, 1.00),
          (0.15, 0.88, 0.43, 0.57), (0.84, 1.00, 0.57, 0.84),
          (0.30, 0.55, 0.00, 0.46)],
    "S": [(0.00, 1.00, 0.83, 1.00), (0.00, 0.15, 0.50, 0.83),
          (0.00, 1.00, 0.44, 0.56), (0.85, 1.00, 0.16, 0.50),
          (0.00, 1.00, 0.00, 0.16)],
    "C": [(0.15, 1.00, 0.86, 1.00), (0.00, 0.15, 0.14, 0.86),
          (0.15, 1.00, 0.00, 0.14)],
    "K": [(0.00, 0.15, 0.00, 1.00), (0.15, 1.00, 0.34, 0.46),
          (0.40, 0.58, 0.46, 1.00)],
    "I": [(0.36, 0.64, 0.00, 1.00)],
    " ": [],
}


def _text(g, axis, t0, t1, chars, u0, v0, w, h, gap=0.30, role=EMIT, cell=E_COLD,
          u_sign=1):
    """把字母按笔画铺到一个平面上（axis 为该面的法线轴）。

    u0/v0 是整串文字的**左下角**；w 是单字宽，h 是字高；gap 是字距（× w）。
    字符竖向堆叠（竖招牌）由调用方逐字给 v0。

    u_sign：文字横轴方向。**站在 +X 侧看向 -X 时 +Y 在右手边 → u_sign=+1**；
    站在 -X 侧看向 +X 时 +Y 在**左手边** → 必须 u_sign=-1，否则整串字左右反写。
    （实测：BAR 招牌挂在东立面、从街心看是 -X 侧，用 +1 时 B 的竖画跑到右边。）
    不要用「实例 rz=180 + 反向镜像」来绕：那会把 +Y 一起翻，问题只是藏起来。
    """
    cw = w
    for ch in chars:
        for (a0, a1, b0, b1) in STROKES.get(ch, []):
            aa0, aa1 = u0 + a0 * cw, u0 + a1 * cw
            if u_sign < 0:
                aa0, aa1 = -aa1, -aa0
            bb0, bb1 = v0 + b0 * h, v0 + b1 * h
            if axis == "x":
                g.box(t0, t1, aa0, aa1, bb0, bb1, role, cell)
            else:
                g.box(aa0, aa1, t0, t1, bb0, bb1, role, cell)
        u0 += cw + gap * cw


def _stairs(g, x0, x1, y0, y1, z0, z1, n, role, cell):
    """阶梯块（踏步）：用于消防梯、入口台阶。沿 z 分层、每层向 y1 收缩。"""
    for i in range(n):
        za = z0 + (z1 - z0) * i / n
        zb = z0 + (z1 - z0) * (i + 1) / n
        yy = y1 - (y1 - y0) * i / n
        g.box(x0, x1, yy, y1, za, zb, role, cell)


def _zigzag_stair(g, x, y0, y1, z0, z1, floors, role, cell, depth=0.9, rail=True):
    """消防梯：每层一段斜梯（阶梯块）+ 平台 + 栏杆。挂在立面 x 之外。"""
    for f in range(floors):
        za = z0 + (z1 - z0) * f / floors
        zb = z0 + (z1 - z0) * (f + 1) / floors
        # 平台
        g.box(x, x + depth, y0, y1, zb - 0.10, zb, role, cell)
        if rail:
            g.box(x + depth - 0.05, x + depth, y0, y1, zb, zb + 0.95, role, cell)
            g.box(x, x + depth, y1 - 0.05, y1, zb, zb + 0.95, role, cell)
            g.box(x, x + depth, y0, y0 + 0.05, zb, zb + 0.95, role, cell)
            for k in range(4):
                g.box(x + depth - 0.06, x + depth - 0.01, y0, y1,
                      zb + 0.18 + k * 0.24, zb + 0.20 + k * 0.24, role, cell)
        # 斜梯（阶梯块从平台下到下一平台）
        steps = 7
        for s in range(steps):
            sy = y0 + (y1 - y0) * s / steps
            sy2 = y0 + (y1 - y0) * (s + 1) / steps
            zz = zb - (zb - za) * (s + 1) / steps
            g.box(x, x + 0.42, sy, sy2, zz, zz + 0.05, role, cell)


# ================================================================ 酒店楼（v003 深化）

HT_X0, HT_X1 = -5.0, 5.0
HT_Y0, HT_Y1 = -6.0, 6.0
HT_TOP = 25.80
HT_SKIN = 0.50
HT_ROWS = (4.30, 8.70, 13.10, 17.50, 21.90)     # 五层窗台
HT_WIN_H = 2.55
HT_COLS = (-2.90, 0.40, 3.70)                    # 正立面三列（局部 y）
HT_WIN_W = 1.90


def c_hotel_tower_detail(g):
    """红褐砖石酒店 10×12×26m（正立面 +X 朝街），参考图左侧主体。

    立面竖向节奏：石砌基座 0–3.45 → 门头/雨棚 3.45–4.30 → 五层拱窗（层高 4.40）
    → 叠涩檐口 25.30–26.30 → 女儿墙 26.30–27.10 → 屋顶水箱/楼梯间/天线。
    细节密度：齐缝砖（步距 0.75）、壁柱（4 道 + 柱头）、窗台两级、拱券六级阶梯、
    消防梯（每层平台 + 斜梯 + 栏杆）、落水管、墙挂空调、屋顶设备。
    """
    F = HT_X1
    S = HT_SKIN

    ops = []
    # 一层门头（卷帘/玻璃门并入本体，不再单独实例化）
    ops.append(dict(face="+X", a0=-2.60, a1=3.40, z0=0.0, z1=3.45))
    # 正立面五层 × 三列拱窗
    for z0 in HT_ROWS:
        for cy in HT_COLS:
            ops.append(dict(face="+X", a0=cy - HT_WIN_W / 2, a1=cy + HT_WIN_W / 2,
                            z0=z0, z1=z0 + HT_WIN_H))
    # 南立面（-Y）三层 × 两列：镜头在南侧，这是第二可见面
    for z0 in (8.70, 13.10, 17.50):
        for cx in (-2.90, 0.50):
            ops.append(dict(face="-Y", a0=cx - 0.95, a1=cx + 0.95, z0=z0, z1=z0 + HT_WIN_H))
    # 背立面（-X）每层两个小窗：远看不见，但俯视时能看出"这栋楼是通透的"
    for z0 in (8.70, 13.10, 17.50, 21.90):
        for cy in (-2.2, 2.2):
            ops.append(dict(face="-X", a0=cy - 0.55, a1=cy + 0.55, z0=z0, z1=z0 + 1.5))

    _shell(g, HT_X0, HT_X1, HT_Y0, HT_Y1, 0.0, HT_TOP, S, ops, H_D2, H_D0,
           faces=("+X", "-X", "-Y"))
    # 北立面（+Y）朝街内侧、被背景楼遮住：只做 0.50 厚实墙，不开洞
    _wall_panel(g, "x", HT_Y1 - S, HT_Y1, HT_X0 + S, HT_X1 - S, 0.0, HT_TOP, [],
                MATTE, H_D1)

    # ------------------------------------------------ 1. 石砌基座（0–3.45）
    g.box(HT_X0 - 0.04, F + 0.10, HT_Y0 - 0.10, HT_Y1 + 0.10, 0.0, 3.45, MATTE, H_D1)
    zz = 0.30
    while zz < 3.35:
        g.box(F + 0.08, F + 0.135, HT_Y0 - 0.10, HT_Y1 + 0.10, zz, zz + SEAM, MATTE, N_INK)
        zz += 0.62
    # 竖向错缝（每 1.24m 一道，错开半块）
    yy = HT_Y0 - 0.06
    k = 0
    while yy < HT_Y1 + 0.04:
        g.box(F + 0.08, F + 0.135, yy, yy + SEAM, 0.30, 3.35, MATTE, N_INK)
        yy += 1.24
        k += 1
    # 基座压顶（两级，上口最亮）
    g.box(F - 0.04, F + 0.20, HT_Y0 - 0.14, HT_Y1 + 0.14, 3.30, 3.45, METAL, H_D5)
    g.box(F + 0.16, F + 0.20, HT_Y0 - 0.14, HT_Y1 + 0.14, 3.30, 3.45, METAL, H_D7)

    # ------------------------------------------------ 2. 门头（玻璃门 + 卷帘 + 雨棚）
    g.box(F - S, F - 0.06, -2.60, 3.40, 0.0, 3.45, MATTE, H_D0)      # 洞内暗腔
    # 卷帘（右侧 2/3 落下 1.95m，左侧玻璃门）
    for i in range(15):
        z = 0.10 + i * 0.125
        g.box(F - 0.10, F + 0.02, 0.45, 3.28, z, z + 0.085, METAL,
              H_D5 if i % 2 else H_D3)
    g.box(F - 0.10, F + 0.03, 0.45, 3.28, 1.92, 2.02, METAL, H_D6)   # 帘底压条
    # 玻璃门 + 门框（左段）
    g.box(F - 0.24, F - 0.20, -2.44, 0.28, 0.02, 2.92, GLOSS, T_GLASS)
    g.box(F - 0.26, F - 0.22, -2.30, 0.14, 2.30, 2.88, EMIT, E_ICE)
    for (a0, a1) in ((-2.60, -2.46), (-2.46, 0.30), (0.30, 0.45)):
        g.box(F - 0.28, F + 0.05, a0, a1, 0.0, 3.02, METAL, H_D6)
    g.box(F - 0.28, F + 0.05, -2.60, 0.45, 2.92, 3.06, METAL, H_D6)
    # 门把手 + 门牌
    g.cyl_x(F - 0.18, F - 0.10, -0.30, 1.10, 0.028, METAL, H_D7, seg=6)
    g.box(F + 0.02, F + 0.05, -2.05, -1.55, 1.55, 1.85, EMIT, E_WARM)
    # 雨棚（出挑 0.95，底面加劲肋 + 灯带）
    g.prism([(F - 0.02, -2.72), (F + 0.95, -2.72), (F + 0.95, 3.50), (F - 0.02, 3.50)],
            3.50, 3.60, MATTE, H_D3)
    g.box(F + 0.86, F + 0.98, -2.72, 3.50, 3.32, 3.60, MATTE, H_D1)
    g.box(F + 0.92, F + 0.98, -2.72, 3.50, 3.32, 3.60, MATTE, N_INK)
    for k in range(6):
        yy = -2.56 + k * 1.14
        g.beam((F + 0.02, yy, 3.56), (F + 0.92, yy, 3.52), 0.05, 0.05, METAL, H_D5)
        g.beam((F + 0.04, yy, 3.52), (F + 0.38, yy, 3.92), 0.045, 0.045, METAL, H_D5)
    g.box(F + 0.78, F + 0.90, -2.50, 3.28, 3.30, 3.36, EMIT, E_WARM)
    # 台阶 + 防滑条
    g.box(F + 0.02, F + 0.52, -2.70, 3.48, 0.0, 0.10, MATTE, H_D2)
    g.box(F + 0.42, F + 0.52, -2.70, 3.48, 0.055, 0.10, METAL, H_D6)
    for k in range(7):
        g.box(F + 0.10, F + 0.48, -2.50 + k * 0.84, -2.44 + k * 0.84, 0.10, 0.115,
              METAL, N_INK)

    # ------------------------------------------------ 3. 壁柱（4 道，出挑 0.16）
    piers = [(HT_Y0, -3.90), (-1.90, -0.60), (1.40, 2.70), (4.70, HT_Y1)]
    for (ya, yb) in piers:
        g.box(F - 0.02, F + 0.16, ya, yb, 3.45, HT_TOP, MATTE, H_D3)
        g.box(F + 0.11, F + 0.185, ya, ya + SEAM, 3.45, HT_TOP, MATTE, N_INK)
        g.box(F + 0.11, F + 0.185, yb - SEAM, yb, 3.45, HT_TOP, MATTE, N_INK)
        # 柱头托块（每层一道）
        for z0 in HT_ROWS:
            g.box(F - 0.02, F + 0.24, ya - 0.05, yb + 0.05, z0 - 0.34, z0 - 0.16,
                  METAL, H_D4)
            g.box(F + 0.19, F + 0.24, ya - 0.05, yb + 0.05, z0 - 0.34, z0 - 0.16,
                  METAL, H_D6)

    # ------------------------------------------------ 4. 齐缝砖（只在壁柱之间的墙面）
    for (ya, yb) in piers:
        pass
    bands = [(-3.90, -1.90), (-0.60, 1.40), (2.70, 4.70), (HT_Y0, -3.90)]
    for (ya, yb) in bands:
        if yb - ya < 0.3:
            continue
        zz = 3.55
        while zz < 25.10:
            # 避让窗洞：窗洞区（含窗台 0.2 与拱顶）不铺砖
            blocked = False
            for z0 in HT_ROWS:
                if z0 - 0.30 < zz < z0 + HT_WIN_H + 0.95:
                    blocked = True
                    break
            if not blocked:
                g.box(F + 0.005, F + 0.045, ya, yb, zz, zz + 0.035, MATTE, H_D2)
            zz += 0.75

    # ------------------------------------------------ 5. 层间腰线（每层一道）
    for z0 in HT_ROWS:
        zb = z0 - 0.30
        g.box(F - 0.02, F + 0.14, HT_Y0, HT_Y1, zb, zb + 0.16, METAL, H_D4)
        g.box(F + 0.10, F + 0.14, HT_Y0, HT_Y1, zb, zb + 0.16, METAL, H_D6)
        g.box(F + 0.10, F + 0.14, HT_Y0, HT_Y1, zb - 0.07, zb, MATTE, N_INK)

    # ------------------------------------------------ 6. 拱窗（五层 × 三列）
    for z0 in HT_ROWS:
        for cy in HT_COLS:
            _win(g, "x", +1, F, cy - HT_WIN_W / 2, cy + HT_WIN_W / 2,
                 z0, z0 + HT_WIN_H, lit=(z0 in (8.70, 17.50) and cy in (-2.90, 3.70)),
                 cell_lit=E_WARM if z0 != 17.50 else E_ICE,
                 arch=0.85, arch_cell=E_DIM, frame_cell=H_D4,
                 band_cell=H_D4, cap_cell=H_D6)
    # 南立面两列
    for z0 in (8.70, 13.10, 17.50):
        for cx in (-2.90, 0.50):
            _win(g, "y", -1, HT_Y0, cx - 0.95, cx + 0.95, z0, z0 + HT_WIN_H,
                 lit=(z0 == 13.10 and cx == 0.50), arch=0.80, frame_cell=H_D4,
                 band_cell=H_D4, cap_cell=H_D6)
    # 背立面小窗（只做玻璃，不做框）
    for z0 in (8.70, 13.10, 17.50, 21.90):
        for cy in (-2.2, 2.2):
            g.box(HT_X0 + 0.42, HT_X0 + 0.46, cy - 0.55, cy + 0.55, z0, z0 + 1.5,
                  GLOSS, T_GLASS)

    # ------------------------------------------------ 7. 檐口（三级叠涩 + 托块）
    for (za, zb, out, cell) in ((25.10, 25.50, 0.22, H_D5),
                                (25.50, 25.85, 0.36, H_D6),
                                (25.85, 26.10, 0.48, H_D7)):
        g.box(HT_X0 - out * 0.6, F + out, HT_Y0 - out * 0.6, HT_Y1 + out, za, zb, METAL, cell)
    # 檐下阴影 + 托块
    g.box(F - 0.02, F + 0.06, HT_Y0, HT_Y1, 24.86, 25.10, MATTE, N_INK)
    yy = HT_Y0 + 0.18
    while yy < HT_Y1 - 0.30:
        g.box(F + 0.04, F + 0.26, yy, yy + 0.16, 24.86, 25.10, METAL, H_D4)
        g.box(F + 0.22, F + 0.26, yy, yy + 0.16, 24.86, 25.10, METAL, H_D6)
        yy += 0.92

    # ------------------------------------------------ 8. 女儿墙（四面 + 压顶 + 分仓缝）
    for (x0, x1, y0, y1) in ((F - 0.42, F, HT_Y0, HT_Y1),
                             (HT_X0, HT_X0 + 0.42, HT_Y0, HT_Y1),
                             (HT_X0, F, HT_Y0, HT_Y0 + 0.42),
                             (HT_X0, F, HT_Y1 - 0.42, HT_Y1)):
        g.box(x0, x1, y0, y1, 26.10, 27.10, MATTE, H_D2)
    g.box(F - 0.50, F + 0.08, HT_Y0 - 0.08, HT_Y1 + 0.08, 27.10, 27.24, METAL, H_D6)
    g.box(F - 0.04, F + 0.08, HT_Y0 - 0.08, HT_Y1 + 0.08, 27.10, 27.24, METAL, H_D7)
    g.box(HT_X0 - 0.08, HT_X0 + 0.50, HT_Y0 - 0.08, HT_Y1 + 0.08, 27.10, 27.24,
          METAL, H_D6)
    g.box(HT_X0 - 0.08, F + 0.08, HT_Y0 - 0.08, HT_Y0 + 0.50, 27.10, 27.24, METAL, H_D6)
    g.box(HT_X0 - 0.08, F + 0.08, HT_Y1 - 0.50, HT_Y1 + 0.08, 27.10, 27.24, METAL, H_D6)
    yy = HT_Y0 + 1.4
    while yy < HT_Y1 - 0.2:
        g.box(F + 0.01, F + 0.07, yy, yy + SEAM, 26.10, 27.10, MATTE, N_INK)
        yy += 1.4

    # ------------------------------------------------ 9. 消防梯（南立面，逐层平台 + 斜梯）
    _zigzag_stair(g, HT_Y0 - 0.95, F - 2.60, F - 0.90, 3.45, 24.90, 5,
                  METAL, H_D4, depth=0.95)

    # ------------------------------------------------ 10. 立面附着：落水管 / 空调 / 线束盒
    for yy in (HT_Y0 + 0.16, HT_Y1 - 0.16):
        V2._vpipe(g, F + 0.22, yy, 0.10, 27.20, 0.095, METAL, H_D5,
                  clamps=9, cell_clamp=H_D7)
        g.box(F + 0.16, F + 0.34, yy - 0.10, yy + 0.10, 0.02, 0.20, METAL, H_D6)
    # 墙挂空调（每层两组，出挑 0.62）
    # 空调机只挂在**层间实墙带**（窗顶 6.85 与下一层腰线 8.40 之间）。
    # 原来写 5.20/9.60/14.00/18.40，全部落在窗洞里，把拱窗劈成两半（实测）。
    for z0 in (7.00, 11.40, 15.80, 20.20):
        for cy in (-1.25, 1.90):
            ax0, ax1 = F, F + 0.62
            ay0, ay1 = cy - 0.48, cy + 0.48
            for yy in (ay0 + 0.14, ay1 - 0.14):
                g.beam((F + 0.02, yy, z0 - 0.02), (ax1 - 0.08, yy, z0 + 0.10), 0.055, 0.055,
                       METAL, H_D5)
                g.beam((F + 0.02, yy, z0 - 0.46), (ax1 - 0.10, yy, z0), 0.045, 0.045,
                       METAL, N_INK)
            g.box(ax0 + 0.04, ax1, ay0, ay1, z0, z0 + 0.68, METAL, H_D3)
            zz2 = z0 + 0.08
            while zz2 < z0 + 0.62:
                g.box(ax1, ax1 + 0.04, ay0 + 0.08, ay1 - 0.08, zz2, zz2 + 0.03,
                      METAL, H_D5)
                zz2 += 0.065
            g.box(ax1 + 0.04, ax1 + 0.07, ay0 + 0.08, ay1 - 0.08, z0 + 0.08, z0 + 0.62,
                  MATTE, N_INK)
            g.cyl(F + 0.18, ay1 - 0.10, 0.10, z0 - 0.02, 0.026, METAL, H_D6, seg=6)
    # 电表箱 + 明装线管（一层右侧实墙）
    g.box(F + 0.02, F + 0.22, 3.50, 4.30, 1.10, 2.10, METAL, H_D3)
    g.box(F + 0.20, F + 0.225, 3.54, 4.26, 1.14, 2.06, METAL, H_D5)
    g.box(F + 0.225, F + 0.25, 3.56, 3.74, 1.70, 1.76, EMIT, E_WARM)
    for yy in (3.62, 4.06):
        g.cyl(F + 0.16, yy, 2.10, 3.45, 0.024, METAL, H_D5, seg=6)

    # ------------------------------------------------ 11. 屋顶：水箱 / 楼梯间 / 天线 / 风机
    g.box(HT_X0 + 0.30, F - 0.34, HT_Y0 + 0.30, HT_Y1 - 0.30, HT_TOP, HT_TOP + 0.10,
          MATTE, H_D2)
    g.box(F - 0.42, F - 0.34, HT_Y0 + 0.30, HT_Y1 - 0.30, HT_TOP + 0.10, HT_TOP + 0.30,
          METAL, H_D5)
    # 水箱（支腿 + 筒身 + 三道箍 + 爬梯）
    TX, TY, TR = 1.30, 2.10, 1.42
    TZ0 = HT_TOP + 0.10
    TZ1 = TZ0 + 1.85
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        g.box(TX + sx * 0.90 - 0.07, TX + sx * 0.90 + 0.07,
              TY + sy * 0.90 - 0.07, TY + sy * 0.90 + 0.07, TZ0, TZ0 + 0.62, METAL, H_D5)
    g.cyl(TX, TY, TZ0 + 0.60, TZ1, TR, METAL, H_D3, seg=14)
    for zz2 in (TZ0 + 0.78, TZ0 + 1.18, TZ1 - 0.16):
        g.cyl(TX, TY, zz2, zz2 + 0.07, TR + 0.05, METAL, H_D6, seg=14)
    g.cyl(TX, TY, TZ1, TZ1 + 0.16, TR * 0.98, METAL, H_D6, seg=14, r2=TR * 0.5)
    for sx in (-0.20, 0.20):
        g.cyl(TX - TR - 0.14 + sx, TY - 0.34, TZ0, TZ1 + 0.22, 0.030, METAL, H_D6, seg=5)
    for k in range(8):
        g.box(TX - TR - 0.20, TX - TR - 0.02, TY - 0.375, TY - 0.305,
              TZ0 + 0.08 + k * 0.235, TZ0 + 0.112 + k * 0.235, METAL, H_D7)
    # 楼梯间
    g.box(-3.60, -0.90, 1.00, 4.40, HT_TOP + 0.10, HT_TOP + 1.95, MATTE, H_D1)
    g.box(-3.68, -0.82, 0.92, 4.48, HT_TOP + 1.95, HT_TOP + 2.05, METAL, H_D6)
    g.box(-0.90, -0.85, 1.55, 3.85, HT_TOP + 0.10, HT_TOP + 1.10, METAL, H_D4)
    g.box(-0.86, -0.80, 1.62, 3.78, HT_TOP + 1.16, HT_TOP + 1.24, EMIT, E_WARM)
    for k in range(3):
        g.box(-0.86, -0.82, 1.05, 4.35, HT_TOP + 0.30 + k * 0.42,
              HT_TOP + 0.32 + k * 0.42, MATTE, N_INK)
    # 风机两台
    for (fx, fy) in ((-2.60, -2.60), (-2.60, -0.60)):
        g.box(fx - 0.62, fx + 0.62, fy - 0.52, fy + 0.52, HT_TOP + 0.10, HT_TOP + 0.66,
              METAL, H_D3)
        g.cyl(fx, fy, HT_TOP + 0.66, HT_TOP + 0.74, 0.36, METAL, H_D6, seg=10)
        g.cyl(fx, fy, HT_TOP + 0.74, HT_TOP + 0.78, 0.28, EMIT, E_DIM, seg=10)
    # 天线 + 拉线 + 顶灯
    g.cyl(3.10, -3.20, HT_TOP + 0.10, HT_TOP + 2.60, 0.055, METAL, H_D6, seg=6)
    for zz2 in (HT_TOP + 0.90, HT_TOP + 1.50, HT_TOP + 2.10):
        g.box(2.70, 3.50, -3.22, -3.18, zz2, zz2 + 0.04, METAL, H_D7)
    g.cyl(3.10, -3.20, HT_TOP + 2.60, HT_TOP + 2.72, 0.09, EMIT, E_PINK, seg=6)
    for (dx, dy) in ((-1.8, 1.2), (1.8, -1.4)):
        g.beam((3.10, -3.20, HT_TOP + 2.20), (3.10 + dx, -3.20 + dy, HT_TOP + 0.14),
               0.022, 0.022, METAL, N_INK)


def c_hotel_sign_detail(g):
    """HOTEL 竖招牌：几何笔画逐字母（局部 +X 朝街，原点在墙面）。"""
    W, D = 2.10, 0.46
    H = 12.30
    # 背板 + 四侧板（灯箱腔朝 +X）
    g.box(0.00, 0.06, -W / 2, W / 2, 0.0, H, METAL, H_D1)
    for (y0, y1, z0, z1) in ((-W / 2, -W / 2 + 0.09, 0.0, H), (W / 2 - 0.09, W / 2, 0.0, H),
                             (-W / 2, W / 2, 0.0, 0.10), (-W / 2, W / 2, H - 0.10, H)):
        g.box(0.00, D, y0, y1, z0, z1, METAL, H_D3)
    # 面板（中调，不发光：发光会把字糊平）
    g.box(D - 0.06, D - 0.02, -W / 2 + 0.10, W / 2 - 0.10, 0.12, H - 0.12, GLOSS, H_D2)
    g.box(D - 0.065, D - 0.058, -W / 2 + 0.13, W / 2 - 0.13, 0.15, H - 0.15, MATTE, N_INK)
    # 五个字母竖向堆叠，整串居中（先算总高再定位）。
    # 上一版按 (i+1)*(lh+gap) 累加，最后一个字母顶出面板上沿，H 被裁掉半个。
    lw, lh, gap = 1.26, 1.86, 0.36
    total = 5 * lh + 4 * gap
    z_base = (H - total) * 0.5
    for i, ch in enumerate("HOTEL"):
        v0 = z_base + (4 - i) * (lh + gap)
        _text(g, "x", D - 0.058, D - 0.012, ch, -lw / 2, v0, lw, lh, role=EMIT, cell=E_ICE)
    # 外框（出挑最远）+ 螺栓
    for (y0, y1, z0, z1) in ((-W / 2, W / 2, H - 0.14, H), (-W / 2, W / 2, 0.0, 0.14),
                             (-W / 2, -W / 2 + 0.14, 0.0, H), (W / 2 - 0.14, W / 2, 0.0, H)):
        g.box(D - 0.04, D + 0.10, y0, y1, z0, z1, METAL, H_D6)
    for yy in (-W / 2 + 0.22, W / 2 - 0.22):
        for zz in (0.30, H - 0.30, H * 0.5):
            g.cyl_x(D + 0.10, D + 0.135, yy, zz, 0.036, METAL, H_D7, seg=6)
    # 顶部遮雨檐 + 挂装臂
    g.box(0.00, D + 0.30, -W / 2 - 0.08, W / 2 + 0.08, H, H + 0.09, METAL, H_D6)
    g.box(D + 0.24, D + 0.30, -W / 2 - 0.08, W / 2 + 0.08, H - 0.09, H, MATTE, N_INK)
    for zz in (0.60, H * 0.55, H - 0.60):
        g.beam((-0.02, 0.0, zz), (0.14, 0.0, zz), 0.09, 0.09, METAL, H_D5)
        g.beam((-0.02, 0.0, zz - 0.42), (0.16, 0.0, zz - 0.04), 0.055, 0.055, METAL, H_D5)


# ================================================================ 酒吧楼（v003 深化）

BR_X0, BR_X1 = -5.0, 5.0
BR_Y0, BR_Y1 = -6.0, 6.0
BR_TOP = 18.30
BR_SKIN = 0.40
BR_ROWS = (5.20, 9.40, 13.60)
BR_COLS = (-4.30, -2.10, 0.40, 2.90)


def c_bar_building_detail(g):
    """深灰金属板工业酒吧 10×12×18m（正立面 -X 朝街），参考图右侧。

    工业语法：竖向肋板（步距 0.72，出挑 0.14）、横向箍带（三道）、铆钉阵列、
    窗下锈痕、明装管束 + 分线盒、屋顶烟囱（带红色顶灯）、消防梯。
    窗是**窄缝窗**（1.05 宽），不是为了好看——工业楼本来就是窄缝采光。
    """
    F = BR_X0
    S = BR_SKIN

    ops = [dict(face="-X", a0=-1.70, a1=1.70, z0=0.0, z1=3.30)]
    for z0 in BR_ROWS:
        for cy in BR_COLS:
            ops.append(dict(face="-X", a0=cy - 0.52, a1=cy + 0.52, z0=z0, z1=z0 + 1.55))
    # 南立面（-Y，镜头可见）三层两列
    for z0 in (5.20, 9.40, 13.60):
        for cx in (-2.80, 0.60):
            ops.append(dict(face="-Y", a0=cx - 0.52, a1=cx + 0.52, z0=z0, z1=z0 + 1.55))

    _shell(g, BR_X0, BR_X1, BR_Y0, BR_Y1, 0.0, BR_TOP, S, ops, B_D3, N_INK,
           faces=("-X", "-Y", "+X"))
    _wall_panel(g, "x", BR_Y1 - S, BR_Y1, BR_X0 + S, BR_X1 - S, 0.0, BR_TOP, [],
                MATTE, B_D2)

    # ------------------------------------------------ 1. 竖向肋板（正立面）
    # 肋板：步距 1.05（0.72 时读成栅栏），且**分段**（8.30–9.40 留实墙）。
    # 通高肋板 + 通高暗缝 = 铁栅栏；分段之后才读成"板墙 + 加劲肋"。
    # 肋板本身只比墙面亮一档（B_D4 vs B_D3），靠出挑 0.10 的阴影出形，不靠颜色。
    yy = BR_Y0 + 0.10
    while yy < BR_Y1 - 0.20:
        for (za, zb) in ((0.0, 8.30), (9.40, BR_TOP)):
            g.box(F - 0.10, F + 0.02, yy, yy + 0.14, za, zb, METAL, B_D4)
            g.box(F - 0.105, F - 0.09, yy, yy + 0.02, za, zb, MATTE, N_INK)
        # 中段实墙（肋板断开处）：故意不提亮，读成"这里是两块板对接"
        g.box(F - 0.012, F, yy, yy + 0.14, 8.30, 9.40, MATTE, B_D2)
        yy += 1.05
    # ------------------------------------------------ 2. 横向箍带（三道）+ 铆钉
    for zc in (4.40, 8.60, 12.80, 17.20):
        g.box(F - 0.20, F + 0.02, BR_Y0, BR_Y1, zc, zc + 0.30, METAL, B_D3)
        g.box(F - 0.205, F - 0.19, BR_Y0, BR_Y1, zc, zc + 0.30, MATTE, N_INK)
        g.box(F - 0.20, F - 0.16, BR_Y0, BR_Y1, zc + 0.22, zc + 0.30, METAL, B_D6)
        yy = BR_Y0 + 0.22
        while yy < BR_Y1 - 0.10:
            for zz in (zc + 0.06, zc + 0.24):
                g.box(F - 0.20, F - 0.16, yy, yy + 0.09, zz, zz + 0.09, METAL, B_D6)
            yy += 1.05
    # 竖向肋板与箍带交点的角码
    for zc in (4.40, 8.60, 12.80, 17.20):
        yy = BR_Y0 + 0.22
        while yy < BR_Y1 - 0.20:
            g.box(F - 0.195, F - 0.12, yy - 0.04, yy + 0.14, zc - 0.06, zc + 0.02,
                  METAL, B_D4)
            yy += 2.10

    # ------------------------------------------------ 3. 底层入口（凹入 + 门槛 + 灯棚）
    g.box(F - S, F - 0.05, -1.70, 1.70, 0.0, 3.30, MATTE, N_INK)
    g.box(F - 0.26, F - 0.22, -1.56, 1.56, 0.02, 3.10, GLOSS, T_GLASS)
    g.box(F - 0.28, F - 0.24, -1.40, 1.40, 2.40, 3.05, EMIT, E_DIM)
    for (a0, a1) in ((-1.70, -1.56), (-0.10, 0.04), (1.56, 1.70)):
        g.box(F - 0.30, F + 0.04, a0, a1, 0.0, 3.20, METAL, B_D5)
    g.box(F - 0.30, F + 0.04, -1.70, 1.70, 3.10, 3.24, METAL, B_D5)
    g.box(F - 0.30, F + 0.04, -1.70, 1.70, 0.0, 0.06, METAL, B_D6)
    # 门头灯棚（出挑 0.7，底面一条红霓虹）
    g.prism([(F - 0.02, -1.90), (F - 0.72, -1.90), (F - 0.72, 1.90), (F - 0.02, 1.90)],
            3.30, 3.42, MATTE, B_D3)
    g.box(F - 0.70, F - 0.62, -1.80, 1.80, 3.22, 3.28, EMIT, E_PINK)
    for k in range(5):
        g.beam((F - 0.02, -1.70 + k * 0.85, 3.36), (F - 0.68, -1.70 + k * 0.85, 3.32),
               0.05, 0.05, METAL, B_D5)
    # 门槛台阶
    g.box(F - 0.62, F + 0.02, -1.86, 1.86, 0.0, 0.08, MATTE, B_D2)
    g.box(F - 0.62, F - 0.54, -1.86, 1.86, 0.05, 0.08, METAL, B_D6)

    # ------------------------------------------------ 4. 窄缝窗内衬（朝 -X）
    for z0 in BR_ROWS:
        for cy in BR_COLS:
            _win(g, "x", -1, F, cy - 0.52, cy + 0.52, z0, z0 + 1.55,
                 lit=((zz := z0) in (5.20, 13.60) and cy in (-4.30, 0.40)),
                 cell_lit=E_PINK if z0 == 5.20 else E_ICE,
                 cell_dark=T_GLASS, mull=1, transom=False, frame_cell=B_D6,
                 grime=False, band_cell=B_D5, cap_cell=B_D7)
    # 南立面
    for z0 in (5.20, 9.40, 13.60):
        for cx in (-2.80, 0.60):
            _win(g, "y", -1, BR_Y0, cx - 0.52, cx + 0.52, z0, z0 + 1.55,
                 lit=(z0 == 9.40 and cx == 0.60), mull=1, transom=False,
                 frame_cell=B_D6, grime=False, band_cell=B_D5, cap_cell=B_D7)

    # ------------------------------------------------ 5. 窗下锈痕 + 板缝污渍（只在窗下）
    for z0 in BR_ROWS:
        for cy in BR_COLS:
            g.box(F - 0.155, F - 0.145, cy - 0.42, cy + 0.42, z0 - 0.72, z0 - 0.02,
                  MATTE, B_D1)
            g.box(F - 0.16, F - 0.148, cy - 0.10, cy - 0.02, z0 - 1.30, z0 - 0.02,
                  MATTE, B_D0)

    # ------------------------------------------------ 6. 明装管束 + 分线盒（正立面两侧）
    for yy, z0, z1 in ((BR_Y0 + 0.30, 0.10, 17.60), (BR_Y1 - 0.30, 0.10, 17.60)):
        for k in range(3):
            g.cyl(F - 0.24 - k * 0.055, yy + k * 0.06, z0, z1, 0.030, METAL, B_D5, seg=6)
        for zz in (2.20, 6.40, 10.60, 14.80):
            g.box(F - 0.30, F - 0.16, yy - 0.10, yy + 0.16, zz, zz + 0.09, METAL, B_D6)
        g.box(F - 0.32, F - 0.14, yy - 0.14, yy + 0.20, 17.60, 18.14, METAL, B_D4)
        g.box(F - 0.34, F - 0.30, yy - 0.04, yy + 0.10, 17.70, 17.78, EMIT, E_WARM)
    # 分线盒 + 下引线
    g.box(F - 0.34, F - 0.14, -0.60, 0.30, 6.60, 7.60, METAL, B_D3)
    g.box(F - 0.36, F - 0.32, -0.56, 0.26, 6.66, 7.54, METAL, B_D5)
    g.box(F - 0.36, F - 0.33, -0.50, -0.30, 7.10, 7.16, EMIT, E_WARM)

    # ------------------------------------------------ 7. 檐口 + 女儿墙
    g.box(F - 0.22, BR_X1 - 0.10, BR_Y0 - 0.10, BR_Y1 + 0.10, BR_TOP - 0.30, BR_TOP - 0.10,
          METAL, B_D4)
    g.box(F - 0.30, BR_X1 - 0.06, BR_Y0 - 0.16, BR_Y1 + 0.16, BR_TOP - 0.10, BR_TOP,
          METAL, B_D6)
    for (x0, x1, y0, y1) in ((F, F + 0.36, BR_Y0, BR_Y1),
                             (BR_X1 - 0.36, BR_X1, BR_Y0, BR_Y1),
                             (F, BR_X1, BR_Y0, BR_Y0 + 0.36),
                             (F, BR_X1, BR_Y1 - 0.36, BR_Y1)):
        g.box(x0, x1, y0, y1, BR_TOP, BR_TOP + 0.85, MATTE, B_D2)
    g.box(F - 0.02, BR_X1, BR_Y0 - 0.06, BR_Y1 + 0.06, BR_TOP + 0.85, BR_TOP + 0.97,
          METAL, B_D6)

    # ------------------------------------------------ 8. 屋顶：烟囱 / 排风机 / 桥架 / 天线
    g.box(F + 0.30, BR_X1 - 0.30, BR_Y0 + 0.30, BR_Y1 - 0.30, BR_TOP, BR_TOP + 0.08,
          MATTE, B_D2)
    g.cyl(2.20, -3.40, BR_TOP + 0.08, BR_TOP + 4.30, 0.58, METAL, B_D3, seg=12)
    for zz in (BR_TOP + 1.20, BR_TOP + 2.40, BR_TOP + 3.60):
        g.cyl(2.20, -3.40, zz, zz + 0.10, 0.64, METAL, B_D6, seg=12)
    g.cyl(2.20, -3.40, BR_TOP + 4.30, BR_TOP + 4.50, 0.78, METAL, B_D4, seg=12)
    g.cyl(2.20, -3.40, BR_TOP + 4.50, BR_TOP + 4.62, 0.50, EMIT, E_PINK, seg=12)
    for (fx, fy) in ((-2.40, 1.80), (-2.40, 3.80)):
        g.box(fx - 0.60, fx + 0.60, fy - 0.50, fy + 0.50, BR_TOP + 0.08, BR_TOP + 0.62,
              METAL, B_D3)
        g.cyl(fx, fy, BR_TOP + 0.62, BR_TOP + 0.70, 0.34, METAL, B_D6, seg=10)
        g.cyl(fx, fy, BR_TOP + 0.70, BR_TOP + 0.74, 0.26, EMIT, E_DIM, seg=10)
    g.box(F + 0.40, BR_X1 - 0.40, 4.20, 4.44, BR_TOP + 0.08, BR_TOP + 0.26, METAL, B_D4)
    for x in (-3.2, -0.6, 2.0):
        g.box(x, x + 0.07, 4.16, 4.48, BR_TOP + 0.08, BR_TOP + 0.34, METAL, B_D6)
    g.cyl(-3.60, -4.40, BR_TOP + 0.08, BR_TOP + 2.30, 0.045, METAL, B_D6, seg=6)
    g.cyl(-3.60, -4.40, BR_TOP + 2.30, BR_TOP + 2.40, 0.075, EMIT, E_PINK, seg=6)

    # ------------------------------------------------ 9. 消防梯（南立面）+ 墙面风机
    _zigzag_stair(g, BR_Y0 - 0.90, F + 0.40, F + 2.40, 3.30, 17.20, 4,
                  METAL, B_D4, depth=0.90)
    for (fy, fz) in ((-3.2, 6.4), (-0.4, 11.0)):
        g.box(F - 0.22, F + 0.02, fy - 0.52, fy + 0.52, fz, fz + 1.04, METAL, B_D3)
        g.cyl(F - 0.20, fy, fz + 0.10, fz + 0.94, 0.42, METAL, B_D5, seg=10)
        for k in range(4):
            g.box(F - 0.24, F - 0.20, fy - 0.40, fy + 0.40, fz + 0.18 + k * 0.20,
                  fz + 0.22 + k * 0.20, METAL, N_INK)


def c_bar_sign_detail(g):
    """BAR 竖招牌：**朝 -X 构建**（局部 x∈[-D, 0]，x=0 贴墙）。

    为什么不再用「朝 +X 建 + 实例 rz=180」：
      rz=180 会把局部 +Y 一起翻转，几何上等于从背面看字，B 的竖画会跑到右边
      （实测渲染确认）。补一层 mirror 只是把镜像再镜像一次，容易在字形表改动时
      再次出错 —— 正确做法是**让招牌本来就朝 -X**，rz=0 即可，字天然正确。
      从 -X 侧看：上方 +Z、右手 +Y，所以 u 轴取 +Y 与观察者方向一致。
    """
    W, D, H = 1.70, 0.40, 6.40

    def B(x0, x1, y0, y1, z0, z1, role, cell):
        g.box(-x1, -x0, y0, y1, z0, z1, role, cell)

    def BC(x0, x1, y, z, r, role, cell, seg=6):
        g.cyl_x(-x1, -x0, y, z, r, role, cell, seg=seg)

    # 背板（贴墙）+ 四侧板
    B(0.00, 0.06, -W / 2, W / 2, 0.0, H, METAL, B_D1)
    for (y0, y1, z0, z1) in ((-W / 2, -W / 2 + 0.08, 0.0, H), (W / 2 - 0.08, W / 2, 0.0, H),
                             (-W / 2, W / 2, 0.0, 0.09), (-W / 2, W / 2, H - 0.09, H)):
        B(0.00, D, y0, y1, z0, z1, METAL, B_D3)
    # 面板（腔口在 x=-D 侧）+ 内压暗底
    B(D - 0.06, D - 0.02, -W / 2 + 0.09, W / 2 - 0.09, 0.11, H - 0.11, GLOSS, B_D2)
    B(D - 0.065, D - 0.058, -W / 2 + 0.12, W / 2 - 0.12, 0.14, H - 0.14, MATTE, N_INK)
    # 三个字母竖向堆叠、整串居中
    lw, lh, gap = 1.06, 1.32, 0.34
    total = 3 * lh + 2 * gap
    z_base = (H - total) * 0.5
    for i, ch in enumerate("BAR"):
        v0 = z_base + (2 - i) * (lh + gap)
        _text(g, "x", -(D - 0.012), -(D - 0.058), ch, -lw / 2, v0, lw, lh,
              role=EMIT, cell=E_PINK, u_sign=-1)
    # 外框（出挑最远：x = -D 再往 -x）+ 三处挂装臂
    for (y0, y1, z0, z1) in ((-W / 2, W / 2, H - 0.12, H), (-W / 2, W / 2, 0.0, 0.12),
                             (-W / 2, -W / 2 + 0.12, 0.0, H), (W / 2 - 0.12, W / 2, 0.0, H)):
        B(D - 0.04, D + 0.08, y0, y1, z0, z1, METAL, B_D6)
    for zz in (0.50, H * 0.5, H - 0.50):
        g.beam((0.02, 0.0, zz), (-0.14, 0.0, zz), 0.08, 0.08, METAL, B_D5)
        g.beam((0.02, 0.0, zz - 0.34), (-0.16, 0.0, zz - 0.03), 0.05, 0.05, METAL, B_D5)


# ================================================================ 背景楼（v003 深化）

BD_X0, BD_X1 = -5.0, 5.0
BD_Y0, BD_Y1 = -3.5, 3.5
BD_TOP = 27.20
BD_SKIN = 0.38


def c_backdrop_tower_detail(g):
    """背景高楼 10×7×27m（正立面 +X 朝街），v002 里是 194 面的空盒子。

    背景楼不需要像主体那样每层做构件，但必须做到三件事：
      ① 竖向壁柱 + 叠涩檐口，让轮廓不是一根光板；
      ② 8 层 × 3 列窄窗，窗灯稀疏（只有 4 扇亮），避免背景比主体亮；
      ③ 屋顶设备（水箱 + 天线 + 排风）破掉平顶。
    """
    F = BD_X1
    S = BD_SKIN
    ops = []
    for i in range(8):
        z0 = 2.60 + i * 3.05
        for cy in (-2.30, 0.00, 2.30):
            ops.append(dict(face="+X", a0=cy - 0.60, a1=cy + 0.60, z0=z0, z1=z0 + 1.55))
    for i in range(6):
        z0 = 5.65 + i * 3.05
        ops.append(dict(face="+Y", a0=-1.60, a1=-0.10, z0=z0, z1=z0 + 1.40))

    _shell(g, BD_X0, BD_X1, BD_Y0, BD_Y1, 0.0, BD_TOP, S, ops, C_D3, N_INK,
           faces=("+X", "+Y", "-X"))

    # 竖向壁柱（4 道）+ 层间箍带
    for cy in (-3.30, -1.15, 1.15, 3.30):
        g.box(F - 0.02, F + 0.14, cy - 0.22, cy + 0.22, 0.0, BD_TOP, MATTE, C_D4)
    for i in range(9):
        z = 2.30 + i * 3.05
        g.box(F - 0.02, F + 0.10, BD_Y0, BD_Y1, z, z + 0.22, METAL, C_D5)
    # 窗（只 4 扇亮）
    lit_set = {(2.60, 0.00), (8.70, 2.30), (14.80, -2.30), (20.90, 0.00)}
    for i in range(8):
        z0 = 2.60 + i * 3.05
        for cy in (-2.30, 0.00, 2.30):
            _win(g, "x", +1, F, cy - 0.60, cy + 0.60, z0, z0 + 1.55,
                 lit=(z0, cy) in lit_set, mull=1, transom=False, frame_cell=C_D5,
                 grime=False, band_cell=C_D4, cap_cell=C_D6)
    # 侧立面窗（-Y 面朝南，镜头能看到一点）
    for i in range(6):
        z0 = 5.65 + i * 3.05
        g.box(-1.60, -0.10, BD_Y0 + 0.30, BD_Y0 + 0.34, z0, z0 + 1.40, GLOSS, T_GLASS)
    # 底层基座 + 檐口
    g.box(BD_X0 - 0.06, F + 0.12, BD_Y0 - 0.06, BD_Y1 + 0.06, 0.0, 2.30, MATTE, C_D2)
    g.box(F + 0.08, F + 0.14, BD_Y0, BD_Y1, 0.0, 2.30, MATTE, C_D4)
    for (za, zb, out, cell) in ((25.60, 26.10, 0.20, C_D5),
                                (26.10, 26.55, 0.34, C_D6),
                                (26.55, 26.90, 0.44, C_D7)):
        g.box(BD_X0 - out * 0.5, F + out, BD_Y0 - out * 0.5, BD_Y1 + out, za, zb, METAL, cell)
    # 女儿墙 + 压顶
    for (x0, x1, y0, y1) in ((F - 0.34, F, BD_Y0, BD_Y1), (BD_X0, BD_X0 + 0.34, BD_Y0, BD_Y1),
                             (BD_X0, F, BD_Y0, BD_Y0 + 0.34), (BD_X0, F, BD_Y1 - 0.34, BD_Y1)):
        g.box(x0, x1, y0, y1, 26.90, BD_TOP, MATTE, C_D2)
    g.box(F - 0.42, F + 0.06, BD_Y0 - 0.06, BD_Y1 + 0.06, BD_TOP, BD_TOP + 0.14, METAL, C_D6)
    # 屋顶：水箱 + 排风 + 天线 + 电缆
    g.box(BD_X0 + 0.24, F - 0.28, BD_Y0 + 0.24, BD_Y1 - 0.24, BD_TOP, BD_TOP + 0.08,
          MATTE, C_D2)
    g.cyl(-1.60, 1.10, BD_TOP + 0.08, BD_TOP + 1.42, 0.92, METAL, C_D3, seg=12)
    for zz in (BD_TOP + 0.52, BD_TOP + 0.96):
        g.cyl(-1.60, 1.10, zz, zz + 0.07, 0.97, METAL, C_D6, seg=12)
    g.cyl(-1.60, 1.10, BD_TOP + 1.42, BD_TOP + 1.54, 0.90, METAL, C_D5, seg=12, r2=0.46)
    for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        g.box(-1.60 + sx * 0.62 - 0.06, -1.60 + sx * 0.62 + 0.06,
              1.10 + sy * 0.62 - 0.06, 1.10 + sy * 0.62 + 0.06,
              BD_TOP + 0.08, BD_TOP + 0.50, METAL, C_D5)
    for (fx, fy) in ((2.20, -1.80), (2.20, 0.60)):
        g.box(fx - 0.56, fx + 0.56, fy - 0.46, fy + 0.46, BD_TOP + 0.08, BD_TOP + 0.56,
              METAL, C_D3)
        g.cyl(fx, fy, BD_TOP + 0.56, BD_TOP + 0.62, 0.30, METAL, C_D6, seg=10)
    g.cyl(3.30, 2.40, BD_TOP + 0.08, BD_TOP + 3.10, 0.05, METAL, C_D6, seg=6)
    for zz in (BD_TOP + 1.40, BD_TOP + 2.30):
        g.box(3.00, 3.60, 2.38, 2.42, zz, zz + 0.035, METAL, C_D7)
    g.cyl(3.30, 2.40, BD_TOP + 3.10, BD_TOP + 3.20, 0.07, EMIT, E_PINK, seg=6)


# ================================================================ 新增街面组件

def c_road_paint(g):
    """10×10 路面标线组：车道虚线 / 停止线 / 导向箭头 / 井盖圈 / 补丁缝。

    只做"覆盖层"（z 0..0.03），叠在既有车道砖上，不改车道本体。
    """
    # 中心虚线（两条，段长 3.0 / 间隔 2.0）
    for x in (-0.30, 0.10):
        for y0 in (-4.8, 0.2):
            g.box(x, x + 0.14, y0, y0 + 3.0, 0.004, 0.028, MATTE, L.C_GREY_MID)
    # 停止线（南端）
    g.box(-4.60, -0.60, -4.70, -4.36, 0.004, 0.030, MATTE, L.C_GREY_MID)
    # 导向箭头（阶梯构成，指向 -Y）
    def arrow(cx, y0):
        g.box(cx - 0.16, cx + 0.16, y0 + 0.70, y0 + 2.40, 0.004, 0.026, MATTE, L.C_GREY_MID)
        for k in range(4):
            hw = 0.16 + (k + 1) * 0.20
            g.box(cx - hw, cx + hw, y0 + 0.70 - k * 0.20, y0 + 0.86 - k * 0.20,
                  0.004, 0.026, MATTE, L.C_GREY_MID)
    arrow(-2.60, -3.20)
    arrow(2.40, 0.60)
    # 边线磨损（断续）
    for y0 in (-4.6, -2.0, 0.6, 3.2):
        g.box(4.60, 4.72, y0, y0 + 1.10, 0.004, 0.024, MATTE, L.C_GREY_COOL)
        g.box(-4.72, -4.60, y0 + 0.30, y0 + 1.40, 0.004, 0.024, MATTE, L.C_GREY_COOL)
    # 井盖圈（八段方环 + 十字）
    cx, cy, r = 1.40, -3.10, 0.42
    for (dx0, dx1, dy0, dy1) in ((-r, r, r - 0.08, r), (-r, r, -r, -r + 0.08),
                                 (-r, -r + 0.08, -r, r), (r - 0.08, r, -r, r)):
        g.box(cx + dx0, cx + dx1, cy + dy0, cy + dy1, 0.004, 0.030, METAL, L.C_PURPLE2)
    g.box(cx - 0.36, cx + 0.36, cy - 0.03, cy + 0.03, 0.006, 0.028, METAL, L.C_BLACK)
    g.box(cx - 0.03, cx + 0.03, cy - 0.36, cy + 0.36, 0.006, 0.028, METAL, L.C_BLACK)
    # 沥青补丁缝（三条细长条，方向不同）
    g.box(-3.90, -1.10, 2.30, 2.38, 0.004, 0.022, MATTE, L.C_BLACK)
    g.box(1.20, 1.28, -2.10, 3.30, 0.004, 0.022, MATTE, L.C_BLACK)
    g.box(-4.40, -2.60, -1.60, -1.53, 0.004, 0.022, MATTE, L.C_BLACK)


def c_pavement_detail(g):
    """5×5 人行道细节层（叠在既有面砖上，z 0.20 起）：砖缝 / 排水篦 / 井盖 / 缘石条。"""
    # 面砖十字缝（4 条）—— 比砖面暗一级
    for t in (-1.25, 0.0, 1.25):
        g.box(t - 0.03, t + 0.03, -2.50, 2.50, 0.200, 0.212, MATTE, L.C_BLACK)
        g.box(-2.50, 2.50, t - 0.03, t + 0.03, 0.200, 0.212, MATTE, L.C_BLACK)
    # 防滑条（靠缘石一侧，三条）
    for k in range(3):
        g.box(1.90, 2.34, -2.20 + k * 1.60, -2.06 + k * 1.60, 0.200, 0.214,
              METAL, L.C_GREY_COOL)
    # 排水篦（四根横条 + 边框）
    g.box(1.62, 2.34, 1.02, 2.18, 0.200, 0.216, METAL, L.C_PURPLE)
    for k in range(5):
        g.box(1.68, 2.28, 1.10 + k * 0.22, 1.18 + k * 0.22, 0.212, 0.222, METAL, L.C_BLACK)
    # 井盖（方盖 + 提孔）
    g.box(-2.10, -1.30, -1.90, -1.10, 0.200, 0.224, METAL, L.C_PURPLE2)
    g.box(-1.86, -1.54, -1.72, -1.28, 0.220, 0.232, METAL, L.C_BLACK)
    g.box(-1.74, -1.66, -1.56, -1.44, 0.230, 0.238, MATTE, L.C_BLACK)
    # 缘石反光条（三段）—— 用金属亮面，**不是自发光**。
    # 用 EMIT 时，近景机位（2m 内）会在画面角落烧出一块纯白斑（实测）；
    # 反光条的正确做法是低粗糙度金属，靠环境反射发亮，本身不发光。
    for k in range(3):
        g.box(2.36, 2.44, -2.30 + k * 1.60, -1.70 + k * 1.60, 0.200, 0.230,
              GLOSS, L.C_GREY_COOL)
    # 树池边（L 形四块）
    for (x0, x1, y0, y1) in ((-0.90, 0.50, 2.10, 2.22), (-0.90, 0.50, 0.02, 0.14),
                             (-1.02, -0.90, 0.02, 2.22), (0.50, 0.62, 0.02, 2.22)):
        g.box(x0, x1, y0, y1, 0.200, 0.256, MATTE, L.C_NAVY2)


def c_cable_harness(g):
    """4m 贴墙线束（局部 +X 为墙面外法线）：三束电缆 + 吊环 + 分线盒 + 下垂段。"""
    LEN = 4.0
    # 三束电缆（分段下垂，每段斜率不同，读成"松弛"）
    for k, z0 in enumerate((0.86, 0.66, 0.48)):
        segs = 4
        for s in range(segs):
            y0 = -LEN / 2 + LEN * s / segs
            y1 = -LEN / 2 + LEN * (s + 1) / segs
            sag = 0.035 if s % 2 else -0.020
            g.beam((0.10, y0, z0 + sag), (0.10, y1, z0 - sag * 0.5), 0.045, 0.045,
                   METAL, L.C_PURPLE if k else L.C_INDIGO)
    # 吊环（4 个）+ 固定板
    for s in range(4):
        yy = -LEN / 2 + 0.30 + s * 1.13
        g.box(0.02, 0.16, yy - 0.04, yy + 0.04, 0.30, 1.06, METAL, L.C_PURPLE2)
        g.box(0.00, 0.06, yy - 0.14, yy + 0.14, 0.24, 1.12, METAL, L.C_PURPLE2)
    # 分线盒
    g.box(0.10, 0.34, -0.30, 0.34, 0.10, 0.78, METAL, L.C_PURPLE)
    g.box(0.32, 0.36, -0.26, 0.30, 0.14, 0.74, METAL, L.C_INDIGO)
    g.box(0.36, 0.375, -0.20, 0.02, 0.60, 0.66, EMIT, L.C_AMBER)
    for k in range(3):
        g.cyl(0.24, -0.22 + k * 0.20, 0.02, 0.10, 0.026, METAL, L.C_PURPLE2, seg=6)
    # 下垂段（从分线盒落到地面附近）
    g.beam((0.24, 0.34, 0.14), (0.24, 0.62, -0.02), 0.05, 0.05, METAL, L.C_INDIGO)
    g.beam((0.24, 0.62, -0.02), (0.24, 0.92, 0.06), 0.05, 0.05, METAL, L.C_INDIGO)


def c_billboard_panel(g):
    """墙面广告灯箱 2.8×3.6（局部 +X 为外法线）：边框 / 内凹板 / 几何图形 / 支架。"""
    W, H = 2.80, 3.60
    # 背板 + 四边框
    g.box(0.00, 0.08, -W / 2, W / 2, 0.0, H, METAL, L.C_PURPLE)
    for (y0, y1, z0, z1) in ((-W / 2, W / 2, H - 0.14, H), (-W / 2, W / 2, 0.0, 0.14),
                             (-W / 2, -W / 2 + 0.14, 0.0, H), (W / 2 - 0.14, W / 2, 0.0, H)):
        g.box(0.00, 0.26, y0, y1, z0, z1, METAL, L.C_PURPLE2)
    # 内凹面板（暗）
    g.box(0.10, 0.16, -W / 2 + 0.16, W / 2 - 0.16, 0.16, H - 0.16, MATTE, L.C_BLACK)
    g.box(0.16, 0.19, -W / 2 + 0.20, W / 2 - 0.20, 0.20, H - 0.20, GLOSS, L.C_NAVY2)
    # 几何图形：两个同心方框 + 三条竖条 + 一条横条（抽象标记，不写具体字）
    g.box(0.19, 0.22, -0.90, 0.90, 1.60, 2.90, EMIT, L.C_BLUE_DARK)
    g.box(0.195, 0.215, -0.74, 0.74, 1.74, 2.76, MATTE, L.C_BLACK)
    for k in range(3):
        g.box(0.19, 0.22, -0.52 + k * 0.42, -0.30 + k * 0.42, 0.42, 1.30, EMIT, L.C_GREY_COOL)
    g.box(0.19, 0.22, -1.00, 1.00, 0.26, 0.36, EMIT, L.C_AMBER2)
    # 顶部灯条 + 支架
    g.box(0.20, 0.30, -W / 2 + 0.20, W / 2 - 0.20, H - 0.06, H - 0.02, EMIT, L.C_GREY_MID)
    for yy in (-1.00, 1.00):
        g.beam((0.00, yy, H - 0.30), (0.00, yy, H + 0.02), 0.10, 0.10, METAL, L.C_PURPLE2)
        g.beam((0.00, yy, 0.30), (0.00, yy, 0.02), 0.10, 0.10, METAL, L.C_PURPLE2)
        g.beam((-0.06, yy, H - 0.20), (0.02, yy, H + 0.34), 0.05, 0.05, METAL, L.C_PURPLE)


# ================================================================ 组件登记

# v002 里这三件在 v003 被并入宿主（拱窗/卷帘/消防梯都变成建筑本体的一部分），
# 不再单独实例化 —— 定义同时剔除，否则会出现"实例数 0 的空资产包"。
EXCLUDED = {
    "hotel_arch_window_bay_02",     # 15 樘拱窗 → 并入酒店外壳的真洞口
    "hotel_shutter_shopfront_03",   # 卷帘门 → 并入酒店门头
    "metal_fire_stair_walkway_03",  # 2 段消防梯 → 酒店与酒吧各自按层高做齐
}

DETAIL_OVERRIDE = {
    "hotel_brick_tower_core_10x12_01": c_hotel_tower_detail,
    "industrial_bar_building_10x12_01": c_bar_building_detail,
    "backdrop_tower_block_10x7_01": c_backdrop_tower_detail,
    "neon_sign_hotel_vertical_01": c_hotel_sign_detail,
    "neon_sign_bar_vertical_03": c_bar_sign_detail,
}

REUSED_FROM_V2 = "art_source/environments/open_world/source/underground_street/v002"

COMPONENTS: list[dict] = []
for _e in V2.COMPONENTS:
    if _e["slug"] in EXCLUDED:
        continue
    _detailed = _e["slug"] in DETAIL_OVERRIDE
    COMPONENTS.append(dict(
        slug=_e["slug"], name_zh=_e["name_zh"], family=_e["family"],
        category=_e["category"],
        builder=DETAIL_OVERRIDE.get(_e["slug"], _e["builder"]),
        note=_e.get("note", "") or "",
        reused_from=None if _detailed else REUSED_FROM_V2,
        detailed=_detailed,
    ))

NEW = [
    dict(slug="road_paint_dash_run_03", name_zh="路面标线组_10x10m_03",
         family="road_marking", category="road_detail", builder=c_road_paint,
         note="车道虚线/停止线/导向箭头/井盖圈/补丁缝；覆盖层做法，不改车道本体",
         reused_from=None),
    dict(slug="street_pavement_detail_03", name_zh="人行道细节层_5x5m_03",
         family="sidewalk_detail", category="road_detail", builder=c_pavement_detail,
         note="砖缝/防滑条/排水篦/井盖/缘石反光条/树池边；叠在既有面砖上（z 0.20 起）",
         reused_from=None),
    dict(slug="street_cable_harness_03", name_zh="贴墙线束_4m_03",
         family="wall_cable", category="facility", builder=c_cable_harness,
         note="三束松弛电缆/吊环/分线盒/下垂段；补街面线缆密度",
         reused_from=None),
    dict(slug="facade_billboard_panel_03", name_zh="墙面广告灯箱_2.8x3.6m_03",
         family="wall_billboard", category="facility", builder=c_billboard_panel,
         note="边框/内凹板/几何标记/支架/顶部灯条；用于大片空墙",
         reused_from=None),
]
COMPONENTS.extend(NEW)

# 招牌重建后正面改为局部 +X（v002 是 -Y）
FRONT_AXIS = dict(V2.FRONT_AXIS)
FRONT_AXIS["neon_sign_hotel_vertical_01"] = "+X"
FRONT_AXIS["neon_sign_bar_vertical_03"] = "+X"
FRONT_AXIS["road_paint_dash_run_03"] = "+Z"
FRONT_AXIS["street_pavement_detail_03"] = "+Z"
FRONT_AXIS["street_cable_harness_03"] = "+X"
FRONT_AXIS["facade_billboard_panel_03"] = "+X"
FIXED_ROT = dict(V2.FIXED_ROT)


# ================================================================ 布局实例

GROUP_ORDER = list(V2.GROUP_ORDER)
LAYOUT: list[dict] = []


def build_layout():
    """继承 v002 的摆位，只做三件事：剔除并入宿主的件、挪两块招牌、追加新组件。"""
    LAYOUT.clear()
    V2.build_layout()
    for it in V2.LAYOUT:
        if it["slug"] in EXCLUDED:
            continue
        LAYOUT.append(dict(it))

    for it in LAYOUT:
        if it["slug"] == "neon_sign_hotel_vertical_01":
            # 挪到南角：v002 挂在 y=1.6，正好压住第一列拱窗（实测渲染里窗被招牌劈成两半）
            it["loc"] = (-9.98, 0.20, 6.00)
            it["rz"] = 0.0
        elif it["slug"] == "neon_sign_bar_vertical_03":
            # 挂正立面（朝街 -X）。招牌几何本身已按 -X 构建（见 c_bar_sign_detail），
            # 所以实例 **rz=0**，不需要翻转，字天然正确。
            it["loc"] = (9.98, -1.60, 9.20)
            it["rz"] = 0.0

    A, B, D = GROUP_ORDER[0], GROUP_ORDER[1], GROUP_ORDER[3]
    # 路面标线：南北两段车道上各一组（避开 y=±7.5 的斑马线）
    for y in (-13.0, 13.0):
        inst("road_paint_dash_run_03", A, 0.0, y)
    # 人行道细节：两侧各三块（缘石在哪边决定 rz）
    for y in (-22.5, -12.5, 12.5, 17.5):
        inst("street_pavement_detail_03", A, -7.5, y, 0.0, 0.0)
    for y in (-17.5, 7.5, 22.5):
        inst("street_pavement_detail_03", A, 7.5, y, 0.0, 180.0)
    # 贴墙线束：酒店正立面两段、酒吧正立面一段
    inst("street_cable_harness_03", D, -9.98, 6.20, 3.60, 0.0)
    inst("street_cable_harness_03", D, -9.98, 1.40, 0.00, 0.0)
    inst("street_cable_harness_03", D, 9.98, -7.40, 3.80, 180.0)
    # 墙面广告：三栋背景楼的空墙
    inst("facade_billboard_panel_03", B, 9.98, 4.00, 12.40, 180.0)
    inst("facade_billboard_panel_03", B, 9.98, 19.00, 10.20, 180.0)
    inst("facade_billboard_panel_03", B, -9.98, 22.50, 11.80, 0.0)


def inst(slug, group, x, y, z=0.0, rz=0.0):
    LAYOUT.append(dict(slug=slug, group=group, loc=(x, y, z), rz=rz))


# ================================================================ 清单写出

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
            "geometry_source": "build_openworld_underground_street_%s.py::%s"
                               % (VERSION, e["builder"].__name__),
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
            "detailed_in_v003": bool(e.get("detailed")),
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
        "reuse_policy": "复用 v002 组件生成器函数（几何零漂移）；v003 只重写 5 件主体与招牌，"
                        "并把 3 件装饰并入宿主（拱窗/卷帘/消防梯）",
    }
    for c in catalog_components:
        plan["families"].setdefault(c["family_id"], []).append(c["slug"])
    with open(os.path.join(OUT_DIR, "component_plan.json"), "w", encoding="utf-8") as f:
        json.dump(plan, f, ensure_ascii=False, indent=2)

    lines = ["%s (%s) - 大世界 地下街区 编号02 · v003 主体楼深化" % (SUITE, VERSION),
             "├── 01_制作组件_按组件拆分_%s (%d Master Components)" % (VERSION, len(records)),
             "├── 02_游戏输出_独立资产包_%s (%d Output Packages, Body/Emissive Split)"
             % (VERSION, len(records)),
             "├── 03_场景拼装_实例布局_%s (%d Collection Instances)" % (VERSION, len(inst_records)),
             "└── 90_展示与动态_灯光相机 (Cameras, Neon Lights)", "",
             "本版重写 %d 件主体 / 新生产 %d 件 / 其余复用 v002"
             % (len([c for c in catalog_components if c.get("detailed_in_v003")]),
                len(NEW)), "Components:"]
    for rec in records:
        c = rec["entry"]
        d = " × ".join("%.2f" % v for v in rec["dims"])
        tag = "  (v003 重写)" if c.get("detailed") else (
            "  (NEW)" if not c.get("reused_from") else "  (reuse v002)")
        lines.append("  - [comp_%s] %s | %s m | polys=%d | instances=%d%s"
                     % (c["slug"], c["name_zh"], d, rec["polys"],
                        count_by_slug.get(c["slug"], 0), tag))
    with open(os.path.join(OUT_DIR, "component_tree.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


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

    build_layout()
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

    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    from mathutils import Vector
    for it in inst_records:
        emp = bpy.data.objects[it["name"]]
        for obj in pkg_colls[it["slug"]].all_objects:
            if obj.type != "MESH":
                continue
            for corner in obj.bound_box:
                w = emp.matrix_world @ obj.matrix_world @ Vector(corner)
                for k in range(3):
                    lo[k] = min(lo[k], w[k])
                    hi[k] = max(hi[k], w[k])

    # ---------------- 世界 / 灯光 ----------------
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
    # 洗墙光朝向必须按 Rz·Rx 分解核对：rz=+90 指 -X（照西侧立面），rz=-90 指 +X（照东侧）
    add_light("酒店洗墙_主", "AREA", (-8.6, 5.20, 17.0), 46, (0.66, 0.72, 1.0),
              (math.radians(52), 0, math.radians(90)), size=7)
    add_light("酒店洗墙_低", "AREA", (-8.8, 0.20, 4.60), 18, (0.62, 0.70, 1.0),
              (math.radians(74), 0, math.radians(90)), size=4)
    add_light("酒吧洗墙_主", "AREA", (8.6, -6.40, 12.0), 40, (0.70, 0.74, 1.0),
              (math.radians(56), 0, math.radians(-90)), size=6)
    add_light("药店洗墙_主", "AREA", (-8.5, -9.2, 8.6), 42, (0.62, 0.74, 1.0),
              (math.radians(58), 0, math.radians(90)), size=6)
    add_light("药店洗墙_补", "AREA", (-8.7, -12.4, 2.4), 16, (0.58, 0.70, 1.0),
              (math.radians(72), 0, math.radians(90)), size=4)
    # 点光放在招牌**外侧 0.9m**（不是贴着面板）：贴着面板会在字上打出一块死白红点
    add_light("霓虹_酒店粉", "POINT", (-8.4, -1.40, 10.6), 300, (1.0, 0.16, 0.34))
    add_light("霓虹_药店青", "POINT", (-8.4, -9.6, 5.0), 200, (0.20, 0.90, 0.86))
    add_light("霓虹_酒吧红", "POINT", (8.4, -9.6, 10.2), 240, (1.0, 0.2, 0.28))
    add_light("霓虹_高架橙", "POINT", (-1.0, 8.6, 12.4), 220, (1.0, 0.62, 0.18))
    # 480W 时在湿沥青上打出一块过曝白斑（街面近景机位实测右下角一个白块）。
    # 降到 300W 并把光锥收窄，热斑降到中调，路面仍读得出被照亮的区域。
    add_light("街口射灯", "SPOT", (5.0, -14.0, 12.6), 300, (0.72, 0.82, 1.0),
              (math.radians(63), 0, math.radians(-24)), spot=math.radians(58))
    add_light("酒店门头暖光", "SPOT", (-8.2, 0.4, 3.6), 220, (1.0, 0.55, 0.3),
              (math.radians(74), 0, math.radians(90)), spot=math.radians(60))
    add_light("蒸汽逆光", "SPOT", (-1.0, 4.4, 6.0), 240, (0.75, 0.86, 1.0),
              (math.radians(96), 0, math.radians(-150)), spot=math.radians(46))
    add_light("地面回光_酒店粉", "POINT", (-6.0, 1.4, 1.2), 120, (1.0, 0.22, 0.40))
    add_light("地面回光_药店青", "POINT", (-6.4, -6.0, 1.0), 90, (0.16, 0.92, 0.86))
    add_light("地面回光_酒吧红", "POINT", (6.6, 0.0, 1.2), 110, (1.0, 0.24, 0.30))
    add_light("地面回光_桥底橙", "POINT", (0.0, 12.0, 1.4), 80, (1.0, 0.62, 0.20))

    cam_data = bpy.data.cameras.new("CAM_参考构图")
    cam_data.lens = 22
    cam_obj = bpy.data.objects.new("CAM_参考构图", cam_data)
    cam_obj.location = (10.5, -23.0, 17.0)
    root_disp.objects.link(cam_obj)
    d = Vector((-5.0, 2.0, 5.5)) - cam_obj.location
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
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 1.15

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, check_existing=False)
    try:
        bpy.ops.file.make_paths_relative()
        bpy.ops.wm.save_mainfile()
    except Exception as exc:
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


if os.environ.get("UG_STREET_BUILD_LIB_ONLY") != "1":
    try:
        main()
    except Exception as exc:
        import traceback
        traceback.print_exc()
        print("BUILD_FAILED:", exc)
        raise
