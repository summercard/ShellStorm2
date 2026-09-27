"""在旧报告的「全关总览」SVG 里定位 room_03 标签，并列出其周围 40 m 内的灰点 —— 
用来判断用户截图是不是这张（旧机制总览）。"""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OLD = os.path.abspath(os.path.join(HERE, "..", "..", "..", "outputs",
                                   "expedition01_spawn_box_map.html"))
text = open(OLD, encoding="utf-8").read()

svgs = re.findall(r'<svg .*?</svg>', text, re.S)
print("svg blocks: %d, sizes=%s" % (len(svgs), [len(s) for s in svgs][:6]))

for i, svg in enumerate(svgs[:2]):
    n_grey = svg.count('fill="#8b98a5"')
    n_col = len(re.findall(r'fill="#(?:f85149|a371f7|2ea043|4f8cc9|ff9e64|e3b341|ff2d55|f2cc60)"', svg))
    labels = re.findall(r'<text x="([\d.]+)" y="([\d.]+)" font-size="[\d.]+" fill="#c9d1d9"[^>]*>([^<]+)</text>', svg)
    print("\n--- overview[%d] greydots=%d colored=%d labels=%d" % (i, n_grey, n_col, len(labels)))
    for lab in labels:
        print("    label %-10s px=(%s,%s)" % (lab[2], lab[0], lab[1]))
    if "room_03" not in [l[2] for l in labels]:
        continue
    lx, ly = [(float(l[0]), float(l[1])) for l in labels if l[2] == "room_03"][0]
    scale = 4.6
    circles = re.findall(r'<circle cx="([\d.]+)" cy="([\d.]+)" r="([\d.]+)" fill="(#[0-9a-f]{6})"', svg)
    near = []
    for cx, cy, r, f in circles:
        dx, dy = (float(cx) - lx) / scale, (float(cy) - ly) / scale
        if abs(dx) <= 35 and abs(dy) <= 35:
            near.append((dx, dy, r, f))
    print("    circles within 35 m of room_03 label: %d" % len(near))
    for dx, dy, r, f in sorted(near, key=lambda t: (t[1], t[0])):
        print("      (%+7.1f m, %+7.1f m)  r=%s  %s" % (dx, dy, r, f))
