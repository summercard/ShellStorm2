"""地下街区 v001 —— 大世界 open_world 地下街区 Blender 原始文件构建器。

参考图：用户提供的赛博朋克街区概念图（HOTEL / 藥 / BAR / SECTOR 07 東區）。
定位：大世界 open_world 地下街区（cavern street），不是地表街区，也不是塔楼房间。
实现：42 个独立组件包 + 实例布局 + 公共色盘逐面 UV + 四共享材质角色。

幂等：重跑会先清空场景再重建（场景内数据可重跑，磁盘 .blend 由调用方负责版本）。
运行方式（在业主的 Blender 会话内、主线程）：
    tools/blender_bridge 执行本文件
"""

from __future__ import annotations

import json
import math
import os
import sys

import bpy

PROJECT = r"I:\工作项目\shellstrom2\ShellStorm2"
sys.path.insert(0, os.path.join(PROJECT, "scripts", "blender"))

import ug_street_lib_v001 as L  # noqa: E402

SUITE = "underground_street"
VERSION = "v001"
OUT_DIR = os.path.join(PROJECT, "art_source", "environments", "open_world", "source", SUITE, VERSION)
BLEND_PATH = os.path.join(OUT_DIR, "env_%s_source_%s.blend" % (SUITE, VERSION))
ASSET_ID_ROOT = "ENV-OPENWORLD-UNDERGROUND-STREET"

# ---------------------------------------------------------------- 尺寸常量
SLAB_HALF = 26.0        # 基底 52×52
CAVERN_INNER = 25.0     # 街区可用半宽
WALL_Z = 25.7           # 围护墙中心线
CEIL_BOTTOM = 28.6
CEIL_TOP = 30.0
TRUSS_Z = 25.4

# ---------------------------------------------------------------- 组件登记
COMPONENTS: list[dict] = []


def comp(slug, name_zh, family, category, builder, note=""):
    COMPONENTS.append(dict(slug=slug, name_zh=name_zh, family=family, category=category,
                           builder=builder, note=note))


def _louver_x(g, y, x0, x1, z0, z1, n, role, cell):
    step = (z1 - z0) / n
    for i in range(n):
        g.box(x0, x1, y - 0.05, y + 0.05, z0 + i * step + step * 0.15, z0 + i * step + step * 0.75, role, cell)


# ================================================================ A 地下围护


def c_base_slab(g):
    g.box(-SLAB_HALF, SLAB_HALF, -SLAB_HALF, SLAB_HALF, -1.8, 0.0, L.ROLE_MATTE, L.C_NAVY2)
    # 边缘岩层 / 破碎带
    for i in range(26):
        a = math.pi * 2 * i / 26
        cx, cy = SLAB_HALF * 0.985 * math.cos(a), SLAB_HALF * 0.985 * math.sin(a)
        w = 2.4 + (i % 3) * 0.7
        g.rbox(cx, cy, -1.7, w, 1.5, 1.9, L.ROLE_MATTE, L.C_BLACK, rz=a)
    # 街区内排水明沟
    g.box(-SLAB_HALF, -5.6, -0.45, 0.45, -0.02, 0.04, L.ROLE_METAL, L.C_BLUE_DARK)
    g.box(5.6, SLAB_HALF, -0.45, 0.45, -0.02, 0.04, L.ROLE_METAL, L.C_BLUE_DARK)


def c_cavern_wall(g):
    # 10m × 30m 混凝土衬砌岩壁模块（内侧朝 -Y）
    g.box(-5.0, 5.0, -0.7, 0.7, 0.0, 30.0, L.ROLE_MATTE, L.C_NAVY)
    g.box(-5.0, 5.0, -0.9, -0.6, 0.0, 1.4, L.ROLE_MATTE, L.C_BLACK)
    for z in range(4, 29, 4):
        g.box(-5.0, 5.0, -1.0, -0.68, z, z + 0.42, L.ROLE_METAL, L.C_PURPLE)
    for x in (-4.6, 4.6):
        g.box(x - 0.35, x + 0.35, -1.15, -0.6, 0.0, 30.0, L.ROLE_METAL, L.C_PURPLE2)
    # 竖向电缆桥架 + 检修梯
    g.box(-1.4, 1.4, -1.05, -0.72, 3.0, 26.0, L.ROLE_METAL, L.C_NAVY2)
    for i in range(9):
        g.box(-1.2, 1.2, -1.12, -0.7, 4.0 + i * 2.4, 4.12 + i * 2.4, L.ROLE_METAL, L.C_INDIGO)
    # 顶部工作灯带
    for x in (-3.0, 0.0, 3.0):
        g.box(x - 1.1, x + 1.1, -1.05, -0.72, 24.4, 24.55, L.ROLE_EMIT, L.C_AMBER)
    # 底部检修门
    g.box(-0.55, 0.55, -1.0, -0.66, 0.0, 2.0, L.ROLE_METAL, L.C_PURPLE2)
    g.box(-0.62, 0.62, -1.06, -0.68, 2.0, 2.12, L.ROLE_EMIT, L.C_AMBER)


def c_cavern_ceiling(g):
    g.box(-SLAB_HALF, SLAB_HALF, -SLAB_HALF, SLAB_HALF, CEIL_BOTTOM, CEIL_TOP, L.ROLE_MATTE, L.C_NAVY2)
    # 井字梁格
    y = -SLAB_HALF + 2.6
    while y < SLAB_HALF:
        g.box(-SLAB_HALF, SLAB_HALF, y - 0.34, y + 0.34, CEIL_BOTTOM - 0.62, CEIL_BOTTOM, L.ROLE_METAL, L.C_PURPLE)
        y += 5.2
    x = -SLAB_HALF + 2.6
    while x < SLAB_HALF:
        g.box(x - 0.34, x + 0.34, -SLAB_HALF, SLAB_HALF, CEIL_BOTTOM - 0.5, CEIL_BOTTOM, L.ROLE_METAL, L.C_PURPLE)
        x += 10.4
    # 顶板管线 / 吊杆
    for y in (-18.0, -8.0, 8.0, 18.0):
        g.cyl_x(-SLAB_HALF + 1.0, SLAB_HALF - 1.0, y, CEIL_BOTTOM - 0.95, 0.22, L.ROLE_METAL, L.C_INDIGO, seg=8)
        g.cyl_x(-SLAB_HALF + 1.0, SLAB_HALF - 1.0, y + 0.55, CEIL_BOTTOM - 1.05, 0.14, L.ROLE_METAL, L.C_PURPLE2, seg=8)
    # 稀疏的顶板射灯
    for x in (-18.0, -6.0, 6.0, 18.0):
        for y in (-14.0, 14.0):
            g.cyl(x, y, CEIL_BOTTOM - 0.3, CEIL_BOTTOM - 0.12, 0.55, L.ROLE_EMIT, L.C_AMBER2, seg=10)


def c_ceiling_truss(g):
    # 51.6m 跨度钢桁架
    half = 25.8
    for z in (TRUSS_Z + 1.75, TRUSS_Z):
        g.box(-half, half, -0.26, 0.26, z, z + 0.45, L.ROLE_METAL, L.C_PURPLE)
    x = -half
    while x <= half + 0.01:
        g.box(x - 0.14, x + 0.14, -0.2, 0.2, TRUSS_Z + 0.42, TRUSS_Z + 1.78, L.ROLE_METAL, L.C_INDIGO)
        x += 2.4
    x = -half + 1.2
    while x < half - 1.2:
        g.beam((x, 0, TRUSS_Z + 0.45), (x + 2.4, 0, TRUSS_Z + 1.75), 0.16, 0.16, L.ROLE_METAL, L.C_PURPLE2)
        x += 4.8
    # 吊杆 + 吊装灯具
    for x in (-18.0, -9.0, 0.0, 9.0, 18.0):
        g.cyl(x, 0.0, TRUSS_Z - 1.6, TRUSS_Z, 0.05, L.ROLE_METAL, L.C_BLACK, seg=6)
        g.cyl(x, 0.0, TRUSS_Z - 1.95, TRUSS_Z - 1.55, 0.42, L.ROLE_METAL, L.C_PURPLE, seg=10)
        g.cyl(x, 0.0, TRUSS_Z - 2.02, TRUSS_Z - 1.94, 0.34, L.ROLE_EMIT, L.C_AMBER, seg=10)
    # 桁架上的走线槽
    g.box(-half, half, -0.62, -0.3, TRUSS_Z + 0.1, TRUSS_Z + 0.42, L.ROLE_METAL, L.C_BLUE_DARK)


def c_tunnel_portal(g):
    # 10m 宽 × 30m 高 隧道口墙，拱洞 7.6 宽 × 6.4 高（立式拱在 XZ 平面，沿 Y 拉伸）
    g.box(-5.0, 5.0, -0.9, 0.9, 8.0, 30.0, L.ROLE_MATTE, L.C_NAVY2)
    # 门洞两侧墙垛
    g.box(-5.0, -3.8, -0.9, 0.9, 0.0, 8.0, L.ROLE_MATTE, L.C_NAVY2)
    g.box(3.8, 5.0, -0.9, 0.9, 0.0, 8.0, L.ROLE_MATTE, L.C_NAVY2)
    # 半圆拱券（0..180°）
    g.arc_xz(0.0, 8.0, 3.8, 5.0, -0.95, 0.95, 0.0, math.pi, L.ROLE_METAL, L.C_PURPLE, seg=12)
    # 拱洞内暗腔（避免透视穿帮）
    g.box(-3.8, 3.8, 0.88, 1.0, 0.0, 8.0, L.ROLE_MATTE, L.C_BLACK)
    # 门楣横梁
    g.box(-5.0, 5.0, -1.08, 0.95, 8.0, 8.6, L.ROLE_METAL, L.C_PURPLE)
    # 门槛警示条
    for i in range(7):
        g.box(-4.4 + i * 1.26, -3.7 + i * 1.26, -0.95, 0.95, 0.0, 0.16,
              L.ROLE_MATTE, L.C_AMBER2 if i % 2 else L.C_BLACK)
    # 洞口两侧警示柱
    for sx in (-1, 1):
        g.box(sx * 3.55 - 0.22, sx * 3.55 + 0.22, -1.05, 0.95, 0.0, 3.4, L.ROLE_METAL, L.C_PURPLE2)
        for z in (3.3, 3.75):
            g.box(sx * 3.55 - 0.26, sx * 3.55 + 0.26, -1.1, 0.96, z, z + 0.2, L.ROLE_EMIT, L.C_CRIMSON)
    # 门楣标牌
    g.box(-2.6, 2.6, -1.14, -0.92, 9.0, 10.3, L.ROLE_METAL, L.C_BLACK)
    for i in range(4):
        g.box(-2.2 + i * 1.1, -1.7 + i * 1.1, -1.18, -1.12, 9.35, 9.95, L.ROLE_EMIT, L.C_AMBER)
    # 上部作业灯带
    g.box(-5.0, 5.0, -0.98, -0.86, 12.6, 12.78, L.ROLE_EMIT, L.C_TEAL)


def c_support_column(g):
    # 30m 支撑巨柱
    g.box(-1.35, 1.35, -1.35, 1.35, 0.0, 1.1, L.ROLE_MATTE, L.C_NAVY2)
    for i in range(6):
        g.box(-1.28 + i * 0.42, -0.9 + i * 0.42, -1.4, -1.02, 0.12, 1.02,
              L.ROLE_MATTE, L.C_AMBER2 if i % 2 else L.C_BLACK)
        g.box(-1.28 + i * 0.42, -0.9 + i * 0.42, 1.02, 1.4, 0.12, 1.02,
              L.ROLE_MATTE, L.C_AMBER2 if i % 2 else L.C_BLACK)
    g.box(-0.95, 0.95, -0.95, 0.95, 1.1, 25.6, L.ROLE_MATTE, L.C_GREY_COOL)
    for z in range(3, 26, 3):
        g.box(-1.05, 1.05, -1.05, 1.05, z, z + 0.28, L.ROLE_METAL, L.C_PURPLE)
    for sx, sy in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        g.box(sx * 0.85 - 0.09, sx * 0.85 + 0.09, sy * 0.85 - 0.09, sy * 0.85 + 0.09,
              1.1, 25.6, L.ROLE_METAL, L.C_INDIGO)
    g.box(-1.35, 1.35, -1.35, 1.35, 25.6, 26.6, L.ROLE_METAL, L.C_PURPLE)
    # 竖向管线 + 柱身灯具
    g.cyl(1.12, 0.5, 1.1, 25.6, 0.14, L.ROLE_METAL, L.C_PURPLE2, seg=8)
    for z in (2.2, 5.2):
        g.box(0.5, 1.0, -1.02, -0.9, z, z + 0.9, L.ROLE_EMIT, L.C_CRIMSON)
    g.box(-1.02, -0.9, -0.6, 0.6, 14.0, 14.9, L.ROLE_EMIT, L.C_AMBER)


# ================================================================ B 地面系统


def c_road_lane(g):
    g.box(-5.0, 5.0, -5.0, 5.0, -0.18, 0.0, L.ROLE_MATTE, L.C_BLACK)
    # 湿沥青表层：哑光底 + 极薄反光膜（单独一条，避免整片车道被灯打白）
    g.box(-4.92, 4.92, -4.92, 4.92, 0.0, 0.012, L.ROLE_MATTE, L.C_BLUE_DARK)
    # 双黄线
    for x in (-0.24, 0.12):
        g.box(x, x + 0.12, -4.9, 4.9, 0.012, 0.03, L.ROLE_MATTE, L.C_AMBER)
    # 边线
    for x in (-4.72, 4.6):
        g.box(x, x + 0.12, -4.9, 4.9, 0.012, 0.026, L.ROLE_MATTE, L.C_GREY_MID)
    # 沥青补丁 / 裂缝
    g.box(-3.6, -1.4, -2.2, -0.6, 0.012, 0.02, L.ROLE_MATTE, L.C_NAVY2)
    g.box(1.8, 3.9, 1.2, 2.9, 0.012, 0.02, L.ROLE_MATTE, L.C_NAVY2)
    g.box(-1.2, 1.6, 3.1, 3.18, 0.012, 0.028, L.ROLE_MATTE, L.C_BLACK)


def c_road_wet_layer(g):
    """可选的反光湿膜（贴地 2cm，只盖局部，用来做霓虹倒影的底）。"""
    g.box(-4.9, 4.9, -4.9, 4.9, 0.0, 0.008, L.ROLE_GLOSS, L.C_BLUE_DARK)


def c_road_crosswalk(g):
    # 10m 宽 × 5m 深 斑马线（覆盖在车道上的薄层）
    for i in range(8):
        x0 = -4.55 + i * 1.16
        g.box(x0, x0 + 0.62, -2.35, 2.35, 0.012, 0.034, L.ROLE_MATTE, L.C_GREY_MID)
    for i in range(8):
        x0 = -4.55 + i * 1.16
        g.box(x0, x0 + 0.62, -2.5, -2.35, 0.012, 0.024, L.ROLE_MATTE, L.C_GREY_COOL)


def c_road_intersection(g):
    g.box(-5.0, 5.0, -5.0, 5.0, -0.18, 0.0, L.ROLE_MATTE, L.C_BLACK)
    g.box(-4.92, 4.92, -4.92, 4.92, 0.0, 0.012, L.ROLE_MATTE, L.C_BLUE_DARK)
    # 停止线
    for (x0, x1, y0, y1) in ((-4.7, -0.6, -4.75, -4.45), (0.6, 4.7, 4.45, 4.75)):
        g.box(x0, x1, y0, y1, 0.012, 0.03, L.ROLE_MATTE, L.C_GREY_MID)
    # 井盖
    for (cx, cy) in ((-2.0, 1.6), (2.6, -2.4)):
        g.cyl(cx, cy, 0.012, 0.05, 0.42, L.ROLE_METAL, L.C_PURPLE, seg=12)
        g.cyl(cx, cy, 0.05, 0.062, 0.30, L.ROLE_METAL, L.C_BLACK, seg=12)
    # 路口四角排水
    for (cx, cy) in ((-4.2, -4.2), (4.2, 4.2)):
        g.box(cx - 0.45, cx + 0.45, cy - 0.28, cy + 0.28, 0.012, 0.04, L.ROLE_METAL, L.C_PURPLE2)


def c_sidewalk_tile(g):
    g.box(-2.5, 2.5, -2.5, 2.5, -0.2, 0.18, L.ROLE_MATTE, L.C_BLACK)
    # 面砖 2×2
    for ix in (-1, 1):
        for iy in (-1, 1):
            cx, cy = ix * 1.2, iy * 1.2
            g.box(cx - 1.13, cx + 1.13, cy - 1.13, cy + 1.13, 0.18, 0.2,
                  L.ROLE_MATTE, L.C_NAVY2 if (ix * iy > 0) else L.C_BLUE_DARK)
    # 路缘石（+X 侧）
    g.box(2.5, 2.78, -2.5, 2.5, -0.2, 0.26, L.ROLE_MATTE, L.C_NAVY)
    g.box(2.5, 2.78, -2.5, 2.5, 0.26, 0.3, L.ROLE_MATTE, L.C_GREY_COOL)
    # 井盖 / 树池
    g.box(-2.2, -1.2, 0.4, 1.4, 0.2, 0.222, L.ROLE_METAL, L.C_PURPLE2)
    for i in range(4):
        g.box(-2.1 + i * 0.22, -2.02 + i * 0.22, 0.5, 1.3, 0.222, 0.232, L.ROLE_METAL, L.C_BLACK)


def c_puddle(g):
    # 水洼：极深哑光底 + 细窄反光内环（大面积高光会被顶光打爆成白团，故不做整片镜面）
    pts = [(-1.9, -1.2), (-0.6, -1.6), (0.9, -1.3), (1.8, -0.4), (1.5, 0.8),
           (0.4, 1.4), (-0.9, 1.2), (-1.8, 0.3)]
    g.prism(pts, 0.014, 0.024, L.ROLE_MATTE, L.C_BLUE_DARK)
    inner = [(p[0] * 0.55, p[1] * 0.55) for p in pts]
    g.prism(inner, 0.024, 0.028, L.ROLE_GLOSS, L.C_NAVY2)


def c_wet_reflect_streak(g):
    """湿路面上的霓虹倒影拉长条（参考图里最抢眼的竖向反光）。"""
    streaks = [
        (-1.9, 0.55, 3.6, L.C_CRIMSON, 0.9),
        (-1.2, 0.24, 5.2, L.C_CRIMSON, 0.55),
        (0.4, 0.30, 4.4, L.C_MAGENTA, 0.7),
        (1.5, 0.18, 3.0, L.C_AMBER, 0.5),
        (2.4, 0.42, 2.2, L.C_TEAL, 0.6),
    ]
    for (cx, w, leng, cell, brk) in streaks:
        segs = 7
        for i in range(segs):
            t0 = i / segs
            t1 = (i + 1) / segs
            ww = w * (1.0 - 0.45 * t0)
            g.box(cx - ww / 2, cx + ww / 2, -leng * (1 - t1), -leng * (1 - t0),
                  0.014, 0.016 + 0.002 * i, L.ROLE_GLOSS, cell)


def c_manhole_set(g):
    g.cyl(0.0, 0.0, 0.0, 0.035, 0.46, L.ROLE_METAL, L.C_PURPLE, seg=14)
    g.cyl(0.0, 0.0, 0.035, 0.05, 0.36, L.ROLE_METAL, L.C_BLACK, seg=14)
    for i in range(3):
        g.box(-0.3, 0.3, -0.035 + i * 0.12 - 0.035, 0.0 + i * 0.12 + 0.035, 0.05, 0.062,
              L.ROLE_METAL, L.C_INDIGO)
    g.box(-0.035, 0.035, -0.32, 0.32, 0.05, 0.062, L.ROLE_METAL, L.C_INDIGO)
    g.box(0.9, 2.1, -0.26, 0.26, 0.0, 0.05, L.ROLE_METAL, L.C_PURPLE2)
    for i in range(5):
        g.box(1.0 + i * 0.22, 1.12 + i * 0.22, -0.2, 0.2, 0.05, 0.07, L.ROLE_METAL, L.C_BLACK)


# ================================================================ C 建筑体量


def _facade_windows_x(g, face_x, sign, y0, y1, cols, zs, w, h, cell_off, cell_lit):
    """在 ±X 立面上做暗窗洞并点亮部分窗。"""
    step = (y1 - y0) / cols
    xin = face_x - 0.16 * sign
    for i in range(cols):
        cy = y0 + step * (i + 0.5)
        for k, z in enumerate(zs):
            g.box(min(face_x, xin), max(face_x, xin), cy - w / 2, cy + w / 2, z, z + h,
                  L.ROLE_MATTE, L.C_BLACK)
            if (i + k) % 3 == 0:
                a, b = min(face_x, xin) + 0.02 * sign, max(face_x, xin) + 0.02 * sign
                g.box(min(a, b), max(a, b), cy - w / 2 + 0.09, cy + w / 2 - 0.09,
                      z + 0.12, z + h - 0.12, L.ROLE_EMIT,
                      cell_lit if (i + k) % 2 == 0 else cell_off)


def _facade_windows_y(g, face_y, sign, x0, x1, cols, zs, w, h, cell_off, cell_lit):
    """在 ±Y 立面上做暗窗洞并点亮部分窗。"""
    step = (x1 - x0) / cols
    yin = face_y - 0.16 * sign
    for i in range(cols):
        cx = x0 + step * (i + 0.5)
        for k, z in enumerate(zs):
            g.box(cx - w / 2, cx + w / 2, min(face_y, yin), max(face_y, yin), z, z + h,
                  L.ROLE_MATTE, L.C_BLACK)
            if (i + k) % 3 == 0:
                a, b = min(face_y, yin) + 0.02 * sign, max(face_y, yin) + 0.02 * sign
                g.box(cx - w / 2 + 0.09, cx + w / 2 - 0.09, min(a, b), max(a, b),
                      z + 0.12, z + h - 0.12, L.ROLE_EMIT,
                      cell_lit if (i + k) % 2 == 0 else cell_off)


def c_hotel_core(g):
    # 10 × 12 × 26 红褐砖石酒店主体（底色压深，靠霓虹与窗光提亮）
    g.box(-5.0, 5.0, -6.0, 6.0, 0.0, 26.0, L.ROLE_MATTE, L.C_BRICK2)
    # 底层石砌基座
    g.box(-5.18, 5.18, -6.18, 6.18, 0.0, 3.2, L.ROLE_MATTE, L.C_BRICK)
    for z in (3.2, 8.2, 13.2, 18.2, 23.2):
        g.box(-5.24, 5.24, -6.24, 6.24, z, z + 0.32, L.ROLE_METAL, L.C_INDIGO)
    # 角部壁柱
    for (cx, cy) in ((4.85, 5.85), (4.85, -5.85), (-4.85, 5.85), (-4.85, -5.85)):
        g.box(cx - 0.34, cx + 0.34, cy - 0.34, cy + 0.34, 0.0, 26.0, L.ROLE_METAL, L.C_PURPLE)
    # 立面窗（东面朝大道 + 南面朝横街）
    zs = [4.1, 9.1, 14.1, 19.1, 23.7]
    # 拱窗由独立模块 hotel_arch_window_bay_02 实例化，主体只留窗台托与层间腰线
    for k, z in enumerate(zs):
        for i in range(3):
            cy = 6.6 + 2.93 * i - 11.0
            g.box(5.0, 5.16, cy - 0.95, cy + 0.95, z - 0.2, z - 0.02, L.ROLE_METAL, L.C_INDIGO)
    # 屋顶
    g.box(-5.0, 5.0, -6.0, 6.0, 26.0, 26.3, L.ROLE_MATTE, L.C_BLACK)
    for (x0, x1, y0, y1) in ((-5.0, 5.0, 5.7, 6.0), (-5.0, 5.0, -6.0, -5.7),
                             (-5.0, -4.7, -6.0, 6.0), (4.7, 5.0, -6.0, 6.0)):
        g.box(x0, x1, y0, y1, 26.3, 27.1, L.ROLE_METAL, L.C_PURPLE)
    g.cyl(1.6, 2.4, 26.3, 28.2, 1.5, L.ROLE_METAL, L.C_PURPLE2, seg=12)
    g.cyl(1.6, 2.4, 28.2, 28.35, 1.55, L.ROLE_METAL, L.C_INDIGO, seg=12)
    g.box(-3.4, -0.8, 1.2, 4.4, 26.3, 27.6, L.ROLE_METAL, L.C_PURPLE)
    g.cyl(-2.8, -3.2, 26.3, 28.3, 0.09, L.ROLE_METAL, L.C_BLACK, seg=6)
    g.box(-2.95, -2.65, -3.35, -3.05, 28.25, 28.4, L.ROLE_EMIT, L.C_CRIMSON)


def c_hotel_window_bay(g):
    # 拱形窗套模块 1.9 宽 × 0.5 深 × 3.1 高（拱在 XZ 平面，朝 -Y 外露）
    g.box(-0.95, 0.95, -0.25, 0.25, 0.0, 0.22, L.ROLE_METAL, L.C_INDIGO)
    g.box(-0.8, 0.8, -0.28, -0.16, 0.22, 2.02, L.ROLE_EMIT, L.C_AMBER)
    for sx in (-1, 1):
        g.box(sx * 0.86 - 0.11, sx * 0.86 + 0.11, -0.32, 0.06, 0.22, 2.05, L.ROLE_METAL, L.C_BRICK)
    g.box(-0.06, 0.06, -0.34, 0.02, 0.22, 2.05, L.ROLE_METAL, L.C_BRICK)
    g.box(-0.95, 0.95, -0.32, 0.02, 1.92, 2.05, L.ROLE_METAL, L.C_BRICK)
    # 半圆拱：内 0.78 / 外 0.98
    g.arc_xz(0.0, 2.05, 0.78, 0.98, -0.32, 0.06, 0.0, math.pi, L.ROLE_METAL, L.C_BRICK, seg=7)
    # 拱内暖光玻璃
    arch_pts = [(0.62 * math.cos(math.pi * i / 8), 2.05 + 0.62 * math.sin(math.pi * i / 8)) for i in range(9)]
    g.prism_xz(arch_pts, -0.28, -0.18, L.ROLE_EMIT, L.C_AMBER)
    # 窗下石台
    g.box(-1.02, 1.02, -0.34, 0.18, 0.0, 0.16, L.ROLE_METAL, L.C_BRICK2)


def c_hotel_shopfront(g):
    # 5.6 × 0.7 × 4.0 金属卷帘门 + 雨棚
    for sx in (-1, 1):
        g.box(sx * 2.7 - 0.22, sx * 2.7 + 0.22, -0.35, 0.35, 0.0, 4.0, L.ROLE_METAL, L.C_BRICK2)
    g.box(-2.5, 2.5, -0.22, 0.1, 0.0, 3.1, L.ROLE_METAL, L.C_PURPLE)
    for i in range(11):
        g.box(-2.4, 2.4, -0.28, -0.12, 0.18 + i * 0.26, 0.32 + i * 0.26, L.ROLE_GLOSS, L.C_PURPLE2)
    # 门洞
    g.box(-0.75, 0.75, -0.3, 0.12, 0.0, 2.3, L.ROLE_MATTE, L.C_BLACK)
    g.box(-0.85, 0.85, -0.34, 0.16, 2.3, 2.45, L.ROLE_EMIT, L.C_AMBER)
    # 雨棚
    g.prism([(-2.9, 0.0), (2.9, 0.0), (2.9, 1.15), (-2.9, 1.15)], 3.1, 3.28, L.ROLE_MATTE, L.C_CRIMSON)
    g.box(-2.9, 2.9, 1.05, 1.15, 3.05, 3.12, L.ROLE_EMIT, L.C_CRIMSON)
    for sx in (-1, 1):
        g.box(sx * 2.6 - 0.06, sx * 2.6 + 0.06, 1.0, 1.12, 2.2, 3.1, L.ROLE_METAL, L.C_INDIGO)
    # 店招
    g.box(-2.5, 2.5, -0.3, -0.22, 3.5, 3.95, L.ROLE_EMIT, L.C_CRIMSON)
    # 台阶
    g.box(-1.4, 1.4, 0.1, 1.0, 0.0, 0.16, L.ROLE_MATTE, L.C_GREY_MID)


def c_pharmacy_block(g):
    # 10 × 8 × 7.5 低矮药店
    g.box(-5.0, 5.0, -4.0, 4.0, 0.0, 7.5, L.ROLE_MATTE, L.C_NAVY2)
    g.box(-5.1, 5.1, -4.1, 4.1, 2.9, 3.15, L.ROLE_METAL, L.C_INDIGO)
    g.box(-5.1, 5.1, -4.1, 4.1, 0.0, 0.4, L.ROLE_MATTE, L.C_GREY_COOL)
    # 一层橱窗（东面）
    g.box(5.0, 5.12, -3.4, 3.4, 0.5, 2.7, L.ROLE_EMIT, L.C_TEAL)
    for i in range(4):
        y = -3.4 + i * 1.7
        g.box(5.12, 5.24, y - 0.07, y + 0.07, 0.5, 2.7, L.ROLE_METAL, L.C_PURPLE)
    g.box(5.12, 5.3, -3.5, 3.5, 2.7, 2.85, L.ROLE_METAL, L.C_PURPLE2)
    # 二层窗
    for i in range(4):
        y = -3.0 + i * 1.9
        g.box(5.0, 5.1, y - 0.55, y + 0.55, 3.6, 5.8, L.ROLE_MATTE, L.C_BLACK)
        g.box(5.04, 5.12, y - 0.48, y + 0.48, 3.7, 5.7, L.ROLE_EMIT, L.C_TEAL_DARK if i % 2 else L.C_AMBER2)
    # 屋顶女儿墙
    for (x0, x1, y0, y1) in ((-5.0, 5.0, 3.6, 4.0), (-5.0, 5.0, -4.0, -3.6),
                             (-5.0, -4.6, -4.0, 4.0), (4.6, 5.0, -4.0, 4.0)):
        g.box(x0, x1, y0, y1, 7.5, 8.1, L.ROLE_METAL, L.C_PURPLE)
    g.box(-2.6, -0.9, -2.4, 0.4, 7.5, 8.5, L.ROLE_METAL, L.C_PURPLE2)
    g.box(-2.7, -0.8, -2.5, 0.5, 8.5, 8.6, L.ROLE_METAL, L.C_INDIGO)


def c_bar_building(g):
    # 10 × 12 × 18 深灰金属板工业酒吧
    g.box(-5.0, 5.0, -6.0, 6.0, 0.0, 18.0, L.ROLE_METAL, L.C_PURPLE)
    for i in range(9):
        y = -5.6 + i * 1.4
        g.box(-5.16, -5.0, y - 0.1, y + 0.1, 0.0, 18.0, L.ROLE_METAL, L.C_INDIGO)
    for z in (5.0, 9.6, 14.2):
        g.box(-5.2, -5.0, -6.0, 6.0, z, z + 0.34, L.ROLE_METAL, L.C_NAVY2)
    # 西立面窄窗
    for k, z in enumerate((5.6, 10.2, 14.8)):
        for i in range(4):
            y = -4.6 + i * 2.6
            g.box(-5.08, -5.0, y - 0.7, y + 0.7, z, z + 1.2, L.ROLE_EMIT, L.C_CRIMSON if (i + k) % 2 else L.C_AMBER)
    # 底层入口
    g.box(-5.1, -4.9, -1.6, 1.6, 0.0, 3.2, L.ROLE_MATTE, L.C_BLACK)
    g.box(-5.16, -4.9, -1.7, 1.7, 3.2, 3.5, L.ROLE_EMIT, L.C_CRIMSON)
    for sx in (-1, 1):
        g.box(-5.2, -4.86, sx * 1.75 - 0.16, sx * 1.75 + 0.16, 0.0, 3.5, L.ROLE_METAL, L.C_PURPLE2)
    # 屋顶 + 排气烟囱
    g.box(-5.0, 5.0, -6.0, 6.0, 18.0, 18.3, L.ROLE_MATTE, L.C_BLACK)
    for (x0, x1, y0, y1) in ((-5.0, 5.0, 5.6, 6.0), (-5.0, 5.0, -6.0, -5.6),
                             (-5.0, -4.6, -6.0, 6.0), (4.6, 5.0, -6.0, 6.0)):
        g.box(x0, x1, y0, y1, 18.3, 19.0, L.ROLE_METAL, L.C_PURPLE)
    g.cyl(2.2, -3.4, 18.3, 22.6, 0.6, L.ROLE_METAL, L.C_PURPLE2, seg=10)
    g.cyl(2.2, -3.4, 22.6, 22.9, 0.78, L.ROLE_METAL, L.C_INDIGO, seg=10)
    g.cyl(2.2, -3.4, 22.9, 23.1, 0.5, L.ROLE_EMIT, L.C_CRIMSON, seg=10)


def c_foreground_roof(g):
    # 15 × 15 × 7.5 前景机房屋顶体量（临街面朝 +X）
    g.box(-7.5, 7.5, -7.5, 7.5, 0.0, 7.5, L.ROLE_MATTE, L.C_NAVY2)
    g.box(7.5, 7.62, -7.5, 7.5, 0.0, 2.4, L.ROLE_METAL, L.C_PURPLE)
    for i in range(10):
        g.box(7.5, 7.7, -7.2 + i * 1.5, -7.12 + i * 1.5, 0.0, 7.5, L.ROLE_METAL, L.C_INDIGO)
    # 屋顶面层
    g.box(-7.4, 7.4, -7.4, 7.4, 7.5, 7.62, L.ROLE_MATTE, L.C_GREY_COOL)
    for (x0, x1, y0, y1) in ((-7.5, 7.5, 7.1, 7.5), (-7.5, 7.5, -7.5, -7.1),
                             (-7.5, -7.1, -7.5, 7.5), (7.1, 7.5, -7.5, 7.5)):
        g.box(x0, x1, y0, y1, 7.62, 8.35, L.ROLE_MATTE, L.C_NAVY)
    # 屋顶楼梯间 + 管口
    g.box(-5.6, -2.6, 2.6, 5.6, 7.62, 10.2, L.ROLE_METAL, L.C_PURPLE)
    g.box(-2.8, -0.2, 2.4, 2.6, 7.62, 9.0, L.ROLE_METAL, L.C_PURPLE2)
    for i in range(3):
        g.cyl(3.6 + i * 1.1, -5.8, 7.62, 8.6, 0.28, L.ROLE_METAL, L.C_INDIGO, seg=8)
    # 屋顶边缘告示灯
    for i in range(4):
        g.box(-6.0 + i * 4.0, -5.4 + i * 4.0, -7.55, -7.42, 7.9, 8.1, L.ROLE_EMIT, L.C_CRIMSON)


def c_backdrop_tower(g):
    # 10 × 7 × 27.4 背景高楼（临街面朝 +X）
    g.box(-5.0, 5.0, -3.5, 3.5, 0.0, 27.4, L.ROLE_MATTE, L.C_NAVY)
    for k in range(7):
        z = 3.0 + k * 3.6
        g.box(-5.1, 5.1, -3.6, 3.6, z, z + 0.3, L.ROLE_METAL, L.C_PURPLE)
    for k in range(7):
        for i in range(3):
            y = -2.4 + i * 2.4
            lit = (i + k) % 4 == 0
            g.box(5.0, 5.08, y - 0.8, y + 0.8, 3.9 + k * 3.6, 5.6 + k * 3.6,
                  L.ROLE_EMIT if lit else L.ROLE_MATTE,
                  L.C_AMBER if lit else L.C_BLACK)
    g.box(-5.0, 5.0, -3.5, 3.5, 27.4, 27.8, L.ROLE_METAL, L.C_PURPLE)
    g.cyl(0.0, 0.0, 27.8, 28.5, 0.1, L.ROLE_METAL, L.C_BLACK, seg=6)
    g.box(-0.12, 0.12, -0.12, 0.12, 28.4, 28.55, L.ROLE_EMIT, L.C_CRIMSON)


# ================================================================ D 霓虹标识


def _seg_digit(g, x, z, w, h, t, segs, role, cell, plane="xz", y=0.0):
    """七段式字符笔画（竖平面，法线朝 +Y 或 -Y）。"""
    def bar(x0, z0, x1, z1):
        if plane == "xz":
            g.box(x + x0 * w, x + x1 * w, y - t / 2, y + t / 2, z + z0 * h, z + z1 * h, role, cell)

    m = 0.09
    if "t" in segs:
        bar(-0.5, 1 - h * 0 + (1 - 1), 0.5, 1)
    if "b" in segs:
        bar(-0.5, 0.0, 0.5, m)
    if "l" in segs:
        bar(-0.5, 0.0, -0.5 + m, 1)
    if "r" in segs:
        bar(0.5 - m, 0.0, 0.5, 1)
    if "m" in segs:
        bar(-0.5, 0.5 - m / 2, 0.5, 0.5 + m / 2)


GLYPHS = {
    "H": "lr m", "O": "lr tb", "T": "t m", "E": "l tb m", "L": "l b",
    "B": "l tb m", "A": "lr t m", "R": "lr t m",
}


def _letter(g, ch, cx, z0, w, h, t, role, cell, y_face=0.0, stroke=0.17):
    segs = GLYPHS.get(ch, "")
    if not segs:
        return
    m = stroke
    def bar(x0, x1, za, zb):
        g.box(cx + x0 * w, cx + x1 * w, y_face - t, y_face, z0 + za * h, z0 + zb * h, role, cell)
    if "t" in segs:
        bar(-0.5, 0.5, 1 - m, 1)
    if "b" in segs:
        bar(-0.5, 0.5, 0, m)
    if "m" in segs:
        bar(-0.5, 0.5, 0.5 - m / 2, 0.5 + m / 2)
    if "l" in segs:
        bar(-0.5, -0.5 + m, 0, 1)
    if "r" in segs:
        bar(0.5 - m, 0.5, 0, 1)


def c_neon_hotel_vertical(g):
    # 竖向 HOTEL 招牌 1.9 × 0.6 × 11.4（参考图主视觉焦点；正面朝 -Y）
    g.box(-0.95, 0.95, -0.25, 0.35, 0.0, 11.4, L.ROLE_METAL, L.C_BLACK)
    # 字面所在的面板
    g.box(-0.93, 0.93, -0.34, -0.24, 0.08, 11.32, L.ROLE_MATTE, L.C_NAVY2)
    # 字：笔画浮在面板外侧 -0.34 之外；参考图读序自上而下 H→O→T→E→L
    for i, ch in enumerate("HOTEL"):
        _letter(g, ch, 0.0, 0.95 + (4 - i) * 1.95, 1.55, 1.45, 0.07,
                L.ROLE_EMIT, L.C_CRIMSON, y_face=-0.34, stroke=0.19)
    # 边框霓虹
    for z0, z1 in ((0.0, 0.12), (11.28, 11.4)):
        g.box(-0.95, 0.95, -0.38, -0.30, z0, z1, L.ROLE_EMIT, L.C_CRIMSON)
    for sx in (-1, 1):
        g.box(sx * 0.95 - 0.07, sx * 0.95 + 0.07, -0.38, -0.30, 0.0, 11.4, L.ROLE_EMIT, L.C_CRIMSON)
    # 支架（连接立面，朝 +Y）
    for z in (2.4, 7.0, 10.6):
        g.box(-1.05, 1.05, 0.3, 1.4, z, z + 0.24, L.ROLE_METAL, L.C_INDIGO)
    # 顶部 NEXUS 副牌
    g.box(-0.98, 0.98, -0.32, 0.3, 11.5, 12.3, L.ROLE_METAL, L.C_BLACK)
    g.box(-0.9, 0.9, -0.38, -0.32, 11.56, 12.24, L.ROLE_EMIT, L.C_MAGENTA)


def c_neon_pharmacy(g):
    # 方形 藥 招牌 3.2 × 0.35 × 3.2
    g.box(-1.6, 1.6, -0.18, 0.18, 0.0, 3.2, L.ROLE_METAL, L.C_BLACK)
    g.box(-1.52, 1.52, -0.22, -0.14, 0.1, 3.1, L.ROLE_EMIT, L.C_BLUE)
    # 十字药徽
    g.box(-0.22, 0.22, -0.26, -0.2, 0.9, 2.4, L.ROLE_EMIT, L.C_TEAL)
    g.box(-0.75, 0.75, -0.26, -0.2, 1.45, 1.89, L.ROLE_EMIT, L.C_TEAL)
    # 笔画（繁体感）
    for i in range(3):
        g.box(-1.2, -0.55, -0.26, -0.2, 0.5 + i * 0.3, 0.62 + i * 0.3, L.ROLE_EMIT, L.C_TEAL)
        g.box(0.55, 1.2, -0.26, -0.2, 0.5 + i * 0.3, 0.62 + i * 0.3, L.ROLE_EMIT, L.C_TEAL)
    # 边框
    for (x0, x1, z0, z1) in ((-1.6, 1.6, 3.16, 3.28), (-1.6, 1.6, -0.12, 0.0),
                             (-1.66, -1.54, 0.0, 3.2), (1.54, 1.66, 0.0, 3.2)):
        g.box(x0, x1, -0.24, -0.16, z0, z1, L.ROLE_EMIT, L.C_MAGENTA)
    # 副牌
    g.box(-1.0, 1.0, -0.24, -0.16, 3.45, 3.95, L.ROLE_EMIT, L.C_PURPLE2)


def c_neon_bar_vertical(g):
    # 竖向 BAR 招牌 1.5 × 0.45 × 6.4（正面朝 -Y）
    g.box(-0.75, 0.75, -0.2, 0.25, 0.0, 6.4, L.ROLE_METAL, L.C_BLACK)
    g.box(-0.7, 0.7, -0.28, -0.19, 0.12, 3.42, L.ROLE_MATTE, L.C_BLACK)
    for i, ch in enumerate("BAR"):
        _letter(g, ch, 0.0, 0.5 + i * 1.0, 0.94, 0.9, 0.07,
                L.ROLE_EMIT, L.C_CRIMSON, y_face=-0.28, stroke=0.2)
    # 鸡尾酒杯（三角杯 + 杯柄 + 底座）
    g.prism_xz([(-0.42, 1.32), (0.42, 1.32), (0.05, 0.52), (-0.05, 0.52)], -0.26, -0.19,
               L.ROLE_EMIT, L.C_TEAL)
    g.box(-0.045, 0.045, -0.26, -0.19, 0.9, 1.34, L.ROLE_EMIT, L.C_TEAL)
    g.box(-0.26, 0.26, -0.26, -0.19, 0.86, 0.96, L.ROLE_EMIT, L.C_TEAL)
    for sx in (-1, 1):
        g.box(sx * 0.75 - 0.06, sx * 0.75 + 0.06, -0.3, -0.22, 0.0, 6.4, L.ROLE_EMIT, L.C_MAGENTA)
    for z in (1.4, 5.2):
        g.box(-0.85, 0.85, 0.2, 0.95, z, z + 0.2, L.ROLE_METAL, L.C_INDIGO)


def c_sector_sign(g):
    # SECTOR 07 / 東區 高架铭牌 9.0 × 0.4 × 2.4
    g.box(-4.5, 4.5, -0.2, 0.2, 0.0, 2.4, L.ROLE_METAL, L.C_BLACK)
    g.box(-4.44, 4.44, -0.25, -0.18, 0.06, 2.34, L.ROLE_MATTE, L.C_NAVY2)
    # 左半斜纹警示
    for i in range(4):
        g.beam((-4.3 + i * 0.5, -0.26, 0.15), (-3.9 + i * 0.5, -0.26, 2.25), 0.2, 0.05, L.ROLE_MATTE, L.C_AMBER2)
    # SECTOR 07 数字条
    g.box(-3.6, -1.2, -0.28, -0.22, 1.0, 1.75, L.ROLE_EMIT, L.C_AMBER)
    g.box(-3.6, -1.2, -0.28, -0.22, 0.35, 0.85, L.ROLE_EMIT, L.C_AMBER)
    # 東區 横条（简笔）
    for i in range(4):
        g.box(0.1 + i * 1.0, 0.94 + i * 1.0, -0.28, -0.22, 0.9, 1.9, L.ROLE_EMIT, L.C_CRIMSON)
    for i in range(3):
        g.box(0.1 + i * 1.0, 0.94 + i * 1.0, -0.28, -0.22, 0.4, 0.55, L.ROLE_EMIT, L.C_CRIMSON)
    # 外框
    for (x0, x1, z0, z1) in ((-4.5, 4.5, 2.34, 2.44), (-4.5, 4.5, -0.04, 0.06),
                             (-4.56, -4.44, 0.0, 2.4), (4.44, 4.56, 0.0, 2.4)):
        g.box(x0, x1, -0.3, -0.22, z0, z1, L.ROLE_EMIT, L.C_AMBER)


def c_blade_sign(g):
    # 小型灯箱刀旗组 0.9 × 0.9 × 4.2（三块）
    g.box(-0.12, 0.12, -0.12, 0.12, 0.0, 4.2, L.ROLE_METAL, L.C_PURPLE)
    specs = [(0.6, 0.9, L.C_TEAL), (1.9, 1.2, L.C_CRIMSON), (3.1, 0.9, L.C_AMBER)]
    for z0, h, cell in specs:
        g.box(-0.95, 0.95, -0.12, 0.12, z0, z0 + h, L.ROLE_METAL, L.C_BLACK)
        g.box(-0.88, 0.88, -0.16, -0.1, z0 + 0.08, z0 + h - 0.08, L.ROLE_EMIT, cell)
        g.box(0.12, 0.95, -0.08, 0.08, z0 + h / 2 - 0.06, z0 + h / 2 + 0.06, L.ROLE_METAL, L.C_INDIGO)


# ================================================================ E 跨街与吊顶


def c_skybridge(g):
    # 21m 跨街走廊（沿 X 展开，纵深 Y 3.2）
    g.box(-10.5, 10.5, -1.6, 1.6, 12.8, 13.1, L.ROLE_METAL, L.C_PURPLE)
    g.box(-10.5, 10.5, -1.6, 1.6, 13.1, 13.25, L.ROLE_MATTE, L.C_GREY_COOL)
    for sy in (-1, 1):
        g.box(-10.5, 10.5, sy * 1.6 - 0.12, sy * 1.6 + 0.12, 12.8, 14.9, L.ROLE_METAL, L.C_INDIGO)
        g.box(-10.5, 10.5, sy * 1.72 - 0.06, sy * 1.72 + 0.06, 14.1, 14.35, L.ROLE_EMIT, L.C_AMBER)
        # 侧面斜撑
        x = -10.0
        while x < 10.0:
            g.beam((x, sy * 1.66, 12.9), (x + 1.6, sy * 1.66, 14.8), 0.12, 0.12, L.ROLE_METAL, L.C_PURPLE)
            g.beam((x + 1.6, sy * 1.66, 12.9), (x, sy * 1.66, 14.8), 0.12, 0.12, L.ROLE_METAL, L.C_PURPLE)
            x += 1.6
        # 腹板黄黑警示斜纹（桥体主识别特征）
        for i in range(10):
            x0 = -10.2 + i * 2.05
            g.box(x0, x0 + 1.0, sy * 1.74 - 0.04, sy * 1.74 + 0.04, 13.32, 13.95,
                  L.ROLE_MATTE, L.C_AMBER2 if i % 2 else L.C_BLACK)
    # 屋面
    g.box(-10.5, 10.5, -1.9, 1.9, 15.4, 15.75, L.ROLE_METAL, L.C_PURPLE2)
    for i in range(11):
        g.box(-10.0 + i * 2.0, -9.72 + i * 2.0, -1.95, 1.95, 15.75, 16.0, L.ROLE_METAL, L.C_PURPLE)
    # 玻璃窗带
    g.box(-10.2, 10.2, -1.62, -1.56, 13.98, 15.3, L.ROLE_GLOSS, L.C_BLUE_DARK)
    g.box(-10.2, 10.2, 1.56, 1.62, 13.98, 15.3, L.ROLE_GLOSS, L.C_BLUE_DARK)
    for i in range(9):
        g.box(-9.6 + i * 2.4 - 0.06, -9.6 + i * 2.4 + 0.06, -1.68, -1.54, 13.98, 15.3,
              L.ROLE_METAL, L.C_PURPLE2)
    # 桥下管线
    for y in (-0.9, 0.0, 0.9):
        g.cyl_x(-10.4, 10.4, y, 12.55, 0.17, L.ROLE_METAL, L.C_PURPLE2, seg=8)
    g.box(-10.4, 10.4, -1.3, 1.3, 12.3, 12.42, L.ROLE_METAL, L.C_BLACK)
    # 桥端连接口
    for sx in (-1, 1):
        g.box(sx * 10.5 - 0.2, sx * 10.5 + 0.2, -1.7, 1.7, 12.6, 15.6, L.ROLE_METAL, L.C_PURPLE)


def c_bridge_pillar(g):
    # 12.8m 警示条纹支撑柱
    g.box(-0.75, 0.75, -0.75, 0.75, 0.0, 0.45, L.ROLE_MATTE, L.C_NAVY2)
    g.box(-0.62, 0.62, -0.62, 0.62, 0.45, 12.4, L.ROLE_METAL, L.C_PURPLE)
    for i in range(9):
        z = 0.45 + i * 0.42
        for (x0, x1, y0, y1) in ((-0.62, 0.62, -0.66, -0.62), (-0.62, 0.62, 0.62, 0.66)):
            g.box(x0, x1, y0, y1, z, z + 0.24, L.ROLE_MATTE, L.C_AMBER2 if i % 2 else L.C_BLACK)
    g.box(-0.9, 0.9, -0.9, 0.9, 12.4, 12.8, L.ROLE_METAL, L.C_PURPLE)
    for z in (3.0, 6.4, 9.8):
        g.box(-0.68, 0.68, -0.68, 0.68, z, z + 0.18, L.ROLE_EMIT, L.C_AMBER)
    g.box(0.62, 0.7, -0.3, 0.3, 2.0, 2.6, L.ROLE_EMIT, L.C_CRIMSON)


def c_duct_bundle(g):
    # 20m 吊顶风管管束
    for (y, w, h, z0, cell) in ((-0.95, 1.25, 0.85, 0.0, L.C_PURPLE2), (0.95, 1.05, 0.7, 0.05, L.C_PURPLE)):
        g.box(-10.0, 10.0, y - w / 2, y + w / 2, z0, z0 + h, L.ROLE_METAL, cell)
        for i in range(9):
            g.box(-9.2 + i * 2.3, -9.05 + i * 2.3, y - w / 2 - 0.06, y + w / 2 + 0.06,
                  z0 - 0.05, z0 + h + 0.05, L.ROLE_METAL, L.C_INDIGO)
    for (y, r, cell) in ((-2.35, 0.16, L.C_INDIGO), (-2.85, 0.11, L.C_PURPLE2), (2.5, 0.13, L.C_BLUE)):
        g.cyl_x(-10.0, 10.0, y, 0.9, r, L.ROLE_METAL, cell, seg=8)
    # 吊杆
    for x in (-9.0, -4.5, 0.0, 4.5, 9.0):
        for y in (-1.9, 1.9):
            g.cyl(x, y, 0.9, 3.2, 0.045, L.ROLE_METAL, L.C_BLACK, seg=6)
        g.box(x - 0.06, x + 0.06, -3.0, 2.65, 3.1, 3.2, L.ROLE_METAL, L.C_INDIGO)


def c_hanging_lamp(g):
    g.cyl(0.0, 0.0, 0.0, 0.06, 0.62, L.ROLE_EMIT, L.C_AMBER, seg=12)
    g.cyl(0.0, 0.0, 0.06, 0.5, 0.66, L.ROLE_METAL, L.C_PURPLE, seg=12, r2=0.2)
    g.cyl(0.0, 0.0, 0.5, 0.62, 0.2, L.ROLE_METAL, L.C_INDIGO, seg=8)
    g.cyl(0.0, 0.0, 0.62, 2.08, 0.04, L.ROLE_METAL, L.C_BLACK, seg=6)
    g.box(-0.32, 0.32, -0.32, 0.32, 2.04, 2.12, L.ROLE_METAL, L.C_INDIGO)


def c_ceiling_fan(g):
    # 3.2m 吊顶排风机
    g.box(-1.6, 1.6, -1.6, 1.6, 0.0, 0.55, L.ROLE_METAL, L.C_PURPLE)
    for i in range(5):
        g.box(-1.5, 1.5, -1.5 + i * 0.62, -1.35 + i * 0.62, -0.1, 0.0, L.ROLE_METAL, L.C_BLACK)
    g.cyl(0.0, 0.0, -0.12, 0.02, 0.5, L.ROLE_METAL, L.C_INDIGO, seg=12)
    g.cyl(0.0, 0.0, -0.16, -0.12, 0.4, L.ROLE_EMIT, L.C_AMBER2, seg=12)
    for sx in (-1, 1):
        for sy in (-1, 1):
            g.cyl(sx * 1.35, sy * 1.35, 0.55, 0.78, 0.06, L.ROLE_METAL, L.C_BLACK, seg=6)


# ================================================================ F 街道设施


def c_street_lamp(g):
    g.cyl(0.0, 0.0, 0.0, 0.4, 0.26, L.ROLE_METAL, L.C_PURPLE, seg=10)
    g.cyl(0.0, 0.0, 0.4, 7.0, 0.11, L.ROLE_METAL, L.C_PURPLE2, seg=10)
    for sx in (-1, 1):
        g.beam((0.0, 0.0, 6.4), (sx * 1.7, 0.0, 7.0), 0.13, 0.13, L.ROLE_METAL, L.C_PURPLE2)
        g.box(sx * 1.5, sx * 2.1, -0.22, 0.22, 6.82, 7.02, L.ROLE_METAL, L.C_INDIGO)
        g.box(sx * 1.55, sx * 2.05, -0.18, 0.18, 6.78, 6.83, L.ROLE_EMIT, L.C_TEAL)
    # 信号灯 + 配电箱
    g.box(-0.22, 0.22, -0.24, 0.24, 3.4, 4.4, L.ROLE_METAL, L.C_BLACK)
    for i, cell in enumerate((L.C_CRIMSON, L.C_AMBER, L.C_TEAL)):
        g.box(-0.16, 0.16, -0.28, -0.2, 3.55 + i * 0.28, 3.75 + i * 0.28, L.ROLE_EMIT, cell)
    g.box(0.11, 0.42, -0.28, 0.28, 1.6, 2.5, L.ROLE_METAL, L.C_PURPLE)
    g.box(0.11, 0.44, -0.3, -0.26, 1.9, 2.4, L.ROLE_EMIT, L.C_AMBER)


def c_bollard(g):
    g.cyl(0.0, 0.0, 0.0, 0.08, 0.28, L.ROLE_METAL, L.C_PURPLE2, seg=10)
    g.cyl(0.0, 0.0, 0.08, 1.05, 0.14, L.ROLE_METAL, L.C_PURPLE, seg=10)
    for i in range(3):
        g.cyl(0.0, 0.0, 0.2 + i * 0.28, 0.3 + i * 0.28, 0.15, L.ROLE_EMIT, L.C_CRIMSON, seg=10)
    g.cyl(0.0, 0.0, 1.05, 1.12, 0.1, L.ROLE_EMIT, L.C_AMBER, seg=8)


def c_guardrail(g):
    # 4m 金属防护栏杆
    for x in (-1.9, 0.0, 1.9):
        g.box(x - 0.06, x + 0.06, -0.06, 0.06, 0.0, 1.05, L.ROLE_METAL, L.C_PURPLE2)
        g.box(x - 0.13, x + 0.13, -0.13, 0.13, 0.0, 0.06, L.ROLE_METAL, L.C_PURPLE)
    for z in (0.35, 0.95):
        g.box(-2.0, 2.0, -0.05, 0.05, z, z + 0.09, L.ROLE_METAL, L.C_PURPLE)
    for i in range(12):
        g.box(-1.85 + i * 0.32, -1.79 + i * 0.32, -0.02, 0.02, 0.44, 0.95, L.ROLE_METAL, L.C_INDIGO)


def c_utility_cabinet(g):
    g.box(-0.7, 0.7, -0.4, 0.4, 0.0, 1.7, L.ROLE_METAL, L.C_PURPLE)
    g.box(-0.62, 0.62, -0.44, -0.38, 0.1, 1.55, L.ROLE_METAL, L.C_NAVY2)
    g.box(-0.3, 0.3, -0.47, -0.4, 1.15, 1.35, L.ROLE_EMIT, L.C_TEAL)
    for i in range(4):
        g.box(-0.5, 0.5, -0.46, -0.42, 0.25 + i * 0.2, 0.33 + i * 0.2, L.ROLE_METAL, L.C_BLACK)
    g.cyl(0.95, 0.0, 0.0, 0.95, 0.34, L.ROLE_METAL, L.C_PURPLE2, seg=10)
    g.cyl(0.95, 0.0, 0.95, 1.0, 0.36, L.ROLE_METAL, L.C_BLACK, seg=10)
    g.box(-0.3, 0.3, 0.1, 0.2, 1.7, 0.0, L.ROLE_METAL, L.C_BLACK)


def c_sedan(g):
    # 4.6 × 1.9 × 1.45 复古方正轿车（车头朝 +X）
    g.box(-2.3, 2.3, -0.95, 0.95, 0.32, 0.95, L.ROLE_GLOSS, L.C_PURPLE)
    g.box(-1.55, 1.15, -0.86, 0.86, 0.95, 1.42, L.ROLE_GLOSS, L.C_INDIGO)
    g.box(-1.45, 1.0, -0.8, 0.8, 1.05, 1.4, L.ROLE_GLOSS, L.C_BLUE_DARK)
    g.box(-2.34, 2.34, -0.9, 0.9, 0.62, 0.78, L.ROLE_METAL, L.C_PURPLE2)
    g.box(-2.3, 2.3, -0.96, 0.96, 0.28, 0.34, L.ROLE_METAL, L.C_BLACK)
    for ax in (-1.45, 1.45):
        for sy in (-1, 1):
            g.cyl_y(sy * 0.86, sy * 1.02, ax, 0.34, 0.34, L.ROLE_MATTE, L.C_BLACK, seg=12)
            g.cyl_y(sy * 0.88, sy * 0.98, ax, 0.34, 0.17, L.ROLE_METAL, L.C_INDIGO, seg=10)
    for sy in (-1, 1):
        g.box(2.2, 2.34, sy * 0.56 - 0.2, sy * 0.56 + 0.2, 0.6, 0.78, L.ROLE_EMIT, L.C_AMBER)
        g.box(-2.34, -2.2, sy * 0.56 - 0.22, sy * 0.56 + 0.22, 0.62, 0.8, L.ROLE_EMIT, L.C_CRIMSON)
    g.box(2.3, 2.36, -0.3, 0.3, 0.45, 0.6, L.ROLE_EMIT, L.C_AMBER)
    for sy in (-1, 1):
        g.box(0.6, 0.75, sy * 1.0 - 0.12, sy * 1.0 + 0.12, 1.05, 1.2, L.ROLE_METAL, L.C_PURPLE2)


def c_roof_chiller(g):
    g.box(-1.3, 1.3, -0.8, 0.8, 0.0, 1.45, L.ROLE_METAL, L.C_PURPLE)
    g.box(-1.35, 1.35, -0.85, 0.85, 1.45, 1.55, L.ROLE_METAL, L.C_INDIGO)
    for sx in (-0.6, 0.6):
        g.cyl(sx, 0.0, 1.55, 1.62, 0.5, L.ROLE_METAL, L.C_BLACK, seg=12)
        g.cyl(sx, 0.0, 1.62, 1.66, 0.44, L.ROLE_EMIT, L.C_TEAL_DARK, seg=12)
        g.cyl(sx, 0.0, 1.66, 1.7, 0.1, L.ROLE_METAL, L.C_PURPLE2, seg=8)
    for i in range(5):
        g.box(-1.2 + i * 0.5, -1.12 + i * 0.5, -0.84, -0.78, 0.2, 1.2, L.ROLE_METAL, L.C_BLACK)
    g.cyl(1.15, 0.6, 1.55, 2.5, 0.08, L.ROLE_METAL, L.C_INDIGO, seg=6)
    g.box(-1.4, -1.3, -0.6, 0.6, 0.0, 0.12, L.ROLE_METAL, L.C_BLACK)


def c_roof_vent(g):
    g.box(-0.7, 0.7, -0.5, 0.5, 0.0, 1.6, L.ROLE_METAL, L.C_PURPLE)
    for i in range(6):
        g.box(-0.6, 0.6, -0.56, -0.5, 0.15 + i * 0.22, 0.28 + i * 0.22, L.ROLE_METAL, L.C_INDIGO)
    g.box(-0.82, 0.82, -0.62, 0.62, 1.6, 1.74, L.ROLE_METAL, L.C_PURPLE2)
    g.cyl(0.0, 0.0, 1.74, 2.3, 0.22, L.ROLE_METAL, L.C_PURPLE2, seg=8)
    g.cyl(0.0, 0.0, 2.3, 2.36, 0.3, L.ROLE_METAL, L.C_BLACK, seg=8)


def c_wall_ac(g):
    g.box(-0.45, 0.45, -0.2, 0.2, 0.0, 0.6, L.ROLE_MATTE, L.C_GREY_MID)
    g.box(-0.42, 0.42, -0.24, -0.18, 0.06, 0.54, L.ROLE_METAL, L.C_INDIGO)
    g.cyl(0.0, -0.26, 0.3, 0.3, 0.19, L.ROLE_METAL, L.C_BLACK, seg=10)
    for sx in (-1, 1):
        g.box(sx * 0.35 - 0.04, sx * 0.35 + 0.04, 0.2, 0.3, -0.16, 0.02, L.ROLE_METAL, L.C_BLACK)
    g.cyl(0.3, 0.15, -0.6, 0.02, 0.04, L.ROLE_METAL, L.C_PURPLE2, seg=6)


def c_pipe_cluster(g):
    # 6m 竖向管道束
    for (dx, dy, r, cell) in ((-0.22, 0.0, 0.12, L.C_PURPLE2), (0.0, 0.18, 0.09, L.C_INDIGO), (0.2, -0.1, 0.07, L.C_PURPLE)):
        g.cyl(dx, dy, 0.0, 6.0, r, L.ROLE_METAL, cell, seg=8)
        for z in (1.2, 3.4, 5.4):
            g.cyl(dx, dy, z, z + 0.16, r * 1.35, L.ROLE_METAL, L.C_NAVY2, seg=8)
    for z in (0.6, 3.0, 5.2):
        g.box(-0.42, 0.42, -0.26, 0.3, z, z + 0.12, L.ROLE_METAL, L.C_BLACK)
    g.cyl(0.0, 0.18, 4.5, 4.58, 0.2, L.ROLE_METAL, L.C_PURPLE2, seg=8)


def c_pipe_elbow(g):
    g.cyl_x(-1.8, 1.2, 0.0, 0.0, 0.13, L.ROLE_METAL, L.C_PURPLE2, seg=8)
    g.cyl(1.2, 0.0, -0.9, 0.0, 0.13, L.ROLE_METAL, L.C_PURPLE2, seg=8)
    g.box(-1.9, 1.3, -0.2, 0.2, -0.06, 0.06, L.ROLE_METAL, L.C_BLACK)
    g.cyl_x(-1.8, 1.3, 0.32, 0.3, 0.07, L.ROLE_METAL, L.C_INDIGO, seg=6)
    for x in (-1.5, 0.6):
        g.box(x - 0.06, x + 0.06, -0.2, 0.24, 0.06, 0.4, L.ROLE_METAL, L.C_NAVY2)


def c_fire_stair(g):
    # 外挂消防梯：一段平台 + 一段梯跑
    g.box(-1.7, 1.7, 0.0, 1.25, 0.0, 0.12, L.ROLE_METAL, L.C_PURPLE)
    for i in range(7):
        g.box(-1.6, -0.9 + i * 0.36, 0.0, 1.2, 0.0, 0.06, L.ROLE_METAL, L.C_INDIGO)
    for sx in (-1, 1):
        g.beam((sx * 1.65, 1.2, 0.12), (sx * 1.65, 0.05, 2.3), 0.1, 0.1, L.ROLE_METAL, L.C_PURPLE)
        g.box(sx * 1.65 - 0.05, sx * 1.65 + 0.05, 1.15, 1.25, 0.12, 1.05, L.ROLE_METAL, L.C_PURPLE2)
    g.box(-1.72, 1.72, 1.2, 1.28, 1.0, 1.08, L.ROLE_METAL, L.C_PURPLE2)
    # 梯跑
    for i in range(8):
        g.box(-0.55, 0.55, 0.3 + i * 0.32, 1.15 + i * 0.32, 2.3 + i * 0.3, 2.38 + i * 0.3,
              L.ROLE_METAL, L.C_INDIGO)
    for sx in (-1, 1):
        g.beam((sx * 0.62, 0.9, 2.3), (sx * 0.62, 3.8, 4.6), 0.08, 0.08, L.ROLE_METAL, L.C_PURPLE2)


def c_rubble(g):
    base = [(-1.4, -0.9), (1.2, -1.1), (1.6, 0.4), (0.2, 1.3), (-1.5, 0.8)]
    g.prism(base, 0.0, 0.45, L.ROLE_MATTE, L.C_BLACK)
    g.prism([(p[0] * 0.62 + 0.1, p[1] * 0.62) for p in base], 0.45, 0.78, L.ROLE_MATTE, L.C_NAVY2)
    for (x, y, r) in ((-0.8, 0.2, 0.3), (0.9, -0.3, 0.24), (0.2, 0.75, 0.2)):
        g.cyl(x, y, 0.0, 0.5, r, L.ROLE_MATTE, L.C_GREY_COOL, seg=7)
    g.box(-0.2, 0.5, 0.1, 0.5, 0.78, 0.9, L.ROLE_METAL, L.C_PURPLE2)


def c_sky_cable(g):
    # 24m 跨街电缆束（两根悬链 + 吊环）
    for sy, sag, r, cell in ((-0.55, 1.7, 0.045, L.C_BLACK), (0.55, 2.1, 0.035, L.C_PURPLE2)):
        prev = None
        for i in range(13):
            t = i / 12
            x = -12.0 + 24.0 * t
            z = 21.5 - sag * math.sin(math.pi * t)
            p = (x, sy, z)
            if prev:
                g.beam(prev, p, r * 2, r * 2, L.ROLE_METAL, cell)
            prev = p
    for sy in (-0.55, 0.55):
        for i in range(5):
            x = -10.0 + i * 5.0
            g.cyl(x, sy, 21.0, 21.6, 0.05, L.ROLE_METAL, L.C_BLACK, seg=5)
    # 悬挂的小灯串
    for i in range(9):
        x = -11.0 + i * 2.75
        z = 21.5 - 1.9 * math.sin(math.pi * (x + 12.0) / 24.0) - 0.35
        g.cyl(x, 0.0, z, z + 0.22, 0.09, L.ROLE_EMIT, L.C_AMBER2 if i % 2 else L.C_CRIMSON, seg=6)
    g.box(-12.0, -11.6, -0.7, 0.7, 21.4, 21.8, L.ROLE_METAL, L.C_PURPLE)
    g.box(11.6, 12.0, -0.7, 0.7, 21.4, 21.8, L.ROLE_METAL, L.C_PURPLE)


# ================================================================ 登记组件
comp("cavern_base_slab_52x52_01", "地下街区基底岩板_52x52m_01", "base_slab", "structural", c_base_slab)
comp("cavern_wall_module_10x30_01", "地下岩壁混凝土衬砌模块_10x30m_01", "cavern_wall", "structural", c_cavern_wall)
comp("cavern_ceiling_slab_52x52_01", "地下街区拱顶板与梁格_52x52m_01", "ceiling", "structural", c_cavern_ceiling)
comp("ceiling_truss_rib_52m_01", "顶板钢桁架横梁_52m_01", "ceiling_truss", "structural", c_ceiling_truss)
comp("tunnel_portal_arch_10m_01", "隧道口拱门墙_10x30m_01", "portal", "structural", c_tunnel_portal)
comp("cavern_support_column_30m_01", "地下支撑巨柱_30m_01", "cavern_column", "structural", c_support_column)

comp("wet_asphalt_lane_10x10_01", "湿润双黄线柏油车道_10x10m_01", "road_deck", "floor", c_road_lane)
comp("wet_asphalt_film_10x10_02", "湿润反光膜覆盖层_10x10m_02", "road_wet_film", "floor", c_road_wet_layer)
comp("wet_asphalt_crosswalk_10x5_02", "湿润斑马线覆盖层_10x5m_02", "road_marking", "floor", c_road_crosswalk)
comp("wet_asphalt_intersection_10x10_03", "湿润柏油十字路口_10x10m_03", "road_deck", "floor", c_road_intersection)
comp("sidewalk_tile_5x5_01", "人行道石砖与路缘_5x5m_01", "sidewalk", "floor", c_sidewalk_tile)
comp("puddle_reflect_patch_04", "湿面反光水洼贴片_04", "wet_detail", "floor", c_puddle)
comp("wet_reflect_streak_05", "湿路面霓虹倒影拉丝_05", "wet_detail", "floor", c_wet_reflect_streak)
comp("drain_manhole_grate_set_01", "铸铁井盖与排水格栅组_01", "drain_detail", "floor", c_manhole_set)

comp("hotel_brick_tower_core_10x12_01", "红褐砖石老旧酒店主体_10x12m_01", "hotel", "structural", c_hotel_core)
comp("hotel_arch_window_bay_02", "酒店暖光拱形窗套_02", "hotel_window", "structural", c_hotel_window_bay)
comp("hotel_shutter_shopfront_03", "酒店底层卷帘门与雨棚入口_03", "shopfront", "structural", c_hotel_shopfront)
comp("pharmacy_shop_block_10x8_01", "低矮药店商业楼体_10x8m_01", "pharmacy", "structural", c_pharmacy_block)
comp("industrial_bar_building_10x12_01", "深灰金属板工业酒吧楼_10x12m_01", "bar_building", "structural", c_bar_building)
comp("foreground_service_roof_15x15_01", "前景机房屋顶体量_15x15m_01", "service_roof", "structural", c_foreground_roof)
comp("backdrop_tower_block_10x7_01", "背景高楼体量_10x7x29m_01", "backdrop_tower", "structural", c_backdrop_tower)

comp("neon_sign_hotel_vertical_01", "竖向 HOTEL 霓虹主招牌_01", "neon_sign_vertical", "facility", c_neon_hotel_vertical)
comp("neon_sign_pharmacy_kanji_02", "方形藥字发光招牌_02", "neon_sign_board", "facility", c_neon_pharmacy)
comp("neon_sign_bar_vertical_03", "竖向 BAR 与鸡尾酒杯霓虹_03", "neon_sign_vertical", "facility", c_neon_bar_vertical)
comp("skybridge_sign_sector07_04", "SECTOR07 東區 高架铭牌_04", "neon_sign_board", "facility", c_sector_sign)
comp("neon_blade_sign_cluster_05", "小型灯箱刀旗组_05", "neon_sign_blade", "facility", c_blade_sign)

comp("skybridge_truss_span_21m_01", "跨街重型装甲走廊_21m_01", "skybridge", "structural", c_skybridge)
comp("skybridge_hazard_pillar_02", "黄黑警示条纹支撑柱_12.8m_02", "bridge_pillar", "structural", c_bridge_pillar)
comp("ceiling_duct_bundle_20m_01", "吊顶风管管束_20m_01", "ceiling_service", "support", c_duct_bundle)
comp("hanging_lamp_industrial_01", "工业吊灯_01", "ceiling_light", "support", c_hanging_lamp)
comp("ceiling_exhaust_fan_3x3_01", "吊顶排风机_3x3m_01", "ceiling_service", "support", c_ceiling_fan)

comp("industrial_street_lamp_pole_01", "双臂工业路灯与信号灯杆_01", "street_lamp", "facility", c_street_lamp)
comp("glowing_hazard_bollard_02", "发光警示防撞柱_02", "street_bollard", "facility", c_bollard)
comp("street_guardrail_fence_4m_01", "人行道金属防护栏杆_4m_01", "street_guardrail", "facility", c_guardrail)
comp("street_utility_cabinet_02", "街道配电控制箱与垃圾箱组_02", "street_utility", "facility", c_utility_cabinet)
comp("retro_cyber_sedan_car_01", "复古方正深色轿车_01", "vehicle", "facility", c_sedan)
comp("rooftop_twin_fan_chiller_01", "屋顶双风扇冷却机组_01", "roof_equipment", "facility", c_roof_chiller)
comp("rooftop_exhaust_vent_box_02", "屋顶方形排风管箱_02", "roof_equipment", "facility", c_roof_vent)
comp("wall_ac_outdoor_unit_03", "建筑外墙悬挂空调外机_03", "facade_detail", "facility", c_wall_ac)
comp("facade_pipe_cluster_vertical_01", "立面重型竖向管道束_01", "facade_pipe", "facility", c_pipe_cluster)
comp("facade_pipe_elbow_horizontal_02", "立面横向转角管道桥架_02", "facade_pipe", "facility", c_pipe_elbow)
comp("metal_fire_stair_walkway_03", "外挂金属消防梯与检修走道_03", "facade_fire_stair", "facility", c_fire_stair)
comp("street_rock_rubble_pile_04", "街区碎石堆_04", "ground_debris", "floor", c_rubble)
comp("sky_cable_span_24m_01", "跨街电缆束_24m_01", "cable", "support", c_sky_cable)


# ================================================================ 布局实例
# (slug, 组, x, y, z, rz)
SW = 5.0   # 人行道砖边长
LAYOUT = []


def inst(slug, group, x, y, z=0.0, rz=0.0):
    LAYOUT.append(dict(slug=slug, group=group, loc=(x, y, z), rz=rz))


def build_layout():
    LAYOUT.clear()
    # ---- 道路 9 块
    for y in (-20, -10, 10, 20):
        inst("wet_asphalt_lane_10x10_01", "03A_街区基底与道路", 0, y)
    for x in (-20, -10, 10, 20):
        inst("wet_asphalt_lane_10x10_01", "03A_街区基底与道路", x, 0, rz=90)
    inst("wet_asphalt_intersection_10x10_03", "03A_街区基底与道路", 0, 0)
    # ---- 斑马线 4 条
    inst("wet_asphalt_crosswalk_10x5_02", "03A_街区基底与道路", 0, -7.5)
    inst("wet_asphalt_crosswalk_10x5_02", "03A_街区基底与道路", 0, 7.5)
    inst("wet_asphalt_crosswalk_10x5_02", "03A_街区基底与道路", -7.5, 0, rz=90)
    inst("wet_asphalt_crosswalk_10x5_02", "03A_街区基底与道路", 7.5, 0, rz=90)
    # ---- 人行道 28 块
    for x in (-7.5, 7.5):
        rz = 0 if x < 0 else 180
        for y in (-22.5, -17.5, -12.5, -7.5, 7.5, 12.5, 17.5, 22.5):
            inst("sidewalk_tile_5x5_01", "03A_街区基底与道路", x, y, rz=rz)
    for y in (7.5, -7.5):
        rz = -90 if y > 0 else 90
        for x in (-22.5, -17.5, -12.5, 12.5, 17.5, 22.5):
            inst("sidewalk_tile_5x5_01", "03A_街区基底与道路", x, y, rz=rz)
    # ---- 水洼 / 井盖
    for (x, y, rz) in ((-2.6, -12.8, 12), (3.4, 3.2, -40), (-3.4, 12.4, 78), (8.6, -3.0, 25), (-9.2, 2.2, -15)):
        inst("puddle_reflect_patch_04", "03A_街区基底与道路", x, y, 0.0, rz)
    for (x, y) in ((-9.6, -14.0), (9.4, 14.2), (14.0, -9.0)):
        inst("drain_manhole_grate_set_01", "03A_街区基底与道路", x, y)
    # 湿面霓虹倒影（贴地拉丝，绕街灯与招牌下方）
    for (x, y, rz) in ((-3.4, -13.2, 0), (-3.4, -3.0, 0), (3.2, 11.0, 0),
                       (-8.0, -8.4, 90), (8.0, 6.4, 90), (2.4, 17.0, 0)):
        inst("wet_reflect_streak_05", "03A_街区基底与道路", x, y, 0.0, rz)
    # ---- 建筑（局部正面 = -Y；+X 朝街写 rz=+90，-X 朝街写 rz=-90）
    inst("hotel_brick_tower_core_10x12_01", "03B_主体建筑与霓虹", -15, 11)
    inst("pharmacy_shop_block_10x8_01", "03B_主体建筑与霓虹", -15, -14)
    inst("industrial_bar_building_10x12_01", "03B_主体建筑与霓虹", 15, 11, rz=-90)
    inst("foreground_service_roof_15x15_01", "03B_主体建筑与霓虹", 17.5, -17.5, rz=-90)
    inst("backdrop_tower_block_10x7_01", "03B_主体建筑与霓虹", 15, 21.5, rz=-90)
    # 酒店东立面拱窗（5 层 × 3 列，朝 +X）
    for k, z in enumerate((4.1, 9.1, 14.1, 19.1, 23.7)):
        for i in range(3):
            inst("hotel_arch_window_bay_02", "03B_主体建筑与霓虹", -9.96, 6.6 + 2.93 * i, z, 90)
    inst("hotel_shutter_shopfront_03", "03B_主体建筑与霓虹", -9.94, 5.0, 0.0, 90)
    # 霓虹（正面朝街）
    inst("neon_sign_hotel_vertical_01", "03B_主体建筑与霓虹", -9.68, 8.4, 9.8, 90)
    inst("neon_sign_pharmacy_kanji_02", "03B_主体建筑与霓虹", -9.66, -14.0, 4.2, 90)
    inst("neon_sign_bar_vertical_03", "03B_主体建筑与霓虹", 9.66, 12.6, 8.0, -90)
    # 刀旗：垂直于墙面悬挂（板面朝 ±Y，行人沿街可见）
    inst("neon_blade_sign_cluster_05", "03B_主体建筑与霓虹", -9.88, -11.6, 3.4, 0)
    inst("neon_blade_sign_cluster_05", "03B_主体建筑与霓虹", -9.88, 2.6, 5.2, 0)
    inst("neon_blade_sign_cluster_05", "03B_主体建筑与霓虹", 9.88, 7.4, 5.6, 180)
    inst("neon_blade_sign_cluster_05", "03B_主体建筑与霓虹", 9.88, -13.5, 3.0, 180)
    # ---- 跨街桥（移到北侧横街上方，不遮挡酒店立面的 HOTEL 主招牌）
    inst("skybridge_truss_span_21m_01", "03C_跨街高架与地下围护", 0, 16.0)
    inst("skybridge_hazard_pillar_02", "03C_跨街高架与地下围护", -9.5, 16.0)
    inst("skybridge_hazard_pillar_02", "03C_跨街高架与地下围护", 9.5, 16.0)
    inst("skybridge_sign_sector07_04", "03C_跨街高架与地下围护", -1.5, 14.12, 12.95, 0)
    # ---- 围护：岩壁 / 拱顶 / 桁架 / 巨柱 / 隧道口
    for x in (-20, -10, 10, 20):
        inst("cavern_wall_module_10x30_01", "03C_跨街高架与地下围护", x, WALL_Z)
        inst("cavern_wall_module_10x30_01", "03C_跨街高架与地下围护", x, -WALL_Z, rz=180)
    for y in (-20, -10, 10, 20):
        inst("cavern_wall_module_10x30_01", "03C_跨街高架与地下围护", WALL_Z, y, rz=-90)
        inst("cavern_wall_module_10x30_01", "03C_跨街高架与地下围护", -WALL_Z, y, rz=90)
    inst("tunnel_portal_arch_10m_01", "03C_跨街高架与地下围护", 0, 25.65)
    inst("tunnel_portal_arch_10m_01", "03C_跨街高架与地下围护", 0, -25.65, rz=180)
    inst("tunnel_portal_arch_10m_01", "03C_跨街高架与地下围护", 25.65, 0, rz=-90)
    inst("tunnel_portal_arch_10m_01", "03C_跨街高架与地下围护", -25.65, 0, rz=90)
    inst("cavern_base_slab_52x52_01", "03C_跨街高架与地下围护", 0, 0)
    inst("cavern_ceiling_slab_52x52_01", "03C_跨街高架与地下围护", 0, 0)
    for y in (-20, -10, 0, 10, 20):
        inst("ceiling_truss_rib_52m_01", "03C_跨街高架与地下围护", 0, y)
    for (x, y) in ((-22.5, -22.5), (22.5, -22.5), (-22.5, 22.5), (22.5, 22.5)):
        inst("cavern_support_column_30m_01", "03C_跨街高架与地下围护", x, y)
    # ---- 吊顶服务
    for y in (-15.0, 5.0):
        inst("ceiling_duct_bundle_20m_01", "03E_吊顶结构与管线", 0, y, 21.2, 90)
    for y in (-18, -12, -6, 0, 6, 12, 18):
        inst("hanging_lamp_industrial_01", "03E_吊顶结构与管线", 0, y, 18.9)
    for (x, y) in ((-14.0, 0.0), (14.0, 0.0)):
        inst("ceiling_exhaust_fan_3x3_01", "03E_吊顶结构与管线", x, y, 27.9)
    # ---- 街道设施
    lamp_pos = [(-8.2, -18.0, 0), (-8.2, -2.0, 0), (-8.2, 12.0, 0), (8.2, -12.0, 180),
                (8.2, 4.0, 180), (8.2, 18.0, 180), (14.0, -7.2, 90), (-14.0, 7.2, -90)]
    for (x, y, rz) in lamp_pos:
        inst("industrial_street_lamp_pole_01", "03D_街道设施与车辆", x, y, 0.18, rz)
    for (x, y) in ((-5.8, -10.6), (-5.8, -4.4), (5.8, -10.6), (5.8, 4.4), (10.6, -4.4), (-10.6, 4.4)):
        inst("glowing_hazard_bollard_02", "03D_街道设施与车辆", x, y)
    for (x, y, rz) in ((-8.6, -20.0, 0), (-8.6, -15.0, 0), (8.6, 15.0, 0), (12.0, -10.6, 90), (-12.0, 10.6, 90)):
        inst("street_guardrail_fence_4m_01", "03D_街道设施与车辆", x, y, 0.18, rz)
    for (x, y, rz) in ((-9.0, -8.6, 0), (9.2, 8.4, 180), (20.0, -8.6, -90), (-20.0, 8.2, 90)):
        inst("street_utility_cabinet_02", "03D_街道设施与车辆", x, y, 0.18, rz)
    for (x, y, rz) in ((-2.6, -16.0, 0), (2.7, 16.5, 180), (16.0, 1.6, 90)):
        inst("retro_cyber_sedan_car_01", "03D_街道设施与车辆", x, y, 0.02, rz)
    # 立面附着
    ac = [(-9.6, 7.4, 6.2), (-9.6, 9.6, 11.6), (-9.6, 13.4, 16.6), (9.6, 8.0, 7.0),
          (9.6, 13.0, 11.2), (-9.6, -16.2, 4.4), (9.6, 5.2, 2.6), (9.6, 16.4, 15.4)]
    for (x, y, z) in ac:
        inst("wall_ac_outdoor_unit_03", "03D_街道设施与车辆", x, y, z, 90 if x < 0 else -90)
    for (x, y, z, rz) in ((-9.85, 15.0, 0.0, 0), (-9.85, 8.2, 0.0, 0), (9.85, 10.0, 0.0, 0),
                          (-9.85, -12.0, 0.0, 0), (9.85, -18.0, 0.0, 0)):
        inst("facade_pipe_cluster_vertical_01", "03D_街道设施与车辆", x, y, z, rz)
    for (x, y, z, rz) in ((-9.85, 14.2, 4.6, 0), (-9.85, 8.0, 1.2, 0), (9.85, 12.0, 3.4, 180), (9.85, -6.0, 6.0, 180)):
        inst("facade_pipe_elbow_horizontal_02", "03D_街道设施与车辆", x, y, z, rz)
    inst("metal_fire_stair_walkway_03", "03D_街道设施与车辆", -12.0, 4.95, 3.0, 0)
    # 屋顶设备
    for (x, y, rz) in ((-18.0, 13.0, 15), (-12.5, 9.0, -30), (20.0, -20.0, 10)):
        inst("rooftop_twin_fan_chiller_01", "03D_街道设施与车辆", x, y, 7.62 if y < -10 else 26.3, rz)
    for (x, y, z, rz) in ((-16.5, 15.5, 26.3, 0), (-13.0, 12.5, 26.3, 90), (21.5, -22.0, 7.62, 0),
                          (13.0, -14.0, 7.62, 45)):
        inst("rooftop_exhaust_vent_box_02", "03D_街道设施与车辆", x, y, z, rz)
    for (x, y, rz) in ((-20.5, -19.0, 30), (18.0, -24.0, -20), (-9.4, 3.2, 0)):
        inst("street_rock_rubble_pile_04", "03D_街道设施与车辆", x, y, 0.0, rz)
    # 跨街电缆
    for y in (1.2, -14.5):
        inst("sky_cable_span_24m_01", "03E_吊顶结构与管线", 0, y, 0.0, 0)


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
    # 场景母版：45 个输出包全部堆在局部原点，显示会盖住实例布局。
    # 与既有 cyberpunk_old_town_street 母版同口径：01/02 隐藏，03 布局显示。
    root_pkg = L.new_collection("02_游戏输出_独立资产包_%s" % VERSION, hide=True)
    root_layout = L.new_collection("03_场景拼装_实例布局_%s" % VERSION)
    root_disp = L.new_collection("90_展示与动态_灯光相机")

    groups = {}
    for gname in GROUP_ORDER:
        groups[gname] = L.new_collection(gname, root_layout)

    records = []
    pkg_colls = {}
    z_offsets = {}
    for entry in COMPONENTS:
        slug = entry["slug"]
        # 游戏输出包：几何统一归零到「局部底面 Z=0」，高程由实例变换承担
        gpkg = L.Geo()
        entry["builder"](gpkg)
        min_z = min(v[2] for v in gpkg.verts)
        if abs(min_z) > 1e-6:
            gpkg.verts = [(v[0], v[1], v[2] - min_z) for v in gpkg.verts]
        z_offsets[slug] = min_z
        pkg = L.new_collection("资产包_%s" % slug, root_pkg)
        L.link_mesh(pkg, entry["name_zh"], gpkg, mats)
        pkg_colls[slug] = pkg
        # 源组件：同一份几何（同一原点约定），供编辑参考
        gsrc = L.Geo()
        entry["builder"](gsrc)
        gsrc.verts = [(v[0], v[1], v[2] - min_z) for v in gsrc.verts]
        src_coll = L.new_collection("组件源_%s" % slug, root_src)
        L.link_mesh(src_coll, "源_%s" % entry["name_zh"], gsrc, mats)
        b = L.bounds_of(gpkg)
        dims = (b[1] - b[0], b[3] - b[2], b[5] - b[4])
        records.append(dict(
            entry=entry, dims=dims, bounds=b, polys=L.poly_count(gpkg),
            z_offset=min_z,
            objects=[o.name for o in pkg.objects],
            src_objects=[o.name for o in src_coll.objects],
        ))

    # 实例：layout 里写的是世界语义高度，实际 Empty Z = 该高度 + 组件归零偏移
    inst_records = []
    for i, item in enumerate(LAYOUT):
        pkg = pkg_colls[item["slug"]]
        emp = bpy.data.objects.new("inst_%s_%02d" % (item["slug"], i + 1), None)
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

    # 灯光 / 相机 / 世界
    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.012, 0.014, 0.024, 1.0)
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

    add_light("补光_顶棚主光", "AREA", (0, 0, 26.5), 2600, (0.62, 0.72, 1.0), (0, 0, 0), size=30)
    add_light("补光_街口冷光", "AREA", (0, -21.0, 14.0), 900, (0.45, 0.62, 1.0), (math.radians(70), 0, 0), size=12)
    add_light("霓虹_酒店粉", "POINT", (-8.6, 11.0, 15.0), 260, (1.0, 0.16, 0.34), )
    add_light("霓虹_药店青", "POINT", (-8.4, -14.0, 4.5), 180, (0.15, 0.95, 0.85), )
    add_light("霓虹_酒吧红", "POINT", (8.4, 12.6, 9.0), 200, (1.0, 0.2, 0.28), )
    add_light("霓虹_高架橙", "POINT", (-1.0, 6.6, 12.0), 150, (1.0, 0.62, 0.18), )
    add_light("街口射灯", "SPOT", (6.0, -16.0, 12.0), 420, (0.7, 0.8, 1.0),
              (math.radians(58), 0, math.radians(-24)), spot=math.radians(70))
    add_light("酒店门头暖光", "SPOT", (-8.2, 5.0, 3.6), 220, (1.0, 0.55, 0.3),
              (math.radians(72), 0, math.radians(-90)), spot=math.radians(60))

    hard_cam = bpy.data.cameras.new("CAM_参考三分之四")
    hard_cam.lens = 34
    cam_obj = bpy.data.objects.new("CAM_参考三分之四", hard_cam)
    cam_obj.location = (17.6, -18.4, 13.2)
    root_disp.objects.link(cam_obj)
    # 朝向街区核心
    target = (-6.5, 6.5, 7.5)
    from mathutils import Vector
    d = Vector(target) - cam_obj.location
    cam_obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam_obj

    top_cam_data = bpy.data.cameras.new("CAM_俯视正交")
    top_cam_data.type = "ORTHO"
    top_cam_data.ortho_scale = 54
    top_cam = bpy.data.objects.new("CAM_俯视正交", top_cam_data)
    top_cam.location = (0, 0, 70)
    root_disp.objects.link(top_cam)

    # 渲染设置
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
    scene.view_settings.view_transform = "Filmic" if "Filmic" in [
        v.name for v in scene.view_settings.bl_rna.properties["view_transform"].enum_items] else "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.6

    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH, check_existing=False)
    try:
        bpy.ops.file.make_paths_relative()
        bpy.ops.wm.save_mainfile()
    except Exception as exc:  # 相对路径失败不应中断交付
        print("WARN make_paths_relative:", exc)

    # ---------------- 清单写盘
    write_catalogs(records, inst_records)
    print(json.dumps({
        "blend": BLEND_PATH,
        "components": len(records),
        "instances": len(inst_records),
        "polygons": sum(r["polys"] for r in records),
        "materials": [m.name for m in bpy.data.materials],
    }, ensure_ascii=False))


def write_catalogs(records, inst_records):
    os.makedirs(OUT_DIR, exist_ok=True)
    pkg_root = os.path.join(OUT_DIR, "component_packages")
    # 幂等：先清掉上一次留下的过期包目录，否则「磁盘包数 == catalog 包数」会红
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
            "category": e["category"],
            "family_id": e["family"],
            "source_blend": os.path.relpath(BLEND_PATH, PROJECT).replace("\\", "/"),
            "blender_collection": "资产包_%s" % slug,
            "source_collection": "组件源_%s" % slug,
            "objects": rec["objects"],
            "source_objects": rec["src_objects"],
            "pivot_rule": "bottom_center_z0",
            "source_z_offset_m": round(rec["z_offset"], 4),
            "front_axis": "+X",
            "dimensions_m": dims,
            "polygon_count": rec["polys"],
            "instance_count": count_by_slug.get(slug, 0),
            "material_roles": sorted({L.ROLE_METAL, L.ROLE_MATTE, L.ROLE_GLOSS}),
            "emissive_split": any("UI灯光自发光" in n for n in rec["objects"]),
            "palette": "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png",
            "uv_layer": "PaletteUV",
            "collision": "none（Blender 源阶段；碰撞归后续 Godot 包装）",
            "export": {"glb": None, "exported": False},
            "note": e["note"],
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
        })

    catalog = {
        "schema": "shellstorm2.openworld.component_catalog",
        "schema_version": 1,
        "suite_name": SUITE,
        "asset_id_root": ASSET_ID_ROOT,
        "version": VERSION,
        "block_id": "open_world",
        "district": "地下街区",
        "unique_component_count": len(catalog_components),
        "total_instance_count": len(inst_records),
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
            "note": "仅初始化与追溯；正式摆位由后续 Godot TSCN 拥有",
            "instances": inst_records,
        }, f, ensure_ascii=False, indent=2)

    plan = {
        "schema": "shellstorm2.openworld.component_plan",
        "schema_version": 1,
        "suite_name": SUITE,
        "version": VERSION,
        "component_budget": {"limit": 50, "unique": len(catalog_components)},
        "family_budget": "同族常规 ≤3、有明确状态轴 ≤5",
        "families": {},
        "layout_groups": GROUP_ORDER,
    }
    for c in catalog_components:
        plan["families"].setdefault(c["family_id"], []).append(c["slug"])
    with open(os.path.join(OUT_DIR, "component_plan.json"), "w", encoding="utf-8") as f:
        json.dump(plan, f, ensure_ascii=False, indent=2)

    lines = ["%s (%s) - 大世界 地下街区 52×52m 街区对角场景" % (SUITE, VERSION),
             "├── 01_制作组件_按组件拆分_%s (%d Master Components)" % (VERSION, len(records)),
             "├── 02_游戏输出_独立资产包_%s (%d Output Packages, Body/Emissive Split)"
             % (VERSION, len(records)),
             "├── 03_场景拼装_实例布局_%s (%d Collection Instances)" % (VERSION, len(inst_records)),
             "└── 90_展示与动态_灯光相机 (Cameras, Neon Lights)", "", "Components:"]
    for rec in records:
        c = rec["entry"]
        d = " × ".join("%.2f" % v for v in rec["dims"])
        lines.append("  - [comp_%s] %s | %s m | polys=%d | instances=%d"
                     % (c["slug"], c["name_zh"], d, rec["polys"], count_by_slug.get(c["slug"], 0)))
    with open(os.path.join(OUT_DIR, "component_tree.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


try:
    main()
except Exception as exc:  # 桥接只回 stdout，异常必须自己打出来
    import traceback
    traceback.print_exc()
    print("BUILD_FAILED:", exc)
    raise
