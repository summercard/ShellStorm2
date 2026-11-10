"""把黑底白剪影 PNG 转成 GDScript 多边形常量。

工程约束：HUD 内不允许出现裸 `TextureRect`（`verify_reference_hud_fate_visual` 断言
HUD 里 `TextureRect` 数量必须等于 3D 投影图标数量），所以剪影必须以**矢量多边形**
形式画在 `_draw()` 里。本工具负责「掩码 → 轮廓 → 简化 → 归一化坐标」这一段，
产出可以直接粘进 GDScript 的数组字面量。

## 算法（为什么是这三步）

1. **放大再二值化**：原掩码 96 px 上直接描边会得到一堆 1 px 的阶梯，简化后要么
   丢耳朵要么长毛刺。先 3× 双线性放大到 288 px 再按中间灰度阈值二值化，
   边界位置本身就带了亚像素信息。
2. **边界有向边行走**：对每个前景像素，若某一侧邻居是背景，就沿那一侧加一条
   **有向单位边**（首尾相接、内部始终在同一侧）。把边按起点串成环，取最长那个
   —— 剪影的四肢可能并成一块、也可能有分离的小块，小块一律丢弃（图标要的是一整块
   可辨认的形状）。这比 Moore 邻域跟踪好写且不会因为"回到上一个点"陷入二点环。
3. **RDP 简化**：把阶梯折线压到 `eps` 误差内的少量拐点。`eps` 以放大后的像素计。

最后归一化到 `[-0.5, 0.5]`，**按最长边**铺满并保持长宽比（图标框是正方形，
翻滚帧本身是竖长或横长，等比缩放才不会变形）。

用法：
    python3 scripts/trace_dash_glyph.py <mask_png> [eps] [out.gd.txt] [upscale]
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

# 二值化阈值（0~255）。原掩码是纯黑白，放大后边缘出现中间灰度，取 110 略偏"瘦"：
# 剪影在 HUD 上只有 20 多 px，轮廓宁可瘦一点也不要糊成一团。
MASK_THRESHOLD = 110


def load_mask(path: Path, upscale: int) -> list[list[bool]]:
    image = Image.open(path).convert("L")
    if upscale > 1:
        image = image.resize(
            (image.width * upscale, image.height * upscale), Image.BILINEAR
        )
    width, height = image.size
    pixels = image.load()
    return [[pixels[x, y] > MASK_THRESHOLD for x in range(width)] for y in range(height)]


def boundary_edges(mask: list[list[bool]]) -> dict[tuple[int, int], list[tuple[int, int]]]:
    """构造边界有向边。返回 起点 → [终点...]。"""
    height = len(mask)
    width = len(mask[0])

    def inside(x: int, y: int) -> bool:
        return 0 <= x < width and 0 <= y < height and mask[y][x]

    edges: dict[tuple[int, int], list[tuple[int, int]]] = {}
    for y in range(height):
        for x in range(width):
            if not mask[y][x]:
                continue
            # 四条边统一按「内部在行进方向右侧」定向（顺时针绕外轮廓）。
            if not inside(x, y - 1):
                edges.setdefault((x, y), []).append((x + 1, y))
            if not inside(x + 1, y):
                edges.setdefault((x + 1, y), []).append((x + 1, y + 1))
            if not inside(x, y + 1):
                edges.setdefault((x + 1, y + 1), []).append((x, y + 1))
            if not inside(x - 1, y):
                edges.setdefault((x, y + 1), []).append((x, y))
    return edges


def all_loops(edges: dict[tuple[int, int], list[tuple[int, int]]]) -> list[list[tuple[int, int]]]:
    """从边集合里串出**全部**闭合环，按长度降序。

    ⚠️ 不能只取最长那个：兔子翻滚那一帧的两只手/脚在剪影上是**分离的小块**
    （身体收成一团、四肢伸在体外）。只留最大块 ⇒ 剪影上凭空少一块，
    看起来像被切掉一角（首版就是这么错的）。
    """
    remaining = {start: list(ends) for start, ends in edges.items()}
    loops: list[list[tuple[int, int]]] = []
    while any(remaining.values()):
        start = next(point for point, ends in remaining.items() if ends)
        loop = [start]
        current = start
        guard = sum(len(v) for v in remaining.values()) + 8
        while guard > 0:
            guard -= 1
            ends = remaining.get(current)
            if not ends:
                break
            nxt = ends.pop()
            if nxt == start:
                break
            loop.append(nxt)
            current = nxt
        if len(loop) >= 8:
            loops.append(loop)
    loops.sort(key=len, reverse=True)
    return loops


def rdp(points: list[tuple[float, float]], eps: float) -> list[tuple[float, float]]:
    if len(points) < 3:
        return points
    ax, ay = points[0]
    bx, by = points[-1]
    dx, dy = bx - ax, by - ay
    norm = (dx * dx + dy * dy) ** 0.5
    worst = 0.0
    worst_index = 0
    for index in range(1, len(points) - 1):
        px, py = points[index]
        if norm < 1e-9:
            distance = ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
        else:
            distance = abs(dy * px - dx * py + bx * ay - by * ax) / norm
        if distance > worst:
            worst = distance
            worst_index = index
    if worst <= eps:
        return [points[0], points[-1]]
    left = rdp(points[: worst_index + 1], eps)
    right = rdp(points[worst_index:], eps)
    return left[:-1] + right


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    source = Path(sys.argv[1])
    eps = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
    out_path = Path(sys.argv[3]) if len(sys.argv) > 3 else source.with_suffix(".gd.txt")
    upscale = int(sys.argv[4]) if len(sys.argv) > 4 else 3

    mask = load_mask(source, upscale)
    loops = all_loops(boundary_edges(mask))
    if not loops:
        print("TRACE_FAIL no_loop")
        return 1
    # 丢掉极小的噪点（< 最大环的 2%，或 < 24 个像素），但**保留**四肢那种小块。
    biggest = len(loops[0])
    loops = [loop for loop in loops if len(loop) >= max(24, int(biggest * 0.02))]

    # 归一化的基准框用**所有轮廓的并集**：只用最大块会把伸出去的四肢裁到框外。
    all_xs = [p[0] for loop in loops for p in loop]
    all_ys = [p[1] for loop in loops for p in loop]
    span = max(max(all_xs) - min(all_xs), max(all_ys) - min(all_ys))
    cx = (max(all_xs) + min(all_xs)) * 0.5
    cy = (max(all_ys) + min(all_ys)) * 0.5

    polygons: list[list[tuple[float, float]]] = []
    for loop in loops:
        closed = [(float(x), float(y)) for x, y in loop]
        closed.append(closed[0])
        simplified = rdp(closed, eps)[:-1]
        if len(simplified) < 4:
            continue
        polygons.append([((x - cx) / span, (y - cy) / span) for x, y in simplified])
    if not polygons:
        print("TRACE_FAIL over_simplified")
        return 1

    total_points = sum(len(p) for p in polygons)
    lines = ["static var DASH_GLYPH_POLYGONS := ["]
    for polygon in polygons:
        lines.append("\tPackedVector2Array([")
        for x, y in polygon:
            lines.append("\t\tVector2(%.4f, %.4f)," % (x, y))
        lines.append("\t]),")
    lines.append("]")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(
        "TRACE_OK polygons=%d points=%d loop_px=%s -> %s"
        % (len(polygons), total_points, [len(l) for l in loops], out_path)
    )

    # 三个尺寸的预览：22 px 是 HUD 上的实际显示尺寸，判"认不认得出"就看它。
    for size in (22, 32, 64):
        preview = Image.new("L", (size, size), 0)
        draw = ImageDraw.Draw(preview)
        for polygon in polygons:
            draw.polygon([((x + 0.5) * size, (y + 0.5) * size) for x, y in polygon], fill=255)
        preview.resize((size * 6, size * 6), Image.NEAREST).save(
            out_path.with_name("%s_preview%d.png" % (out_path.name.replace(".gd.txt", "").replace(".gd", ""), size))
        )
    print("TRACE_PREVIEW_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
