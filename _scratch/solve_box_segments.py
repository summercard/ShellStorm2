"""只读求解：为一个 prefab 的 GLB 几何求「矩形碰撞盒分段」方案，并双向校验。

用法：python _scratch/solve_box_segments.py <prefab 相对路径> [MIN_AREA_M2]
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
NUM = r"(-?\d+(?:\.\d+)?(?:e-?\d+)?)"


def max_rect(alive, nx, nz):
    """柱状图单调栈求当前最大全 1 矩形，返回 (面积格数, i0, i1, j0, j1)。"""
    heights = [0] * nx
    best = None
    for j in range(nz):
        base = j * nx
        for i in range(nx):
            heights[i] = heights[i] + 1 if alive[base + i] else 0
        stack = []
        for i in range(nx + 1):
            h = heights[i] if i < nx else 0
            start = i
            while stack and stack[-1][1] >= h:
                si, sh = stack.pop()
                if sh > 0:
                    area = sh * (i - si)
                    if best is None or area > best[0]:
                        best = (area, si, i - 1, j - sh + 1, j)
                start = si
            stack.append((start, h))
    return best


def decompose(occ, nx, nz, min_cells):
    alive = bytearray(occ)
    rects = []
    while True:
        best = max_rect(alive, nx, nz)
        if best is None or best[0] < min_cells:
            break
        _, i0, i1, j0, j1 = best
        rects.append([i0, i1, j0, j1])
        for j in range(j0, j1 + 1):
            row = j * nx
            for i in range(i0, i1 + 1):
                alive[row + i] = 0
    return rects, sum(alive)


def merge(rects):
    rr = [list(r) for r in rects]
    changed = True
    while changed and len(rr) > 1:
        changed = False
        for a in range(len(rr)):
            for b in range(a + 1, len(rr)):
                x, y = rr[a], rr[b]
                if x[0] == y[0] and x[1] == y[1] and (x[3] + 1 == y[2] or y[3] + 1 == x[2]):
                    y[2], y[3] = min(x[2], y[2]), max(x[3], y[3])
                elif x[2] == y[2] and x[3] == y[3] and (x[1] + 1 == y[0] or y[1] + 1 == x[0]):
                    y[0], y[1] = min(x[0], y[0]), max(x[1], y[1])
                else:
                    continue
                rr.pop(a)
                changed = True
                break
            if changed:
                break
    return rr


def main():
    rel = sys.argv[1]
    min_area = float(sys.argv[2]) if len(sys.argv) > 2 else 0.20
    tscn = ROOT / rel
    text = tscn.read_text(encoding="utf-8")
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")
    verts, tris = glbgeom.parse_glb(glb)
    gx = [v[0] for v in verts]
    gy = [v[1] for v in verts]
    gz = [v[2] for v in verts]
    x0, x1, z0, z1 = min(gx), max(gx), min(gz), max(gz)
    y0, y1 = min(gy), max(gy)
    print("GLB      %s" % glb.relative_to(ROOT).as_posix())
    print("几何 AABB x[%.4f, %.4f] y[%.4f, %.4f] z[%.4f, %.4f]  三角面 %d"
          % (x0, x1, y0, y1, z0, z1, len(tris)))

    CELL = 0.05 if (x1 - x0) * (z1 - z0) <= 100 else 0.10
    nx = int((x1 - x0) / CELL) + 2
    nz = int((z1 - z0) / CELL) + 2
    occ = glbgeom.rasterize_xz(verts, tris, x0, z0, nx, nz, CELL)
    print("栅格 %d x %d（%.2f m），几何投影 %.2f m^2，AABB %.2f m^2"
          % (nx, nz, CELL, sum(occ) * CELL * CELL, (x1 - x0) * (z1 - z0)))

    min_cells = max(1, int(min_area / (CELL * CELL)))
    rects, leftover = decompose(occ, nx, nz, min_cells)
    rects = merge(rects)
    print("\n贪心分解 %d 个矩形（合并后），未覆盖 %d 格 = %.3f m^2"
          % (len(rects), leftover, leftover * CELL * CELL))

    segs = sorted(
        [[x0 + r[0] * CELL, x0 + (r[1] + 1) * CELL, z0 + r[2] * CELL, z0 + (r[3] + 1) * CELL] for r in rects],
        key=lambda s: (-(s[1] - s[0]) * (s[3] - s[2])),
    )

    print("\n分段方案（GLB/Godot 局部坐标）")
    print("%-3s %9s %9s %9s %9s %10s %8s" % ("#", "x_lo", "x_hi", "z_lo", "z_hi", "尺寸", "面积"))
    tot = 0.0
    for k, (lx, hx, lz, hz) in enumerate(segs, 1):
        a = (hx - lx) * (hz - lz)
        tot += a
        print("%-3d %9.3f %9.3f %9.3f %9.3f %4.3f x %4.3f %7.2f"
              % (k, lx, hx, lz, hz, hx - lx, hz - lz, a))
    print("合计足印 %.2f m^2（原整块 AABB %.2f m^2，省掉 %.2f m^2）"
          % (tot, (x1 - x0) * (z1 - z0), (x1 - x0) * (z1 - z0) - tot))

    print("\n可直接写入 tscn 的节点（Y 取 [%.4f, %.4f]）：" % (y0, y1))
    for k, (lx, hx, lz, hz) in enumerate(segs, 1):
        cx, cz = (lx + hx) / 2, (lz + hz) / 2
        cy = (y0 + y1) / 2
        print("  size%s = Vector3(%g, %g, %g)   position = Vector3(%g, %g, %g)"
              % (k, round(hx - lx, 4), round(y1 - y0, 4), round(hz - lz, 4),
                 round(cx, 4), round(cy, 4), round(cz, 4)))

    # —— 双向校验 ——
    def in_segs(px, pz, tol=0.0):
        for lx, hx, lz, hz in segs:
            if lx - tol <= px <= hx + tol and lz - tol <= pz <= hz + tol:
                return True
        return False

    out_tris = 0
    for a, b, c in tris:
        cx = (verts[a][0] + verts[b][0] + verts[c][0]) / 3.0
        cz = (verts[a][2] + verts[b][2] + verts[c][2]) / 3.0
        if not in_segs(cx, cz, 1e-6):
            out_tris += 1
    print("\n① 三角面重心落在分段外：%d / %d" % (out_tris, len(tris)))

    step = CELL
    empty = tot_s = 0
    for lx, hx, lz, hz in segs:
        px = lx + step / 2
        while px < hx:
            pz = lz + step / 2
            while pz < hz:
                tot_s += 1
                ci = int((px - x0) / CELL)
                cj = int((pz - z0) / CELL)
                if not (0 <= ci < nx and 0 <= cj < nz) or not occ[cj * nx + ci]:
                    empty += 1
                pz += step
            px += step
    print("② 分段内落在几何投影之外的采样格：%d / %d = %.2f m^2"
          % (empty, tot_s, empty * CELL * CELL))

    ov = []
    for i in range(len(segs)):
        for j in range(i + 1, len(segs)):
            a_, b_ = segs[i], segs[j]
            ox = min(a_[1], b_[1]) - max(a_[0], b_[0])
            oz = min(a_[3], b_[3]) - max(a_[2], b_[2])
            if ox > 1e-6 and oz > 1e-6:
                ov.append((i + 1, j + 1, round(ox, 3), round(oz, 3)))
    print("③ 分段两两重叠：%s" % (ov if ov else "无"))


if __name__ == "__main__":
    main()
