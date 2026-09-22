# -*- coding: utf-8 -*-
"""GLB 结构探针：只读解析 glTF JSON chunk，报告材质名 / 图元数 / 顶点数 / 法线轴向上界。
用途：独立于 Godot 导入器核验 env_tower_floor_tile_5m_top3d.glb 的几何契约。
"""
import json
import struct
import sys
from pathlib import Path

DEFAULT = Path(r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments"
               r"\tower_descent_3d\components\floor_tile_5m"
               r"\env_tower_floor_tile_5m_top3d.glb")


def load_glb(path: Path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", raw, 0)
    assert magic == 0x46546C67, "not a GLB"
    offset = 12
    gltf = None
    while offset < length:
        clen, ctype = struct.unpack_from("<II", raw, offset)
        chunk = raw[offset + 8: offset + 8 + clen]
        if ctype == 0x4E4F534A:
            gltf = json.loads(chunk.decode("utf-8"))
        offset += 8 + clen + ((4 - clen % 4) % 4 if clen % 4 else 0)
    assert gltf is not None, "no JSON chunk"
    return gltf


def main():
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    g = load_glb(path)
    print("GLB_FILE %s" % path.name)
    print("GLB_BYTES %d" % path.stat().st_size)
    header = g.get("asset", {})
    print("GLB_GENERATOR %s" % header.get("generator", "-"))

    mats = g.get("materials", [])
    print("GLB_MATERIALS %d %s" % (len(mats), [m.get("name") for m in mats]))
    print("GLB_IMAGES %d  GLB_TEXTURES %d" % (len(g.get("images", [])), len(g.get("textures", []))))
    print("GLB_MESHES %d  GLB_NODES %d" % (len(g.get("meshes", [])), len(g.get("nodes", []))))
    print("GLB_NODE_NAMES %s" % [n.get("name") for n in g.get("nodes", [])])

    accessors = g.get("accessors", [])
    total_tris = 0
    total_verts = 0
    prim_count = 0
    ymax_all = None
    ymin_all = None
    for mesh in g.get("meshes", []):
        for prim in mesh.get("primitives", []):
            prim_count += 1
            pos = accessors[prim["attributes"]["POSITION"]]
            total_verts += pos["count"]
            if "indices" in prim:
                total_tris += accessors[prim["indices"]]["count"] // 3
            lo, hi = pos.get("min"), pos.get("max")
            if lo and hi:
                ymax_all = hi[1] if ymax_all is None else max(ymax_all, hi[1])
                ymin_all = lo[1] if ymin_all is None else min(ymin_all, lo[1])
                print("GLB_PRIM tris=%-5d verts=%-5d mat=%s  min=%s max=%s" % (
                    accessors[prim["indices"]]["count"] // 3 if "indices" in prim else 0,
                    pos["count"],
                    mats[prim["material"]].get("name") if "material" in prim else "-",
                    [round(v, 4) for v in lo], [round(v, 4) for v in hi],
                ))
    print("GLB_PRIMS %d  TRIS %d  VERTS %d" % (prim_count, total_tris, total_verts))
    print("GLB_Y_RANGE [%.4f, %.4f]  HEIGHT=%.4f" % (ymin_all, ymax_all, ymax_all - ymin_all))
    expect = 0.1540
    ok = abs(ymax_all - expect) <= 1e-6
    print("GLB_TOP_MATCHES_ANTICOPLANAR_TOP %s (expect %.4f got %.4f)" % (ok, expect, ymax_all))
    print("GLB_VERDICT %s" % ("PASS" if ok else "FAIL"))


if __name__ == "__main__":
    main()
