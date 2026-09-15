import argparse
import bpy
import bmesh
import hashlib
import json
import struct
import sys
from pathlib import Path


PROJECT = Path("/Users/summercards/ShellStorm2")
SOURCE = PROJECT / "assets/art/environments/tower_descent_3d/source/stairs_12m/stairwell_art_v021/env_tower_stairwell_dual_art_source_v021.blend"
EXPORT_ROOT = SOURCE.parent / "export/v021"
COMPONENT_ROOT = PROJECT / "assets/art/environments/tower_descent_3d/components"
LEAVES = [
    "通用墙组件_资产包",
    "通用地板组件_资产包",
    "通用楼梯组件_资产包",
    "墙面装甲与结构框_装饰组件",
    "地面导光与警示_装饰组件",
    "工业管线_装饰组件",
    "灯带与发光几何_装饰组件",
    "楼层标识与海报_装饰组件",
    "控制盒_装饰组件",
    "固定绿植_装饰组件",
]
SPECS = {
    "A": {
        "tag": "A_100_to_99",
        "source_root": "楼梯A_100至99层_装配根",
        "asset_id": "ENV-TOWER-STAIRWELL-ROOFTOP-12M",
        "root_name": "Stairwell_Rooftop_12M_v002_ROOT",
        "derived": "env_tower_stairwell_rooftop_12m_runtime_v002.blend",
        "glb": "env_tower_stairwell_rooftop_12m_top3d_v002.glb",
    },
    "B": {
        "tag": "B_99_to_98",
        "source_root": "楼梯B_99至98层_装配根",
        "asset_id": "ENV-TOWER-STAIRWELL-GENERIC-12M",
        "root_name": "Stairwell_Generic_12M_v002_ROOT",
        "derived": "env_tower_stairwell_generic_12m_runtime_v002.blend",
        "glb": "env_tower_stairwell_generic_12m_top3d_v002.glb",
    },
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean_name(name: str) -> str:
    if "__" in name:
        name = name.split("__", 1)[1]
    return name.replace("_游戏输出_v017输出", "").replace("_v017输出", "")


def triangulate(mesh: bpy.types.Mesh) -> None:
    bm = bmesh.new()
    bm.from_mesh(mesh)
    faces = [face for face in bm.faces if len(face.verts) > 3]
    if faces:
        bmesh.ops.triangulate(bm, faces=faces)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def join_group(objects: list[bpy.types.Object], name: str, collision_role: str) -> bpy.types.Object:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    active = objects[0]
    bpy.context.view_layer.objects.active = active
    bpy.ops.object.join()
    active.name = name
    active.data.name = f"{name}_Mesh"
    active["runtime_collision_role"] = collision_role
    active["source_output_mesh_count"] = len(objects)
    return active


def parse_glb(path: Path) -> dict:
    data = path.read_bytes()
    offset = 12
    document = None
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset:offset + length]
        offset += length
        if kind == 0x4E4F534A:
            document = json.loads(chunk.rstrip(b" \0"))
    if document is None:
        raise RuntimeError("GLB JSON chunk missing")
    return document


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--assembly", choices=sorted(SPECS), required=True)
    cli = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(cli)
    spec = SPECS[args.assembly]
    EXPORT_ROOT.mkdir(parents=True, exist_ok=True)
    COMPONENT_ROOT.mkdir(parents=True, exist_ok=True)

    source_root = bpy.data.objects[spec["source_root"]]
    root_inverse = source_root.matrix_world.inverted()
    records = []
    for collection_name in LEAVES:
        for obj in bpy.data.collections[collection_name].objects:
            if obj.type != "MESH" or obj.get("stairwell_instance") != spec["tag"]:
                continue
            obj_copy = obj.copy()
            obj_copy.data = obj.data.copy()
            records.append((obj_copy, collection_name, root_inverse @ obj.matrix_world))
    if len(records) != 382:
        raise RuntimeError(f"Expected 382 output meshes, found {len(records)}")

    output = bpy.data.collections.new("02_游戏输出_整合模型")
    bpy.context.scene.collection.children.link(output)
    export_root = bpy.data.objects.new(spec["root_name"], None)
    export_root["asset_id"] = spec["asset_id"]
    export_root["asset_version"] = "v002"
    export_root["blender_source_version"] = "v021"
    export_root["block_id"] = "stairs"
    export_root["unit_contract"] = "1 Blender unit = 1 meter"
    export_root["godot_forward"] = "+X local before runtime yaw"
    output.objects.link(export_root)

    exported = []
    walkable_count = 0
    enclosure_count = 0
    for obj, collection_name, local_matrix in records:
        obj.animation_data_clear()
        obj.parent = export_root
        obj.matrix_world = local_matrix
        name = clean_name(obj.name)
        source_locked = str(obj.get("SS2_from_locked_source", ""))
        if collection_name == "通用墙组件_资产包":
            name = f"EnclosureWall_{name}"
            obj["runtime_collision_role"] = "enclosure"
            enclosure_count += 1
        elif collection_name == "通用地板组件_资产包" and source_locked.startswith("地板."):
            name = f"FloorWalkable_{name}"
            obj["runtime_collision_role"] = "walkable"
            walkable_count += 1
        elif collection_name == "通用楼梯组件_资产包" and "Walkable" in name:
            role = "UpperFlight_Walkable" if local_matrix.translation.z > -3.0 else "LowerFlight_Walkable"
            name = f"{role}_{name}"
            obj["runtime_collision_role"] = "walkable"
            walkable_count += 1
        else:
            obj["runtime_collision_role"] = "none"
        obj.name = name
        obj["source_component_collection"] = collection_name
        obj["source_art_version"] = "v021"
        triangulate(obj.data)
        output.objects.link(obj)
        exported.append(obj)

    source_output_count = len(exported)
    wall_objects = [obj for obj in exported if obj.get("runtime_collision_role") == "enclosure"]
    walkable_objects = [obj for obj in exported if obj.get("runtime_collision_role") == "walkable"]
    visual_objects = [obj for obj in exported if obj.get("runtime_collision_role") == "none"]
    exported = [
        join_group(wall_objects, "EnclosureWall_VisualCollision", "enclosure"),
        join_group(walkable_objects, "FloorAndFlight_Walkable", "walkable"),
        join_group(visual_objects, "StairwellArt_VisualOnly", "none"),
    ]
    enclosure_count = 1
    walkable_count = 1

    keep = set(exported + [export_root])
    for obj in list(bpy.data.objects):
        if obj not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections):
        if collection != output:
            bpy.data.collections.remove(collection)

    bpy.context.scene["asset_id"] = spec["asset_id"]
    bpy.context.scene["asset_version"] = "v002"
    bpy.context.scene["blender_source_version"] = "v021"
    bpy.context.scene["source_output_mesh_count"] = source_output_count
    bpy.context.scene["optimized_mesh_count"] = len(exported)
    bpy.context.scene["walkable_collision_source_count"] = walkable_count
    bpy.context.scene["enclosure_collision_source_count"] = enclosure_count
    bpy.context.scene["palette"] = "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

    derived = EXPORT_ROOT / spec["derived"]
    glb = COMPONENT_ROOT / spec["glb"]
    bpy.ops.wm.save_as_mainfile(filepath=str(derived), compress=True)
    bpy.ops.wm.open_mainfile(filepath=str(derived))
    bpy.ops.object.select_all(action="DESELECT")
    for obj in bpy.data.collections["02_游戏输出_整合模型"].objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = bpy.data.objects[spec["root_name"]]
    bpy.ops.export_scene.gltf(
        filepath=str(glb),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_extras=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    document = parse_glb(glb)
    if document.get("images") or document.get("textures"):
        raise RuntimeError("Exported GLB contains embedded images or textures")
    result = {
        "asset_id": spec["asset_id"],
        "version": "v002",
        "source_blend": str(SOURCE.relative_to(PROJECT)),
        "source_sha256": sha256(SOURCE),
        "derived_blend": str(derived.relative_to(PROJECT)),
        "derived_sha256": sha256(derived),
        "glb": str(glb.relative_to(PROJECT)),
        "glb_sha256": sha256(glb),
        "source_output_mesh_count": source_output_count,
        "optimized_mesh_count": len(exported),
        "walkable_collision_source_count": walkable_count,
        "enclosure_collision_source_count": enclosure_count,
        "glb_node_count": len(document.get("nodes", [])),
        "glb_mesh_count": len(document.get("meshes", [])),
        "glb_material_count": len(document.get("materials", [])),
        "glb_image_count": len(document.get("images", [])),
        "glb_texture_count": len(document.get("textures", [])),
        "runtime_collision_owner": "src/world3d/TowerDescent3D.gd",
        "palette_post_import": "res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd",
    }
    manifest = EXPORT_ROOT / f"{args.assembly.lower()}_godot_export_manifest.json"
    manifest.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
