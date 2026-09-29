"""只读分析：把一个 prefab 的几何按某个轴切条，看它到底长什么样（占用宽度 / 高度区间 / 三角面数）。

用法：python _scratch/inspect_geometry_profile.py <prefab 相对路径> [axis=x|z] [bins=60]
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CELL = 0.05


def main():
    rel = sys.argv[1]
    axis = sys.argv[2] if len(sys.argv) > 2 else "z"
    bins = int(sys.argv[3]) if len(sys.argv) > 3 else 60
    tscn = ROOT / rel
    text = tscn.read_text(encoding="utf-8")
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")
    verts, tris = glbgeom.parse_glb(glb)
    print("GLB %s" % glb.relative_to(ROOT).as_posix())
    print("mesh 实例数解析后顶点 %d 三角面 %d" % (len(verts), len(tris)))

    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    print("AABB x[%.4f, %.4f] y[%.4f, %.4f] z[%.4f, %.4f]" % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))

    lo_a, hi_a = (min(zs), max(zs)) if axis == "z" else (min(xs), max(xs))
    other = "x" if axis == "z" else "z"
    step = (hi_a - lo_a) / bins
    print("\n沿 %s 轴切 %d 段（每段 %.3f m）：" % (axis, bins, step))
    print("%-6s %-18s %8s %8s %9s %9s %7s"
          % ("段", "%s 区间" % axis, "投影宽", "点数", "y_lo", "y_hi", "三角面"))

    # 三角面归属：按重心
    tri_of = []
    for a, b, c in tris:
        cz = (verts[a][2] + verts[b][2] + verts[c][2]) / 3.0
        cx = (verts[a][0] + verts[b][0] + verts[c][0]) / 3.0
        tri_of.append(cz if axis == "z" else cx)

    for k in range(bins):
        a0 = lo_a + k * step
        a1 = a0 + step
        sel_v = [v for v in verts if a0 <= (v[2] if axis == "z" else v[0]) < a1]
        n_tri = sum(1 for t in tri_of if a0 <= t < a1)
        if not sel_v and n_tri == 0:
            continue
        o_vals = [(v[0] if other == "x" else v[2]) for v in sel_v] or [0.0]
        y_lo = min((v[1] for v in sel_v), default=0.0)
        y_hi = max((v[1] for v in sel_v), default=0.0)
        print("%-6d [%7.3f,%7.3f] %8.3f %8d %9.3f %9.3f %7d"
              % (k, a0, a1, max(o_vals) - min(o_vals), len(sel_v), y_lo, y_hi, n_tri))


if __name__ == "__main__":
    main()
