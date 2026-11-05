"""把 gpt-image-2 生成的「绿色黏液摊」做成方形地面贴图（透明底，512²）。

⚠ 生成器给的其实是**白底 RGB**（`background=transparent` 没生效，整图 alpha 恒 255），
所以本脚本第一步是**本地抠白**，不能直接读 alpha 求包围盒（否则 bbox = 全图）。

口径：
  1. 从四边**泛洪**出与边缘连通的近白像素 ⇒ 背景掩膜。用泛洪而不是「亮度阈值」，
     是为了保住气泡里那几颗**白色高光**（它们被绿色包着，泛洪到不了，是刻意的细节）；
  2. alpha = 背景反相，再 1px 高斯羽化（AI 出来的边缘本身就是从白到绿的混合，
     硬切会留锯齿）；
  3. **去白边（despill）**：半透明像素按 `c_obj = (c - 255·(1-a)) / a` 反解，
     否则羽化边会带一圈白晕，贴在深色地板上像发光；
  4. 用 alpha > ALPHA_CONTENT 求内容包围盒（**飞溅小点算内容** —— 它们是轮廓的一部分）；
  5. 以包围盒长边为基准扩成正方形，四周留 PAD_RATIO 安全边距，LANCZOS 缩到 TARGET²
     （512：贴图只铺在 0.6~0.9m 的地面片上，再大是浪费显存；也在
     `check_runtime_texture_policy` 的 1024 上限内）；
  6. 递归把 alpha 低于 CUT 的像素清成完全透明（去掉残留雾边）。

用法：
  python build_puddle_texture.py <源图.png> <输出.png> [TARGET]
"""

import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SRC = sys.argv[1]
DST = sys.argv[2]
TARGET = int(sys.argv[3]) if len(sys.argv) > 3 else 1024

PAD_RATIO = 0.08
ALPHA_CONTENT = 24
ALPHA_CUT = 10
# 生成图的背景**不是纯白**，而是一层浅灰渐晕（实测最暗 207，与 255 差 48）。
# 阈值必须盖住这层渐晕，否则右上角会留一片灰影。绿色本体与该阈值差 160+，
# 浅色高光（#A8F566，差 87）虽也低于阈值，但被绿色包着、泛洪打不进去，安全。
WHITE_THRESH = 80
FEATHER_RADIUS = 0.8
# 泛洪后仍残留的**灰色孤岛**（渐晕被描边割开的碎片）：低饱和 + 高亮度 ⇒ 丢掉
GHOST_SAT_MAX = 26
GHOST_VALUE_MIN = 168

# ── 描边加粗（业主 2026-11-05「轮廓感强一些」的落地手段）─────────────────
# 生成图自带的描边在**源分辨率**下约 12px；按它在游戏里的实际占屏（0.7m 的贴地面片，
# 960×600 视口里约 200px 宽）换算后只剩 2~3px，实拍里几乎读不出来（第一版就是这样，
# 描边被 mipmap 平滑成了一片模糊的绿）。这里在**源图上向外扩一圈**同色深描边，
# 让它在缩到占屏尺寸后仍有 4~5px —— 这是「轮廓感」唯一能靠贴图本身解决的部分，
# 靠加材质描边/后处理都做不到（unshaded 面片没有边界可描）。
OUTLINE_OUT_PX = 24
# 描边色取原图最暗的那批绿（实测 #24500F），再压暗一点 ⇒ 与 #60AD3D 的填充形成硬对比，
# 贴在深灰地板上也读得出边界（浅地板上则靠「比填充暗得多」成立）。
OUTLINE_RGB = (26, 58, 10)
# 泛洪用的哨兵色：绝不会出现在原图里（原图只有绿/白系）
SENTINEL = (255, 0, 255)


def _drop_ghost_islands(rgb: Image.Image, keep: np.ndarray) -> np.ndarray:
    """把「低饱和 + 高亮度」的孤立碎片从 keep 掩膜里剔掉（保留绿色飞溅点）。

    用 8 连通标记；只剔**面积 < 1% 画幅**的碎块 —— 主体与飞溅点都是饱和绿，
    不会被这条规则误伤（真绿玻璃点的高饱和远高于 GHOST_SAT_MAX）。
    """
    from scipy import ndimage

    labels, count = ndimage.label(keep, structure=np.ones((3, 3), dtype=int))
    if count <= 1:
        return keep
    arr = np.asarray(rgb).astype(np.float32)
    out = keep.copy()
    total = keep.size
    for label in range(1, count + 1):
        region = labels == label
        area = int(region.sum())
        if area == 0 or area > total * 0.01:
            continue
        mx = arr[region].max(axis=1)
        mn = arr[region].min(axis=1)
        sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1.0) * 255.0, 0.0)
        if sat.mean() < GHOST_SAT_MAX and arr[region].mean() > GHOST_VALUE_MIN:
            out[region] = False
    return out


def key_white_background(im: Image.Image) -> Image.Image:
    """白底 RGB → 带 alpha 的 RGBA（泛洪 + 去灰孤岛 + 羽化 + 去白边）。"""
    rgb = im.convert("RGB")
    w, h = rgb.size
    filled = rgb.copy()
    # 四角各泛洪一次：白底往往是连通的，但生成图偶尔有被描边割开的角落
    for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(filled, seed, SENTINEL, thresh=WHITE_THRESH)
    mask = np.all(np.asarray(filled) == np.array(SENTINEL, dtype=np.uint8), axis=2)
    keep = _drop_ghost_islands(rgb, ~mask)

    alpha = np.where(keep, 255.0, 0.0).astype(np.uint8)
    alpha_img = Image.fromarray(alpha, "L").filter(
        ImageFilter.GaussianBlur(FEATHER_RADIUS)
    )
    a = np.asarray(alpha_img).astype(np.float32) / 255.0

    # 去白边：半透明像素 = 目标色 × a + 白 × (1-a)，反解目标色
    src = np.asarray(rgb).astype(np.float32)
    safe = np.maximum(a, 1e-4)[..., None]
    obj = (src - 255.0 * (1.0 - safe)) / safe
    # 只在羽化带做反解；完全不透明区原样保留（避免把纯白高光也当白边削掉）
    blend = (a > 0.02) & (a < 0.995)
    out_rgb = np.where(blend[..., None], obj, src)
    out_rgb = np.clip(out_rgb, 0.0, 255.0).astype(np.uint8)

    return Image.fromarray(np.dstack([out_rgb, alpha_img]), "RGBA")


def _grow_outline(im: Image.Image) -> Image.Image:
    """给固体外缘向外扩一圈深墨绿描边（`OUTLINE_OUT_PX` 源图像素）。

    只扩**外面**、不侵蚀里面：原图有几颗巴掌大的浅绿高光气泡（直径 20~30px），
    往内侵蚀会先把它们吃干净 —— 那正是业主点名要留的「不写实」的部分。
    """
    from scipy import ndimage

    arr = np.asarray(im).astype(np.float32)
    alpha = arr[..., 3]
    body = alpha > ALPHA_CONTENT
    grown = ndimage.binary_dilation(body, iterations=OUTLINE_OUT_PX)
    ring = grown & ~body
    if not ring.any():
        return im

    out = arr.copy()
    out[ring, 0] = OUTLINE_RGB[0]
    out[ring, 1] = OUTLINE_RGB[1]
    out[ring, 2] = OUTLINE_RGB[2]
    out[ring, 3] = 255.0
    # 环的内侧一律盖成描边色：原图描边与填充之间有一圈抗锯齿过渡，
    # 不盖掉的话加粗后的描边会被那圈过渡「切」出一条浅色缝。
    edge = body & ~ndimage.binary_erosion(body, iterations=1)
    out[edge, 0] = np.minimum(out[edge, 0], OUTLINE_RGB[0])
    out[edge, 1] = np.minimum(out[edge, 1], OUTLINE_RGB[1])
    out[edge, 2] = np.minimum(out[edge, 2], OUTLINE_RGB[2])

    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def main() -> None:
    im = Image.open(SRC)
    if im.mode != "RGBA" or im.convert("RGBA").getchannel("A").getextrema()[0] > 250:
        im = key_white_background(im)
    else:
        im = im.convert("RGBA")

    im = _grow_outline(im)

    alpha = im.getchannel("A")
    bbox = alpha.point(lambda v: 255 if v > ALPHA_CONTENT else 0).getbbox()
    if bbox is None:
        raise SystemExit("source image has no visible content after keying")

    left, top, right, bottom = bbox
    cw, ch = right - left, bottom - top
    side = int(round(max(cw, ch) * (1.0 + PAD_RATIO * 2.0)))
    cx = (left + right) // 2
    cy = (top + bottom) // 2
    box = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)

    # crop 允许越界：越界部分由 PIL 补成完全透明，正好当成安全边距。
    out = im.crop(box).resize((TARGET, TARGET), Image.LANCZOS)

    px = out.load()
    for y in range(TARGET):
        for x in range(TARGET):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 0) if a < ALPHA_CUT else (r, g, b, a)

    out.save(DST, "PNG", optimize=True)

    bb = out.getchannel("A").point(lambda v: 255 if v > ALPHA_CONTENT else 0).getbbox()
    opaque = np.asarray(out.getchannel("A")) > 250
    print(
        f"bbox={bbox} side={side} -> {DST} {out.size} content={bb} "
        f"opaque_ratio={opaque.mean():.3f}"
    )


if __name__ == "__main__":
    main()
