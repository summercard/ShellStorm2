"""只读：沿轴切片，量出几何的**精确边界轮廓**（顶点级）。

用途：矩形分段盒的边界靠「落在矩形内的顶点包围盒」决定，但亚格级的外伸
（例如 L 形后臂实际比 1.75 m 深 4.5 cm）会被格子吃掉，留下细长漏覆盖带。
本工具直接按顶点给出轮廓，用来把盒边界钉到真实棱线。

只统计「触及玩家高度带」的三角面（min-y <= PLAYER_TOP）。

用法：python _scratch/measure_outline.py <prefab 相对路径> [STEP=0.25] [PLAYER_TOP=2.2]
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main():
    rel = sys.argv[1]
    step = float(sys.argv[2]) if len(sys.argv) > 2 else 0.25
    top = float(sys.argv[3]) if len(sys.argv) > 3 else 2.2

    tscn = ROOT / rel
    text = tscn.read_text(encoding="utf-8")
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")
    verts, tris = glbgeom.parse_glb(glb)

    keep = set()
    for a, b, c in tris:
        if min(verts[a][1], verts[b][1], verts[c][1]) <= top:
            keep.add(a)
            keep.add(b)
            keep.add(c)
    pts = [verts[k] for k in sorted(keep)]
    xs = [p[0] for p in pts]
    zs = [p[2] for p in pts]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    print("prefab %s" % rel)
    print("相关顶点 %d 个（触及 y<=%.2f 的三角面）  x[%.4f, %.4f] z[%.4f, %.4f]"
          % (len(pts), top, x0, x1, z0, z1))
    print("切片 STEP=%.3f m\n" % step)

    print("A) 沿 z 切片 —— 每个 z 带上几何的 x 范围（看 L 形两臂在 z 上的走向）")
    j = 0
    zz = z0
    while zz < z1 - 1e-9:
        sel = [p for p in pts if zz - 1e-9 <= p[2] < zz + step - 1e-9]
        if sel:
            print("  z[%8.4f, %8.4f)  n=%-6d x[%8.4f, %8.4f]  span %7.4f"
                  % (zz, zz + step, len(sel), min(p[0] for p in sel), max(p[0] for p in sel),
                     max(p[0] for p in sel) - min(p[0] for p in sel)))
        zz = round(z0 + (j := j + 1) * step, 6)
    print()

    print("B) 沿 x 切片 —— 每个 x 带上几何的 z 范围（看 L 形两臂在 x 上的走向）")
    i = 0
    xx = x0
    while xx < x1 - 1e-9:
        sel = [p for p in pts if xx - 1e-9 <= p[0] < xx + step - 1e-9]
        if sel:
            print("  x[%8.4f, %8.4f)  n=%-6d z[%8.4f, %8.4f]  span %7.4f"
                  % (xx, xx + step, len(sel), min(p[2] for p in sel), max(p[2] for p in sel),
                     max(p[2] for p in sel) - min(p[2] for p in sel)))
        xx = round(x0 + (i := i + 1) * step, 6)


if __name__ == "__main__":
    main()
