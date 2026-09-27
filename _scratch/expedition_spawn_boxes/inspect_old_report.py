"""从**旧**报告 HTML 里抽出 room_03 的卡片正文（去标签），看它当时到底画成什么样。"""
import re
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OLD = os.path.abspath(os.path.join(HERE, "..", "..", "..", "outputs",
                                   "expedition01_spawn_box_map.html"))
text = open(OLD, encoding="utf-8").read()
print("file=%s bytes=%d" % (OLD, len(text)))

# 页面头部 chip 行（总览数字）
m = re.search(r'<div class="meta">(.*?)</div>', text, re.S)
if m:
    chips = re.findall(r'<b>(.*?)</b>', m.group(1))
    print("HEADER CHIPS:", chips)

# 逐房卡片
cards = re.split(r'<div class="card">', text)
for card in cards:
    m = re.search(r'<h3>(.*?)</h3>', card)
    if not m or "room_03" not in m.group(1):
        continue
    body = card.split('</div></body>')[0]
    # 去掉 svg 块（太长），只留文字与表格
    body_nosvg = re.sub(r'<svg.*?</svg>', '<<<SVG>>>', body, flags=re.S)
    body_nosvg = re.sub(r'<[^>]+>', ' ', body_nosvg)
    body_nosvg = re.sub(r'[ \t]+', ' ', body_nosvg)
    body_nosvg = re.sub(r'\n\s*\n+', '\n', body_nosvg)
    print("\n===== room_03 CARD (text only) =====")
    print(body_nosvg.strip()[:2500])
    # SVG 里的盒矩形：x/y/w/h + rotate 中心
    svg = re.search(r'<svg.*?</svg>', body, re.S)
    if svg:
        rects = re.findall(
            r'<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="([\d.]+)" '
            r'fill="#39c5cf" fill-opacity="0.13"[^/]*transform="rotate\(([-\d.]+) ([\d.]+) ([\d.]+)\)"',
            svg.group(0))
        print("\nBOX RECTS (svg px, scale=9, pad=3):")
        for r in rects:
            print("   ", r)
        circles = re.findall(r'<circle cx="([\d.]+)" cy="([\d.]+)" r="([\d.]+)" fill="(#[0-9a-f]{6})"', svg.group(0))
        print("POINT CIRCLES: %d" % len(circles))
        for c in circles:
            print("   ", c)
