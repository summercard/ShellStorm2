"""共享：GLB 几何读取 + XZ 投影栅格化（供本目录的只读分析脚本复用）。

要点（都是踩过的坑）：
  * primitive 可能**没有 indices**（Blender 导 quad 时直接给 6 个顶点）—— 必须每 3 个顶点成面，
    否则 XZ 投影会几乎全空，把「实心件」误判成「全是空腔」。
  * glTF 的 mesh 可能挂在带 TRS 的 node 上（例如 Y-up 根变换）—— 顶点要乘到世界坐标，
    否则坐标整体偏。
  * 细长三角形（地板对角线、薄墙）用「格中心在三角形内」会漏格 —— 补一遍边线栅格化。
  * 🔴 **节点的 bbox 会骗人**：一个「自发光灯带」节点的 bbox 可能横跨 39 m，但它的三角面
    只出现在两端。判断几何分布必须落到三角面，不能看节点 bbox。
  * 🔴 **必须记录每格的 y 区间**：同一 XZ 格上，档案柜（y 0..3.05）和吊顶灯带（y 2.9..2.9）
    完全不同 —— 只看 XZ 投影会把「只在 2.9 m 高处的装饰」当成需要碰撞的实体。
"""
import json
import struct
from pathlib import Path

CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def _mat_identity():
    return [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def _mat_mul(a, b):
    """列主序 4x4 相乘：结果 = a * b（即先应用 b）。"""
    out = [0.0] * 16
    for c in range(4):
        for r in range(4):
            out[c * 4 + r] = sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4))
    return out


def _mat_from_trs(node):
    if "matrix" in node:
        return list(node["matrix"])
    t = node.get("translation", [0.0, 0.0, 0.0])
    r = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    s = node.get("scale", [1.0, 1.0, 1.0])
    x, y, z, w = r
    rot = [
        1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
        2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
        2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
        0, 0, 0, 1,
    ]
    for c in range(3):
        for r_ in range(3):
            rot[c * 4 + r_] *= s[c]
    rot[12], rot[13], rot[14] = t
    return rot


def _xform(m, p):
    x, y, z = p[0], p[1], p[2]
    return (
        m[0] * x + m[4] * y + m[8] * z + m[12],
        m[1] * x + m[5] * y + m[9] * z + m[13],
        m[2] * x + m[6] * y + m[10] * z + m[14],
    )


def _read_glb(path):
    """返回 (gltf_json, buf, bin_off)；读不开时返回 (None, None, 0)。"""
    buf = path.read_bytes()
    off, chunks = 12, []
    while off < len(buf):
        clen, ctype = struct.unpack("<II", buf[off:off + 8])
        chunks.append((ctype, off + 8, clen))
        off += 8 + clen
    if len(chunks) < 2:
        return None, None, 0
    gltf = json.loads(buf[chunks[0][1]:chunks[0][1] + chunks[0][2]].decode("utf-8"))
    return gltf, buf, chunks[1][1]


def parse_glb_parts(path: Path):
    """返回 [(label, verts, tris)]，label = "<node 路径>/prim#<i>"，坐标为 glTF 场景世界坐标。

    用途：需要把几何按「实物件」分组时（例如判断某一堆三角面到底在不在玩家高度带里）。
    """
    gltf, buf, bin_off = _read_glb(path)
    if gltf is None:
        return []

    def read_accessor(idx):
        acc = gltf["accessors"][idx]
        fmt, size = CT[acc["componentType"]]
        n = NC[acc["type"]]
        bv = gltf["bufferViews"][acc["bufferView"]]
        base = bin_off + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = bv.get("byteStride") or (size * n)
        return [struct.unpack_from("<" + fmt * n, buf, base + i * stride) for i in range(acc["count"])]

    instances = []

    def walk(ni, parent, path_str):
        node = gltf["nodes"][ni]
        m = _mat_mul(parent, _mat_from_trs(node))
        here = path_str + "/" + node.get("name", "node%d" % ni)
        if "mesh" in node:
            instances.append((node["mesh"], m, here))
        for ch in node.get("children", []):
            walk(ch, m, here)

    if "scenes" in gltf:
        for ni in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
            walk(ni, _mat_identity(), "")
    else:
        for ni in range(len(gltf.get("nodes", []))):
            if "mesh" in gltf["nodes"][ni]:
                instances.append((gltf["nodes"][ni]["mesh"], _mat_identity(), "/node%d" % ni))
    if not instances:
        instances = [(i, _mat_identity(), "/mesh%d" % i) for i in range(len(gltf.get("meshes", [])))]

    parts = []
    for mi, m, label in instances:
        ident = m == _mat_identity()
        for pi, prim in enumerate(gltf["meshes"][mi]["primitives"]):
            if "POSITION" not in prim["attributes"]:
                continue
            pos = read_accessor(prim["attributes"]["POSITION"])
            verts = list(pos) if ident else [_xform(m, p) for p in pos]
            tris = []
            if prim.get("mode", 4) == 4:
                if "indices" in prim:
                    idx = [v[0] for v in read_accessor(prim["indices"])]
                    tris = [(idx[k], idx[k + 1], idx[k + 2]) for k in range(0, len(idx) - 2, 3)]
                else:
                    # 🔴 无索引：每 3 个顶点一个面
                    tris = [(k, k + 1, k + 2) for k in range(0, len(pos) - 2, 3)]
            parts.append(("%s/prim#%d" % (label, pi), verts, tris))
    return parts


def parse_glb(path: Path):
    """返回 (verts, tris)，坐标为 glTF 场景世界坐标（已应用 node TRS）。"""
    verts, tris = [], []
    for _, v, t in parse_glb_parts(path):
        base = len(verts)
        verts.extend(v)
        tris.extend((a + base, b + base, c + base) for a, b, c in t)
    return verts, tris


def rasterize_xz(verts, tris, x0, z0, nx, nz, cell):
    """把三角面的 XZ 投影光栅化成占用栅格（1 = 被覆盖）。"""
    return rasterize_xz_band(verts, tris, x0, z0, nx, nz, cell)


def rasterize_xz_band(verts, tris, x0, z0, nx, nz, cell, ids=None, yacc=None):
    """同上，但可只光栅化指定三角面，并把每个三角面的 y 区间记到被标记的格上。

    ids  : 参与光栅化的三角面索引（None = 全部）
    yacc : (minY, maxY) 两个列表；被标记的格按三角面的 y 区间收窄/扩张。
           （本函数不再跳过「已被标记」的格，否则先标记的低矮件会压掉后标记的高大件。）
    """
    occ = bytearray(nx * nz)
    idlist = range(len(tris)) if ids is None else list(ids)

    def mark(i, j, ymin, ymax):
        if 0 <= i < nx and 0 <= j < nz:
            k = j * nx + i
            occ[k] = 1
            if yacc is not None:
                if ymin < yacc[0][k]:
                    yacc[0][k] = ymin
                if ymax > yacc[1][k]:
                    yacc[1][k] = ymax

    def line(ax, az, bx, bz, ymin, ymax):
        """把线段按格中心步进打点，保证细条不漏。"""
        dx, dz = bx - ax, bz - az
        steps = int(max(abs(dx), abs(dz)) / (cell * 0.5)) + 1
        for s in range(steps + 1):
            t = s / steps if steps else 0.0
            mark(int((ax + dx * t - x0) / cell), int((az + dz * t - z0) / cell), ymin, ymax)

    # ① 顶点与棱线先打底
    for t in idlist:
        a, b, c = tris[t]
        ymin = min(verts[a][1], verts[b][1], verts[c][1])
        ymax = max(verts[a][1], verts[b][1], verts[c][1])
        for v in (a, b, c):
            mark(int((verts[v][0] - x0) / cell), int((verts[v][2] - z0) / cell), ymin, ymax)
        line(verts[a][0], verts[a][2], verts[b][0], verts[b][2], ymin, ymax)
        line(verts[b][0], verts[b][2], verts[c][0], verts[c][2], ymin, ymax)
        line(verts[c][0], verts[c][2], verts[a][0], verts[a][2], ymin, ymax)

    # ② 内部填充（格中心在三角形内）
    for t in idlist:
        a, b, c = tris[t]
        ax, az = verts[a][0], verts[a][2]
        bx, bz = verts[b][0], verts[b][2]
        cx, cz = verts[c][0], verts[c][2]
        ymin = min(verts[a][1], verts[b][1], verts[c][1])
        ymax = max(verts[a][1], verts[b][1], verts[c][1])
        i0, i1 = int((min(ax, bx, cx) - x0) / cell), int((max(ax, bx, cx) - x0) / cell)
        j0, j1 = int((min(az, bz, cz) - z0) / cell), int((max(az, bz, cz) - z0) / cell)
        if (i1 - i0 + 1) * (j1 - j0 + 1) > 2_000_000:
            continue
        area2 = (bx - ax) * (cz - az) - (cx - ax) * (bz - az)
        if abs(area2) < 1e-12:
            continue
        for j in range(j0, j1 + 1):
            pz = z0 + (j + 0.5) * cell
            row = j * nx
            for i in range(i0, i1 + 1):
                if yacc is None and occ[row + i]:
                    continue
                px = x0 + (i + 0.5) * cell
                d1 = (bx - ax) * (pz - az) - (px - ax) * (bz - az)
                d2 = (cx - bx) * (pz - bz) - (px - bx) * (cz - bz)
                d3 = (ax - cx) * (pz - cz) - (px - cx) * (az - cz)
                if (d1 <= 0 and d2 <= 0 and d3 <= 0) or (d1 >= 0 and d2 >= 0 and d3 >= 0):
                    mark(i, j, ymin, ymax)
    return occ


def dilate(occ, nx, nz, r):
    cur = occ
    for _ in range(r):
        nxt = bytearray(cur)
        for j in range(nz):
            row = j * nx
            for i in range(nx):
                if cur[row + i]:
                    continue
                hit = False
                for dj in (-1, 0, 1):
                    jj = j + dj
                    if jj < 0 or jj >= nz:
                        continue
                    rr = jj * nx
                    for di in (-1, 0, 1):
                        ii = i + di
                        if 0 <= ii < nx and cur[rr + ii]:
                            hit = True
                            break
                    if hit:
                        break
                if hit:
                    nxt[row + i] = 1
        cur = nxt
    return cur


def components8(mask, nx, nz):
    """把 mask 中为 1 的格按 8 连通切块，返回 [[cell_k, ...], ...]。"""
    seen = bytearray(nx * nz)
    out = []
    for j in range(nz):
        for i in range(nx):
            k = j * nx + i
            if not mask[k] or seen[k]:
                continue
            stack = [k]
            seen[k] = 1
            cells = []
            while stack:
                cur = stack.pop()
                cells.append(cur)
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
                            if mask[kk] and not seen[kk]:
                                seen[kk] = 1
                                stack.append(kk)
            out.append(cells)
    return out


def blob_stat(mask, nx, nz, min_cells):
    """统计 mask 中**为 1** 的格：返回 (总格数, 最大连通块格数, 超过 min_cells 的块总格数)。

    🔴 注意方向：本函数统计「被标记」的格，不是「未标记」的格。
    （早期版本反了，导致出现「漏覆盖 > 几何投影」这种数学上不可能的结果。）
    """
    total, biggest, big = 0, 0, 0
    for cells in components8(mask, nx, nz):
        n = len(cells)
        total += n
        biggest = max(biggest, n)
        if n >= min_cells:
            big += n
    return total, biggest, big
