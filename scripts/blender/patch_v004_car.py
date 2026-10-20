"""v004 轿车重写（第二版）。

第一版的两个硬错误（近景渲染实测）：
1. **车轮被侧板包住**：side_segs 的区间是 (0.95,1.95) 与 (-1.95,-0.95)，而轮心
   恰好在 x=±1.45 —— 侧板正好盖在轮子上，整车四个轮子一个都看不见。
2. **侧窗玻璃埋在窗下墙里**：窗下墙 y∈[1.045,1.095]，玻璃 y∈[1.048,1.058]，
   玻璃整体在墙体内部 → 侧窗全黑，整车读成一个铁盒子。

第二版把「轮拱洞」和「窗洞」都当真实洞口处理：
- 车身侧板分成 3 段，轮拱处**留空**；轮拱用 arc_xz 做轮眉、prism_xz 做内衬；
- 车窗按「暗腔 → 玻璃（与外墙齐平并外凸 0.004）→ 窗框」分层，玻璃一定在最外层；
- 车顶与车身同宽减 0.03（形成一圈边缝），不再是悬空的一块板。

尺寸：4.70 × 2.02 × 1.44（宽 2.02 是含后视镜的整车宽，车身本体 ±0.88）。
"""

from __future__ import annotations

import io

NEW = '''# ================================================================ 轿车
def c_sedan_detail(g):
    """复古方正轿车 4.70 × 2.02 × 1.44，车头朝 +X。

    0.1m 颗粒的落点：
    · 车轮：胎面 / 内外胎壁 / 轮辋盘 / 轮辋凸缘 / 5 根斜辐条 / 中心盖 / 车标盖 /
      5 颗轮毂螺栓 / 气门嘴 / 轮拱内衬 / 轮眉（各 1）
    · 前脸：格栅内腔 + 上下框 + 左右框 + 9 竖条 + 2 横条 + 车标座；
      大灯（灯碗 / 灯罩 / 4 螺栓）×2、转向灯（灯罩 + 底座）×2、雾灯 ×2
    · 车身：门槛压条 / 腰线饰条 / 3 道门缝 / 门把手 + 锁孔（各 2）/ 防擦条 / 标牌
    · 尾部：尾灯 3 格 + 分隔条 + 镀铬边（各 2）/ 牌照 + 4 螺栓 / 排气 ×2 + 吊耳 ×2
    · 保险杠：中段 + 左右防撞块 + 橡胶条 + 端头 + 镀铬条 + 拖车钩（前后各一套）
    · 细节：雨刷 ×2、后视镜（臂/壳/镜）、行李架压条 ×2、天线、车顶边缝
    """
    BX0, BX1 = -2.35, 2.35
    BY = 0.88                      # 车身半宽（本体，不含后视镜）
    WF, WRX = 1.42, -1.42          # 前 / 后轮心 x
    WY, WR = 0.74, 0.340           # 轮心 y、胎半径
    WTH = 0.115                    # 半胎宽 → 胎外沿 0.855，略小于车身 0.88（被轮拱包住）
    ARCH = 0.435                   # 轮拱半径（比胎大 0.095 → 有可见的轮拱间隙）
    BELT, ROOF = 0.980, 1.440      # 腰线、车顶
    SILL = 0.330                   # 门槛下沿

    # ---------------- 底盘：地板 + 双纵梁 + 4 横梁 + 传动轴槽 + 油箱
    g.box(-2.16, 2.16, -0.78, 0.78, 0.255, 0.330, MAT, M1)
    for sy in (-1, 1):
        g.box(-2.14, 2.14, sy * 0.56 - 0.050, sy * 0.56 + 0.050, 0.215, 0.340, MET, M2)
        for x in (-1.90, -0.90, 0.10, 1.10, 1.90):      # 线束卡扣
            g.box(x - 0.025, x + 0.025, sy * 0.56 - 0.070, sy * 0.56 + 0.070,
                  0.300, 0.358, MET, M6)
    for x in (-1.78, -0.62, 0.62, 1.78):
        g.box(x - 0.042, x + 0.042, -0.66, 0.66, 0.235, 0.312, MET, M2)
    g.box(-1.30, 0.40, -0.075, 0.075, 0.200, 0.258, MET, M3)       # 传动轴槽
    g.box(-2.05, -1.32, -0.46, 0.46, 0.240, 0.395, MET, M2)        # 油箱
    g.cyl_x(-2.30, -1.30, 0.40, 0.245, 0.042, MET, M4, seg=8)      # 加油管

    # ---------------- 车身侧板：3 段（轮拱处留空）
    # 前轮拱 x∈[1.00,1.84]，后轮拱 x∈[-1.84,-1.00] —— 这两个区间不放侧板
    SIDE_SEGS = ((1.84, 2.30), (-1.00, 1.00), (-2.30, -1.84))
    for sy in (-1, 1):
        y_in, y_out = sy * (BY - 0.045), sy * BY
        lo, hi = min(y_in, y_out), max(y_in, y_out)
        for (a, b) in SIDE_SEGS:
            g.box(a, b, lo, hi, SILL, BELT, GLS, M3)                # 下段（门槛→腰线）
            g.box(a, b, lo, hi, SILL, 0.470, MAT, M2)               # 裙板暗带
        # 门槛压条（轮拱之间那一段）
        g.box(-1.00, 1.00, sy * (BY + 0.004), sy * (BY + 0.042), 0.312, 0.392, MET, RUB)
        # 轮眉（外凸 0.038 的半圆环）+ 轮拱内衬
        for wx in (WF, WRX):
            y_a, y_b = sy * (BY - 0.010), sy * (BY + 0.030)
            g.arc_xz(wx, WR, ARCH, ARCH + 0.070, min(y_a, y_b), max(y_a, y_b),
                     0.0, math.pi, MET, M4, seg=10)
            g.prism_xz(_semi_pts(wx, WR, ARCH + 0.004, 10),
                       min(y_in, y_in - sy * 0.030), max(y_in, y_in - sy * 0.030),
                       MAT, M0)
        # 腰线饰条（全程）+ 3 道门缝
        g.box(BX0 + 0.02, BX1 - 0.02, sy * (BY + 0.004), sy * (BY + 0.050),
              BELT - 0.042, BELT + 0.004, MET, M6)
        for x in (0.02, -0.88, -1.56):
            g.box(x - 0.006, x + 0.006, sy * (BY + 0.002), sy * (BY + 0.052),
                  0.360, BELT - 0.042, MAT, M0)
        # 防擦条 + 门牌
        g.box(-1.50, 0.80, sy * (BY + 0.034), sy * (BY + 0.054), 0.520, 0.572, MET, M6)

    # ---------------- 驾驶舱：窗下墙 / 窗上沿 / A·B·C 柱 / 玻璃（玻璃在外层）
    CAB_X0, CAB_X1 = -1.56, 0.88
    WIN_Z0, WIN_Z1 = 1.062, 1.338
    for sy in (-1, 1):
        y_in, y_out = sy * (BY - 0.048), sy * BY
        lo, hi = min(y_in, y_out), max(y_in, y_out)
        g.box(CAB_X0, CAB_X1, lo, hi, BELT, WIN_Z0, GLS, M3)            # 窗下墙
        g.box(CAB_X0, CAB_X1, lo, hi, WIN_Z1, ROOF - 0.030, GLS, M3)    # 窗上沿
        # A 柱（斜）+ B 柱 + C 柱
        g.beam((0.88, sy * (BY - 0.022), ROOF - 0.030),
               (1.10, sy * (BY - 0.022), WIN_Z0 - 0.010), 0.080, 0.058, MET, M4)
        g.box(-0.09, 0.02, lo, hi, WIN_Z0, WIN_Z1, MET, M4)
        g.box(CAB_X0, CAB_X0 + 0.13, lo, hi, WIN_Z0, WIN_Z1, MET, M4)
        # 侧窗暗腔（向内退 0.05）+ 玻璃（与外墙齐平并外凸 0.004）+ 窗框
        for (a, b) in ((0.02, 0.86), (CAB_X0 + 0.13, -0.10)):
            g.box(a, b, sy * (BY - 0.052), sy * (BY - 0.048),
                  WIN_Z0 + 0.008, WIN_Z1 - 0.008, MAT, M0)             # 暗腔
            g.box(a + 0.012, b - 0.012, sy * (BY + 0.002), sy * (BY + 0.006),
                  WIN_Z0 + 0.020, WIN_Z1 - 0.020, GLS, GLASS)          # 玻璃（最外）
            g.box(a, b, sy * (BY + 0.004), sy * (BY + 0.012),
                  WIN_Z0 + 0.008, WIN_Z0 + 0.020, MET, M5)             # 下框
            g.box(a, b, sy * (BY + 0.004), sy * (BY + 0.012),
                  WIN_Z1 - 0.020, WIN_Z1 - 0.008, MET, M5)             # 上框
        # 车窗上沿镀铬饰条
        g.box(CAB_X0, CAB_X1, sy * (BY + 0.004), sy * (BY + 0.024),
              WIN_Z1 - 0.014, WIN_Z1 + 0.004, MET, CHR)
        # 门把手 + 锁孔（各 2）
        for hx in (0.42, -0.62):
            g.box(hx - 0.078, hx + 0.078, sy * (BY + 0.052), sy * (BY + 0.092),
                  0.882, 0.918, MET, CHR)
            g.box(hx - 0.088, hx - 0.058, sy * (BY + 0.052), sy * (BY + 0.078),
                  0.888, 0.912, MET, M1)
            g.cyl_y(sy * (BY + 0.010), sy * (BY + 0.040), hx - 0.115, 0.900,
                    0.017, MET, M0, seg=6)
        g.box(-0.55, -0.30, sy * (BY + 0.048), sy * (BY + 0.060), 0.640, 0.700, MET, M7)

    # 前挡 / 后挡（斜板；w 沿 Y 为宽，t 为厚）
    g.beam((0.86, 0.0, ROOF - 0.022), (1.14, 0.0, WIN_Z0 - 0.028), 1.72, 0.024, GLS, GLASS)
    g.beam((0.85, 0.0, ROOF - 0.010), (1.15, 0.0, WIN_Z0 - 0.036), 1.78, 0.048, MET, M4)
    g.beam((CAB_X0, 0.0, ROOF - 0.022), (CAB_X0 - 0.30, 0.0, WIN_Z0 - 0.028),
           1.68, 0.024, GLS, GLASS)
    g.beam((CAB_X0 + 0.01, 0.0, ROOF - 0.010), (CAB_X0 - 0.31, 0.0, WIN_Z0 - 0.036),
           1.74, 0.048, MET, M4)
    # 后视镜：臂 + 壳 + 镜面
    for sy in (-1, 1):
        g.beam((0.78, sy * (BY - 0.010), 1.100), (0.84, sy * (BY + 0.180), 1.190),
               0.042, 0.042, MET, M4)
        g.box(0.78, 0.90, sy * (BY + 0.150) - 0.032, sy * (BY + 0.150) + 0.032,
              1.128, 1.258, MET, M4)
        g.box(0.898, 0.906, sy * (BY + 0.150) - 0.026, sy * (BY + 0.150) + 0.026,
              1.138, 1.248, GLS, CHR)
    # 车顶（四边各留 0.03 边缝，不与侧板齐平）+ 行李架压条 + 天线
    g.box(CAB_X0 + 0.02, CAB_X1 - 0.02, -(BY - 0.030), BY - 0.030,
          ROOF - 0.036, ROOF, GLS, M3)
    for sy in (-1, 1):
        g.box(CAB_X0 + 0.10, CAB_X1 - 0.12, sy * (BY - 0.090) - 0.018,
              sy * (BY - 0.090) + 0.018, ROOF, ROOF + 0.020, MET, M5)
    g.beam((CAB_X0 + 0.12, 0.0, ROOF), (CAB_X0 + 0.02, 0.0, ROOF + 0.42),
           0.018, 0.018, MET, M7)
    g.cyl_y(-0.016, 0.016, CAB_X0 + 0.02, ROOF + 0.43, 0.024, EMT, E_RED, seg=6)

    # ---------------- 引擎盖 / 后备箱盖（板 + 中缝 + 4 铰链）
    g.box(1.10, 2.28, -(BY - 0.030), BY - 0.030, BELT - 0.028, BELT + 0.010, GLS, M3)
    g.box(1.12, 2.26, -0.006, 0.006, BELT + 0.010, BELT + 0.018, MAT, M0)
    for sy in (-1, 1):
        for x in (1.18, 1.86):
            g.box(x - 0.048, x + 0.048, sy * 0.62 - 0.018, sy * 0.62 + 0.018,
                  BELT + 0.010, BELT + 0.028, MET, M5)
    g.box(-2.30, -1.58, -(BY - 0.030), BY - 0.030, BELT - 0.028, BELT + 0.010, GLS, M3)
    g.box(-2.28, -1.60, -0.006, 0.006, BELT + 0.010, BELT + 0.016, MAT, M0)

    # ---------------- 前脸：格栅 9 竖 2 横 + 灯组 + 保险杠
    GX0, GX1 = 2.290, 2.348
    g.box(GX0, GX1, -0.470, 0.470, 0.606, 0.862, MAT, M0)            # 格栅内腔
    for (z0, z1) in ((0.590, 0.634), (0.842, 0.882)):
        g.box(GX0 - 0.010, GX1 + 0.012, -0.488, 0.488, z0, z1, MET, M6)
    for sy in (-1, 1):
        g.box(GX0 - 0.010, GX1 + 0.012, sy * 0.458, sy * 0.488, 0.590, 0.882, MET, M6)
    for i in range(9):
        yc = -0.400 + i * 0.100
        g.box(GX1 - 0.004, GX1 + 0.020, yc - 0.013, yc + 0.013, 0.634, 0.842, MET, M8)
    for zc in (0.700, 0.768):
        g.box(GX1 - 0.002, GX1 + 0.016, -0.458, 0.458, zc - 0.010, zc + 0.010, MET, M7)
    g.box(GX1 + 0.016, GX1 + 0.032, -0.070, 0.070, 0.696, 0.774, MET, CHR)   # 车标座

    for sy in (-1, 1):
        ly = sy * 0.700
        g.cyl_x(2.258, 2.330, ly, 0.736, 0.140, MET, M2, seg=12)      # 灯碗
        g.cyl_x(2.330, 2.354, ly, 0.736, 0.128, GLS, CHR, seg=12)     # 灯罩
        g.cyl_x(2.352, 2.364, ly, 0.736, 0.114, EMT, E_COLD, seg=12)  # 发光面
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            g.cyl_x(2.330, 2.346, ly + 0.146 * math.cos(a),
                    0.736 + 0.146 * math.sin(a), 0.015, MET, M8, seg=6)
        g.box(2.298, 2.336, ly - 0.088, ly + 0.088, 0.558, 0.598, EMT, E_AMBER)
        g.box(2.288, 2.298, ly - 0.098, ly + 0.098, 0.550, 0.606, MET, M5)
        g.cyl_x(2.320, 2.344, sy * 0.400, 0.492, 0.050, EMT, E_WARM, seg=8)   # 雾灯

    g.box(2.300, 2.400, -0.500, 0.500, 0.355, 0.545, MET, M4)         # 前杠中段
    for sy in (-1, 1):
        g.box(2.310, 2.420, sy * 0.505, sy * 0.880, 0.365, 0.535, MET, M3)
        g.box(2.415, 2.435, sy * 0.545, sy * 0.845, 0.372, 0.528, MET, RUB)
        g.box(2.300, 2.380, sy * 0.880, sy * 0.902, 0.380, 0.520, MET, M2)
    g.box(2.395, 2.412, -0.440, 0.440, 0.435, 0.470, MET, CHR)
    g.cyl_x(2.400, 2.500, -0.180, 0.320, 0.036, MET, M6, seg=8)       # 拖车钩
    g.cyl_x(2.480, 2.520, -0.180, 0.320, 0.050, MET, M3, seg=8)

    # ---------------- 尾部：尾灯 3 格 + 牌照 + 排气 + 后保险杠
    for sy in (-1, 1):
        ty = sy * 0.680
        g.box(-2.372, -2.300, ty - 0.180, ty + 0.180, 0.640, 0.860, MAT, M0)
        for k, cell in enumerate((E_RED, E_AMBER, E_RED)):
            zc = 0.664 + k * 0.064
            g.box(-2.386, -2.368, ty - 0.160, ty + 0.160, zc, zc + 0.050, EMT, cell)
        for k in range(3):
            zc = 0.660 + k * 0.064
            g.box(-2.390, -2.366, ty - 0.170, ty + 0.170, zc - 0.006, zc, MET, M1)
        for sx in (-1, 1):
            g.box(-2.396, -2.370, ty + sx * 0.162 - 0.016, ty + sx * 0.162 + 0.016,
                  0.630, 0.870, MET, CHR)
    g.box(-2.402, -2.378, -0.240, 0.240, 0.520, 0.660, MET, M5)       # 牌照底板
    g.box(-2.412, -2.400, -0.216, 0.216, 0.530, 0.650, EMT, E_ICE)    # 牌照
    for sx in (-1, 1):
        for sz in (-1, 1):
            g.cyl_x(-2.418, -2.404, sx * 0.188, 0.590 + sz * 0.046, 0.013, MET, M2, seg=6)
    for sy in (-1, 1):
        g.cyl_x(-2.340, -2.460, sy * 0.400, 0.300, 0.040, MET, M0, seg=8)
        g.cyl_x(-2.455, -2.475, sy * 0.400, 0.300, 0.048, MET, M6, seg=8)
        g.box(-2.360, -2.320, sy * 0.400 - 0.028, sy * 0.400 + 0.028, 0.330, 0.378,
              MET, M4)
    g.box(-2.400, -2.300, -0.500, 0.500, 0.355, 0.545, MET, M4)
    for sy in (-1, 1):
        g.box(-2.420, -2.310, sy * 0.505, sy * 0.880, 0.365, 0.535, MET, M3)
        g.box(-2.435, -2.415, sy * 0.545, sy * 0.845, 0.372, 0.528, MET, RUB)
    g.box(-2.412, -2.395, -0.440, 0.440, 0.435, 0.470, MET, CHR)

    # ---------------- 雨刷 ×2
    for sy in (-1, 1):
        g.beam((1.10, sy * 0.10, WIN_Z0 - 0.036), (1.00, sy * 0.60, WIN_Z0 + 0.004),
               0.024, 0.012, MET, M1)
        g.box(1.08, 1.13, sy * 0.09, sy * 0.14, WIN_Z0 - 0.056, WIN_Z0 - 0.020, MET, M4)

    # ---------------- 车轮 ×4
    # cyl_y(y0, y1, cx, cz, r)：旋转轴 Y，轮心 = (cx, cz) = (wx, WR)
    for wx in (WF, WRX):
        for sy in (-1, 1):
            yc = sy * WY
            y_in, y_out = yc - sy * WTH, yc + sy * WTH
            g.cyl_y(min(y_out - sy * 0.038, y_out), max(y_out - sy * 0.038, y_out),
                    wx, WR, WR * 0.975, MAT, RUB, seg=16)              # 外侧胎壁
            g.cyl_y(min(y_in, y_in + sy * 0.038), max(y_in, y_in + sy * 0.038),
                    wx, WR, WR * 0.975, MAT, RUB, seg=16)              # 内侧胎壁
            g.cyl_y(min(y_out - sy * 0.038, y_in + sy * 0.038),
                    max(y_out - sy * 0.038, y_in + sy * 0.038),
                    wx, WR, WR, MAT, RUB, seg=16)                      # 胎面
            rim = yc + sy * (WTH - 0.030)
            g.cyl_y(min(rim - sy * 0.010, rim + sy * 0.004),
                    max(rim - sy * 0.010, rim + sy * 0.004),
                    wx, WR, 0.252, MET, M2, seg=16)                    # 轮辋盘
            g.cyl_y(min(rim - sy * 0.018, rim + sy * 0.008),
                    max(rim - sy * 0.018, rim + sy * 0.008),
                    wx, WR, 0.268, MET, M6, seg=16)                    # 轮辋凸缘
            for k in range(5):                                          # 5 根辐条
                _spoke_xz(g, wx, WR, math.pi * 2 * k / 5 + 0.31, 0.072, 0.240, 0.036,
                          min(rim, rim + sy * 0.020), max(rim, rim + sy * 0.020),
                          MET, M7)
            g.cyl_y(min(rim, rim + sy * 0.018), max(rim, rim + sy * 0.018),
                    wx, WR, 0.076, MET, M5, seg=10)                    # 中心盖
            g.cyl_y(min(rim + sy * 0.016, rim + sy * 0.024),
                    max(rim + sy * 0.016, rim + sy * 0.024),
                    wx, WR, 0.046, MET, CHR, seg=10)                   # 车标盖
            for k in range(5):                                          # 5 颗螺栓
                a = math.pi * 2 * k / 5 + 0.31
                g.cyl_y(min(rim + sy * 0.014, rim + sy * 0.028),
                        max(rim + sy * 0.014, rim + sy * 0.028),
                        wx + 0.110 * math.cos(a), WR + 0.110 * math.sin(a),
                        0.015, MET, M8, seg=6)
            g.cyl_y(min(rim + sy * 0.004, rim + sy * 0.028),                 # 气门嘴
                    max(rim + sy * 0.004, rim + sy * 0.028),
                    wx + 0.225 * math.cos(0.9), WR + 0.225 * math.sin(0.9),
                    0.011, MET, M1, seg=5)
'''


def _semi_pts(cx, cz, r, n=12):
    pts = [(cx, cz)]
    for i in range(n + 1):
        a = math.pi * i / n
        pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


p = "ug_props_v004.py"
s = io.open(p, encoding="utf-8").read()
lines = s.splitlines(True)
start = None
for i, ln in enumerate(lines):
    if ln.startswith("def c_sedan_detail("):
        start = i
        break
assert start is not None, "sedan not found"
head_src = "".join(lines[:start])
io.open(p, "w", encoding="utf-8").write(head_src + NEW)
print("sedan rewritten, total lines =", len((head_src + NEW).splitlines()))
