# -*- coding: utf-8 -*-
"""只读 GLB 结构探针：打印 scenes/nodes/meshes/prims/materials/accessor bounds。"""
import json
import struct
import sys


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, ver, length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67, "not glb"
    off = 12
    js = None
    while off < len(data):
        clen, ctype = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        off += 8 + clen
    return js


g = load(sys.argv[1])
print("asset:", g.get("asset"))
print("scenes:", len(g.get("scenes", [])), "default_scene:", g.get("scene"))
print("nodes:", len(g.get("nodes", [])))
for i, n in enumerate(g.get("nodes", [])):
    trs = {k: n[k] for k in ("translation", "rotation", "scale", "matrix") if k in n}
    print("  node[%d] name=%r mesh=%s children=%s trs=%s" % (i, n.get("name"), n.get("mesh"), n.get("children"), trs or "identity"))
print("meshes:", len(g.get("meshes", [])))
for i, m in enumerate(g.get("meshes", [])):
    print("  mesh[%d] name=%r prims=%d" % (i, m.get("name"), len(m.get("primitives", []))))
print("materials:", [m.get("name") for m in g.get("materials", [])])
print("images:", len(g.get("images", [])), "textures:", len(g.get("textures", [])))
print("extras:", json.dumps(g.get("extras", {}), ensure_ascii=False))
print("scene extras:", json.dumps([s.get("extras", {}) for s in g.get("scenes", [])], ensure_ascii=False))
