"""Repair palette UV metadata without changing palette assignments or geometry."""

import argparse
import sys
from pathlib import Path

import bpy


def args():
    values = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--glb", type=Path)
    parser.add_argument("--asset-name")
    parser.add_argument("--donor-blend", type=Path)
    parser.add_argument("--donor-object")
    return parser.parse_args(values)


def restore_missing_palette_uv(donor_blend, donor_object_name):
    missing = [o for o in bpy.context.scene.objects if o.type == "MESH" and "PaletteUV" not in o.data.uv_layers]
    if not missing:
        return
    if len(missing) != 1 or not donor_blend or not donor_object_name:
        raise RuntimeError("missing PaletteUV requires exactly one target and an explicit donor")
    with bpy.data.libraries.load(str(donor_blend), link=False) as (source, target):
        if donor_object_name not in source.objects:
            raise RuntimeError(f"donor object not found: {donor_object_name}")
        target.objects = [donor_object_name]
    donor = target.objects[0]
    target_obj = missing[0]
    donor_layer = donor.data.uv_layers.get("PaletteUV")
    if donor_layer is None or len(donor.data.loops) != len(target_obj.data.loops):
        raise RuntimeError(f"donor loop mismatch: {len(donor.data.loops)} != {len(target_obj.data.loops)}")
    layer = target_obj.data.uv_layers.new(name="PaletteUV")
    for index in range(len(layer.data)):
        layer.data[index].uv = donor_layer.data[index].uv
    bpy.data.objects.remove(donor, do_unlink=True)


def standardize_uv_layers():
    # Mesh datablocks can be shared by several objects. Process each datablock once,
    # then set the edit/render layer in a second pass because removing a legacy UV
    # can reset Blender's render-active flag.
    meshes = {obj.data for obj in bpy.context.scene.objects if obj.type == "MESH"}
    for mesh in meshes:
        palette = mesh.uv_layers.get("PaletteUV")
        if palette is None:
            raise RuntimeError(f"{mesh.name} has no PaletteUV")
        for layer in list(mesh.uv_layers):
            if layer != palette:
                mesh.uv_layers.remove(layer)
    for mesh in meshes:
        palette = mesh.uv_layers["PaletteUV"]
        mesh.uv_layers.active = palette
        palette.active_render = True
        mesh.update()
    for material in bpy.data.materials:
        if not material.use_nodes or material.node_tree is None:
            continue
        for node in material.node_tree.nodes:
            if node.type == "UVMAP":
                node.uv_map = "PaletteUV"
            elif node.type == "TEX_IMAGE":
                node.interpolation = "Closest"


def normalize_standard_material_names():
    aliases = {
        "mat_metal_brushed_purple": "01_精工金属_紫色骨架",
        "mat_matte_teal": "02_细腻哑光_青绿大面",
        "mat_clearcoat_magenta": "03_清漆反光_紫粉点缀",
        "mat_emissive_ui": "04_自发光_UI灯光",
    }
    for old_name, new_name in aliases.items():
        material = bpy.data.materials.get(old_name)
        if material is not None:
            material.name = new_name


def ensure_output_collection(asset_name):
    if any(c.name.startswith("02_游戏输出") for c in bpy.data.collections):
        return
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError("collection repair only supports a single integrated mesh")
    root = bpy.data.collections.new(f"{asset_name}_中文资产管理")
    source_note = bpy.data.collections.new("01_制作组件_母版见中文枪械库")
    output = bpy.data.collections.new("02_游戏输出_整合模型")
    bpy.context.scene.collection.children.link(root)
    root.children.link(source_note)
    root.children.link(output)
    obj = meshes[0]
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)
    output.objects.link(obj)
    obj.name = f"{asset_name}_主体_金属哑光反光"
    for collection in list(bpy.data.collections):
        if collection not in {root, source_note, output}:
            bpy.data.collections.remove(collection)


def purge_unused_materials():
    used = {m for o in bpy.context.scene.objects if o.type == "MESH" for m in o.data.materials if m}
    for material in list(bpy.data.materials):
        if material not in used:
            bpy.data.materials.remove(material)


def export_glb(path):
    outputs = [c for c in bpy.data.collections if c.name.startswith("02_游戏输出")]
    objects = {o for c in outputs for o in c.all_objects if o.type == "MESH"}
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = next(iter(objects))
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True, export_yup=True, export_apply=True)


def main():
    options = args()
    restore_missing_palette_uv(options.donor_blend, options.donor_object)
    standardize_uv_layers()
    normalize_standard_material_names()
    if options.asset_name:
        ensure_output_collection(options.asset_name)
    purge_unused_materials()
    options.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(options.output), compress=True)
    if options.glb:
        export_glb(options.glb)


main()
