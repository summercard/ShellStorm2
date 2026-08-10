from pathlib import Path
from collections import defaultdict, deque

import bpy


LIBRARY = Path(r"C:\Users\zhuangmenghong\Documents\图片制作\新建文件夹\中文游戏资产成品\风格统一重制V3")


for path in sorted(LIBRARY.glob("0[1-5]_*_风格统一源文件.blend")):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    print(f"\n=== {path.name} ===")
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        data = obj.data
        default_like = len(data.vertices) == 8 and len(data.polygons) == 6
        if "cube" in obj.name.lower() or "box" in obj.name.lower() or default_like:
            collections = ",".join(c.name for c in obj.users_collection)
            print(
                "BOX_CANDIDATE",
                obj.name,
                "verts", len(data.vertices),
                "faces", len(data.polygons),
                "dims", tuple(round(v, 4) for v in obj.dimensions),
                "loc", tuple(round(v, 4) for v in obj.location),
                "collections", collections,
            )
    for mat in bpy.data.materials:
        if not mat.use_nodes or mat.node_tree is None:
            continue
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        images = [n.image.name for n in mat.node_tree.nodes if n.type == "TEX_IMAGE" and n.image]
        if bsdf:
            emission = bsdf.inputs.get("Emission Strength")
            print(
                "MATERIAL", mat.name,
                "metal", round(bsdf.inputs["Metallic"].default_value, 3),
                "rough", round(bsdf.inputs["Roughness"].default_value, 3),
                "emission", round(emission.default_value, 3) if emission else None,
                "images", images,
            )
    for image in bpy.data.images:
        if image.size[0] == 512 and image.size[1] == 512:
            pixels = list(image.pixels[: 512 * 4 * 52])
            print("IMAGE", image.name, image.filepath, "first", tuple(round(v, 3) for v in pixels[:4]))
    output = bpy.data.collections.get("02_游戏输出_整合模型")
    if output:
        for obj in (o for o in output.objects if o.type == "MESH"):
            uv = obj.data.uv_layers.get("PaletteUV")
            area_by_key = defaultdict(float)
            if uv:
                for poly in obj.data.polygons:
                    loop = uv.data[poly.loop_start].uv
                    cell = (min(9, int(loop.x * 10)), min(9, int(loop.y * 10)))
                    area_by_key[(poly.material_index, cell)] += poly.area
            print("OUTPUT", obj.name, "verts", len(obj.data.vertices), "faces", len(obj.data.polygons))
            for key, area in sorted(area_by_key.items(), key=lambda item: item[1], reverse=True)[:12]:
                print("AREA", key, round(area, 4))

            adjacency = defaultdict(set)
            for edge in obj.data.edges:
                a, b = edge.vertices
                adjacency[a].add(b)
                adjacency[b].add(a)
            unseen = set(range(len(obj.data.vertices)))
            components = []
            while unseen:
                root = unseen.pop()
                todo = [root]
                vertices = {root}
                while todo:
                    current = todo.pop()
                    for other in adjacency[current]:
                        if other in unseen:
                            unseen.remove(other)
                            vertices.add(other)
                            todo.append(other)
                faces = [p for p in obj.data.polygons if all(v in vertices for v in p.vertices)]
                coords = [obj.data.vertices[v].co for v in vertices]
                minimum = tuple(min(c[i] for c in coords) for i in range(3))
                maximum = tuple(max(c[i] for c in coords) for i in range(3))
                components.append((len(vertices), len(faces), minimum, maximum))
            for component in sorted(components, key=lambda c: c[0])[:8]:
                if component[0] <= 8:
                    print("COMPONENT", component[0], component[1], tuple(round(v, 3) for v in component[2]), tuple(round(v, 3) for v in component[3]))
