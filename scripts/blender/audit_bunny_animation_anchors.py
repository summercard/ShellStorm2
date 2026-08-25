"""Audit Bunny hand-ring and ear-root animation anchor candidates."""

import json

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


OBJECT_NAMES = (
    "SRC_Hand_Main_L",
    "SRC_Hand_Main_R",
    "SRC_Hand_Cuff_L",
    "SRC_Hand_Cuff_R",
    "SRC_Ear_L_Mirror",
    "SRC_Ear_R",
)


def _world_vertices(obj: bpy.types.Object) -> list[Vector]:
    return [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]


def _vector(value: Vector) -> list[float]:
    return [float(value.x), float(value.y), float(value.z)]


def main() -> None:
    report: dict[str, dict[str, object]] = {}
    head = bpy.data.objects["SRC_Head"]
    head_vertices = _world_vertices(head)
    head_bvh = BVHTree.FromPolygons(
        head_vertices,
        [[index for index in polygon.vertices] for polygon in head.data.polygons],
    )
    for name in OBJECT_NAMES:
        obj = bpy.data.objects[name]
        vertices = _world_vertices(obj)
        minimum = Vector(tuple(min(vertex[axis] for vertex in vertices) for axis in range(3)))
        maximum = Vector(tuple(max(vertex[axis] for vertex in vertices) for axis in range(3)))
        low_threshold = minimum.z + max(0.01, (maximum.z - minimum.z) * 0.06)
        low_vertices = [vertex for vertex in vertices if vertex.z <= low_threshold]
        low_center = sum(low_vertices, Vector()) / len(low_vertices)
        vertex_center = sum(vertices, Vector()) / len(vertices)
        report[name] = {
            "origin": _vector(obj.matrix_world.translation),
            "minimum": _vector(minimum),
            "maximum": _vector(maximum),
            "bounds_center": _vector((minimum + maximum) * 0.5),
            "vertex_center": _vector(vertex_center),
            "low_center": _vector(low_center),
            "low_vertex_count": len(low_vertices),
        }
        if name.startswith("SRC_Ear_"):
            contact_points: list[Vector] = []
            for vertex in vertices:
                nearest = head_bvh.find_nearest(vertex)
                if nearest is not None and nearest[3] <= 0.025 and vertex.z <= 1.10:
                    contact_points.append(vertex)
            if contact_points:
                report[name]["head_contact_center"] = _vector(
                    sum(contact_points, Vector()) / len(contact_points)
                )
                report[name]["head_contact_count"] = len(contact_points)
    print("BUNNY_ANCHOR_AUDIT=" + json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    main()
