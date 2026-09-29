"""只读分析：在 19:06 的实拍截图（本轮改动前）里定位底栏 / 计时栏 / 世界时间的像素位置，
为「去掉背板」提供改动前的对照证据。不改动任何文件，只读 + 打印。
"""
from PIL import Image

SRC = r"I:/工作项目/shellstrom2/ShellStorm2/outputs/hud_cleanup_after2_20260928.png"

im = Image.open(SRC).convert("RGB")
W, H = im.size
print("SIZE", W, H)
px = im.load()


def luminance(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def scan_band(y0, y1, x0, x1, tag):
    """统计一个矩形区域内：平均亮度、极暗像素占比、青色描边像素数。"""
    total = 0
    dark = 0
    cyan = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            lum = luminance(r, g, b)
            total += lum
            if lum < 40:
                dark += 1
            # 青色描边/括号：蓝绿明显高于红，且足够亮
            if b > 120 and g > 110 and b - r > 45 and g - r > 35:
                cyan += 1
    n = max(1, (y1 - y0) * (x1 - x0))
    print(
        f"{tag}: mean_lum={total / n:.1f} dark<40={dark / n * 100:.1f}% "
        f"cyan={cyan / n * 100:.2f}%  area=({x0},{y0})-({x1},{y1})"
    )
    return dark / n


# 按 HUD_UI_SCALE=0.80 与 1920x1000 视口推算的几何（改动前后坐标相同）
SC = 0.80
CX = W // 2
# 武器栏：anchor 0.5/1.0，offset -156,-79 .. 156,-20
w_x0, w_x1 = int(CX - 156 * SC), int(CX + 156 * SC)
w_y1 = H
w_y0 = int(H - 79 * SC)
# 快捷槽 0/1
q0_x0, q0_x1 = int(CX - 220 * SC), int(CX - 162 * SC)
q1_x0, q1_x1 = int(CX + 162 * SC), int(CX + 220 * SC)
q_y0, q_y1 = int(H - 75 * SC), int(H - 20 * SC)
print("--- 底栏（改动前，应有深色背板 + 青色四角括号）---")
scan_band(w_y0, w_y1, w_x0, w_x1, "weapon_panel")
scan_band(q_y0, q_y1, q0_x0, q0_x1, "quick_0")
scan_band(q_y0, q_y1, q1_x0, q1_x1, "quick_1")
# 对照：底栏左侧空白（无 HUD），应无深色块
scan_band(w_y0, w_y1, 60, w_x0 - 60, "bottom_left_empty_control")

print("--- 右侧时间区（改动前）---")
t_x0, t_x1 = int(W - 214 * SC), int(W - 18 * SC)
t_y0, t_y1 = int(318 * SC), int(358 * SC)
scan_band(t_y0, t_y1, t_x0, t_x1, "timer_panel")
wt_x0, wt_x1 = int(W - 292 * SC), int(W - 18 * SC)
wt_y0, wt_y1 = int(318 * SC) + 0, int(318 * SC)  # 占位，下面单独扫
wt_y0, wt_y1 = 300, 330  # 世界时间改动前在 366..416 附近（未缩放前坐标）
scan_band(300, 340, wt_x0, wt_x1, "world_time_old_area")


def crop(x0, y0, x1, y1, out):
    box = (max(0, x0), max(0, y0), min(W, x1), min(H, y1))
    im.crop(box).save(out)
    print("CROP_SAVED", out, box)


crop(min(q0_x0, w_x0) - 30, w_y0 - 30, max(q1_x1, w_x1) + 30, H, r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/before_bottom_bar.png")
crop(t_x0 - 30, min(t_y0, 300) - 20, W, t_y1 + 30, r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/before_right_times.png")
