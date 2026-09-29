"""主界面截图曝光审计：量化角色过曝与标题区异常亮点。

只读分析，不改任何资产。
"""
import sys
from PIL import Image

PNG = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/probe_main_entry_screen.png"
img = Image.open(PNG).convert("RGB")
W, H = img.size
print("size", W, H)
px = img.load()


def region_stats(name, x0, y0, x1, y1):
    n = 0
    total = 0.0
    over240 = 0
    over250 = 0
    near255 = 0
    mx = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            # 感知亮度
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            total += lum
            n += 1
            mx = max(mx, lum)
            if lum > 240:
                over240 += 1
            if lum > 250:
                over250 += 1
            if max(r, g, b) >= 254:
                near255 += 1
    print(
        "%-14s n=%6d mean=%6.1f max=%6.1f  >240=%5.2f%%  >250=%5.2f%%  clip255=%5.2f%%"
        % (
            name, n, total / n, mx,
            100.0 * over240 / n, 100.0 * over250 / n, 100.0 * near255 / n,
        )
    )
    return 100.0 * over250 / n


# 角色主体（兔子外观 + 衣服），按截图目视包围盒
region_stats("avatar", 480, 300, 760, 570)
# 角色头部单独看（耳朵 + 兜帽，最容易烧白）
region_stats("avatar_head", 520, 300, 720, 400)
# 衣服躯干
region_stats("avatar_torso", 550, 400, 700, 500)
# 对照：左侧菜单按钮区（应为深色底）
region_stats("buttons", 70, 340, 440, 500)
# 对照：背景地面
region_stats("floor", 60, 620, 1200, 700)
# 对照：右上背景
region_stats("bg_top_right", 900, 20, 1260, 200)

print()
print("--- 标题区异常亮点扫描 (x 240..380, y 200..270) ---")
hits = []
for y in range(200, 270):
    for x in range(240, 380):
        r, g, b = px[x, y]
        lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if lum > 150 and r > g and g > b:
            # 偏暖（红>绿>蓝）且亮
            hits.append((x, y, r, g, b, round(lum, 1)))
print("warm-bright pixels:", len(hits))
for h in hits[:12]:
    print("  ", h)
if hits:
    xs = [h[0] for h in hits]
    ys = [h[1] for h in hits]
    print("  bbox x[%d,%d] y[%d,%d]" % (min(xs), max(xs), min(ys), max(ys)))
    cy = sum(ys) // len(ys)
    cx = sum(xs) // len(xs)
    r, g, b = px[cx, cy]
    print("  centroid=(%d,%d) rgb=(%d,%d,%d)" % (cx, cy, r, g, b))
