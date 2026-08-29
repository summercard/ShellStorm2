"""Print stairwell object transforms and world-space bounds for source QA."""

import bpy
from mathutils import Vector


ROOT_NAMES = (
    "Stair_Generic_Rotatable_ROOT",
    "Stair_Special_Rooftop_ROOT",
)


def bounds_in_space(obj, world_to_space):
    if obj.type != "MESH":
        return None
    points = [world_to_space @ obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    mins = tuple(min(point[i] for point in points) for i in range(3))
    maxs = tuple(max(point[i] for point in points) for i in range(3))
    return mins, maxs


for root_name in ROOT_NAMES:
    root = bpy.data.objects.get(root_name)
    if root is None:
        print(f"MISSING_ROOT {root_name}")
        continue
    print(
        f"ROOT {root.name} location={tuple(round(v, 4) for v in root.location)} "
        f"rotation={tuple(round(v, 4) for v in root.rotation_euler)}"
    )
    descendants = []
    stack = list(root.children)
    while stack:
        obj = stack.pop()
        descendants.append(obj)
        stack.extend(obj.children)
    for obj in sorted(descendants, key=lambda item: item.name):
        bounds = bounds_in_space(obj, root.matrix_world.inverted())
        relative = root.matrix_world.inverted() @ obj.matrix_world
        relative_location = tuple(round(v, 4) for v in relative.translation)
        if bounds is None:
            print(
                f"  {obj.type:8} {obj.name} "
                f"loc={tuple(round(v, 4) for v in obj.location)} rel={relative_location}"
            )
            continue
        mins, maxs = bounds
        size = tuple(maxs[i] - mins[i] for i in range(3))
        print(
            f"  MESH {obj.name} loc={tuple(round(v, 4) for v in obj.location)} "
            f"rel={relative_location} "
            f"min={tuple(round(v, 4) for v in mins)} "
            f"max={tuple(round(v, 4) for v in maxs)} "
            f"size={tuple(round(v, 4) for v in size)}"
        )
        if "DoorLanding" in obj.name or "EnclosureWall" in obj.name:
            matrix = root.matrix_world.inverted() @ obj.matrix_world
            coordinates = [matrix @ vertex.co for vertex in obj.data.vertices]
            xs = sorted({round(point.x, 4) for point in coordinates})
            ys = sorted({round(point.y, 4) for point in coordinates})
            zs = sorted({round(point.z, 4) for point in coordinates})
            print(f"    COORDS x={xs} y={ys} z={zs}")
