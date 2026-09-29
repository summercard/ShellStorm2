"""自动检测主人截图里的红色标注框，精确给出矩形范围。只读分析。

判据：描边红像素 R 明显高于 G/B。聚类成若干矩形后打印包围盒。
"""
from PIL import Image

SRC = r"C:\Users\zhuangmenghong\.workbuddy\clipboard-images\clipboard-2026-09-28T10-23-24-919Z-99fd660b.jpg"
img = Image.open(SRC).convert("RGB")
W, H = img.size
px = img.load()
print("size", W, H)

red = set()
for y in range(H):
    for x in range(W):
        r, g, b = px[x, y]
        if r > 175 and r - g > 85 and r - b > 85 and g < 130 and b < 130:
            red.add((x, y))

print("red stroke pixels:", len(red))

# 连通分量（4 邻域，用步长加速的粗聚类）
seen = set()
boxes = []
pts = list(red)
ptset = red
for p in pts:
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
            if q in ptset and q not in seen:
                seen.add(q)
                stack.append(q)
    if len(comp) < 400:
        continue
    xs = [c[0] for c in comp]
    ys = [c[1] for c in comp]
    boxes.append((min(xs), min(ys), max(xs), max(ys), len(comp)))

boxes.sort(key=lambda b: -b[4])
print()
print("detected red annotation boxes (>=400 px):")
for i, (x0, y0, x1, y1, n) in enumerate(boxes, 1):
    print(
        "  #%d  x[%4d,%4d] y[%4d,%4d]  w=%4d h=%4d  px=%5d"
        % (i, x0, x1, y0, y1, x1 - x0, y1 - y0, n)
    )
