"""打印塔楼门墙 GLB 的 JSON 结构摘要（节点/网格/材质/场景/扩展）。

用于在改 prefab 之前确认导入后可见的节点名与材质角色，不写任何文件。
"""

import json
import struct
import sys
from pathlib import Path

path = Path(sys.argv[1] if len(sys.argv) > 1 else (
    r"I:\工作项目\shellstrom2\ShellStorm2\assets\art\environments\tower_descent_3d"
    r"\components\env_tower_wall_door_5m_top3d.glb"
))

data = path.read_bytes()
magic, version, length = struct.unpack_from("<III", data, 0)
assert magic == 0x46546C67, "not a GLB"
offset = 12
gltf = None
while offset < length:
    chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
    chunk = data[offset + 8: offset + 8 + chunk_length]
    if chunk_type == 0x4E4F534A:
        gltf = json.loads(chunk.decode("utf-8"))
        break
    offset += 8 + chunk_length

print("file          %s" % path.name)
print("bytes         %d" % len(data))
print("scenes        %d %s  default=%s" % (
    len(gltf.get("scenes", [])),
    [s.get("name") for s in gltf.get("scenes", [])],
    gltf.get("scene"),
))
print("nodes         %d" % len(gltf.get("nodes", [])))
for index, node in enumerate(gltf.get("nodes", [])):
    trs = {k: node[k] for k in ("translation", "rotation", "scale", "matrix") if k in node}
    print("  [%d] name=%r mesh=%s children=%s trs=%s extras=%s" % (
        index,
        node.get("name"),
        node.get("mesh"),
        node.get("children"),
        trs if trs else "identity",
        node.get("extras"),
    ))
print("meshes        %d" % len(gltf.get("meshes", [])))
for mesh in gltf.get("meshes", []):
    print("  name=%r primitives=%d" % (mesh.get("name"), len(mesh.get("primitives", []))))
print("materials     %d" % len(gltf.get("materials", [])))
for material in gltf.get("materials", []):
    pbr = material.get("pbrMetallicRoughness", {})
    print("  name=%r base=%s emissive=%s extras=%s" % (
        material.get("name"),
        pbr.get("baseColorFactor"),
        material.get("emissiveFactor"),
        material.get("extras"),
    ))
print("extensions    used=%s required=%s" % (
    gltf.get("extensionsUsed"), gltf.get("extensionsRequired"),
))
print("images=%d textures=%d" % (len(gltf.get("images", [])), len(gltf.get("textures", []))))
