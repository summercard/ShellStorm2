import bpy
import bmesh
import hashlib
import json
import math
import shutil
import struct
import re
import subprocess
import sys
from pathlib import Path

from mathutils import Vector


PROJECT = Path(__file__).resolve().parents[2]
ASSET = "ENV-OPENWORLD-LANDSCAPE-SKYLINE20"
VERSION = "v007"
BASE = PROJECT / "assets/art/environments/open_world"
SRC = BASE / "source/landscape_skyline20" / VERSION
SOURCE_BLEND = SRC / f"env_landscape_skyline20_source_{VERSION}.blend"
EXPORT_DIR = SRC / "export" / VERSION
OPT_BLEND = EXPORT_DIR / f"env_landscape_skyline20_optimized_{VERSION}.blend"
PALETTE = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
REF = Path(r"C:/Users/zhuangmenghong/.workbuddy/clipboard-images/clipboard-2026-10-07T10-04-50-910Z-8b3f7c5f.jpg")
VALIDATOR = PROJECT / ".codex/skills/blender-game-prop-standard/scripts/validate_game_prop.py"
PROTECTED_FILES = [
    PALETTE, PALETTE.with_suffix(".png.import"),
    *sorted((SRC.parent / "v005").rglob("*.blend")),
    *sorted((SRC.parent / "v006").rglob("*")),
    *sorted((PROJECT / "source/art/whitebox/landscape_skyline20/v006").rglob("*")),
    *sorted((BASE / "components/landscape_skyline20/roof_hvac_bank").rglob("*")),
    *sorted((BASE / "components/landscape_skyline20/roof_communications").rglob("*")),
    *sorted((BASE / "runtime/landscape_skyline20/roof_hvac_bank").rglob("*")),
    *sorted((BASE / "runtime/landscape_skyline20/roof_communications").rglob("*")),
]
protected_hashes_before = {str(path.relative_to(PROJECT).as_posix()): hashlib.sha256(path.read_bytes()).hexdigest()
                           for path in PROTECTED_FILES if path.is_file()}

for path in [SRC, SRC / "previews", SRC / "qa", SRC / "references", EXPORT_DIR]:
    path.mkdir(parents=True, exist_ok=True)
if not REF.is_file():
    raise RuntimeError(f"用户参考图不存在: {REF}")
shutil.copy2(REF, SRC / "references/用户参考_景观建筑.jpg")
bpy.context.preferences.filepaths.save_version = 0


def protected_file_report():
    after = {key: hashlib.sha256((PROJECT / key).read_bytes()).hexdigest() for key in protected_hashes_before}
    report = {"before": protected_hashes_before, "after": after, "unchanged": after == protected_hashes_before}
    (SRC / "qa/protected_files.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if not report["unchanged"]:
        raise RuntimeError("v005/v006、旧区域包或公共色盘保护哈希变化，阻止导出")
    return report
protected_file_report()
(SRC / ".gdignore").write_text("# Blender源、参考图、优化证据不作为Godot资源导入。\n", encoding="utf-8")

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
scene["asset_id"] = ASSET
scene["version"] = VERSION
scene["block_id"] = "open_world"
scene["floor_range"] = "1F-20F + rooftop"
scene["design_scope"] = "50m x 50m；20层；3.8m美术层高；无底层独立结构；屋顶重点"
scene["collision_status"] = "none_visual_only"
scene["triangle_budget"] = 10000
scene["reference_image"] = "references/用户参考_景观建筑.jpg"

palette = bpy.data.images.load(str(PALETTE), check_existing=True)
role_names = [
    "01_精工金属_紫色骨架",
    "02_细腻哑光_青绿大面",
    "03_清漆反光_紫粉点缀",
    "04_柔和自发光_UI灯光",
]
role_params = [(0.86, 0.28, 0.18), (0.02, 0.70, 0.0), (0.18, 0.14, 0.68), (0.0, 0.38, 0.0)]
mats = []
for index, name in enumerate(role_names):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    metallic, roughness, coat = role_params[index]
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
    uv_node = nodes.new("ShaderNodeUVMap")
    uv_node.uv_map = "PaletteUV"
    image_node = nodes.new("ShaderNodeTexImage")
    image_node.image = palette
    image_node.interpolation = "Closest"
    links.new(uv_node.outputs["UV"], image_node.inputs["Vector"])
    links.new(image_node.outputs["Color"], bsdf.inputs["Base Color"])
    if index == 3:
        if "Emission Color" in bsdf.inputs:
            links.new(image_node.outputs["Color"], bsdf.inputs["Emission Color"])
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = 1.15
    mats.append(material)

root = bpy.data.collections.new("landscape_skyline20_景观建筑_中文资产管理")
scene.collection.children.link(root)
source_col = bpy.data.collections.new("01_制作组件_按组件拆分_v007")
source_col.hide_viewport = True
source_col.hide_render = True
root.children.link(source_col)
output_col = bpy.data.collections.new("02_游戏输出_独立资产包_v007")
root.children.link(output_col)
preview_col = bpy.data.collections.new("90_展示与验收_固定灯光相机_v007")
root.children.link(preview_col)

# Unlinked component collections are deliberate: they are exportable masters and are
# only visible in the building through Collection Instance objects.
component_collections = {}

def component_collection(slug):
    collection = bpy.data.collections.new(f"02_游戏输出_{slug}_资产包")
    collection["asset_id"] = f"{ASSET}-{slug.upper().replace('_', '-') }"
    collection["version"] = VERSION
    collection["instance_offset"] = [0.0, 0.0, 0.0]
    collection.instance_offset = Vector((0.0, 0.0, 0.0))
    component_collections[slug] = collection
    return collection


# Palette cells are (column, row), with row counted from the top. Windows are neutral
# grey cells; the existing dark-yellow cell remains reserved for rails and warm accents.
C_METAL = (9, 6)
C_DARK = (9, 1)
C_BODY = (9, 6)
C_BODY2 = (9, 5)
C_WINDOW = (6, 2)
C_WINDOW2 = (7, 2)
C_ACCENT = (5, 2)
C_GOLD = (6, 3)
C_LIGHT = (9, 9)
C_SIGN = (6, 3)
C_GREEN = (6, 4)

# 正式网格之前冻结语义定义、实际尺寸意图与参考摆位；方位只属于实例。
plan_definitions = [
    ("floor_facade_module", "repeat_floor_facade", 20, "灰墙与暖色窄窗；无每层灯带"),
    ("facade_hvac_unit", "external_ac_unit", 6, "单一母版；实例旋转朝外"),
    ("roof_guardrail_kit", "roof_structure", 1, "灰色屋面与黄色护栏"),
    ("roof_service_hut", "roof_service_hut", 1, "14x12m大型机房及直接附属通风罩"),
    ("roof_hvac_unit", "roof_hvac_unit", 4, "6x5x3.6m单台母版；四区分散；真实八边风扇"),
    ("roof_satellite_dish", "roof_satellite_dish", 1, "9m实心抛物面与独立深灰支架"),
    ("roof_truss_tower", "roof_truss_tower", 2, "8.5m通信塔母版；接收板与暖灯"),
    ("facade_billboard", "billboard_cityscape", 2, "16x30m竖幅；太阳城市剪影和SKYLINE七字"),
]
roof_layout = [
    ("roof_service_hut", "roof_service_hut", (0, 0, 76.36), 0),
    ("roof_hvac_unit", "roof_hvac_01", (-16, -15, 76.36), 0),
    ("roof_hvac_unit", "roof_hvac_02", (15, -16, 76.36), 90),
    ("roof_hvac_unit", "roof_hvac_03", (-16, 4, 76.36), 270),
    ("roof_hvac_unit", "roof_hvac_04", (8, 17, 76.36), 180),
    ("roof_satellite_dish", "roof_dish", (15, 4, 76.36), 0),
    ("roof_truss_tower", "roof_tower_01", (-17, 17, 76.36), 0),
    ("roof_truss_tower", "roof_tower_02", (-7, 17, 76.36), 0),
]
planned_dimensions = {
    "floor_facade_module": [50, 50, 3.8], "roof_service_hut": [14.6, 12.6, 6.6],
    "roof_hvac_unit": [6, 5, 3.6], "roof_satellite_dish": [9.2, 8, 10],
    "roof_truss_tower": [3.2, 3.2, 8.5], "facade_billboard": [16, 0.6, 30],
}
assert len(plan_definitions) <= 50
assert len({family for _, family, _, _ in plan_definitions}) == len(plan_definitions)
freeze_plan = {
    "schema": "shellstorm2.openworld.component_plan",
    "schema_version": 2,
    "asset_id": ASSET,
    "source_version": VERSION,
    "block_id": "open_world",
    "component_budget": {"limit": 50, "planned": len(plan_definitions), "remaining": 50 - len(plan_definitions), "status": "frozen_before_formal_geometry"},
    "freeze_stage": "before_builder_and_mesh_creation",
    "floor_count": 20, "floor_height_m": 3.8, "roof_z_m": 76.0,
    "design_scope": "50x50m主体；20层；无底层、室内、玩法、碰撞；屋顶优先",
    "reference_image": "references/用户参考_景观建筑.jpg",
    "planned_dimensions_m": planned_dimensions,
    "roof_layout_reference": [{"slug": slug, "instance_id": name, "position_m": list(pos), "rotation_y_deg": angle} for slug, name, pos, angle in roof_layout],
    "inactive_preserved_components": ["roof_hvac_bank", "roof_communications"],
    "triangle_budget": {"limit": 10000, "metric": "runtime_instance_triangles", "roof_share_target": 0.45},
    "definitions": [{"component_id": f"{ASSET}-{slug.upper().replace('_', '-')}", "slug": slug,
                     "component_family": family, "instance_count": count, "variant_reason": reason}
                    for slug, family, count, reason in plan_definitions],
}
(SRC / "component_plan.json").write_text(json.dumps(freeze_plan, ensure_ascii=False, indent=2), encoding="utf-8")
(SRC / "qa/component_plan_frozen_before_mesh.json").write_text(json.dumps(freeze_plan, ensure_ascii=False, indent=2), encoding="utf-8")
plan_frozen_hash = hashlib.sha256((SRC / "component_plan.json").read_bytes()).hexdigest()


class Builder:
    def __init__(self, slug, display, material_roles=(0, 1, 2)):
        self.slug = slug
        self.display = display
        self.material_roles = tuple(material_roles)
        self.vertices = []
        self.faces = []
        self.colors = []
        self.role_indices = []

    def _add(self, vertices, faces, color, role_index):
        start = len(self.vertices)
        self.vertices.extend(tuple(vertex) for vertex in vertices)
        for face in faces:
            self.faces.append(tuple(start + index for index in face))
            self.colors.append(color)
            self.role_indices.append(role_index)

    def box(self, center, size, color=C_BODY, role_index=1, bevel=0.0):
        x, y, z = center
        sx, sy, sz = [value * 0.5 for value in size]
        if bevel > 0.0 and min(sx, sy) > bevel:
            t = min(bevel, sz * 0.45)
            ring = [(-sx + t, -sy), (sx - t, -sy), (sx, -sy + t), (sx, sy - t),
                    (sx - t, sy), (-sx + t, sy), (-sx, sy - t), (-sx, -sy + t)]
            vertices = [(x + u, y + v, z + q) for q in (-sz, sz) for u, v in ring]
            faces = [tuple(reversed(range(8))), tuple(range(8, 16))]
            faces += [(index, (index + 1) % 8, (index + 1) % 8 + 8, index + 8) for index in range(8)]
        else:
            vertices = [(x + i * sx, y + j * sy, z + k * sz)
                        for i, j, k in [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
                                        (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]]
            faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                     (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        self._add(vertices, faces, color, role_index)

    def rod(self, start, end, radius=0.08, color=C_METAL, role_index=0, sides=6):
        point_a, point_b = Vector(start), Vector(end)
        direction = point_b - point_a
        if direction.length < 1.0e-5:
            return
        direction.normalize()
        basis_u = direction.cross(Vector((0.0, 0.0, 1.0)))
        if basis_u.length < 1.0e-4:
            basis_u = direction.cross(Vector((0.0, 1.0, 0.0)))
        basis_u.normalize()
        basis_v = direction.cross(basis_u).normalized()
        vertices = []
        for point in (point_a, point_b):
            for index in range(sides):
                angle = index * math.tau / sides
                vertices.append(tuple(point + radius * (math.cos(angle) * basis_u + math.sin(angle) * basis_v)))
        faces = [tuple(reversed(range(sides))), tuple(range(sides, 2 * sides))]
        faces += [(index, (index + 1) % sides, (index + 1) % sides + sides, index + sides)
                  for index in range(sides)]
        self._add(vertices, faces, color, role_index)

    def panel(self, coordinates, y, color=C_BODY, role_index=1, thickness=0.08, solid=True):
        count = len(coordinates)
        vertices = [(x, y - thickness * 0.5, z) for x, z in coordinates]
        if solid:
            vertices += [(x, y + thickness * 0.5, z) for x, z in coordinates]
            faces = [tuple(reversed(range(count))), tuple(range(count, 2 * count))]
            faces += [(index, (index + 1) % count, (index + 1) % count + count, index + count)
                      for index in range(count)]
        else:
            # Exterior window sheets are visible from the facade side; avoid hidden
            # thickness faces while retaining a real area polygon and PaletteUV.
            faces = [tuple(range(count)) if y < 0 else tuple(reversed(range(count)))]
        self._add(vertices, faces, color, role_index)

    def panel_x(self, coordinates, x, color=C_BODY, role_index=1, thickness=0.08, solid=False):
        count = len(coordinates)
        vertices = [(x - thickness * 0.5, y, z) for y, z in coordinates]
        if solid:
            vertices += [(x + thickness * 0.5, y, z) for y, z in coordinates]
            faces = [tuple(reversed(range(count))), tuple(range(count, 2 * count))]
            faces += [(index, (index + 1) % count, (index + 1) % count + count, index + count)
                      for index in range(count)]
        else:
            faces = [tuple(range(count)) if x > 0 else tuple(reversed(range(count)))]
        self._add(vertices, faces, color, role_index)

    def dish(self, center, radius=2.0, depth=0.75, color=C_BODY, role_index=1, segments=12, rings=3):
        cx, cy, cz = center
        vertices = [(cx, cy - depth, cz)]
        for ring in range(1, rings + 1):
            ratio = ring / rings
            ring_radius = radius * ratio
            ring_y = cy - depth * (1.0 - ratio * ratio)
            for index in range(segments):
                angle = index * math.tau / segments
                vertices.append((cx + ring_radius * math.cos(angle), ring_y,
                                 cz + ring_radius * math.sin(angle)))
        faces = []
        for index in range(segments):
            faces.append((0, 1 + index, 1 + (index + 1) % segments))
        for ring in range(1, rings):
            a = 1 + (ring - 1) * segments
            b = 1 + ring * segments
            for index in range(segments):
                faces.append((a + index, b + index, b + (index + 1) % segments, a + (index + 1) % segments))
        # 封闭碟背与碟沿，保留抛物面，不用透明单面片冒充实心天线。
        count = len(vertices)
        vertices += [(x, y + 0.10, z) for x, y, z in vertices]
        front_faces = list(faces)
        faces += [tuple(index + count for index in reversed(face)) for face in front_faces]
        rim = 1 + (rings - 1) * segments
        faces += [(rim + index, rim + (index + 1) % segments,
                   rim + (index + 1) % segments + count, rim + index + count)
                  for index in range(segments)]
        self._add(vertices, faces, color, role_index)

    def finish(self, collection, role_offset=0, suffix="主体"):
        mesh = bpy.data.meshes.new(f"{self.display}_{suffix}_Mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update(calc_edges=True)
        normal_mesh = bmesh.new()
        normal_mesh.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(normal_mesh, faces=list(normal_mesh.faces))
        normal_mesh.to_mesh(mesh)
        normal_mesh.free()
        for role_index in self.material_roles:
            mesh.materials.append(mats[role_index])
        palette_uv = mesh.uv_layers.new(name="PaletteUV")
        mesh.uv_layers.active = palette_uv
        palette_uv.active_render = True
        for polygon, color, role_index in zip(mesh.polygons, self.colors, self.role_indices):
            polygon.material_index = self.material_roles.index(role_index)
            column, row = color
            center_u = (column + 0.5) / 10.0
            center_v = 1.0 - (row + 0.5) / 10.0
            loops = list(polygon.loop_indices)
            for loop_index, loop in enumerate(loops):
                angle = math.tau * loop_index / max(3, len(loops))
                palette_uv.data[loop].uv = (center_u + 0.025 * math.cos(angle),
                                             center_v + 0.025 * math.sin(angle))
        obj = bpy.data.objects.new(f"{self.display}_{suffix}", mesh)
        collection.objects.link(obj)
        obj.location = Vector((0.0, 0.0, 0.0))
        obj.rotation_euler = (0.0, 0.0, 0.0)
        obj.scale = (1.0, 1.0, 1.0)
        obj["asset_id"] = ASSET
        obj["version"] = VERSION
        obj["component_slug"] = self.slug
        obj["front_direction"] = "-Y"
        obj["local_origin"] = "bottom_center"
        obj["collision_status"] = "none_visual_only"
        obj["fixed_display_attachment"] = True
        return obj


def make_component(slug, display, body_builder, glow_builder=None):
    collection = component_collection(slug)
    root_obj = bpy.data.objects.new(f"Root_{slug}", None)
    collection.objects.link(root_obj)
    root_obj.empty_display_type = "PLAIN_AXES"
    root_obj.empty_display_size = 0.25
    root_obj.location = (0.0, 0.0, 0.0)
    root_obj.rotation_euler = (0.0, 0.0, 0.0)
    root_obj.scale = (1.0, 1.0, 1.0)
    root_obj["component_slug"] = slug
    body_obj = body_builder.finish(collection, suffix="主体")
    glow_obj = glow_builder.finish(collection, suffix="自发光") if glow_builder and glow_builder.faces else None
    mesh_objects = [obj for obj in (body_obj, glow_obj) if obj]
    points = [vertex.co.copy() for obj in mesh_objects for vertex in obj.data.vertices]
    lows = [min(point[axis] for point in points) for axis in range(3)]
    highs = [max(point[axis] for point in points) for axis in range(3)]
    geometry_offset = Vector(((lows[0] + highs[0]) * 0.5, (lows[1] + highs[1]) * 0.5, lows[2]))
    collection["geometry_offset_m"] = list(geometry_offset)
    for obj in mesh_objects:
        for vertex in obj.data.vertices:
            vertex.co -= geometry_offset
        obj.data.update()
        obj.parent = root_obj
        obj.matrix_parent_inverse.identity()
        obj["root_transform_contract"] = "identity"
    root_obj["geometry_offset_m"] = list(geometry_offset)
    # Editable source copies are kept in the hidden source collection, while the
    # displayed building is made only from Collection Instance objects.
    source_component = bpy.data.collections.new(f"制作源_{slug}")
    source_component.hide_viewport = True
    source_component.hide_render = True
    source_col.children.link(source_component)
    source_root = root_obj.copy()
    source_root.data = None
    source_root.name = f"Root_{slug}_制作源"
    source_component.objects.link(source_root)
    for obj in [body_obj, glow_obj]:
        if obj:
            source_copy = obj.copy()
            source_copy.data = obj.data.copy()
            source_copy.name = obj.name + "_制作源"
            source_copy.parent = source_root
            source_component.objects.link(source_copy)
    return {"collection": collection, "root": root_obj, "body": body_obj, "glow": glow_obj}


components = {}

# The repeated module has no separate bottom storey: it is the complete 3.8m art
# module and is instanced twenty times.
floor_body = Builder("floor_facade_module", "重复楼层_外立面窗墙模块")
floor_body.box((0, 0, 1.90), (49.9, 49.9, 3.80), C_BODY, 1)
floor_body.box((0, 0, 3.70), (50.0, 50.0, 0.12), C_BODY2, 1)
for sign in (-1, 1):
    for index, center in enumerate((-21, -15, -9, -3, 3, 9, 15, 21)):
        color = C_WINDOW2 if index in (1, 4, 6) else C_WINDOW
        coords = [(center - 0.9, 0.65), (center + 0.9, 0.65), (center + 0.9, 3.05), (center - 0.9, 3.05)]
        floor_body.panel(coords, sign * 25.0, color, 2, 0.0, solid=False)
        floor_body.panel_x(coords, sign * 25.0, color, 2, 0.0, solid=False)
components["floor_facade_module"] = make_component("floor_facade_module", "重复楼层", floor_body)

# One facade AC component is reused and rotated so its grille faces outwards.
hvac_body = Builder("facade_hvac_unit", "外立面空调外机")
hvac_body.box((0, 0, 0.12), (2.6, 1.55, 0.24), C_METAL, 0, 0.08)
hvac_body.box((0, 0, 1.05), (2.35, 1.35, 1.75), C_BODY, 1, 0.08)
hvac_body.box((0, -0.70, 1.05), (1.9, 0.08, 1.3), C_DARK, 0, 0.02)
for z in (0.62, 0.82, 1.02, 1.22, 1.42):
    hvac_body.box((0, -0.76, z), (1.75, 0.05, 0.06), C_METAL, 0)
hvac_body.rod((-1.25, -0.55, 0.3), (-1.25, -0.55, 1.85), 0.04, C_ACCENT, 0)
hvac_glow = Builder("facade_hvac_unit", "外立面空调_中性状态灯", material_roles=(3,))
hvac_glow.box((0.92, -0.79, 1.46), (0.22, 0.05, 0.18), C_LIGHT, 3)
components["facade_hvac_unit"] = make_component("facade_hvac_unit", "外立面空调", hvac_body, hvac_glow)

# Roof guardrail kit: simple grey roof slab and yellow safety rail, no extra floor.
roof_body = Builder("roof_guardrail_kit", "屋顶结构_女儿墙与黄色护栏")
roof_body.box((0, 0, 0.18), (50.0, 50.0, 0.36), C_BODY2, 1, 0.18)
for x in (-20, -10, 0, 10, 20):
    roof_body.box((x, -24.55, 0.70), (9.2, 0.35, 1.05), C_BODY, 1, 0.04)
    roof_body.box((x, 24.55, 0.70), (9.2, 0.35, 1.05), C_BODY, 1, 0.04)
for y in (-20, -10, 0, 10, 20):
    roof_body.box((-24.55, y, 0.70), (0.35, 9.2, 1.05), C_BODY, 1, 0.04)
    roof_body.box((24.55, y, 0.70), (0.35, 9.2, 1.05), C_BODY, 1, 0.04)
for start, end in [((-24, -23.8, 1.30), (24, -23.8, 1.30)),
                   ((-24, 23.8, 1.30), (24, 23.8, 1.30)),
                   ((-23.8, -24, 1.30), (-23.8, 24, 1.30)),
                   ((23.8, -24, 1.30), (23.8, 24, 1.30))]:
    roof_body.rod(start, end, 0.10, C_GOLD, 0, 6)
    roof_body.rod((start[0], start[1], 2.15), (end[0], end[1], 2.15), 0.07, C_GOLD, 0, 6)
    for index in range(0, 11):
        if index in (2, 5, 8):
            continue
        point = Vector(start).lerp(Vector(end), index / 10.0)
        roof_body.rod((point.x, point.y, 1.28), (point.x, point.y, 2.18), 0.055, C_METAL, 0, 6)
roof_glow = Builder("roof_guardrail_kit", "屋顶护栏_中性灯带", material_roles=(3,))
for x, y in [(-24.3, -23.7), (24.3, -23.7), (-24.3, 23.7), (24.3, 23.7)]:
    roof_glow.box((x, y, 1.43), (0.16, 0.16, 0.16), C_LIGHT, 3)
components["roof_guardrail_kit"] = make_component("roof_guardrail_kit", "屋顶结构", roof_body, roof_glow)

service_body = Builder("roof_service_hut", "屋顶机房_服务舱")
service_body.box((0, 0, 2.8), (14, 12, 5.6), C_BODY, 1, 0.20)
service_body.box((0, -6.08, 2.1), (3.2, 0.15, 4.0), C_DARK, 0)
service_body.box((0, -6.18, 2.1), (2.7, 0.08, 3.7), C_WINDOW, 1)
service_body.box((0, 0, 5.68), (14.6, 12.6, 0.32), C_METAL, 0, 0.12)
for x in (-4.6, 4.6):
    service_body.box((x, 0, 6.1), (3.0, 6.0, 0.7), C_BODY2, 1, 0.12)
    for y in (-2, -1, 0, 1, 2):
        service_body.box((x, y, 6.48), (2.7, 0.12, 0.06), C_DARK, 0)
for x in (-5.8, 5.8):
    service_body.box((x, -6.05, 1.1), (1.5, 0.7, 2.0), C_BODY2, 1)
for sign in (-1, 1):
    for y in (-3, -1, 1, 3):
        service_body.panel_x([(y - 0.6, 1.2), (y + 0.6, 1.2), (y + 0.6, 4.5), (y - 0.6, 4.5)], sign * 7.03, C_DARK, 0, 0.0)
service_glow = Builder("roof_service_hut", "屋顶机房_暖色门灯", material_roles=(3,))
service_glow.box((0, -6.25, 4.3), (2.8, 0.05, 0.18), C_GOLD, 3)
components["roof_service_hut"] = make_component("roof_service_hut", "屋顶机房", service_body, service_glow)

hvac_roof_body = Builder("roof_hvac_unit", "屋顶HVAC_单台双风扇")
for x in (-2.1, 2.1):
    hvac_roof_body.box((x, 0, 0.15), (0.45, 4.8, 0.3), C_DARK, 0)
hvac_roof_body.box((0, 0, 1.8), (5.8, 4.8, 3.0), C_BODY, 1, 0.12)
hvac_roof_body.box((0, 0, 3.35), (6, 5, 0.20), C_METAL, 0)
for sign in (-1, 1):
    hvac_roof_body.panel([(-2.5, 0.65), (2.5, 0.65), (2.5, 2.95), (-2.5, 2.95)], sign * 2.425, C_DARK, 0, 0.0, solid=False)
    for z in (0.9, 1.3, 1.7, 2.1, 2.5, 2.9):
        hvac_roof_body.panel([(-2.5, z), (2.5, z), (2.5, z + 0.12), (-2.5, z + 0.12)], sign * 2.44, C_BODY2, 0, 0.0, solid=False)
for x in (-1.5, 1.5):
    hvac_roof_body.rod((x, 0, 3.46), (x, 0, 3.52), 1.13, C_DARK, 0, 8)
    hvac_roof_body.rod((x, 0, 3.52), (x, 0, 3.60), 0.20, C_METAL, 0, 8)
    for index in range(8):
        a = index * math.tau / 8
        b = a + 0.35
        blade = [(x + r * math.cos(t), r * math.sin(t), 3.54) for r, t in ((0.24, a), (0.95, a + 0.2), (0.95, b + 0.2), (0.24, b))]
        hvac_roof_body._add(blade, [(0, 1, 2, 3)], C_BODY2, 0)
hvac_roof_glow = Builder("roof_hvac_unit", "屋顶HVAC_暖色状态灯", material_roles=(3,))
hvac_roof_glow.box((2.3, -2.47, 2.6), (0.3, 0.06, 0.18), C_GOLD, 3)
components["roof_hvac_unit"] = make_component("roof_hvac_unit", "屋顶HVAC", hvac_roof_body, hvac_roof_glow)

comm_body = Builder("roof_satellite_dish", "屋顶卫星天线_实心碟与深灰支架")
comm_body.box((0, 0, 0.2), (4.8, 4.8, 0.4), C_DARK, 0)
for x in (-1.7, 1.7):
    for y in (-1.7, 1.7):
        comm_body.rod((x, y, 0.4), (x * 0.7, y * 0.7, 5.4), 0.17, C_DARK, 0, 6)
        comm_body.rod((x, y, 0.6), (-x * 0.7, y * 0.7, 5.2), 0.10, C_METAL, 0, 4)
for z in (1.0, 3.0, 5.2):
    comm_body.box((0, 0, z), (3.5, 3.5, 0.18), C_DARK, 0)
dish_center = Vector((0, -0.4, 6.0))
def dish_point(point):
    point = Vector(point)
    angle = math.radians(-35)
    return dish_center + Vector((point.x, point.y * math.cos(angle) - point.z * math.sin(angle), point.y * math.sin(angle) + point.z * math.cos(angle)))
dish_start = len(comm_body.vertices)
comm_body.dish(tuple(dish_center), radius=4.5, depth=1.3, color=(9, 8), role_index=1, segments=16, rings=3)
for index in range(dish_start, len(comm_body.vertices)):
    comm_body.vertices[index] = tuple(dish_point(Vector(comm_body.vertices[index]) - dish_center))
for index in range(16):
    a, b = index * math.tau / 16, (index + 1) * math.tau / 16
    rim_a = dish_point((4.5 * math.cos(a), -0.03, 4.5 * math.sin(a)))
    rim_b = dish_point((4.5 * math.cos(b), -0.03, 4.5 * math.sin(b)))
    comm_body.rod(rim_a, rim_b, 0.10, C_DARK, 0, 4)
    if index % 4 == 0:
        comm_body.rod(dish_point((0, -2.1, 0)), rim_a, 0.07, C_DARK, 0, 4)
comm_body.rod(dish_point((0, -1.2, 0)), dish_point((0, -2.2, 0)), 0.18, C_GOLD, 0, 6)
components["roof_satellite_dish"] = make_component("roof_satellite_dish", "屋顶卫星天线", comm_body)

tower_body = Builder("roof_truss_tower", "屋顶通信塔_桁架与接收板")
tower_body.box((0, 0, 0.15), (3.2, 3.2, 0.3), C_DARK, 0)
levels = [(0.3, 1.25), (2.6, 1.0), (5.0, 0.7), (7.8, 0.4)]
for level_index, (z, half) in enumerate(levels):
    corners = [(-half, -half, z), (half, -half, z), (half, half, z), (-half, half, z)]
    for index in range(4):
        tower_body.rod(corners[index], corners[(index + 1) % 4], 0.09, C_METAL, 0, 4)
        if level_index < len(levels) - 1:
            next_z, next_half = levels[level_index + 1]
            upper = [(-next_half, -next_half, next_z), (next_half, -next_half, next_z), (next_half, next_half, next_z), (-next_half, next_half, next_z)]
            tower_body.rod(corners[index], upper[index], 0.13, C_DARK, 0, 4)
            tower_body.rod(corners[index], upper[(index + 1) % 4], 0.075, C_METAL, 0, 4)
for x in (-1.0, 1.0):
    tower_body.box((x, 0, 6.5), (0.55, 0.65, 2.4), (9, 8), 1, 0.05)
    tower_body.box((x, -0.34, 6.5), (0.38, 0.04, 2.1), C_BODY2, 1)
tower_body.rod((0, 0, 7.7), (0, 0, 8.3), 0.10, C_DARK, 0, 6)
tower_glow = Builder("roof_truss_tower", "屋顶通信塔_暖色警示灯", material_roles=(3,))
tower_glow.box((0, 0, 8.35), (0.3, 0.3, 0.3), C_GOLD, 3)
components["roof_truss_tower"] = make_component("roof_truss_tower", "屋顶通信塔", tower_body, tower_glow)

bill_body = Builder("facade_billboard", "立面广告牌_SKYLINE城市剪影")
bill_body.box((0, 0, 15), (16, 0.36, 30), (8, 0), 1)
for x in (-7.8, 7.8):
    bill_body.box((x, -0.2, 15), (0.4, 0.20, 30), C_METAL, 0)
for z in (0.2, 29.8):
    bill_body.box((0, -0.2, z), (16, 0.20, 0.4), C_METAL, 0)
sun = [(6.4 * math.cos(index * math.tau / 20), 20 + 6.4 * math.sin(index * math.tau / 20)) for index in range(20)]
bill_body.panel(sun, -0.31, (6, 3), 1, 0.0, solid=False)
for index, height in enumerate((4, 7, 5, 10, 13, 8, 6, 9, 4)):
    x = -7.0 + index * 1.6
    bill_body.panel([(x, 8), (x + 1.3, 8), (x + 1.3, 8 + height), (x, 8 + height)], -0.35, (9, 0), 1, 0.0, solid=False)
# 低面二维笔画，七字均为真实几何，不依赖私有文字纹理。
glyphs = {
    "S": [((1, 1), (0, 1)), ((0, 1), (0, .5)), ((0, .5), (1, .5)), ((1, .5), (1, 0)), ((1, 0), (0, 0))],
    "K": [((0, 0), (0, 1)), ((0, .5), (1, 1)), ((0, .5), (1, 0))],
    "Y": [((0, 1), (.5, .5)), ((1, 1), (.5, .5)), ((.5, .5), (.5, 0))],
    "L": [((0, 1), (0, 0)), ((0, 0), (1, 0))],
    "I": [((0, 1), (1, 1)), ((.5, 1), (.5, 0)), ((0, 0), (1, 0))],
    "N": [((0, 0), (0, 1)), ((0, 1), (1, 0)), ((1, 0), (1, 1))],
    "E": [((0, 0), (0, 1)), ((0, 1), (1, 1)), ((0, .5), (.8, .5)), ((0, 0), (1, 0))],
}
for index, letter in enumerate("SKYLINE"):
    for a, b in glyphs[letter]:
        start = Vector((-6.5 + index * 1.9 + a[0] * 1.3, 3.6 + a[1] * 2.5))
        end = Vector((-6.5 + index * 1.9 + b[0] * 1.3, 3.6 + b[1] * 2.5))
        direction = (end - start).normalized()
        offset = Vector((-direction.y, direction.x)) * .10
        bill_body.panel([tuple(start - offset), tuple(end - offset), tuple(end + offset), tuple(start + offset)], -0.38, C_GOLD, 1, 0.0, solid=False)
bill_glow = Builder("facade_billboard", "立面广告牌_暖光边线", material_roles=(3,))
for z in (0.7, 29.3):
    bill_glow.box((0, -0.34, z), (14.3, 0.06, 0.12), C_GOLD, 3)
components["facade_billboard"] = make_component("facade_billboard", "立面广告牌", bill_body, bill_glow)


# One frozen instance list is the only layout source for the Blender preview and Godot root.
component_instances = [
    *[{"component_id": f"{ASSET}-FLOOR-FACADE-MODULE", "slug": "floor_facade_module",
       "instance_id": f"floor_{index + 1:02d}", "position_m": [0.0, 0.0, index * 3.8],
       "rotation_y_deg": 0.0, "scale": [1.0, 1.0, 1.0]} for index in range(20)],
    {"component_id": f"{ASSET}-FACADE-HVAC-UNIT", "slug": "facade_hvac_unit", "instance_id": "facade_hvac_01", "position_m": [-25.8, -10.0, 1.0], "rotation_y_deg": 270.0, "scale": [1.0, 1.0, 1.0]},
    {"component_id": f"{ASSET}-FACADE-HVAC-UNIT", "slug": "facade_hvac_unit", "instance_id": "facade_hvac_02", "position_m": [25.8, -6.0, 11.0], "rotation_y_deg": 90.0, "scale": [1.0, 1.0, 1.0]},
    {"component_id": f"{ASSET}-FACADE-HVAC-UNIT", "slug": "facade_hvac_unit", "instance_id": "facade_hvac_03", "position_m": [-25.8, 5.0, 25.0], "rotation_y_deg": 270.0, "scale": [1.0, 1.0, 1.0]},
    {"component_id": f"{ASSET}-FACADE-HVAC-UNIT", "slug": "facade_hvac_unit", "instance_id": "facade_hvac_04", "position_m": [25.8, 10.0, 39.0], "rotation_y_deg": 90.0, "scale": [1.0, 1.0, 1.0]},
    {"component_id": f"{ASSET}-FACADE-HVAC-UNIT", "slug": "facade_hvac_unit", "instance_id": "facade_hvac_05", "position_m": [-25.8, -7.0, 53.0], "rotation_y_deg": 270.0, "scale": [1.0, 1.0, 1.0]},
    {"component_id": f"{ASSET}-FACADE-HVAC-UNIT", "slug": "facade_hvac_unit", "instance_id": "facade_hvac_06", "position_m": [25.8, 5.0, 67.0], "rotation_y_deg": 90.0, "scale": [1.0, 1.0, 1.0]},
    {"component_id": f"{ASSET}-ROOF-GUARDRAIL-KIT", "slug": "roof_guardrail_kit", "instance_id": "roof_guardrail", "position_m": [0.0, 0.0, 76.0], "rotation_y_deg": 0.0, "scale": [1.0, 1.0, 1.0]},
    *[{"component_id": f"{ASSET}-{slug.upper().replace('_', '-')}", "slug": slug, "instance_id": name,
       "position_m": list(pos), "rotation_y_deg": angle, "scale": [1.0, 1.0, 1.0]}
      for slug, name, pos, angle in roof_layout],
    {"component_id": f"{ASSET}-FACADE-BILLBOARD", "slug": "facade_billboard", "instance_id": "billboard_south", "position_m": [0.0, -25.55, 32.0], "rotation_y_deg": 0.0, "scale": [1.0, 1.0, 1.0]},
    {"component_id": f"{ASSET}-FACADE-BILLBOARD", "slug": "facade_billboard", "instance_id": "billboard_east", "position_m": [25.55, 0.0, 38.0], "rotation_y_deg": 90.0, "scale": [1.0, 1.0, 1.0]},
]

for instance in component_instances:
    offset = Vector(component_collections[instance["slug"]]["geometry_offset_m"])
    angle = math.radians(instance["rotation_y_deg"])
    rotated_offset = Vector((offset.x * math.cos(angle) - offset.y * math.sin(angle),
                             offset.x * math.sin(angle) + offset.y * math.cos(angle), offset.z))
    instance["reference_position_m"] = list(instance["position_m"])
    instance["geometry_offset_m"] = list(offset)
    instance["position_m"] = [round(value, 7) for value in Vector(instance["position_m"]) + rotated_offset]
    instance["source_object"] = f"实例_{instance['instance_id']}"

instances_path = SRC / "component_instances.json"
instances_payload = {
    "schema": "shellstorm2.openworld.component_instances",
    "schema_version": 1,
    "library": VERSION,
    "asset_id": ASSET,
    "source_room_type_blend": str(SOURCE_BLEND.relative_to(PROJECT).as_posix()),
    "coordinate_contract": {
        "source_space": "blender_room_local",
        "origin_mode": "component_bounds_xy_center_at_walk_plane",
        "blender_plane": "XY",
        "blender_up": "+Z",
        "rotation_y_deg_semantics": "rotation_about_blender_Z",
        "godot_mapping": "(bx, by, bz) -> (bx, bz, -by)",
        "godot_rotation_mapping": "Blender +Z rotation -> Godot +Y rotation",
        "room_frame_world_translation_m": [0.0, 0.0, 0.0],
    },
    "instances": component_instances,
    "validation": {
        "instance_count": len(component_instances),
        "unique_component_count": len(component_collections),
        "coverage_ok": True,
        "layout_owner": "Godot TSCN after initialization",
    },
}
instances_path.write_text(json.dumps(instances_payload, ensure_ascii=False, indent=2), encoding="utf-8")

# Preview uses only Collection Instance objects. The component collections themselves
# are not linked to the visible scene, so no master overlaps at the origin.
def add_collection_instance(instance):
    empty = bpy.data.objects.new(f"实例_{instance['instance_id']}", None)
    preview_col.objects.link(empty)
    empty.empty_display_type = "CUBE"
    empty.instance_type = "COLLECTION"
    empty.instance_collection = component_collections[instance["slug"]]
    empty.location = Vector(instance["position_m"])
    empty.rotation_euler = (0.0, 0.0, math.radians(instance["rotation_y_deg"]))
    empty.scale = tuple(instance["scale"])
    empty["component_id"] = instance["component_id"]
    empty["position_m"] = instance["position_m"]
    empty["rotation_y_deg"] = instance["rotation_y_deg"]
    return empty

for instance in component_instances:
    add_collection_instance(instance)

scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {item.identifier for item in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 1100
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
try:
    scene.view_settings.look = "AgX - Medium High Contrast"
except Exception:
    pass
world = bpy.data.worlds.new("中性天空展示环境")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.07, 0.09, 0.12, 1.0)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.65


def add_light(name, kind, location, energy, color, size=10.0):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    obj = bpy.data.objects.new(name, data)
    preview_col.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0.0, 0.0, 38.0)) - obj.location).to_track_quat("-Z", "Y").to_euler()
    if kind == "AREA":
        data.shape = "DISK"
        data.size = size
    return obj

add_light("KEY_中性微暖", "AREA", (-70, -90, 120), 250000, (1.0, 0.96, 0.90), 55)
add_light("FILL_中性", "AREA", (80, -30, 90), 160000, (1.0, 1.0, 1.0), 65)
add_light("RIM_中性顶部", "AREA", (0, 80, 130), 190000, (1.0, 1.0, 1.0), 45)
add_light("SUN_中性结构照明", "SUN", (-70, -90, 120), 2.0, (1.0, 1.0, 1.0))
cam_data = bpy.data.cameras.new("CAM_景观建筑完整镜头")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 104
cam_data.clip_end = 300
camera = bpy.data.objects.new("CAM_景观建筑完整镜头", cam_data)
preview_col.objects.link(camera)
scene.camera = camera

camera_specs = {
    "front": ((105, -125, 105), 104, (0, 0, 40)),
    "back": ((-112, 100, 82), 102, (0, 0, 42)),
    "side": ((135, 18, 82), 102, (0, 0, 40)),
    "game": ((88, -105, 65), 92, (0, 0, 37)),
    "roof": ((58, -70, 116), 85, (0, 0, 78)),
}


def render_views(folder, prefix):
    folder.mkdir(parents=True, exist_ok=True)
    active_camera = bpy.data.objects.get("CAM_景观建筑完整镜头")
    if active_camera is None:
        raise RuntimeError("render camera missing after file reopen")
    scene.camera = active_camera
    hashes = {}
    for name, (location, ortho_scale, target) in camera_specs.items():
        active_camera.location = location
        active_camera.data.ortho_scale = ortho_scale
        active_camera.rotation_euler = (Vector(target) - active_camera.location).to_track_quat("-Z", "Y").to_euler()
        path = folder / f"{prefix}_{name}.png"
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    # Keep the full-building game camera as the saved scene camera.
    location, ortho_scale, target = camera_specs["game"]
    active_camera.location = location
    active_camera.data.ortho_scale = ortho_scale
    active_camera.rotation_euler = (Vector(target) - active_camera.location).to_track_quat("-Z", "Y").to_euler()
    return hashes


def triangle_count(obj):
    return sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons)


def bbox(obj):
    points = [Vector(corner) for corner in obj.bound_box]
    low = [min(point[index] for point in points) for index in range(3)]
    high = [max(point[index] for point in points) for index in range(3)]
    return [round(value, 6) for value in low + high]


def uv_fingerprint(obj):
    layer = obj.data.uv_layers.get("PaletteUV")
    if not layer:
        return ""
    values = sorted((round(item.uv.x, 7), round(item.uv.y, 7)) for item in layer.data)
    return hashlib.sha256(json.dumps(values, separators=(",", ":")).encode()).hexdigest()


def mesh_evidence(obj):
    mesh = obj.data
    layer = mesh.uv_layers["PaletteUV"]
    corner_set = set()
    areas = {}
    for poly in mesh.polygons:
        uv = [layer.data[index].uv for index in poly.loop_indices]
        cell = (poly.material_index, int(sum(item.x for item in uv) / len(uv) * 10),
                int(sum(item.y for item in uv) / len(uv) * 10))
        area = abs(sum(a.x * b.y - b.x * a.y for a, b in zip(uv, uv[1:] + uv[:1]))) * 0.5
        areas[str(cell)] = areas.get(str(cell), 0.0) + area
        for loop_index in poly.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            item = layer.data[loop_index].uv
            corner_set.add(tuple(round(value, 5) for value in co) +
                           (round(item.x, 6), round(item.y, 6), poly.material_index))
    geometry = {"vertices": [list(vertex.co) for vertex in mesh.vertices],
                "faces": [(list(poly.vertices), poly.material_index) for poly in mesh.polygons]}
    return {"triangles": triangle_count(obj), "vertices": len(mesh.vertices), "edges": len(mesh.edges),
            "polygons": len(mesh.polygons), "bbox": bbox(obj), "uv_fingerprint": uv_fingerprint(obj),
            "geometry_sha256": hashlib.sha256(json.dumps(geometry).encode()).hexdigest(),
            "corner_uv_material_sha256": hashlib.sha256(json.dumps(sorted(corner_set)).encode()).hexdigest(),
            "uv_area_by_material_cell": areas}


def optimize_mesh(obj):
    before = mesh_evidence(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    uv_layer = bm.loops.layers.uv["PaletteUV"]
    zero_faces = [face for face in bm.faces if face.calc_area() <= 1.0e-12]
    counts = {"zero_area_faces": len(zero_faces), "duplicate_faces": 0, "merged_vertices": 0}
    if zero_faces:
        bmesh.ops.delete(bm, geom=zero_faces, context="FACES_ONLY")
    seen = set()
    duplicates = []
    for face in bm.faces:
        key = (face.material_index, tuple(sorted(tuple(round(value, 7) for value in loop.vert.co) +
                tuple(round(value, 7) for value in loop[uv_layer].uv) for loop in face.loops)))
        if key in seen:
            duplicates.append(face)
        seen.add(key)
    counts["duplicate_faces"] = len(duplicates)
    if duplicates:
        bmesh.ops.delete(bm, geom=duplicates, context="FACES_ONLY")
    # 仅合并 UV/材质/硬边签名完全相同的重复顶点，不跨材质或色盘边界焊接。
    groups = {}
    for vertex in bm.verts:
        signature = tuple(sorted((loop.face.material_index, round(loop[uv_layer].uv.x, 7),
                                  round(loop[uv_layer].uv.y, 7), loop.face.smooth)
                                 for loop in vertex.link_loops))
        groups.setdefault(signature, []).append(vertex)
    for vertices in groups.values():
        if len(vertices) > 1:
            prior = len(bm.verts)
            bmesh.ops.remove_doubles(bm, verts=vertices, dist=1.0e-6)
            counts["merged_vertices"] += prior - len(bm.verts)
    loose_edges = [edge for edge in bm.edges if not edge.link_faces]
    counts["loose_edges"] = len(loose_edges)
    if loose_edges:
        bmesh.ops.delete(bm, geom=loose_edges, context="EDGES")
    loose_vertices = [vertex for vertex in bm.verts if not vertex.link_faces and not vertex.link_edges]
    counts["loose_vertices"] = len(loose_vertices)
    if loose_vertices:
        bmesh.ops.delete(bm, geom=loose_vertices, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update(calc_edges=True)
    after = mesh_evidence(obj)
    bbox_ok = all(abs(a - b) <= 1.0e-5 for a, b in zip(before["bbox"], after["bbox"]))
    corner_ok = before["corner_uv_material_sha256"] == after["corner_uv_material_sha256"]
    area_ok = before["uv_area_by_material_cell"].keys() == after["uv_area_by_material_cell"].keys() and all(
        abs(value - after["uv_area_by_material_cell"][cell]) <= 1.0e-6
        for cell, value in before["uv_area_by_material_cell"].items())
    if not (bbox_ok and corner_ok and area_ok):
        raise RuntimeError(f"优化保真失败 {obj.name}: bbox={bbox_ok}, corner_uv={corner_ok}, area={area_ok}")
    return {"before": before, "after": after, "processed_counts": counts,
            "operations": ["delete_zero_area_faces(area<=1e-12)", "delete_duplicate_faces(material_uv_preserving)",
                           "remove_doubles(dist=1e-6,matching_uv_material_hard_edge)", "delete_loose_edges_vertices",
                           "recalc_face_normals", "triangulate(BEAUTY)"],
            "fidelity": {"bbox_equal": bbox_ok, "corner_uv_material_equal": corner_ok, "uv_cell_area_equal": area_ok},
            "reduction_ratio": (before["triangles"] - after["triangles"]) / before["triangles"],
            "budget": None, "budget_source": "用户整栋实例成本<=10000；未提供逐组件预算",
            "retained_faces_reason": "底面、背面与封闭面用于独立组件复用及投影，缺少不可见证据故保留；源已使用低分段，无安全额外减面。",
            "zero_change_reason": "完整清理真实执行；无命中记录零处理量；三角化不宣称减面。"}



anchor_records = {}
for slug, data in components.items():
    objects = [obj for obj in (data["body"], data["glow"]) if obj]
    points = [vertex.co for obj in objects for vertex in obj.data.vertices]
    low = [min(point[axis] for point in points) for axis in range(3)]
    high = [max(point[axis] for point in points) for axis in range(3)]
    bottom_center_ok = abs(low[2]) < 1.0e-5 and all(abs(low[axis] + high[axis]) < 1.0e-5 for axis in (0, 1))
    identity = lambda obj: obj.location.length < 1.0e-6 and obj.rotation_euler.to_matrix().is_identity and all(abs(value - 1) < 1.0e-6 for value in obj.scale)
    root_ok = identity(data["root"])
    meshes_ok = all(identity(obj) and obj.parent == data["root"] for obj in objects)
    offset_ok = data["collection"].instance_offset.length < 1.0e-6
    if not all((bottom_center_ok, root_ok, meshes_ok, offset_ok)):
        raise RuntimeError(f"组件三层锚点失败 {slug}")
    anchor_records[slug] = {"bottom_center": bottom_center_ok, "root_identity": root_ok,
                            "mesh_local_identity_parented": meshes_ok, "collection_offset_zero": offset_ok,
                            "geometry_offset_m": list(data["collection"]["geometry_offset_m"])}

# Freeze the source before any optimization operation.
location, ortho_scale, target = camera_specs["game"]
camera.location = location
camera.data.ortho_scale = ortho_scale
camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = str(SRC / "previews")
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND))
source_hash = hashlib.sha256(SOURCE_BLEND.read_bytes()).hexdigest()
instances_payload["source_room_type_sha256"] = source_hash
for instance in component_instances:
    instance["source_sha256"] = source_hash
instances_path.write_text(json.dumps(instances_payload, ensure_ascii=False, indent=2), encoding="utf-8")
(SRC / "qa/component_anchors.json").write_text(json.dumps(anchor_records, ensure_ascii=False, indent=2), encoding="utf-8")
source_runtime_triangles = sum(sum(triangle_count(obj) for obj in (components[item["slug"]]["body"], components[item["slug"]]["glow"]) if obj) for item in component_instances)
if source_runtime_triangles > 10000:
    raise RuntimeError(f"实例三角预算超限: {source_runtime_triangles}")
before_views = render_views(SRC / "previews", "before")
# Rendering changes only the in-memory camera state; do not resave the source after
# its protected hash is recorded.
source_hash_after_render = hashlib.sha256(SOURCE_BLEND.read_bytes()).hexdigest()

optimization_records = {}
for slug, data in components.items():
    entries = []
    for obj in [data["body"], data["glow"]]:
        if obj:
            entries.append({"object": obj.name, "role": "emissive" if "自发光" in obj.name else "body", **optimize_mesh(obj)})
    optimization_records[slug] = entries

# Save and reopen the independent optimized derivative before any export.
bpy.ops.wm.save_as_mainfile(filepath=str(OPT_BLEND))
bpy.ops.wm.open_mainfile(filepath=str(OPT_BLEND))
optimized_hash = hashlib.sha256(OPT_BLEND.read_bytes()).hexdigest()

# Re-run the strict project validator on the source and optimized files. Export is
# blocked if either file fails; the source validator is the pre-export gate.
def run_validator(blend_path, report_path):
    blender_executable = shutil.which("blender") or "blender"
    command = [blender_executable, "--background", str(blend_path), "--python", str(VALIDATOR), "--",
               "--max-materials", "12", "--shared-palette", str(PALETTE), "--json", str(report_path)]
    result = subprocess.run(command, cwd=str(PROJECT), capture_output=True, text=True)
    (report_path.with_suffix(".stdout.txt")).write_text(result.stdout + "\n" + result.stderr, encoding="utf-8")
    if result.returncode != 0:
        raise RuntimeError(f"validate_game_prop.py failed for {blend_path}: {result.stdout[-4000:]}")
    return result.returncode

source_validation_report = SRC / "qa/validate_source.json"
optimized_validation_report = SRC / "qa/validate_optimized.json"
run_validator(SOURCE_BLEND, source_validation_report)
run_validator(OPT_BLEND, optimized_validation_report)

# Reopened optimized scene is the only scene used for GLB export and after renders.
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {item.identifier for item in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE"
after_views = render_views(EXPORT_DIR / "previews_after", "after")
scene.render.filepath = str(EXPORT_DIR / "previews_after/after_game.png")
# Do not save the optimized file after the post-reopen renders: render output changes
# only in-memory state, and the saved hash must identify the exact file used for export.
optimized_hash_after_render = hashlib.sha256(OPT_BLEND.read_bytes()).hexdigest()

# Export each component from the reopened optimized file. Components are temporarily
# linked into the visible output parent only for the exporter context, then unlinked.
component_slugs = [slug for slug, _, _, _ in plan_definitions]


def resolve_component_objects(slug):
    collection = bpy.data.collections[f"02_游戏输出_{slug}_资产包"]
    candidates = [obj for obj in collection.objects if obj.type == "MESH"]
    bodies = [obj for obj in candidates if "自发光" not in obj.name]
    glows = [obj for obj in candidates if "自发光" in obj.name]
    if len(bodies) != 1 or len(glows) > 1:
        raise RuntimeError(f"组件主体/自发光数量无效: {slug}")
    return bodies[0], glows[0] if glows else None


def inspect_glb(path, expected_triangles):
    binary = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", binary)
    if magic != b"glTF" or version != 2 or length != len(binary):
        raise RuntimeError(f"GLB 二进制头无效: {path}")
    chunk_length, chunk_type = struct.unpack_from("<II", binary, 12)
    if chunk_type != 0x4E4F534A:
        raise RuntimeError(f"GLB JSON chunk 缺失: {path}")
    document = json.loads(binary[20:20 + chunk_length])
    if document.get("images") or document.get("textures"):
        raise RuntimeError(f"GLB 内嵌图片或纹理: {path}")
    triangles = 0
    surfaces = 0
    for mesh in document.get("meshes", []):
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) != 4:
                raise RuntimeError("GLB 包含非三角图元")
            accessor = primitive.get("indices", primitive["attributes"]["POSITION"])
            count = document["accessors"][accessor]["count"]
            if count % 3:
                raise RuntimeError("GLB 三角索引数量错误")
            triangles += count // 3
            surfaces += 1
    if triangles != expected_triangles:
        raise RuntimeError(f"GLB 三角数不符: {triangles} != {expected_triangles}")
    return {"images": len(document.get("images", [])), "textures": len(document.get("textures", [])),
            "triangles": triangles, "surfaces": surfaces, "mesh_count": len(document.get("meshes", [])),
            "material_count": len(document.get("materials", [])), "json_chunk_sha256": hashlib.sha256(binary[20:20 + chunk_length]).hexdigest()}


protected_evidence = protected_file_report()
if source_hash != hashlib.sha256(SOURCE_BLEND.read_bytes()).hexdigest() or optimized_hash != optimized_hash_after_render:
    raise RuntimeError("源或优化文件哈希变化，阻止导出")
export_records = []
for slug in component_slugs:
    component_collection_obj = bpy.data.collections.get(f"02_游戏输出_{slug}_资产包")
    output_parent = bpy.data.collections.get("02_游戏输出_独立资产包_v007")
    if component_collection_obj is None or output_parent is None:
        raise RuntimeError(f"export collection missing: {slug}")
    output_parent.children.link(component_collection_obj)
    body_obj, glow_obj = resolve_component_objects(slug)
    bpy.ops.object.select_all(action="DESELECT")
    mesh_objects = [obj for obj in (body_obj, glow_obj) if obj is not None]
    for obj in mesh_objects:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body_obj
    target = BASE / "components/landscape_skyline20" / slug / f"env_landscape_skyline20_{slug}_visual_top3d.glb"
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(target), export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_texcoords=True, export_normals=True,
        export_materials="EXPORT", export_image_format="NONE", export_extras=False,
        export_cameras=False, export_lights=False, export_animations=False,
    )
    output_parent.children.unlink(component_collection_obj)
    records = []
    for obj in mesh_objects:
        records.append({
            "object": obj.name,
            "role": "emissive" if "自发光" in obj.name else "body",
            "triangles": triangle_count(obj),
            "vertices": len(obj.data.vertices),
            "polygons": len(obj.data.polygons),
            "bbox_local": bbox(obj),
            "uv_fingerprint": uv_fingerprint(obj),
        })
    bbox_lows = [min(item["bbox_local"][axis] for item in records) for axis in (0, 1, 2)]
    bbox_highs = [max(item["bbox_local"][axis + 3] for item in records) for axis in (0, 1, 2)]
    union_bbox = [round(bbox_highs[axis] - bbox_lows[axis], 6) for axis in range(3)]
    export_records.append({
        "asset_id": f"{ASSET}-{slug.upper().replace('_', '-')}",
        "slug": slug,
        "component_id": f"{ASSET}-{slug.upper().replace('_', '-')}",
        "collection": f"02_游戏输出_{slug}_资产包",
        "source_objects": records,
        "source_sha256": source_hash,
        "optimized_sha256": optimized_hash_after_render,
        "instance_transforms": [item for item in component_instances if item["slug"] == slug],
        "geometry_offset_m": list(component_collection_obj["geometry_offset_m"]),
        "glb_inspection": inspect_glb(target, sum(item["triangles"] for item in records)),
        "triangles_before": sum(item["before"]["triangles"] for item in optimization_records[slug]),
        "triangles_after": sum(item["after"]["triangles"] for item in optimization_records[slug]),
        "bbox_m": union_bbox,
        "bbox_local": bbox_lows + bbox_highs,
        "glb": target.relative_to(PROJECT).as_posix(),
        "glb_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        "material_roles": role_names,
        "palette": PALETTE.relative_to(PROJECT).as_posix(),
        "embedded_images": False,
    })

# Compute the measured assembly envelope from the same component records and instance
# list consumed by Blender and Godot. Structural footprint remains the requested 50m
# square; facade attachments are reported separately instead of being hidden.
def measured_assembly_bounds(records, instances):
    by_slug = {record["slug"]: record for record in records}
    points = []
    for instance in instances:
        record = by_slug[instance["slug"]]
        bounds = record["bbox_local"]
        low = bounds[:3]
        high = bounds[3:]
        angle = math.radians(instance["rotation_y_deg"])
        cos_a = math.cos(angle)
        sin_a = math.sin(angle)
        tx, ty, tz = instance["position_m"]
        for x in (low[0], high[0]):
            for y in (low[1], high[1]):
                for z in (low[2], high[2]):
                    rx = x * cos_a - y * sin_a + tx
                    ry = x * sin_a + y * cos_a + ty
                    points.append((rx, ry, z + tz))
    lows = [min(point[axis] for point in points) for axis in range(3)]
    highs = [max(point[axis] for point in points) for axis in range(3)]
    return {
        "bounds_local": [round(value, 6) for value in lows + highs],
        "size_m": [round(highs[axis] - lows[axis], 6) for axis in range(3)],
    }

assembly_bounds = measured_assembly_bounds(export_records, component_instances)
roof_equipment_boxes = {}
for instance in component_instances:
    if instance["slug"].startswith("roof_") and instance["slug"] != "roof_guardrail_kit":
        roof_equipment_boxes[instance["instance_id"]] = measured_assembly_bounds(export_records, [instance])["bounds_local"]
clearance_pairs = []
for index, (name, box) in enumerate(roof_equipment_boxes.items()):
    if not (-23.5 <= box[0] and box[3] <= 23.5 and -23.5 <= box[1] and box[4] <= 23.5):
        raise RuntimeError(f"屋顶设备超出护栏净空: {name}")
    if abs(box[2] - 76.36) > 0.001:
        raise RuntimeError(f"屋顶设备未贴合屋面: {name}")
    for other_name, other in list(roof_equipment_boxes.items())[index + 1:]:
        gap_x = max(other[0] - box[3], box[0] - other[3], 0)
        gap_y = max(other[1] - box[4], box[1] - other[4], 0)
        gap = math.hypot(gap_x, gap_y)
        if gap < 1.0:
            raise RuntimeError(f"屋顶设备净空不足1m: {name}/{other_name}: {gap}")
        clearance_pairs.append({"a": name, "b": other_name, "horizontal_aabb_gap_m": gap})
roof_clearance = {"equipment_bounds": roof_equipment_boxes, "pair_checks": clearance_pairs,
                  "minimum_gap_m": min(item["horizontal_aabb_gap_m"] for item in clearance_pairs), "passed": True}
(SRC / "qa/roof_clearance.json").write_text(json.dumps(roof_clearance, ensure_ascii=False, indent=2), encoding="utf-8")

# Write component contracts and isolated visual-only PackedScenes. The root scenes
# own no collision and no gameplay; Godot owns only the private asset roots here.
def godot_position(position):
    x, y, z = position
    return f"Vector3({x:.6f}, {z:.6f}, {-y:.6f})"


def godot_rotation(rotation_y_deg):
    return f"Vector3(0, {math.radians(rotation_y_deg):.9f}, 0)"


def write_prefab(path, root_name, glb_rel, asset_id, slug, bbox_size):
    path.parent.mkdir(parents=True, exist_ok=True)
    text = "[gd_scene load_steps=2 format=3]\n\n"
    text += f'[ext_resource type="PackedScene" path="res://{glb_rel}" id="1"]\n\n'
    text += f'[node name="{root_name}" type="Node3D"]\n'
    text += f'metadata/asset_id = "{asset_id}"\nmetadata/asset_version = "{VERSION}"\n'
    text += f'metadata/component_id = "{asset_id}"\nmetadata/component_slug = "{slug}"\n'
    text += 'metadata/collision_status = "none_visual_only"\nmetadata/layout_owner = "private_component_root"\n'
    text += f'metadata/bounds_m = Vector3({bbox_size[0]:.6f}, {bbox_size[1]:.6f}, {bbox_size[2]:.6f})\n\n'
    text += '[node name="Visual" type="Node3D" parent="."]\n\n'
    text += '[node name="ImportedModel" parent="Visual" instance=ExtResource("1")]\n'
    path.write_text(text, encoding="utf-8", newline="\r\n")


for record in export_records:
    slug = record["slug"]
    asset_id = record["asset_id"]
    runtime = BASE / "runtime/landscape_skyline20" / slug / f"env_landscape_skyline20_{slug}_root_top3d.tscn"
    dims = record["bbox_m"]
    godot_dims = [dims[0], dims[2], dims[1]]
    write_prefab(runtime, f"LandscapeSkyline20_{slug}", record["glb"], asset_id, slug, godot_dims)
    record["prefab"] = runtime.relative_to(PROJECT).as_posix()
    import_path = BASE / "components/landscape_skyline20" / slug / f"env_landscape_skyline20_{slug}_visual_top3d.glb.import"
    existing_import = import_path.read_text(encoding="utf-8") if import_path.exists() else ""
    if existing_import:
        import_text = re.sub(r'(?m)^gltf/embedded_image_handling=.*$', 'gltf/embedded_image_handling=0', existing_import)
        import_text = re.sub(r'(?m)^import_script/path=.*$', 'import_script/path="res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd"', import_text)
        import_text = re.sub(r'(?m)^meshes/generate_lods=.*$', 'meshes/generate_lods=false', import_text)
        import_path.write_text(import_text, encoding="utf-8", newline="\r\n")
    else:
        import_path.write_text(
        "[remap]\n\nimporter=\"scene\"\nimporter_version=1\ntype=\"PackedScene\"\n\n"
        "[deps]\n\n"
        f"source_file=\"res://{record['glb']}\"\n"
        "dest_files=[]\n\n[params]\n"
        "gltf/embedded_image_handling=0\n"
        "import_script/path=\"res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd\"\n"
        "materials/extract=0\nmeshes/generate_lods=false\n",
        encoding="utf-8",
        newline="\r\n",
    )
    optimization = optimization_records[slug]
    manifest = {
        "schema": "shellstorm2.openworld.component_asset_manifest",
        "schema_version": 2,
        "asset_id": asset_id,
        "parent_asset_id": ASSET,
        "component_id": asset_id,
        "slug": slug,
        "component_family": next(family for key, family, _, _ in plan_definitions if key == slug),
        "instance_transforms": [item for item in component_instances if item["slug"] == slug],
        "source_sha256": source_hash,
        "bbox_godot_m": godot_dims,
        "geometry_offset_m": list(bpy.data.collections[record["collection"]]["geometry_offset_m"]),
        "variant_axis": None,
        "variant_value": None,
        "variant_reason": None,
        "scope": "asset_local",
        "serves_room_types": ["open_world_landscape"],
        "version": VERSION,
        "source_blend": SOURCE_BLEND.relative_to(PROJECT).as_posix(),
        "optimized_blend": OPT_BLEND.relative_to(PROJECT).as_posix(),
        "source_sha256_before": source_hash,
        "source_sha256_after": source_hash_after_render,
        "optimized_sha256": optimized_hash_after_render,
        "glb": record["glb"],
        "glb_sha256": record["glb_sha256"],
        "prefab": runtime.relative_to(PROJECT).as_posix(),
        "collection": record["collection"],
        "root_object": f"Root_{slug}",
        "local_origin": [0.0, 0.0, 0.0],
        "front_axis": "-Y",
        "allowed_rotations_y_deg": [0, 90, 180, 270],
        "collision_owner": "none_visual_only",
        "palette_uv_layer": "PaletteUV",
        "instance_offset": [0.0, 0.0, 0.0],
        "triangles_before": record["triangles_before"],
        "triangles_after": record["triangles_after"],
        "reduction_ratio": (record["triangles_before"] - record["triangles_after"]) / record["triangles_before"] if record["triangles_before"] else None,
        "optimization_records": optimization,
        "bbox_m": dims,
        "uv_fingerprints": {item["object"]: item["uv_fingerprint"] for item in record["source_objects"]},
        "embedded_images": False,
        "import_contract": {
            "gltf_embedded_image_handling": 0,
            "post_import": "res://tools/asset_pipeline/scene_facility_shared_palette_post_import.gd",
        },
        "collision": "none_visual_only",
    }
    (runtime.parent / "asset_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

# Root assembly scene uses the same component_instances.json, with Blender->Godot
# position and rotation conversion made explicit. It is not a formal room scene.
root_tscn = BASE / "runtime/landscape_skyline20/env_landscape_skyline20_root_top3d.tscn"
resources = []
for index, record in enumerate(export_records, 1):
    resources.append(
        f'[ext_resource type="PackedScene" path="res://assets/art/environments/open_world/runtime/landscape_skyline20/{record["slug"]}/env_landscape_skyline20_{record["slug"]}_root_top3d.tscn" id="{index}"]'
    )
slug_to_resource = {record["slug"]: index for index, record in enumerate(export_records, 1)}
nodes = [
    f"[gd_scene load_steps={len(export_records) + 1} format=3]", "", *resources, "",
    '[node name="LandscapeSkyline20" type="Node3D"]',
    f'metadata/asset_id = "{ASSET}"',
    f'metadata/asset_version = "{VERSION}"',
    'metadata/block_id = "open_world"',
    'metadata/floor_range = "1F-20F + rooftop"',
    'metadata/design_scope = "50m x 50m; 20层；3.8m美术层高；无底层；屋顶重点"',
    'metadata/collision_status = "none_visual_only"',
    'metadata/layout_owner = "Godot TSCN initialization; not formal room"',
    f'metadata/component_count = {len(export_records)}',
    f'metadata/instance_count = {len(component_instances)}',
    "",
]
for instance in component_instances:
    resource_id = slug_to_resource[instance["slug"]]
    nodes += [
        f'[node name="{instance["instance_id"]}" parent="." instance=ExtResource("{resource_id}")]',
        f'position = {godot_position(instance["position_m"])}',
        f'rotation = {godot_rotation(instance["rotation_y_deg"])}',
        "",
    ]
root_tscn.parent.mkdir(parents=True, exist_ok=True)
root_tscn.write_text("\n".join(nodes), encoding="utf-8", newline="\r\n")

# 计划只有一个来源；冻结后不重写，由实测报告承载几何统计。
plan = freeze_plan
assert hashlib.sha256((SRC / "component_plan.json").read_bytes()).hexdigest() == plan_frozen_hash

whitebox = {
    "schema": "shellstorm2.openworld.whitebox",
    "schema_version": 2,
    "scene_id": "landscape_skyline20",
    "display_name": "景观建筑 Skyline 同类 20层楼",
    "version": VERSION,
    "block": {"block_id": "open_world", "floor_range": "1F-20F + rooftop", "design_scope": plan["design_scope"]},
    "source": {"document": "用户参考图及建筑需求", "read_date": "2026-10-07", "reference_image": plan["reference_image"]},
    "unit": "meter",
    "coordinate_system": "blender_z_up",
    "scene_size_m": [50.0, 50.0, assembly_bounds["size_m"][2]],
    "measured_assembly_bounds": assembly_bounds,
    "roof_clearance": roof_clearance,
    "floor_height_m": 3.8,
    "modules": [{"module_id": slug, "instance_count": count, "component_id": f"{ASSET}-{slug.upper().replace('_', '-')}", "positions": [item["position_m"] for item in component_instances if item["slug"] == slug]} for slug, _, count, _ in plan_definitions],
    "clearance_zones": [],
    "collision": "none_visual_only",
    "notes": ["不制作底层结构", "20层重复", "屋顶预算优先", "总输出运行时实例三角面不得超过10000", "组件Collection Instance与Godot私有root共用component_instances.json"],
}
WB = PROJECT / "source/art/whitebox/landscape_skyline20/v007/data"
WB.mkdir(parents=True, exist_ok=True)
(WB / "whitebox_landscape_skyline20_v007.json").write_text(json.dumps(whitebox, ensure_ascii=False, indent=2), encoding="utf-8")

# Catalog and package tree are the authoritative per-component inventory, not the ledger.
instance_counts = {slug: sum(1 for item in component_instances if item["slug"] == slug) for slug in component_slugs}
tri_by_slug = {record["slug"]: record["triangles_after"] for record in export_records}
runtime_triangles = sum(tri_by_slug[slug] * count for slug, count in instance_counts.items())
roof_triangles = sum(tri_by_slug[slug] * count for slug, count in instance_counts.items() if slug.startswith("roof_"))
roof_budget = {"instance_triangles": roof_triangles, "share": roof_triangles / runtime_triangles,
               "target": 0.45, "target_met": roof_triangles / runtime_triangles >= 0.45}
if runtime_triangles > 10000 or not roof_budget["target_met"]:
    raise RuntimeError(f"总预算或屋顶投入门禁失败: {runtime_triangles}, {roof_budget}")
source_hash_final = hashlib.sha256(SOURCE_BLEND.read_bytes()).hexdigest()
source_unchanged = source_hash == source_hash_final
catalog = {
    "schema": "shellstorm2.openworld.component_catalog",
    "schema_version": 2,
    "asset_id": ASSET,
    "version": VERSION,
    "source_blend": SOURCE_BLEND.relative_to(PROJECT).as_posix(),
    "source_sha256": source_hash_final,
    "optimized_blend": OPT_BLEND.relative_to(PROJECT).as_posix(),
    "optimized_sha256": optimized_hash_after_render,
    "instances_file": instances_path.relative_to(PROJECT).as_posix(),
    "component_count": len(export_records),
    "instance_count": len(component_instances),
    "runtime_triangle_budget": {"limit": 10000, "actual": runtime_triangles, "pass": runtime_triangles <= 10000, "metric": "instance triangles"},
    "structural_footprint_m": [50.0, 50.0],
    "measured_assembly_bounds": assembly_bounds,
    "roof_clearance": roof_clearance,
    "components": export_records,
    "instance_transforms": component_instances,
    "source_protection": {"source_sha256_before": source_hash, "source_sha256_after": source_hash_final, "unchanged": source_unchanged, "v005_not_overwritten": True},
}
(SRC / "component_catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
(SRC / "component_tree.txt").write_text("\n".join(["landscape_skyline20_景观建筑_中文资产管理", "├─ 01_制作组件_按组件拆分_v007", *[f"│  └─ 制作源_{slug}" for slug in component_slugs], "└─ 02_游戏输出_独立资产包_v007", *[f"   └─ 02_游戏输出_{slug}_资产包 (主体 + 自发光)" for slug in component_slugs]]), encoding="utf-8")

# Export and QA manifests explicitly retain actual results. No Godot result is
# marked passed here; this task only writes the import contracts and runs Blender QA.
export_manifest = {
    "schema": "shellstorm2.openworld.export.v002",
    "asset_id": ASSET,
    "version": VERSION,
    "source": SOURCE_BLEND.relative_to(PROJECT).as_posix(),
    "source_sha256": source_hash_final,
    "optimized": OPT_BLEND.relative_to(PROJECT).as_posix(),
    "optimized_sha256": optimized_hash_after_render,
    "source_unchanged": source_unchanged,
    "pre_export_validation": {"source": str(source_validation_report.relative_to(PROJECT).as_posix()), "optimized": str(optimized_validation_report.relative_to(PROJECT).as_posix())},
    "optimization": optimization_records,
    "triangle_budget": 10000,
    "runtime_instance_triangles": runtime_triangles,
    "roof_triangle_budget": roof_budget,
    "runtime_triangle_budget_pass": runtime_triangles <= 10000,
    "instance_counts": instance_counts,
    "structural_footprint_m": [50.0, 50.0],
    "measured_assembly_bounds": assembly_bounds,
    "roof_clearance": roof_clearance,
    "coordinate_map": "Blender (x,y,z)->Godot (x,z,-y); Blender +Z rotation -> Godot +Y rotation",
    "collision": "none_visual_only",
    "before_views": before_views,
    "after_views": after_views,
    "visual_comparison": {"same_camera": True, "front_back_side_game_roof_rendered": True, "note": "v007优化仅清理/法线/三角化；若哈希不同来自重渲染，不将其伪称为简化。"},
    "records": export_records,
}
EXPORT_DIR.joinpath("export_manifest.json").write_text(json.dumps(export_manifest, ensure_ascii=False, indent=2), encoding="utf-8")
root_manifest = {
    "schema": "shellstorm2.openworld.runtime_manifest",
    "asset_id": ASSET,
    "version": VERSION,
    "source_blend": SOURCE_BLEND.relative_to(PROJECT).as_posix(),
    "source_sha256": source_hash_final,
    "optimized_blend": OPT_BLEND.relative_to(PROJECT).as_posix(),
    "prefab": root_tscn.relative_to(PROJECT).as_posix(),
    "component_catalog": (SRC / "component_catalog.json").relative_to(PROJECT).as_posix(),
    "component_instances": instances_path.relative_to(PROJECT).as_posix(),
    "component_count": len(export_records),
    "instance_count": len(component_instances),
    "instance_counts": instance_counts,
    "floor_count": 20,
    "structural_footprint_m": [50.0, 50.0],
    "measured_assembly_bounds": assembly_bounds,
    "roof_clearance": roof_clearance,
    "footprint_m": [50.0, 50.0],
    "height_m": assembly_bounds["size_m"][2],
    "collision": "none_visual_only",
    "layout_owner": "Godot TSCN initialization; not formal room",
    "coordinate_map": "Blender (x,y,z)->Godot (x,z,-y); rotation +Z -> +Y",
    "runtime_triangle_budget": {"limit": 10000, "actual": runtime_triangles, "pass": runtime_triangles <= 10000},
    "runtime_status": "GLB与私有root已生成；Godot实际导入/独立加载验收待执行",
    "runtime_integrated": False,
    "reference_art_approved": False,
    "records": export_records,
}
(BASE / "runtime/landscape_skyline20/asset_manifest.json").write_text(json.dumps(root_manifest, ensure_ascii=False, indent=2), encoding="utf-8")
qa_report = {
    "asset_id": ASSET,
    "version": VERSION,
    "source_hash": source_hash_final,
    "optimized_hash": optimized_hash_after_render,
    "source_unchanged": source_unchanged,
    "v005_preserved": True,
    "component_count": len(export_records),
    "instance_count": len(component_instances),
    "footprint_m": [50.0, 50.0],
    "height_m": assembly_bounds["size_m"][2],
    "floor_height_m": 3.8,
    "triangle_budget": 10000,
    "structural_footprint_m": [50.0, 50.0],
    "measured_assembly_bounds": assembly_bounds,
    "roof_clearance": roof_clearance,
    "component_triangles": tri_by_slug,
    "runtime_instance_triangles": runtime_triangles,
    "roof_triangle_budget": roof_budget,
    "budget_pass": runtime_triangles <= 10000,
    "validator": {"source": "passed", "optimized": "passed", "command": "validate_game_prop.py --max-materials 12 --shared-palette <公共色盘>"},
    "godot_import": "PENDING_NOT_RUN",
    "godot_runtime_probe": "PENDING_NOT_RUN",
    "collision": "none_visual_only",
    "palette": PALETTE.relative_to(PROJECT).as_posix(),
    "status": "BLENDER_SOURCE_OPTIMIZED_EXPORT_COMPLETE_GODOT_PENDING",
}
# Produce a separate whitebox Blend and a top/annotated image. It is a planning
# artifact only and is not used as the game export or formal room scene.
whitebox_blend = PROJECT / "source/art/whitebox/landscape_skyline20/v007/whitebox_landscape_skyline20_v007.blend"
whitebox_preview = PROJECT / "source/art/whitebox/landscape_skyline20/v007/previews/whitebox_top_annotated.png"
whitebox_blend.parent.mkdir(parents=True, exist_ok=True)
whitebox_preview.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
wb_scene = bpy.context.scene
wb_scene.unit_settings.system = "METRIC"
wb_scene.unit_settings.scale_length = 1.0
wb_scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {item.identifier for item in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE"
wb_scene.render.resolution_x = 1200
wb_scene.render.resolution_y = 900
wb_scene.render.resolution_percentage = 100
wb_scene.render.image_settings.file_format = "PNG"
wb_scene.world = bpy.data.worlds.new("白盒中性背景")
wb_scene.world.use_nodes = True
wb_scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.045, 0.06, 1.0)
wb_scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.4
wb_root = bpy.data.collections.new("WHITEBOX_LANDSCAPE_SKYLINE20_V007")
wb_scene.collection.children.link(wb_root)
wb_mat = bpy.data.materials.new("白盒_主体")
wb_mat.diffuse_color = (0.34, 0.42, 0.50, 1.0)
roof_mat = bpy.data.materials.new("白盒_屋顶")
roof_mat.diffuse_color = (0.76, 0.48, 0.08, 1.0)
label_mat = bpy.data.materials.new("白盒_标注")
label_mat.diffuse_color = (0.04, 0.06, 0.08, 1.0)
for material in (wb_mat, roof_mat, label_mat):
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = material.diffuse_color
    bsdf.inputs["Roughness"].default_value = 0.85
label_bsdf = label_mat.node_tree.nodes.get("Principled BSDF")
label_bsdf.inputs["Emission Color"].default_value = (0.01, 0.015, 0.02, 1.0)
label_bsdf.inputs["Emission Strength"].default_value = 1.0

def wb_box(name, location, dimensions, material):
    bpy.ops.mesh.primitive_cube_add(location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for coll in list(obj.users_collection):
        coll.objects.unlink(obj)
    wb_root.objects.link(obj)
    obj.data.materials.append(material)
    return obj

wb_box("重复楼层_20层白盒", (0, 0, 38.0), (50, 50, 76), wb_mat)
wb_box("屋顶平台白盒", (0, 0, 76.4), (50, 50, 0.8), roof_mat)
whitebox_labels = []
for name, box in roof_equipment_boxes.items():
    center = tuple((box[axis] + box[axis + 3]) * 0.5 for axis in range(3))
    dims = tuple(box[axis + 3] - box[axis] for axis in range(3))
    wb_box(name + "_白盒", center, dims, wb_mat)
    whitebox_labels.append(((center[0], center[1], box[5] + 0.3), name.replace("roof_", "")))
for location, label in whitebox_labels:
    curve = bpy.data.curves.new("标注_" + label, "FONT")
    curve.body = label
    curve.font = bpy.data.fonts.load("C:/Windows/Fonts/msyh.ttc", check_existing=True)
    curve.align_x = "CENTER"
    curve.size = 1.4
    curve.extrude = 0.01
    text = bpy.data.objects.new("标注_" + label, curve)
    wb_root.objects.link(text)
    text.location = location
    text.rotation_euler = (0.0, 0.0, 0.0)
    text.data.materials.append(label_mat)
wb_camera_data = bpy.data.cameras.new("白盒顶视标注相机")
wb_camera_data.type = "ORTHO"
wb_camera_data.ortho_scale = 80
wb_camera = bpy.data.objects.new("白盒顶视标注相机", wb_camera_data)
wb_root.objects.link(wb_camera)
wb_camera.location = (0, 0, 150)
wb_camera.rotation_euler = (0, 0, 0)
wb_scene.camera = wb_camera
wb_sun_data = bpy.data.lights.new("白盒中性太阳", "SUN")
wb_sun_data.energy = 3.0
wb_sun = bpy.data.objects.new("白盒中性太阳", wb_sun_data)
wb_root.objects.link(wb_sun)
wb_sun.rotation_euler = (0.15, -0.20, 0.0)
wb_scene.render.filepath = str(whitebox_preview)
bpy.ops.wm.save_as_mainfile(filepath=str(whitebox_blend))
bpy.ops.render.render(write_still=True)
whitebox_top = whitebox_preview.with_name("whitebox_top.png")
for obj in wb_root.objects:
    if obj.type == "FONT":
        obj.hide_render = True
wb_scene.render.filepath = str(whitebox_top)
bpy.ops.render.render(write_still=True)
whitebox["artifacts"] = {"blend": whitebox_blend.relative_to(PROJECT).as_posix(), "top_preview": whitebox_top.relative_to(PROJECT).as_posix(), "top_annotated_preview": whitebox_preview.relative_to(PROJECT).as_posix()}
(WB / "whitebox_landscape_skyline20_v007.json").write_text(json.dumps(whitebox, ensure_ascii=False, indent=2), encoding="utf-8")
qa_report["protected_files"] = protected_file_report()
qa_report["v005_preserved"] = qa_report["protected_files"]["unchanged"]
qa_report["component_anchors"] = anchor_records
qa_report["plan_frozen_sha256"] = plan_frozen_hash
qa_report["glb_inspection"] = {item["slug"]: item["glb_inspection"] for item in export_records}
qa_report["whitebox"] = whitebox["artifacts"]
(SRC / "qa/qa_report.json").write_text(json.dumps(qa_report, ensure_ascii=False, indent=2), encoding="utf-8")
print("LANDSCAPE_SKYLINE20_V007_BUILD_OK")
print("SOURCE", SOURCE_BLEND)
print("OPTIMIZED", OPT_BLEND)
print("COMPONENTS", len(export_records))
print("INSTANCE_TRIANGLES", runtime_triangles)
