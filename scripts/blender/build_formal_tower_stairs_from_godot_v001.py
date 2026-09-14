"""Build the formal 12 m stairwell Blender source from the current Godot GLBs.

This deliberately starts from an empty file, so battle, rooftop, base, props,
cameras and display geometry cannot leak into the stairwell source.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[2]
CONTRACT = ROOT / "source/art/whitebox/tower_zones/v012/data/whitebox_stairs_v012.json"
OUTPUT = ROOT / "assets/art/environments/tower_descent_3d/source/stairs_12m/env_tower_stairs_12m_source_v001.blend"
MANIFEST = OUTPUT.with_name("asset_manifest_v001.json")
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def new_collection(name: str, parent: bpy.types.Collection) -> bpy.types.Collection:
    collection = bpy.data.collections.new(name)
    parent.children.link(collection)
    return collection


def move_to(object_: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for owner in list(object_.users_collection):
        owner.objects.unlink(object_)
    collection.objects.link(object_)


def make_material(name: str, base_color, metallic: float, roughness: float, cell: tuple[int, int]):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material["palette_cell"] = list(cell)
    material.diffuse_color = (*base_color, 1.0)
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = (*base_color, 1.0)
    principled.inputs["Metallic"].default_value = metallic
    principled.inputs["Roughness"].default_value = roughness
    uv = material.node_tree.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    image = material.node_tree.nodes.new("ShaderNodeTexImage")
    image.image = bpy.data.images.load(str(PALETTE), check_existing=True)
    image.interpolation = "Closest"
    material.node_tree.links.new(uv.outputs["UV"], image.inputs["Vector"])
    material.node_tree.links.new(image.outputs["Color"], principled.inputs["Base Color"])
    return material


def assign_palette_uv(mesh: bpy.types.Mesh, cell: tuple[int, int]) -> None:
    while mesh.uv_layers:
        mesh.uv_layers.remove(mesh.uv_layers[0])
    layer = mesh.uv_layers.new(name="PaletteUV")
    mesh.uv_layers.active = layer
    layer.active_render = True
    cx = (cell[0] + 0.5) / 10.0
    cy = 1.0 - (cell[1] + 0.5) / 10.0
    radius = 0.022
    for polygon in mesh.polygons:
        count = polygon.loop_total
        for index, loop_index in enumerate(polygon.loop_indices):
            angle = 2.0 * math.pi * index / max(count, 3)
            layer.data[loop_index].uv = (cx + math.cos(angle) * radius, cy + math.sin(angle) * radius)


def classify(name: str):
    lower = name.lower()
    if "guard" in lower or "tread" in lower:
        return "metal"
    return "matte"


def import_package(glb: Path, source_collection: bpy.types.Collection, source_label: str, materials: dict):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    imported = [obj for obj in bpy.data.objects if obj not in before]
    for obj in imported:
        move_to(obj, source_collection)
        obj["block_id"] = "stairs"
        obj["derived_from_godot_glb"] = True
        obj["source_glb"] = str(glb.relative_to(ROOT))
        obj["source_package"] = source_label
        if obj.type == "MESH":
            role = classify(obj.name)
            obj.data.materials.clear()
            obj.data.materials.append(materials[role])
            assign_palette_uv(obj.data, materials[role]["palette_cell"])
    return imported


def duplicate_package(source_objects, output_collection: bpy.types.Collection, label: str):
    copies = []
    mapping = {}
    for obj in source_objects:
        copy = obj.copy()
        if obj.data:
            copy.data = obj.data.copy()
        copy.name = f"{label}_{obj.name}"
        output_collection.objects.link(copy)
        mapping[obj] = copy
        copies.append(copy)
    for original, copy in mapping.items():
        copy.parent = mapping.get(original.parent)
        copy["asset_package"] = label
        copy["production_stage"] = "formal_blender_source"
    return copies


def main() -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["block_id"] = "stairs"
    scene["production_stage"] = "formal_blender_source"
    scene["derived_from_godot_glb"] = True
    scene["floor_height_m"] = contract["floor_height_m"]
    scene["visible_wall_height_m"] = contract["visible_wall_height_m"]
    scene["runtime_reimported"] = False

    root = new_collection("塔楼12米楼梯间_中文资产管理", scene.collection)
    source_root = new_collection("01_制作组件_由Godot现行模型反推", root)
    output_root = new_collection("02_游戏输出_独立资产包_v001", root)

    materials = {
        "metal": make_material("01_精工金属_紫色骨架", (0.16, 0.07, 0.24), 0.86, 0.27, (1, 1)),
        "matte": make_material("02_细腻哑光_青绿大面", (0.05, 0.34, 0.32), 0.02, 0.70, (4, 3)),
    }

    package_specs = [
        ("楼梯A_100至99层", ROOT / contract["source_glbs"]["stair_a"]),
        ("楼梯B_99至98层", ROOT / contract["source_glbs"]["stair_b"]),
    ]
    manifest_packages = []
    for label, glb in package_specs:
        source_collection = new_collection(f"{label}_源组件", source_root)
        output_collection = new_collection(f"{label}_资产包", output_root)
        imported = import_package(glb, source_collection, label, materials)
        copies = duplicate_package(imported, output_collection, label)
        source_collection.hide_viewport = True
        source_collection.hide_render = True
        meshes = [obj for obj in copies if obj.type == "MESH"]
        manifest_packages.append({
            "package_id": label,
            "source_glb": str(glb.relative_to(ROOT)),
            "source_glb_sha256": sha256(glb),
            "output_collection": output_collection.name,
            "mesh_count": len(meshes),
            "object_count": len(copies),
            "footprint_size_m": contract["footprint_size_m"],
            "floor_height_m": contract["floor_height_m"],
        })

    non_stair_meshes = [obj.name for obj in bpy.data.objects if obj.type == "MESH" and obj.get("block_id") != "stairs"]
    if non_stair_meshes:
        raise RuntimeError(f"Non-stair meshes found: {non_stair_meshes}")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
    manifest = {
        "asset_id": "ENV-TOWER-STAIRS-12M-SOURCE",
        "version": "v001",
        "block_id": "stairs",
        "source_blend": str(OUTPUT.relative_to(ROOT)),
        "contract": str(CONTRACT.relative_to(ROOT)),
        "production_stage": "formal_blender_source",
        "runtime_reimported": False,
        "contains_non_stair_models": False,
        "packages": manifest_packages,
    }
    MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
