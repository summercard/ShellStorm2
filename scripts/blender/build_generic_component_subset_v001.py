"""Create a new generic scene-component source from the validated battle library.

Retains exactly six reusable components:
- one L-shaped corner wall from the validated Base99 source;
- one standard wall, one door wall, one door leaf;
- two floor tile variants from the validated battle common library.

This is a Blender source-only subset. It does not export GLB, create collision,
or connect any Godot runtime scene.
"""
import bpy
import hashlib
import json
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
BATTLE = ROOT / "assets/art/environments/tower_zones/battle/source/common_components/v006"
BATTLE_BLEND = BATTLE / "env_battle_common_components_source_v006.blend"
CORNER_BLEND = ROOT / "source/art/blender/base_facility_layout/component_packages/architecture/base_corner_l_5m/base_corner_l_5m_source_v024.blend"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
OUT_DIR = ROOT / "assets/art/environments/tower_zones/shared/source/common_components/v001"
OUT_BLEND = OUT_DIR / "generic_scene_components_source_v001.blend"
OUT_CATALOG = OUT_DIR / "component_catalog.json"
OUT_QA = OUT_DIR / "QA_REPORT.md"

# Existing validated package collections and their output mesh names.
BATTLE_TARGETS = {
    "wall_standard_5m": {"category": "通用墙", "asset_id": "ENV-SHARED-GENERIC-WALL-STANDARD-5M", "source_package_id": "ENV-BATTLE-COMMON-WALL-STANDARD-5M"},
    "wall_door_5m": {"category": "门墙", "asset_id": "ENV-SHARED-GENERIC-WALL-DOOR-5M", "source_package_id": "ENV-BATTLE-COMMON-WALL-DOOR-5M"},
    "door_5m": {"category": "门", "asset_id": "ENV-SHARED-GENERIC-DOOR-5M", "source_package_id": "ENV-BATTLE-COMMON-DOOR-5M"},
    "floor_tile_r01_c01": {"category": "地砖", "asset_id": "ENV-SHARED-GENERIC-FLOOR-TILE-R01-C01", "source_package_id": "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01"},
    "floor_tile_r01_c02": {"category": "地砖", "asset_id": "ENV-SHARED-GENERIC-FLOOR-TILE-R01-C02", "source_package_id": "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02"},
}
BATTLE_CATALOG = BATTLE / "component_catalog.json"


def dump(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(value, ensure_ascii=False, indent=2) + "\n"
    path.write_bytes(text.replace("\n", "\r\n").encode("utf-8"))


def hashfile(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def clean_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        if c.name != "Collection":
            bpy.data.collections.remove(c)
    scene = bpy.context.scene
    for child in list(scene.collection.children):
        scene.collection.children.unlink(child)
    return scene


def make_collection(name, parent):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


def copy_materials_and_images(objects):
    for obj in objects:
        if obj.type != "MESH":
            continue
        for index, material in enumerate(list(obj.data.materials)):
            if material is None:
                continue
            existing = bpy.data.materials.get(material.name)
            if existing is not None:
                obj.data.materials[index] = existing
                continue
            copied = material.copy()
            for node in copied.node_tree.nodes if copied.use_nodes and copied.node_tree else []:
                if node.type == "TEX_IMAGE" and node.image:
                    node.image.filepath = str(PALETTE)
                    node.image.source = "FILE"
                    node.interpolation = "Closest"
            obj.data.materials[index] = copied


def copy_collection_objects(source_collection, edit_collection, output_collection, prefix, asset_id, world_offset=(0.0, 0.0, 0.0)):
    source_meshes = [o for o in source_collection.all_objects if o.type == "MESH" and not o.get("collision_only", False)]
    if not source_meshes:
        raise RuntimeError(f"No visual mesh in {source_collection.name}")
    copied = []
    offset = Vector(world_offset)
    for source in source_meshes:
        # Bake the authored world transform minus the source placement into the
        # copied mesh. The object itself then has identity transform, which is
        # the shared-component anchor contract.
        baked_matrix = source.matrix_world.copy()
        baked_matrix.translation -= offset

        edit = source.copy()
        edit.data = source.data.copy()
        edit.data.transform(baked_matrix)
        edit.name = f"{prefix}_制作_{source.name}"
        edit.location = (0.0, 0.0, 0.0)
        edit.rotation_euler = (0.0, 0.0, 0.0)
        edit.scale = (1.0, 1.0, 1.0)
        edit_collection.objects.link(edit)
        edit.hide_render = True
        edit.hide_viewport = True
        copied.append(edit)

        output = source.copy()
        output.data = source.data.copy()
        output.data.transform(baked_matrix)
        output.name = f"{prefix}_输出_{source.name}"
        output.location = (0.0, 0.0, 0.0)
        output.rotation_euler = (0.0, 0.0, 0.0)
        output.scale = (1.0, 1.0, 1.0)
        output_collection.objects.link(output)
        output["room_owned_geometry"] = False
        output["asset_id"] = asset_id
        copied.append(output)
    copy_materials_and_images(copied)
    return [o for o in output_collection.all_objects if o.type == "MESH"]


def bounds(objects):
    points = [obj.matrix_world @ vertex.co for obj in objects for vertex in obj.data.vertices]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    return lo, hi


def set_component_root(output_collection, root_name, asset_id, category):
    root = bpy.data.objects.new(root_name, None)
    output_collection.objects.link(root)
    root["asset_id"] = asset_id
    root["category"] = category
    root["room_owned_geometry"] = False
    for obj in list(output_collection.all_objects):
        if obj == root or obj.type != "MESH":
            continue
        obj.parent = root
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.matrix_local = Matrix.Identity(4)
    return root


def identity_matrix():
    from mathutils import Matrix
    return Matrix.Identity(4)


def create_camera(scene, all_objects):
    lo, hi = bounds([o for o in all_objects if o.type == "MESH"])
    center = (Vector(lo) + Vector(hi)) * 0.5
    extent = max((Vector(hi) - Vector(lo)).length, 2.0)
    camera_data = bpy.data.cameras.new("Camera_Generic_Component_Gallery")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = extent * 1.15
    camera = bpy.data.objects.new("Camera_Generic_Component_Gallery", camera_data)
    scene.collection.objects.link(camera)
    camera.location = center + Vector((0.9, -1.5, 0.9)).normalized() * extent * 2.2
    camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera


def load_objects_from_blend(path, collection_name):
    with bpy.data.libraries.load(str(path), link=False) as (data_from, data_to):
        if collection_name not in data_from.collections:
            raise RuntimeError(f"Missing collection {collection_name} in {path}")
        data_to.collections = [collection_name]
    collection = data_to.collections[0]
    if collection is None:
        raise RuntimeError(f"Cannot load {collection_name}")
    bpy.context.scene.collection.children.link(collection)
    return collection


def load_component_collection(path, collection_name, expected_asset_id=None):
    collection = load_objects_from_blend(path, collection_name)
    if expected_asset_id:
        matching = [o for o in collection.all_objects if o.get("asset_id") == expected_asset_id]
        if matching:
            return collection
    return collection


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.name = "Generic_Component_Library"
    scene["library_role"] = "shared generic scene components"
    scene["runtime_connected"] = False
    scene["collision_authored"] = False
    scene["glb_exported"] = False

    root = scene.collection
    edit_root = make_collection("01_制作组件_通用基础组件", root)
    output_root = make_collection("02_游戏输出_通用基础组件", root)
    gallery_root = make_collection("00_Component_Gallery", root)
    all_rows = []
    all_output_meshes = []
    all_output_roots = []

    # Load the five battle-library packages by collection and copy their authored geometry.
    battle_catalog = json.loads(BATTLE_CATALOG.read_text(encoding="utf-8"))
    battle_rows = {row["slug"]: row for row in battle_catalog}
    battle_source_collection = load_objects_from_blend(BATTLE_BLEND, "02_游戏输出_独立资产包_v003")
    for slug, meta in BATTLE_TARGETS.items():
        source_candidates = [o for o in battle_source_collection.all_objects if o.type == "MESH" and slug in o.name]
        if not source_candidates:
            raise RuntimeError(f"Cannot locate source objects for {slug}")
        class SourceSlice:
            all_objects = source_candidates
            name = f"{slug}_源切片"
        src = SourceSlice()
        edit = make_collection(f"制作_{slug}", edit_root)
        output = make_collection(f"输出_{slug}", output_root)
        asset_id = meta["asset_id"]
        source_offset = battle_rows[slug].get("world_position", [0.0, 0.0, 0.0])
        meshes = copy_collection_objects(src, edit, output, slug, asset_id, source_offset)
        root_obj = set_component_root(output, f"ROOT_{slug}_通用组件", asset_id, meta["category"])
        lo, hi = bounds(meshes)
        row = {
            "component_id": asset_id,
            "slug": slug,
            "category": meta["category"],
            "source_package_id": meta["source_package_id"],
            "source_blend": "assets/art/environments/tower_zones/battle/source/common_components/v006/env_battle_common_components_source_v006.blend",
            "source_collection": src.name,
            "collection": output.name,
            "editable_collection": edit.name,
            "root_object": root_obj.name,
            "bounds_lo_m": lo,
            "bounds_hi_m": hi,
            "bounds_size_m": [hi[i] - lo[i] for i in range(3)],
            "local_origin": [0.0, 0.0, 0.0],
            "front_axis": "+Y",
            "godot_front_axis": "-Z",
            "allowed_rotations_blender_z_deg": [0, 90, 180, 270],
            "collision_owner": "godot_wrapper",
            "palette_uv_layer": "PaletteUV",
            "room_owned_geometry": False,
            "instance_offset": [0.0, 0.0, 0.0],
            "collision_authored": False,
            "glb_exported": False,
            "runtime_connected": False,
            "source_sha256": hashfile(BATTLE_BLEND),
            "selection_reason": "validated battle common component; not reconstructed from the Boss room instance",
            "objects": [o.name for o in meshes],
        }
        all_rows.append(row)
        all_output_meshes.extend(meshes)
        all_output_roots.append(root_obj)

    # Load the already validated Base99 L-corner source and copy only its visual output.
    corner_src = load_objects_from_blend(CORNER_BLEND, "02_游戏输出_整合模型")
    corner_edit = make_collection("制作_base_corner_l_5m", edit_root)
    corner_output = make_collection("输出_base_corner_l_5m", output_root)
    corner_asset_id = "ENV-SHARED-GENERIC-CORNER-L-5M"
    corner_meshes = copy_collection_objects(corner_src, corner_edit, corner_output, "base_corner_l_5m", corner_asset_id)
    corner_root = set_component_root(corner_output, "ROOT_base_corner_l_5m_通用组件", corner_asset_id, "L型转角")
    corner_lo, corner_hi = bounds(corner_meshes)
    corner_row = {
        "component_id": corner_asset_id,
        "slug": "base_corner_l_5m",
        "category": "L型转角",
        "source_package_id": "ENV-TOWER-CORNER-L-5M",
        "source_blend": "source/art/blender/base_facility_layout/component_packages/architecture/base_corner_l_5m/base_corner_l_5m_source_v024.blend",
        "source_collection": corner_src.name,
        "collection": corner_output.name,
        "editable_collection": corner_edit.name,
        "root_object": corner_root.name,
        "bounds_lo_m": corner_lo,
        "bounds_hi_m": corner_hi,
        "bounds_size_m": [corner_hi[i] - corner_lo[i] for i in range(3)],
        "local_origin": [0.0, 0.0, 0.0],
        "front_axis": "+Y",
        "godot_front_axis": "-Z",
        "allowed_rotations_blender_z_deg": [0, 90, 180, 270],
        "collision_owner": "godot_wrapper",
        "palette_uv_layer": "PaletteUV",
        "room_owned_geometry": False,
        "instance_offset": [0.0, 0.0, 0.0],
        "collision_authored": False,
        "glb_exported": False,
        "runtime_connected": False,
        "source_sha256": hashfile(CORNER_BLEND),
        "selection_reason": "validated Base99 generic L-corner component; not reconstructed from the Boss room instance",
        "objects": [o.name for o in corner_meshes],
    }
    all_rows.append(corner_row)
    all_output_meshes.extend(corner_meshes)
    all_output_roots.append(corner_root)
    corner_src.hide_viewport = True
    corner_src.hide_render = True

    # Remove the two temporary linked source collections. The output library must
    # contain only the selected six generic components, not whole source libraries.
    battle_loaded = bpy.data.collections.get("02_游戏输出_独立资产包_v003")
    if battle_loaded is not None:
        bpy.data.collections.remove(battle_loaded, do_unlink=True)
    corner_loaded = bpy.data.collections.get("02_游戏输出_整合模型")
    if corner_loaded is not None:
        bpy.data.collections.remove(corner_loaded, do_unlink=True)

    # Separated gallery: real collection instances, not overlapping source copies.
    x = 0.0
    y = 0.0
    for row in all_rows:
        lo = Vector(row["bounds_lo_m"])
        size = Vector(row["bounds_size_m"])
        if x > 0 and x + size.x > 28:
            x = 0.0
            y += 16.0
        inst = bpy.data.objects.new(f"Preview_{row['slug']}", None)
        gallery_root.objects.link(inst)
        inst.instance_type = "COLLECTION"
        inst.instance_collection = bpy.data.collections[row["collection"]]
        inst.location = (x - lo.x, y - lo.y, 0.0)
        x += max(size.x, 2.0) + 2.0

    create_camera(scene, all_output_meshes)
    scene.world = bpy.data.worlds.new("Generic_Component_Studio")
    scene.world.use_nodes = True
    bg = next(n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.28, 0.31, 0.36, 1.0)
    bg.inputs["Strength"].default_value = 0.45
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(OUT_DIR / "generic_component_gallery_workbench.png")
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True

    catalog = {
        "schema": "shellstorm2.shared_generic_component_catalog.v001",
        "library": "generic_scene_components_source_v001.blend",
        "purpose": "shared reusable L-corner, wall, door wall, door leaf and floor tile source",
        "component_count": len(all_rows),
        "requested_counts": {"L型转角": 1, "通用墙": 1, "门墙": 1, "门": 1, "地砖": 2},
        "source_libraries": [str(BATTLE_BLEND.relative_to(ROOT)).replace("\\", "/"), str(CORNER_BLEND.relative_to(ROOT)).replace("\\", "/")],
        "runtime_connected": False,
        "collision_authored": False,
        "glb_exported": False,
        "ledger_registration": "pending; source subset only",
        "packages": all_rows,
    }
    dump(OUT_CATALOG, catalog)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND), check_existing=False)
    print("GENERIC_COMPONENT_SUBSET_WRITTEN", OUT_BLEND)
    print("GENERIC_COMPONENT_COUNT", len(all_rows))
    print("GENERIC_COMPONENT_ROWS", json.dumps([(r["category"], r["slug"]) for r in all_rows], ensure_ascii=False))


if __name__ == "__main__":
    main()
