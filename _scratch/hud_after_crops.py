"""只读：把改动后截图缩到可读尺寸，并把底栏区域放大裁剪，便于目视核对「框是否没了」。"""
from PIL import Image

AFTER = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/probe_expedition_hud_after.png"
im = Image.open(AFTER).convert("RGB")
W, H = im.size

# 整图缩略
im.resize((W // 2, H // 2), Image.LANCZOS).save(
    r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/after_full_half.png"
)
# 底栏整条（含左右快捷槽与两侧留白，看有没有残留框线）
im.crop((0, H - 130, W, H)).save(
    r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/after_bottom_wide.png"
)
# 底栏中段放大 2 倍
mid = im.crop((640, H - 120, 1280, H))
mid.resize((mid.width * 2, mid.height * 2), Image.LANCZOS).save(
    r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/after_bottom_zoom2x.png"
)
print("OK", im.size)
