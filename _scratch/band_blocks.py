"""只读：**只看玩家高度带**的几何占用 → XZ 连通块 → 每块精确包围盒（可直接落成碰撞盒）。

为什么需要本工具（`component_blocks.py` 不够用）：
  * `component_blocks.py` 的块级分析把**全部**几何一起光栅化。一个「高处横梁 + 两端立柱」
    的构件会在 XZ 上连成一个 8 连通块 —— 但玩家只在意 [0, BAND_TOP] 这一带，
    高于该带的横梁不需要碰撞，也不该把两根立柱"焊"成一块。
  * 本工具先用 `ids=` 过滤出**触及高度带**的三角面，再做连通块，于是能正确切出立柱。

输出：
  ① 件级（只统计带内三角面）：每件的带内三角面数 / 带内 XZ bbox / 带内 y 区间
  ② 块级：每块的精确顶点包围盒 + 填充率（占用格 / 包围盒格）+ 建议 size/pos
  ③ 直接可粘贴的 `[sub_resource]` + `[node]` 片段

用法：python _scratch/band_blocks.py <prefab 相对路径> [CELL=0.05] [BAND_TOP=2.2] [MIN_M2=0.05]
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]


def r4(v):
    """压到 0.1 mm 精度，避免 -0.0 与浮点噪声。"""
    q = round(v, 4)
    return 0.0 if q == 0 else q


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

    verts, tris, part_of = [], [], []
    for label, pv, pt in parts:
        base = len(verts)
        verts.extend(pv)
        for t in pt:
            tris.append((t[0] + base, t[1] + base, t[2] + base))
            part_of.append(label)

    print("prefab %s" % rel)
    print("GLB    %s   三角面 %d" % (glb.name, len(tris)))
    print("参数   CELL=%.2f m  BAND_TOP=%.2f m  MIN_M2=%.2f\n" % (cell, top, min_m2))

    # 带内三角面 = 其任一顶点 y <= top
    band_ids = [t for t in range(len(tris))
                if min(verts[tris[t][k]][1] for k in range(3)) <= top]
    print("① 件级（只统计触及高度带的三角面）")
    for label, pv, pt in parts:
        base = None
        ids = [i for i, lab in enumerate(part_of) if lab == label]
        sub = [tris[i] for i in ids]
        vs = sorted({v for t in sub for v in t})
        pxs = [verts[v][0] for v in vs]
        pys = [verts[v][1] for v in vs]
        pzs = [verts[v][2] for v in vs]
        inband = [t for t in sub if min(verts[t[k]][1] for k in range(3)) <= top]
        ibv = sorted({v for t in inband for v in t})
        if ibv:
            ix = [verts[v][0] for v in ibv]
            iy = [verts[v][1] for v in ibv]
            iz = [verts[v][2] for v in ibv]
            ib = "x[%9.4f,%9.4f] z[%9.4f,%9.4f] y[%7.4f,%7.4f]" % (
                min(ix), max(ix), min(iz), max(iz), min(iy), max(iy))
        else:
            ib = "（无）"
        print("  %s" % label)
        print("      全部 tris=%-6d x[%9.4f,%9.4f] z[%9.4f,%9.4f] y[%7.4f,%7.4f]"
              % (len(sub), min(pxs), max(pxs), min(pzs), max(pzs), min(pys), max(pys)))
        print("      带内 tris=%-6d %s" % (len(inband), ib))
    print()

    vx = [v[0] for v in verts]
    vz = [v[2] for v in verts]
    x0, z0 = min(vx), min(vz)
    nx = int((max(vx) - x0) / cell) + 2
    nz = int((max(vz) - z0) / cell) + 2

    miny = [1e9] * (nx * nz)
    maxy = [-1e9] * (nx * nz)
    occ = glbgeom.rasterize_xz_band(verts, tris, x0, z0, nx, nz, cell,
                                    ids=band_ids, yacc=(miny, maxy))
    blocks = glbgeom.components8(occ, nx, nz)

    print("② 块级（只含触及高度带的几何，XZ 8 连通）")
    print("  %-3s %10s %10s %10s %10s %9s %9s %9s %8s %7s"
          % ("#", "x_lo", "x_hi", "z_lo", "z_hi", "y_lo", "y_hi", "足印", "填充率", "触带"))
    info = []
    for k, cells in enumerate(sorted(blocks, key=len, reverse=True), 1):
        cellset = set(cells)
        sel = [i for i in range(len(verts))
               if (int((vz[i] - z0) / cell) * nx + int((vx[i] - x0) / cell)) in cellset]
        sl = min(vx[i] for i in sel)
        sh = max(vx[i] for i in sel)
        zl = min(vz[i] for i in sel)
        zh = max(vz[i] for i in sel)
        ia = min(c % nx for c in cells)
        ib = max(c % nx for c in cells)
        ja = min(c // nx for c in cells)
        jb = max(c // nx for c in cells)
        fill = len(cells) / float((ib - ia + 1) * (jb - ja + 1))
        ylo = min(miny[c] for c in cells if maxy[c] > -1e8)
        yhi = max(maxy[c] for c in cells if maxy[c] > -1e8)
        area = (sh - sl) * (zh - zl)
        info.append(dict(n=k, x=(sl, sh), z=(zl, zh), y=(ylo, yhi), area=area, fill=fill))
        print("  %-3d %10.4f %10.4f %10.4f %10.4f %9.4f %9.4f %9.3f %8.3f %7s"
              % (k, sl, sh, zl, zh, ylo, yhi, area, fill, "是" if ylo <= top else "否"))
    print()

    print("③ 结论 / 建议盒（含 y 用该块几何实际区间；size/pos 按 bottom_center 契约）")
    keep = [b for b in info if b["area"] >= min_m2]
    drop = [b for b in info if b["area"] < min_m2]
    print("  建议 %d 个盒，合计足印 %.3f m^2" % (len(keep), sum(b["area"] for b in keep)))
    for b in keep:
        sx = r4(b["x"][1] - b["x"][0])
        sy = r4(b["y"][1] - b["y"][0])
        sz = r4(b["z"][1] - b["z"][0])
        cx = r4((b["x"][0] + b["x"][1]) / 2)
        cy = r4((b["y"][0] + b["y"][1]) / 2)
        cz = r4((b["z"][0] + b["z"][1]) / 2)
        print("    #%d  size=(%g, %g, %g)  pos=(%g, %g, %g)   填充率 %.3f"
              % (b["n"], sx, sy, sz, cx, cy, cz, b["fill"]))
    if drop:
        print("  过小丢弃 %d 个：" % len(drop))
        for b in drop:
            print("    x[%.4f,%.4f] z[%.4f,%.4f] y[%.4f,%.4f] %.4f m^2"
                  % (b["x"][0], b["x"][1], b["z"][0], b["z"][1], b["y"][0], b["y"][1], b["area"]))


if __name__ == "__main__":
    main()
