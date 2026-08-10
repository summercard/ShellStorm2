import argparse
import math
from pathlib import Path

import bpy
from mathutils import Vector


CONFIG = {
    "workshop": {
        "name": "枪械工坊",
        "chair_name": "赛博维修圆凳",
        "chair_prefix": "STOOL",
        "base_scale": (2.05 * 1.60) / 2.335,
        "x_structural": {"BACK", "CAB", "STRUCT", "TOP"},
        "depth_structural": {"CAB", "STRUCT", "TOP"},
        "backboard": {"BACK"},
        "metal_mapping": {(3, 2): (2, 3), (5, 2): (4, 3), (7, 2): (6, 3)},
        "chair_accent_mapping": {},
    },
    "mission": {
        "name": "远征情报终端",
        "chair_name": "战术指挥椅",
        "chair_prefix": "CHAIR",
        "base_scale": (2.15 * 1.60) / 2.45,
        "x_structural": {"BASE", "BOARD", "FRAME", "MAP", "SCREEN", "TOP"},
        "depth_structural": {"BASE", "BOARD", "TOP"},
        "backboard": {"FRAME", "MAP", "SCREEN"},
        "metal_mapping": {(3, 2): (2, 3)},
        "chair_accent_mapping": {},
    },
}


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--asset", choices=CONFIG, required=True)
    parser.add_argument("--mode", choices=("facility", "chair"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--preview", type=Path, required=True)
    return parser.parse_args(bpy.app.driver_namespace.get("argv", []))


def prefix(obj):
    return obj.name.split("_", 1)[0]


def semantic_group(obj, structural_prefixes):
    name = obj.name
    tokens = set(structural_prefixes) | {
        "CRATE",
        "DEVICE",
        "LAMP",
        "PARTS",
        "TERM",
        "TOOL",
        "PROPS",
        "CTRL",
        "RADAR",
    }
    for token in sorted(tokens):
        if name.startswith(f"{token}_") or f"_{token}_" in name:
            return token
    return prefix(obj)


def bounds(objects):
    bpy.context.view_layer.update()
    minimum = Vector((math.inf, math.inf, math.inf))
    maximum = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objects:
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            minimum.x = min(minimum.x, point.x)
            minimum.y = min(minimum.y, point.y)
            minimum.z = min(minimum.z, point.z)
            maximum.x = max(maximum.x, point.x)
            maximum.y = max(maximum.y, point.y)
            maximum.z = max(maximum.z, point.z)
    return minimum, maximum


def apply_scale(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def scale_all(objects, factor):
    for obj in objects:
        obj.location *= factor
        obj.scale *= factor
        apply_scale(obj)


def palette_cell(uv):
    return min(9, max(0, int(uv.x * 10))), min(9, max(0, int(uv.y * 10)))


def remap_metal_palette(objects, mapping):
    changed = 0
    for obj in objects:
        uv_layer = obj.data.uv_layers.get("PaletteUV") or obj.data.uv_layers.active
        if uv_layer is None:
            continue
        uv_layer.name = "PaletteUV"
        for polygon in obj.data.polygons:
            if polygon.material_index >= len(obj.material_slots) or not polygon.loop_indices:
                continue
            material = obj.material_slots[polygon.material_index].material
            if material is None or not (
                "精工金属" in material.name or material.name.startswith("mat_metal")
            ):
                continue
            average = sum(
                (uv_layer.data[index].uv for index in polygon.loop_indices),
                start=uv_layer.data[polygon.loop_indices[0]].uv.copy() * 0.0,
            ) / len(polygon.loop_indices)
            current = palette_cell(average)
            if current not in mapping:
                continue
            target = mapping[current]
            target_uv = ((target[0] + 0.5) / 10.0, (target[1] + 0.5) / 10.0)
            for index in polygon.loop_indices:
                uv_layer.data[index].uv = target_uv
                changed += 1
    return changed


def remap_chair_accents(objects, mapping):
    changed = 0
    if not mapping:
        return changed
    for obj in objects:
        if "SeatCushion" not in obj.name:
            continue
        uv_layer = obj.data.uv_layers.get("PaletteUV") or obj.data.uv_layers.active
        if uv_layer is None:
            continue
        for polygon in obj.data.polygons:
            if not polygon.loop_indices:
                continue
            average = sum(
                (uv_layer.data[index].uv for index in polygon.loop_indices),
                start=uv_layer.data[polygon.loop_indices[0]].uv.copy() * 0.0,
            ) / len(polygon.loop_indices)
            current = palette_cell(average)
            if current not in mapping:
                continue
            target = mapping[current]
            target_uv = ((target[0] + 0.5) / 10.0, (target[1] + 0.5) / 10.0)
            for index in polygon.loop_indices:
                uv_layer.data[index].uv = target_uv
                changed += 1
    return changed


def expand_width(objects, structural_prefixes, target_width=5.0):
    structural_objects = [obj for obj in objects if prefix(obj) in structural_prefixes]
    for _iteration in range(3):
        minimum, maximum = bounds(structural_objects)
        current_width = maximum.x - minimum.x
        if abs(current_width - target_width) < 0.002:
            break
        factor = target_width / current_width
        center = (minimum.x + maximum.x) * 0.5
        groups = {}
        for obj in objects:
            groups.setdefault(semantic_group(obj, structural_prefixes), []).append(obj)
        for group_name, members in groups.items():
            if group_name in structural_prefixes:
                for obj in members:
                    obj.location.x = center + (obj.location.x - center) * factor
                    if prefix(obj) in structural_prefixes and obj.dimensions.x >= 0.18:
                        obj.scale.x *= factor
                        apply_scale(obj)
                continue
            group_minimum, group_maximum = bounds(members)
            group_center = (group_minimum.x + group_maximum.x) * 0.5
            target_center = center + (group_center - center) * factor
            for obj in members:
                obj.location.x += target_center - group_center
    target_minimum, target_maximum = bounds(structural_objects)
    groups = {}
    for obj in objects:
        group_name = semantic_group(obj, structural_prefixes)
        groups.setdefault(group_name, []).append(obj)
    for group_name, members in groups.items():
        if group_name in structural_prefixes:
            continue
        group_minimum, group_maximum = bounds(members)
        shift = 0.0
        if group_minimum.x < target_minimum.x:
            shift = target_minimum.x - group_minimum.x
        if group_maximum.x + shift > target_maximum.x:
            shift += target_maximum.x - (group_maximum.x + shift)
        for obj in members:
            obj.location.x += shift


def expand_depth(objects, table_prefixes, backboard_prefixes):
    minimum, maximum = bounds(objects)
    center = (minimum.y + maximum.y) * 0.5
    before_depth = maximum.y - minimum.y
    structural_prefixes = set(table_prefixes) | set(backboard_prefixes)
    groups = {}
    for obj in objects:
        groups.setdefault(semantic_group(obj, structural_prefixes), []).append(obj)
    for group_name, members in groups.items():
        if group_name in structural_prefixes:
            for obj in members:
                obj.location.y = center + (obj.location.y - center) * 2.0
                actual_prefix = prefix(obj)
                if actual_prefix in table_prefixes and obj.dimensions.y >= 0.08:
                    obj.scale.y *= 2.0
                    apply_scale(obj)
                elif actual_prefix in backboard_prefixes and obj.dimensions.y >= 0.015:
                    obj.scale.y *= 2.0
                    apply_scale(obj)
            continue
        group_minimum, group_maximum = bounds(members)
        group_center = (group_minimum.y + group_maximum.y) * 0.5
        target_center = center + (group_center - center) * 2.0
        for obj in members:
            obj.location.y += target_center - group_center
    after_minimum, after_maximum = bounds(objects)
    return before_depth, after_maximum.y - after_minimum.y


def center_and_ground(objects):
    minimum, maximum = bounds(objects)
    offset = Vector((-(minimum.x + maximum.x) * 0.5, -(minimum.y + maximum.y) * 0.5, -minimum.z))
    for obj in objects:
        obj.location += offset
    bpy.context.view_layer.update()


def remove_objects(objects):
    for obj in list(objects):
        bpy.data.objects.remove(obj, do_unlink=True)


def clear_output_collection():
    output = bpy.data.collections.get("02_游戏输出_整合模型")
    if output is None:
        output = bpy.data.collections.new("02_游戏输出_整合模型")
    else:
        remove_objects(list(output.all_objects))
    return output


def evaluated_copy(source, collection, depsgraph):
    evaluated = source.evaluated_get(depsgraph)
    mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
    mesh.transform(source.matrix_world)
    copy = bpy.data.objects.new(source.name.removesuffix(".001"), mesh)
    collection.objects.link(copy)
    return copy


def remove_unused_material_slots(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.material_slot_remove_unused()


def build_integrated_output(source_objects, output, asset_name):
    depsgraph = bpy.context.evaluated_depsgraph_get()
    copies = [evaluated_copy(obj, output, depsgraph) for obj in source_objects]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in copies:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = f"{asset_name}_主体_金属哑光反光"
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    emission_faces = 0
    for polygon in body.data.polygons:
        material = body.data.materials[polygon.material_index] if polygon.material_index < len(body.data.materials) else None
        is_emissive = material is not None and (
            "自发光" in material.name
            or "UI灯光" in material.name
            or material.name.startswith("mat_emissive")
        )
        polygon.select = is_emissive
        emission_faces += int(is_emissive)
    emissive = None
    if emission_faces:
        before = set(output.objects)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        emissive = next(obj for obj in output.objects if obj not in before and obj != body)
        emissive.name = f"{asset_name}_UI灯光_柔和自发光"
    remove_unused_material_slots(body)
    if emissive is not None:
        remove_unused_material_slots(emissive)
    for obj in [body, emissive]:
        if obj is None:
            continue
        uv_layer = obj.data.uv_layers.get("PaletteUV") or obj.data.uv_layers.active
        if uv_layer is not None:
            uv_layer.name = "PaletteUV"
    return [obj for obj in (body, emissive) if obj is not None]


def organize_collections(source, output, asset_name):
    root = next((collection for collection in bpy.data.collections if collection.name.endswith("中文资产管")), None)
    if root is None:
        root = bpy.data.collections.new(f"{asset_name}_中文资产管理")
        bpy.context.scene.collection.children.link(root)
    root.name = f"{asset_name}_中文资产管理"
    source.name = "01_制作组件_已统一材质"
    output.name = "02_游戏输出_整合模型"
    if source.name not in root.children:
        root.children.link(source)
    if output.name not in root.children:
        root.children.link(output)
    for parent in list(bpy.context.scene.collection.children):
        if parent in (root,):
            continue
        if parent == source or parent == output:
            bpy.context.scene.collection.children.unlink(parent)
    source.hide_viewport = True
    source.hide_render = True
    output.hide_viewport = False
    output.hide_render = False


def purge_unused_materials():
    for material in list(bpy.data.materials):
        if material.users == 0:
            bpy.data.materials.remove(material)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def render_preview(output_objects, path):
    minimum, maximum = bounds(output_objects)
    size = maximum - minimum
    center = (minimum + maximum) * 0.5
    temp = bpy.data.collections.new("TEMP_PREVIEW")
    bpy.context.scene.collection.children.link(temp)
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    temp.objects.link(camera)
    distance = max(size.x, size.y, size.z) * 1.65
    camera.location = center + Vector((distance * 0.78, -distance, distance * 0.58))
    look_at(camera, center + Vector((0, 0, size.z * 0.05)))
    camera_data.lens = 58
    bpy.context.scene.camera = camera
    for name, location, energy, color, scale in (
        ("Key", center + Vector((-size.x, -size.y, size.z * 1.6)), 1150, (0.55, 0.78, 1.0), max(size.x, size.y)),
        ("Fill", center + Vector((size.x, -size.y * 0.3, size.z)), 800, (0.85, 0.38, 1.0), max(size.x, size.y) * 0.8),
        ("Rim", center + Vector((0, size.y, size.z * 1.5)), 1050, (1.0, 0.42, 0.18), max(size.x, size.y) * 0.7),
    ):
        light_data = bpy.data.lights.new(name, "AREA")
        energy_scale = max(0.08, min(1.0, max(size.x, size.y, size.z) / 5.0))
        light_data.energy = energy * energy_scale
        light_data.color = color
        light_data.shape = "DISK"
        light_data.size = max(1.0, scale)
        light = bpy.data.objects.new(name, light_data)
        light.location = location
        look_at(light, center)
        temp.objects.link(light)
    bpy.ops.mesh.primitive_plane_add(size=max(size.x, size.y) * 3.0, location=(0, 0, minimum.z - 0.01))
    ground = bpy.context.object
    for collection in list(ground.users_collection):
        collection.objects.unlink(ground)
    temp.objects.link(ground)
    ground_material = bpy.data.materials.new("PreviewGround")
    ground_material.diffuse_color = (0.018, 0.025, 0.05, 1.0)
    ground.data.materials.append(ground_material)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(path)
    if scene.world is None:
        scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.color = (0.008, 0.012, 0.025)
    scene.view_settings.look = "AgX - Medium High Contrast"
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.render.render(write_still=True)


def main(arguments):
    config = CONFIG[arguments.asset]
    source = bpy.data.collections.get("01_制作组件_已统一材质")
    if source is None:
        raise RuntimeError("Missing 01_制作组件_已统一材质 collection")
    source.hide_viewport = False
    source.hide_render = False
    source_objects = [obj for obj in source.all_objects if obj.type == "MESH"]
    chair_objects = [obj for obj in source_objects if config["chair_prefix"] in obj.name]
    if not chair_objects:
        raise RuntimeError(f"No {config['chair_prefix']} chair components found")
    if arguments.mode == "facility":
        remove_objects(chair_objects)
        objects = [obj for obj in source.all_objects if obj.type == "MESH"]
        asset_name = config["name"]
    else:
        remove_objects([obj for obj in source_objects if obj not in chair_objects])
        objects = [obj for obj in source.all_objects if obj.type == "MESH"]
        asset_name = config["chair_name"]
    scale_all(objects, config["base_scale"])
    remapped = remap_metal_palette(objects, config["metal_mapping"])
    if arguments.mode == "chair":
        remapped += remap_chair_accents(objects, config["chair_accent_mapping"])
    if arguments.mode == "facility":
        desk_top_before = max(
            obj.location.z + obj.dimensions.z * 0.5 for obj in objects if prefix(obj) == "TOP"
        )
        expand_width(objects, config["x_structural"], 5.0)
        depth_before, depth_after = expand_depth(objects, config["depth_structural"], config["backboard"])
    else:
        desk_top_before = 0.0
        depth_before = bounds(objects)[1].y - bounds(objects)[0].y
        depth_after = depth_before
    center_and_ground(objects)
    output = clear_output_collection()
    output_objects = build_integrated_output(objects, output, asset_name)
    organize_collections(source, output, asset_name)
    purge_unused_materials()
    final_minimum, final_maximum = bounds(output_objects)
    bpy.context.scene["asset_name_cn"] = asset_name
    bpy.context.scene["asset_revision"] = "volume_v002"
    bpy.context.scene["asset_forward_axis"] = "Godot local -Z"
    bpy.context.scene["palette_revision"] = "dark_violet_metal_v002"
    bpy.context.scene["palette_uv_remapped_loops"] = remapped
    bpy.context.scene["facility_width_m"] = round(final_maximum.x - final_minimum.x, 4)
    bpy.context.scene["facility_depth_before_m"] = round(depth_before, 4)
    bpy.context.scene["facility_depth_after_m"] = round(depth_after, 4)
    bpy.context.scene["desktop_height_locked_m"] = round(desk_top_before, 4)
    bpy.context.scene["backboard_thickness_multiplier"] = 2.0 if arguments.mode == "facility" else 1.0
    bpy.context.scene["chair_embedded"] = False
    bpy.ops.file.pack_all()
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(arguments.output), compress=True)
    render_preview(output_objects, arguments.preview)
    print(
        "BUILT",
        asset_name,
        "MODE",
        arguments.mode,
        "BOUNDS",
        tuple(round(value, 4) for value in final_minimum),
        tuple(round(value, 4) for value in final_maximum),
        "DESKTOP_HEIGHT",
        round(desk_top_before, 4),
        "DEPTH",
        round(depth_before, 4),
        "->",
        round(depth_after, 4),
        "REMAPPED",
        remapped,
    )


if __name__ == "__main__":
    import sys

    separator = sys.argv.index("--") if "--" in sys.argv else len(sys.argv)
    bpy.app.driver_namespace["argv"] = sys.argv[separator + 1 :]
    main(parse_args())
