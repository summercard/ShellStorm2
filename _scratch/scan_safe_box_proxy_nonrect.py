"""只读扫描：找出所有「collision_policy=safe_box_proxy 且足印非矩形」的房型组件 prefab。

判据：
  ① 组件 prefab 只声明 1 个 CollisionShape3D（= 整块 AABB 代理）；
  ② 该 AABB 的 XZ 投影栅格里，存在「离 GLB 几何 XZ 投影 > EMPTY_TOL 且成片」的空腔 ——
     这些格子就是被整块代理误挡的「空阻挡」，玩家在该处走不过去、子弹打不出去。

输出：按空腔面积降序的清单（含单个空腔最大连通块尺寸，用于区分
      「桌子底下的小缝」与「L 形凹口那种真正能站人的空地」）。
"""
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFAB_ROOT = ROOT / "assets/art/environments/tower_zones/expedition/runtime/room_type_components"

CELL = 0.10          # 栅格边长（m）
EMPTY_TOL = 0.30     # 距几何投影多远算「空」
R = int(round(EMPTY_TOL / CELL))   # 膨胀半径（格）
MIN_BLOB_CELLS = 20  # 单个空腔小于此格数（0.2 m^2）忽略，视为造型细节

CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


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
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            if "POSITION" not in prim["attributes"]:
                continue
            pos = read_accessor(prim["attributes"]["POSITION"])
            if "indices" not in prim:
                base = len(verts)
                verts.extend(pos)
                continue
            idx = [v[0] for v in read_accessor(prim["indices"])]
            base = len(verts)
            verts.extend(pos)
            tris += [(base + idx[k], base + idx[k + 1], base + idx[k + 2]) for k in range(0, len(idx), 3)]
    return verts, tris


def aabb(verts):
    xs = [v[0] for v in verts]
    ys = [v[1] for v in verts]
    zs = [v[2] for v in verts]
    return min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)


def rasterize(verts, tris, x0, z0, nx, nz):
    """把三角面投影光栅化成占用栅格。返回 bytearray（1 = 被几何 XZ 投影覆盖）。"""
    occ = bytearray(nx * nz)

    def mark(ix, iz):
        if 0 <= ix < nx and 0 <= iz < nz:
            occ[iz * nx + ix] = 1

    # 顶点直接落格（防退化面/极细面漏格）
    for v in verts:
        mark(int((v[0] - x0) / CELL), int((v[2] - z0) / CELL))

    for a, b, c in tris:
        ax, az = verts[a][0], verts[a][2]
        bx, bz = verts[b][0], verts[b][2]
        cx, cz = verts[c][0], verts[c][2]
        lx, hx = min(ax, bx, cx), max(ax, bx, cx)
        lz, hz = min(az, bz, cz), max(az, bz, cz)
        i0, i1 = int((lx - x0) / CELL), int((hx - x0) / CELL)
        j0, j1 = int((lz - z0) / CELL), int((hz - z0) / CELL)
        if (i1 - i0 + 1) * (j1 - j0 + 1) > 4_000_000:
            continue  # 病态面，跳过
        area2 = (bx - ax) * (cz - az) - (cx - ax) * (bz - az)
        for j in range(j0, j1 + 1):
            pz = z0 + (j + 0.5) * CELL
            for i in range(i0, i1 + 1):
                if occ[j * nx + i]:
                    continue
                px = x0 + (i + 0.5) * CELL
                if abs(area2) < 1e-12:
                    # 退化面（线段）：只按包围盒
                    mark(i, j)
                    continue
                d1 = (bx - ax) * (pz - az) - (px - ax) * (bz - az)
                d2 = (cx - bx) * (pz - bz) - (px - bx) * (cz - bz)
                d3 = (ax - cx) * (pz - cz) - (px - cx) * (az - cz)
                if (d1 <= 0 and d2 <= 0 and d3 <= 0) or (d1 >= 0 and d2 >= 0 and d3 >= 0):
                    mark(i, j)
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


def blobs(occ, nx, nz):
    """返回 (空腔总格数, 最大连通块格数)。"""
    seen = bytearray(nx * nz)
    total, biggest = 0, 0
    for j in range(nz):
        for i in range(nx):
            k = j * nx + i
            if occ[k] or seen[k]:
                continue
            stack = [k]
            seen[k] = 1
            size = 0
            while stack:
                cur = stack.pop()
                size += 1
                ci, cj = cur % nx, cur // nx
                for dj in (-1, 0, 1):
                    jj = cj + dj
                    if jj < 0 or jj >= nz:
                        continue
                    rr = jj * nx
                    for di in (-1, 0, 1):
                        ii = ci + di
                        if ii < 0 or ii >= nx:
                            continue
                        kk = rr + ii
                        if not occ[kk] and not seen[kk]:
                            seen[kk] = 1
                            stack.append(kk)
            total += size
            biggest = max(biggest, size)
    return total, biggest


def scan(tscn: Path):
    text = tscn.read_text(encoding="utf-8")
    if 'collision_policy = "safe_box_proxy"' not in text:
        return None
    shapes = re.findall(r'\[node name="[^"]+" type="CollisionShape3D"', text)
    m = re.search(r'\[ext_resource type="PackedScene" path="([^"]+)"', text)
    if not m:
        return None
    glb_rel = m.group(1).replace("res://", "")
    glb = ROOT / glb_rel
    if not glb.exists():
        return {"tscn": tscn, "error": "GLB 缺失: " + glb_rel}
    verts, tris = parse_glb(glb)
    if not verts:
        return {"tscn": tscn, "error": "GLB 无顶点"}
    xmin, xmax, ymin, ymax, zmin, zmax = aabb(verts)
    nx = max(1, int((xmax - xmin) / CELL) + 1)
    nz = max(1, int((zmax - zmin) / CELL) + 1)
    occ = rasterize(verts, tris, xmin, zmin, nx, nz)
    grown = dilate(occ, nx, nz, R)
    total, biggest = blobs(grown, nx, nz)
    return {
        "tscn": tscn,
        "shapes": len(shapes),
        "verts": len(verts),
        "tris": len(tris),
        "aabb": (xmin, xmax, ymin, ymax, zmin, zmax),
        "cells": nx * nz,
        "empty_cells": total,
        "empty_area": total * CELL * CELL,
        "biggest": biggest,
        "biggest_area": biggest * CELL * CELL,
        "foot_area": (xmax - xmin) * (zmax - zmin),
    }


def main():
    rows, errors = [], []
    files = sorted(PREFAB_ROOT.rglob("*_root_top3d.tscn"))
    for n, tscn in enumerate(files, 1):
        try:
            r = scan(tscn)
        except Exception as exc:  # noqa: BLE001
            errors.append((tscn, repr(exc)))
            continue
        if r is None:
            continue
        if "error" in r:
            errors.append((tscn, r["error"]))
            continue
        r["slug"] = tscn.parent.name
        r["room_type"] = tscn.parent.parent.name
        rows.append(r)
        print("[%d/%d] %s/%s  empty=%.2f m^2  biggest=%.2f m^2"
              % (n, len(files), r["room_type"], r["slug"], r["empty_area"], r["biggest_area"]),
              file=sys.stderr)

    rows.sort(key=lambda r: -r["biggest_area"])
    out = ROOT / "_scratch" / "safe_box_proxy_scan.json"
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=1), encoding="utf-8")

    print("\n=== safe_box_proxy 非矩形件清单（按最大空腔面积降序）===")
    print("%-12s %-26s %8s %8s %8s %8s %6s" % ("房型", "slug", "AABB m2", "空腔 m2", "最大块", "占比", "盒数"))
    for r in rows:
        if r["biggest"] < MIN_BLOB_CELLS:
            continue
        print("%-12s %-26s %8.2f %8.2f %8.2f %7.1f%% %6d"
              % (r["room_type"], r["slug"], r["foot_area"], r["empty_area"],
                 r["biggest_area"], 100.0 * r["empty_area"] / r["foot_area"], r["shapes"]))
    skipped = [r for r in rows if r["biggest"] < MIN_BLOB_CELLS]
    print("\n另有 %d 件空腔 < %.1f m^2（视为造型细节，不处理）" % (len(skipped), MIN_BLOB_CELLS * CELL * CELL))
    print("错误 %d 件" % len(errors))
    for t, e in errors:
        print("  ! %s : %s" % (t.name, e))


if __name__ == "__main__":
    main()
