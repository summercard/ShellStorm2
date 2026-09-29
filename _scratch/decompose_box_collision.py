"""只读求解：为一个 prefab 的 GLB 几何求「最少数量矩形碰撞盒」的分段方案。

做法：
  ① 把几何的 XZ 投影栅格化（CELL）；
  ② 贪心最大矩形分解（柱状图单调栈）—— 反复取出当前最大的全占用矩形；
  ③ 合并同宽且相邻的矩形，削减盒数；
  ④ 用真实几何顶点坐标把每个矩形的边界吸附到棱线上（避免 0.05 这样的半格值）；
  ⑤ 双向校验：盒并集 ⊇ 几何投影（不漏）且盒内空腔面积可控。

只打印方案与校验结果，不写任何文件。
用法：python _scratch/decompose_box_collision.py <prefab 相对路径> [MIN_AREA_M2]
"""
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CELL = 0.05
CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
NUM = r"(-?\d+(?:\.\d+)?(?:e-?\d+)?)"


def parse_glb(path):
    buf = path.read_bytes()
    off, chunks = 12, []
    while off < len(buf):
        clen, ctype = struct.unpack("<II", buf[off:off + 8])
        chunks.append((ctype, off + 8, clen))
        off += 8 + clen
    gltf = json.loads(buf[chunks[0][1]:chunks[0][1] + chunks[0][2]].decode("utf-8"))
    bin_off = chunks[1][1]

    def read_accessor(idx):
        acc = gltf["accessors"][idx]
        fmt, size = CT[acc["componentType"]]
        n = NC[acc["type"]]
        bv = gltf["bufferViews"][acc["bufferView"]]
        base = bin_off + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = bv.get("byteStride") or (size * n)
        return [struct.unpack_from("<" + fmt * n, buf, base + i * stride) for i in range(acc["count"])]

    verts, tris = [], []
    for mesh in gltf.get("meshes", []):
        for prim in mesh["primitives"]:
            if "POSITION" not in prim["attributes"]:
                continue
            pos = read_accessor(prim["attributes"]["POSITION"])
            base = len(verts)
            verts.extend(pos)
            if "indices" not in prim:
                continue
            idx = [v[0] for v in read_accessor(prim["indices"])]
            tris += [(base + idx[k], base + idx[k + 1], base + idx[k + 2]) for k in range(0, len(idx), 3)]
    return verts, tris


def load_prefab(rel):
    tscn = ROOT / rel
    text = tscn.read_text(encoding="utf-8")
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")
    return tscn, text, glb


def rasterize(verts, tris, x0, z0, nx, nz):
    occ = bytearray(nx * nz)

    def mark(i, j):
        if 0 <= i < nx and 0 <= j < nz:
            occ[j * nx + i] = 1

    for v in verts:
        mark(int((v[0] - x0) / CELL), int((v[2] - z0) / CELL))
    for a, b, c in tris:
        ax, az = verts[a][0], verts[a][2]
        bx, bz = verts[b][0], verts[b][2]
        cx, cz = verts[c][0], verts[c][2]
        i0, i1 = int((min(ax, bx, cx) - x0) / CELL), int((max(ax, bx, cx) - x0) / CELL)
        j0, j1 = int((min(az, bz, cz) - z0) / CELL), int((max(az, bz, cz) - z0) / CELL)
        area2 = (bx - ax) * (cz - az) - (cx - ax) * (bz - az)
        for j in range(j0, j1 + 1):
            pz = z0 + (j + 0.5) * CELL
            row = j * nx
            for i in range(i0, i1 + 1):
                if occ[row + i]:
                    continue
                px = x0 + (i + 0.5) * CELL
                if abs(area2) < 1e-12:
                    mark(i, j)
                    continue
                d1 = (bx - ax) * (pz - az) - (px - ax) * (bz - az)
                d2 = (cx - bx) * (pz - bz) - (px - bx) * (cz - bz)
                d3 = (ax - cx) * (pz - cz) - (px - cx) * (az - cz)
                if (d1 <= 0 and d2 <= 0 and d3 <= 0) or (d1 >= 0 and d2 >= 0 and d3 >= 0):
                    mark(i, j)
    return occ


def max_rect(occ, nx, nz, alive):
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
        best = max_rect(occ, nx, nz, alive)
        if best is None or best[0] < min_cells:
            break
        area, i0, i1, j0, j1 = best
        rects.append([i0, i1, j0, j1])
        for j in range(j0, j1 + 1):
            row = j * nx
            for i in range(i0, i1 + 1):
                alive[row + i] = 0
    return rects, sum(alive)


def merge(rects):
    changed = True
    rr = [list(r) for r in rects]
    while changed:
        changed = False
        out = []
        while rr:
            cur = rr.pop()
            for k in range(len(rr)):
                o = rr[k]
                # 同 x 范围、z 相邻 → 合并
                if cur[0] == o[0] and cur[1] == o[1] and (cur[3] + 1 == o[2] or o[3] + 1 == cur[2]):
                    o[2] = min(cur[2], o[2])
                    o[3] = max(cur[3], o[3])
                    changed = True
                    break
                # 同 z 范围、x 相邻 → 合并
                if cur[2] == o[2] and cur[3] == o[3] and (cur[1] + 1 == o[0] or o[1] + 1 == cur[0]):
                    o[0] = min(cur[0], o[0])
                    o[1] = max(cur[1], o[1])
                    changed = True
                    break
            else:
                out.append(cur)
            if changed:
                out.extend(rr)
                rr = out
                break
        if not changed:
            rr = out + rr
            break
    return rr


def main():
    rel = sys.argv[1]
    min_area = float(sys.argv[2]) if len(sys.argv) > 2 else 0.20
    tscn, text, glb = load_prefab(rel)
    verts, tris = parse_glb(glb)
    gx = [v[0] for v in verts]
    gy = [v[1] for v in verts]
    gz = [v[2] for v in verts]
    x0, x1, z0, z1 = min(gx), max(gx), min(gz), max(gz)
    y0, y1 = min(gy), max(gy)
    nx = int((x1 - x0) / CELL) + 2
    nz = int((z1 - z0) / CELL) + 2
    print("几何 AABB  x[%.4f, %.4f]  y[%.4f, %.4f]  z[%.4f, %.4f]" % (x0, x1, y0, y1, z0, z1))
    print("栅格 %d x %d = %d 格 (%.2f m)" % (nx, nz, nx * nz, CELL))

    occ = rasterize(verts, tris, x0, z0, nx, nz)
    total_occ = sum(occ)
    print("几何投影占用 %d 格 = %.2f m^2（AABB %.2f m^2）"
          % (total_occ, total_occ * CELL * CELL, (x1 - x0) * (z1 - z0)))

    min_cells = max(1, int(min_area / (CELL * CELL)))
    rects, leftover = decompose(occ, nx, nz, min_cells)
    print("\n贪心分解得 %d 个矩形，未覆盖 %d 格 = %.3f m^2" % (len(rects), leftover, leftover * CELL * CELL))
    rects = merge(rects)
    print("合并后 %d 个矩形" % len(rects))

    # 边界吸附：用该矩形覆盖范围内几何顶点的真实 min/max
    def snap(r):
        i0, i1, j0, j1 = r
        lx, hx = x0 + i0 * CELL, x0 + (i1 + 1) * CELL
        lz, hz = z0 + j0 * CELL, z0 + (j1 + 1) * CELL
        sx = [v[0] for v in verts if lx - CELL <= v[0] <= hx + CELL and lz - CELL <= v[2] <= hz + CELL]
        sz = [v[2] for v in verts if lx - CELL <= v[0] <= hx + CELL and lz - CELL <= v[2] <= hz + CELL]
        if not sx:
            return lx, hx, lz, hz
        return min(sx), max(sx), min(sz), max(sz)

    snapped = [snap(r) for r in rects]
    snapped.sort(key=lambda s: (-(s[1] - s[0]) * (s[3] - s[2])))

    print("\n矩形分段（Blender XZ 坐标，Y 统一取 [%.4f, %.4f]）：" % (y0, y1))
    tot = 0.0
    for k, (lx, hx, lz, hz) in enumerate(snapped, 1):
        a = (hx - lx) * (hz - lz)
        tot += a
        print("  R%-2d x[%8.4f, %8.4f] z[%8.4f, %8.4f]  %.3f x %.3f m  面积 %.2f m^2"
              % (k, lx, hx, lz, hz, hx - lx, hz - lz, a))
    print("  合计足印 %.2f m^2（原整块 AABB %.2f m^2）" % (tot, (x1 - x0) * (z1 - z0)))

    # 双向校验
    def in_boxes(px, pz, tol=0.0):
        for lx, hx, lz, hz in snapped:
            if lx - tol <= px <= hx + tol and lz - tol <= pz <= hz + tol:
                return True
        return False

    out_tris = 0
    for a, b, c in tris:
        cx = (verts[a][0] + verts[b][0] + verts[c][0]) / 3.0
        cz = (verts[a][2] + verts[b][2] + verts[c][2]) / 3.0
        if not in_boxes(cx, cz, 1e-6):
            out_tris += 1
    print("\n① 三角面重心落在盒外：%d / %d" % (out_tris, len(tris)))

    # 空腔：盒内但离几何 > 0.30
    empty = 0
    tot_samples = 0
    step = 0.10
    for lx, hx, lz, hz in snapped:
        px = lx + step / 2
        while px < hx:
            pz = lz + step / 2
            while pz < hz:
                tot_samples += 1
                d = 1e9
                for a, b, c in tris:
                    ax, az = verts[a][0], verts[a][2]
                    bx, bz = verts[b][0], verts[b][2]
                    cx, cz = verts[c][0], verts[c][2]
                    if min(ax, bx, cx) - 0.4 > px or max(ax, bx, cx) + 0.4 < px:
                        continue
                    if min(az, bz, cz) - 0.4 > pz or max(az, bz, cz) + 0.4 < pz:
                        continue
                    area2 = (bx - ax) * (cz - az) - (cx - ax) * (bz - az)
                    if abs(area2) > 1e-9:
                        d1 = (bx - ax) * (pz - az) - (px - ax) * (bz - az)
                        d2 = (cx - bx) * (pz - bz) - (px - bx) * (cz - bz)
                        d3 = (ax - cx) * (pz - cz) - (px - cx) * (az - cz)
                        if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)):
                            d = 0.0
                            break
                    for (sx, sz, ex, ez) in ((ax, az, bx, bz), (bx, bz, cx, cz), (cx, cz, ax, az)):
                        ex2, ez2 = ex - sx, ez - sz
                        L2 = ex2 * ex2 + ez2 * ez2
                        if L2 <= 1e-12:
                            dd = ((px - sx) ** 2 + (pz - sz) ** 2) ** 0.5
                        else:
                            t = ((px - sx) * ex2 + (pz - sz) * ez2) / L2
                            t = 0.0 if t < 0 else (1.0 if t > 1 else t)
                            dd = ((px - (sx + t * ex2)) ** 2 + (pz - (sz + t * ez2))) ** 0.5
                        if dd < d:
                            d = dd
                    if d == 0.0:
                        break
                if d > 0.30:
                    empty += 1
                pz += step
            px += step
    print("② 盒内离几何 >0.30m 的采样点：%d / %d = %.2f m^2 空腔"
          % (empty, tot_samples, empty * step * step))
    print("③ 盒间两两重叠：", end="")
    ov = []
    for i in range(len(snapped)):
        for j in range(i + 1, len(snapped)):
            a_, b_ = snapped[i], snapped[j]
            ox = min(a_[1], b_[1]) - max(a_[0], b_[0])
            oz = min(a_[3], b_[3]) - max(a_[2], b_[2])
            if ox > 1e-6 and oz > 1e-6:
                ov.append((i + 1, j + 1, round(ox, 3), round(oz, 3)))
    print("有 %s" % ov if ov else "无")


if __name__ == "__main__":
    main()
