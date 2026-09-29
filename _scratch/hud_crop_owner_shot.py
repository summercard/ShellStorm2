"""裁剪主人截图（1920x1000），看清四个红框范围与面板文案。只读分析。"""
from PIL import Image

SRC = r"C:\Users\zhuangmenghong\.workbuddy\clipboard-images\clipboard-2026-09-28T10-23-24-919Z-99fd660b.jpg"
img = Image.open(SRC).convert("RGB")
W, H = img.size
print("size", W, H)

crops = {
    "q_status": (0, 0, 640, 240),        # 左上角色状态块
    "q_objective": (0, 220, 600, 470),   # 左侧任务引导面板
    "q_radar": (1560, 20, 1920, 420),    # 右上雷达
    "q_bottom": (660, 880, 1240, 1000),  # 底部中央
    "q_top": (620, 0, 1340, 110),        # 顶部中央
}
for name, box in crops.items():
    c = img.crop(box)
    s = max(1, int(980 / c.width))
    c = c.resize((c.width * s, c.height * s), Image.LANCZOS)
    out = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/%s.png" % name
    c.save(out)
    print(name, box, "x%d" % s, "->", c.size)
