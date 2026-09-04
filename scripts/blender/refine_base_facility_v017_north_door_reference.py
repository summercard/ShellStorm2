#!/usr/bin/env python3
"""Rebuild the north-east standard lift door visual to match the supplied base reference.

Only the east_personnel_security_door output/source pair and its attached light are
editable.  The scene coordinate contract remains 2.2 x 0.325 x 2.5 m.
"""
from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
REPORT = VERIFY / "north_door_reference_refinement_acceptance.json"
MANIFEST = ROOT / "east_facilities/east_personnel_security_door/asset_manifest.json"
if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

spec = importlib.util.spec_from_file_location("v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py")
reorg = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(reorg)

door = reorg.package_by_slug("east_personnel_security_door")
source = bpy.data.collections["v017_源资产包_east_personnel_security_door"]
body = bpy.data.objects["东墙标准滑升门_主体_金属哑光反光"]
emissive = bpy.data.objects["东墙标准滑升门_状态灯_柔和自发光"]
body_source = bpy.data.objects["东墙标准滑升门_主体_金属哑光反光__源"]
emissive_source = bpy.data.objects["东墙标准滑升门_状态灯_柔和自发光__源"]
lamp = bpy.data.objects["东墙滑升门_状态照明"]
lamp_source = bpy.data.objects["东墙滑升门_状态照明__源"]
allowed = set(door.objects) | set(source.objects)
locked_before = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj not in allowed}

metal = bpy.data.materials["01_精工金属_紫色骨架"]
matte = bpy.data.materials["02_细腻哑光_青绿大面"]
gloss = bpy.data.materials["03_清漆反光_紫粉点缀"]
emit = bpy.data.materials["04_柔和自发光_UI灯光"]

# Palette-cell centres.  The palette's tenth column supplies the cold industrial
# greys; cyan/orange occupy the visible top-row accent cells.
DARK = (0.95, 0.55)
MID = (0.95, 0.35)
LIGHT = (0.95, 0.25)
CYAN = (0.35, 0.95)
ORANGE = (0.45, 0.95)


class Builder:
    def __init__(self):
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[list[int]] = []
        self.materials: list[int] = []
        self.cells: list[tuple[float, float]] = []

    def face(self, indices, material, cell):
        self.faces.append(indices)
        self.materials.append(material)
        self.cells.append(cell)

    def box(self, cx, cy, cz, sx, sy, sz, material, cell):
        start = len(self.verts)
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        self.verts.extend([
            (cx - hx, cy - hy, cz - hz), (cx + hx, cy - hy, cz - hz),
            (cx + hx, cy + hy, cz - hz), (cx - hx, cy + hy, cz - hz),
            (cx - hx, cy - hy, cz + hz), (cx + hx, cy - hy, cz + hz),
            (cx + hx, cy + hy, cz + hz), (cx - hx, cy + hy, cz + hz),
        ])
        for indices in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            self.face([start + index for index in indices], material, cell)

    @staticmethod
    def octagon(cx, cz, half_width, half_height, chamfer):
        return [
            (cx - half_width + chamfer, cz + half_height), (cx + half_width - chamfer, cz + half_height),
            (cx + half_width, cz + half_height - chamfer), (cx + half_width, cz - half_height + chamfer),
            (cx + half_width - chamfer, cz - half_height), (cx - half_width + chamfer, cz - half_height),
            (cx - half_width, cz - half_height + chamfer), (cx - half_width, cz + half_height - chamfer),
        ]

    def octagonal_prism(self, cx, front, back, cz, half_width, half_height, chamfer, material, cell):
        start = len(self.verts)
        contour = self.octagon(cx, cz, half_width, half_height, chamfer)
        self.verts.extend([(x, front, z) for x, z in contour] + [(x, back, z) for x, z in contour])
        self.face([start + index for index in range(8)], material, cell)
        self.face([start + 8 + index for index in reversed(range(8))], material, cell)
        for index in range(8):
            nxt = (index + 1) % 8
            self.face([start + index, start + nxt, start + 8 + nxt, start + 8 + index], material, cell)

    def octagonal_ring(self, cx, front, back, cz, outer_w, outer_h, outer_c, inner_w, inner_h, inner_c, material, cell):
        start = len(self.verts)
        outer = self.octagon(cx, cz, outer_w, outer_h, outer_c)
        inner = self.octagon(cx, cz, inner_w, inner_h, inner_c)
        self.verts.extend(
            [(x, front, z) for x, z in outer] + [(x, back, z) for x, z in outer] +
            [(x, front, z) for x, z in inner] + [(x, back, z) for x, z in inner]
        )
        for index in range(8):
            nxt = (index + 1) % 8
            # Visible front annulus, recessed rear annulus, outer and inner bevel walls.
            self.face([start + index, start + nxt, start + 16 + nxt, start + 16 + index], material, cell)
            self.face([start + 8 + nxt, start + 8 + index, start + 24 + index, start + 24 + nxt], material, cell)
            self.face([start + index, start + 8 + index, start + 8 + nxt, start + nxt], material, cell)
            self.face([start + 16 + nxt, start + 24 + nxt, start + 24 + index, start + 16 + index], material, cell)

    def mesh(self, name, materials):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.verts, [], self.faces)
        mesh.materials.clear()
        for material in materials:
            mesh.materials.append(material)
        for polygon, material_index in zip(mesh.polygons, self.materials):
            polygon.material_index = material_index
            polygon.use_smooth = False
        uv = mesh.uv_layers.new(name="PaletteUV")
        mesh.uv_layers.active = uv
        uv.active_render = True
        for polygon, cell in zip(mesh.polygons, self.cells):
            # A small editable island entirely inside the selected palette cell.
            radius = 0.022
            for offset, loop_index in enumerate(polygon.loop_indices):
                angle = math.tau * offset / max(3, len(polygon.loop_indices))
                uv.data[loop_index].uv = (cell[0] + math.cos(angle) * radius, cell[1] + math.sin(angle) * radius)
        mesh.update()
        return mesh


def build_body_mesh(name):
    b = Builder()
    # Canonical 2.2 x 0.325 x 2.5m body envelope, then layered front geometry.
    # Recess the solid rear slab so it cannot occlude the visible layered face.
    # Its rear still reaches the canonical 0.325m envelope.
    b.box(0.0, 0.030, 1.25, 2.20, 0.265, 2.50, 0, DARK)
    # Main heavy octagonal metal surround and recessed grey door leaf.
    b.octagonal_ring(0.0, -0.1625, -0.102, 1.25, 1.04, 1.18, 0.18, 0.84, 0.98, 0.14, 0, DARK)
    b.octagonal_prism(0.0, -0.141, -0.088, 1.25, 0.82, 0.96, 0.13, 1, MID)
    # Nested industrial panel, lower orange latch module, header and side fasteners.
    b.octagonal_ring(0.0, -0.151, -0.124, 1.29, 0.64, 0.75, 0.11, 0.51, 0.62, 0.09, 0, DARK)
    b.octagonal_prism(0.0, -0.145, -0.110, 1.29, 0.49, 0.60, 0.08, 1, MID)
    b.box(0.0, -0.154, 2.13, 1.18, 0.016, 0.06, 2, LIGHT)
    b.box(-0.73, -0.153, 1.50, 0.08, 0.018, 0.42, 0, LIGHT)
    b.box(0.73, -0.153, 1.50, 0.08, 0.018, 0.42, 0, LIGHT)
    b.octagonal_ring(0.0, -0.156, -0.130, 0.63, 0.25, 0.34, 0.055, 0.16, 0.24, 0.04, 2, ORANGE)
    b.box(0.0, -0.157, 0.63, 0.20, 0.010, 0.042, 0, DARK)
    for x in (-0.91, 0.91):
        for z in (0.30, 0.92, 1.63, 2.15):
            b.box(x, -0.155, z, 0.095, 0.014, 0.095, 0, LIGHT)
    b.box(-0.48, -0.1545, 1.48, 0.42, 0.014, 0.05, 0, DARK)
    b.box(0.48, -0.1545, 1.12, 0.42, 0.014, 0.05, 0, DARK)
    return b.mesh(name, (metal, matte, gloss))


def build_emissive_mesh(name):
    b = Builder()
    # Restrained cyan status strips: visible in the reference but below sign intensity.
    b.box(0.0, -0.158, 2.13, 1.05, 0.008, 0.030, 0, CYAN)
    b.box(-0.75, -0.158, 1.85, 0.030, 0.008, 0.17, 0, CYAN)
    b.box(0.75, -0.158, 1.85, 0.030, 0.008, 0.17, 0, CYAN)
    b.box(0.0, -0.158, 0.63, 0.12, 0.008, 0.022, 0, ORANGE)
    return b.mesh(name, (emit,))


body.data = build_body_mesh("东墙标准滑升门_主体_金属哑光反光_参考深化网格")
emissive.data = build_emissive_mesh("东墙标准滑升门_状态灯_柔和自发光_参考深化网格")
body_source.data = body.data.copy()
body_source.data.name = "东墙标准滑升门_主体_金属哑光反光_参考深化网格__源"
emissive_source.data = emissive.data.copy()
emissive_source.data.name = "东墙标准滑升门_状态灯_柔和自发光_参考深化网格__源"
for obj in (body, emissive, body_source, emissive_source):
    obj["高还原结构"] = "厚重八角外框、分层内嵌门板、下部橙色锁扣、冷青状态条"
    obj["参考版本"] = "v017_north_door_reference_refine_001"

for target in (lamp, lamp_source):
    target.location = (14.84, 2.50, 2.13)
    target.data.color = (0.12, 0.78, 1.0)
    target.data.energy = 38.0
    target.data.shadow_soft_size = 0.22
    target["高还原灯光"] = "门顶冷青状态条的局部实体照明"

bpy.context.view_layer.update()
center, size = reorg.bbox((body, emissive))
if center != [15.0, 2.5, 1.25] or size != [0.325, 2.2, 2.5]:
    raise RuntimeError(f"door interface changed: center={center}, size={size}")
for obj in (body, emissive, body_source, emissive_source):
    uv = obj.data.uv_layers.get("PaletteUV")
    if [layer.name for layer in obj.data.uv_layers] != ["PaletteUV"] or obj.data.uv_layers.active != uv or not uv.active_render:
        raise RuntimeError(f"PaletteUV layer contract failed: {obj.name}")

catalog = reorg.write_catalog(reorg.packages())
meta = {
    "component_set": "base99_east_door_wall_set",
    "component_set_role": "lift_door",
    "host_wall_asset": "east_door_wall_module",
    "scene_anchor_m": [15.0, 2.5, 0.0],
    "scene_bay": "保留东墙_03（北段）",
    "visual_revision": "v017_north_door_reference_refine_001",
    "reference_structure": ["厚重八角金属外框", "冷灰分层内门板", "下部橙色锁扣", "门顶冷青状态条", "右侧独立门禁接口"],
    "interface_contract_m": {"width": 2.2, "depth": 0.325, "height": 2.5, "center": [15.0, 2.5, 1.25]},
    "light_ownership": "东墙滑升门_状态照明与其源镜像均归属 east_personnel_security_door",
}
manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
manifest.update(meta)
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for entry in catalog["packages"]:
    if entry["asset_slug"] == "east_personnel_security_door":
        entry.update(meta)
catalog["source"] = "v017 north door reference refinement"
catalog["scope"] = "Only the standard personnel lift-door package output/source meshes and attached local status lights were rebuilt; all other scene objects signature locked."
reorg.CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

locked_after = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj.name in locked_before}
mismatches = {name: {"before": locked_before[name], "after": locked_after.get(name)} for name in locked_before if locked_before[name] != locked_after.get(name)}
if mismatches:
    raise RuntimeError(f"outside-scope mutations: {list(mismatches)[:8]}")
result = {
    "status": "pass",
    "scope": "east_personnel_security_door output/source meshes plus two attached state-light objects",
    "lock": {"locked_count": len(locked_before), "locked_match": True, "mismatches": {}},
    "door_center_m": center,
    "door_dimensions_m": size,
    "visual_layers": meta["reference_structure"],
    "object_count": len(door.objects),
    "source_object_count": len(source.objects),
    "package_count": len(reorg.packages()),
    "runtime_note": "Blender source visual refined only; no standalone GLB, collision, LOD or PackedScene was exported in this iteration.",
}
REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.context.scene["v017_iteration"] = "north_door_reference_refine_001"
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps(result, ensure_ascii=False))
