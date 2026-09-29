"""只读：把 workbench_a（东侧 L 形维修台）的运行时几何投影成 XZ 占用栅格，用于设计分段碰撞盒。"""
import json
import struct
import sys
from collections import defaultdict

GLB = (
    "assets/art/environments/tower_zones/expedition/components/room_type_components/"
    "db_room/workbench_a/workbench_a_visual_top3d.glb"
)
CELL = 0.10

buf = open(GLB, "rb").read()
off = 12
chunks = []
while off < len(buf):
    clen, ctype = struct.unpack("<II", buf[off : off + 8])
    chunks.append((ctype, off + 8, clen))
    off += 8 + clen
gltf = json.loads(buf[chunks[0][1] : chunks[0][1] + chunks[0][2]].decode("utf-8"))
bin_off = chunks[1][1]

CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(idx):
    acc = gltf["accessors"][idx]
    fmt, size = CT[acc["componentType"]]
    n = NC[acc["type"]]
    bv = gltf["bufferViews"][acc["bufferView"]]
    base = bin_off + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or (size * n)
    out = []
    for i in range(acc["count"]):
        s = base + i * stride
        out.append(struct.unpack_from("<" + fmt * n, buf, s))
    return out


positions_all = []
for mesh in gltf["meshes"]:
    for prim in mesh["primitives"]:
        pos = read_accessor(prim["attributes"]["POSITION"])
        idx = [v[0] for v in read_accessor(prim["indices"])]
        positions_all.append((mesh.get("name", ""), pos, idx))

# 全体几何包围盒
gx = [p[0] for _, pos, _ in positions_all for p in pos]
gy = [p[1] for _, pos, _ in positions_all for p in pos]
gz = [p[2] for _, pos, _ in positions_all for p in pos]
print("geometry AABB godot: x[%.3f, %.3f] y[%.3f, %.3f] z[%.3f, %.3f]" % (min(gx), max(gx), min(gy), max(gy), min(gz), max(gz)))

x0, x1 = min(gx), max(gx)
z0, z1 = min(gz), max(gz)
nx = int((x1 - x0) / CELL) + 1
nz = int((z1 - z0) / CELL) + 1
occ = [[0] * nx for _ in range(nz)]
ymin = [[1e9] * nx for _ in range(nz)]
ymax = [[-1e9] * nx for _ in range(nz)]
r = CELL * 0.5


def mark(ix, iz, y):
    if 0 <= ix < nx and 0 <= iz < nz:
        occ[iz][ix] = 1
        if y < ymin[iz][ix]:
            ymin[iz][ix] = y
        if y > ymax[iz][ix]:
            ymax[iz][ix] = y


def seg_hits_cell(ax, az, bx, bz, cx, cz):
    ex, ez = bx - ax, bz - az
    L2 = ex * ex + ez * ez
    if L2 <= 1e-12:
        d2 = (cx - ax) ** 2 + (cz - az) ** 2
    else:
        t = ((cx - ax) * ex + (cz - az) * ez) / L2
        t = 0.0 if t < 0 else (1.0 if t > 1 else t)
        d2 = (cx - (ax + t * ex)) ** 2 + (cz - (az + t * ez)) ** 2
    return d2 <= r * r


tri_count = 0
for name, pos, idx in positions_all:
    for k in range(0, len(idx), 3):
        a = pos[idx[k]]
        b = pos[idx[k + 1]]
        c = pos[idx[k + 2]]
        tri_count += 1
        ax, az = a[0], a[2]
        bx, bz = b[0], b[2]
        cx, cz = c[0], c[2]
        ytri = (a[1], b[1], c[1])
        area2 = (bx - ax) * (cz - az) - (cx - ax) * (bz - az)
        ixa = int((min(ax, bx, cx) - x0) / CELL)
        ixb = int((max(ax, bx, cx) - x0) / CELL)
        iza = int((min(az, bz, cz) - z0) / CELL)
        izb = int((max(az, bz, cz) - z0) / CELL)
        for iz in range(max(0, iza), min(nz - 1, izb) + 1):
            pz = z0 + (iz + 0.5) * CELL
            for ix in range(max(0, ixa), min(nx - 1, ixb) + 1):
                px = x0 + (ix + 0.5) * CELL
                ok = False
                if abs(area2) > 1e-9:
                    d1 = (bx - ax) * (pz - az) - (px - ax) * (bz - az)
                    d2 = (cx - bx) * (pz - bz) - (px - bx) * (cz - bz)
                    d3 = (ax - cx) * (pz - cz) - (px - cx) * (az - cz)
                    neg = d1 < 0 or d2 < 0 or d3 < 0
                    pos_ = d1 > 0 or d2 > 0 or d3 > 0
                    if not (neg and pos_):
                        ok = True
                        w = d2 / area2
                        wb = d3 / area2
                        wa = 1.0 - w - wb
                        yy = wa * ytri[0] + w * ytri[1] + wb * ytri[2]
                        mark(ix, iz, yy)
                if not ok:
                    if (
                        seg_hits_cell(ax, az, bx, bz, px, pz)
                        or seg_hits_cell(bx, bz, cx, cz, px, pz)
                        or seg_hits_cell(cx, cz, ax, az, px, pz)
                    ):
                        mark(ix, iz, min(ytri))

print("triangles=%d cell=%.2fm grid=%dx%d" % (tri_count, CELL, nx, nz))

print()
print("占用栅格（# = 有几何；. = 空；列＝Godot X 从 %.2f 到 %.2f，行＝Godot Z 从 %.2f 到 %.2f）" % (x0, x1, z0, z1))
header = "      " + "".join(str((i // 10) % 10) if i % 10 == 0 else " " for i in range(nx))
print(header)
for iz in range(nz):
    zc = z0 + (iz + 0.5) * CELL
    row = "".join("#" if occ[iz][ix] else "." for ix in range(nx))
    print("%6.2f %s" % (zc, row))

print()
print("每行（固定 Z）的占用 X 区间：")
for iz in range(nz):
    runs = []
    ix = 0
    while ix < nx:
        if occ[iz][ix]:
            s = ix
            while ix < nx and occ[iz][ix]:
                ix += 1
            runs.append((x0 + s * CELL, x0 + ix * CELL))
        else:
            ix += 1
    if runs:
        zc = z0 + (iz + 0.5) * CELL
        print("  z=%6.2f  " % zc + "  ".join("[%.2f, %.2f]" % r_ for r_ in runs))
