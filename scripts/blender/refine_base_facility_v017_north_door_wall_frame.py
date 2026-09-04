#!/usr/bin/env python3
"""Add the north door's frame as wall-owned geometry in the locked v017 scene.

The personnel door leaf and the access controller remain separate assets.  This
script only changes the output/source meshes inside east_door_wall_module.
"""
from __future__ import annotations

import importlib.util
import json
import math
from pathlib import Path

import bpy

PROJECT = Path("/Users/summercards/ShellStorm2")
BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
ROOT = PROJECT / "source/art/blender/base_facility_layout/component_packages_v017"
VERIFY = PROJECT / "outputs/verification/base_facility_runtime_layout_hq_v017"
REPORT = VERIFY / "north_door_wall_frame_refinement_acceptance.json"
MANIFEST = ROOT / "architecture/east_door_wall_module/asset_manifest.json"

if Path(bpy.data.filepath).resolve() != BLEND.resolve():
    raise RuntimeError("must run with v017 open")

spec = importlib.util.spec_from_file_location(
    "v017_reorg", PROJECT / "scripts/blender/reorganize_base_facility_component_packages_v017.py"
)
reorg = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(reorg)

wall_package = reorg.package_by_slug("east_door_wall_module")
source_package = bpy.data.collections["v017_源资产包_east_door_wall_module"]
wall = bpy.data.objects["带门墙体_主体_金属哑光反光.002"]
wall_source = bpy.data.objects["带门墙体_主体_金属哑光反光.002__源"]
door = bpy.data.objects["东墙标准滑升门_主体_金属哑光反光"]
access = bpy.data.objects["东墙人员门_门侧控制面板"]
access_before = reorg.signature(access)

allowed = set(wall_package.objects) | set(source_package.objects)
locked_before = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj not in allowed}

metal = bpy.data.materials["01_精工金属_紫色骨架"]
matte = bpy.data.materials["02_细腻哑光_青绿大面"]
gloss = bpy.data.materials["03_清漆反光_紫粉点缀"]

# Palette-cell centres in the shared external 10x10 palette.
DARK = (0.95, 0.55)
MID = (0.95, 0.35)
LIGHT = (0.95, 0.25)
ORANGE = (0.45, 0.95)


class FrameBuilder:
    def __init__(self):
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[list[int]] = []
        self.materials: list[int] = []
        self.cells: list[tuple[float, float]] = []

    def face(self, indices, material, cell):
        self.faces.append(list(indices))
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

    def ring(self, cx, front, back, cz, outer_w, outer_h, outer_c, inner_w, inner_h, inner_c, material, cell):
        start = len(self.verts)
        outer = self.octagon(cx, cz, outer_w, outer_h, outer_c)
        inner = self.octagon(cx, cz, inner_w, inner_h, inner_c)
        self.verts.extend(
            [(x, front, z) for x, z in outer] + [(x, back, z) for x, z in outer] +
            [(x, front, z) for x, z in inner] + [(x, back, z) for x, z in inner]
        )
        for index in range(8):
            nxt = (index + 1) % 8
            self.face([start + index, start + nxt, start + 16 + nxt, start + 16 + index], material, cell)
            self.face([start + 8 + nxt, start + 8 + index, start + 24 + index, start + 24 + nxt], material, cell)
            self.face([start + index, start + 8 + index, start + 8 + nxt, start + nxt], material, cell)
            self.face([start + 16 + nxt, start + 24 + nxt, start + 24 + index, start + 16 + index], material, cell)


def copy_existing_mesh_data(old):
    """Return geometry with a polygon-ordered PaletteUV copy from the old wall."""
    uv = old.data.uv_layers.get("PaletteUV")
    if uv is None:
        raise RuntimeError("wall does not have PaletteUV")
    vertices = [tuple(vertex.co) for vertex in old.data.vertices]
    faces = [list(polygon.vertices) for polygon in old.data.polygons]
    uvs = [[tuple(uv.data[index].uv) for index in polygon.loop_indices] for polygon in old.data.polygons]
    return vertices, faces, uvs


def build_wall_with_frame(old, name):
    vertices, faces, old_uvs = copy_existing_mesh_data(old)
    frame = FrameBuilder()
    # The wall's local -Y face is its exterior.  A 52mm trim projection prevents
    # z-fighting while keeping the 5x9m wall-core contract intact.
    frame.ring(0.0, -0.638, -0.548, 1.55, 1.36, 1.55, 0.20, 1.18, 1.36, 0.16, 0, DARK)
    # Inset cold-grey reveal gives the wall-side door frame a distinct stepped
    # silhouette without becoming part of the independent door leaf asset.
    frame.ring(0.0, -0.643, -0.610, 1.55, 1.285, 1.465, 0.16, 1.215, 1.395, 0.13, 1, MID)
    frame.box(0.0, -0.650, 3.07, 1.58, 0.070, 0.105, 0, LIGHT)
    frame.box(0.0, -0.655, 3.07, 1.15, 0.012, 0.030, 2, ORANGE)
    # Anchored fasteners and small orange service tags belong to the wall frame.
    for x in (-1.22, 1.22):
        for z in (0.36, 1.08, 1.92, 2.66):
            frame.box(x, -0.651, z, 0.105, 0.050, 0.105, 0, LIGHT)
    for x in (-1.23, 1.23):
        frame.box(x, -0.654, 2.45, 0.15, 0.014, 0.060, 2, ORANGE)

    offset = len(vertices)
    vertices.extend(frame.verts)
    faces.extend([[offset + index for index in face] for face in frame.faces])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    for material in (metal, matte, gloss):
        mesh.materials.append(material)
    # Existing wall stays matte.  All new annular trim faces use shared role slots.
    for index, polygon in enumerate(mesh.polygons):
        polygon.material_index = 1 if index < len(old_uvs) else frame.materials[index - len(old_uvs)]
        polygon.use_smooth = False
    palette = mesh.uv_layers.new(name="PaletteUV")
    mesh.uv_layers.active = palette
    palette.active_render = True
    for index, polygon in enumerate(mesh.polygons):
        if index < len(old_uvs):
            for loop_index, old_uv in zip(polygon.loop_indices, old_uvs[index]):
                palette.data[loop_index].uv = old_uv
            continue
        cell = frame.cells[index - len(old_uvs)]
        radius = 0.022
        for point_index, loop_index in enumerate(polygon.loop_indices):
            angle = math.tau * point_index / max(3, len(polygon.loop_indices))
            palette.data[loop_index].uv = (cell[0] + math.cos(angle) * radius, cell[1] + math.sin(angle) * radius)
    mesh.update()
    return mesh


wall.data = build_wall_with_frame(wall, "带门墙体_主体_墙体归属门框_参考深化网格")
wall_source.data = wall.data.copy()
wall_source.data.name = "带门墙体_主体_墙体归属门框_参考深化网格__源"
for obj in (wall, wall_source):
    obj["高还原结构"] = "墙体归属八角门框、双层冷灰门洞饰条、顶部服务铭牌、可见固定螺栓"
    obj["门框归属"] = "east_door_wall_module（门框与门洞饰条归属墙体；门扇与门禁保持独立）"
    obj["参考版本"] = "v017_north_door_wall_frame_refine_001"

bpy.context.view_layer.update()
base_wall_dims = [1.1712, 5.0, 9.0]
wall_center, wall_visual_dims = reorg.bbox((wall,))
door_center, door_dims = reorg.bbox((door,))
access_center, access_dims = reorg.bbox((access,))
if door_center != [15.0, 2.5, 1.25] or door_dims != [0.325, 2.2, 2.5]:
    raise RuntimeError(f"door interface changed: {door_center=} {door_dims=}")
if reorg.signature(access) != access_before:
    raise RuntimeError(f"access interface changed: {access_center=} {access_dims=}")
for obj in (wall, wall_source):
    layers = [layer.name for layer in obj.data.uv_layers]
    uv = obj.data.uv_layers.get("PaletteUV")
    if layers != ["PaletteUV"] or obj.data.uv_layers.active != uv or not uv.active_render:
        raise RuntimeError(f"PaletteUV contract failed: {obj.name}")

catalog = reorg.write_catalog(reorg.packages())
frame_meta = {
    "component_set": "base99_east_door_wall_set",
    "component_set_role": "host_wall_and_wall_owned_door_frame",
    "scene_anchor_m": [15.0, 2.5, 0.0],
    "scene_bay": "保留东墙_03（北段）",
    "visual_revision": "v017_north_door_wall_frame_refine_001",
    "base_wall_core_dimensions_m": {"depth": 1.1712, "width": 5.0, "height": 9.0},
    "wall_owned_door_frame": {
        "outer_width_m": 2.72,
        "outer_height_m": 3.10,
        "inner_clear_width_m": 2.36,
        "inner_clear_height_m": 2.72,
        "front_projection_m": 0.0524,
        "features": ["八角外轮廓", "双层冷灰门洞饰条", "顶部橙色服务铭牌", "成对紧固件"],
    },
    "asset_ownership": {
        "wall_and_frame": "east_door_wall_module",
        "door_leaf_and_status_light": "east_personnel_security_door",
        "access_control": "east_door_access_control",
    },
    "interface_contract": {
        "door_leaf_center_m": door_center,
        "door_leaf_dimensions_m": door_dims,
        "access_control_center_m": access_center,
        "access_control_dimensions_m": access_dims,
    },
}
manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
manifest.update(frame_meta)
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for entry in catalog["packages"]:
    if entry["asset_slug"] == "east_door_wall_module":
        entry.update(frame_meta)
catalog["source"] = "v017 north door wall frame reference refinement"
catalog["scope"] = "Only east_door_wall_module output/source wall meshes were refined with wall-owned frame geometry; door leaf, access control, supply and all other scene objects signature locked."
reorg.CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

locked_after = {obj.name: reorg.signature(obj) for obj in bpy.data.objects if obj.name in locked_before}
mismatches = {name: {"before": locked_before[name], "after": locked_after.get(name)} for name in locked_before if locked_before[name] != locked_after.get(name)}
if mismatches:
    raise RuntimeError(f"outside-scope mutations: {list(mismatches)[:8]}")

result = {
    "status": "pass",
    "scope": "east_door_wall_module output/source wall meshes only",
    "lock": {"locked_count": len(locked_before), "locked_match": True, "mismatches": {}},
    "ownership": frame_meta["asset_ownership"],
    "wall_core_dimensions_m": base_wall_dims,
    "wall_visual_center_m": wall_center,
    "wall_visual_dimensions_m": wall_visual_dims,
    "door_interface": frame_meta["interface_contract"],
    "frame": frame_meta["wall_owned_door_frame"],
    "wall_package_object_count": len(wall_package.objects),
    "source_package_object_count": len(source_package.objects),
    "package_count": len(reorg.packages()),
    "runtime_note": "Blender source visual refined only; no standalone GLB, collision, LOD or PackedScene was exported in this iteration.",
}
REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
bpy.context.scene["v017_iteration"] = "north_door_wall_frame_refine_001"
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
print(json.dumps(result, ensure_ascii=False))
