"""裁剪放大主界面截图的关键区域，用于亲眼核对。

只读分析。
"""
from PIL import Image

PNG = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/probe_main_entry_screen.png"
img = Image.open(PNG).convert("RGB")

crops = {
    # 标题区右上角，含目视疑似小亮点
    "entry_crop_title": (250, 190, 470, 300),
    # 角色头部（耳朵 + 兜帽）
    "entry_crop_head": (500, 290, 760, 430),
    # 角色整体
    "entry_crop_avatar": (470, 280, 790, 590),
}

for name, box in crops.items():
    c = img.crop(box)
    scale = max(1, int(900 / c.width))
    c = c.resize((c.width * scale, c.height * scale), Image.NEAREST)
    out = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/%s.png" % name
    c.save(out)
    print(name, "box=", box, "scale=", scale, "->", c.size)

# 精确定位标题区里的孤立亮点
px = img.load()
print()
print("--- 孤立亮点扫描 (x 250..470, y 190..300)，判据：亮度>其他区域10px均值+60 ---")
found = []
for y in range(195, 295, 1):
    for x in range(255, 465, 1):
        r, g, b = px[x, y]
        lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if lum < 90:
            continue
        # 周围 12px 环形均值
        tot = 0.0
        cnt = 0
        for dy in range(-12, 13, 4):
            for dx in range(-12, 13, 4):
                xx, yy = x + dx, y + dy
                if 0 <= xx < img.width and 0 <= yy < img.height:
                    rr, gg, bb = px[xx, yy]
                    tot += 0.2126 * rr + 0.7152 * gg + 0.0722 * bb
                    cnt += 1
        if cnt and lum - tot / cnt > 60:
            found.append((x, y, r, g, b, round(lum, 1), round(tot / cnt, 1)))
print("hits:", len(found))
for h in found[:20]:
    print("   x=%d y=%d rgb=(%d,%d,%d) lum=%.1f ring=%.1f" % h)
