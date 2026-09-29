"""看底部整条与顶部中央的红框精确范围。只读分析。"""
from PIL import Image

SRC = r"C:\Users\zhuangmenghong\.workbuddy\clipboard-images\clipboard-2026-09-28T10-23-24-919Z-99fd660b.jpg"
img = Image.open(SRC).convert("RGB")

crops = {
    "q_bottom_wide": (560, 840, 1500, 1000),
    "q_top_wide": (560, 0, 1400, 120),
    "q_left_all": (0, 200, 480, 500),
}
for name, box in crops.items():
    c = img.crop(box)
    s = max(1, int(1100 / c.width))
    c = c.resize((c.width * s, c.height * s), Image.LANCZOS)
    out = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/%s.png" % name
    c.save(out)
    print(name, box, "x%d" % s, "->", c.size)
