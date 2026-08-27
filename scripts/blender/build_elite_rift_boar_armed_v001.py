"""Build the authored visual for elite_rift_boar_armed and export a GLB.

The GLB is presentation-only. Enemy3D continues to own collision, AI, damage,
health, spawning and persistence.
"""

from pathlib import Path
import math

import bpy


ROOT = Path("/Users/summercards/ShellStorm2")
ASSET_ROOT = ROOT / "assets/art/enemies/elite_3d/rift_boar_armed"
SOURCE_PATH = ASSET_ROOT / "source/enm_elite_rift_boar_armed_source_v001.blend"
GLB_PATH = ASSET_ROOT / "components/enm_elite_rift_boar_armed_visual_top3d_v001.glb"


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.name != "Collection":
            bpy.data.collections.remove(collection)
    bpy.context.scene.collection.children.unlink(bpy.data.collections["Collection"])
    bpy.data.collections.remove(bpy.data.collections["Collection"])


def material(name, color, metallic=0.0, roughness=0.55, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    shader = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if emission is not None:
        shader.inputs["Emission Color"].default_value = (*emission, 1.0)
        shader.inputs["Emission Strength"].default_value = 3.2
    return mat


def finish_object(obj, name, mat, parent, collection, bevel=0.0):
    obj.name = name
    obj.data.name = f"{name}_Mesh"
    obj.data.materials.append(mat)
    obj.parent = parent
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    collection.objects.link(obj)
    if bevel > 0.0:
        modifier = obj.modifiers.new("软边", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth_by_angle()
    obj.select_set(False)
    return obj


def add_uv_sphere(name, location, scale, mat, parent, collection):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, location=location)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, name, mat, parent, collection)


def add_box(name, location, scale, mat, parent, collection, rotation=(0, 0, 0), bevel=0.06):
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish_object(obj, name, mat, parent, collection, bevel)


def add_cylinder(name, location, radius, depth, mat, parent, collection, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=radius, depth=depth, location=location, rotation=rotation)
    return finish_object(bpy.context.object, name, mat, parent, collection, 0.025)


def add_cone(name, location, radius1, radius2, depth, mat, parent, collection, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=16, radius1=radius1, radius2=radius2, depth=depth, location=location, rotation=rotation)
    return finish_object(bpy.context.object, name, mat, parent, collection, 0.018)


def main():
    reset_scene()
    SOURCE_PATH.parent.mkdir(parents=True, exist_ok=True)
    GLB_PATH.parent.mkdir(parents=True, exist_ok=True)

    output = bpy.data.collections.new("游戏输出_背枪的裂口爬虫")
    bpy.context.scene.collection.children.link(output)
    root = bpy.data.objects.new("精英根_背枪的裂口爬虫", None)
    output.objects.link(root)
    root["asset_id"] = "ENM-ELITE-RIFT-BOAR-ARMED-3D"
    root["content_id"] = "elite_rift_boar_armed"
    root["blender_forward"] = "-Y"
    root["godot_forward"] = "-Z"
    root["unit"] = "meter"
    root["collision_owner"] = "Enemy3D"
    root["presentation_only"] = True

    body_mat = material("裂口肉体", (0.21, 0.045, 0.055), roughness=0.72)
    shell_mat = material("琥珀甲壳", (0.82, 0.19, 0.035), metallic=0.18, roughness=0.42)
    gun_mat = material("夺取枪身", (0.045, 0.23, 0.27), metallic=0.72, roughness=0.27)
    glow_mat = material("精英能量", (0.02, 0.65, 0.78), metallic=0.1, roughness=0.22, emission=(0.02, 0.72, 0.92))

    body = add_uv_sphere("Core_裂口主体", (0.0, 0.04, 0.76), (0.78, 0.92, 0.60), body_mat, root, output)
    body["semantic_component"] = "core"

    for side in (-1, 1):
        plate = add_uv_sphere(
            f"Shell_侧甲_{'左' if side < 0 else '右'}",
            (side * 0.48, 0.10, 0.91),
            (0.42, 0.72, 0.46),
            shell_mat, root, output,
        )
        plate.rotation_euler.y = side * math.radians(13)
        plate["semantic_component"] = "shell"

    # Front jaw and cyan裂口 make the silhouette readable from the top camera.
    for side in (-1, 1):
        jaw = add_cone(
            f"Appendages_裂口颚_{'左' if side < 0 else '右'}",
            (side * 0.27, -0.89, 0.63), 0.20, 0.055, 0.66,
            shell_mat, root, output, rotation=(math.radians(78), 0, side * math.radians(13)),
        )
        jaw["semantic_component"] = "appendages"
    mouth = add_box("StateVFX_裂口能量", (0.0, -0.82, 0.65), (0.09, 0.10, 0.25), glow_mat, root, output, rotation=(math.radians(10), 0, 0), bevel=0.035)
    mouth["semantic_component"] = "state_vfx"

    # Four broad claws keep the melee-chaser ancestry recognizable.
    for side in (-1, 1):
        for front, y in (("前", -0.42), ("后", 0.48)):
            claw = add_cone(
                f"Appendages_{front}爪_{'左' if side < 0 else '右'}",
                (side * 0.82, y, 0.36), 0.18, 0.045, 0.72,
                shell_mat, root, output,
                rotation=(0, math.radians(90), side * math.radians(8)),
            )
            claw["semantic_component"] = "appendages"

    # The stolen twin-barrel gun is deliberately oversized and mounted high.
    harness = add_box("BackGun_背负枪架", (0.0, 0.18, 1.38), (0.52, 0.40, 0.11), gun_mat, root, output, rotation=(math.radians(9), 0, 0), bevel=0.07)
    harness["semantic_component"] = "weapon_attachment"
    for side in (-1, 1):
        barrel = add_cylinder(
            f"BackGun_副枪管_{'左' if side < 0 else '右'}",
            (side * 0.22, -0.18, 1.62), 0.105, 1.28,
            gun_mat, root, output, rotation=(math.radians(90), 0, 0),
        )
        barrel["semantic_component"] = "weapon_attachment"
        muzzle = add_cylinder(
            f"StateVFX_枪口环_{'左' if side < 0 else '右'}",
            (side * 0.22, -0.84, 1.62), 0.125, 0.11,
            glow_mat, root, output, rotation=(math.radians(90), 0, 0),
        )
        muzzle["semantic_component"] = "state_vfx"
    magazine = add_box("BackGun_能量弹仓", (0.0, 0.34, 1.58), (0.30, 0.20, 0.22), glow_mat, root, output, bevel=0.07)
    magazine["semantic_component"] = "weapon_attachment"

    # Rear fungal horns exaggerate the elite outline without changing collision.
    for side in (-1, 1):
        horn = add_cone(
            f"Appendages_菌角_{'左' if side < 0 else '右'}",
            (side * 0.43, 0.68, 1.39), 0.15, 0.02, 0.54,
            glow_mat, root, output, rotation=(side * math.radians(14), 0, 0),
        )
        horn["semantic_component"] = "appendages"

    # Author the final visual footprint against the unchanged melee_chaser
    # gameplay cylinder. Appendages may touch the silhouette but must not turn
    # the presentation asset into a larger hidden hit target.
    authored_scale = 0.82
    for obj in output.all_objects:
        if obj.type != "MESH":
            continue
        obj.location *= authored_scale
        obj.scale *= authored_scale
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        obj.select_set(False)

    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    bpy.context.scene["asset_id"] = "ENM-ELITE-RIFT-BOAR-ARMED-3D"
    bpy.context.scene["output_collection"] = output.name
    bpy.context.scene["bounds_target_m"] = "<=2.00W x <=1.95D x <=1.75H; Enemy3D owns gameplay collision"
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_PATH))

    bpy.ops.object.select_all(action="DESELECT")
    for obj in output.all_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_extras=True,
    )
    print(f"EXPORTED {GLB_PATH}")


main()
