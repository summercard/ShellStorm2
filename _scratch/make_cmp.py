"""Deliverable: before/after comparison of the bottom HUD bar. Read-only on sources."""
from PIL import Image, ImageDraw

SC = 0.80
BEFORE = r"I:/工作项目/shellstrom2/ShellStorm2/outputs/hud_cleanup_after2_20260928.png"
AFTER = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/probe_expedition_hud_after.png"
OUT = r"I:/工作项目/shellstrom2/ShellStorm2/outputs/hud_bottom_bar_before_after_20260928.png"

PAD = 24
LABEL_H = 34


def strip(path):
    im = Image.open(path).convert("RGB")
    W, H = im.size
    cx = W // 2
    y0 = int(H - 79 * SC) - 26
    return im.crop((cx - 330, y0, cx + 330, H))


b = strip(BEFORE)
a = strip(AFTER)
w = 660
h = LABEL_H + b.height + PAD + LABEL_H + a.height + PAD

canvas = Image.new("RGB", (w, h), (18, 22, 28))
draw = ImageDraw.Draw(canvas)
draw.text((10, 8), "BEFORE - dark plate + cyan frame on all three bottom panels", fill=(255, 120, 120))
y = LABEL_H
canvas.paste(b, (0, y))
y += b.height + PAD
draw.text((10, y + 8), "AFTER - plate and frame removed, text keeps black outline", fill=(120, 240, 160))
y += LABEL_H
canvas.paste(a, (0, y))

canvas.save(OUT)
print("SAVED", OUT, canvas.size)
