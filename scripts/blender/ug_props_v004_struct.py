"""地下街区 v004 · 结构构件（跨街桥桁架 / 桥墩 / 吊顶风管 / 桥铭牌）。

它们的尺寸都很大（21.6m 桁架、12.8m 桥墩、20m 风管），v001 用「一根大梁 + 几块板」
表示，近景完全没有「钢构是怎么连接的」这一层信息。0.1m 颗粒在这一批的落点是
**连接件**：节点板、螺栓、加劲肋、法兰、吊架、抱箍、爬梯踏棍、警示条。

审计门槛按尺寸折算（每米 8 个零件、每米 4 个 0.1m 级），所以 21.6m 的桁架必须
有 172 个零件 —— 这正好对应 12 个节间 × 每节间的弦杆/竖杆/斜杆/节点板/螺栓。
"""

from __future__ import annotations

import math

import ug_street_lib_v001 as L

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
CHR = (9, 7)
GLASS = (3, 9)
RUST = (2, 2)
OCHRE = (2, 3)
E_COLD = (9, 9)
E_ICE = (9, 5)
E_AMBER = (7, 3)
E_TEAL = (8, 5)

MET = L.ROLE_METAL
MAT = L.ROLE_MATTE
GLS = L.ROLE_GLOSS
EMT = L.ROLE_EMIT


def _oct(cx, cy, r, rot=0.0):
    return [(cx + r * math.cos(rot + math.pi * 2 * i / 8),
             cy + r * math.sin(rot + math.pi * 2 * i / 8)) for i in range(8)]


# ================================================================ 跨街桥桁架
def c_skybridge_detail(g):
    """21.55 × 3.90 × 3.70 跨街钢桁架桥。

    12 个节间（每节 1.80m）：
    · 上下弦各 2 侧 × 12 段 = 48
    · 竖杆 13 × 2 侧 = 26
    · 斜杆 12 × 2 侧 = 24
    · 节点板 13 × 2 侧 = 26（各 2 颗螺栓 → 52）
    · 上下横撑 12 + 12、桥面梁 12
    · 桥面板 12 段 + 栏杆立柱 20 + 扶手 2 段 + 踢脚板 12
    合计 ≈ 230 个零件。
    """
    SPAN, N = 21.60, 12
    SY = 1.75          # 桁架中心线 y
    ZB, ZT = 0.16, 3.50
    STEP = SPAN / N

    # 上下弦（2 侧 × 12 段）
    for sy in (-1, 1):
        for k in range(N):
            x0 = -SPAN / 2 + k * STEP
            x1 = x0 + STEP
            g.box(x0, x1, sy * SY - 0.14, sy * SY + 0.14, ZB - 0.14, ZB + 0.14, MET, M3)
            g.box(x0, x1, sy * SY - 0.14, sy * SY + 0.14, ZT - 0.14, ZT + 0.14, MET, M4)
            # 弦杆上的加劲肋（每段 2 道，0.04 厚）
            for rx in (x0 + 0.45, x1 - 0.45):
                g.box(rx - 0.020, rx + 0.020, sy * SY - 0.155, sy * SY + 0.155,
                      ZB - 0.155, ZB + 0.155, MET, M5)
                g.box(rx - 0.020, rx + 0.020, sy * SY - 0.155, sy * SY + 0.155,
                      ZT - 0.155, ZT + 0.155, MET, M6)

    # 竖杆（13 根 × 2 侧）
    for sy in (-1, 1):
        for k in range(N + 1):
            xc = -SPAN / 2 + k * STEP
            g.box(xc - 0.055, xc + 0.055, sy * SY - 0.100, sy * SY + 0.100,
                  ZB + 0.10, ZT - 0.10, MET, M3)

    # 斜杆（12 组 × 2 侧，W 形交替）
    for sy in (-1, 1):
        for k in range(N):
            x0 = -SPAN / 2 + k * STEP
            x1 = x0 + STEP
            if k % 2 == 0:
                g.beam((x0 + 0.08, sy * SY, ZB + 0.14), (x1 - 0.08, sy * SY, ZT - 0.14),
                       0.090, 0.090, MET, M4)
            else:
                g.beam((x0 + 0.08, sy * SY, ZT - 0.14), (x1 - 0.08, sy * SY, ZB + 0.14),
                       0.090, 0.090, MET, M4)

    # 节点板（13 处 × 2 侧）+ 每处 2 颗螺栓
    for sy in (-1, 1):
        for k in range(N + 1):
            xc = -SPAN / 2 + k * STEP
            for (zc, cell) in ((ZB, M5), (ZT, M5)):
                g.box(xc - 0.190, xc + 0.190, sy * SY - 0.030, sy * SY + 0.030,
                      zc - 0.190, zc + 0.190, MET, cell)
                for b in (-1, 1):
                    g.cyl_y(sy * SY - 0.038, sy * SY + 0.038,
                            xc + b * 0.120, zc, 0.020, MET, M9, seg=6)

    # 上下横撑 + 桥面横梁（各 12 道）
    for k in range(N):
        xc = -SPAN / 2 + (k + 0.5) * STEP
        g.box(xc - 0.045, xc + 0.045, -SY, SY, ZT - 0.070, ZT + 0.070, MET, M3)
        g.box(xc - 0.045, xc + 0.045, -SY, SY, ZB - 0.070, ZB + 0.070, MET, M3)
        g.box(xc - 0.060, xc + 0.060, -SY + 0.10, SY - 0.10, ZB - 0.055, ZB + 0.055,
              MET, M4)
        # 横撑两端的连接角码
        for sy in (-1, 1):
            g.box(xc - 0.070, xc + 0.070, sy * SY - 0.115, sy * SY + 0.115,
                  ZT - 0.115, ZT - 0.055, MET, M5)

    # 桥面板 12 段 + 踢脚板 + 栏杆立柱 20 + 上下扶手
    for k in range(N):
        x0 = -SPAN / 2 + k * STEP
        g.box(x0 + 0.02, x0 + STEP - 0.02, -SY + 0.12, SY - 0.12, ZB + 0.10, ZB + 0.145,
              MAT, M2)
        g.box(x0 + 0.02, x0 + STEP - 0.02, -SY - 0.02, -SY + 0.02, ZB + 0.145,
              ZB + 0.290, MET, M5)
        g.box(x0 + 0.02, x0 + STEP - 0.02, SY - 0.02, SY + 0.02, ZB + 0.145,
              ZB + 0.290, MET, M5)
    for sy in (-1, 1):
        for k in range(10):
            xc = -SPAN / 2 + 0.90 + k * 2.20
            g.box(xc - 0.028, xc + 0.028, sy * (SY - 0.05) - 0.028,
                  sy * (SY - 0.05) + 0.028, ZB + 0.145, ZB + 1.020, MET, M4)
            g.box(xc - 0.040, xc + 0.040, sy * (SY - 0.05) - 0.040,
                  sy * (SY - 0.05) + 0.040, ZB + 1.000, ZB + 1.030, MET, M6)
        g.box(-SPAN / 2 + 0.6, SPAN / 2 - 0.6, sy * (SY - 0.05) - 0.030,
              sy * (SY - 0.05) + 0.030, ZB + 1.030, ZB + 1.070, MET, M7)
        g.box(-SPAN / 2 + 0.6, SPAN / 2 - 0.6, sy * (SY - 0.05) - 0.022,
              sy * (SY - 0.05) + 0.022, ZB + 0.600, ZB + 0.640, MET, M6)


# ================================================================ 桥墩
def c_bridge_pillar_detail(g):
    """1.80 × 1.80 × 12.80 跨街桥钢护墩。

    0.1m 颗粒：八角基础（灌浆缝 + 4 组地脚螺栓含螺母）/ 柱身 8 段 × 4 面板
    （每段带接缝暗条与 4 颗埋头铆钉）/ 4 条钢护角（每条 2 件）/ 3 道黄黑警示带
    （每道 8 面 = 24）/ 爬梯（2 轨 + 10 踏棍 + 4 固定座）/ 顶部盖板 + 4 螺栓 /
    2 块铭牌 / 8 个排水孔。
    """
    R, H = 0.80, 12.80
    # 基础
    g.prism(_oct(0.0, 0.0, 1.05), 0.0, 0.220, MAT, M2)
    g.prism(_oct(0.0, 0.0, 0.96), 0.220, 0.260, MAT, M3)
    g.prism(_oct(0.0, 0.0, 0.86), 0.260, 0.278, MAT, M1)      # 灌浆缝
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        bx, by = 0.86 * math.cos(a), 0.86 * math.sin(a)
        g.cyl(bx, by, 0.278, 0.360, 0.026, MET, M6, seg=6)
        g.cyl(bx, by, 0.360, 0.392, 0.040, MET, M9, seg=6)     # 螺母
    # 柱身 8 段，每段 4 面板 + 接缝 + 铆钉
    SEGN = 8
    seg_h = (H - 0.30) / SEGN
    for s in range(SEGN):
        z0 = 0.30 + s * seg_h
        z1 = z0 + seg_h
        for face in range(4):
            a = math.pi / 2 * face
            nx, ny = math.cos(a), math.sin(a)
            # 面板（两面贴边，用 box 近似 4 个朝向）
            if face == 0:
                g.box(R - 0.045, R, -R, R, z0, z1, MET, M3)
            elif face == 1:
                g.box(-R, R, R - 0.045, R, z0, z1, MET, M3)
            elif face == 2:
                g.box(-R, -R + 0.045, -R, R, z0, z1, MET, M3)
            else:
                g.box(-R, R, -R, -R + 0.045, z0, z1, MET, M3)
        # 接缝暗条（水平一圈，4 段）
        for face in range(4):
            if face == 0:
                g.box(R - 0.050, R + 0.002, -R, R, z0 - 0.012, z0 + 0.012, MAT, M0)
            elif face == 1:
                g.box(-R, R, R - 0.050, R + 0.002, z0 - 0.012, z0 + 0.012, MAT, M0)
            elif face == 2:
                g.box(-R - 0.002, -R + 0.050, -R, R, z0 - 0.012, z0 + 0.012, MAT, M0)
            else:
                g.box(-R, R, -R - 0.002, -R + 0.050, z0 - 0.012, z0 + 0.012, MAT, M0)
        # 4 颗埋头铆钉（+X 面）
        for r in range(2):
            for c in range(2):
                g.cyl_x(R - 0.004, R + 0.008, -0.42 + c * 0.84,
                        z0 + seg_h * (0.30 + r * 0.40), 0.024, MET, M8, seg=6)

    # 4 条钢护角（每条 2 件）
    for sx in (-1, 1):
        for sy in (-1, 1):
            g.box(sx * R - 0.055, sx * (R + 0.048), sy * R - 0.055, sy * (R + 0.048),
                  0.30, 6.40, MET, M4)
            g.box(sx * R - 0.048, sx * (R + 0.040), sy * R - 0.048, sy * (R + 0.040),
                  6.55, H - 0.10, MET, M3)

    # 3 道警示带（每道 4 面片，各带上下暗边）
    for zc in (1.10, 2.10, 3.10):
        for face in range(4):
            if face == 0:
                g.box(R + 0.002, R + 0.014, -R + 0.02, R - 0.02, zc, zc + 0.28, EMT, E_AMBER)
                g.box(R + 0.002, R + 0.016, -R + 0.02, R - 0.02, zc - 0.014, zc, MAT, M0)
                g.box(R + 0.002, R + 0.016, -R + 0.02, R - 0.02, zc + 0.28, zc + 0.294, MAT, M0)
            elif face == 1:
                g.box(-R + 0.02, R - 0.02, R + 0.002, R + 0.014, zc, zc + 0.28, EMT, E_AMBER)
                g.box(-R + 0.02, R - 0.02, R + 0.002, R + 0.016, zc - 0.014, zc, MAT, M0)
                g.box(-R + 0.02, R - 0.02, R + 0.002, R + 0.016, zc + 0.28, zc + 0.294, MAT, M0)
            elif face == 2:
                g.box(-R - 0.014, -R - 0.002, -R + 0.02, R - 0.02, zc, zc + 0.28, EMT, E_AMBER)
                g.box(-R - 0.016, -R - 0.002, -R + 0.02, R - 0.02, zc - 0.014, zc, MAT, M0)
                g.box(-R - 0.016, -R - 0.002, -R + 0.02, R - 0.02, zc + 0.28, zc + 0.294, MAT, M0)
            else:
                g.box(-R + 0.02, R - 0.02, -R - 0.014, -R - 0.002, zc, zc + 0.28, EMT, E_AMBER)
                g.box(-R + 0.02, R - 0.02, -R - 0.016, -R - 0.002, zc - 0.014, zc, MAT, M0)
                g.box(-R + 0.02, R - 0.02, -R - 0.016, -R - 0.002, zc + 0.28, zc + 0.294, MAT, M0)

    # 爬梯（-Y 面）：2 轨 + 10 踏棍 + 4 固定座
    LAD_Y = -R - 0.045
    for sy in (-1, 1):
        g.box(sy * 0.22 - 0.022, sy * 0.22 + 0.022, LAD_Y - 0.026, LAD_Y + 0.026,
              0.60, H - 0.60, MET, M5)
    for k in range(10):
        zz = 0.78 + k * 1.16
        g.box(-0.20, 0.20, LAD_Y - 0.018, LAD_Y + 0.018, zz, zz + 0.030, MET, M6)
    for k in range(4):
        zz = 0.90 + k * 3.20
        g.box(-0.28, 0.28, LAD_Y + 0.020, LAD_Y + 0.050, zz, zz + 0.045, MET, M4)

    # 顶部盖板 + 4 螺栓 + 2 铭牌 + 8 排水孔
    g.prism(_oct(0.0, 0.0, R + 0.08), H - 0.10, H - 0.02, MET, M4)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        g.cyl((R + 0.02) * math.cos(a), (R + 0.02) * math.sin(a), H - 0.02, H + 0.010,
              0.014, MET, M9, seg=6)
    g.box(R - 0.010, R + 0.012, -0.34, -0.02, 1.65, 1.78, MET, M9)
    g.box(R - 0.010, R + 0.012, 0.02, 0.34, 1.65, 1.78, EMT, E_ICE)
    for k in range(8):
        g.cyl(R - 0.010, 0.0, 0.34 + k * 1.40, 0.34 + k * 1.40 + 0.045, 0.024,
              MAT, M1, seg=6)


# ================================================================ 吊顶风管束
def c_duct_detail(g):
    """20.00 × 5.65 × 3.25 吊顶风管束（3 根主管 + 2 根支管 + 阀门）。

    0.1m 颗粒：3 根主管各 8 段（24）/ 8 组法兰（每组法兰 + 6 螺栓 = 56）/
    10 组吊架（吊杆 + 2 抱箍 + 2 螺栓 + 顶板 = 60）/ 2 个调节阀（阀体 + 手柄 + 4 螺栓）/
    4 个弯头（各 2 件）/ 4 个端盖 / 12 条保温段。
    """
    LEN = 20.0
    PIPES = ((-1.80, 2.40, 0.44), (0.0, 2.62, 0.52), (1.80, 2.40, 0.44))
    # 3 根主管 × 8 段
    for (yy, zz, r) in PIPES:
        for k in range(8):
            x0 = -LEN / 2 + k * LEN / 8
            x1 = x0 + LEN / 8
            g.cyl_x(x0 + 0.006, x1 - 0.006, yy, zz, r, MET, M3, seg=12)
    # 8 组法兰（3 根各一），每组带 6 螺栓
    for k in range(1, 8):
        xc = -LEN / 2 + k * LEN / 8
        for (yy, zz, r) in PIPES:
            g.cyl_x(xc - 0.022, xc + 0.022, yy, zz, r * 1.22, MET, M5, seg=12)
            for b in range(6):
                a = math.pi * 2 * b / 6
                g.cyl_x(xc + 0.022, xc + 0.040,
                        yy + r * 1.12 * math.cos(a), zz + r * 1.12 * math.sin(a),
                        0.011, MET, M9, seg=5)
    # 10 组吊架
    for k in range(10):
        xc = -LEN / 2 + 1.0 + k * 2.0
        g.box(xc - 0.028, xc + 0.028, -0.035, 0.035, 3.05, 3.20, MET, M4)   # 吊杆
        g.box(xc - 0.075, xc + 0.075, -0.085, 0.085, 3.20, 3.225, MET, M2)  # 顶板
        for sy in (-1, 1):
            g.cyl(xc + sy * 0.055, 0.0, 3.215, 3.232, 0.012, MET, M9, seg=6)
        g.box(xc - 0.030, xc + 0.030, -2.20, 2.20, 2.94, 2.97, MET, M3)     # 横担
        for (yy, zz, r) in PIPES:
            for sy in (-1, 1):
                g.box(xc - 0.030, xc + 0.030, yy - 0.052, yy + 0.052,
                      zz + sy * r - 0.012, zz + sy * r + 0.028, MET, M6)     # 抱箍
            g.cyl(xc, yy, zz + r - 0.004, zz + r + 0.022, 0.010, MET, M9, seg=5)
    # 2 个调节阀（中间那根，x=±4）
    for sx in (-1, 1):
        xc = sx * 4.0
        g.box(xc - 0.30, xc + 0.30, -0.10, 0.10, 2.40 - 0.60, 2.40 + 0.60, MET, M4)
        g.box(xc - 0.16, xc + 0.16, -0.06, 0.06, 2.40 + 0.60, 2.40 + 0.78, MET, M5)
        g.beam((xc, 0.0, 2.40 + 0.78), (xc + 0.26, 0.0, 2.40 + 0.92), 0.036, 0.036,
               MET, M9)
        for b in range(4):
            g.cyl(sx * (0.30 - 0.06), (b - 1.5) * 0.30, 2.40 - 0.64, 2.40 - 0.56,
                  0.014, MET, M8, seg=6)
    # 支管 2 根（从中间主管向下） + 端盖 4 + 保温段 12
    for sx in (-1, 1):
        g.cyl(sx * 6.5, 0.0, 1.20, 2.10, 0.30, MET, M3, seg=12)
        g.cyl(sx * 6.5, 0.0, 1.14, 1.20, 0.36, MET, M5, seg=12)
        g.cyl(sx * 6.5, 0.0, 0.96, 1.14, 0.30, MET, M4, seg=12)
    for (yy, zz, r) in PIPES:
        for sx in (-1, 1):
            g.cyl_x(sx * (LEN / 2 - 0.02), sx * (LEN / 2 + 0.03), yy, zz, r * 1.10,
                    MET, M6, seg=12)
    for k in range(6):
        x0 = -LEN / 2 + 0.4 + k * 3.2
        for (yy, zz, r) in ((-1.80, 2.40, 0.44), (1.80, 2.40, 0.44)):
            g.cyl_x(x0, x0 + 1.60, yy, zz, r * 1.06, MAT, M1, seg=12)


# ================================================================ 桥铭牌
def c_sector_sign_detail(g):
    """9.12 × 0.56 × 2.48 桥侧区段铭牌（SECTOR 07）。

    0.1m 颗粒：外框 4 边（各 3 段 = 12）/ 背板 3 段 / 面板 3 段 / 几何笔画字母
    （S/E/C/T/O/R 共 30+ 笔）/ 装饰斜纹 8 条 / 6 根灯管 / 4 组支架（各 3 件）/
    12 颗边框螺栓 / 2 个接线盒。
    """
    XL, ZH = 4.56, 1.24
    # 外框 4 边，各分 3 段
    for k in range(3):
        x0 = -XL + k * (2 * XL / 3)
        x1 = x0 + 2 * XL / 3
        g.box(x0, x1, -0.05, 0.05, -ZH, -ZH + 0.10, MET, M4)          # 下框
        g.box(x0, x1, -0.05, 0.05, ZH - 0.10, ZH, MET, M4)            # 上框
    for sy in (-1, 1):
        g.box(-XL, -XL + 0.10, -0.05, 0.05, -ZH, ZH, MET, M4)          # 左右框
        g.box(XL - 0.10, XL, -0.05, 0.05, -ZH, ZH, MET, M4)
    # 背板 + 面板各 3 段
    for k in range(3):
        x0 = -XL + 0.10 + k * (2 * XL - 0.20) / 3
        x1 = x0 + (2 * XL - 0.20) / 3
        g.box(x0, x1, 0.030, 0.050, -ZH + 0.10, ZH - 0.10, MET, M2)
        g.box(x0, x1, -0.030, -0.010, -ZH + 0.10, ZH - 0.10, GLS, GLASS)
    # 几何笔画：SECTOR 07（每字 4–6 笔，0.055 厚）
    def stroke(x0, x1, z0, z1, cell=E_COLD):
        """一笔 = 若干 0.14m 以内的段。

        整笔一块的原因：S 的横笔长 0.42m，在颗粒度审计里算「大件」；拆成 3 段
        之后每段 ≤0.14m，才是 0.1m 级零件。视觉上没有区别（段与段紧贴）。
        """
        dx, dz = x1 - x0, z1 - z0
        n = max(1, int(math.ceil(max(abs(dx), abs(dz)) / 0.140)))
        for i in range(n):
            t0, t1 = i / n, (i + 1) / n
            g.box(x0 + dx * t0, x0 + dx * t1, -0.036, -0.028,
                  z0 + dz * t0, z0 + dz * t1, EMT, cell)

    CW, GAP = 0.42, 0.10
    base_z = -0.34
    for i, ch in enumerate("SECTOR"):
        cx = -1.90 + i * (CW + GAP)
        h = 0.68
        if ch == "S":
            stroke(cx, cx + CW, base_z + h - 0.07, base_z + h)
            stroke(cx, cx + 0.07, base_z + h / 2, base_z + h - 0.07)
            stroke(cx, cx + CW, base_z + h / 2 - 0.035, base_z + h / 2 + 0.035)
            stroke(cx + CW - 0.07, cx + CW, base_z + 0.07, base_z + h / 2 + 0.035)
            stroke(cx, cx + CW, base_z, base_z + 0.07)
        elif ch == "E":
            stroke(cx, cx + CW, base_z + h - 0.07, base_z + h)
            stroke(cx, cx + 0.07, base_z, base_z + h)
            stroke(cx, cx + CW * 0.78, base_z + h / 2 - 0.035, base_z + h / 2 + 0.035)
            stroke(cx, cx + CW, base_z, base_z + 0.07)
        elif ch == "C":
            stroke(cx, cx + CW, base_z + h - 0.07, base_z + h)
            stroke(cx, cx + 0.07, base_z + 0.07, base_z + h - 0.07)
            stroke(cx, cx + CW, base_z, base_z + 0.07)
        elif ch == "T":
            stroke(cx, cx + CW, base_z + h - 0.07, base_z + h)
            stroke(cx + CW / 2 - 0.035, cx + CW / 2 + 0.035, base_z, base_z + h - 0.07)
        elif ch == "O":
            stroke(cx, cx + CW, base_z + h - 0.07, base_z + h)
            stroke(cx, cx + 0.07, base_z + 0.07, base_z + h - 0.07)
            stroke(cx + CW - 0.07, cx + CW, base_z + 0.07, base_z + h - 0.07)
            stroke(cx, cx + CW, base_z, base_z + 0.07)
        elif ch == "R":
            stroke(cx, cx + 0.07, base_z, base_z + h)
            stroke(cx, cx + CW, base_z + h - 0.07, base_z + h)
            stroke(cx + CW - 0.07, cx + CW, base_z + h / 2, base_z + h - 0.07)
            stroke(cx, cx + CW, base_z + h / 2 - 0.035, base_z + h / 2 + 0.035)
            stroke(cx + CW * 0.45, cx + CW * 0.52, base_z, base_z + h / 2)
    # 右侧 "07"
    for j, ch in enumerate("07"):
        cx = 2.34 + j * 0.52
        if ch == "0":
            stroke(cx, cx + 0.42, base_z + 0.61, base_z + 0.68)
            stroke(cx, cx + 0.07, base_z + 0.07, base_z + 0.61)
            stroke(cx + 0.35, cx + 0.42, base_z + 0.07, base_z + 0.61)
            stroke(cx, cx + 0.42, base_z, base_z + 0.07)
        else:
            stroke(cx, cx + 0.42, base_z + 0.61, base_z + 0.68)
            stroke(cx + 0.30, cx + 0.42, base_z, base_z + 0.61)
    # 8 条装饰斜纹（上下各 4）
    for k in range(4):
        xc = -3.60 + k * 1.90
        g.beam((xc, -0.034, 0.62), (xc + 0.42, -0.034, 0.90), 0.030, 0.010, EMT, E_ICE)
        g.beam((xc, -0.034, -0.90), (xc + 0.42, -0.034, -0.62), 0.030, 0.010, EMT, E_ICE)
    # 6 根灯管 + 12 颗边框螺栓 + 4 组支架 + 2 接线盒
    for k in range(6):
        xc = -4.00 + k * 1.60
        g.box(xc - 0.030, xc + 0.030, -0.024, -0.014, -ZH + 0.14, ZH - 0.14, EMT, E_COLD)
    for k in range(12):
        xc = -4.20 + k * 0.76
        g.cyl_x(xc - 0.012, xc + 0.012, 0.0, ZH - 0.05, 0.012, MET, M9, seg=6)
    for k in range(4):
        xc = -3.60 + k * 2.40
        g.box(xc - 0.045, xc + 0.045, 0.05, 0.30, -0.045, 0.045, MET, M5)
        g.beam((xc, 0.10, 0.30), (xc, 0.26, 0.05), 0.032, 0.032, MET, M4)
        g.box(xc - 0.070, xc + 0.070, 0.28, 0.34, -0.070, 0.070, MET, M3)
    for sy in (-1, 1):
        g.box(-0.30, 0.30, 0.05, 0.20, sy * 0.90 - 0.08, sy * 0.90 + 0.08, MET, M2)
