"""为一个房型组件 prefab 求解「矩形碰撞盒分段」。

工程原则：
  * 碰撞盒略大于几何是无害的（顶多玩家蹭到一点点）；**留空隙才是 bug（会穿模）**。
  * 因此先把几何的 XZ 投影做「开运算」（腐蚀→膨胀）去掉 <2 格的装饰薄片，
    再用贪心最大矩形分解，得到少而实的分段盒。

算法：
  ① 光栅化几何 XZ 投影（CELL，含棱线打点）；
  ② 开运算 r 格 → 掩膜（薄片/细尖消失，主块保留）；
  ③ 贪心最大矩形分解（柱状图单调栈）+ 相邻合并；
  ④ 矩形外扩到「落在该矩形内的几何顶点包围盒」，贴上真实棱线；
  ⑤ 自检：① 几何占用格被覆盖比例 ② 盒内空腔面积 ③ 盒间重叠。

用法：
  python _scratch/segment_collision_boxes.py <prefab 相对路径>... [--cell=0.05] [--open=1] [--min=0.10]
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
NUM = r"(-?\d+(?:\.\d+)?(?:e-?\d+)?)"
EPS = 1e-6


def load_geom(tscn: Path):
    text = tscn.read_text(encoding="utf-8")
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    if not m:
        raise RuntimeError("找不到 GLB 引用")
    glb = ROOT / m.group(1).replace("res://", "")
    verts, tris = glbgeom.parse_glb(glb)
    if not verts or not tris:
        raise RuntimeError("GLB 无三角面")
    return text, glb, verts, tris


def erode(mask, nx, nz, r):
    cur = mask
    for _ in range(r):
        nxt = bytearray(nx * nz)
        for j in range(nz):
            for i in range(nx):
                if not cur[j * nx + i]:
                    continue
                ok = True
                for dj in (-1, 0, 1):
                    jj = j + dj
                    if jj < 0 or jj >= nz:
                        ok = False
                        break
                    rr = jj * nx
                    for di in (-1, 0, 1):
                        ii = i + di
                        if ii < 0 or ii >= nx or not cur[rr + ii]:
                            ok = False
                            break
                    if not ok:
                        break
                if ok:
                    nxt[j * nx + i] = 1
        cur = nxt
    return cur


def max_rect(alive, nx, nz):
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


def greedy(mask, nx, nz, min_cells):
    alive = bytearray(mask)
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
    return rects


def merge(rects):
    rr = [list(r) for r in rects]
    changed = True
    while changed and len(rr) > 1:
        changed = False
        for a in range(len(rr)):
            for b in range(a + 1, len(rr)):
                x, y = rr[a], rr[b]
                if x[0] == y[0] and x[1] == y[1] and (x[3] + 1 >= y[2] and y[2] >= x[3] - 1):
                    y[2], y[3] = min(x[2], y[2]), max(x[3], y[3])
                elif x[2] == y[2] and x[3] == y[3] and (x[1] + 1 >= y[0] and y[0] >= x[1] - 1):
                    y[0], y[1] = min(x[0], y[0]), max(x[1], y[1])
                else:
                    continue
                rr.pop(a)
                changed = True
                break
            if changed:
                break
    return rr


def solve(tscn: Path, cell=0.05, open_r=1, min_area=0.10):
    text, glb, verts, tris = load_geom(tscn)
    vx = [v[0] for v in verts]
    vy = [v[1] for v in verts]
    vz = [v[2] for v in verts]
    x0, x1, z0, z1 = min(vx), max(vx), min(vz), max(vz)
    y0, y1 = min(vy), max(vy)
    nx = int((x1 - x0) / cell) + 2
    nz = int((z1 - z0) / cell) + 2

    occ = glbgeom.rasterize_xz(verts, tris, x0, z0, nx, nz, cell)
    er = erode(occ, nx, nz, open_r) if open_r else occ
    opened = glbgeom.dilate(er, nx, nz, open_r) if open_r else er

    min_cells = max(1, int(round(min_area / (cell * cell))))
    rects = merge(greedy(opened, nx, nz, min_cells))

    # 外扩到落在矩形内的几何顶点包围盒
    vxi = [int((x - x0) / cell) for x in vx]
    vzi = [int((z - z0) / cell) for z in vz]
    segs = []
    for i0, i1, j0, j1 in rects:
        sl, sh = x0 + i0 * cell, x0 + (i1 + 1) * cell
        zl, zh = z0 + j0 * cell, z0 + (j1 + 1) * cell
        sel = [k for k in range(len(vx)) if i0 <= vxi[k] <= i1 and j0 <= vzi[k] <= j1]
        if sel:
            sl = min(sl, min(vx[k] for k in sel))
            sh = max(sh, max(vx[k] for k in sel))
            zl = min(zl, min(vz[k] for k in sel))
            zh = max(zh, max(vz[k] for k in sel))
        segs.append((round(sl, 4), round(sh, 4), round(zl, 4), round(zh, 4)))
    segs = [s for s in segs if s[1] - s[0] > 1e-6 and s[3] - s[2] > 1e-6]
    segs.sort(key=lambda s: (-(s[1] - s[0]) * (s[3] - s[2]), s[2]))
    return {"text": text, "glb": glb, "verts": verts, "tris": tris,
            "aabb": (x0, x1, y0, y1, z0, z1), "segs": segs, "occ": occ,
            "grid": (nx, nz, x0, z0, cell), "n_occ": sum(occ), "opened": sum(opened)}


def verify(sol, tol_cells=4):
    verts, tris, segs = sol["verts"], sol["tris"], sol["segs"]

    def inside(px, pz, pad=1e-6):
        for sl, sh, zl, zh in segs:
            if sl - pad <= px <= sh + pad and zl - pad <= pz <= zh + pad:
                return True
        return False

    nx, nz, x0, z0, cell = sol["grid"]
    occ = sol["occ"]
    grown = glbgeom.dilate(occ, nx, nz, tol_cells)

    uncov = sum(1 for j in range(nz) for i in range(nx)
                if occ[j * nx + i] and not inside(x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell))
    out_tris = 0
    for a, b, c in tris:
        cx = (verts[a][0] + verts[b][0] + verts[c][0]) / 3.0
        cz = (verts[a][2] + verts[b][2] + verts[c][2]) / 3.0
        if not inside(cx, cz):
            out_tris += 1

    # 盒内空腔（距几何超过 tol_cells 格）
    cav = tot = 0
    for j in range(nz):
        for i in range(nx):
            if not grown[j * nx + i]:
                continue  # 只检查远离几何的点
            if inside(x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell):
                tot += 1
    for j in range(nz):
        for i in range(nx):
            cx, cz = x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell
            if inside(cx, cz) and not occ[j * nx + i] and not grown[j * nx + i]:
                cav += 1
    ov = []
    for i in range(len(segs)):
        for j in range(i + 1, len(segs)):
            a_, b_ = segs[i], segs[j]
            ox = min(a_[1], b_[1]) - max(a_[0], b_[0])
            oz = min(a_[3], b_[3]) - max(a_[2], b_[2])
            if ox > 1e-6 and oz > 1e-6:
                ov.append((i + 1, j + 1, round(ox, 4), round(oz, 4)))
    return {"uncovered_cells": uncov, "uncovered_m2": uncov * cell * cell,
            "uncovered_pct": 100.0 * uncov / max(1, sol["n_occ"]),
            "out_tris": out_tris, "n_tris": len(tris),
            "cavity_m2": cav * cell * cell, "overlaps": ov}


def report(tscn, sol, v, tol_cells=4):
    x0, x1, y0, y1, z0, z1 = sol["aabb"]
    segs = sol["segs"]
    tot = sum((s[1] - s[0]) * (s[3] - s[2]) for s in segs)
    print("prefab  %s" % tscn.relative_to(ROOT).as_posix())
    print("AABB    x[%.4f, %.4f] y[%.4f, %.4f] z[%.4f, %.4f]  三角面 %d  占用 %.2f m^2"
          % (x0, x1, y0, y1, z0, z1, len(sol["tris"]), sol["n_occ"] * sol["grid"][4] ** 2))
    print("分段    %d 盒，足印 %.2f m^2（AABB %.2f → 削掉 %.2f m^2）"
          % (len(segs), tot, (x1 - x0) * (z1 - z0), (x1 - x0) * (z1 - z0) - tot))
    for k, (sl, sh, zl, zh) in enumerate(segs, 1):
        print("  %-2d x[%9.4f, %9.4f] z[%9.4f, %9.4f]  → size = Vector3(%g, %g, %g)  position = Vector3(%g, %g, %g)"
              % (k, sl, sh, zl, zh, round(sh - sl, 4), round(y1 - y0, 4), round(zh - zl, 4),
                 round((sl + sh) / 2, 4), round((y0 + y1) / 2, 4), round((zl + zh) / 2, 4)))
    print("  自检  未覆盖格 %d (%.3f m^2, %.2f%%)  重心越界 %d/%d  空腔 %.3f m^2  重叠 %s"
          % (v["uncovered_cells"], v["uncovered_m2"], v["uncovered_pct"],
             v["out_tris"], v["n_tris"], v["cavity_m2"], v["overlaps"] or "无"))
    print()


if __name__ == "__main__":
    opts = {"cell": 0.05, "open_r": 1, "min_area": 0.10}
    args = []
    for a in sys.argv[1:]:
        if a.startswith("--cell="):
            opts["cell"] = float(a.split("=")[1])
        elif a.startswith("--open="):
            opts["open_r"] = int(a.split("=")[1])
        elif a.startswith("--min="):
            opts["min_area"] = float(a.split("=")[1])
        else:
            args.append(a)
    for rel in args:
        tscn = ROOT / rel
        sol = solve(tscn, **opts)
        report(tscn, sol, verify(sol), 4)
