"""只读：把 prefab 几何的 XZ 投影按连通分量切成「天然块」，给出每块的精确包围盒。

用途：手工做碰撞盒分段时，先看清几何到底是几个分离的实体块，每块的真实边界在哪。

做法：
  ① 光栅化占用（CELL，含棱线）；
  ② 膨胀 BRIDGE 格合并缝隙，再取 8 连通分量；
  ③ 每块 = 归入该分量的「原始占用格」的外接矩形，再外扩到该矩形内几何顶点的包围盒。

用法：python _scratch/geometry_clusters.py <prefab 相对路径> [CELL] [BRIDGE]
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main():
    rel = sys.argv[1]
    cell = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05
    bridge = int(sys.argv[3]) if len(sys.argv) > 3 else 1

    tscn = ROOT / rel
    text = tscn.read_text(encoding="utf-8")
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")
    verts, tris = glbgeom.parse_glb(glb)
    vx = [v[0] for v in verts]
    vy = [v[1] for v in verts]
    vz = [v[2] for v in verts]
    x0, x1, z0, z1 = min(vx), max(vx), min(vz), max(vz)
    y0, y1 = min(vy), max(vy)
    nx = int((x1 - x0) / cell) + 2
    nz = int((z1 - z0) / cell) + 2

    occ = glbgeom.rasterize_xz(verts, tris, x0, z0, nx, nz, cell)
    grown = glbgeom.dilate(occ, nx, nz, bridge)

    label = [-1] * (nx * nz)
    comps = []
    for j in range(nz):
        for i in range(nx):
            k = j * nx + i
            if not grown[k] or label[k] >= 0:
                continue
            cid = len(comps)
            stack = [k]
            label[k] = cid
            while stack:
                cur = stack.pop()
                ci, cj = cur % nx, cur // nx
                for dj in (-1, 0, 1):
                    jj = cj + dj
                    if jj < 0 or jj >= nz:
                        continue
                    rr = jj * nx
                    for di in (-1, 0, 1):
                        ii = ci + di
                        if 0 <= ii < nx:
                            kk = rr + ii
                            if grown[kk] and label[kk] < 0:
                                label[kk] = cid
                                stack.append(kk)
            # 该分量内的原始占用格
            cells = [q for q in range(nx * nz) if label[q] == cid and occ[q]]
            if not cells:
                continue
            ia = min(c % nx for c in cells)
            ib = max(c % nx for c in cells)
            ja = min(c // nx for c in cells)
            jb = max(c // nx for c in cells)
            comps.append((ia, ib, ja, jb, len(cells)))

    print("GLB  %s" % glb.relative_to(ROOT).as_posix())
    print("AABB x[%.4f, %.4f] y[%.4f, %.4f] z[%.4f, %.4f]  占用 %.2f m^2  分量 %d 个"
          % (x0, x1, y0, y1, z0, z1, sum(occ) * cell * cell, len(comps)))
    print("参数 CELL=%.2f BRIDGE=%d 格（%.2f m）\n" % (cell, bridge, bridge * cell))

    comps.sort(key=lambda c: -(c[1] - c[0] + 1) * (c[3] - c[2] + 1))
    tot = 0.0
    print("  %-3s %9s %9s %9s %9s %10s %8s %8s" % ("#", "x_lo", "x_hi", "z_lo", "z_hi", "尺寸 x×z", "足印", "占用格"))
    for k, (ia, ib, ja, jb, n) in enumerate(comps, 1):
        sl, sh = x0 + ia * cell, x0 + (ib + 1) * cell
        zl, zh = z0 + ja * cell, z0 + (jb + 1) * cell
        sel = [t for t in range(len(vx))
               if ia <= int((vx[t] - x0) / cell) <= ib and ja <= int((vz[t] - z0) / cell) <= jb]
        if sel:
            sl = min(sl, min(vx[t] for t in sel))
            sh = max(sh, max(vx[t] for t in sel))
            zl = min(zl, min(vz[t] for t in sel))
            zh = max(zh, max(vz[t] for t in sel))
        a = (sh - sl) * (zh - zl)
        tot += a
        print("  %-3d %9.4f %9.4f %9.4f %9.4f %4.3f×%5.3f %8.2f %8d"
              % (k, sl, sh, zl, zh, sh - sl, zh - zl, a, n))
    print("\n  合计足印 %.2f m^2（原整块 AABB %.2f m^2，削掉 %.2f m^2）"
          % (tot, (x1 - x0) * (z1 - z0), (x1 - x0) * (z1 - z0) - tot))
    print("  Y 区间 [%.4f, %.4f]，中心 %.4f" % (y0, y1, (y0 + y1) / 2))


if __name__ == "__main__":
    main()
