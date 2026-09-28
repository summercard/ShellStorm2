"""只读校验：prefab 里声明的碰撞盒 vs GLB 几何，双向判据。

判据（全部只看「触及玩家高度带」的几何，见下）：
  ① 无穿模：相关三角面的重心必须落在盒并集内（重心在外 = 有表面露在碰撞外，能被穿过去）。
  ② 无空阻挡：盒并集内、离相关几何 XZ 投影 > EMPTY_TOL 的成片区域（面积 + 最大连通块）。
  ③ 无重叠：盒与盒不该互相重叠。
  ④ 覆盖率：以 CELL 栅格统计相关几何占用格被盒覆盖的比例（格中心容差 CELL/2，见下）。

两条容易搞错的口径：
  * **只算玩家高度带**：`--band-top`（默认 2.2 m）。只在 2.9 m 高处的一条自发光灯带
    XZ 横跨整面墙，但它不需要碰撞；把它算成「必须覆盖」会永远判 FAIL。
  * **格中心容差 CELL/2**：几何面恰好落在盒边界（如 z=-1.875）时，栅格化会把这条边
    记进隔壁那一格，而那一格中心已在盒外 —— 纯属 5 cm 量化伪影，不是真漏。因此
    覆盖判据给半个格容差（等价于真漏必须 >= 2 格 = 10 cm 才报）。

用法：
  python _scratch/verify_box_segments.py <prefab 相对路径>... [--empty-tol=0.30] [--band-top=2.2] [--all-band]
"""
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402

def _find_root():
    env = os.environ.get("SS2_ROOT")
    if env:
        return Path(env).resolve()
    p = Path.cwd().resolve()
    for cand in [p, *p.parents]:
        if (cand / "project.godot").exists():
            return cand
    return p


ROOT = _find_root()
NUM = r"(-?\d+(?:\.\d+)?(?:e-?\d+)?)"
CELL = 0.05
# 几何面与盒面**重合**是常见情形（例如竖直面正好贴在盒的某一侧）。此时重心与盒边界的
# 浮点比较会在 1e-16 量级上翻卦，故给 0.1 mm 的边界容差 —— 远小于任何真实穿模。
EDGE_EPS = 1e-4


def boxes_from_tscn(text):
    sizes = {
        m.group(1): [float(v) for v in re.findall(NUM, m.group(2))]
        for m in re.finditer(
            r'\[sub_resource type="BoxShape3D" id="([^"]+)"\]\s*\r?\nsize = Vector3\(([^)]*)\)', text)
    }
    out = []
    for m in re.finditer(
        r'\[node name="([^"]+)" type="CollisionShape3D"[^\]]*\]\s*\r?\n((?:[^\[]*\r?\n)*?)(?=\[|$)', text):
        name, body = m.group(1), m.group(2)
        pm = re.search(r"position = Vector3\(([^)]*)\)", body)
        sm = re.search(r'shape = SubResource\("([^"]+)"\)', body)
        if not sm or sm.group(1) not in sizes:
            continue
        pos = [float(v) for v in re.findall(NUM, pm.group(1))] if pm else [0.0, 0.0, 0.0]
        size = sizes[sm.group(1)]
        if len(pos) < 3 or len(size) < 3:
            continue
        out.append((name, [pos[i] - size[i] / 2 for i in range(3)], [pos[i] + size[i] / 2 for i in range(3)]))
    return out


def verify(rel, empty_tol, band_top, quiet=False):
    tscn = ROOT / rel
    text = tscn.read_text(encoding="utf-8")
    boxes = boxes_from_tscn(text)
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")
    verts, tris = glbgeom.parse_glb(glb)

    if band_top is None:
        rel_ids = list(range(len(tris)))
    else:
        rel_ids = [t for t in range(len(tris))
                   if min(verts[tris[t][k]][1] for k in range(3)) <= band_top]

    gx = [verts[i][0] for t in rel_ids for i in tris[t]]
    gy = [verts[i][1] for t in rel_ids for i in tris[t]]
    gz = [verts[i][2] for t in rel_ids for i in tris[t]]
    aabb = (min(gx), max(gx), min(gy), max(gy), min(gz), max(gz))

    if not quiet:
        print("prefab  %s" % rel)
        print("几何    三角面 %d，其中触及玩家带(y<=%s)的 %d 面参与判定（排除 %d 面 = 高处装饰）"
              % (len(tris), "全部" if band_top is None else "%.2f m" % band_top,
                 len(rel_ids), len(tris) - len(rel_ids)))
        print("相关包围 x[%.4f, %.4f] y[%.4f, %.4f] z[%.4f, %.4f]"
              % (aabb[0], aabb[1], aabb[2], aabb[3], aabb[4], aabb[5]))
        print("声明 %d 个碰撞盒：" % len(boxes))
        for n, lo, hi in boxes:
            print("   %-18s x[%9.4f,%9.4f] y[%7.4f,%7.4f] z[%9.4f,%9.4f]  size=(%g, %g, %g)"
                  % (n, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2],
                     hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))

    def in_xz(x, z, pad=0.0):
        p = pad + 1e-6  # 浮点边界：格中心与盒边界常常正好相差 1e-16 量级，必须给 eps
        for _, lo, hi in boxes:
            if lo[0] - p <= x <= hi[0] + p and lo[2] - p <= z <= hi[2] + p:
                return True
        return False

    # ① 相关三角面重心
    out_tris, out_area, out_list = 0, 0.0, []
    for t in rel_ids:
        a, b, c = tris[t]
        cx = (verts[a][0] + verts[b][0] + verts[c][0]) / 3.0
        cz = (verts[a][2] + verts[b][2] + verts[c][2]) / 3.0
        if in_xz(cx, cz, EDGE_EPS):
            continue
        out_tris += 1
        ax, az = verts[a][0], verts[a][2]
        bx, bz = verts[b][0], verts[b][2]
        dx, dz = verts[c][0], verts[c][2]
        ar = abs((bx - ax) * (dz - az) - (dx - ax) * (bz - az)) / 2.0
        out_area += ar
        if len(out_list) < 10:
            ymin = min(verts[a][1], verts[b][1], verts[c][1])
            ymax = max(verts[a][1], verts[b][1], verts[c][1])
            out_list.append((cx, cz, ar, ymin, ymax))

    x0, x1, z0, z1 = aabb[0], aabb[1], aabb[4], aabb[5]
    nx = int((x1 - x0) / CELL) + 2
    nz = int((z1 - z0) / CELL) + 2
    occ = glbgeom.rasterize_xz_band(verts, tris, x0, z0, nx, nz, CELL, ids=rel_ids)
    grown = glbgeom.dilate(occ, nx, nz, int(round(empty_tol / CELL)))

    cav = bytearray(nx * nz)
    uncov = bytearray(nx * nz)
    for j in range(nz):
        for i in range(nx):
            cx, cz = x0 + (i + 0.5) * CELL, z0 + (j + 0.5) * CELL
            if in_xz(cx, cz):
                if not occ[j * nx + i] and not grown[j * nx + i]:
                    cav[j * nx + i] = 1
            elif occ[j * nx + i] and not in_xz(cx, cz, CELL / 2):
                # 只有「超出盒半个格」才算真漏（半个格是栅格化的量化误差）
                uncov[j * nx + i] = 1

    n_occ = sum(occ)
    min_cells = max(1, int(0.20 / (CELL * CELL)))
    cav_tot, cav_big, _ = glbgeom.blob_stat(cav, nx, nz, min_cells)
    unc_tot, unc_big, _ = glbgeom.blob_stat(uncov, nx, nz, min_cells)
    ov = []
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            _, l1, h1 = boxes[i]
            _, l2, h2 = boxes[j]
            o = [min(h1[k], h2[k]) - max(l1[k], l2[k]) for k in range(3)]
            if all(v > 1e-6 for v in o):
                ov.append((boxes[i][0], boxes[j][0], [round(v, 4) for v in o]))

    new_area = sum((hi[0] - lo[0]) * (hi[2] - lo[2]) for _, lo, hi in boxes)
    aabb_area = (aabb[1] - aabb[0]) * (aabb[5] - aabb[4])
    ok = (out_tris == 0) and (cav_big < min_cells) and not ov and (unc_big < min_cells)

    if not quiet:
        print("\n① 相关三角面重心在盒外：%d / %d（面积 %.4f m^2）"
              % (out_tris, len(rel_ids), out_area))
        print("② 盒内空阻挡（距相关几何 >%.2fm）：%.3f m^2 总计，最大块 %.3f m^2"
              % (empty_tol, cav_tot * CELL * CELL, cav_big * CELL * CELL))
        for cx, cz, ar, ymin, ymax in out_list:
            print("     重心外 x=%9.4f z=%9.4f  面积 %.6f m^2  y[%.4f, %.4f]" % (cx, cz, ar, ymin, ymax))
        print("③ 盒间重叠：%s" % (ov or "无"))
        print("④ 相关几何占用格未覆盖（超半格才计）：%d / %d（%.3f m^2，最大块 %.3f m^2）"
              % (unc_tot, n_occ, unc_tot * CELL * CELL, unc_big * CELL * CELL))
        print("⑤ 足印 %.2f m^2（原整块 AABB %.2f m^2，削掉 %.2f m^2）"
              % (new_area, aabb_area, aabb_area - new_area))
        print("\n%s" % ("BOX_SEGMENTS_OK" if ok else "BOX_SEGMENTS_FAIL"))
    return ok


def main():
    tol, band = 0.30, 2.2
    rels = []
    for a in sys.argv[1:]:
        if a.startswith("--empty-tol="):
            tol = float(a.split("=")[1])
        elif a.startswith("--band-top="):
            band = float(a.split("=")[1])
        elif a == "--all-band":
            band = None
        else:
            rels.append(a)
    allok = True
    for rel in rels:
        allok &= verify(rel, tol, band)
        print()
    sys.exit(0 if allok else 1)


if __name__ == "__main__":
    main()
