import bpy, os
for img in bpy.data.images:
    print("IMG", img.name)
    print("  filepath:", img.filepath)
    print("  abs:", bpy.path.abspath(img.filepath))
    print("  exists:", os.path.exists(bpy.path.abspath(img.filepath)))
    print("  packed:", img.packed_file is not None, "size:", tuple(img.size))
for m in bpy.data.materials:
    if not m.use_nodes: continue
    for n in m.node_tree.nodes:
        if n.type == "TEX_IMAGE":
            print("MAT", m.name, "tex image:", n.image.name if n.image else None, "has_data:", bool(n.image.has_data) if n.image else None)
