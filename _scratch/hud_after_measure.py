"""只读分析：本轮改动后截图里，底栏 / 计时栏 / 世界时间区域的深色底与青色描边是否消失。
判据与改动前同一套公式，便于逐行对照。只读 + 打印，不改文件。
"""
from PIL import Image

AFTER = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/probe_expedition_hud_after.png"
BEFORE = r"I:/工作项目/shellstrom2/ShellStorm2/outputs/hud_cleanup_after2_20260928.png"

SC = 0.80


def luminance(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def stats(im, x0, y0, x1, y1):
    W, H = im.size
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(W, x1), min(H, y1)
    px = im.load()
    total = dark = cyan = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b = px[x, y]
            total += luminance(r, g, b)
            if luminance(r, g, b) < 40:
                dark += 1
            if b > 120 and g > 110 and b - r > 45 and g - r > 35:
                cyan += 1
    n = max(1, (x1 - x0) * (y1 - y0))
    return total / n, dark / n * 100, cyan / n * 100


def box_for(im, kind):
    W, H = im.size
    CX = W // 2
    if kind == "weapon":
        return int(CX - 156 * SC), int(H - 79 * SC), int(CX + 156 * SC), H
    if kind == "quick0":
        return int(CX - 220 * SC), int(H - 75 * SC), int(CX - 162 * SC), int(H - 20 * SC)
    if kind == "quick1":
        return int(CX + 162 * SC), int(H - 75 * SC), int(CX + 220 * SC), int(H - 20 * SC)
    if kind == "timer":
        return int(W - 214 * SC), int(318 * SC), int(W - 18 * SC), int(358 * SC)
    if kind == "worldtime":
        return int(W - 292 * SC), int(48 * SC), int(W - 18 * SC), int(98 * SC)
    if kind == "bottom_left_control":
        return 60, int(H - 79 * SC), int(CX - 156 * SC) - 60, H
    raise KeyError(kind)


before = Image.open(BEFORE).convert("RGB")
after = Image.open(AFTER).convert("RGB")
print("before", before.size, " after", after.size)
print(f"{'region':22s} {'mean_lum 前→后':>22s} {'dark% 前→后':>18s} {'cyan% 前→后':>18s}")

for kind in ["weapon", "quick0", "quick1", "timer", "worldtime", "bottom_left_control"]:
    b = stats(before, *box_for(before, kind))
    a = stats(after, *box_for(after, kind))
    print(
        f"{kind:22s} {b[0]:8.1f} →{a[0]:7.1f}   {b[1]:7.1f}% →{a[1]:6.1f}%   {b[2]:7.2f}% →{a[2]:6.2f}%"
    )

# 眼睛看得到的证据：裁剪前后同区域的底栏与右侧时间区
for im, tag in [(before, "before"), (after, "after")]:
    W, H = im.size
    CX = W // 2
    im.crop((int(CX - 256), int(H - 79 * SC) - 26, int(CX + 256), H)).save(
        rf"I:/工作项目/shellstrom2/ShellStorm2/_scratch/{tag}_bottom_strip.png"
    )
    im.crop((int(W - 320), 20, W, 200)).save(
        rf"I:/工作项目/shellstrom2/ShellStorm2/_scratch/{tag}_right_time.png"
    )
print("CROPS_SAVED")
