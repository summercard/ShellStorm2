"""检测新截图的尺寸与红色标注框。只读分析。"""
from PIL import Image

P = r"C:\Users\zhuangmenghong\.workbuddy\clipboard-images\clipboard-2026-09-28T11-29-01-208Z-a2633eef.png"
img = Image.open(P).convert("RGB")
W, H = img.size
px = img.load()
print("size", W, H)

red = set()
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        if r > 175 and r - g > 85 and r - b > 85 and g < 130 and b < 130:
            red.add((x, y))
print("red px:", len(red))

seen = set()
boxes = []
for p in list(red):
    if p in seen:
        continue
    stack = [p]
    seen.add(p)
    comp = []
    while stack:
        cx, cy = stack.pop()
        comp.append((cx, cy))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (cx + dx, cy + dy)
            if q in red and q not in seen:
                seen.add(q)
                stack.append(q)
    if len(comp) < 100:
        continue
    xs = [c[0] for c in comp]
    ys = [c[1] for c in comp]
    boxes.append((min(xs), min(ys), max(xs), max(ys), len(comp)))
boxes.sort(key=lambda b: -b[4])
for i, (x0, y0, x1, y1, n) in enumerate(boxes, 1):
    print("  #%d x[%d,%d] y[%d,%d] w=%d h=%d px=%d" % (i, x0, x1, y0, y1, x1 - x0, y1 - y0, n))

# 放大整图
img.resize((W * 2, H * 2), Image.LANCZOS).save(
    r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/v4_shot_zoom.png"
)
print("saved zoom")
