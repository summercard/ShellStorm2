"""Build a non-destructive Blender assembly of the live Base 99 runtime layout.

Run with:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python \
    scripts/blender/build_base_facility_runtime_layout_v002.py

Sources of truth, in precedence order:
1. runtime transforms dumped from scenes/TowerDescent3D.tscn
2. DungeonRoom3D's generated 99F shell and floor alignment
3. env_base_facility_art_layout_top3d_v001.tscn for structural modules
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


PROJECT = Path(__file__).resolve().parents[2]
OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_v002.blend"
OUTPUT_PREVIEW = PROJECT / "outputs/verification/base_facility_runtime_layout_blender_v002.png"

PROPS = PROJECT / "assets/art/props/base_world_3d/components"
ENV = PROJECT / "assets/art/environments/base_facility_3d/components"

ASSETS = {
    "mission": PROPS / "mission_operations/prp_base_mission_operations_visual_top3d_v005.glb",
    "workshop": PROPS / "weapon_workshop/prp_base_weapon_workshop_visual_top3d_v005.glb",
    "vending": PROPS / "vending_machine/prp_base_vending_machine_visual_top3d_v003.glb",
    "locker": PROPS / "locker_station/prp_base_locker_station_visual_top3d_v004.glb",
    "retro": PROPS / "retro_tv_station/prp_base_retro_tv_station_visual_top3d_v004.glb",
    "stool": PROPS / "workshop_stool/prp_base_workshop_stool_visual_top3d_v003.glb",
    "chair": PROPS / "mission_command_chair/prp_base_mission_command_chair_visual_top3d_v003.glb",
    "floor_plain": ENV / "env_base99_floor_plain_5m/env_base99_floor_plain_5m_visual_top3d_v001.glb",
    "floor_rivet": ENV / "env_base99_floor_rivet_5m/env_base99_floor_rivet_5m_visual_top3d_v001.glb",
    "wall_plain": ENV / "env_base99_wall_plain_5x9/env_base99_wall_plain_5x9_visual_top3d_v001.glb",
    "wall_window": ENV / "env_base99_wall_window_5x9/env_base99_wall_window_5x9_visual_top3d_v001.glb",
    "wall_door": ENV / "env_base99_wall_door_5x9/env_base99_wall_door_5x9_visual_top3d_v001.glb",
    "door_lift": ENV / "env_base99_door_lift_2p2x2p5/env_base99_door_lift_2p2x2p5_visual_top3d_v001.glb",
    "mezzanine": ENV / "env_base99_mezzanine_20x10_z5/env_base99_mezzanine_20x10_z5_visual_top3d_v003.glb",
    "stair_l": ENV / "env_base99_stair_l_z5/env_base99_stair_l_z5_visual_top3d_v004.glb",
    "stair_exterior": ENV / "env_base99_stair_exterior_h4/env_base99_stair_exterior_h4_visual_top3d_v002.glb",
    "underdeck": ENV / "env_base99_mezzanine_underdeck_blocker/env_base99_mezzanine_underdeck_blocker_visual_top3d_v003.glb",
}


def collection(name: str, parent: bpy.types.Collection | None = None) -> bpy.types.Collection:
    value = bpy.data.collections.get(name)
    if value is None:
        value = bpy.data.collections.new(name)
        (parent.children if parent else bpy.context.scene.collection.children).link(value)
    return value


def link_only(obj: bpy.types.Object, target: bpy.types.Collection) -> None:
    for owner in list(obj.users_collection):
        owner.objects.unlink(obj)
    target.objects.link(obj)


def godot_to_blender(location: tuple[float, float, float]) -> tuple[float, float, float]:
    """Inverse of Blender glTF export: (bx, by, bz) -> (gx, gy, gz)=(bx,bz,-by)."""
    return (location[0], -location[2], location[1])


GODOT_TO_BLENDER_BASIS = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, -1.0), (0.0, 1.0, 0.0)))
BLENDER_TO_GODOT_BASIS = GODOT_TO_BLENDER_BASIS.transposed()


def godot_basis(yaw: float = 0.0, scale: float = 1.0) -> Matrix:
    return Matrix.Rotation(yaw, 3, "Y") @ Matrix.Diagonal((scale, scale, scale))


def blender_matrix_from_godot(origin, basis: Matrix) -> Matrix:
    converted = GODOT_TO_BLENDER_BASIS @ basis @ BLENDER_TO_GODOT_BASIS
    result = converted.to_4x4()
    result.translation = godot_to_blender(origin)
    return result


def import_template(key: str, path: Path, target: bpy.types.Collection) -> bpy.types.Object:
    if not path.is_file():
        raise FileNotFoundError(path)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = list(set(bpy.data.objects) - before)
    root = bpy.data.objects.new("模板_" + key, None)
    target.objects.link(root)
    for obj in imported:
        link_only(obj, target)
    for obj in imported:
        if obj.parent is None:
            obj.parent = root
    return root


def copy_tree(source: bpy.types.Object, target: bpy.types.Collection, parent=None) -> bpy.types.Object:
    duplicate = source.copy()
    duplicate.data = source.data
    target.objects.link(duplicate)
    duplicate.parent = parent
    duplicate.matrix_parent_inverse = parent.matrix_world.inverted() if parent else source.matrix_parent_inverse.copy()
    duplicate.matrix_local = source.matrix_local.copy()
    for child in source.children:
        copy_tree(child, target, duplicate)
    return duplicate


def place(template: bpy.types.Object, target: bpy.types.Collection, name: str,
          godot_location: tuple[float, float, float], godot_yaw: float = 0.0,
          godot_scale: float = 1.0, exact_basis: Matrix | None = None) -> bpy.types.Object:
    root = copy_tree(template, target)
    root.name = name
    source_basis = exact_basis if exact_basis is not None else godot_basis(godot_yaw, godot_scale)
    root.matrix_world = blender_matrix_from_godot(godot_location, source_basis)
    root["godot_global_position_m"] = godot_location
    root["godot_yaw_rad"] = godot_yaw
    root["godot_global_basis_columns"] = tuple(value for column in source_basis.col for value in column)
    root["placement_source"] = "TowerDescent3D runtime transform dump"
    return root


def material(name: str, color: tuple[float, float, float, float], metallic: float, roughness: float,
             emission: tuple[float, float, float, float] | None = None) -> bpy.types.Material:
    value = bpy.data.materials.get(name)
    if value:
        return value
    value = bpy.data.materials.new(name)
    value.diffuse_color = color
    value.use_nodes = True
    shader = next((node for node in value.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
    if shader is None:
        raise RuntimeError("无法创建 Principled BSDF 预览材质：%s" % name)
    shader.inputs["Base Color"].default_value = color
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if emission:
        shader.inputs["Emission Color"].default_value = emission
        shader.inputs["Emission Strength"].default_value = 1.5
    return value


def box(parent: bpy.types.Object, target: bpy.types.Collection, name: str,
        godot_location: tuple[float, float, float], godot_size: tuple[float, float, float], mat) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add()
    obj = bpy.context.object
    link_only(obj, target)
    obj.name = name
    obj.dimensions = (godot_size[0], godot_size[2], godot_size[1])
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.parent = parent
    obj.location = godot_to_blender(godot_location)
    obj.data.materials.append(mat)
    return obj


def cylinder(parent: bpy.types.Object, target: bpy.types.Collection, name: str,
             godot_location: tuple[float, float, float], radius: float, depth: float, mat) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=depth)
    obj = bpy.context.object
    link_only(obj, target)
    obj.name = name
    obj.parent = parent
    obj.location = godot_to_blender(godot_location)
    obj.data.materials.append(mat)
    return obj


def generic_facility(target: bpy.types.Collection, name: str, godot_location,
                     godot_yaw: float = 0.0, child_scale: float = 1.0) -> bpy.types.Object:
    root = bpy.data.objects.new(name, None)
    target.objects.link(root)
    root.matrix_world = blender_matrix_from_godot(godot_location, godot_basis(godot_yaw))
    root["godot_global_position_m"] = godot_location
    root["godot_yaw_rad"] = godot_yaw
    root["model_note"] = "游戏内 prp_base_facility_root_top3d_v001 的程序占位设施"
    metal = material("占位设施_深紫金属", (0.055, 0.035, 0.12, 1), 0.8, 0.3)
    matte = material("占位设施_青绿哑光", (0.035, 0.32, 0.34, 1), 0.05, 0.7)
    glow = material("占位设施_青色信标", (0.04, 0.62, 0.82, 1), 0.0, 0.35, (0.04, 0.62, 0.82, 1))
    scaled = lambda values: tuple(component * child_scale for component in values)
    box(root, target, name + "_主体", scaled((0, 0.9, 0)), scaled((2.9, 1.8, 2.7)), matte)
    box(root, target, name + "_顶棚", scaled((0, 1.92, 0)), scaled((3.25, 0.35, 3.05)), metal)
    box(root, target, name + "_门", scaled((0, 0.72, -1.43)), scaled((0.95, 1.35, 0.16)), metal)
    cylinder(root, target, name + "_信标", scaled((0, 2.38, 0)), 0.28 * child_scale, 0.52 * child_scale, glow)
    return root


def corner_module(target: bpy.types.Collection, name: str, godot_location, godot_yaw: float) -> bpy.types.Object:
    root = bpy.data.objects.new(name, None)
    target.objects.link(root)
    root.matrix_world = blender_matrix_from_godot(godot_location, godot_basis(godot_yaw))
    root["godot_global_position_m"] = godot_location
    root["godot_yaw_rad"] = godot_yaw
    root["asset_id"] = "ENV-TOWER-CORNER-L-5M"
    wall_mat = material("基地99层_尘深蓝拐角墙", (0.11, 0.15, 0.19, 1), 0.05, 0.75)
    box(root, target, name + "_长臂", (2.5, 4.45, 0), (5, 8.9, 0.3), wall_mat)
    box(root, target, name + "_短臂", (0, 4.45, -2.5), (0.3, 8.9, 5), wall_mat)
    return root


def elevator_bay(target: bpy.types.Collection, godot_location, godot_yaw: float) -> None:
    bay = generic_facility(target, "99层塔楼电梯控制台", godot_location, godot_yaw, child_scale=0.7)
    bay["runtime_source"] = "TowerDescent3D._create_standalone_elevator"
    pad_mat = material("电梯地台_青黑自发光", (0.035, 0.12, 0.15, 1), 0.72, 0.30, (0.02, 0.45, 0.52, 1))
    box(bay, target, "99层塔楼电梯地台", (0, 0.045, 0), (5.0, 0.08, 4.8), pad_mat)


def add_wardrobe_overlays(root: bpy.types.Object, target: bpy.types.Collection) -> None:
    accent = material("衣柜_青色顶灯", (0.08, 0.58, 0.72, 1), 0.58, 0.34, (0.05, 0.5, 0.72, 1))
    screen = material("衣柜_控制屏", (0.1, 0.22, 0.28, 1), 0.36, 0.3, (0.12, 0.76, 0.88, 1))
    box(root, target, "角色衣柜_顶灯", (0, 3.62, -0.83), (3.9, 0.08, 0.04), accent)
    box(root, target, "角色衣柜_控制屏", (0, 2.18, -0.84), (1.55, 0.72, 0.05), screen)


def look_at(obj: bpy.types.Object, point: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_preview_environment(target: bpy.types.Collection) -> None:
    world = bpy.context.scene.world or bpy.data.worlds.new("基地预览世界")
    bpy.context.scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.014, 0.035, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.28
    for name, location, color, energy, size in [
        ("预览_主灯", (2, -5, 18), (0.35, 0.68, 1.0), 1500, 9),
        ("预览_紫色轮廓灯", (-16, 12, 6), (0.9, 0.16, 0.75), 1000, 7),
        ("预览_暖色轮廓灯", (16, -18, 6), (1.0, 0.32, 0.08), 850, 6),
    ]:
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.color = color
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        target.objects.link(light)
        light.location = location
        look_at(light, (0, -5, -4))
    camera_data = bpy.data.cameras.new("基地总装预览相机")
    camera = bpy.data.objects.new("基地总装预览相机", camera_data)
    target.objects.link(camera)
    # Orthographic plan view is used for the generated QA image. It makes every
    # facility placement inspectable while leaving the real wall geometry intact.
    camera.location = (0, -5, 42)
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 38
    look_at(camera, (0, -5, -4.5))
    bpy.context.scene.camera = camera


def basis_from_columns(columns) -> Matrix:
    return Matrix(tuple(zip(*columns)))


def main() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for value in list(bpy.data.collections):
        bpy.data.collections.remove(value)

    root = collection("基地99层运行时布局_游戏全局坐标v002")
    root["layout_source"] = "scenes/TowerDescent3D.tscn + TowerDescent3D._install_facilities runtime dump"
    root["room_global_origin_godot"] = (0.0, -9.0, 5.0)
    root["coordinate_contract"] = "Godot global (X,Y,Z) -> Blender (X,-Z,Y); Blender Z yaw = Godot Y yaw"
    templates = collection("00_资源模板_隐藏", root)
    templates.hide_viewport = True
    templates.hide_render = True
    lower_shell = collection("01_99层地板与下层围墙_运行时生成结果", root)
    structure = collection("02_楼中楼与100层围护_美术布局", root)
    facilities = collection("03_设施与独立装饰_最终运行态", root)
    doors = collection("04_升降门与99层电梯_运行时生成", root)
    ceiling = collection("05_18米封顶_默认隐藏便于查看内景", root)
    ceiling.hide_viewport = True
    ceiling.hide_render = True
    preview = collection("90_预览环境_不参与游戏", root)

    template = {key: import_template(key, path, templates) for key, path in ASSETS.items()}

    # Runtime room origin is Godot global (0,-9,5). The floor visual is lowered
    # 0.30 m locally so its structural top aligns with the support plane at Y=0.
    for row, gz in enumerate((-12.5, -7.5, -2.5, 2.5, 7.5, 12.5)):
        for col, gx in enumerate((-12.5, -7.5, -2.5, 2.5, 7.5, 12.5)):
            key = "floor_rivet" if (row + col) % 2 else "floor_plain"
            place(template[key], lower_shell, f"99层地板_{row:02d}_{col:02d}", (gx, -9.3, gz + 5.0))

    # Base 99 lower shell generated by DungeonRoom3D._build_base_facility_shell.
    for corner_name, location, yaw in [
        ("NW", (-15, -9, -10), -math.pi / 2),
        ("NE", (15, -9, -10), math.pi),
        ("SW", (-15, -9, 20), 0.0),
        ("SE", (15, -9, 20), math.pi / 2),
    ]:
        corner_module(lower_shell, f"99层拐角墙_{corner_name}", location, yaw)
    for index, gx in enumerate((-7.5, -2.5, 2.5, 7.5), start=1):
        place(template["wall_plain"], lower_shell, f"99层北墙_{index:02d}", (gx, -9, -10))
        place(template["wall_plain"], lower_shell, f"99层南墙_{index:02d}", (gx, -9, 20), math.pi)
    for index, gz in enumerate((-2.5, 2.5, 7.5, 12.5), start=1):
        key = "wall_door" if index == 2 else "wall_plain"
        place(template[key], lower_shell, f"99层西墙_{index:02d}", (-15, -9, gz), math.pi / 2)
        place(template[key], lower_shell, f"99层东墙_{index:02d}", (15, -9, gz), -math.pi / 2)
    # Both lower room door leaves have the same runtime visual basis.
    place(template["door_lift"], doors, "99层西侧升降门", (-15, -9, 2.5), math.pi / 2)
    place(template["door_lift"], doors, "99层东侧升降门", (15, -9, 2.5), math.pi / 2)

    # Active art modules, expressed in their final Godot global coordinates.
    place(template["mezzanine"], structure, "二层楼中楼楼板_20x10米_Z5", (5, -9, -5))
    place(template["underdeck"], structure, "楼中楼下方工业仓库挡板", (5, -9, -5))
    place(template["stair_l"], structure, "L型楼梯_一楼至二楼_Z5", (-9.58, -9, -4.15))
    place(template["stair_exterior"], structure, "外门小楼梯_二楼至100层_H4", (10.78, -4, -2.5))

    # Upper shell starts at world Y=0 because the base room itself is at Y=-9.
    north = [(-12.5, "wall_plain"), (-7.5, "wall_window"), (-2.5, "wall_window"), (2.5, "wall_window"), (7.5, "wall_window"), (12.5, "wall_plain")]
    for index, (gx, key) in enumerate(north):
        place(template[key], structure, f"100层北墙_{index:02d}", (gx, 0, -10))
    for index, gx in enumerate((12.5, 7.5, 2.5, -2.5, -7.5, -12.5)):
        place(template["wall_plain"], structure, f"100层南墙_{index:02d}", (gx, 0, 20), math.pi)
    for index, gz in enumerate((-7.5, -2.5, 2.5, 7.5, 12.5, 17.5)):
        place(template["wall_plain"], structure, f"100层西墙_{index:02d}", (-15, 0, gz), math.pi / 2)
        key = "wall_door" if index == 1 else "wall_plain"
        place(template[key], structure, f"100层东墙_{index:02d}", (15, 0, gz), -math.pi / 2)
    place(template["door_lift"], doors, "100层东侧天台升降门", (15, 0, -2.5), math.pi / 2)

    # The game ceiling is kept, but hidden by default for interior inspection.
    for row, gz in enumerate((-12.5, -7.5, -2.5, 2.5, 7.5, 12.5)):
        for col, gx in enumerate((-12.5, -7.5, -2.5, 2.5, 7.5, 12.5)):
            key = "floor_rivet" if (row + col) % 2 else "floor_plain"
            place(template[key], ceiling, f"18米封顶_{row:02d}_{col:02d}", (gx, 9, gz + 5.0))

    # Final *visual* bases and global origins captured from a live TowerDescent3D
    # instance. Locker/retro/wardrobe include their runtime Visual 180° wrapper.
    mission_basis = basis_from_columns(((0.799995482, 0.001790053, -0.002014372), (-0.001791030, 0.799997926, -0.000386539), (0.002013504, 0.000391038, 0.799997389)))
    vault_visual_basis = basis_from_columns(((0.000000333, 0, 0.9), (0, 0.9, 0), (-0.9, 0, 0.000000333)))
    fate_visual_basis = basis_from_columns(((0.799647033, 0, -0.023761116), (0, 0.8, 0), (0.023761116, 0, 0.799647033)))
    vending_basis = basis_from_columns(((-0.000000044, 0, 1), (0, 1, 0), (-1, 0, -0.000000044)))
    chair_basis = basis_from_columns(((0.473139316, 0, -0.515886784), (0, 0.7, 0), (0.515886784, 0, 0.473139316)))
    place(template["mission"], facilities, "远征情报终端", (7.2398195, -9, 1.0356579), exact_basis=mission_basis)
    place(template["workshop"], facilities, "枪械工坊", (2.8696804, -9, 1.0700879), godot_scale=0.8)
    place(template["locker"], facilities, "保险柜", (-5.5436068, -9, -2.3653212), exact_basis=vault_visual_basis)
    generic_facility(facilities, "怪物档案台_程序占位", (-3, -9, 16.6), child_scale=0.7)
    place(template["retro"], facilities, "命运卡收藏室", (-8.1812763, -9, -4.4919252), exact_basis=fate_visual_basis)
    place(template["vending"], facilities, "自动贩卖机", (14.1468973, -9, 7.5015855), exact_basis=vending_basis)
    generic_facility(facilities, "状态恢复舱_程序占位", (11.6, -9, -1.0813355), math.pi / 2)
    wardrobe = place(template["locker"], facilities, "角色衣柜_复用储物站模型", (12.7670174, -4.1720738, -8.8386993), godot_scale=0.8)
    add_wardrobe_overlays(wardrobe, facilities)
    place(template["stool"], facilities, "维修圆凳_独立装饰", (-0.3827412, -9, 2.3513927), godot_scale=0.7)
    place(template["chair"], facilities, "战术指挥椅_独立装饰", (7.4598789, -9, 3.0791037), exact_basis=chair_basis)
    elevator_bay(doors, (9, -9, 16.6), math.pi)

    add_preview_environment(preview)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(OUTPUT_PREVIEW)
    scene.render.film_transparent = False
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), compress=True)
    bpy.ops.render.render(write_still=True)
    print("BASE_FACILITY_LAYOUT_BUILD_OK", OUTPUT_BLEND)
    print("BASE_FACILITY_LAYOUT_PREVIEW_OK", OUTPUT_PREVIEW)


if __name__ == "__main__":
    main()
