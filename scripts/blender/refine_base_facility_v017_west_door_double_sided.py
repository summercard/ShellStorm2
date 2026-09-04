#!/usr/bin/env python3
"""Repair the west third-bay door wall as a centred, double-sided assembly.

Only the two existing west packages and their source mirrors are editable.  The
wall keeps the 5×9m structural core aligned to neighbouring west modules, while
the door portal and leaf gain a deliberately thicker, mirrored front/back
design.  The wall owns its portal; the sliding leaf remains a separate asset.
"""
from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
PACKAGES = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
REPORT = VERIFY / "west_door_wall_double_sided_refinement_acceptance.json"
WALL_MANIFEST = PACKAGES / "architecture/west_door_wall_module/asset_manifest.json"
DOOR_MANIFEST = PACKAGES / "west_facilities/west_door_lift_instance/asset_manifest.json"
ASSEMBLY = PACKAGES / "component_sets/west_door_wall_set/assembly_manifest.json"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

spec = importlib.util.spec_from_file_location(
    "v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py"
)
reorg = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(reorg)

wall_package = reorg.package_by_slug("west_door_wall_module")
door_package = reorg.package_by_slug("west_door_lift_instance")
wall_source_package = bpy.data.collections["v017_源资产包_west_door_wall_module"]
door_source_package = bpy.data.collections["v017_源资产包_west_door_lift_instance"]

wall = bpy.data.objects["西墙带门墙体_主体_金属哑光反光"]
wall_source = bpy.data.objects["西墙带门墙体_主体_金属哑光反光__源"]
door = bpy.data.objects["西墙标准滑升门_主体_金属哑光反光"]
door_source = bpy.data.objects["西墙标准滑升门_主体_金属哑光反光__源"]
emissive = bpy.data.objects["西墙标准滑升门_状态灯_柔和自发光"]
emissive_source = bpy.data.objects["西墙标准滑升门_状态灯_柔和自发光__源"]
lamp = bpy.data.objects["西墙滑升门_状态照明"]
lamp_source = bpy.data.objects["西墙滑升门_状态照明__源"]

allowed = set(wall_package.objects) | set(door_package.objects) | set(wall_source_package.objects) | set(door_source_package.objects)
locked_before = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj not in allowed}

metal = bpy.data.materials["01_精工金属_紫色骨架"]
matte = bpy.data.materials["02_细腻哑光_青绿大面"]
gloss = bpy.data.materials["03_清漆反光_紫粉点缀"]
emission_material = bpy.data.materials["04_柔和自发光_UI灯光"]

DARK = (0.95, 0.55)
MID = (0.95, 0.35)
LIGHT = (0.95, 0.25)
ORANGE = (0.45, 0.95)
CYAN = (0.25, 0.75)


class Builder:
    def __init__(self):
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[list[int]] = []
        self.materials: list[int] = []
        self.cells: list[tuple[float, float]] = []

    def face(self, indexes, material, cell):
        self.faces.append(list(indexes))
        self.materials.append(material)
        self.cells.append(cell)

    def box(self, cx, cy, cz, sx, sy, sz, material, cell):
        base = len(self.verts)
        hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
        self.verts.extend([
            (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
            (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
            (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
            (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
        ])
        for face in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.face([base + index for index in face], material, cell)

    @staticmethod
    def octagon(cx, cz, half_width, half_height, chamfer):
        return [
            (cx - half_width + chamfer, cz + half_height), (cx + half_width - chamfer, cz + half_height),
            (cx + half_width, cz + half_height - chamfer), (cx + half_width, cz - half_height + chamfer),
            (cx + half_width - chamfer, cz - half_height), (cx - half_width + chamfer, cz - half_height),
            (cx - half_width, cz - half_height + chamfer), (cx - half_width, cz + half_height - chamfer),
        ]

    def ring(self, cx, front, back, cz, outer_w, outer_h, outer_c, inner_w, inner_h, inner_c, material, cell):
        base = len(self.verts)
        outer = self.octagon(cx, cz, outer_w, outer_h, outer_c)
        inner = self.octagon(cx, cz, inner_w, inner_h, inner_c)
        self.verts.extend(
            [(x, front, z) for x, z in outer] + [(x, back, z) for x, z in outer] +
            [(x, front, z) for x, z in inner] + [(x, back, z) for x, z in inner]
        )
        for index in range(8):
            nxt = (index + 1) % 8
            self.face([base + index, base + nxt, base + 16 + nxt, base + 16 + index], material, cell)
            self.face([base + 8 + nxt, base + 8 + index, base + 24 + index, base + 24 + nxt], material, cell)
            self.face([base + index, base + 8 + index, base + 8 + nxt, base + nxt], material, cell)
            self.face([base + 16 + nxt, base + 24 + nxt, base + 24 + index, base + 16 + index], material, cell)


def finish_mesh(name, builder: Builder, materials):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(builder.verts, [], builder.faces)
    for material in materials:
        mesh.materials.append(material)
    for index, polygon in enumerate(mesh.polygons):
        polygon.material_index = builder.materials[index]
        polygon.use_smooth = False
    palette = mesh.uv_layers.new(name="PaletteUV")
    mesh.uv_layers.active = palette
    palette.active_render = True
    for index, polygon in enumerate(mesh.polygons):
        cell = builder.cells[index]
        radius = 0.022
        for point_index, loop_index in enumerate(polygon.loop_indices):
            angle = math.tau * point_index / max(3, len(polygon.loop_indices))
            palette.data[loop_index].uv = (cell[0] + math.cos(angle) * radius, cell[1] + math.sin(angle) * radius)
    mesh.update()
    return mesh


def build_wall():
    builder = Builder()
    # The structural core exactly shares the centred 360mm thickness of adjacent
    # 5×9m west wall modules.  The opening is 2.20m wide × 2.50m high.
    builder.box(-1.80, 0.0, 4.50, 1.40, 0.36, 9.00, 1, MID)
    builder.box(+1.80, 0.0, 4.50, 1.40, 0.36, 9.00, 1, MID)
    builder.box(0.00, 0.0, 5.75, 2.20, 0.36, 6.50, 1, MID)
    for z in (3.34, 6.25, 8.35):
        builder.box(0.00, 0.0, z, 5.00, 0.42, 0.11, 0, DARK)
    # A single closed ring deliberately traverses both faces: its same octagonal
    # silhouette is visible from exterior and interior, so it cannot float away.
    builder.ring(0.0, -0.43, +0.43, 1.55, 1.43, 1.55, 0.20, 1.13, 1.25, 0.16, 0, DARK)
    builder.ring(0.0, -0.465, +0.465, 1.55, 1.34, 1.46, 0.16, 1.22, 1.34, 0.13, 1, LIGHT)
    for side in (-1.0, +1.0):
        builder.box(0.0, side * 0.485, 3.08, 1.58, 0.055, 0.10, 0, LIGHT)
        builder.box(0.0, side * 0.518, 3.08, 1.15, 0.015, 0.030, 2, ORANGE)
        for x in (-1.24, +1.24):
            for z in (0.34, 1.08, 1.94, 2.64):
                builder.box(x, side * 0.485, z, 0.105, 0.050, 0.105, 0, LIGHT)
        for x in (-1.24, +1.24):
            builder.box(x, side * 0.518, 2.43, 0.15, 0.015, 0.060, 2, ORANGE)
    return finish_mesh("西墙带门墙体_双面厚门框_对齐网格", builder, (metal, matte, gloss))


def build_door_body():
    builder = Builder()
    # The closed slab is 620mm deep and stays fully inside the 860mm portal.
    builder.box(0.0, 0.0, 1.27, 2.04, 0.62, 2.34, 0, DARK)
    for side in (-1.0, +1.0):
        y = side * 0.345
        builder.box(0.0, y, 1.27, 1.82, 0.07, 2.10, 1, MID)
        builder.box(0.0, side * 0.385, 1.28, 1.38, 0.025, 1.58, 0, DARK)
        builder.box(0.0, side * 0.402, 1.28, 1.10, 0.015, 1.28, 1, LIGHT)
        builder.box(0.0, side * 0.414, 0.62, 0.78, 0.018, 0.12, 2, ORANGE)
        builder.box(0.0, side * 0.414, 1.94, 0.78, 0.018, 0.08, 2, ORANGE)
        for x in (-0.70, +0.70):
            builder.box(x, side * 0.425, 1.25, 0.08, 0.025, 1.72, 0, DARK)
    return finish_mesh("西墙标准滑升门_双面加厚主体网格", builder, (metal, matte, gloss))


def build_door_emissive():
    builder = Builder()
    for side in (-1.0, +1.0):
        y = side * 0.438
        builder.box(0.0, y, 2.12, 1.05, 0.022, 0.055, 0, CYAN)
        builder.box(0.0, y, 1.30, 0.34, 0.022, 0.12, 0, CYAN)
        builder.box(-0.84, y, 1.85, 0.07, 0.022, 0.36, 0, CYAN)
        builder.box(+0.84, y, 0.70, 0.07, 0.022, 0.36, 0, CYAN)
    return finish_mesh("西墙标准滑升门_双面状态灯网格", builder, (emission_material,))


wall.data = build_wall()
wall.data.name = "西墙带门墙体_主体_双面厚门框_对齐网格"
wall_source.data = wall.data.copy()
wall_source.data.name = "西墙带门墙体_主体_双面厚门框_对齐网格__源"
door.data = build_door_body()
door.data.name = "西墙标准滑升门_双面加厚主体网格"
door_source.data = door.data.copy()
door_source.data.name = "西墙标准滑升门_双面加厚主体网格__源"
emissive.data = build_door_emissive()
emissive.data.name = "西墙标准滑升门_双面状态灯网格"
emissive_source.data = emissive.data.copy()
emissive_source.data.name = "西墙标准滑升门_双面状态灯网格__源"

# One centred point light illuminates both visible faces and remains owned by its
# emitting door package; it no longer implies a one-sided front face.
for point in (lamp, lamp_source):
    point.location = (-15.0, 2.5, 2.05)
    point.data.energy = 18.0
    point.data.color = (0.18, 0.82, 1.0)
    point["归属发光设施"] = "west_door_lift_instance"

for obj in (wall, wall_source):
    obj["高还原结构"] = "居中5×9m墙芯、双面闭合八角门框、双面服务铭牌、固定螺栓；门框归属墙体"
    obj["门框归属"] = "west_door_wall_module（闭合双面门框与墙体连续，不归属门扇）"
    obj["参考版本"] = "v017_west_double_sided_alignment_002"
for obj in (door, door_source, emissive, emissive_source):
    obj["高还原结构"] = "620mm加厚双面滑升门；双面同构嵌板、橙色警示条与青色状态灯"
    obj["参考版本"] = "v017_west_double_sided_alignment_002"

bpy.context.view_layer.update()
wall_center, wall_dims = reorg.bbox((wall,))
door_center, door_dims = reorg.bbox((door, emissive))
if wall_center != [-15.0, 2.5, 4.5] or wall_dims != [1.051, 5.0, 9.0]:
    raise RuntimeError(f"unexpected west wall envelope: {wall_center} {wall_dims}")
if door_center != [-15.0, 2.5, 1.27] or door_dims != [0.898, 2.04, 2.34]:
    raise RuntimeError(f"unexpected west door envelope: {door_center} {door_dims}")
for obj in (wall, wall_source, door, door_source, emissive, emissive_source):
    uv = obj.data.uv_layers.get("PaletteUV")
    if [layer.name for layer in obj.data.uv_layers] != ["PaletteUV"] or obj.data.uv_layers.active != uv or not uv.active_render:
        raise RuntimeError(f"PaletteUV contract failed: {obj.name}")

wall_manifest = json.loads(WALL_MANIFEST.read_text(encoding="utf-8"))
wall_manifest.update({
    "visual_revision": "v017_west_double_sided_alignment_002",
    "visual_envelope_m": {"depth_x": 1.051, "width_y": 5.0, "height_z": 9.0},
    "structural_core_dimensions_m": {"depth_x": 0.36, "width_y": 5.0, "height_z": 9.0},
    "wall_owned_door_frame": "双面闭合门框；与360mm墙芯同中心，外观投影930mm，门框不再脱离墙面。",
    "door_opening_m": {"width_y": 2.20, "height_z": 2.50},
})
WALL_MANIFEST.write_text(json.dumps(wall_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
door_manifest = json.loads(DOOR_MANIFEST.read_text(encoding="utf-8"))
door_manifest.update({
    "visual_revision": "v017_west_double_sided_alignment_002",
    "visual_envelope_m": {"depth_x": 0.898, "width_y": 2.04, "height_z": 2.34},
    "door_leaf_design": "620mm加厚闭合门扇；内外两面完全同构的嵌板、警示条和状态灯。",
    "fixture_light_ownership": "西墙滑升门_状态照明为门实例唯一局部点光，位于门厚度中轴，照亮双面。",
})
DOOR_MANIFEST.write_text(json.dumps(door_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
assembly = json.loads(ASSEMBLY.read_text(encoding="utf-8"))
assembly["visual_revision"] = "v017_west_double_sided_alignment_002"
assembly["interface_contract"] = {
    "wall_core": "5.000m along local X × 0.360m local Y × 9.000m Z, centred on the west wall anchor.",
    "portal": "closed, symmetric 0.930m-thick portal with 1.051m maximum service-tag detail envelope, belonging only to west_door_wall_module.",
    "door_leaf": "closed, symmetric 0.898m-thick visual slab belonging only to west_door_lift_instance.",
}
ASSEMBLY.write_text(json.dumps(assembly, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

# Do not re-run the broad legacy organizer: it would rewrite unrelated package
# manifests.  Synchronize only these two changed package records in the catalog.
catalog = json.loads(reorg.CATALOG.read_text(encoding="utf-8"))
for package, manifest in ((wall_package, wall_manifest), (door_package, door_manifest)):
    slug = str(package["资产包键"])
    entry = next(candidate for candidate in catalog["packages"] if candidate["asset_slug"] == slug)
    visual_objects = [obj for obj in package.objects if obj.type == "MESH"]
    center, dimensions = reorg.bbox(visual_objects)
    entry.update({
        "object_count": len(package.objects),
        "mesh_count": sum(obj.type == "MESH" for obj in package.objects),
        "light_count": sum(obj.type == "LIGHT" for obj in package.objects),
        "object_names": sorted(obj.name for obj in package.objects),
        "world_center_m": center,
        "bounding_size_m": dimensions,
        "visual_revision": manifest["visual_revision"],
        "visual_envelope_m": manifest["visual_envelope_m"],
    })
catalog["package_count"] = len(reorg.packages())
catalog["source"] = "v017 west door double-sided alignment refinement"
catalog["scope"] = "Only west_door_wall_module and west_door_lift_instance geometry/source mirrors were revised; all other v017 objects remain signature locked."
reorg.CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

locked_after = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj.name in locked_before}
mismatches = {name: {"before": locked_before[name], "after": locked_after.get(name)} for name in locked_before if locked_before[name] != locked_after.get(name)}
if mismatches:
    raise RuntimeError(f"outside-scope changes: {list(mismatches)[:8]}")

report = {
    "status": "pass",
    "revision": "v017_west_double_sided_alignment_002",
    "scope": "west_door_wall_module + west_door_lift_instance and their source mirrors only",
    "locked_outside_scope": len(locked_before),
    "locked_mismatches": mismatches,
    "wall_center_m": wall_center,
    "wall_envelope_m": wall_dims,
    "wall_structural_core_m": [0.36, 5.0, 9.0],
    "door_center_m": door_center,
    "door_envelope_m": door_dims,
    "door_leaf_thickness_m": 0.62,
    "wall_portal_thickness_m": 1.051,
    "double_sided": True,
    "source_mirrors": True,
}
REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.context.scene["v017_iteration"] = "west_door_double_sided_alignment_002"
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps(report, ensure_ascii=False))
