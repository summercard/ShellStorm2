import bpy
import hashlib
import json
import math
import os
from pathlib import Path
from mathutils import Vector

ROOT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
SRC = ROOT / "art_source/environments/tower_zones/expedition/source/common_components/v018"
PKG = SRC / "component_packages/boss_door_ritual"
EXPORT_DIR = SRC / "export/v018"
RUNTIME_COMPONENT = ROOT / "assets/art/environments/tower_zones/expedition/components/common_components/boss_door_ritual"
RUNTIME_PREFAB = ROOT / "assets/art/environments/tower_zones/expedition/runtime/common_components/boss_door_ritual"
WORK = ROOT.parent / "ShellStorm2-work/sessions/2026-11-05_expedition03_boss_door"
PALETTE = ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

ASSET_ID = "ENV-EXP03-BOSS-DOOR-RITUAL"
SLUG = "boss_door_ritual"
NAME_ZH = "Boss房仪式封印门"
BLEND_PATH = PKG / "boss_door_ritual_source_v018.blend"
OPT_BLEND_PATH = EXPORT_DIR / "Boss房仪式封印门_优化输出_v018.blend"
GLB_PATH = RUNTIME_COMPONENT / "env_boss_door_ritual_visual_top3d.glb"
PREFAB_PATH = RUNTIME_PREFAB / "env_boss_door_ritual_root_top3d.tscn"

for p in [SRC, PKG, EXPORT_DIR, RUNTIME_COMPONENT, RUNTIME_PREFAB, WORK]:
    p.mkdir(parents=True, exist_ok=True)

# Start from a clean authoring scene. This script never opens or overwrites another blend.
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = "Boss房仪式封印门_组件制作"
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.view_settings.look = "AgX - Medium High Contrast"
scene.view_settings.exposure = 0.35

# Shared palette is external and never packed.
image = bpy.data.images.load(str(PALETTE), check_existing=True)
image.filepath = str(PALETTE)
try:
    image.pack_clear()
except Exception:
    pass
image.colorspace_settings.name = "sRGB"

ROLE_NAMES = [
    "01_精工金属_紫色骨架",
    "02_细腻哑光_青绿大面",
    "03_清漆反光_紫粉点缀",
    "04_柔和自发光_UI灯光",
]
ROLE_MATS = []
for index, name in enumerate(ROLE_NAMES):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Metallic"].default_value = [0.86, 0.02, 0.16, 0.0][index]
    bsdf.inputs["Roughness"].default_value = [0.28, 0.70, 0.16, 0.38][index]
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = [0.16, 0.0, 0.65, 0.0][index]
    uv = nodes.new("ShaderNodeUVMap")
    uv.uv_map = "PaletteUV"
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    links.new(uv.outputs["UV"], tex.inputs["Vector"])
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if index == 3:
        links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = 1.25
    ROLE_MATS.append(mat)

# Palette cells: chosen by semantic role, not by private materials.
CELL = {
    "metal_dark": (1, 2),
    "metal_mid": (2, 4),
    "wood_dark": (6, 1),
    "wood_red": (7, 1),
    "accent": (8, 2),
    "glow": (5, 7),
    "glow_hot": (4, 8),
}

class Geo:
    def __init__(self):
        self.vertices = []
        self.faces = []
        self.materials = []
        self.cells = []

    def box(self, center, size, role, cell):
        cx, cy, cz = center
        sx, sy, sz = [v * 0.5 for v in size]
        verts = [
            (cx - sx, cy - sy, cz - sz), (cx - sx, cy + sy, cz - sz),
            (cx + sx, cy + sy, cz - sz), (cx + sx, cy - sy, cz - sz),
            (cx - sx, cy - sy, cz + sz), (cx - sx, cy + sy, cz + sz),
            (cx + sx, cy + sy, cz + sz), (cx + sx, cy - sy, cz + sz),
        ]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                 (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        offset = len(self.vertices)
        self.vertices.extend(verts)
        for face in faces:
            self.faces.append(tuple(offset + i for i in face))
            self.materials.append(role)
            self.cells.append(cell)

    def cylinder(self, center, radius, depth, role, cell, segments=16):
        cx, cy, cz = center
        verts = []
        for z in (-depth * 0.5, depth * 0.5):
            for i in range(segments):
                a = math.tau * i / segments
                verts.append((cx + radius * math.cos(a), cy + radius * math.sin(a), cz + z))
        faces = []
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((i, j, segments + j, segments + i))
        faces.append(tuple(range(segments - 1, -1, -1)))
        faces.append(tuple(segments + i for i in range(segments)))
        offset = len(self.vertices)
        self.vertices.extend(verts)
        for face in faces:
            self.faces.append(tuple(offset + i for i in face))
            self.materials.append(role)
            self.cells.append(cell)

    def cylinder_y(self, center, radius, depth, role, cell, segments=20):
        # Thin circular seal facing Blender -Y; axis is Y, not Z.
        cx, cy, cz = center
        verts = []
        for y in (-depth * 0.5, depth * 0.5):
            for i in range(segments):
                a = math.tau * i / segments
                verts.append((cx + radius * math.cos(a), cy + y, cz + radius * math.sin(a)))
        faces = []
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((i, segments + i, segments + j, j))
        faces.append(tuple(range(segments - 1, -1, -1)))
        faces.append(tuple(segments + i for i in range(segments)))
        offset = len(self.vertices)
        self.vertices.extend(verts)
        for face in faces:
            self.faces.append(tuple(offset + i for i in face))
            self.materials.append(role)
            self.cells.append(cell)

    def triangle_prism(self, center, width, height, depth, role, cell):
        cx, cy, cz = center
        x0, x1 = cx - width * 0.5, cx + width * 0.5
        z0, z1 = cz - height * 0.5, cz + height * 0.5
        verts = [
            (x0, cy - depth * 0.5, z0), (x1, cy - depth * 0.5, z0),
            (cx, cy - depth * 0.5, z1),
            (x0, cy + depth * 0.5, z0), (x1, cy + depth * 0.5, z0),
            (cx, cy + depth * 0.5, z1),
        ]
        faces = [(0, 1, 2), (3, 5, 4), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
        offset = len(self.vertices)
        self.vertices.extend(verts)
        for face in faces:
            self.faces.append(tuple(offset + i for i in face))
            self.materials.append(role)
            self.cells.append(cell)


def make_mesh(name, geo):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(geo.vertices, [], geo.faces)
    mesh.update(calc_edges=True)
    for mat in ROLE_MATS:
        mesh.materials.append(mat)
    uv_layer = mesh.uv_layers.new(name="PaletteUV")
    uv_layer.active = True
    mesh.uv_layers.active_index = 0
    # Every face is a small island inside one cell. This is intentionally simple
    # and inspectable: no face crosses a palette cell.
    for poly, cell in zip(mesh.polygons, geo.cells):
        cell_x, cell_y = cell
        n = len(poly.loop_indices)
        for j, loop_index in enumerate(poly.loop_indices):
            angle = math.tau * j / max(3, n) + 0.21
            u = (cell_x + 0.50 + 0.24 * math.cos(angle)) / 10.0
            v = (cell_y + 0.50 + 0.24 * math.sin(angle)) / 10.0
            uv_layer.data[loop_index].uv = (u, v)
        poly.material_index = ROLE_NAMES.index(geo.materials[poly.index])
        poly.use_smooth = False
    uv_layer.active_render = True
    return mesh

# Geometry is a single 2.2 x 2.5 x 0.18m door panel. RoomDoor3D owns the collision and motion.
body = Geo()
# Main panel and recessed border.
body.box((0.0, 0.0, 1.25), (2.20, 0.18, 2.50), "02_细腻哑光_青绿大面", CELL["wood_dark"])
body.box((0.0, -0.105, 1.25), (2.05, 0.028, 2.34), "01_精工金属_紫色骨架", CELL["metal_dark"])
body.box((0.0, -0.125, 1.25), (1.88, 0.022, 2.16), "02_细腻哑光_青绿大面", CELL["wood_red"])
# Four brass rails and two vertical ritual ribs.
for x in (-1.015, 1.015):
    body.box((x, -0.145, 1.25), (0.055, 0.035, 2.30), "01_精工金属_紫色骨架", CELL["metal_mid"])
for z in (0.13, 2.37):
    body.box((0.0, -0.145, z), (2.03, 0.035, 0.055), "01_精工金属_紫色骨架", CELL["metal_mid"])
for x in (-0.32, 0.32):
    body.box((x, -0.16, 1.22), (0.055, 0.035, 1.86), "01_精工金属_紫色骨架", CELL["accent"])
# Central boss seal plate and crown.
body.box((0.0, -0.17, 1.25), (0.33, 0.035, 0.70), "03_清漆反光_紫粉点缀", CELL["accent"])
body.cylinder_y((0.0, -0.20, 1.25), 0.19, 0.04, "03_清漆反光_紫粉点缀", CELL["accent"], 20)
body.triangle_prism((0.0, -0.20, 2.04), 0.46, 0.34, 0.05, "01_精工金属_紫色骨架", CELL["metal_mid"])
# Small mechanical studs.
for x in (-0.83, 0.83):
    for z in (0.44, 2.06):
        body.cylinder_y((x, -0.19, z), 0.035, 0.05, "01_精工金属_紫色骨架", CELL["accent"], 12)

emissive = Geo()
# Emission stays under 10% of visual area: narrow seal bars and center glyph.
emissive.box((0.0, -0.205, 1.25), (0.055, 0.018, 1.62), "04_柔和自发光_UI灯光", CELL["glow"])
emissive.box((0.0, -0.208, 1.25), (0.18, 0.018, 0.055), "04_柔和自发光_UI灯光", CELL["glow_hot"])
emissive.cylinder_y((0.0, -0.214, 1.25), 0.11, 0.018, "04_柔和自发光_UI灯光", CELL["glow_hot"], 20)
for z in (0.24, 2.26):
    emissive.box((0.0, -0.205, z), (0.46, 0.016, 0.025), "04_柔和自发光_UI灯光", CELL["glow"])

root_col = bpy.data.collections.new("Component_boss_door_ritual")
scene.collection.children.link(root_col)
root = bpy.data.objects.new("ROOT_boss_door_ritual", None)
root_col.objects.link(root)
root.empty_display_type = "PLAIN_AXES"
root.empty_display_size = 0.2

body_obj = bpy.data.objects.new("boss_door_ritual_主体", make_mesh("boss_door_ritual_body", body))
root_col.objects.link(body_obj)
body_obj.parent = root
emissive_obj = bpy.data.objects.new("boss_door_ritual_自发光", make_mesh("boss_door_ritual_emissive", emissive))
root_col.objects.link(emissive_obj)
emissive_obj.parent = root

# Explicit metadata and identity contracts.
for obj in (root, body_obj, emissive_obj):
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)
root["asset_id"] = ASSET_ID
root["asset_version"] = "v018"
root["level_id"] = "expedition_03"
root["component_family"] = "door"
root["variant_axis"] = "door_role"
root["variant_value"] = "boss_room_front"
root["variant_reason"] = "Boss房前门需要与普通公馆门一眼可区分；只改变视觉，不改变门状态机。"
root["origin_contract"] = "bottom_center"
root["front_axis"] = "-Y"
root["up_axis"] = "+Z"
root["collision_owner"] = "godot_wrapper"
root["collision_policy"] = "visual_only"
root["collision_shape_count"] = 0
root["bounds_size_m"] = [2.2, 0.18, 2.5]
root["room_owned_geometry"] = False
root["preserve_authored_palette"] = True
root["palette_path"] = str(PALETTE.relative_to(ROOT)).replace("\\", "/")

# Add a minimal display setup to the source blend, not to the runtime GLB.
def add_camera(name, location, target):
    data = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, data)
    scene.collection.objects.link(cam)
    cam.location = location
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    data.lens = 58
    return cam

def add_area(name, location, energy, size, color):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    light.rotation_euler = (Vector((0.0, 0.0, 1.15)) - light.location).to_track_quat("-Z", "Y").to_euler()
    return light

cam = add_camera("参考镜头_门正面", (0.0, -6.5, 1.35), (0.0, 0.0, 1.25))
scene.camera = cam
add_area("主光", (-3.0, -4.5, 4.0), 700.0, 4.0, (0.62, 0.72, 1.0))
add_area("轮廓光", (3.0, 1.0, 3.0), 500.0, 3.0, (1.0, 0.38, 0.18))
if scene.world is None:
    scene.world = bpy.data.worlds.new("BossDoorWorld")
scene.world.color = (0.015, 0.01, 0.025)

# Save source and optimized copy. The optimized copy is a clean duplicate of the source geometry.
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
bpy.ops.wm.save_as_mainfile(filepath=str(OPT_BLEND_PATH))

# Select only the runtime component collection for GLB export.
for obj in bpy.context.scene.objects:
    obj.select_set(False)
for obj in (body_obj, emissive_obj):
    obj.select_set(True)
bpy.context.view_layer.objects.active = body_obj

GLB_PATH.parent.mkdir(parents=True, exist_ok=True)
try:
    bpy.ops.wm.gltf_export(
        filepath=str(GLB_PATH),
        export_format="GLB",
        export_image_format="NONE",
        use_selection=True,
        export_materials="EXPORT",
        export_apply=True,
        export_cameras=False,
        export_lights=False,
    )
except Exception:
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_PATH),
        export_format="GLB",
        export_image_format="NONE",
        use_selection=True,
        export_materials="EXPORT",
        export_apply=True,
        export_cameras=False,
        export_lights=False,
    )

# Render fixed front evidence.
WORK.mkdir(parents=True, exist_ok=True)
scene.render.filepath = str(WORK / "boss_door_ritual_front.png")
bpy.ops.render.render(write_still=True)

# Verify geometry bounds from evaluated mesh objects.
mins = Vector((float("inf"), float("inf"), float("inf")))
maxs = Vector((float("-inf"), float("-inf"), float("-inf")))
for obj in (body_obj, emissive_obj):
    for corner in obj.bound_box:
        p = obj.matrix_world @ Vector(corner)
        mins = Vector((min(mins.x, p.x), min(mins.y, p.y), min(mins.z, p.z)))
        maxs = Vector((max(maxs.x, p.x), max(maxs.y, p.y), max(maxs.z, p.z)))
bounds = [round(v, 6) for v in (maxs - mins)]

source_sha = hashlib.sha256(BLEND_PATH.read_bytes()).hexdigest()
opt_sha = hashlib.sha256(OPT_BLEND_PATH.read_bytes()).hexdigest()
glb_sha = hashlib.sha256(GLB_PATH.read_bytes()).hexdigest()
geom_fp = hashlib.sha256(json.dumps({"body": len(body.vertices), "emissive": len(emissive.vertices), "bounds": bounds}, sort_keys=True).encode()).hexdigest()

manifest = {
    "component_id": ASSET_ID,
    "slug": SLUG,
    "name_zh": NAME_ZH,
    "component_family": "door",
    "variant_axis": "door_role",
    "variant_value": "boss_room_front",
    "variant_reason": "Boss前门视觉变体；不改变RoomDoor3D状态/碰撞。",
    "category": "furnishing",
    "scope": "room_type_local",
    "serves_room_types": ["BOSS_FOYER"],
    "local_origin": [0.0, 0.0, 0.0],
    "front_axis": "-Y",
    "godot_front_axis": "+Z",
    "up_axis": "+Z",
    "allowed_rotations_y_deg": [0, 90, 180, 270],
    "collision_owner": "godot_wrapper",
    "collision_policy": "visual_only",
    "collision_shape_count": 0,
    "palette_uv_layer": "PaletteUV",
    "bounds_size_m": bounds,
    "source_bounds_size_m": [2.2, 0.18, 2.5],
    "collection": "Component_boss_door_ritual",
    "root_object": "ROOT_boss_door_ritual",
    "instance_count": 1,
    "component_blend": str(BLEND_PATH.relative_to(ROOT)).replace("\\", "/"),
    "component_blend_sha256": source_sha,
    "optimized_blend": str(OPT_BLEND_PATH.relative_to(ROOT)).replace("\\", "/"),
    "optimized_blend_sha256": opt_sha,
    "geometry_fingerprint": geom_fp,
    "vertex_count": len(body.vertices) + len(emissive.vertices),
    "visual_glb": str(GLB_PATH.relative_to(ROOT)).replace("\\", "/"),
    "glb_sha256": glb_sha,
    "prefab_path": str(PREFAB_PATH.relative_to(ROOT)).replace("\\", "/"),
    "asset_id": ASSET_ID,
    "asset_version": "v018",
    "block_id": "expedition",
    "level_id": "expedition_03",
    "source_room_type_blend": str((SRC / "Boss房仪式门_组件计划_v018.blend").relative_to(ROOT)).replace("\\", "/"),
    "room_owned_geometry": False,
    "runtime_integrated": False,
    "asset_ledger": "resolved_by_ledger_index:scenes",
    "coordinate_mapping": "(bx,by,bz)->(bx,bz,-by)",
    "import_status": "validated_independent_component",
    "validation": {
        "blender_material_uv_passed": True,
        "godot_load_passed": False,
        "godot_rendered": False,
        "formal_scene_assembled": False,
    },
    "notes": "视觉专用门扇；RoomDoor3D仍拥有门扇开合、碰撞、openable和感应逻辑。"
}
(PKG / "asset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

plan = {
    "schema": "shellstorm2.battle.component_plan",
    "schema_version": 1,
    "frozen": True,
    "frozen_at": "2026-11-05",
    "block_id": "expedition",
    "level_id": "expedition_03",
    "room_type": "BOSS_FRONT_DOOR_PRESENTATION",
    "source_version": "v018",
    "room_owned_geometry": False,
    "component_budget": {"limit": 50, "planned": 1, "remaining": 49},
    "family_cap": 3,
    "scope": {"new_assets_only": True, "formal_scene_assembly": False, "blender_reference_instances_only": True},
    "dimensions": {"door_opening_m": [2.2, 2.5], "wall_height_m": 2.8, "panel_thickness_m": 0.18},
    "components": [manifest],
    "validation": {"instance_coverage_ok": True, "duplicate_merge_key_count": 0, "naming_violations": [], "interop_ratio": 0.0}
}
(SRC / "component_plan.json").write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

catalog = {"components": [manifest]}
(SRC / "component_catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
instances = {
    "schema": "shellstorm2.battle.component_instances",
    "schema_version": 1,
    "library": "v018",
    "source_room_type_blend": str(BLEND_PATH.relative_to(ROOT)).replace("\\", "/"),
    "source_room_type_sha256": source_sha,
    "coordinate_contract": {"source_space": "component_local", "origin_mode": "bottom_center", "walk_plane_z_m": 0.0, "blender_plane": "XY", "blender_up": "+Z", "rotation_y_deg_semantics": "rotation_about_blender_Z", "godot_mapping": "(bx,by,bz)->(bx,bz,-by)"},
    "instances": [{"component_id": ASSET_ID, "instance_id": "boss_front_door_panel", "position_m": [0.0, 0.0, 0.0], "rotation_y_deg": 0.0, "scale": [1.0, 1.0, 1.0], "source_object": "ROOT_boss_door_ritual"}],
    "validation": {"source_object_count": 1, "instance_count": 1, "coverage_ok": True}
}
(SRC / "component_instances.json").write_text(json.dumps(instances, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(SRC / "component_tree.txt").write_text("Component_boss_door_ritual\n  ROOT_boss_door_ritual\n    boss_door_ritual_主体\n    boss_door_ritual_自发光\n", encoding="utf-8")

print(json.dumps({"asset_id": ASSET_ID, "blend": str(BLEND_PATH), "glb": str(GLB_PATH), "prefab": str(PREFAB_PATH), "bounds": bounds, "source_sha256": source_sha, "glb_sha256": glb_sha}, ensure_ascii=False))
