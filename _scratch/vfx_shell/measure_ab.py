"""复量真渲染图：确认 0.8 弹壳在画面里是「单一连通块」而非裂成两段。

判据（外部真源，与被测脚本无关）：
  橙色像素 = R-B>40 且 R>90（弹壳基色 0.92,0.56,0.16）。
  连通块数量：取像素群在竖直方向的「行程段数」（连续 y 段）。
    弹壳是竖直的短柱 + 上下两件紧贴 ⇒ 整体应只有 1 段连续行程。
    裂开（壳体缩了而底缘/底火不动）⇒ 中间出现空隙 ⇒ ≥2 段。
"""
import sys
from PIL import Image

img = Image.open(r"I:\工作项目\shellstrom2\ShellStorm2\outputs\verification\shell_casing_size_ab.png").convert("RGB")
w, h = img.size
px = img.load()

# 左右两半：A(0.8) 在左侧，B(1.0) 在右侧（探针 center_px 已证实 x≈241 / 1039）
def orange_mask(x0, x1):
    cols = {}
    for x in range(x0, x1):
        for y in range(h):
            r, g, b = px[x, y]
            if r - b > 40 and r > 90:
                cols.setdefault(x, []).append(y)
    return cols

def report(label, x0, x1):
    cols = orange_mask(x0, x1)
    if not cols:
        print(f"{label}: NO_ORANGE")
        return
    xs = sorted(cols)
    ys_all = [y for v in cols.values() for y in v]
    y_lo, y_hi = min(ys_all), max(ys_all)
    # 竖直行程段数：逐 x 列取该列 y 的连续段，合并全图后的「最大连续覆盖」
    covered = set(ys_all)
    runs = 0
    prev = False
    for y in range(y_lo, y_hi + 1):
        here = y in covered
        if here and not prev:
            runs += 1
        prev = here
    span = y_hi - y_lo + 1
    print(f"{label}: px={len(ys_all)} x=[{xs[0]}..{xs[-1]}] y=[{y_lo}..{y_hi}] "
          f"v_span={span} v_runs={runs} 宽度={xs[-1]-xs[0]+1}")

report("A(0.8)", 0, w // 2)
report("B(1.0)", w // 2, w)

# 高度比复算（用竖直外接跨度）
def vspan(x0, x1):
    ys = [y for x in range(x0, x1) for y in range(h)
          if (lambda p: p[0] - p[2] > 40 and p[0] > 90)(px[x, y])]
    return (max(ys) - min(ys) + 1) if ys else 0

sa, sb = vspan(0, w // 2), vspan(w // 2, w)
if sb:
    print(f"竖直跨度比 A/B = {sa}/{sb} = {sa/sb:.4f}（期望 ~0.80）")
