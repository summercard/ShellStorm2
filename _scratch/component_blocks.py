"""只读：把 prefab 几何按「实物件」与「XZ 连通块」两个视角摊开，并给出每块的 **y 区间**。

为什么要看 y 区间：
  * `safe_box_proxy` 的目标是「挡住玩家该被挡的地方」。玩家高度带 [0, PLAYER_TOP]。
  * 只在 2.9 m 高处的一条自发光灯带，XZ 投影横跨整面墙，但它**不需要碰撞**。
  * 只看 XZ 投影会把这种装饰当成必须覆盖的实体，于是永远「漏覆盖」。

输出三节：
  ① 件级：每个 GLB 节点/primitive 的 三角面数 / XZ bbox / y 区间 / 自身 XZ 占用面积
  ② 块级：整体 XZ 占用按 8 连通切块，每块的 x/z bbox + y 区间 + 是否触碰玩家高度带
  ③ 结论：真正需要碰撞的「实体块」清单（触碰玩家高度带、且面积 > MIN）

用法：python _scratch/component_blocks.py <prefab 相对路径> [CELL=0.05] [PLAYER_TOP=2.2] [MIN_M2=0.05]
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
    top = float(sys.argv[3]) if len(sys.argv) > 3 else 2.2
    min_m2 = float(sys.argv[4]) if len(sys.argv) > 4 else 0.05

    tscn = ROOT / rel
    text = tscn.read_text(encoding="utf-8")
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")
    parts = glbgeom.parse_glb_parts(glb)

    verts, tris = [], []
    for _, v, t in parts:
        base = len(verts)
        verts.extend(v)
        tris.extend((a + base, b + base, c + base) for a, b, c in t)
    if not verts:
        print("GLB 无几何")
        return
    vx = [v[0] for v in verts]
    vy = [v[1] for v in verts]
    vz = [v[2] for v in verts]
    x0, x1, z0, z1 = min(vx), max(vx), min(vz), max(vz)
    y0, y1 = min(vy), max(vy)
    nx = int((x1 - x0) / cell) + 2
    nz = int((z1 - z0) / cell) + 2

    print("prefab %s" % rel)
    print("GLB    %s" % glb.name)
    print("AABB   x[%.4f, %.4f] y[%.4f, %.4f] z[%.4f, %.4f]   三角面 %d"
          % (x0, x1, y0, y1, z0, z1, len(tris)))
    print("参数   CELL=%.2f m  PLAYER_TOP=%.2f m  MIN_M2=%.2f\n" % (cell, top, min_m2))

    print("① 件级")
    for label, pv, pt in parts:
        if not pv:
            continue
        pxs = [q[0] for q in pv]
        pys = [q[1] for q in pv]
        pzs = [q[2] for q in pv]
        occ = glbgeom.rasterize_xz(pv, pt, x0, z0, nx, nz, cell) if pt else bytearray(nx * nz)
        hit = "是" if min(pys) <= top else "否"
        print("  %s" % label)
        print("      tris=%-6d x[%9.4f, %9.4f] z[%9.4f, %9.4f] y[%7.4f, %7.4f]  自身占用 %8.3f m^2  触及玩家带=%s"
              % (len(pt), min(pxs), max(pxs), min(pzs), max(pzs), min(pys), max(pys),
                 sum(occ) * cell * cell, hit))
    print()

    miny = [1e9] * (nx * nz)
    maxy = [-1e9] * (nx * nz)
    occ = glbgeom.rasterize_xz_band(verts, tris, x0, z0, nx, nz, cell, yacc=(miny, maxy))
    cells_list = glbgeom.components8(occ, nx, nz)

    blocks = []
    for cells in cells_list:
        ia = min(c % nx for c in cells)
        ib = max(c % nx for c in cells)
        ja = min(c // nx for c in cells)
        jb = max(c // nx for c in cells)
        by0 = min(miny[c] for c in cells)
        by1 = max(maxy[c] for c in cells)
        # 块内几何顶点的**精确**包围盒（格矩形只作兜底：格边界会把盒多撑一格 = 5 cm）
        cellset = set(cells)
        sl, sh = x0 + ia * cell, x0 + (ib + 1) * cell
        zl, zh = z0 + ja * cell, z0 + (jb + 1) * cell
        sel = [k for k in range(len(vx))
               if (int((vz[k] - z0) / cell) * nx + int((vx[k] - x0) / cell)) in cellset]
        if sel:
            sl = min(vx[k] for k in sel)
            sh = max(vx[k] for k in sel)
            zl = min(vz[k] for k in sel)
            zh = max(vz[k] for k in sel)
            by0 = min(vy[k] for k in sel)
            by1 = max(vy[k] for k in sel)
        blocks.append({"x": (sl, sh), "z": (zl, zh), "y": (by0, by1), "n": len(cells),
                       "area": (sh - sl) * (zh - zl), "touch": by0 <= top})

    print("② 块级（XZ 连通分量）")
    print("  %-3s %10s %10s %10s %10s %9s %9s %10s %6s" %
          ("#", "x_lo", "x_hi", "z_lo", "z_hi", "y_lo", "y_hi", "足印", "触玩家带"))
    for k, b in enumerate(blocks, 1):
        print("  %-3d %10.4f %10.4f %10.4f %10.4f %9.4f %9.4f %10.3f %6s"
              % (k, b["x"][0], b["x"][1], b["z"][0], b["z"][1],
                 b["y"][0], b["y"][1], b["area"], "是" if b["touch"] else "否"))
    print()

    need = [b for b in blocks if b["touch"] and b["area"] >= min_m2]
    skip = [b for b in blocks if not (b["touch"] and b["area"] >= min_m2)]
    print("③ 结论")
    print("  需要碰撞的块 %d 个，合计足印 %.3f m^2（原整块 AABB %.3f m^2）"
          % (len(need), sum(b["area"] for b in need), (x1 - x0) * (z1 - z0)))
    for b in need:
        print("    x[%9.4f, %9.4f] z[%9.4f, %9.4f] y[%7.4f, %7.4f]   size=(%g, %g, %g) pos=(%g, %g, %g)"
              % (b["x"][0], b["x"][1], b["z"][0], b["z"][1], b["y"][0], b["y"][1],
                 round(b["x"][1] - b["x"][0], 4), round(b["y"][1] - b["y"][0], 4), round(b["z"][1] - b["z"][0], 4),
                 round((b["x"][0] + b["x"][1]) / 2, 4), round((b["y"][0] + b["y"][1]) / 2, 4),
                 round((b["z"][0] + b["z"][1]) / 2, 4)))
    print("  判定为「装饰/高处，不做碰撞」的块 %d 个，合计 %.3f m^2：" % (len(skip), sum(b["area"] for b in skip)))
    for b in skip:
        why = "高处(y>%.2f)" % top if not b["touch"] else "过小(<%.2f m^2)" % min_m2
        print("    x[%9.4f, %9.4f] z[%9.4f, %9.4f] y[%7.4f, %7.4f] %.3f m^2  ← %s"
              % (b["x"][0], b["x"][1], b["z"][0], b["z"][1], b["y"][0], b["y"][1], b["area"], why))


if __name__ == "__main__":
    main()
