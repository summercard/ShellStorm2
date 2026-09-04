"""Audit Base99 v017 floor-source overlaps and top-down mesh optimization scope.

Read-only: this script does not save or mutate the loaded Blender file.
"""

from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector


PROJECT_ROOT = Path(__file__).resolve().parents[2]
BLEND_VERSION = Path(bpy.data.filepath).stem.rsplit("_", 1)[-1]
OUTPUT = PROJECT_ROOT / "outputs/verification" / f"base99_floor_{BLEND_VERSION}_overlap_audit.json"
FLOOR_COLLECTION_SUFFIX = "_原砖与深化内容_资产包"
LOFT_COLLECTION_NAME = "116_二楼地板色彩深化_资产包"
REUSED_BASE_MARKERS = ("保留地板", "普通地板_主体", "带铆钉地板_主体", "输出根节点")
TOP_NORMAL_MIN_Z = 0.95
BOTTOM_NORMAL_MAX_Z = -0.95
PLANE_EPSILON = 0.0005
AREA_EPSILON = 0.000001
GRID_SIZE = 0.25
MAX_CANDIDATES = 300


def is_reused_base_object(obj: bpy.types.Object) -> bool:
    return any(marker in obj.name for marker in REUSED_BASE_MARKERS)


def signed_area(points: list[Vector]) -> float:
    return sum(
        points[index].x * points[(index + 1) % len(points)].y
        - points[(index + 1) % len(points)].x * points[index].y
        for index in range(len(points))
    ) * 0.5


def polygon_area(points: list[Vector]) -> float:
    return abs(signed_area(points))


def line_intersection(start: Vector, end: Vector, clip_start: Vector, clip_end: Vector) -> Vector:
    direction = end - start
    clip_direction = clip_end - clip_start
    denominator = direction.x * clip_direction.y - direction.y * clip_direction.x
    if abs(denominator) <= 0.000000001:
        return start.copy()
    offset = clip_start - start
    t = (offset.x * clip_direction.y - offset.y * clip_direction.x) / denominator
    return start + direction * t


def clip_convex(subject: list[Vector], clip: list[Vector]) -> list[Vector]:
    """Sutherland-Hodgman clip for CCW convex polygons in the XY plane."""
    output = subject
    for index, clip_start in enumerate(clip):
        clip_end = clip[(index + 1) % len(clip)]
        if not output:
            break
        input_points = output
        output = []
        previous = input_points[-1]
        previous_inside = (
            (clip_end.x - clip_start.x) * (previous.y - clip_start.y)
            - (clip_end.y - clip_start.y) * (previous.x - clip_start.x)
        ) >= -AREA_EPSILON
        for current in input_points:
            current_inside = (
                (clip_end.x - clip_start.x) * (current.y - clip_start.y)
                - (clip_end.y - clip_start.y) * (current.x - clip_start.x)
            ) >= -AREA_EPSILON
            if current_inside != previous_inside:
                output.append(line_intersection(previous, current, clip_start, clip_end))
            if current_inside:
                output.append(current.copy())
            previous = current
            previous_inside = current_inside
    return output


def overlapping_area(first: list[Vector], second: list[Vector]) -> float:
    first_xy = [Vector((point.x, point.y)) for point in first]
    second_xy = [Vector((point.x, point.y)) for point in second]
    if signed_area(first_xy) < 0.0:
        first_xy.reverse()
    if signed_area(second_xy) < 0.0:
        second_xy.reverse()
    return polygon_area(clip_convex(first_xy, second_xy))


def cell_range(minimum: float, maximum: float) -> range:
    start = int(minimum // GRID_SIZE)
    end = int(maximum // GRID_SIZE)
    return range(start, end + 1)


def selected_floor_objects() -> tuple[list[dict[str, object]], list[bpy.types.Object]]:
    entries: list[dict[str, object]] = []
    detail_objects: list[bpy.types.Object] = []
    floor_collections = sorted(
        [
            collection
            for collection in bpy.data.collections
            if collection.name.startswith("地砖_R")
            and collection.name.endswith(FLOOR_COLLECTION_SUFFIX)
        ],
        key=lambda collection: collection.name,
    )
    if len(floor_collections) != 36:
        raise RuntimeError(f"Expected 36 floor packages, got {len(floor_collections)}")
    for collection in floor_collections:
        for obj in collection.objects:
            if obj.type != "MESH":
                continue
            role = "base" if is_reused_base_object(obj) else "detail"
            entries.append({"object": obj, "package": collection.name, "role": role})
            if role == "detail":
                detail_objects.append(obj)
    loft = bpy.data.collections.get(LOFT_COLLECTION_NAME)
    if loft is None:
        raise RuntimeError(f"Missing loft collection: {LOFT_COLLECTION_NAME}")
    for obj in loft.objects:
        if obj.type == "MESH":
            entries.append({"object": obj, "package": loft.name, "role": "loft_detail"})
            detail_objects.append(obj)
    return entries, detail_objects


def triangles_for_entries(entries: list[dict[str, object]]) -> tuple[list[dict[str, object]], dict[str, int], float]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    top_triangles: list[dict[str, object]] = []
    downward_count: dict[str, int] = defaultdict(int)
    downward_area = 0.0
    for entry in entries:
        obj = entry["object"]
        role = str(entry["role"])
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        try:
            mesh.calc_loop_triangles()
            for triangle in mesh.loop_triangles:
                points = [evaluated.matrix_world @ mesh.vertices[index].co for index in triangle.vertices]
                normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
                area = (points[1] - points[0]).cross(points[2] - points[0]).length * 0.5
                if role != "base" and normal.z < BOTTOM_NORMAL_MAX_Z:
                    downward_count[obj.name] += 1
                    downward_area += area
                if normal.z < TOP_NORMAL_MIN_Z:
                    continue
                z_values = [point.z for point in points]
                if max(z_values) - min(z_values) > PLANE_EPSILON:
                    continue
                top_triangles.append(
                    {
                        "object": obj.name,
                        "package": entry["package"],
                        "role": role,
                        "material": (
                            obj.material_slots[triangle.material_index].material.name
                            if triangle.material_index < len(obj.material_slots)
                            and obj.material_slots[triangle.material_index].material is not None
                            else None
                        ),
                        "points": points,
                        "z": sum(z_values) / 3.0,
                        "area": area,
                    }
                )
        finally:
            evaluated.to_mesh_clear()
    return top_triangles, downward_count, downward_area


def find_top_overlaps(triangles: list[dict[str, object]]) -> list[dict[str, object]]:
    buckets: dict[tuple[int, int, int], list[int]] = defaultdict(list)
    for index, triangle in enumerate(triangles):
        points = triangle["points"]
        min_x = min(point.x for point in points)
        max_x = max(point.x for point in points)
        min_y = min(point.y for point in points)
        max_y = max(point.y for point in points)
        plane = round(float(triangle["z"]) / PLANE_EPSILON)
        for cell_x in cell_range(min_x, max_x):
            for cell_y in cell_range(min_y, max_y):
                buckets[(plane, cell_x, cell_y)].append(index)
    visited: set[tuple[int, int]] = set()
    candidates: list[dict[str, object]] = []
    for indices in buckets.values():
        for first_offset, first_index in enumerate(indices):
            for second_index in indices[first_offset + 1 :]:
                pair = tuple(sorted((first_index, second_index)))
                if pair in visited:
                    continue
                visited.add(pair)
                first = triangles[first_index]
                second = triangles[second_index]
                if first["object"] == second["object"]:
                    continue
                if abs(float(first["z"]) - float(second["z"])) > PLANE_EPSILON:
                    continue
                overlap = overlapping_area(first["points"], second["points"])
                if overlap <= AREA_EPSILON:
                    continue
                candidates.append(
                    {
                        "overlap_area_m2": round(overlap, 8),
                        "z_m": round(float(first["z"]), 6),
                        "first": {
                            key: first[key]
                            for key in ("object", "package", "role", "material")
                        },
                        "second": {
                            key: second[key]
                            for key in ("object", "package", "role", "material")
                        },
                    }
                )
                if len(candidates) >= MAX_CANDIDATES:
                    return candidates
    return candidates


def main() -> None:
    entries, _detail_objects = selected_floor_objects()
    top_triangles, downward_count, downward_area = triangles_for_entries(entries)
    overlaps = find_top_overlaps(top_triangles)
    payload = {
        "source_blend": bpy.data.filepath,
        "audit_scope": "36 ground tile packages including reused base meshes, plus loft finish",
        "top_horizontal_triangle_count": len(top_triangles),
        "top_coplanar_overlap_candidate_count": len(overlaps),
        "top_coplanar_overlap_candidates": overlaps,
        "downward_facing_triangle_count": sum(downward_count.values()),
        "downward_facing_area_m2": round(downward_area, 6),
        "downward_facing_triangles_by_object": dict(sorted(downward_count.items())),
        "thresholds": {
            "top_normal_min_z": TOP_NORMAL_MIN_Z,
            "bottom_normal_max_z": BOTTOM_NORMAL_MAX_Z,
            "plane_epsilon_m": PLANE_EPSILON,
        },
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"BASE99_FLOOR_OVERLAP_AUDIT:{OUTPUT}")
    print(f"TOP_COPLANAR_OVERLAPS:{len(overlaps)}")
    print(f"DOWNWARD_TRIANGLES:{sum(downward_count.values())}")


if __name__ == "__main__":
    main()
