"""只读：打印 GLB 中每个「带网格的节点 / 每个 primitive」的世界坐标包围盒。

用途：手工做碰撞盒分段前，先弄清几何由哪几件实物组成、每件的真实三维范围
（尤其是细长件是「踢脚 / 顶轨 / 装饰薄片」还是「真实障碍」）。

用法：python _scratch/glb_node_boxes.py <prefab 相对路径>
"""
import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glbgeom  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main():
    rel = sys.argv[1]
    tscn = ROOT / rel
    text = tscn.read_text(encoding="utf-8")
    import re
    m = re.search(r'\[ext_resource[^\]]*path="(res://[^"]+\.glb)"', text)
    glb = ROOT / m.group(1).replace("res://", "")

    buf = glb.read_bytes()
    off, chunks = 12, []
    while off < len(buf):
        clen, ctype = struct.unpack("<II", buf[off:off + 8])
        chunks.append((ctype, off + 8, clen))
        off += 8 + clen
    g = json.loads(buf[chunks[0][1]:chunks[0][1] + chunks[0][2]].decode("utf-8"))
    bin_off = chunks[1][1]

    def read_accessor(idx):
        acc = g["accessors"][idx]
        fmt, size = glbgeom.CT[acc["componentType"]]
        n = glbgeom.NC[acc["type"]]
        bv = g["bufferViews"][acc["bufferView"]]
        base = bin_off + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = bv.get("byteStride") or (size * n)
        return [struct.unpack_from("<" + fmt * n, buf, base + i * stride)
                for i in range(acc["count"])]

    rows = []

    def walk(ni, parent, path):
        node = g["nodes"][ni]
        mm = glbgeom._mat_mul(parent, glbgeom._mat_from_trs(node))
        name = node.get("name", "node%d" % ni)
        here = path + "/" + name
        if "mesh" in node:
            for pi, prim in enumerate(g["meshes"][node["mesh"]]["primitives"]):
                if "POSITION" not in prim["attributes"]:
                    continue
                pos = read_accessor(prim["attributes"]["POSITION"])
                w = [glbgeom._xform(mm, p) for p in pos]
                xs = [q[0] for q in w]
                ys = [q[1] for q in w]
                zs = [q[2] for q in w]
                mode = prim.get("mode", 4)
                ntri = (len(read_accessor(prim["indices"])) // 3) if "indices" in prim else len(pos) // 3
                rows.append((here, pi, mode, len(pos), ntri,
                             (min(xs), max(xs)), (min(ys), max(ys)), (min(zs), max(zs))))
        for ch in node.get("children", []):
            walk(ch, mm, here)

    for ni in g["scenes"][g.get("scene", 0)]["nodes"]:
        walk(ni, glbgeom._mat_identity(), "")

    print("GLB %s" % glb.relative_to(ROOT).as_posix())
    print("共 %d 个带网格的 primitive\n" % len(rows))
    for here, pi, mode, nv, ntri, xr, yr, zr in rows:
        print("%s  prim#%d mode=%d verts=%d tris=%d" % (here, pi, mode, nv, ntri))
        print("    x[%9.4f, %9.4f]  span %7.3f" % (xr[0], xr[1], xr[1] - xr[0]))
        print("    y[%9.4f, %9.4f]  span %7.3f" % (yr[0], yr[1], yr[1] - yr[0]))
        print("    z[%9.4f, %9.4f]  span %7.3f" % (zr[0], zr[1], zr[1] - zr[0]))
        print()


if __name__ == "__main__":
    main()
