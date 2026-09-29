"""检测两张新截图里的红色标注框。只读分析。"""
from PIL import Image

IMGS = [
    ("img1_status", r"C:\Users\zhuangmenghong\.workbuddy\clipboard-images\clipboard-2026-09-28T10-53-17-621Z-3d2ed2db.png"),
    ("img2_time", r"C:\Users\zhuangmenghong\.workbuddy\clipboard-images\clipboard-2026-09-28T10-53-17-622Z-2729d6ae.png"),
]

for tag, path in IMGS:
    img = Image.open(path).convert("RGB")
    W, H = img.size
    px = img.load()
    red = set()
    for y in range(H):
        for x in range(W):
            r, g, b = px[x, y]
            if r > 175 and r - g > 85 and r - b > 85 and g < 130 and b < 130:
                red.add((x, y))
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
        if len(comp) < 120:
            continue
        xs = [c[0] for c in comp]
        ys = [c[1] for c in comp]
        boxes.append((min(xs), min(ys), max(xs), max(ys), len(comp)))
    boxes.sort(key=lambda b: -b[4])
    print("%s size=%s  red_px=%d  boxes=%d" % (tag, (W, H), len(red), len(boxes)))
    for i, (x0, y0, x1, y1, n) in enumerate(boxes, 1):
        print("   #%d x[%d,%d] y[%d,%d] w=%d h=%d px=%d" % (i, x0, x1, y0, y1, x1 - x0, y1 - y0, n))
    print()
