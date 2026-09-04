"""Audit the current Base99 mezzanine, stairs, and wall output packages."""

from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT = Path("/Users/summercards/ShellStorm2")
OUTPUT = PROJECT / "outputs/verification/base99_structural_assets_preopt_audit.json"
ASSET_IDS = (
    "ENV-BASE99-MEZZANINE-20X10-Z5",
    "ENV-BASE99-STAIR-L-Z5",
    "ENV-BASE99-WALL-PLAIN-5X9",
    "ENV-BASE99-WALL-DOOR-5X9",
    "ENV-BASE99-WALL-WINDOW-5X9",
)


def descendants(root: bpy.types.Object) -> list[bpy.types.Object]:
    result: list[bpy.types.Object] = []
    queue = list(root.children)
    while queue:
        node = queue.pop()
        result.append(node)
        queue.extend(node.children)
    return result


def local_bounds(root: bpy.types.Object, objects: list[bpy.types.Object]) -> tuple[list[float], list[float]]:
    inverse = root.matrix_world.inverted()
    points = [
        inverse @ obj.matrix_world @ vertex.co
        for obj in objects
        for vertex in obj.data.vertices
    ]
    minimum = [min(point[index] for point in points) for index in range(3)]
    maximum = [max(point[index] for point in points) for index in range(3)]
    return minimum, maximum


def triangle_count(mesh: bpy.types.Mesh) -> int:
    return sum(max(0, len(face.vertices) - 2) for face in mesh.polygons)


def report_asset(asset_id: str) -> dict:
    roots = [
        obj for obj in bpy.data.objects
        if obj.get("asset_id") == asset_id and "输出根节点" in obj.name
    ]
    if not roots:
        raise RuntimeError("Expected at least one output root for %s" % asset_id)
    # Earlier output roots are intentionally kept in the editable Blend for rollback.
    root = sorted(roots, key=lambda node: str(node.get("asset_version", "v001")))[-1]
    meshes = [obj for obj in descendants(root) if obj.type == "MESH"]
    materials = sorted({material.name for obj in meshes for material in obj.data.materials if material})
    polygons = sum(len(obj.data.polygons) for obj in meshes)
    triangles = sum(triangle_count(obj.data) for obj in meshes)
    vertices = sum(len(obj.data.vertices) for obj in meshes)
    uv_failures = 0
    for obj in meshes:
        uv = obj.data.uv_layers.get("PaletteUV")
        if uv is None or obj.data.uv_layers.active != uv or not uv.active_render:
            uv_failures += len(obj.data.polygons)
    minimum, maximum = local_bounds(root, meshes)
    return {
        "asset_id": asset_id,
        "asset_version": root.get("asset_version", "v001"),
        "root": root.name,
        "mesh_count": len(meshes),
        "vertices": vertices,
        "polygons": polygons,
        "triangles": triangles,
        "materials": materials,
        "palette_uv_failures": uv_failures,
        "bounds_min": [round(value, 5) for value in minimum],
        "bounds_max": [round(value, 5) for value in maximum],
        "dimensions": [round(maximum[index] - minimum[index], 5) for index in range(3)],
    }


def report_source_children(asset_id: str) -> list[dict]:
    roots = [
        obj for obj in bpy.data.objects
        if obj.get("asset_id") == asset_id and "制作根节点" in obj.name
    ]
    if not roots:
        return []
    root = sorted(roots, key=lambda node: str(node.get("asset_version", "v001")))[-1]
    return [
        {
            "name": child.name,
            "triangles": triangle_count(child.data) if child.type == "MESH" else 0,
            "type": child.type,
            "semantic_component": child.get("semantic_component", ""),
        }
        for child in root.children
    ]


result = {
    "blend": bpy.data.filepath,
    "assets": [report_asset(asset_id) for asset_id in ASSET_IDS],
    "mezzanine_source_children": report_source_children("ENV-BASE99-MEZZANINE-20X10-Z5"),
}
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for asset in result["assets"]:
    print("BASE99_STRUCTURE_AUDIT:%s:triangles=%d meshes=%d" % (
        asset["asset_id"], asset["triangles"], asset["mesh_count"]
    ))
