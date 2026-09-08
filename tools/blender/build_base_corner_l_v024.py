import bpy
import bmesh
import hashlib
import json
from mathutils import Matrix, Vector
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v023.blend"
OUTPUT = ROOT / "source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v024.blend"
ASSET_BLEND = ROOT / "source/art/blender/base_facility_layout/component_packages/architecture/base_corner_l_5m/base_corner_l_5m_source_v024.blend"
PACKAGE_NAME = "117_基地5米L型转角墙_资产包"
SOURCE_COLLECTION_NAME = "117_01_制作组件_已统一材质"
OUTPUT_COLLECTION_NAME = "117_02_游戏输出_整合模型"
COLLISION_COLLECTION_NAME = "117_03_碰撞代理_Godot规格"
ASSET_ID = "ENV-BASE99-CORNER-L-5M"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
MATERIAL_NAME = "02_细腻哑光_青绿大面_117转角墙外链修正版"


def stable_float(value):
    return round(float(value), 7)


def existing_object_signature():
    rows = []
    for obj in sorted(bpy.data.objects, key=lambda item: item.name):
        mesh_payload = None
        if obj.type == "MESH":
            mesh_payload = {
                "vertices": [tuple(stable_float(v) for v in vertex.co) for vertex in obj.data.vertices],
                "polygons": [tuple(poly.vertices) for poly in obj.data.polygons],
                "materials": [material.name if material else None for material in obj.data.materials],
                "uv_layers": [layer.name for layer in obj.data.uv_layers],
            }
        rows.append({
            "name": obj.name,
            "type": obj.type,
            "parent": obj.parent.name if obj.parent else None,
            "matrix": [stable_float(value) for row in obj.matrix_world for value in row],
            "dimensions": [stable_float(value) for value in obj.dimensions],
            "mesh": mesh_payload,
            "modifiers": [(modifier.name, modifier.type) for modifier in obj.modifiers],
            "animation": obj.animation_data.action.name if obj.animation_data and obj.animation_data.action else None,
        })
    payload = json.dumps(rows, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def make_collection(name, parent):
    collection = bpy.data.collections.new(name)
    parent.children.link(collection)
    return collection


def unlink_all(obj):
    for collection in list(obj.users_collection):
        collection.objects.unlink(obj)


def normalized_mesh(source_obj, name, material, short_arm=False):
    mesh = source_obj.data.copy()
    mesh.name = name
    source_min_x = min(vertex.co.x for vertex in mesh.vertices)
    source_center_y = (min(vertex.co.y for vertex in mesh.vertices) + max(vertex.co.y for vertex in mesh.vertices)) * 0.5
    source_min_z = min(vertex.co.z for vertex in mesh.vertices)
    source_size_y = max(vertex.co.y for vertex in mesh.vertices) - min(vertex.co.y for vertex in mesh.vertices)
    source_size_z = max(vertex.co.z for vertex in mesh.vertices) - source_min_z
    thickness_scale = 0.30 / source_size_y
    height_scale = 8.90 / source_size_z
    for vertex in mesh.vertices:
        long_x = vertex.co.x - source_min_x
        long_y = (vertex.co.y - source_center_y) * thickness_scale
        height = (vertex.co.z - source_min_z) * height_scale
        # Blender +Y becomes Godot -Z during glTF Y-up conversion. Both arms'
        # authored ribs must face the inside quadrant (+X/+Y in Blender): the
        # long arm mirrors the template across Y, while the short arm rotates it.
        vertex.co = Vector((-long_y, long_x, height)) if short_arm else Vector((long_x, -long_y, height))
    if not short_arm:
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
    palette_uv = mesh.uv_layers.get("PaletteUV")
    if palette_uv is None:
        raise RuntimeError(f"{source_obj.name} has no PaletteUV")
    mesh.uv_layers.active = palette_uv
    palette_uv.active_render = True
    mesh.materials.clear()
    mesh.materials.append(material)
    mesh.update()
    return mesh


def create_component(source_obj, collection, name, material, short_arm=False):
    obj = bpy.data.objects.new(name, normalized_mesh(source_obj, f"{name}_网格", material, short_arm))
    collection.objects.link(obj)
    obj["asset_id"] = ASSET_ID
    obj["component_role"] = "short_arm" if short_arm else "long_arm"
    obj["origin_contract"] = "inside_corner_bottom"
    obj["forward_axis"] = "Blender +Y / Godot -Z"
    return obj


def create_asset_material(source_obj):
    source_material = source_obj.data.materials[0]
    material = source_material.copy()
    material.name = MATERIAL_NAME
    if not material.use_nodes or material.node_tree is None:
        raise RuntimeError("Authored Blender wall material has no node tree")
    image_nodes = [node for node in material.node_tree.nodes if node.type == "TEX_IMAGE"]
    if not image_nodes:
        raise RuntimeError("Authored Blender wall material has no palette image")
    for node in image_nodes:
        image = node.image.copy()
        image.name = "设施低亮多巴胺色盘_117转角墙外链"
        image.filepath = str(PALETTE)
        image.source = "FILE"
        node.image = image
        node.interpolation = "Closest"
    return material


def create_box(collection, name, minimum, maximum):
    min_x, min_y, min_z = minimum
    max_x, max_y, max_z = maximum
    vertices = [
        (min_x, min_y, min_z), (max_x, min_y, min_z),
        (max_x, max_y, min_z), (min_x, max_y, min_z),
        (min_x, min_y, max_z), (max_x, min_y, max_z),
        (max_x, max_y, max_z), (min_x, max_y, max_z),
    ]
    faces = [
        (0, 3, 2, 1), (4, 5, 6, 7),
        (0, 1, 5, 4), (1, 2, 6, 5),
        (2, 3, 7, 6), (3, 0, 4, 7),
    ]
    mesh = bpy.data.meshes.new(f"{name}_网格")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj["asset_id"] = ASSET_ID
    obj["collision_only"] = True
    obj.display_type = "WIRE"
    obj.hide_render = True
    return obj


def main():
    if Path(bpy.data.filepath).resolve() != SOURCE.resolve():
        raise RuntimeError(f"Expected source {SOURCE}, got {bpy.data.filepath}")
    if bpy.data.collections.get(PACKAGE_NAME) is not None:
        raise RuntimeError(f"Collection already exists: {PACKAGE_NAME}")
    before = existing_object_signature()
    architecture = bpy.data.collections.get("10_建筑结构")
    retained_walls = bpy.data.collections.get("11_四向保留墙体系统_资产包")
    if architecture is None or retained_walls is None:
        raise RuntimeError("Required architecture collections are missing")
    source_obj = next(
        (obj for obj in retained_walls.all_objects if obj.type == "MESH" and obj.name.startswith("普通墙体_主体_金属哑光反光")),
        None,
    )
    if source_obj is None:
        raise RuntimeError("No authored Blender wall source found")

    package = make_collection(PACKAGE_NAME, architecture)
    editable = make_collection(SOURCE_COLLECTION_NAME, package)
    game_output = make_collection(OUTPUT_COLLECTION_NAME, package)
    collision_output = make_collection(COLLISION_COLLECTION_NAME, package)
    package["asset_id"] = ASSET_ID
    package["asset_version"] = "v024"
    package["module_contract"] = "Godot 5m L corner; visual 8.9m; collision reserved at 9m"
    package["local_origin"] = "inside corner at floor Z=0"
    package["bounds_m"] = "5.15 x 5.15 x 8.9 (two 5m arms including 0.15m outer half-thickness)"
    package["visual_arm_thickness_m"] = 0.30
    package["logical_height_m"] = 9.0
    package["source_visual_language"] = "11_四向保留墙体系统_资产包"
    package["export_status"] = "blender_source_complete_not_exported"

    asset_material = create_asset_material(source_obj)
    source_long = create_component(source_obj, editable, "基地5米L型转角墙_长臂_制作组件", asset_material, False)
    source_short = create_component(source_obj, editable, "基地5米L型转角墙_短臂_制作组件", asset_material, True)
    editable.hide_render = True
    editable.hide_viewport = True

    output_long = source_long.copy()
    output_long.data = source_long.data.copy()
    output_long.name = "基地5米L型转角墙_长臂_输出"
    output_short = source_short.copy()
    output_short.data = source_short.data.copy()
    output_short.name = "基地5米L型转角墙_短臂_输出"
    game_output.objects.link(output_long)
    game_output.objects.link(output_short)

    bpy.ops.object.select_all(action="DESELECT")
    output_long.select_set(True)
    output_short.select_set(True)
    bpy.context.view_layer.objects.active = output_long
    bpy.ops.object.join()
    output_long.name = "基地5米L型转角墙_主体_金属哑光反光"
    output_long.data.name = "基地5米L型转角墙_主体_网格"
    output_long["asset_id"] = ASSET_ID
    output_long["asset_version"] = "v024"
    output_long["visual_bounds_m"] = "5.0 x 5.0 x 8.9"
    output_long["collision_contract"] = "Godot wrapper supplies two 5m x 9m x 0.3m wall-arm blockers"
    output_long["export_ready"] = True

    collision_long = create_box(
        collision_output,
        "COLLISION_基地5米L型转角墙_长臂",
        (0.0, -0.15, 0.0),
        (5.0, 0.15, 9.0),
    )
    collision_short = create_box(
        collision_output,
        "COLLISION_基地5米L型转角墙_短臂",
        (-0.15, 0.0, 0.0),
        (0.15, 5.0, 9.0),
    )
    collision_output.hide_render = True

    for obj in (source_long, source_short, output_long):
        obj.location = Vector((0.0, 0.0, 0.0))
        obj.rotation_euler = Vector((0.0, 0.0, 0.0))
        obj.scale = Vector((1.0, 1.0, 1.0))

    existing_names = {
        source_long.name, source_short.name, output_long.name,
        collision_long.name, collision_short.name,
    }
    after_rows = []
    for obj in sorted((obj for obj in bpy.data.objects if obj.name not in existing_names), key=lambda item: item.name):
        mesh_payload = None
        if obj.type == "MESH":
            mesh_payload = {
                "vertices": [tuple(stable_float(v) for v in vertex.co) for vertex in obj.data.vertices],
                "polygons": [tuple(poly.vertices) for poly in obj.data.polygons],
                "materials": [material.name if material else None for material in obj.data.materials],
                "uv_layers": [layer.name for layer in obj.data.uv_layers],
            }
        after_rows.append({
            "name": obj.name,
            "type": obj.type,
            "parent": obj.parent.name if obj.parent else None,
            "matrix": [stable_float(value) for row in obj.matrix_world for value in row],
            "dimensions": [stable_float(value) for value in obj.dimensions],
            "mesh": mesh_payload,
            "modifiers": [(modifier.name, modifier.type) for modifier in obj.modifiers],
            "animation": obj.animation_data.action.name if obj.animation_data and obj.animation_data.action else None,
        })
    after_payload = json.dumps(after_rows, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    after = hashlib.sha256(after_payload.encode("utf-8")).hexdigest()
    if before != after:
        raise RuntimeError(f"Locked scene changed: {before} != {after}")
    package["locked_signature_before"] = before
    package["locked_signature_after"] = after
    package["locked_match"] = True

    # Keep the reusable local-origin package out of the authored room render.
    package.hide_render = True
    package.hide_viewport = True
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

    # Also save a clean, independently maintainable asset file so the standard
    # validator can inspect only this package without the full layout scene.
    asset_scene = bpy.data.scenes.new("基地5米L型转角墙_独立资产")
    bpy.context.window.scene = asset_scene
    asset_scene.collection.children.link(package)
    for scene in list(bpy.data.scenes):
        if scene != asset_scene:
            bpy.data.scenes.remove(scene)
    keep_collections = {package, editable, game_output, collision_output}
    for collection in list(bpy.data.collections):
        if collection not in keep_collections:
            bpy.data.collections.remove(collection)
    keep_objects = set(package.all_objects)
    for obj in list(bpy.data.objects):
        if obj not in keep_objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for material in list(bpy.data.materials):
        if material.users == 0:
            bpy.data.materials.remove(material)
    for image in list(bpy.data.images):
        if image.users == 0:
            bpy.data.images.remove(image)
    editable.name = "01_制作组件_已统一材质"
    game_output.name = "02_游戏输出_整合模型"
    collision_output.name = "03_碰撞代理_Godot规格"
    package.hide_render = False
    package.hide_viewport = False
    editable.hide_render = True
    editable.hide_viewport = True
    collision_output.hide_render = True
    bpy.ops.wm.save_as_mainfile(filepath=str(ASSET_BLEND))
    print(json.dumps({
        "output": str(OUTPUT),
        "independent_asset_blend": str(ASSET_BLEND),
        "package": PACKAGE_NAME,
        "asset_id": ASSET_ID,
        "locked_match": before == after,
        "output_object": output_long.name,
        "dimensions": [round(value, 4) for value in output_long.dimensions],
        "collision_dimensions": [
            [round(value, 4) for value in collision_long.dimensions],
            [round(value, 4) for value in collision_short.dimensions],
        ],
        "triangles": sum(len(poly.vertices) - 2 for poly in output_long.data.polygons),
        "materials": [material.name for material in output_long.data.materials if material],
        "uv_layers": [layer.name for layer in output_long.data.uv_layers],
    }, ensure_ascii=False, indent=2))


main()
