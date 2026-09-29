"""量化主界面截图里角色（亮色主体）在画面中的水平重心。

设计口径（docs/v0.1/16_技术施工_主页面与角色换装.md §1 + 探针断言）：
角色应落在屏幕右侧 x ∈ [0.55, 0.88]、y ∈ [0.15, 0.85]。
只读分析。
"""
from PIL import Image

PNG = r"I:/工作项目/shellstrom2/ShellStorm2/_scratch/probe_main_entry_screen.png"
img = Image.open(PNG).convert("RGB")
W, H = img.size
px = img.load()

# UI 左栏是深色底（按钮/标题），角色是浅色主体。
# 判据：亮度 > 95 且位于右半区之外也纳入统计 —— 用亮度阈值把角色从暗背景里切出来。
xs = []
ys = []
lum_map = {}
for y in range(0, H):
    for x in range(0, W):
        r, g, b = px[x, y]
        lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
        lum_map[(x, y)] = lum
        if lum > 100:
            xs.append(x)
            ys.append(y)

print("bright(>100) pixel count:", len(xs))

# 角色包围盒：排除左侧 UI 文字/按钮（那些也在 x<470），
# 用连通性近似 —— 取 x>470 区域的亮像素。
pairs = [(x, y) for (x, y) in zip(xs, ys) if x > 470]
xs2 = [p[0] for p in pairs]
ys2 = [p[1] for p in pairs]
print("avatar-region bright count (x>470):", len(pairs))
if pairs:
    print("  bbox x=[%d,%d] y=[%d,%d]" % (min(xs2), max(xs2), min(ys2), max(ys2)))

    # 亮度加权重心（越亮越算角色本体）
    sx = 0.0
    sy = 0.0
    sw = 0.0
    for (x, y) in pairs:
        w = lum_map[(x, y)] - 100.0
        sx += x * w
        sy += y * w
        sw += w
    cx = sx / sw
    cy = sy / sw
    print("  luminance-weighted centroid = (%.1f, %.1f)" % (cx, cy))
    print("  normalized centoid = (%.3f, %.3f)  [screen 0..1]" % (cx / W, cy / H))
    print()
    print("  设计口径 x in [0.550, 0.880] y in [0.150, 0.850]")
    okx = 0.550 <= cx / W <= 0.880
    oky = 0.150 <= cy / H <= 0.850
    print("  horizontal (screen-right) satisfied:", okx)
    print("  vertical satisfied:", oky)
    if not okx:
        need = 0.55 * W
        print("  >> 需右移 %.0f px 才进设计区间下界" % (need - cx))

    # 几何包围盒中心（不做亮度加权）
    print()
    print("  bbox centroid = (%.1f, %.1f) -> (%.3f, %.3f)"
          % ((min(xs2) + max(xs2)) / 2.0, (min(ys2) + max(ys2)) / 2.0,
             (min(xs2) + max(xs2)) / 2.0 / W, (min(ys2) + max(ys2)) / 2.0 / H))
