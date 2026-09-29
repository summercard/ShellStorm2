"""Split the existing 99F chair output meshes into rolling base and swivel top.

Run with Blender --background <v003.blend> --python this_file -- --kind stool|chair.
The v003 source and existing GLBs remain untouched.
"""

import argparse
from collections import defaultdict
from pathlib import Path
import sys

import bpy


def args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=("stool", "chair"), required=True)
    return parser.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])


def vertex_islands(mesh):
    parent = list(range(len(mesh.vertices)))

    def find(number):
        while parent[number] != number:
            parent[number] = parent[parent[number]]
            number = parent[number]
        return number

    for edge in mesh.edges:
        a, b = edge.vertices
        parent[find(a)] = find(b)
    islands = defaultdict(list)
    for vertex in mesh.vertices:
        islands[find(vertex.index)].append(vertex.index)
    return list(islands.values())


def split_output(obj, upper_min_z):
    mesh = obj.data
    upper_ids = set()
    island_count = 0
    for island in vertex_islands(mesh):
        minimum = min(mesh.vertices[index].co.z for index in island)
        if minimum >= upper_min_z:
            upper_ids.update(island)
            island_count += 1
    assert 0 < len(upper_ids) < len(mesh.vertices)
    assert island_count in (3, 5), island_count
    source_vertex_count = len(mesh.vertices)
    before = set(bpy.data.objects)
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.context.tool_settings.mesh_select_mode = (True, False, False)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for vertex in mesh.vertices:
        vertex.select = vertex.index in upper_ids
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    created = [candidate for candidate in bpy.data.objects if candidate not in before]
    assert len(created) == 1, [candidate.name for candidate in created]
    upper = created[0]
    assert len(obj.data.vertices) + len(upper.data.vertices) == source_vertex_count
    obj.name = "座椅_滑行底座_v004"
    upper.name = "座椅_旋转上部_v004"
    obj["motion_role"] = "rolling_base"
    upper["motion_role"] = "swivel_top"
    return obj, upper


def export(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True,
        export_yup=True, export_apply=True, export_texcoords=True,
        export_normals=True, export_materials="EXPORT", export_image_format="NONE",
        export_extras=True, export_cameras=False, export_lights=False,
        export_animations=False,
    )


def main():
    kind = args().kind
    expected = "workshop_stool" if kind == "stool" else "mission_command_chair"
    name = "赛博维修圆凳" if kind == "stool" else "战术指挥椅"
    assert bpy.data.filepath.endswith(f"prp_base_{expected}_source_v003.blend"), bpy.data.filepath
    root = Path(bpy.data.filepath).parents[2]
    source_dir = root / "source" / expected
    component_dir = root / "components" / expected
    combined = bpy.data.objects[f"{name}_主体_金属哑光反光"]
    base, upper = split_output(combined, 0.54 if kind == "stool" else 0.60)
    output_collection = bpy.data.collections["02_游戏输出_整合模型"]
    assert base.name in output_collection.objects and upper.name in output_collection.objects
    base_parts = [base]
    if kind == "stool":
        base_parts.append(bpy.data.objects[f"{name}_UI灯光_柔和自发光"])
    blend_path = source_dir / f"prp_base_{expected}_source_v004.blend"
    assert not blend_path.exists(), blend_path
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    export(component_dir / f"prp_base_{expected}_base_visual_v004.glb", base_parts)
    export(component_dir / f"prp_base_{expected}_swivel_visual_v004.glb", [upper])
    print("SWIVEL_SEAT_EXPORTED", kind, len(base.data.vertices), len(upper.data.vertices), blend_path)


main()
