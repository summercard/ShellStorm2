"""Print the glTF node names / mesh count of a GLB (definitive check of what was exported)."""
import json
import struct
import sys
from pathlib import Path

for raw in sys.argv[1:]:
    path = Path(raw)
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a GLB: %s" % path
    offset = 12
    chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
    assert chunk_type == 0x4E4F534A, "first chunk is not JSON"
    doc = json.loads(data[offset + 8: offset + 8 + chunk_len].decode("utf-8"))
    print("\n== %s (v%d, %d bytes) ==" % (path.name, version, length))
    print("   scenes=%s" % doc.get("scenes"))
    print("   nodes:")
    for index, node in enumerate(doc.get("nodes", [])):
        print("     [%d] name=%r mesh=%s children=%s" % (
            index, node.get("name"), node.get("mesh"), node.get("children")))
    print("   meshes=%d materials=%s" % (
        len(doc.get("meshes", [])),
        [m.get("name") for m in doc.get("materials", [])]))
