"""Probe the door wall's thickness layering before mirroring the decoration.

Question this answers: the structural back plane sits at Blender +Y = 0.15 and the
decoration protrudes to -Y.  To mirror the decoration onto the +Y side without
creating coincident (z-fighting) faces, the derivation has to split the mesh by
the structural plane.  That split is only safe if it is exactly there, so measure
it instead of assuming it.

Run:
    blender --factory-startup --background --python _scratch/inspect_door_wall_layers.py
"""

import sys
from pathlib import Path

import bpy
from mathutils import Vector

PROJECT = Path(__file__).resolve().parents[1]
DERIVED = (
    PROJECT
    / "assets/art/environments/tower_descent_3d/source/wall_height12"
    / "env_tower_wall_door_5m_source_v004.blend"
)
SOURCE = (
    PROJECT
    / "assets/art/environments/tower_zones/battle/source/common_components/v007"
    / "env_battle_common_components_source_v007.blend"
)

PLANE_Y_M = 0.15
EPS = 0.002


def band(value, width=0.02):
    return round(value / width) * width


def report(label, obj):
    mesh = obj.data
    print("=" * 78)
    print("### %s  object=%s" % (label, obj.name))
    points = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lows = [min(p[i] for p in points) for i in range(3)]
    highs = [max(p[i] for p in points) for i in range(3)]
    print("  verts=%d faces=%d" % (len(mesh.vertices), len(mesh.polygons)))
    print("  bounds min=%s max=%s" % ([round(v, 5) for v in lows], [round(v, 5) for v in highs]))
    print("  uv_layers=%s" % [l.name for l in mesh.uv_layers])
    print("  material_slots=%s" % [s.material.name if s.material else None for s in obj.material_slots])

    matrix = obj.matrix_world
    faces = list(mesh.polygons)

    # Face-centre histogram along Blender Y (the thickness axis).
    hist = {}
    for face in faces:
        center = matrix @ face.center
        hist[band(center.y)] = hist.get(band(center.y), 0) + 1
    print("  --- face-centre histogram along Blender Y (0.02 bins) ---")
    for key in sorted(hist):
        print("    y=%+.2f  %5d  %s" % (key, hist[key], "#" * min(60, hist[key] // 20)))

    # Split into the three regions the mirror decision needs.
    in_front = []      # whole face strictly in front of the structural plane
    straddle = []      # face crosses the plane
    inside = []        # face inside / behind the structural slab
    for face in faces:
        ys = [(matrix @ mesh.vertices[i].co).y for i in face.vertices]
        lo, hi = min(ys), max(ys)
        if hi <= -(PLANE_Y_M + EPS):
            in_front.append(face.index)
        elif lo < -(PLANE_Y_M + EPS) < hi:
            straddle.append(face.index)
        else:
            inside.append(face.index)

    print("  --- split at Blender y = %.3f ---" % PLANE_Y_M)
    print("    strictly in front (decor)  = %d" % len(in_front))
    print("    straddling the plane       = %d" % len(straddle))
    print("    inside/behind the slab     = %d" % len(inside))

    if in_front:
        pts = [matrix @ mesh.vertices[i].co for fi in in_front for i in mesh.polygons[fi].vertices]
        print(
            "    decor bounds min=%s max=%s"
            % (
                [round(min(p[i] for p in pts), 5) for i in range(3)],
                [round(max(p[i] for p in pts), 5) for i in range(3)],
            )
        )
        roles = {}
        for fi in in_front:
            name = obj.material_slots[mesh.polygons[fi].material_index].material
            key = name.name if name else "<none>"
            roles[key] = roles.get(key, 0) + 1
        print("    decor faces per material role = %s" % roles)

    # Where exactly does the outermost geometry sit, and is the slab's front face
    # present as a plane at all (it only shows through gaps in the decoration)?
    front_plane = [
        f.index
        for f in faces
        if all(abs((matrix @ mesh.vertices[i].co).y + PLANE_Y_M) <= EPS for i in f.vertices)
    ]
    back_plane = [
        f.index
        for f in faces
        if all(abs((matrix @ mesh.vertices[i].co).y - PLANE_Y_M) <= EPS for i in f.vertices)
    ]
    print("    faces lying ON y=%+.3f (structural back plane) = %d" % (PLANE_Y_M, back_plane))
    print("    faces lying ON y=%+.3f (slab front plane)      = %d" % (-PLANE_Y_M, front_plane))

    down = [f.index for f in faces if f.normal.normalized().z < -0.5]
    print("    world-downward faces = %d" % len(down))

    # Open-shell detection: a boundary edge means the decoration has an open rear
    # (no cap against the slab), which decides whether the mirrored copy needs one.
    edge_use = {}
    for face in faces:
        verts = list(face.vertices)
        for i in range(len(verts)):
            key = tuple(sorted((verts[i], verts[(i + 1) % len(verts)])))
            edge_use[key] = edge_use.get(key, 0) + 1
    boundary = sum(1 for v in edge_use.values() if v == 1)
    nonmanifold = sum(1 for v in edge_use.values() if v > 2)
    print("    edges: total=%d boundary(open)=%d nonmanifold=%d" % (len(edge_use), boundary, nonmanifold))


for path, label, wanted in (
    (DERIVED, "DERIVED v004 (post-yaw, decor on Blender -Y)", "ENV_TOWER_WALL_DOOR_5M"),
    (SOURCE, "SOURCE v007 wall_door_5m package (decor on Blender +Y)", "wall_door_5m_主体_输出"),
):
    if not path.is_file():
        print("MISSING %s" % path)
        continue
    bpy.ops.wm.open_mainfile(filepath=str(path))
    obj = bpy.data.objects.get(wanted)
    if obj is None:
        print("MISSING object %s in %s" % (wanted, path))
        continue
    report(label, obj)

print("INSPECT_DONE")
