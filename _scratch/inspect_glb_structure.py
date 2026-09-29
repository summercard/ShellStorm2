"""只读：打印 GLB 的 scene/node/mesh/primitive 结构，确认没有漏解析的网格。"""
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    rel = sys.argv[1]
    buf = (ROOT / rel).read_bytes()
    off, chunks = 12, []
    while off < len(buf):
        clen, ctype = struct.unpack("<II", buf[off:off + 8])
        chunks.append((ctype, off + 8, clen))
        off += 8 + clen
    g = json.loads(buf[chunks[0][1]:chunks[0][1] + chunks[0][2]].decode("utf-8"))
    print("scenes=%d 默认=%s  nodes=%d  meshes=%d  materials=%d"
          % (len(g.get("scenes", [])), g.get("scene"), len(g.get("nodes", [])),
             len(g.get("meshes", [])), len(g.get("materials", []))))
    for i, sc in enumerate(g.get("scenes", [])):
        print("  scene[%d] name=%r nodes=%s" % (i, sc.get("name"), sc.get("nodes")))
    if "nodes" in g:
        for i, n in enumerate(g["nodes"]):
            trs = {k: n[k] for k in ("translation", "rotation", "scale", "matrix") if k in n}
            print("  node[%d] name=%-24r mesh=%s children=%s %s"
                  % (i, n.get("name"), n.get("mesh"), n.get("children"), trs or ""))
    for i, m in enumerate(g.get("meshes", [])):
        modes = [p.get("mode", 4) for p in m["primitives"]]
        idx = [("indices" in p) for p in m["primitives"]]
        print("  mesh[%d] name=%-24r prims=%d modes=%s has_indices=%s"
              % (i, m.get("name"), len(m["primitives"]), modes, idx))


if __name__ == "__main__":
    main()
