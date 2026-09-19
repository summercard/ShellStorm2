"""门墙「双面」到底是**镜像**还是**同一块**的画面对拍。

v005 的做法是把装饰面绕基准面镜像一份到背面（不是旋转 180° 复制），所以从
两侧看到的应该是彼此的**左右翻转**。本脚本把走廊侧图水平翻转后与房内侧图比，
若翻转后差异显著小于未翻转，即坐实「镜像」，而不是「两面各自独立画了一遍」。

只算中央 3/4 区域，与 scripts/png_diff.py 口径一致。
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
from png_diff import read_png  # noqa: E402


def region_diff(w, h, ch, a, b, flip):
    x0, x1 = int(w * 0.12), int(w * 0.88)
    y0, y1 = int(h * 0.10), int(h * 0.90)
    total = 0
    diff_pixels = 0
    samples = 0
    for y in range(y0, y1, 2):
        row = y * w * ch
        for x in range(x0, x1, 2):
            bx = (w - 1 - x) if flip else x
            i = row + x * ch
            j = row + bx * ch
            d = abs(a[i] - b[j]) + abs(a[i + 1] - b[j + 1]) + abs(a[i + 2] - b[j + 2])
            total += d
            samples += 1
            if d > 12:
                diff_pixels += 1
    return total / max(samples, 1) / 3.0, 100.0 * diff_pixels / max(samples, 1), samples


def main():
    a_path, b_path = sys.argv[1], sys.argv[2]
    wa, ha, ca, a = read_png(a_path)
    wb, hb, cb, b = read_png(b_path)
    assert (wa, ha, ca) == (wb, hb, cb), "尺寸/通道不同"
    print("A(房内侧) = %s" % os.path.basename(a_path))
    print("B(走廊侧) = %s" % os.path.basename(b_path))
    for flip in (False, True):
        mean, pct, samples = region_diff(wa, ha, ca, a, b, flip)
        print("  B %s -> 平均通道差 %.2f/255，明显不同(d>12) 占比 %.1f%%（%d 点）" % (
            "水平翻转后" if flip else "原样    ", mean, pct, samples))


if __name__ == "__main__":
    main()
