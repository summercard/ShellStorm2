"""把 gpt-image-2 生成的吼叫贴纸裁成方形图标贴图（透明底）。

口径：
  1. 用 alpha>阈值 的像素求内容包围盒；
  2. 以包围盒长边为基准扩成正方形，四周再留 PAD_RATIO 的安全边距；
  3. LANCZOS 缩到 TARGET×TARGET；
  4. 递归把 alpha 低于 CUT 的像素清成完全透明（去掉生成器残留的极淡雾边）。
"""

import sys
from PIL import Image

SRC = sys.argv[1]
DST = sys.argv[2]
TARGET = int(sys.argv[3]) if len(sys.argv) > 3 else 256

PAD_RATIO = 0.10
ALPHA_CONTENT = 24
ALPHA_CUT = 10

im = Image.open(SRC).convert("RGBA")
w, h = im.size
alpha = im.getchannel("A")

bbox = alpha.point(lambda v: 255 if v > ALPHA_CONTENT else 0).getbbox()
if bbox is None:
    raise SystemExit("source image has no visible content")

left, top, right, bottom = bbox
cw, ch = right - left, bottom - top
side = max(cw, ch)
side = int(round(side * (1.0 + PAD_RATIO * 2.0)))
cx = (left + right) // 2
cy = (top + bottom) // 2
box = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)

# crop 允许越界：越界部分由 PIL 补成完全透明，正好当成安全边距。
sq = im.crop(box)

out = sq.resize((TARGET, TARGET), Image.LANCZOS)

px = out.load()
for y in range(TARGET):
    for x in range(TARGET):
        r, g, b, a = px[x, y]
        px[x, y] = (r, g, b, 0) if a < ALPHA_CUT else (r, g, b, a)

out.save(DST, "PNG", optimize=True)

bb = out.getchannel("A").point(lambda v: 255 if v > ALPHA_CONTENT else 0).getbbox()
print(f"src={w}x{h} bbox={bbox} side={side} -> {DST} {out.size} content={bb}")
