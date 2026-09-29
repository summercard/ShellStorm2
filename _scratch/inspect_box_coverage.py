"""只读诊断：把「几何占用」与「声明的碰撞盒」叠成 ASCII 图，直接看出漏覆盖/空阻挡在哪。

图例（每个字符代表 AGG 格 = AGG*CELL 米）：
  #  几何占用 且 在盒内          → 正常
  o  几何占用 但 不在盒内        → **漏覆盖**（表面露在碰撞外，能穿过去）
  ,  在盒内 且 靠近几何(<TOL)    → 正常的「盒略大于几何」
  ' '在盒内 但 远离几何(>TOL)    → **空阻挡**（玩家被无故挡住）
  .  既无几何也不在盒内          → 空白

用法：python _scratch/inspect_box_coverage.py <prefab 相对路径> [CELL=0.05] [AGG=3] [TOL=0.30] [BAND_TOP=2.2]
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402
from verify_box_segments import boxes_from_tscn  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main():
    rel = sys.argv[1]
    cell = float(sys.argv[2]) if len(sys.argv) > 2 else 0.05
    agg = int(sys.argv[3]) if len(sys.argv) > 3 else 3
    tol = float(sys.argv[4]) if len(sys.argv) > 4 else 0.30
    band_top = float(sys.argv[5]) if len(sys.argv) > 5 else 2.2

    tscn = ROOT / rel
    text = tscn.read_text(encoding="utf-8")
    boxes = boxes_from_tscn(text)
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")
    verts, tris = glbgeom.parse_glb(glb)

    rel_ids = [t for t in range(len(tris))
               if min(verts[tris[t][k]][1] for k in range(3)) <= band_top]
    print("prefab %s" % rel)
    print("几何 %d 三角面，其中触及玩家带(y<=%.2f)的 %d 面参与判定（排除 %d 面 = 高处装饰）"
          % (len(tris), band_top, len(rel_ids), len(tris) - len(rel_ids)))

    gx = [verts[i][0] for t in rel_ids for i in tris[t]]
    gz = [verts[i][2] for t in rel_ids for i in tris[t]]
    x0, x1, z0, z1 = min(gx), max(gx), min(gz), max(gz)
    nx = int((x1 - x0) / cell) + 2
    nz = int((z1 - z0) / cell) + 2

    def in_xz(x, z, pad=1e-6):
        for _, lo, hi in boxes:
            if lo[0] - pad <= x <= hi[0] + pad and lo[2] - pad <= z <= hi[2] + pad:
                return True
        return False

    occ = glbgeom.rasterize_xz_band(verts, tris, x0, z0, nx, nz, cell, ids=rel_ids)
    grown = glbgeom.dilate(occ, nx, nz, int(round(tol / cell)))

    uncov = bytearray(nx * nz)
    cav = bytearray(nx * nz)
    for j in range(nz):
        for i in range(nx):
            k = j * nx + i
            inside = in_xz(x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell)
            if occ[k] and not inside:
                uncov[k] = 1
            if inside and not occ[k] and not grown[k]:
                cav[k] = 1

    print("\n声明 %d 个碰撞盒：" % len(boxes))
    for n, lo, hi in boxes:
        print("   %-18s x[%9.4f,%9.4f] z[%9.4f,%9.4f]" % (n, lo[0], hi[0], lo[2], hi[2]))

    for tag, mask in (("漏覆盖", uncov), ("空阻挡", cav)):
        blobs = glbgeom.components8(mask, nx, nz)
        blobs.sort(key=len, reverse=True)
        print("\n%s 块 %d 个，合计 %.3f m^2" % (tag, len(blobs), sum(len(c) for c in blobs) * cell * cell))
        for c in blobs[:8]:
            ia = min(q % nx for q in c)
            ib = max(q % nx for q in c)
            ja = min(q // nx for q in c)
            jb = max(q // nx for q in c)
            print("    %6.3f m^2  x[%8.4f,%8.4f] z[%8.4f,%8.4f]"
                  % (len(c) * cell * cell, x0 + ia * cell, x0 + (ib + 1) * cell,
                     z0 + ja * cell, z0 + (jb + 1) * cell))

    print("\n叠图（每格 %.2f m）" % (cell * agg))
    na_x = (nx + agg - 1) // agg
    na_z = (nz + agg - 1) // agg
    grid = [["."] * na_x for _ in range(na_z)]
    for j in range(nz):
        for i in range(nx):
            k = j * nx + i
            if occ[k]:
                ch = "#" if in_xz(x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell) else "o"
            else:
                ch = " " if (cav[k]) else ("," if in_xz(x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell) else ".")
            gi, gj = i // agg, j // agg
            prev = grid[gj][gi]
            # 优先级：o > # > 空格 > , > .
            rank = {"o": 4, "#": 3, " ": 2, ",": 1, ".": 0}
            if rank[ch] > rank[prev]:
                grid[gj][gi] = ch
    for gj in range(na_z - 1, -1, -1):
        print("  z=%8.3f |%s|" % (z0 + gj * agg * cell, "".join(grid[gj])))
    print("  %s x: %.3f .. %.3f" % (" " * 12, x0, x1))


if __name__ == "__main__":
    main()
