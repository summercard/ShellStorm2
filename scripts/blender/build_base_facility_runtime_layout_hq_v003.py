"""Build the high-quality 30m x 30m Base 99 collectible diorama.

The scene keeps the registered Base 99 floor/wall modules, rebuilds the
mezzanine dressing and fixed facilities as editable palette-UV components,
and records the conversion back to the live Godot room coordinates.

Run:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python \
    scripts/blender/build_base_facility_runtime_layout_hq_v003.py
"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT = Path(__file__).resolve().parents[2]
OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v003.blend"
OUTPUT_HERO = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v003.png"
OUTPUT_TOP = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v003_top.png"
OUTPUT_DETAIL = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v003_underloft.png"
PALETTE = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
ENV = PROJECT / "assets/art/environments/base_facility_3d/components"

ASSETS = {
    "floor_plain": ENV / "env_base99_floor_plain_5m/env_base99_floor_plain_5m_visual_top3d_v001.glb",
    "floor_rivet": ENV / "env_base99_floor_rivet_5m/env_base99_floor_rivet_5m_visual_top3d_v001.glb",
    "wall_plain": ENV / "env_base99_wall_plain_5x9/env_base99_wall_plain_5x9_visual_top3d_v001.glb",
    "wall_door": ENV / "env_base99_wall_door_5x9/env_base99_wall_door_5x9_visual_top3d_v001.glb",
}

MATS: dict[str, bpy.types.Material] = {}
SOURCE: bpy.types.Collection
OUTPUT: bpy.types.Collection
COLLS: dict[str, bpy.types.Collection] = {}


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


def palette_center(col: int, row_top: int) -> tuple[float, float]:
    return ((col + 0.5) / 10.0, 1.0 - (row_top + 0.5) / 10.0)


COLORS = {
    "black": (0, 0), "teal": (1, 0), "purple": (2, 0), "cyan": (3, 0),
    "rust": (4, 2), "red": (2, 1), "wine": (4, 1), "yellow": (5, 3),
    "green": (5, 4), "blue": (3, 5), "violet": (4, 6), "magenta": (3, 7),
    "orange": (5, 2), "dark_gray": (9, 0), "mid_gray": (9, 3),
    "light_gray": (9, 5), "warm_gray": (9, 8), "wood": (3, 2),
}


def create_palette_material(name: str, metallic: float, roughness: float,
                            coat: float = 0.0, emission: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    tex = nodes.new("ShaderNodeTexImage")
    image = bpy.data.images.get(PALETTE.name) or bpy.data.images.load(str(PALETTE), check_existing=True)
    image.filepath = str(PALETTE)
    if image.packed_file:
        image.unpack(method="USE_ORIGINAL")
    tex.image = image
    tex.interpolation = "Closest"
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if shader.inputs.get("Coat Weight"):
        shader.inputs["Coat Weight"].default_value = coat
    if emission > 0:
        shader.inputs["Emission Strength"].default_value = emission
    out = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(uv.outputs["UV"], tex.inputs["Vector"])
    mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Base Color"])
    if emission > 0:
        mat.node_tree.links.new(tex.outputs["Color"], shader.inputs["Emission Color"])
    mat.node_tree.links.new(shader.outputs["BSDF"], out.inputs["Surface"])
    return mat


def create_materials() -> None:
    MATS["metal"] = create_palette_material("01_精工金属_紫色骨架", 0.86, 0.27, 0.18)
    MATS["matte"] = create_palette_material("02_细腻哑光_青绿大面", 0.03, 0.70)
    MATS["gloss"] = create_palette_material("03_清漆反光_紫粉点缀", 0.16, 0.15, 0.68)
    MATS["emit"] = create_palette_material("04_柔和自发光_UI灯光", 0.0, 0.38, 0.0, 1.5)


def apply_palette_uv(obj: bpy.types.Object, cell: tuple[int, int], reset: bool = True) -> None:
    if obj.type != "MESH":
        return
    mesh = obj.data
    if reset:
        while mesh.uv_layers:
            mesh.uv_layers.remove(mesh.uv_layers[0])
        uv = mesh.uv_layers.new(name="PaletteUV")
    else:
        uv = mesh.uv_layers.get("PaletteUV")
        if uv is None:
            if mesh.uv_layers:
                mesh.uv_layers.active.name = "PaletteUV"
                uv = mesh.uv_layers.active
            else:
                uv = mesh.uv_layers.new(name="PaletteUV")
        for layer in list(mesh.uv_layers):
            if layer != uv:
                mesh.uv_layers.remove(layer)
    mesh.uv_layers.active = uv
    uv.active_render = True
    cx, cy = palette_center(*cell)
    radius = 0.022
    for poly in mesh.polygons:
        count = max(3, poly.loop_total)
        for idx, loop_index in enumerate(poly.loop_indices):
            angle = (2.0 * math.pi * idx / count) + math.pi / 4.0
            uv.data[loop_index].uv = (cx + math.cos(angle) * radius, cy + math.sin(angle) * radius)


def assign_material(obj: bpy.types.Object, role: str, cell: tuple[int, int], reset_uv: bool = True) -> None:
    if obj.type != "MESH":
        return
    obj.data.materials.clear()
    obj.data.materials.append(MATS[role])
    for poly in obj.data.polygons:
        poly.material_index = 0
    apply_palette_uv(obj, cell, reset=reset_uv)
    obj["material_role"] = role
    obj["palette_cell_col_row_top"] = cell


def publish(src: bpy.types.Object, target: bpy.types.Collection, name: str | None = None) -> bpy.types.Object:
    out = src.copy()
    if src.data:
        out.data = src.data
    target.objects.link(out)
    out.name = name or src.name.replace("__源", "")
    return out


def bevel_apply(obj: bpy.types.Object, width: float, segments: int = 2) -> None:
    if width <= 0 or obj.type != "MESH":
        return
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    mod = obj.modifiers.new("边缘倒角", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod.limit_method = "ANGLE"
    try:
        bpy.ops.object.modifier_apply(modifier=mod.name)
    except RuntimeError:
        pass
    obj.select_set(False)


def add_box(name: str, loc, size, role="matte", color="dark_gray", bevel=0.035,
            target: bpy.types.Collection | None = None, obstacle=False, rotation=(0, 0, 0)) -> bpy.types.Object:
    target = target or COLLS["facility"]
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rotation)
    src = bpy.context.object
    link_only(src, SOURCE)
    src.name = name + "__源"
    src.dimensions = size
    bpy.context.view_layer.objects.active = src
    src.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    src.select_set(False)
    bevel_apply(src, min(bevel, min(size) * 0.22), 2)
    assign_material(src, role, COLORS[color])
    src["ground_obstacle"] = bool(obstacle)
    out = publish(src, target, name)
    out["ground_obstacle"] = bool(obstacle)
    return out


def add_cylinder(name: str, loc, radius, depth, role="metal", color="purple", vertices=16,
                 target: bpy.types.Collection | None = None, obstacle=False, rotation=(0, 0, 0)) -> bpy.types.Object:
    target = target or COLLS["facility"]
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rotation)
    src = bpy.context.object
    link_only(src, SOURCE)
    src.name = name + "__源"
    bevel_apply(src, min(0.025, radius * 0.16), 2)
    assign_material(src, role, COLORS[color])
    src["ground_obstacle"] = bool(obstacle)
    return publish(src, target, name)


def add_sphere(name: str, loc, radius, role="gloss", color="cyan",
               target: bpy.types.Collection | None = None) -> bpy.types.Object:
    target = target or COLLS["motion"]
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=loc)
    src = bpy.context.object
    link_only(src, SOURCE)
    src.name = name + "__源"
    assign_material(src, role, COLORS[color])
    return publish(src, target, name)


def add_beam(name: str, start, end, thickness=0.08, role="metal", color="purple",
             target: bpy.types.Collection | None = None) -> bpy.types.Object:
    start_v, end_v = Vector(start), Vector(end)
    delta = end_v - start_v
    obj = add_box(name, (start_v + end_v) * 0.5, (thickness, thickness, delta.length), role, color,
                  bevel=thickness * 0.25, target=target)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = delta.to_track_quat("Z", "Y")
    # Keep the editable source aligned too.
    src = bpy.data.objects.get(name + "__源")
    if src:
        src.rotation_mode = "QUATERNION"
        src.rotation_quaternion = obj.rotation_quaternion
    return obj


def add_text(name: str, body: str, loc, size=0.45, role="emit", color="cyan", extrude=0.025,
             align="CENTER", rotation=(0, 0, 0), target: bpy.types.Collection | None = None) -> bpy.types.Object:
    target = target or COLLS["facility"]
    curve = bpy.data.curves.new(name + "_字体", "FONT")
    curve.body = body
    curve.align_x = align
    curve.align_y = "CENTER"
    curve.size = size
    curve.extrude = extrude
    curve.bevel_depth = min(0.008, extrude * 0.3)
    src = bpy.data.objects.new(name + "__源", curve)
    SOURCE.objects.link(src)
    src.location = loc
    src.rotation_euler = rotation
    bpy.context.view_layer.objects.active = src
    src.select_set(True)
    bpy.ops.object.convert(target="MESH")
    src = bpy.context.object
    src.name = name + "__源"
    assign_material(src, role, COLORS[color])
    src.select_set(False)
    return publish(src, target, name)


def add_plane_mesh(name: str, verts, role="matte", color="yellow", target=None) -> bpy.types.Object:
    target = target or COLLS["facility"]
    mesh = bpy.data.meshes.new(name + "_网格")
    mesh.from_pydata(verts, [], [list(range(len(verts)))])
    mesh.update()
    src = bpy.data.objects.new(name + "__源", mesh)
    SOURCE.objects.link(src)
    assign_material(src, role, COLORS[color])
    return publish(src, target, name)


def tag_game_position(obj: bpy.types.Object, asset_id: str | None = None) -> None:
    x, y, z = obj.location
    obj["godot_global_position_m"] = (round(x, 4), round(-9.0 + z, 4), round(5.0 - y, 4))
    obj["coordinate_contract"] = "Blender local (X,Y,Z) -> Godot global (X,-9+Z,5-Y)"
    if asset_id:
        obj["asset_id"] = asset_id


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
        if obj.type == "MESH":
            old_names = " ".join((slot.material.name if slot.material else "") for slot in obj.material_slots).lower()
            role = "matte"
            if any(word in old_names for word in ("emiss", "glow", "light", "led")):
                role = "emit"
            elif any(word in old_names for word in ("glass", "screen", "gloss", "clearcoat")):
                role = "gloss"
            elif any(word in old_names for word in ("metal", "steel", "frame", "trim")):
                role = "metal"
            default_cell = COLORS["dark_gray"] if role != "emit" else COLORS["cyan"]
            # Registered GLBs already carry palette coordinates; glTF import calls it UVMap.
            assign_material(obj, role, default_cell, reset_uv=not bool(obj.data.uv_layers))
    for obj in imported:
        if obj.parent is None:
            obj.parent = root
    return root


def copy_tree(source: bpy.types.Object, target: bpy.types.Collection, parent=None) -> bpy.types.Object:
    dup = source.copy()
    if source.data:
        dup.data = source.data
    target.objects.link(dup)
    dup.parent = parent
    dup.matrix_local = source.matrix_local.copy()
    for child in source.children:
        copy_tree(child, target, dup)
    return dup


def place_template(template: bpy.types.Object, target: bpy.types.Collection, name: str, loc, yaw=0.0) -> bpy.types.Object:
    root = copy_tree(template, target)
    root.name = name
    root.location = loc
    root.rotation_euler[2] = yaw
    tag_game_position(root)
    return root


def set_tree_camera_visibility(root: bpy.types.Object, visible: bool) -> None:
    root.visible_camera = visible
    for child in root.children_recursive:
        child.visible_camera = visible


def add_area_light(name, loc, energy, color, size=3.0, target=(0, 0, 0), shadows=True,
                   collection_target=None) -> bpy.types.Object:
    collection_target = collection_target or COLLS["lights"]
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.color = color
    data.shape = "RECTANGLE"
    data.size = size
    data.size_y = max(0.25, size * 0.35)
    data.use_shadow = shadows
    obj = bpy.data.objects.new(name, data)
    collection_target.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    return obj


def keyframe_cycle(obj, data_path: str, frames_values) -> None:
    for frame, value in frames_values:
        setattr(obj, data_path, value)
        obj.keyframe_insert(data_path=data_path, frame=frame)
    if obj.animation_data and obj.animation_data.action:
        for fcurve in obj.animation_data.action.fcurves:
            for point in fcurve.keyframe_points:
                point.interpolation = "BEZIER"
            fcurve.modifiers.new("CYCLES")


def animate_light_energy(light_obj, values) -> None:
    for frame, energy in values:
        light_obj.data.energy = energy
        light_obj.data.keyframe_insert(data_path="energy", frame=frame)
    if light_obj.data.animation_data and light_obj.data.animation_data.action:
        for curve in light_obj.data.animation_data.action.fcurves:
            for point in curve.keyframe_points:
                point.interpolation = "BEZIER"
            curve.modifiers.new("CYCLES")


def build_registered_shell(templates) -> None:
    floor_coll = COLLS["shell"]
    centers = (-12.5, -7.5, -2.5, 2.5, 7.5, 12.5)
    for row, y in enumerate(centers):
        for col, x in enumerate(centers):
            key = "floor_rivet" if (row + col) % 2 else "floor_plain"
            # Runtime lowers the decorative floor by 0.30m so the structural
            # support plane and all facility origins stay at local Z=0.
            place_template(templates[key], floor_coll, f"保留地板_{row:02d}_{col:02d}", (x, y, -0.30))
    for idx, x in enumerate(centers):
        place_template(templates["wall_plain"], floor_coll, f"保留北墙_{idx:02d}", (x, 15, 0), 0)
        south = place_template(templates["wall_plain"], floor_coll, f"保留南墙_{idx:02d}", (x, -15, 0), math.pi)
        set_tree_camera_visibility(south, False)
    for idx, y in enumerate(centers):
        key = "wall_door" if idx == 2 else "wall_plain"
        place_template(templates[key], floor_coll, f"保留西墙_{idx:02d}", (-15, y, 0), math.pi / 2)
        east = place_template(templates[key], floor_coll, f"保留东墙_{idx:02d}", (15, y, 0), -math.pi / 2)
        set_tree_camera_visibility(east, False)


def build_corridor() -> None:
    c = COLLS["corridor"]
    add_box("中央环氧主通道面层", (0, 0, 0.19), (29.4, 14.7, 0.08), "gloss", "dark_gray", 0.01, c)
    for y in (-7.25, 7.25):
        add_box(f"主通道黄色边界_{y:+.2f}", (0, y, 0.245), (29.3, 0.13, 0.025), "emit", "yellow", 0.005, c)
    for x in (-10, 0, 10):
        verts = [(x - 1.35, -0.60, 0.27), (x + 0.35, -0.60, 0.27), (x + 0.35, -1.05, 0.27),
                 (x + 1.45, 0, 0.27), (x + 0.35, 1.05, 0.27), (x + 0.35, 0.60, 0.27),
                 (x - 1.35, 0.60, 0.27)]
        add_plane_mesh(f"东西向箭头_{x:+03d}", verts, "emit", "yellow", c)
    add_text("地面字_MAIN_CORRIDOR", "MAIN CORRIDOR", (-6.7, -3.5, 0.275), 0.72, "emit", "yellow", 0.008,
             "LEFT", (0, 0, 0), c)
    add_text("地面字_KEEP_CLEAR", "KEEP CLEAR", (0, 3.25, 0.275), 0.60, "emit", "yellow", 0.008,
             "CENTER", (0, 0, 0), c)
    add_text("地面字_VEHICLE_PATH", "VEHICLE PATH", (7.1, -3.5, 0.275), 0.58, "emit", "yellow", 0.008,
             "CENTER", (0, 0, 0), c)
    for y in (-7.78, 7.78):
        for x in (-12, -6, 0, 6, 12):
            add_cylinder(f"通道警示柱_{x}_{y}", (x, y, 0.48), 0.11, 0.72, "metal", "yellow", 16, c, True)
            add_box(f"通道警示柱黑环_{x}_{y}", (x, y, 0.54), (0.25, 0.25, 0.12), "matte", "black", 0.01, c)


def add_wire_guard(prefix, x0, x1, y, z0, height=1.2, target=None) -> None:
    target = target or COLLS["mezz"]
    add_beam(prefix + "_上横杆", (x0, y, z0 + height), (x1, y, z0 + height), 0.09, "metal", "black", target)
    add_beam(prefix + "_中横杆", (x0, y, z0 + height * 0.55), (x1, y, z0 + height * 0.55), 0.055, "metal", "purple", target)
    for x in [x0 + i * 1.0 for i in range(int((x1 - x0) / 1.0) + 1)]:
        add_beam(f"{prefix}_立柱_{x:.1f}", (x, y, z0), (x, y, z0 + height), 0.065, "metal", "black", target)
    for x in [x0 + 0.5 + i * 0.5 for i in range(int((x1 - x0) / 0.5))]:
        add_beam(f"{prefix}_铁丝网_{x:.1f}", (x, y, z0 + 0.1), (x, y, z0 + height - 0.1), 0.018,
                 "metal", "mid_gray", target)
    for zi in range(1, 5):
        z = z0 + zi * height / 5
        add_beam(f"{prefix}_网格横丝_{zi}", (x0, y, z), (x1, y, z), 0.018, "metal", "mid_gray", target)


def build_mezzanine_and_stairs() -> None:
    c = COLLS["mezz"]
    add_box("楼中楼_主承重楼板", (0, 10, 5.78), (20, 10, 0.44), "metal", "dark_gray", 0.05, c)
    add_box("楼中楼_深色木纹生活面", (0, 10, 6.04), (19.6, 9.6, 0.10), "matte", "wood", 0.02, c)
    for x in (-9.65, 9.65):
        for y in (8.6, 14.55):
            add_box(f"楼中楼_承重柱_{x}_{y}", (x, y, 2.9), (0.30, 0.30, 5.8), "metal", "purple", 0.04, c, True)
    for y in (5.15, 14.78):
        add_beam(f"楼板边梁_{y}", (-9.9, y, 5.52), (9.9, y, 5.52), 0.28, "metal", "purple", c)
    for x in (-9.9, 9.9):
        add_beam(f"楼板侧梁_{x}", (x, 5.25, 5.52), (x, 14.75, 5.52), 0.28, "metal", "purple", c)
    # South guard has a western stair opening.
    add_wire_guard("楼中楼_南护栏东段", -7.9, 9.8, 5.18, 6.08, target=c)
    add_wire_guard("楼中楼_北护栏", -9.8, 9.8, 14.72, 6.08, target=c)
    add_wire_guard("楼中楼_东护栏", 9.75, 9.77, 5.2, 6.08, target=c)

    # L stair: first run climbs north, second run turns east.
    rise = 0.30
    tread = 0.44
    for i in range(10):
        y = 8.0 + i * tread
        z = (i + 0.5) * rise
        add_box(f"L梯_第一跑踏步_{i+1:02d}", (-13.1, y, z), (2.0, tread, rise), "metal", "dark_gray", 0.025, c, True)
        strip = add_box(f"L梯_第一跑导光_{i+1:02d}", (-13.1, y - tread * 0.44, z + rise * 0.45),
                        (1.75, 0.035, 0.035), "emit", "cyan", 0.005, COLLS["motion"])
        strip.scale = (1, 1, 0.2)
        strip.keyframe_insert("scale", frame=1 + i * 4)
        strip.scale = (1, 1, 1)
        strip.keyframe_insert("scale", frame=12 + i * 4)
        strip.scale = (1, 1, 0.2)
        strip.keyframe_insert("scale", frame=70 + i * 4)
    add_box("L梯_转角平台", (-13.0, 12.65, 3.02), (2.3, 2.2, 0.24), "metal", "dark_gray", 0.035, c, True)
    for i in range(10):
        x = -12.75 + i * tread
        z = 3.0 + (i + 0.5) * rise
        add_box(f"L梯_第二跑踏步_{i+1:02d}", (x, 13.75, z), (tread, 2.0, rise), "metal", "dark_gray", 0.025, c, True)
        strip = add_box(f"L梯_第二跑导光_{i+1:02d}", (x - tread * 0.44, 13.75, z + rise * 0.45),
                        (0.035, 1.75, 0.035), "emit", "cyan", 0.005, COLLS["motion"])
        for frame, value in ((41 + i * 4, 0.2), (52 + i * 4, 1.0), (110 + i * 4, 0.2)):
            strip.scale = (1, 1, value)
            strip.keyframe_insert("scale", frame=frame)
    # Round-tube handrail, clear of the platform access.
    for x in (-14.18, -12.02):
        add_beam(f"L梯_第一跑扶手_{x}", (x, 7.8, 1.05), (x, 12.5, 4.05), 0.075, "metal", "black", c)
        for i in range(4):
            y = 8.2 + i * 1.25
            z = 0.8 + (y - 7.8) * (3.0 / 4.7)
            add_beam(f"L梯_第一跑栏杆柱_{x}_{i}", (x, y, z - 0.9), (x, y, z), 0.06, "metal", "black", c)
    for y in (12.66, 14.84):
        add_beam(f"L梯_第二跑扶手_{y}", (-13.0, y, 4.05), (-8.55, y, 7.05), 0.075, "metal", "black", c)

    # Landing utilities.
    add_box("平台鞋柜", (-13.0, 13.2, 3.65), (1.45, 0.48, 1.05), "matte", "teal", 0.05, c)
    add_box("平台钥匙盒", (-13.65, 12.35, 4.25), (0.42, 0.12, 0.55), "gloss", "orange", 0.035, c)
    add_box("平台门禁面板", (-12.95, 12.35, 4.30), (0.42, 0.10, 0.65), "gloss", "cyan", 0.03, c)
    add_box("平台监控屏幕", (-12.15, 12.35, 4.45), (0.75, 0.10, 0.52), "gloss", "blue", 0.025, c)
    add_box("平台公告板", (-13.0, 14.65, 4.45), (1.55, 0.10, 0.85), "matte", "wood", 0.025, c)
    add_box("平台应急灯", (-13.0, 14.55, 5.15), (0.68, 0.16, 0.18), "emit", "red", 0.025, c)

    # Under-deck line lighting; visible geometry and real breathing lights are separate.
    for x in (-7.5, -2.5, 2.5, 7.5):
        add_box(f"阁楼底部灯带_{x}", (x, 9.25, 5.48), (3.2, 0.16, 0.10), "emit", "cyan", 0.02, COLLS["motion"])
        light = add_area_light(f"阁楼底部呼吸灯_{x}", (x, 9.25, 5.35), 480, (0.10, 0.72, 1.0), 3.0,
                               (x, 9.25, 0.5), False)
        animate_light_energy(light, [(1, 280), (60, 520), (120, 300), (180, 510), (240, 280)])


def build_bed_and_living() -> None:
    c = COLLS["living"]
    # Bed frame and bedding.
    add_box("阁楼床_床垫", (-5.6, 11.6, 6.72), (3.8, 2.15, 0.34), "matte", "light_gray", 0.12, c)
    add_box("阁楼床_毛毯", (-5.1, 11.6, 6.92), (2.55, 2.08, 0.12), "matte", "blue", 0.06, c)
    add_box("阁楼床_枕头", (-6.75, 11.6, 7.00), (0.85, 1.45, 0.22), "matte", "warm_gray", 0.12, c)
    for x in (-7.45, -3.75):
        for y in (10.55, 12.65):
            add_cylinder(f"阁楼床_床脚_{x}_{y}", (x, y, 6.45), 0.055, 0.75, "metal", "purple", 12, c)
    for a, b, n in [((-7.45, 10.55, 6.55), (-3.75, 10.55, 6.55), "南"),
                    ((-7.45, 12.65, 6.55), (-3.75, 12.65, 6.55), "北"),
                    ((-7.45, 10.55, 6.55), (-7.45, 12.65, 6.55), "西"),
                    ((-3.75, 10.55, 6.55), (-3.75, 12.65, 6.55), "东")]:
        add_beam("阁楼床_金属床框_" + n, a, b, 0.10, "metal", "purple", c)
    for x in (-6.7, -5.45, -4.2):
        add_box(f"床下储物箱_{x}", (x, 11.6, 6.30), (1.0, 1.45, 0.42), "matte", "teal", 0.06, c)
        add_box(f"床下储物箱扣件_{x}", (x, 10.86, 6.34), (0.28, 0.05, 0.16), "metal", "yellow", 0.02, c)
    # Warm bedside lamp.
    add_cylinder("床头灯_灯座", (-7.9, 12.75, 6.35), 0.18, 0.20, "metal", "black", 16, c)
    add_beam("床头灯_灯杆", (-7.9, 12.75, 6.42), (-7.9, 12.75, 7.35), 0.06, "metal", "black", c)
    add_box("床头灯_灯罩", (-7.9, 12.75, 7.45), (0.46, 0.46, 0.30), "emit", "orange", 0.08, c)
    add_area_light("床头暖光", (-7.9, 12.6, 7.35), 180, (1.0, 0.48, 0.18), 1.1, (-6.2, 11.6, 6.5), False)

    # Curtain on ceiling rail, animated in alternating strips.
    add_beam("床区布帘顶轨", (-3.2, 10.35, 8.65), (-3.2, 13.05, 8.65), 0.055, "metal", "black", c)
    for i in range(9):
        panel = add_box(f"床区布帘_{i+1:02d}", (-3.20, 10.48 + i * 0.31, 7.65), (0.035, 0.34, 1.85),
                        "matte", "wine" if i % 2 else "purple", 0.012, COLLS["motion"])
        panel.rotation_euler[1] = math.radians((-1) ** i * 1.2)
        panel.keyframe_insert("rotation_euler", frame=1)
        panel.rotation_euler[1] = math.radians((-1) ** (i + 1) * 3.0)
        panel.keyframe_insert("rotation_euler", frame=96)
        panel.rotation_euler[1] = math.radians((-1) ** i * 1.2)
        panel.keyframe_insert("rotation_euler", frame=192)

    # High table, stools and compact workstation.
    add_cylinder("阁楼高脚桌_立柱", (1.4, 11.3, 7.05), 0.12, 1.75, "metal", "purple", 16, c)
    add_box("阁楼高脚桌_桌面", (1.4, 11.3, 7.95), (2.3, 1.15, 0.16), "matte", "wood", 0.06, c)
    for i, x in enumerate((0.55, 2.25)):
        add_cylinder(f"阁楼高脚椅_{i+1}_立柱", (x, 9.95, 6.85), 0.10, 1.25, "metal", "black", 14, c)
        add_cylinder(f"阁楼高脚椅_{i+1}_坐面", (x, 9.95, 7.50), 0.34, 0.14, "matte", "teal", 18, c)
    add_box("阁楼小型工作台_主体", (6.5, 12.25, 6.85), (4.8, 1.15, 1.30), "matte", "dark_gray", 0.06, c)
    add_box("阁楼小型工作台_桌面", (6.5, 12.15, 7.54), (5.0, 1.40, 0.16), "metal", "mid_gray", 0.04, c)
    add_box("阁楼电脑_屏幕", (6.9, 12.65, 8.25), (1.65, 0.16, 0.95), "gloss", "blue", 0.06, c)
    add_box("阁楼电脑_键盘", (6.9, 11.75, 7.70), (1.45, 0.52, 0.08), "matte", "black", 0.025, c)
    add_box("阁楼电台", (4.8, 12.10, 7.85), (1.15, 0.65, 0.48), "metal", "teal", 0.05, c)
    for i in range(5):
        add_cylinder(f"电台旋钮_{i}", (4.38 + i * 0.18, 11.76, 7.86), 0.045, 0.07, "gloss", "yellow", 12,
                     c, rotation=(math.pi / 2, 0, 0))
    add_box("阁楼急救包", (8.2, 12.0, 7.88), (0.78, 0.38, 0.48), "matte", "red", 0.08, c)
    add_text("阁楼急救包十字", "+", (8.2, 11.78, 7.89), 0.28, "emit", "light_gray", 0.008,
             "CENTER", (math.pi / 2, 0, 0), c)
    add_cylinder("阁楼灭火器", (8.85, 10.65, 6.80), 0.18, 1.30, "gloss", "red", 18, c)


def add_labeled_locker(prefix, x, label, color, transparent=False) -> None:
    c = COLLS["facility"]
    add_box(prefix + "_柜体", (x, 13.75, 1.45), (1.65, 0.75, 2.85), "metal", "dark_gray", 0.07, c, True)
    add_box(prefix + "_柜门", (x, 13.34, 1.45), (1.42, 0.08, 2.50), "gloss" if transparent else "matte",
            "mid_gray" if transparent else color, 0.035, c)
    add_box(prefix + "_铭牌", (x, 13.285, 2.38), (1.18, 0.025, 0.30), "emit", "cyan", 0.01, c)
    add_text(prefix + "_标签", label, (x, 13.255, 2.39), 0.18, "emit", "light_gray", 0.006,
             "CENTER", (math.pi / 2, 0, 0), c)
    add_box(prefix + "_把手", (x + 0.53, 13.20, 1.38), (0.06, 0.08, 0.55), "metal", "yellow", 0.02, c)
    if transparent:
        for row in range(3):
            add_box(f"{prefix}_可见物资_{row}", (x, 13.64, 0.65 + row * 0.65), (1.05, 0.20, 0.28),
                    "matte", ("red", "teal", "yellow")[row], 0.04, c)


def add_simple_weapon(name, loc, scale=1.0, rotation_z=0.0) -> None:
    c = COLLS["attachment"]
    x, y, z = loc
    add_box(name + "_机匣", (x, y, z), (1.05 * scale, 0.13 * scale, 0.22 * scale), "metal", "dark_gray", 0.025, c,
            rotation=(0, 0, rotation_z))
    add_box(name + "_枪托", (x - 0.70 * scale, y, z), (0.38 * scale, 0.18 * scale, 0.26 * scale), "matte", "purple", 0.035, c,
            rotation=(0, 0, rotation_z))
    add_cylinder(name + "_枪管", (x + 0.85 * scale, y, z), 0.045 * scale, 0.95 * scale, "metal", "black", 12, c,
                 rotation=(0, math.pi / 2, rotation_z))
    add_box(name + "_弹匣", (x + 0.05 * scale, y, z - 0.24 * scale), (0.20 * scale, 0.14 * scale, 0.42 * scale),
            "metal", "black", 0.025, c, rotation=(0, 0, rotation_z))


def build_visual_center() -> None:
    c = COLLS["facility"]
    # Mixed steel / reclaimed wood / concrete television backdrop.
    add_box("电视背景墙_钢板左", (-3.9, 14.52, 2.35), (2.2, 0.20, 4.25), "metal", "dark_gray", 0.03, c)
    add_box("电视背景墙_旧木板中", (0, 14.48, 2.25), (5.65, 0.18, 4.05), "matte", "wood", 0.025, c)
    add_box("电视背景墙_水泥板右", (3.9, 14.52, 2.35), (2.2, 0.20, 4.25), "matte", "mid_gray", 0.025, c)
    for x in (-4.6, -2.3, 0, 2.3, 4.6):
        add_box(f"电视背景墙_钢包边_{x}", (x, 14.32, 2.35), (0.09, 0.08, 4.2), "metal", "purple", 0.015, c)
    add_box("工业电视墙_主机壳", (0, 13.95, 2.25), (6.4, 0.46, 2.65), "metal", "black", 0.12, c, True)
    add_box("工业电视墙_屏幕", (0, 13.68, 2.38), (5.78, 0.07, 2.05), "emit", "blue", 0.035, c)
    add_box("工业电视墙_下方储物柜", (0, 13.35, 0.70), (6.8, 1.0, 1.20), "matte", "dark_gray", 0.08, c, True)
    for x in (-2.55, -0.85, 0.85, 2.55):
        add_box(f"电视低柜门_{x}", (x, 12.82, 0.72), (1.48, 0.06, 0.90), "matte", "teal", 0.025, c)
        add_box(f"电视低柜把手_{x}", (x, 12.77, 0.93), (0.38, 0.04, 0.06), "metal", "yellow", 0.015, c)
    # Scanline animation across the display.
    for i in range(8):
        line = add_box(f"电视扫描线_{i:02d}", (0, 13.635, 1.55 + i * 0.23), (5.55, 0.015, 0.018),
                       "emit", "cyan" if i % 2 else "violet", 0.002, COLLS["motion"])
        line.location.z += 0.0
        line.keyframe_insert("location", frame=1 + i * 3)
        line.location.z += 1.55
        line.keyframe_insert("location", frame=80 + i * 3)
        line.location.z -= 1.55
        line.keyframe_insert("location", frame=160 + i * 3)
    # Hero sign.
    add_box("BASE_CAMP_金属背板", (0, 14.14, 4.45), (8.8, 0.18, 1.02), "metal", "purple", 0.10, c)
    add_text("BASE_CAMP_立体霓虹字", "BASE CAMP", (0, 13.98, 4.48), 0.92, "emit", "light_gray", 0.055,
             "CENTER", (math.pi / 2, 0, 0), c)
    for x, color in ((-2.2, (0.10, 0.45, 1.0)), (2.2, (0.55, 0.12, 1.0))):
        lamp = add_area_light(f"BASE_CAMP_背光_{x}", (x, 13.70, 4.45), 420, color, 4.2, (x, 11, 3), False)
        animate_light_energy(lamp, [(1, 410), (47, 360), (50, 80), (53, 420), (121, 390), (124, 150), (127, 430), (240, 410)])

    # Six locker labels across both sides.
    lockers = [(-8.8, "MEDICAL", "red", True), (-7.0, "TOOLS", "teal", False), (-5.2, "AMMO", "yellow", True),
               (5.2, "FOOD", "orange", True), (7.0, "CLOTHING", "violet", False), (8.8, "BATTERIES", "cyan", True)]
    for idx, (x, label, color, transparent) in enumerate(lockers):
        add_labeled_locker(f"工业储物柜_{idx+1:02d}", x, label, color, transparent)
        # Locker-top life details stay independent.
        if idx % 2 == 0:
            add_box(f"柜顶工具箱_{idx}", (x, 13.6, 3.08), (0.95, 0.42, 0.34), "matte", "red", 0.06, COLLS["attachment"])
        else:
            add_cylinder(f"柜顶头盔_{idx}", (x, 13.6, 3.12), 0.34, 0.30, "metal", "mid_gray", 18, COLLS["attachment"])

    # Armory work zone beneath east half of mezzanine.
    add_box("武器台防滑橡胶垫", (5.3, 9.45, 0.28), (6.5, 3.1, 0.08), "matte", "black", 0.02, c)
    add_box("武器台锁柜主体", (5.3, 10.6, 0.85), (5.8, 1.15, 1.45), "metal", "dark_gray", 0.08, c, True)
    add_box("武器台加固木台面", (5.3, 10.5, 1.65), (6.2, 1.45, 0.20), "matte", "wood", 0.05, c)
    add_box("武器挂墙板", (5.3, 13.05, 3.05), (7.0, 0.22, 2.2), "metal", "dark_gray", 0.035, c)
    for x in (2.6, 3.5, 4.4, 5.3, 6.2, 7.1, 8.0):
        add_box(f"武器挂架孔列_{x}", (x, 12.90, 3.05), (0.035, 0.025, 1.75), "emit", "cyan", 0.003, c)
    add_simple_weapon("展示步枪_A", (4.25, 12.72, 3.35), 1.0)
    add_simple_weapon("展示步枪_B", (6.55, 12.72, 2.75), 0.9)
    add_box("刀具磁吸条", (7.9, 12.78, 3.75), (1.25, 0.10, 0.18), "metal", "purple", 0.025, c)
    for i in range(4):
        add_box(f"展示刀具_{i}", (7.48 + i * 0.28, 12.68, 3.28), (0.10, 0.10, 0.70), "metal", "light_gray", 0.025,
                COLLS["attachment"], rotation=(0, 0, math.radians((-8 + i * 5))))
    for i, x in enumerate((3.2, 4.2, 5.2, 6.2, 7.2)):
        add_box(f"弹匣收纳格_{i}", (x, 12.72, 2.05), (0.62, 0.25, 0.58), "matte", "black", 0.025, c)
    for i, x in enumerate((3.5, 5.3, 7.1)):
        add_box(f"武器台弹药箱_{i}", (x, 10.25, 1.95), (1.25, 0.70, 0.52), "matte", "teal", 0.06, COLLS["attachment"])
    add_text("ARMORY_霓虹字", "ARMORY", (5.3, 12.75, 4.45), 0.52, "emit", "red", 0.035,
             "CENTER", (math.pi / 2, 0, 0), c)
    red = add_area_light("武器台红色警示灯", (5.3, 11.8, 4.6), 0, (1.0, 0.04, 0.03), 1.8, (5.3, 10, 1), False)
    animate_light_energy(red, [(1, 0), (35, 0), (38, 420), (46, 420), (49, 0), (120, 0)])


def build_vending() -> None:
    c = COLLS["facility"]
    x, y = 11.7, 9.0
    add_box("复古工业自动贩卖机_机身", (x, y, 1.75), (2.25, 1.15, 3.5), "metal", "purple", 0.14, c, True)
    add_box("自动贩卖机_玻璃橱窗", (x - 0.25, y - 0.61, 2.10), (1.45, 0.07, 2.05), "gloss", "blue", 0.045, c)
    add_box("自动贩卖机_控制面板", (x + 0.75, y - 0.62, 1.78), (0.48, 0.08, 1.25), "matte", "black", 0.035, c)
    add_box("自动贩卖机_付款屏", (x + 0.75, y - 0.68, 2.15), (0.32, 0.03, 0.36), "emit", "cyan", 0.015, c)
    add_box("自动贩卖机_取货口", (x, y - 0.66, 0.55), (1.20, 0.10, 0.42), "matte", "black", 0.025, c)
    for row in range(4):
        add_box(f"自动贩卖机_层板_{row}", (x - 0.25, y - 0.42, 1.10 + row * 0.52), (1.35, 0.36, 0.05),
                "metal", "light_gray", 0.01, c)
        for col in range(4):
            color = ("cyan", "orange", "red", "yellow")[(row + col) % 4]
            add_box(f"自动贩卖机_商品_{row}_{col}", (x - 0.72 + col * 0.31, y - 0.47, 1.30 + row * 0.52),
                    (0.22, 0.20, 0.34), "matte", color, 0.045, COLLS["attachment"])
    for i, color in enumerate(("red", "blue")):
        led = add_box(f"自动贩卖机_指示灯_{i}", (x + 0.63 + i * 0.22, y - 0.69, 2.72), (0.12, 0.03, 0.12),
                      "emit", color, 0.015, COLLS["motion"])
        for frame, scale in ((1 + i * 10, 0.25), (25 + i * 10, 1.0), (50 + i * 10, 0.25)):
            led.scale = (scale, scale, scale)
            led.keyframe_insert("scale", frame=frame)
    add_text("自动贩卖机_旧贴纸", "SUPPLY / 24H", (x - 0.35, y - 0.69, 3.20), 0.20, "emit", "yellow", 0.008,
             "CENTER", (math.pi / 2, 0, 0), c)
    add_cylinder("自动贩卖机旁垃圾桶", (13.25, 8.95, 0.58), 0.42, 1.12, "metal", "dark_gray", 18, c, True)
    add_cylinder("自动贩卖机旁烟灰缸", (10.25, 8.95, 0.72), 0.28, 1.40, "metal", "mid_gray", 18, c, True)
    add_box("自动贩卖机旁回收箱", (13.35, 10.45, 0.62), (0.9, 0.75, 1.15), "matte", "teal", 0.08, c, True)


def add_shelf(prefix, x, y, width=4.6) -> None:
    c = COLLS["warehouse"]
    for px in (x - width / 2, x + width / 2):
        add_box(f"{prefix}_立柱_{px}", (px, y, 1.75), (0.14, 0.42, 3.5), "metal", "purple", 0.025, c, True)
    for row, z in enumerate((0.35, 1.25, 2.15, 3.05)):
        add_box(f"{prefix}_层板_{row}", (x, y, z), (width, 0.82, 0.12), "metal", "dark_gray", 0.025, c, True)
        for col in range(4):
            px = x - 1.65 + col * 1.1
            color = ("teal", "red", "orange", "yellow")[(row + col) % 4]
            add_box(f"{prefix}_补给箱_{row}_{col}", (px, y - 0.08, z + 0.34), (0.88, 0.58, 0.50),
                    "matte", color, 0.055, COLLS["attachment"])


def build_warehouse() -> None:
    c = COLLS["warehouse"]
    add_shelf("南仓库重型货架_A", -10.8, -13.55, 5.4)
    add_shelf("南仓库重型货架_B", -4.6, -13.55, 5.4)
    add_shelf("南仓库重型货架_C", 1.6, -13.55, 5.4)
    # Repair station and tool wall.
    add_box("南仓维修台_柜体", (8.2, -13.0, 0.95), (5.4, 1.35, 1.55), "metal", "dark_gray", 0.08, c, True)
    add_box("南仓维修台_厚钢台面", (8.2, -12.85, 1.78), (5.8, 1.65, 0.18), "metal", "mid_gray", 0.05, c)
    add_box("南仓工具墙", (8.2, -14.40, 3.20), (5.8, 0.16, 2.30), "matte", "teal", 0.035, c)
    for i in range(14):
        x = 5.75 + (i % 7) * 0.82
        z = 2.45 + (i // 7) * 0.85
        add_box(f"南仓工具挂件_{i:02d}", (x, -14.28, z), (0.10 + (i % 3) * 0.06, 0.10, 0.55),
                "metal", "yellow" if i % 4 == 0 else "light_gray", 0.02, COLLS["attachment"],
                rotation=(0, 0, math.radians((i % 5 - 2) * 7)))
    for i in range(10):
        add_box(f"零件盒_{i:02d}", (5.8 + (i % 5) * 0.85, -12.15, 2.12 + (i // 5) * 0.42),
                (0.68, 0.42, 0.30), "matte", "orange" if i % 2 else "cyan", 0.04, COLLS["attachment"])

    # Power and utilities east side.
    add_box("备用发电机_底座", (12.4, -9.4, 0.55), (3.5, 2.2, 0.85), "metal", "purple", 0.10, c, True)
    add_cylinder("备用发电机_转子罩", (12.4, -9.4, 1.20), 0.58, 2.25, "metal", "dark_gray", 24, c,
                 rotation=(0, math.pi / 2, 0))
    add_box("备用发电机_控制屏", (11.25, -8.65, 1.35), (0.82, 0.18, 0.62), "emit", "cyan", 0.04, c)
    for i in range(4):
        add_box(f"蓄电池组_{i}", (9.7 + i * 0.72, -8.65, 0.55), (0.58, 0.85, 0.85), "matte", "dark_gray", 0.06, c, True)
        add_box(f"蓄电池组_状态灯_{i}", (9.7 + i * 0.72, -8.18, 0.68), (0.22, 0.03, 0.12), "emit", "green", 0.015, c)
    add_box("南仓配电箱", (13.8, -12.35, 2.35), (1.55, 0.36, 2.15), "metal", "dark_gray", 0.08, c)
    add_text("南仓配电箱标签", "POWER", (13.8, -12.14, 2.65), 0.23, "emit", "red", 0.008,
             "CENTER", (math.pi / 2, 0, 0), c)
    add_beam("南仓电线桥架_主线", (-14.0, -10.7, 5.5), (14.0, -10.7, 5.5), 0.18, "metal", "dark_gray", c)
    for x in (-10, -5, 0, 5, 10):
        add_beam(f"南仓桥架吊杆_{x}", (x, -10.7, 5.5), (x, -10.7, 7.6), 0.06, "metal", "black", c)

    # Water, compressor, sanitation west side.
    add_cylinder("工业水箱", (-12.5, -9.55, 1.35), 1.10, 2.60, "metal", "mid_gray", 24, c, True)
    for i in range(3):
        add_beam(f"工业水箱箍带_{i}", (-12.5, -9.55, 0.55 + i * 0.8), (-12.5, -9.55, 0.58 + i * 0.8),
                 0.17, "metal", "purple", c)
    add_box("净水器", (-9.8, -9.25, 1.35), (1.7, 1.2, 2.6), "matte", "teal", 0.12, c, True)
    add_cylinder("净水器滤芯_A", (-10.2, -8.58, 1.10), 0.22, 1.45, "gloss", "cyan", 18, c)
    add_cylinder("净水器滤芯_B", (-9.55, -8.58, 1.10), 0.22, 1.45, "gloss", "cyan", 18, c)
    add_box("洗手台", (-7.3, -9.1, 0.95), (2.0, 1.2, 1.20), "metal", "light_gray", 0.10, c, True)
    add_cylinder("水管卷盘", (-13.85, -8.7, 2.75), 0.68, 0.28, "metal", "yellow", 24, c,
                 rotation=(math.pi / 2, 0, 0))
    add_box("空气压缩机", (-4.6, -9.0, 0.78), (2.3, 1.35, 1.25), "metal", "purple", 0.12, c, True)
    add_cylinder("空气压缩机储气罐", (-4.6, -9.0, 0.75), 0.52, 1.75, "metal", "dark_gray", 24, c,
                 rotation=(0, math.pi / 2, 0))
    add_box("水泵控制器", (-1.95, -9.0, 0.82), (1.35, 1.2, 1.45), "matte", "teal", 0.10, c, True)

    # Sorting / cleaning station.
    for i, (x, color, label) in enumerate([(3.7, "dark_gray", "WASTE"), (5.1, "red", "FLAMMABLE"), (6.5, "teal", "RECYCLE")]):
        add_box(f"分类垃圾箱_{label}", (x, -8.55, 0.72), (1.15, 1.05, 1.35), "matte", color, 0.10, c, True)
        add_text(f"分类垃圾箱标签_{label}", label, (x, -7.99, 0.85), 0.14, "emit", "light_gray", 0.006,
                 "CENTER", (math.pi / 2, 0, 0), c)
    for i, x in enumerate((8.1, 8.5, 8.9)):
        add_beam(f"清洁工具_{i}", (x, -8.2, 0.15), (x + 0.15 * i, -8.2, 2.15), 0.06, "metal", "yellow", c)

    # Wall boards and records.
    boards = [(-11.5, "BASE MAP"), (-7.5, "GEAR LIST"), (-3.5, "MISSION BOARD"),
              (0.5, "MAINTENANCE"), (4.5, "INVENTORY"), (8.5, "SAFETY RULES")]
    for i, (x, label) in enumerate(boards):
        add_box(f"南墙资料板_{i}", (x, -14.55, 5.0), (3.0, 0.12, 1.35), "matte", "wood" if i % 2 else "mid_gray", 0.04, c)
        add_text(f"南墙资料板标题_{i}", label, (x, -14.42, 5.35), 0.22, "emit", "yellow", 0.008,
                 "CENTER", (-math.pi / 2, 0, 0), c)
        for row in range(4):
            add_box(f"南墙资料板内容_{i}_{row}", (x, -14.41, 4.85 - row * 0.18), (2.25 - row * 0.18, 0.025, 0.025),
                    "emit", "light_gray", 0.002, c)


def build_lighting_and_motion() -> None:
    # Main warehouse pendant lamps with gentle sway.
    for idx, x in enumerate((-10, 0, 10)):
        for row, y in enumerate((-3.4, 3.4)):
            pivot = bpy.data.objects.new(f"仓库吊灯摆动轴_{idx}_{row}", None)
            COLLS["lights"].objects.link(pivot)
            pivot.location = (x, y, 8.1)
            cable = add_cylinder(f"仓库吊灯线缆_{idx}_{row}", (x, y, 7.65), 0.025, 0.9, "metal", "black", 10, COLLS["motion"])
            shade = add_cylinder(f"仓库防爆吊灯_{idx}_{row}", (x, y, 7.15), 0.62, 0.34, "metal", "dark_gray", 24, COLLS["motion"])
            glow = add_cylinder(f"仓库吊灯发光面_{idx}_{row}", (x, y, 6.95), 0.46, 0.08, "emit", "light_gray", 24, COLLS["motion"])
            light = add_area_light(f"仓库主吊灯光_{idx}_{row}", (x, y, 6.88), 620, (0.63, 0.82, 1.0), 3.2, (x, y, 0), idx == 1 and row == 0)
            for obj in (cable, shade, glow, light):
                obj.parent = pivot
                obj.matrix_parent_inverse = pivot.matrix_world.inverted()
            for frame, rx, ry in ((1, -1.2, 0.6), (80, 1.4, -0.8), (160, -0.9, 1.0), (240, -1.2, 0.6)):
                pivot.rotation_euler = (math.radians(rx), math.radians(ry), 0)
                pivot.keyframe_insert("rotation_euler", frame=frame)
    # Emergency lights at lane ends.
    for x in (-13.8, 13.8):
        add_box(f"主通道应急灯_{x}", (x, 0, 2.2), (0.22, 0.75, 0.32), "emit", "red", 0.045, COLLS["motion"])
        lamp = add_area_light(f"主通道应急红光_{x}", (x, 0, 2.15), 120, (1.0, 0.05, 0.03), 1.2, (0, 0, 0), False)
        animate_light_energy(lamp, [(1, 80), (55, 150), (110, 80), (165, 150), (240, 80)])
    # Steam wisps near the workshop and water plant.
    for group, origin in enumerate(((8.8, -11.5, 2.0), (-9.0, -9.4, 2.2))):
        for i in range(5):
            obj = add_sphere(f"设备蒸汽_{group}_{i}", (origin[0] + i * 0.08, origin[1], origin[2] + i * 0.18),
                             0.11 + i * 0.025, "gloss", "light_gray", COLLS["motion"])
            base_z = obj.location.z
            obj.scale = (0.4, 0.4, 0.4)
            obj.keyframe_insert("scale", frame=1 + i * 12)
            obj.keyframe_insert("location", frame=1 + i * 12)
            obj.location.z = base_z + 2.0
            obj.location.x += 0.35
            obj.scale = (1.3, 1.3, 1.3)
            obj.keyframe_insert("scale", frame=75 + i * 12)
            obj.keyframe_insert("location", frame=75 + i * 12)
            obj.location.z = base_z
            obj.location.x -= 0.35
            obj.scale = (0.4, 0.4, 0.4)
            obj.keyframe_insert("scale", frame=150 + i * 12)
            obj.keyframe_insert("location", frame=150 + i * 12)
    # Dust motes in the central beams.
    for i in range(28):
        x = -12 + (i * 2.37) % 24
        y = -6 + (i * 3.11) % 12
        z = 1.0 + (i * 1.73) % 6.5
        obj = add_sphere(f"光束尘埃_{i:02d}", (x, y, z), 0.022 + (i % 3) * 0.009, "emit", "light_gray", COLLS["motion"])
        obj.location.x += 0.35
        obj.location.z += 0.5
        obj.keyframe_insert("location", frame=120)
        obj.location.x -= 0.35
        obj.location.z -= 0.5
        obj.keyframe_insert("location", frame=240)


def add_camera(name, loc, target, ortho_scale) -> bpy.types.Object:
    data = bpy.data.cameras.new(name)
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    data.lens = 48
    obj = bpy.data.objects.new(name, data)
    COLLS["preview"].objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
    return obj


def build_preview() -> tuple[bpy.types.Object, bpy.types.Object, bpy.types.Object]:
    world = bpy.data.worlds.new("基地模型世界")
    bpy.context.scene.world = world
    world.use_nodes = True
    background = next((node for node in world.node_tree.nodes if node.type == "BACKGROUND"), None)
    if background is None:
        background = world.node_tree.nodes.new("ShaderNodeBackground")
        world_output = world.node_tree.nodes.new("ShaderNodeOutputWorld")
        world.node_tree.links.new(background.outputs["Background"], world_output.inputs["Surface"])
    background.inputs["Color"].default_value = (0.006, 0.008, 0.018, 1)
    background.inputs["Strength"].default_value = 0.30
    add_area_light("预览冷白主光", (4, -9, 24), 2600, (0.52, 0.72, 1.0), 12, (0, 1, 2), True, COLLS["preview"])
    add_area_light("预览蓝紫轮廓光", (-20, 11, 12), 1750, (0.25, 0.08, 1.0), 9, (0, 4, 3), False, COLLS["preview"])
    add_area_light("预览暖橙补光", (18, -18, 10), 1350, (1.0, 0.25, 0.06), 8, (5, -8, 2), False, COLLS["preview"])
    hero = add_camera("基地微缩模型_英雄相机", (32, -40, 27), (0, 1.5, 3.0), 35.5)
    top = add_camera("基地微缩模型_顶视相机", (0, 0, 46), (0, 0, 0), 35.0)
    detail = add_camera("基地微缩模型_阁楼下方近景相机", (0, -2.0, 3.2), (0, 14.0, 2.7), 15.0)
    return hero, top, detail


def validate_layout() -> None:
    offenders = []
    for obj in bpy.data.objects:
        if obj.type != "MESH" or not obj.get("ground_obstacle", False):
            continue
        if -7.48 < obj.location.y < 7.48 and obj.location.z < 2.5:
            offenders.append((obj.name, tuple(round(v, 3) for v in obj.location)))
    if offenders:
        raise RuntimeError("中央15x30m主通道存在地面障碍物: %s" % offenders[:20])
    uv_missing = []
    for coll_key in ("shell", "corridor", "mezz", "living", "facility", "warehouse", "attachment", "motion"):
        for obj in COLLS[coll_key].all_objects:
            if obj.type == "MESH" and "PaletteUV" not in obj.data.uv_layers:
                uv_missing.append(obj.name)
    if uv_missing:
        raise RuntimeError("输出网格缺少PaletteUV: %s" % uv_missing[:20])


def main() -> None:
    global SOURCE, OUTPUT
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)

    root = collection("基地99层高品质微缩模型_中文资产管理")
    root["asset_id"] = "ENV-BASE99-ART-LAYOUT-3D"
    root["version"] = "v003"
    root["space_m"] = (30.0, 30.0, 9.0)
    root["north_direction"] = "Blender +Y; Godot global -Z"
    root["coordinate_contract"] = "Blender local (X,Y,Z) -> Godot global (X,-9+Z,5-Y)"
    root["godot_room_global_origin"] = (0.0, -9.0, 5.0)
    root["main_corridor"] = "X[-15,15], Y[-7.5,7.5], east-west, ground obstacles forbidden"
    templates_coll = collection("00_资源模板_隐藏", root)
    templates_coll.hide_viewport = True
    templates_coll.hide_render = True
    SOURCE = collection("01_制作组件_已统一材质", root)
    # Keep editable sources selectable while operators build/convert text.
    # The collection is hidden only after construction and validation.
    SOURCE.hide_viewport = False
    SOURCE.hide_render = True
    OUTPUT = collection("02_游戏输出_整合模型", root)
    COLLS["shell"] = collection("10_保留墙体与地板", OUTPUT)
    COLLS["corridor"] = collection("20_中央东西主通道", OUTPUT)
    COLLS["mezz"] = collection("30_北侧楼中楼与L型楼梯", OUTPUT)
    COLLS["living"] = collection("31_阁楼生活区", OUTPUT)
    COLLS["facility"] = collection("40_阁楼下方视觉中心与固定设施", OUTPUT)
    COLLS["warehouse"] = collection("50_南侧仓库与辅助设施", OUTPUT)
    COLLS["attachment"] = collection("60_独立展示附件_不焊接", OUTPUT)
    COLLS["motion"] = collection("70_基础动效几何", OUTPUT)
    COLLS["lights"] = collection("80_实际灯光与动效", OUTPUT)
    COLLS["preview"] = collection("90_展示环境_灯光相机", root)

    create_materials()
    templates = {key: import_template(key, path, templates_coll) for key, path in ASSETS.items()}
    build_registered_shell(templates)
    build_corridor()
    build_mezzanine_and_stairs()
    build_bed_and_living()
    build_visual_center()
    build_vending()
    build_warehouse()
    build_lighting_and_motion()
    hero, top, detail = build_preview()

    # Major scene anchors carry runtime coordinate metadata.
    for name, asset_id in {
        "楼中楼_主承重楼板": "ENV-BASE99-MEZZANINE-20X10-Z5",
        "工业电视墙_主机壳": "PRP-BASE-RETRO-TV-STATION-3D",
        "复古工业自动贩卖机_机身": "PRP-BASE-VENDING-MACHINE-3D",
        "武器台锁柜主体": "PRP-BASE-WORKSHOP",
    }.items():
        obj = bpy.data.objects.get(name)
        if obj:
            tag_game_position(obj, asset_id)

    # Imported GLBs create temporary material datablocks. Their meshes have
    # already been remapped to the four shared palette roles, so purge only
    # genuinely unused material remnants before validation and delivery.
    for mat in list(bpy.data.materials):
        if mat not in MATS.values() and mat.users == 0:
            bpy.data.materials.remove(mat)
    for obj in bpy.data.objects:
        if obj.type == "MESH" and any(slot.material == MATS["emit"] for slot in obj.material_slots):
            if not any(token in obj.name.lower() for token in ("自发光", "ui灯光", "emissive", "glow")):
                obj.name += "_自发光"

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 1000
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.use_freestyle = True
    scene.render.line_thickness = 0.75
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 240
    scene.frame_set(48)
    scene.view_settings.look = "AgX - Medium High Contrast"

    scene.use_nodes = True
    nodes = scene.node_tree.nodes
    nodes.clear()
    render_layers = nodes.new("CompositorNodeRLayers")
    glare = nodes.new("CompositorNodeGlare")
    glare.glare_type = "FOG_GLOW"
    glare.quality = "HIGH"
    glare.threshold = 0.8
    glare.size = 7
    composite = nodes.new("CompositorNodeComposite")
    scene.node_tree.links.new(render_layers.outputs["Image"], glare.inputs["Image"])
    scene.node_tree.links.new(glare.outputs["Image"], composite.inputs["Image"])

    validate_layout()
    SOURCE.hide_viewport = True
    OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_HERO.parent.mkdir(parents=True, exist_ok=True)
    scene.camera = hero
    scene.render.filepath = str(OUTPUT_HERO)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), compress=True)
    bpy.ops.render.render(write_still=True)
    scene.camera = top
    scene.render.filepath = str(OUTPUT_TOP)
    bpy.ops.render.render(write_still=True)
    scene.camera = detail
    scene.render.filepath = str(OUTPUT_DETAIL)
    bpy.ops.render.render(write_still=True)
    scene.camera = hero
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), compress=True)
    print("BASE_HQ_LAYOUT_OK", OUTPUT_BLEND)
    print("BASE_HQ_HERO_OK", OUTPUT_HERO)
    print("BASE_HQ_TOP_OK", OUTPUT_TOP)
    print("BASE_HQ_DETAIL_OK", OUTPUT_DETAIL)


if __name__ == "__main__":
    main()
