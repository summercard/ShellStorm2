"""放大改动后的实拍图关键区域，核对细节。只读分析。"""
from PIL import Image

SRC = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/probe_expedition_hud_after.png"
img = Image.open(SRC).convert("RGB")
W, H = img.size
print("size", W, H)

crops = {
    "after_left": (0, 0, 560, 420),        # 状态块 + 任务卡
    "after_right": (1560, 0, 1920, 380),   # 右上（雷达位置）
    "after_bottom": (600, 880, 1320, 1000),
}
for name, box in crops.items():
    c = img.crop(box)
    s = max(1, int(1000 / c.width))
    c = c.resize((c.width * s, c.height * s), Image.LANCZOS)
    c.save(r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/%s.png" % name)
    print(name, box, "x%d" % s)
