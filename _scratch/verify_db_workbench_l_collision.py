"""只读校验：workbench_a_root_top3d.tscn 里声明的分段碰撞盒是否与运行时几何一致。

判据（双向）：
  ① 全覆盖：几何的每个三角面重心都必须落在两盒并集内（否则有实体露在碰撞外，能穿模）。
  ② 无空腔：并集内任何离几何 > EMPTY_TOL 的点都不该被挡（否则就是「空阻挡」）。
  ③ 零重叠：两盒不该互相重叠（重叠＝重复计数，说明拆分边界没对齐几何棱）。
"""
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GLB = ROOT / (
    "assets/art/environments/tower_zones/expedition/components/room_type_components/"
    "db_room/workbench_a/workbench_a_visual_top3d.glb"
)
TSCN = ROOT / (
    "assets/art/environments/tower_zones/expedition/runtime/room_type_components/"
    "db_room/workbench_a/workbench_a_root_top3d.tscn"
)
EMPTY_TOL = 0.30

# —— 解析 tscn 里声明的盒 ——
text = TSCN.read_text(encoding="utf-8")
sizes = {
    m.group(1): [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", m.group(2))]
    for m in re.finditer(r'\[sub_resource type="BoxShape3D" id="([^"]+)"\]\s*\r?\nsize = Vector3\(([^)]+)\)', text)
}
boxes = []
for m in re.finditer(
    r'\[node name="([^"]+)" type="CollisionShape3D" parent="[^"]*"\]\s*\r?\n'
    r"position = Vector3\(([^)]+)\)\s*\r?\n"
    r'shape = SubResource\("([^"]+)"\)',
    text,
):
    name, pos, sid = m.group(1), [float(v) for v in m.group(2).split(",")], m.group(3)
    size = sizes[sid]
    lo = [pos[i] - size[i] / 2 for i in range(3)]
    hi = [pos[i] + size[i] / 2 for i in range(3)]
    boxes.append((name, lo, hi))
print("tscn 声明的碰撞盒：")
for name, lo, hi in boxes:
    print("  %-10s x[%7.3f,%7.3f] y[%6.3f,%6.3f] z[%7.3f,%7.3f]  size=(%.3f, %.3f, %.3f)"
          % (name, lo[0], hi[0], lo[1], hi[1], lo[2], hi[2], hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]))

# —— 读几何 ——
buf = GLB.read_bytes()
off, chunks = 12, []
while off < len(buf):
    clen, ctype = struct.unpack("<II", buf[off : off + 8])
    chunks.append((ctype, off + 8, clen))
    off += 8 + clen
gltf = json.loads(buf[chunks[0][1] : chunks[0][1] + chunks[0][2]].decode("utf-8"))
bin_off = chunks[1][1]
CT = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(idx):
    acc = gltf["accessors"][idx]
    fmt, size = CT[acc["componentType"]]
    n = NC[acc["type"]]
    bv = gltf["bufferViews"][acc["bufferView"]]
    base = bin_off + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or (size * n)
    return [struct.unpack_from("<" + fmt * n, buf, base + i * stride) for i in range(acc["count"])]


verts, tris = [], []
for mesh in gltf["meshes"]:
    for prim in mesh["primitives"]:
        pos = read_accessor(prim["attributes"]["POSITION"])
        idx = [v[0] for v in read_accessor(prim["indices"])]
        base = len(verts)
        verts.extend(pos)
        tris += [(base + idx[k], base + idx[k + 1], base + idx[k + 2]) for k in range(0, len(idx), 3)]


def in_xz(x, z, tol=0.0):
    for _, lo, hi in boxes:
        if lo[0] - tol <= x <= hi[0] + tol and lo[2] - tol <= z <= hi[2] + tol:
            return True
    return False


fail = []

# ① 三角面重心全覆盖
out = 0
worst = (0.0, None)
for a, b, c in tris:
    cx = (verts[a][0] + verts[b][0] + verts[c][0]) / 3.0
    cz = (verts[a][2] + verts[b][2] + verts[c][2]) / 3.0
    if not in_xz(cx, cz, 1e-6):
        out += 1
        d = min(
            max(lo[0] - cx, cx - hi[0], 0.0) ** 2 + max(lo[2] - cz, cz - hi[2], 0.0) ** 2
            for _, lo, hi in boxes
        ) ** 0.5
        if d > worst[0]:
            worst = (d, (round(cx, 3), round(cz, 3)))
print("\n① 三角面重心落在两盒之外：%d / %d  最远越界 %.4f m @ %s" % (out, len(tris), worst[0], worst[1]))
if out:
    fail.append("有 %d 个三角面重心在碰撞盒外（实体可穿模）" % out)

# ② 并集内无空腔（点到「三角面在 XZ 上的投影」的真实距离，不是到顶点）
proj = []
for a, b, c in tris:
    ax, az = verts[a][0], verts[a][2]
    bx, bz = verts[b][0], verts[b][2]
    cx, cz = verts[c][0], verts[c][2]
    area2 = (bx - ax) * (cz - az) - (cx - ax) * (bz - az)
    proj.append((
        min(ax, bx, cx), max(ax, bx, cx), min(az, bz, cz), max(az, bz, cz),
        ax, az, bx, bz, cx, cz, area2,
    ))


def seg_dist(ax, az, bx, bz, px, pz):
    ex, ez = bx - ax, bz - az
    L2 = ex * ex + ez * ez
    if L2 <= 1e-12:
        return ((px - ax) ** 2 + (pz - az) ** 2) ** 0.5
    t = ((px - ax) * ex + (pz - az) * ez) / L2
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return ((px - (ax + t * ex)) ** 2 + (pz - (az + t * ez)) ** 2) ** 0.5


def xz_dist(px, pz):
    best = 1e9
    for (lx, hx, lz, hz, ax, az, bx, bz, cx, cz, area2) in proj:
        if px < lx - best or px > hx + best or pz < lz - best or pz > hz + best:
            continue
        if abs(area2) > 1e-9:
            d1 = (bx - ax) * (pz - az) - (px - ax) * (bz - az)
            d2 = (cx - bx) * (pz - bz) - (px - bx) * (cz - bz)
            d3 = (ax - cx) * (pz - cz) - (px - cx) * (az - cz)
            if not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0)):
                return 0.0
        for (sx, sz, ex, ez) in ((ax, az, bx, bz), (bx, bz, cx, cz), (cx, cz, ax, az)):
            d = seg_dist(sx, sz, ex, ez, px, pz)
            if d < best:
                best = d
        if best == 0.0:
            return 0.0
    return best


step = 0.20
empty_pts = []
total = 0
for name, lo, hi in boxes:
    z = lo[2] + step / 2
    while z < hi[2]:
        x = lo[0] + step / 2
        while x < hi[0]:
            total += 1
            if xz_dist(x, z) > EMPTY_TOL:
                empty_pts.append((round(x, 2), round(z, 2)))
            x += step
        z += step
print("② 盒内离任何顶点 >%.2fm 的采样点：%d / %d %s"
      % (EMPTY_TOL, len(empty_pts), total, empty_pts[:6]))
if empty_pts:
    fail.append("盒内有 %d 个空白阻挡采样点（空阻挡）" % len(empty_pts))

# ③ 两盒是否重叠
names = [b[0] for b in boxes]
for i in range(len(boxes)):
    for j in range(i + 1, len(boxes)):
        _, lo1, hi1 = boxes[i]
        _, lo2, hi2 = boxes[j]
        ov = [min(hi1[k], hi2[k]) - max(lo1[k], lo2[k]) for k in range(3)]
        if all(v > 1e-6 for v in ov):
            fail.append("%s 与 %s 重叠 %s（应无重叠）" % (names[i], names[j], ov))
print("③ 盒间重叠：%s" % ("有" if any(r.startswith("B") or " 与 " in r for r in fail) else "无"))

# ④ 旧整块 AABB 的虚假阻挡面积对照
old_area = 14.1 * 7.25
new_area = sum((hi[0] - lo[0]) * (hi[2] - lo[2]) for _, lo, hi in boxes)
print("\n④ 足印面积：旧整块 %.2f m^2 -> 新分段 %.2f m^2（减少 %.2f m^2 虚假阻挡）"
      % (old_area, new_area, old_area - new_area))

print()
print("DB_WORKBENCH_L_COLLISION_%s" % ("OK" if not fail else "FAIL"))
for f in fail:
    print("  - " + f)
