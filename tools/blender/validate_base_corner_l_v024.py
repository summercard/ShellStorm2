import bpy
import json
import math
from pathlib import Path


PACKAGE_NAME = "117_基地5米L型转角墙_资产包"
OUTPUT_NAME = "基地5米L型转角墙_主体_金属哑光反光"
COLLISION_NAMES = (
    "COLLISION_基地5米L型转角墙_长臂",
    "COLLISION_基地5米L型转角墙_短臂",
)
PALETTE_PATH = Path(__file__).resolve().parents[2] / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"


def close_tuple(actual, expected, tolerance=1.0e-4):
    return len(actual) == len(expected) and all(abs(a - b) <= tolerance for a, b in zip(actual, expected))


def uv_area(points):
    return abs(sum(
        points[index].x * points[(index + 1) % len(points)].y
        - points[(index + 1) % len(points)].x * points[index].y
        for index in range(len(points))
    )) * 0.5


def main():
    failures = []
    package = bpy.data.collections.get(PACKAGE_NAME)
    output = bpy.data.objects.get(OUTPUT_NAME)
    if package is None:
        failures.append("missing independent package collection")
    if output is None:
        failures.append("missing integrated visual output")
    else:
        if not close_tuple(tuple(output.dimensions), (5.15, 5.15, 8.9)):
            failures.append(f"wrong overall visual bounds: {tuple(output.dimensions)}")
        if not close_tuple(tuple(output.location), (0.0, 0.0, 0.0)):
            failures.append("visual root is not at local origin")
        materials = [material.name for material in output.data.materials if material]
        if materials != ["02_细腻哑光_青绿大面_117转角墙外链修正版"]:
            failures.append(f"wrong material role: {materials}")
        if [layer.name for layer in output.data.uv_layers] != ["PaletteUV"]:
            failures.append("visual output must contain PaletteUV only")
        layer = output.data.uv_layers.get("PaletteUV")
        if layer is None or output.data.uv_layers.active != layer or not layer.active_render:
            failures.append("PaletteUV is not active/render active")
        elif any(
            uv_area([layer.data[index].uv for index in polygon.loop_indices]) < 1.0e-7
            for polygon in output.data.polygons
        ):
            failures.append("PaletteUV contains degenerate face islands")
        elif any(
            len({min(9, max(0, math.floor(layer.data[index].uv.x * 10.0))) for index in polygon.loop_indices}) != 1
            or len({min(9, max(0, math.floor(layer.data[index].uv.y * 10.0))) for index in polygon.loop_indices}) != 1
            for polygon in output.data.polygons
        ):
            failures.append("PaletteUV contains faces crossing color cells")
        if sum(len(poly.vertices) - 2 for poly in output.data.polygons) != 168:
            failures.append("unexpected visual triangle count")
        long_rib_levels = {
            round(vertex.co.z, 3) for vertex in output.data.vertices
            if 0.20 < vertex.co.x < 4.80 and 0.09 < vertex.co.y < 0.16
        }
        short_rib_levels = {
            round(vertex.co.z, 3) for vertex in output.data.vertices
            if 0.09 < vertex.co.x < 0.16 and 0.20 < vertex.co.y < 4.80
        }
        if len(long_rib_levels) < 10:
            failures.append(f"long arm horizontal ribs are incomplete: {sorted(long_rib_levels)}")
        if len(short_rib_levels) < 10:
            failures.append(f"short arm horizontal ribs are incomplete: {sorted(short_rib_levels)}")
        material = output.data.materials[0] if output.data.materials else None
        uv_nodes = [node for node in material.node_tree.nodes if node.type == "UVMAP"] if material and material.use_nodes else []
        image_nodes = [node for node in material.node_tree.nodes if node.type == "TEX_IMAGE"] if material and material.use_nodes else []
        if not uv_nodes or any(node.uv_map != "PaletteUV" for node in uv_nodes):
            failures.append("material does not explicitly read PaletteUV")
        if not image_nodes:
            failures.append("material has no shared palette image")
        for node in image_nodes:
            if node.image is None or Path(bpy.path.abspath(node.image.filepath)).resolve() != PALETTE_PATH:
                failures.append("material palette path is not the project shared palette")
            elif node.image.packed_file is not None:
                failures.append("shared palette must remain unpacked")
            if node.interpolation != "Closest":
                failures.append("shared palette interpolation is not Closest")
    expected_collision_dimensions = ((5.0, 0.3, 9.0), (0.3, 5.0, 9.0))
    for name, expected in zip(COLLISION_NAMES, expected_collision_dimensions):
        collision = bpy.data.objects.get(name)
        if collision is None:
            failures.append(f"missing collision proxy: {name}")
        elif not close_tuple(tuple(collision.dimensions), expected):
            failures.append(f"wrong collision dimensions for {name}: {tuple(collision.dimensions)}")
    if package is not None:
        if not bool(package.get("locked_match", False)):
            failures.append("locked scene signature does not match")
        package_meshes = [obj for obj in package.all_objects if obj.type == "MESH"]
        if len(package_meshes) != 5:
            failures.append(f"unexpected package mesh count: {len(package_meshes)}")
        for obj in package_meshes:
            if len(obj.users_collection) != 1:
                failures.append(f"object belongs to multiple collections: {obj.name}")
    report = {
        "passed": not failures,
        "package": PACKAGE_NAME,
        "asset_id": package.get("asset_id", "") if package else "",
        "visual_bounds_m": [round(value, 4) for value in output.dimensions] if output else [],
        "visual_triangles": sum(len(poly.vertices) - 2 for poly in output.data.polygons) if output else 0,
        "horizontal_rib_level_count_per_arm": [len(long_rib_levels), len(short_rib_levels)] if output else [],
        "collision_dimensions_m": [list(values) for values in expected_collision_dimensions],
        "locked_match": bool(package.get("locked_match", False)) if package else False,
        "failures": failures,
    }
    print(json.dumps(report, ensure_ascii=False, indent=2))
    if failures:
        raise SystemExit(1)


main()
