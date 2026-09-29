"""只读：从运行时几何精确求 workbench_a 的 L 形两臂矩形，并做「两盒覆盖」验证。"""
import json
import struct

GLB = (
    "assets/art/environments/tower_zones/expedition/components/room_type_components/"
    "db_room/workbench_a/workbench_a_visual_top3d.glb"
)

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
    return [struct.unpack_from("<" + fmt * n, buf, base + i * stride) for i in range(acc["count"])]


verts = []
tris = []
for mesh in gltf["meshes"]:
    for prim in mesh["primitives"]:
        pos = read_accessor(prim["attributes"]["POSITION"])
        idx = [v[0] for v in read_accessor(prim["indices"])]
        base = len(verts)
        verts.extend(pos)
        for k in range(0, len(idx), 3):
            tris.append((base + idx[k], base + idx[k + 1], base + idx[k + 2]))

xmin = min(v[0] for v in verts)
xmax = max(v[0] for v in verts)
ymin = min(v[1] for v in verts)
ymax = max(v[1] for v in verts)
zmin = min(v[2] for v in verts)
zmax = max(v[2] for v in verts)
print("AABB  x[%.4f, %.4f]  y[%.4f, %.4f]  z[%.4f, %.4f]" % (xmin, xmax, ymin, ymax, zmin, zmax))
print("size   x=%.4f  y=%.4f  z=%.4f" % (xmax - xmin, ymax - ymin, zmax - zmin))

# 长臂：贴着 z=zmin 那面墙，沿 X 全长；其深度 = 左半区(x<0)几何的最大 z
left_zmax = max(v[2] for v in verts if v[0] <= 0.0)
# 短臂：贴着 x=xmax 那面墙，沿 Z 延伸；其宽度 = 前区(z>1)几何的最小 x
front_xmin = min(v[0] for v in verts if v[2] >= 1.0)
print()
print("左半区 (x<=0) 最大 z = %.4f  -> 长臂深度 %.4f" % (left_zmax, left_zmax - zmin))
print("前区 (z>=1)  最小 x = %.4f  -> 短臂宽度 %.4f" % (front_xmin, xmax - front_xmin))

# 两矩形（角落重叠共 3 个候选分段，二矩形联合即可）
A = (xmin, left_zmax, zmin, zmax)  # 沿 X 全长的那条
B = (front_xmin, xmax, left_zmax, zmax)  # 沿 Z 的那条
print()
print("矩形A  x[%.3f, %.3f] z[%.3f, %.3f]" % A)
print("矩形B  x[%.3f, %.3f] z[%.3f, %.3f]" % B)


def inside(x, z, tol=0.0):
    if xmin - tol <= x <= xmax + tol and zmin - tol <= z <= A[1] + tol:
        return True
    if B[0] - tol <= x <= xmax + tol and A[1] - tol <= z <= zmax + tol:
        return True
    return False


# 验证：三角面重心是否都在联合区域内；以及联合区域内的空采样
bad = 0
worst = 0.0
for a, b, c in tris:
    cx = (verts[a][0] + verts[b][0] + verts[c][0]) / 3.0
    cz = (verts[a][2] + verts[b][2] + verts[c][2]) / 3.0
    if not inside(cx, cz, 1e-4):
        bad += 1
        # 到最近边的距离
        d = min(abs(cz - A[1]) if cx < B[0] else 9e9, abs(cx - B[0]) if cz > A[1] else 9e9)
        worst = max(worst, d)
print()
print("三角面重心落在两矩形之外：%d / %d（最大越界 %.3f m）" % (bad, len(tris), worst))

# 反向：联合区域内，距离任何几何 > 0.25m 的空洞体积占比（用重心距离近似）
step = 0.25
empty = 0
total = 0
cx = xmin + step / 2
while cx < xmax:
    cz = zmin + step / 2
    while cz < zmax:
        if inside(cx, cz):
            total += 1
            near = False
            for a, b, c in tris:
                ax, az = verts[a][0], verts[a][2]
                bx, bz = verts[b][0], verts[b][2]
                gx, gz = verts[c][0], verts[c][2]
                if min(ax, bx, gx) - 0.3 <= cx <= max(ax, bx, gx) + 0.3 and min(az, bz, gz) - 0.3 <= cz <= max(az, bz, gz) + 0.3:
                    near = True
                    break
            if not near:
                empty += 1
        cz += step
    cx += step
print("两矩形联合区域内、离任何三角面包围盒 >0.30m 的采样点：%d / %d" % (empty, total))
