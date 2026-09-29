"""只读：把 prefab 几何的 XZ 占用画成 ASCII 图，肉眼确认形状。

用法：python _scratch/ascii_xz_map.py <prefab 相对路径> [cell_m] [axis_x|axis_z]
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main():
    rel = sys.argv[1]
    cell = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    text = (ROOT / rel).read_text(encoding="utf-8")
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")
    verts, tris = glbgeom.parse_glb(glb)
    xs = [v[0] for v in verts]
    zs = [v[2] for v in verts]
    x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
    print("%s" % glb.name)
    print("AABB x[%.3f, %.3f] z[%.3f, %.3f]  cell=%.2fm" % (x0, x1, z0, z1, cell))
    nx = int((x1 - x0) / cell) + 2
    nz = int((z1 - z0) / cell) + 2
    occ = glbgeom.rasterize_xz(verts, tris, x0, z0, nx, nz, cell)
    print("占用 %.3f m^2 / AABB %.3f m^2\n" % (sum(occ) * cell * cell, (x1 - x0) * (z1 - z0)))
    print("    z→ 每行一个 z 带，纵轴为 x（上 = x_max）")
    for j in range(nz - 1, -1, -1):
        row = "".join("#" if occ[j * nx + i] else "." for i in range(nx))
        print("  %7.2f |%s|" % (z0 + j * cell, row))
    hdr = " " * 10
    ticks = []
    for i in range(nx):
        ticks.append("|" if i % 5 == 0 else " ")
    print(hdr + "".join(ticks))
    print(hdr + "x: %.2f .. %.2f  (每 5 格一格标)" % (x0, x1))


if __name__ == "__main__":
    main()
