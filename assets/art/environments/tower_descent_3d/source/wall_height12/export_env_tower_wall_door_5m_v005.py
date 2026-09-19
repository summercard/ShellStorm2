"""Derive the tower A-suite 5m door-wall module (v005) from battle-zone art,
this time with the decoration mirrored onto the structural back so the module
reads as decor from BOTH sides.

Why this revision exists
------------------------
v004 shipped the door wall single-sided: decoration on Godot +Z (the room side),
a flat structural back on Godot -Z.  That is correct for a room's own four walls,
which `DungeonRoom3D._build_corner_aware_wall_run` rotates so the decorated face
always points into the room.  But a door wall also sits on the room/corridor
boundary, and the player standing in the corridor sees that flat back.  v005
mirrors the decoration onto the back so the module is symmetric about its own
reference plane and reads correctly from either side.

Source (read-only, never modified):
    assets/art/environments/tower_zones/battle/source/common_components/v007/
        env_battle_common_components_source_v007.blend
        -> collection `wall_door_5m_通用包`
        -> ROOT empty `ROOT_wall_door_5m_通用组件`
             + mesh `wall_door_5m_主体_输出`          (4410 polys, roles 01/02/03)
             + mesh `wall_door_5m_UI灯光_柔和自发光`   (182 polys, role 04)

Derived output (versioned, tower zone owns it):
    assets/art/environments/tower_descent_3d/source/wall_height12/
        env_tower_wall_door_5m_source_v005.blend

Runtime output (stable path, overwrite in place, no version in the name):
    assets/art/environments/tower_descent_3d/components/
        env_tower_wall_door_5m_top3d.glb

What changed against v004 (everything else is deliberately identical)
--------------------------------------------------------------------
  * NEW STEP `mirror_decoration()`, run per source mesh after the 180 deg bake and
    after triangulation, before the downward-face cull.

  * The mirror cannot be a blanket "duplicate the object and scale Y by -1".
    Measured on the v004 payload: of 7935 triangles only 7799 lie strictly in front
    of the structural plane (Blender y = -0.15); the other 136 are the back shell
    plus the door tunnel that bores the full thickness.  Mirroring the whole object
    would lay a coplanar twin directly over the back plate -- the signature of
    z-fighting -- and would also duplicate the tunnel.  So the mesh is partitioned
    at the structural plane (guard 2mm so a face merely touching the plane stays
    out), only the decoration is mirrored, and the partition is joined back.

  * The mirror runs about Blender y = 0, the structural slab's mid-plane, which is
    the module's reference plane and the shared grid centreline.  Mirroring about
    anything else would push the wall off the grid.

  * Verified on a dry run of the real mesh before this script was written:
    7935 -> 15734 faces, envelope y[-0.3415, 0.15] -> y[-0.3415, 0.3415],
    coincident-face groups 132 -> 264 (exactly 2x, i.e. the mirror added ZERO new
    coplanar twins), PaletteUV and all four material roles preserved.

Unchanged from v004 (still asserted here)
-----------------------------------------
  * 180 deg yaw about Blender Z so the decorated face (+Y in the source) lands on
    Godot +Z: Godot maps Blender (x, y, z) -> (x, z, -y), and the tower A-suite
    hard-requires forward_axis "+Z" (verify_tower_module_prefabs.gd).
  * Offset baked into the vertex data, root node exactly T=0 R=identity S=1.
    TowerDescent3D.gd preloads the sibling solid GLB directly, and the project's
    contracts assume the same root convention everywhere.
  * Downward faces are culled with a GROUND BAND, not blanket.  The door wall has a
    lintel whose underside faces straight down at z=2.5 inside the opening;
    blanket-culling would punch it out and let the player see through the wall from
    below.  Only faces on the floor plane (|z| <= GROUND_BAND_M) are removed.
  * Culling runs AFTER triangulation (an n-gon's stored normal is the average of its
    corners; measured on the solid wall: cull-then-triangulate leaves 11 survivors,
    triangulate-then-cull leaves 0).

Contract assertions this script enforces (all measured on the baked result, never
read back from the source's own metadata):

  * grid width 5.0 exactly, centred on the origin; height on Blender Z [0, 11.9]
  * BOTH decoration faces present and at equal depth: thickness axis must be
    symmetric about 0, i.e. [-DECOR_DEPTH_M, +DECOR_DEPTH_M]
  * the two halves must be exact mirrors -- face counts equal AND the per-face
    (centre, normal) signature of the +Y half must equal the mirrored signature of
    the -Y half.  A winding mistake in the mirror shows up as inward-facing normals
    (the back would render invisible in Godot) and fails here rather than in-game
  * no coincident face pair may straddle the two halves: that is the z-fighting
    guard, and it is what makes the "mirror only the decoration" cut load-bearing
  * the door opening survives: clear width 2.2, clear height 2.5, verified by ray
    casting out of the opening's own volume
  * NEW: the opening stays clear through the whole thickness (rays along +-Y from
    inside the aperture must leave the wall), because v005 added geometry to the
    far side of the opening for the first time
  * the lintel underside (the only downward-facing surface a player can look up at)
    is still present after the cull
  * one scene, one node, identity root, four primitives, no embedded images

Run:
    SS_DOOR_PHASE=derive  blender --factory-startup --background \
        --python export_env_tower_wall_door_5m_v005.py
    SS_DOOR_PHASE=export  blender --factory-startup --background \
        --python export_env_tower_wall_door_5m_v005.py
"""

import json
import math
import os
from collections import Counter
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ASSET_ID = "ENV-TOWER-WALL-DOOR-5M"
ASSET_VERSION = "v005"
NODE_NAME = "ENV_TOWER_WALL_DOOR_5M"
MESH_NAME = "ENV_TOWER_WALL_DOOR_5M_Mesh"

SOURCE_COMPONENT = "ROOT_wall_door_5m_通用组件"
SOURCE_PACKAGE = "wall_door_5m_通用包"
SOURCE_BODY = "wall_door_5m_主体_输出"
SOURCE_EMISSIVE = "wall_door_5m_UI灯光_柔和自发光"

# Door aperture contract, shared with the battle-zone common component and with
# TowerGeometry3D.DOOR_CLEAR_*: the runtime door leaf and the script-side collision
# proxy are both authored against these numbers, so the art has to honour them.
DOOR_CLEAR_WIDTH_M = 2.2
DOOR_CLEAR_HEIGHT_M = 2.5
GRID_UNIT_M = 5.0
STRUCTURAL_BACK_Y_M = 0.15
# Decoration depth, measured on the v004 payload (min Y = -0.3415).  v005 turns the
# single-sided envelope into a symmetric one, so this constant now pins both ends.
DECOR_DEPTH_M = 0.3415
# The module's reference plane: the structural slab is +-0.15 thick, so its
# mid-plane is y = 0 and that is where the mirror has to run.
MIRROR_PLANE_Y_M = 0.0
# Faces are only mirrored when they lie ENTIRELY in front of the structural face.
# The guard keeps a face that merely touches the plane out of the copy -- such a
# face would land coplanar on the back plate.
CUT_GUARD_M = 0.002

DOWN_FACE_NORMAL_Z = -0.5
# Only faces sitting on the floor plane are culled -- see the module docstring.
GROUND_BAND_M = 0.05
# The v007 package ships a handful of zero-area triangles (measured: 24 of 15734).
# Their normal is not a direction at all -- it is whatever the cross product of
# collinear edges normalises to -- so whether they count as "downward" is not stable
# across a save/reload.  Measured: the same geometry yields 1376 above-band downward
# faces in one pass and 1368 in another, a 24-face difference that made the cull
# assertions flaky.  They render nothing either way, so they are excluded from every
# downward-face count (and reported separately) instead of being deleted from the
# art, which would be a silent modification of the source.
DEGENERATE_AREA_M2 = 1e-9
# The aperture probe casts from this height, i.e. mid-opening, well clear of both
# the floor band and the lintel.
APERTURE_PROBE_Z_M = 1.25

BOUNDS_TOLERANCE_M = 0.002
APERTURE_TOLERANCE_M = 0.002
SIDE_TOLERANCE_M = 0.0005
# The two mirror halves are compared through invariants that survive float32 noise:
# a bit-exact vertex-position multiset, plus this relative bound on the vector-area
# difference (the winding check).  Float32 summation noise is ~1e-6 relative; a
# mirrored half with the winding not flipped differs by 200%.
MIRROR_AREA_REL_TOL = 0.001
# Slack on the above-band downward-face count, which is a threshold classification
# (see the lintel assertion in derive()).
DOWN_FACE_COUNT_TOLERANCE = 4

SCRIPT_DIR = Path(__file__).resolve().parent
TOWER_DIR = SCRIPT_DIR.parents[1]
PROJECT = SCRIPT_DIR.parents[5]

SOURCE_BLEND = (
    PROJECT
    / "assets/art/environments/tower_zones/battle/source/common_components/v007"
    / "env_battle_common_components_source_v007.blend"
)
OUTPUT_BLEND = SCRIPT_DIR / ("env_tower_wall_door_5m_source_%s.blend" % ASSET_VERSION)
GLB_OUTPUT = TOWER_DIR / "components" / "env_tower_wall_door_5m_top3d.glb"
MANIFEST = SCRIPT_DIR / ("env_tower_wall_door_5m_%s_manifest.json" % ASSET_VERSION)


def rel(path):
    try:
        return str(Path(path).resolve().relative_to(PROJECT))
    except ValueError:
        return str(path)


def open_blend(path):
    if not path.exists():
        raise RuntimeError("Missing blend: %s" % path)
    bpy.ops.wm.open_mainfile(filepath=str(path))
    current = bpy.data.filepath
    if not current or Path(current).resolve() != path.resolve():
        raise RuntimeError("Expected %s to be open, got %s" % (path, current))
    print("OPENED %s" % path)


def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def local_bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    lows = [min(p[i] for p in points) for i in range(3)]
    highs = [max(p[i] for p in points) for i in range(3)]
    return lows, highs


def bounds_report(obj):
    lows, highs = local_bounds(obj)
    return {
        "min": [round(v, 5) for v in lows],
        "max": [round(v, 5) for v in highs],
        "size": [round(highs[i] - lows[i], 5) for i in range(3)],
    }


def count_degenerate_faces(obj):
    return sum(1 for face in obj.data.polygons if face.area <= DEGENERATE_AREA_M2)


def classify_down_faces(obj):
    """Split world-downward faces into floor-band ones and everything above.

    Zero-area faces are skipped: their normal is numerical garbage, not a direction.
    """
    ground = 0
    above = 0
    for face in obj.data.polygons:
        if face.area <= DEGENERATE_AREA_M2:
            continue
        if face.normal.normalized().z >= DOWN_FACE_NORMAL_Z:
            continue
        if abs(face.center.z) <= GROUND_BAND_M:
            ground += 1
        else:
            above += 1
    return ground, above


def remove_ground_down_faces(obj):
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    remove = []
    for face in bm.faces:
        if face.calc_area() <= DEGENERATE_AREA_M2:
            continue
        if face.normal.normalized().z >= DOWN_FACE_NORMAL_Z:
            continue
        if abs(face.calc_center_median().z) <= GROUND_BAND_M:
            remove.append(face)
    if remove:
        bmesh.ops.delete(bm, geom=remove, context="FACES")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return len(remove)


def triangulate(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def cut_plane_y():
    """The plane that separates decoration from structure, in Blender Y."""
    return -(STRUCTURAL_BACK_Y_M + CUT_GUARD_M)


def mirror_decoration(obj):
    """Mirror only the decoration onto the +Y side, in place.

    Returns (decorated_faces, structural_faces, mirrored_faces_added).

    The partition is done by deleting faces on both sides of a copied mesh rather
    than by bisecting: bisecting would cut triangles at the plane and leave slivers
    that are neither decoration nor structure.  Whole-face partitioning is exact and
    keeps every UV and material index untouched.
    """
    mesh = obj.data
    cut = cut_plane_y()

    decor = bpy.data.objects.new("DERIVED_decor_%s" % ASSET_VERSION, mesh.copy())
    bpy.context.scene.collection.objects.link(decor)
    decor.matrix_world = obj.matrix_world.copy()

    decor_bm = bmesh.new()
    decor_bm.from_mesh(decor.data)
    dropped_from_decor = [
        face for face in decor_bm.faces if max(v.co.y for v in face.verts) > cut
    ]
    bmesh.ops.delete(decor_bm, geom=dropped_from_decor, context="FACES")
    decor_bm.to_mesh(decor.data)
    decor_bm.free()
    decor.data.update()
    decor_faces = len(decor.data.polygons)

    main_bm = bmesh.new()
    main_bm.from_mesh(mesh)
    dropped_from_main = [
        face for face in main_bm.faces if max(v.co.y for v in face.verts) <= cut
    ]
    bmesh.ops.delete(main_bm, geom=dropped_from_main, context="FACES")
    main_bm.to_mesh(mesh)
    main_bm.free()
    mesh.update()
    structural_faces = len(mesh.polygons)

    # Mirror modifier rather than a hand-rolled bmesh negation: the modifier flips
    # the winding of the mirrored half itself, so the copy comes out facing outward
    # instead of inward (an inward-facing back would simply be invisible in Godot).
    # `use_mirror_merge` stays off -- there is nothing to weld at y = 0, and welding
    # would collapse the copied shell onto the reference plane.
    activate(decor)
    modifier = decor.modifiers.new(name="decor_mirror", type="MIRROR")
    modifier.use_axis = (False, True, False)
    modifier.use_mirror_merge = False
    modifier.use_clip = False
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    mirrored_faces = len(decor.data.polygons) - decor_faces

    activate(obj)
    decor.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.join()
    return decor_faces, structural_faces, mirrored_faces


def face_side(obj, face):
    """+1 when the face lies wholly on the mirrored side, -1 on the original side.

    0 means the face spans the cut (the door tunnel and the back shell do), which is
    exactly the set the mirror must leave alone.
    """
    cut = cut_plane_y()
    ys = [obj.data.vertices[i].co.y for i in face.vertices]
    if min(ys) >= -cut - SIDE_TOLERANCE_M:
        return 1
    if max(ys) <= cut + SIDE_TOLERANCE_M:
        return -1
    return 0


def face_side_counts(obj):
    minus = 0
    plus = 0
    for face in obj.data.polygons:
        side = face_side(obj, face)
        if side > 0:
            plus += 1
        elif side < 0:
            minus += 1
    return minus, plus


def _face_position_key(mesh, face):
    """Bit-stable per-face key: the face's vertex positions as the mirror stores them.

    Vertex coordinates are bit-exact between a face and its mirrored twin -- the
    mirror only negates Y and copies X/Z through -- so this key needs no tolerance.
    A face centroid or normal is recomputed from the vertices and therefore lands up
    to one ulp away, which is exactly what makes them useless for this comparison.
    """
    return tuple(
        sorted(
            (
                round(mesh.vertices[i].co.x, 4),
                round(abs(mesh.vertices[i].co.y), 4),
                round(mesh.vertices[i].co.z, 4),
            )
            for i in face.vertices
        )
    )


def mirror_symmetry(obj):
    """Prove the +Y half is the exact mirror of the -Y half.

    Returns (differing_position_keys, vector_area_relative_delta, sample).

    Two independent invariants, both immune to the float32 noise that a
    centroid-based comparison drowns in.  Measured on a correct mirror: 39 of 7799
    centroids flip their 5th decimal, which shifts a sorted pairwise zip and makes it
    report 911 phantom mismatches whose Z differs by metres; and a tolerance-based
    greedy match still reports 29 phantom mismatches, because tolerance matching is
    not transitive (each of those rows had an identical twin in the other half).

      * the multiset of per-face vertex-position keys must be identical -- an exact
        statement, since a mirrored vertex is a bit-exact negation in Y;
      * the mirrored half's vector area (sum of area-weighted normals) must equal the
        reflection of the original half's.  This is the invariant that catches a
        mirrored half written WITHOUT the winding flip: its normals would point into
        the wall, the vector area would come out negated, and every back face would
        be invisible in Godot.
    """
    mesh = obj.data
    minus_keys = Counter()
    plus_keys = Counter()
    minus_area = Vector((0.0, 0.0, 0.0))
    plus_area = Vector((0.0, 0.0, 0.0))
    for face in mesh.polygons:
        side = face_side(obj, face)
        if side == 0:
            continue
        key = _face_position_key(mesh, face)
        verts = [mesh.vertices[i].co for i in face.vertices]
        if side > 0:
            plus_keys[key] += 1
        else:
            minus_keys[key] += 1
        if len(verts) >= 3:
            area_vector = (verts[1] - verts[0]).cross(verts[2] - verts[0]) * 0.5
            if side > 0:
                plus_area += area_vector
            else:
                minus_area += area_vector

    differing = sum((minus_keys - plus_keys).values()) + sum((plus_keys - minus_keys).values())
    sample = None
    if differing:
        sample = {
            "original_only": [list(k) for k in list(minus_keys - plus_keys)[:2]],
            "mirrored_only": [list(k) for k in list(plus_keys - minus_keys)[:2]],
        }

    mirrored_minus_area = Vector((minus_area.x, -minus_area.y, minus_area.z))
    scale = max(plus_area.length, mirrored_minus_area.length, 1e-6)
    delta = (plus_area - mirrored_minus_area).length / scale
    return differing, delta, sample


def coincident_cross_side_pairs(obj):
    """Count coplanar twin faces whose members sit on OPPOSITE sides of the cut.

    The source package already ships "thin plate rendered from both sides" pairs, so
    the absolute twin count is not zero and never was.  What must stay zero is twins
    that pair a mirrored face with a kept face: that is the coplanar overlap the cut
    exists to prevent, and it is the only way this mirror can flicker.
    """
    verts = obj.data.vertices
    groups = {}
    for face in obj.data.polygons:
        key = frozenset(
            tuple(round(v, 4) for v in verts[i].co) for i in face.vertices
        )
        groups.setdefault(key, []).append(face.index)
    twins = [indexes for indexes in groups.values() if len(indexes) > 1]
    cross = []
    for indexes in twins:
        sides = set()
        for index in indexes:
            side = face_side(obj, obj.data.polygons[index])
            if side != 0:
                sides.add(side)
        if len(sides) > 1:
            cross.append(indexes)
    return len(twins), cross


def measure_aperture(obj):
    """Cast rays out of the door opening's own volume to measure the real clearance.

    Returns the signed half-widths and the lintel underside height.  Reading the
    geometry with rays (instead of trusting the source's declared bounds) is the
    whole point: a decoration that reaches into the opening shows up here as a
    half-width below 1.1 or a lintel below 2.5, even though the wall's outer
    envelope still looks correct.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    tree = BVHTree.FromBMesh(bm)
    origin = Vector((0.0, 0.0, APERTURE_PROBE_Z_M))
    report = {}
    directions = {
        "plus_x": Vector((1.0, 0.0, 0.0)),
        "minus_x": Vector((-1.0, 0.0, 0.0)),
        "plus_z": Vector((0.0, 0.0, 1.0)),
        "minus_z": Vector((0.0, 0.0, -1.0)),
        # New in v005: the wall now carries decoration on the far side of the
        # opening as well, so the opening has to be proven clear end to end.
        "plus_y": Vector((0.0, 1.0, 0.0)),
        "minus_y": Vector((0.0, -1.0, 0.0)),
    }
    for name, direction in directions.items():
        # BVHTree.ray_cast returns (location, normal, index, distance); every field
        # is None on a miss.  Unpacking it as (hit, location, ...) silently yields
        # the surface NORMAL where the hit point is expected.
        location, _normal, _index, _distance = tree.ray_cast(origin, direction, 10.0)
        report[name] = [round(v, 5) for v in location] if location is not None else None
    bm.free()

    plus = report["plus_x"]
    minus = report["minus_x"]
    up = report["plus_z"]
    down = report["minus_z"]
    return {
        "origin": [round(v, 5) for v in origin],
        "ray_plus_x": plus,
        "ray_minus_x": minus,
        "ray_plus_z": up,
        "ray_minus_z": down,
        "ray_plus_y": report["plus_y"],
        "ray_minus_y": report["minus_y"],
        "clear_width_m": round(plus[0] - minus[0], 5) if plus and minus else None,
        "clear_height_m": round(up[2], 5) if up else None,
        "floor_hit_z_m": round(down[2], 5) if down else None,
        "clear_through_thickness": report["plus_y"] is None and report["minus_y"] is None,
    }


def aperture_problems(aperture):
    problems = []
    if aperture["clear_width_m"] is None:
        problems.append("could not measure the door opening width")
    elif abs(aperture["clear_width_m"] - DOOR_CLEAR_WIDTH_M) > APERTURE_TOLERANCE_M:
        problems.append(
            "clear width %.5f, expected %.2f" % (aperture["clear_width_m"], DOOR_CLEAR_WIDTH_M)
        )
    if aperture["clear_height_m"] is None:
        problems.append("could not measure the door opening height")
    elif abs(aperture["clear_height_m"] - DOOR_CLEAR_HEIGHT_M) > APERTURE_TOLERANCE_M:
        problems.append(
            "clear height %.5f, expected %.2f" % (aperture["clear_height_m"], DOOR_CLEAR_HEIGHT_M)
        )
    if not aperture["clear_through_thickness"]:
        problems.append(
            "the opening is blocked along the thickness axis (ray +Y hit %s, ray -Y hit %s); "
            "a mirrored face is closing the doorway"
            % (aperture["ray_plus_y"], aperture["ray_minus_y"])
        )
    return problems


def derive():
    open_blend(SOURCE_BLEND)

    package = bpy.data.collections.get(SOURCE_PACKAGE)
    if package is None:
        raise RuntimeError("Missing collection %s" % SOURCE_PACKAGE)

    root = bpy.data.objects.get(SOURCE_COMPONENT)
    if root is None or root.type != "EMPTY":
        raise RuntimeError("Missing ROOT empty %s" % SOURCE_COMPONENT)
    root_location = root.matrix_world.translation.copy()
    print("SOURCE ROOT world = (%.6f, %.6f, %.6f)" % tuple(root_location))
    print("SOURCE ROOT props = %s" % dict(root.items()))

    sources = []
    for name in (SOURCE_BODY, SOURCE_EMISSIVE):
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            raise RuntimeError("Missing source mesh %s" % name)
        if not any(collection == package for collection in obj.users_collection):
            raise RuntimeError("%s is not in %s" % (name, SOURCE_PACKAGE))
        sources.append(obj)

    # 180 deg yaw about Blender Z, applied about the ROOT origin, then baked so the
    # exported root node stays identity.
    yaw = Matrix.Rotation(math.pi, 4, "Z")
    recenter = Matrix.Translation(-root_location)
    bake = yaw @ recenter

    export_collection = bpy.data.collections.new("runtime_%s" % ASSET_VERSION)
    bpy.context.scene.collection.children.link(export_collection)

    removed_ground = 0
    down_above_before = 0
    faces_before = 0
    decorated_total = 0
    structural_total = 0
    mirrored_total = 0
    for source in sources:
        clone = source.copy()
        clone.data = source.data.copy()
        clone.animation_data_clear()
        # Object.copy keeps the production parent; drop it or the world transform
        # is evaluated through the original hierarchy a second time in GLB.
        clone.parent = None
        clone.matrix_world = bake @ source.matrix_world
        clone.name = "DERIVED_%s" % source.name
        export_collection.objects.link(clone)

        faces_before += len(clone.data.polygons)
        activate(clone)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        # Triangulate FIRST: an n-gon would otherwise be partitioned as one unit and
        # a decoration n-gon that reaches past the plane would stay whole (see the
        # cull note in the docstring for the same reason).
        triangulate(clone)
        decorated, structural, mirrored = mirror_decoration(clone)
        decorated_total += decorated
        structural_total += structural
        mirrored_total += mirrored
        print(
            "  %s: decorated=%d structural=%d mirrored=%d"
            % (clone.name, decorated, structural, mirrored)
        )
        _ground, above = classify_down_faces(clone)
        down_above_before += above
        removed_ground += remove_ground_down_faces(clone)

    # The mirror has to be exactly 1:1 -- every decoration face gets a twin and
    # nothing else is duplicated.  Checked here, before the cull, so both counts
    # measure the same quantity.
    if mirrored_total != decorated_total:
        raise RuntimeError(
            "mirror step lost faces: decorated=%d mirrored=%d"
            % (decorated_total, mirrored_total)
        )

    # Join with the body active so the material slot order is body roles first,
    # then the emissive role -- deterministic, not dependent on collection order.
    body_clone = None
    for obj in export_collection.objects:
        if SOURCE_BODY in obj.name:
            body_clone = obj
            break
    if body_clone is None:
        raise RuntimeError("Body clone not found in the export collection")
    activate(body_clone)
    for clone in export_collection.objects:
        clone.select_set(True)
    bpy.context.view_layer.objects.active = body_clone
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    merged.name = NODE_NAME
    merged.data.name = MESH_NAME

    # Drop material slots that carry no face.  This package uses all four roles, so
    # nothing is expected to drop -- the loop stays as a guard, and the report says
    # what actually happened.
    dropped_slots = []
    used = {poly.material_index for poly in merged.data.polygons}
    for index in reversed(range(len(merged.material_slots))):
        if index not in used:
            dropped_slots.append(merged.material_slots[index].material.name)
            activate(merged)
            merged.active_material_index = index
            bpy.ops.object.material_slot_remove()

    # The lintel underside must have survived the cull.  If the cull ever widens
    # back to a blanket one, this is the assertion that fails -- it would drop the
    # whole count (~1367 faces per half), not a couple of faces.
    #
    # The tolerance is deliberate: this count is a threshold classification over
    # thousands of faces, so a face whose normal sits within float noise of the
    # 60 deg cut can flip during the bmesh round-trip (measured: two passes over the
    # same source report 1367 and 1368 above-band downward faces per half).  The
    # lintel's actual presence is proven exactly, not statistically, by the aperture
    # probe: `clear_height_m == 2.5` can only be measured if a surface is there.
    _ground_after, above_after = classify_down_faces(merged)
    if abs(above_after - down_above_before) > DOWN_FACE_COUNT_TOLERANCE:
        raise RuntimeError(
            "lintel underside was culled: %d downward faces above the floor band "
            "before the cull, %d after" % (down_above_before, above_after)
        )

    aperture = measure_aperture(merged)
    print("APERTURE before export %s" % json.dumps(aperture, ensure_ascii=False))
    problems = aperture_problems(aperture)

    minus_faces, plus_faces = face_side_counts(merged)
    # The cull removes floor-band faces from both halves alike, so the invariant to
    # check here is symmetry between the halves, not a match against the pre-cull
    # `decorated_total` (which counts 84 more faces fore-side than survive).
    if minus_faces == 0 or plus_faces == 0:
        problems.append(
            "decoration missing on one side (original=%d mirrored=%d)" % (minus_faces, plus_faces)
        )
    elif minus_faces != plus_faces:
        problems.append(
            "decoration is not symmetric after the cull: original=%d mirrored=%d"
            % (minus_faces, plus_faces)
        )
    mismatches, area_delta, sample = mirror_symmetry(merged)
    if mismatches:
        problems.append(
            "the mirrored half is not an exact mirror: %d face position keys differ "
            "(e.g. %s)" % (mismatches, sample)
        )
    if area_delta > MIRROR_AREA_REL_TOL:
        problems.append(
            "the mirrored half's winding is wrong: its vector area differs from the "
            "mirrored original by %.4f relative (normals point into the wall and the "
            "back faces render invisible)" % area_delta
        )
    twin_groups, cross_twins = coincident_cross_side_pairs(merged)
    if cross_twins:
        problems.append(
            "%d coplanar twin face groups straddle the cut (e.g. %s): the mirror "
            "overlaps kept geometry and the wall will z-fight"
            % (len(cross_twins), cross_twins[0])
        )

    lows, highs = local_bounds(merged)
    if abs((highs[0] - lows[0]) - GRID_UNIT_M) > BOUNDS_TOLERANCE_M:
        problems.append("grid width %.5f, expected %.2f" % (highs[0] - lows[0], GRID_UNIT_M))
    if abs(lows[0] + highs[0]) > BOUNDS_TOLERANCE_M:
        problems.append("not centred on X: [%.5f, %.5f]" % (lows[0], highs[0]))
    if abs(lows[2]) > BOUNDS_TOLERANCE_M:
        problems.append("bottom not on Y=0 in Blender Z: %.5f" % lows[2])
    if abs(lows[1] + DECOR_DEPTH_M) > BOUNDS_TOLERANCE_M:
        problems.append(
            "decoration front face Y = %.5f, expected %.5f (the original side moved, "
            "so the 180 deg bake is off)" % (lows[1], -DECOR_DEPTH_M)
        )
    if abs(highs[1] - DECOR_DEPTH_M) > BOUNDS_TOLERANCE_M:
        problems.append(
            "mirrored decoration Y = %.5f, expected %.5f (double-siding lost)"
            % (highs[1], DECOR_DEPTH_M)
        )
    if abs(lows[1] + highs[1]) > BOUNDS_TOLERANCE_M:
        problems.append(
            "thickness is not symmetric about the reference plane: [%.5f, %.5f]"
            % (lows[1], highs[1])
        )
    if problems:
        raise RuntimeError("DOOR_V005_DERIVE_CONTRACT_FAILED: " + " | ".join(problems))

    # Provenance and post-derivation truth.  `front_axis_blender` is corrected
    # because the source declaration ("+Y") is no longer true after the yaw; the
    # double-sided revision keeps +Z as the declared forward axis (that is the side
    # the room sees and what verify_tower_module_prefabs.gd requires) and records
    # the mirror separately.
    merged["asset_id"] = ASSET_ID
    merged["asset_version"] = ASSET_VERSION
    merged["visual_only"] = True
    merged["origin_contract"] = "bottom_center"
    merged["front_axis_blender"] = "-Y"
    merged["front_axis_godot"] = "+Z"
    merged["double_sided"] = True
    merged["mirror_axis_godot"] = "-Z"
    merged["mirror_plane_y_m"] = MIRROR_PLANE_Y_M
    merged["decor_depth_m"] = DECOR_DEPTH_M
    merged["collision_owner"] = "DungeonRoom3D"
    merged["door_clear_width_m"] = DOOR_CLEAR_WIDTH_M
    merged["door_clear_height_m"] = DOOR_CLEAR_HEIGHT_M
    merged["derived_from_blend"] = rel(SOURCE_BLEND)
    merged["derived_from_component"] = SOURCE_COMPONENT
    merged["derived_from_package"] = SOURCE_PACKAGE
    merged["source_component_asset_version"] = str(
        bpy.data.objects[SOURCE_BODY].get("asset_version", "")
    )
    merged["supersedes"] = "v004 single-sided door wall (same v007 package)"
    merged["replaced_legacy"] = "v003 legacy tower-kit procedural door wall"
    merged["derivation"] = (
        "yaw 180 about Blender Z (decorated face +Y -> -Y so YUP export lands on "
        "Godot +Z); offset baked and ROOT empty dropped; two meshes joined into one; "
        "decoration partitioned at the structural face and mirrored about the "
        "reference plane so both faces read as decor; only floor-plane downward "
        "faces culled (the lintel underside is kept because a player can look up at "
        "it); triangulated."
    )

    # Keep only the export payload so the derived blend cannot be mistaken for a
    # production source and so re-exporting is deterministic.
    for obj in list(bpy.data.objects):
        if obj is not merged:
            bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections):
        if collection != export_collection:
            bpy.data.collections.remove(collection)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    # The batch source carries twelve Scene datablocks (eleven review scenes plus
    # the production one) and the glTF exporter writes ALL of them by default.
    # Godot then loads default scene index 0 -- an empty review scene -- and the
    # model imports as nothing.  Collapse to a single clean scene and drop the
    # batch's scene-level extras, which would otherwise ship policy strings that
    # this derivation deliberately contradicts.
    keep_scene = bpy.context.scene
    scenes_removed = 0
    for scene in list(bpy.data.scenes):
        if scene != keep_scene:
            bpy.data.scenes.remove(scene)
            scenes_removed += 1
    for key in list(keep_scene.keys()):
        del keep_scene[key]
    keep_scene.name = "env_tower_wall_door_5m_%s" % ASSET_VERSION

    uv_layers = [layer.name for layer in merged.data.uv_layers]
    if "PaletteUV" in uv_layers:
        merged.data.uv_layers["PaletteUV"].active_render = True
    merged.data.calc_loop_triangles()

    report = {
        "asset_id": ASSET_ID,
        "asset_version": ASSET_VERSION,
        "node_name": NODE_NAME,
        "double_sided": True,
        "source_blend": rel(SOURCE_BLEND),
        "source_package": SOURCE_PACKAGE,
        "source_component": SOURCE_COMPONENT,
        "source_root_world_translation": [round(v, 6) for v in root_location],
        "baked_yaw_deg": 180,
        "mirror_plane_y_m": MIRROR_PLANE_Y_M,
        "cut_plane_y_m": cut_plane_y(),
        "decorated_faces_per_side": decorated_total,
        "decorated_faces_per_side_after_cull": minus_faces,
        "mirrored_faces_added": mirrored_total,
        "structural_faces_left_untouched": structural_total,
        "mirror_position_key_mismatches": mismatches,
        "mirror_vector_area_relative_delta": round(area_delta, 6),
        "coincident_twin_groups": twin_groups,
        "coincident_cross_side_twin_groups": len(cross_twins),
        "faces_before_optimize": faces_before,
        "downward_faces_above_floor_band_kept": down_above_before,
        "downward_faces_removed_on_floor_band": removed_ground,
        "faces_after_optimize": len(merged.data.polygons),
        "triangles_after_optimize": len(merged.data.loop_triangles),
        "degenerate_zero_area_faces": count_degenerate_faces(merged),
        "door_aperture": aperture,
        "material_roles": [
            slot.material.name for slot in merged.material_slots if slot.material
        ],
        "dropped_empty_material_slots": dropped_slots,
        "scenes_removed": scenes_removed,
        "uv_layers": uv_layers,
        "bounds_blender": bounds_report(merged),
        "derived_blend": rel(OUTPUT_BLEND),
    }

    OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    MANIFEST.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("DOOR_V005_DERIVE_REPORT " + json.dumps(report, ensure_ascii=False))
    print("DERIVE_OK blend=%s" % OUTPUT_BLEND)


def read_glb_json(path):
    """Parse the JSON chunk straight out of the .glb (no importer involved).

    This is the only place that can prove what a consumer will actually see:
    Blender-side state is already gone by the time Godot instantiates the file.
    """
    import struct

    data = path.read_bytes()
    magic, _version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise RuntimeError("Not a GLB: %s" % path)
    offset = 12
    while offset < length:
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8: offset + 8 + chunk_length]
        if chunk_type == 0x4E4F534A:
            return json.loads(chunk.decode("utf-8"))
        offset += 8 + chunk_length + ((4 - chunk_length % 4) % 4 if chunk_length % 4 else 0)
    raise RuntimeError("GLB has no JSON chunk: %s" % path)


def verify_glb():
    gltf = read_glb_json(GLB_OUTPUT)
    problems = []

    scenes = gltf.get("scenes", [])
    if len(scenes) != 1:
        problems.append("expected exactly 1 glTF scene, found %d" % len(scenes))
    default_index = gltf.get("scene", 0)
    if scenes and default_index != 0:
        problems.append("default scene index is %d, expected 0" % default_index)

    nodes = gltf.get("nodes", [])
    if len(nodes) != 1:
        problems.append("expected exactly 1 glTF node, found %d" % len(nodes))
    else:
        node = nodes[0]
        if node.get("name") != NODE_NAME:
            problems.append("node name is %r, expected %r" % (node.get("name"), NODE_NAME))
        for key in ("translation", "rotation", "scale", "matrix"):
            if key in node:
                problems.append(
                    "root node carries %s=%s; the offset must be baked into the "
                    "vertex data" % (key, node[key])
                )
        extras = node.get("extras", {})
        if not extras.get("double_sided"):
            problems.append("root node extras lost double_sided=True")

    meshes = gltf.get("meshes", [])
    if len(meshes) != 1:
        problems.append("expected exactly 1 mesh, found %d" % len(meshes))
    primitives = meshes[0].get("primitives", []) if meshes else []
    if len(primitives) != 4:
        problems.append(
            "expected 4 primitives (4 palette roles), found %d" % len(primitives)
        )

    accessors = gltf.get("accessors", [])
    lows = [None, None, None]
    highs = [None, None, None]
    for primitive in primitives:
        accessor = accessors[primitive["attributes"]["POSITION"]]
        for axis in range(3):
            lows[axis] = accessor["min"][axis] if lows[axis] is None else min(lows[axis], accessor["min"][axis])
            highs[axis] = accessor["max"][axis] if highs[axis] is None else max(highs[axis], accessor["max"][axis])

    # Godot space: bottom_center origin, 11.9m tall, decoration on BOTH +Z and -Z.
    # The structural back plane must still land on -0.15/+0.15 so the wall keeps
    # sharing the grid centreline with the solid wall and the floor tiles.
    expected_min = [-2.5, 0.0, -DECOR_DEPTH_M]
    expected_max = [2.5, 11.9, DECOR_DEPTH_M]
    for axis in range(3):
        if lows[axis] is None or abs(lows[axis] - expected_min[axis]) > BOUNDS_TOLERANCE_M:
            problems.append("godot bounds min axis %d = %s, expected %.4f" % (axis, lows[axis], expected_min[axis]))
        if highs[axis] is None or abs(highs[axis] - expected_max[axis]) > BOUNDS_TOLERANCE_M:
            problems.append("godot bounds max axis %d = %s, expected %.4f" % (axis, highs[axis], expected_max[axis]))
    if highs[2] is not None and highs[2] <= 0.16:
        problems.append(
            "decoration is not on Godot +Z (max Z = %s); the tower A-suite requires "
            "forward_axis +Z" % highs[2]
        )
    if lows[2] is not None and lows[2] >= -0.16:
        problems.append(
            "no decoration on Godot -Z (min Z = %s); the v005 mirror did not survive "
            "the export" % lows[2]
        )

    if gltf.get("images") or gltf.get("textures"):
        problems.append(
            "GLB embeds images/textures; the shared palette must be bound after "
            "import, not baked in"
        )

    if problems:
        raise RuntimeError("DOOR_V005_GLB_VERIFY_FAILED: " + " | ".join(problems))

    size = [round(highs[axis] - lows[axis], 5) for axis in range(3)]
    print(
        "DOOR_V005_GLB_VERIFIED scenes=1 nodes=1 meshes=1 prims=%d "
        "godot_min=%s godot_max=%s godot_size=%s nodes_trs=identity double_sided"
        % (
            len(primitives),
            [round(v, 5) for v in lows],
            [round(v, 5) for v in highs],
            size,
        )
    )


def export():
    open_blend(OUTPUT_BLEND)
    obj = bpy.data.objects.get(NODE_NAME)
    if obj is None or obj.type != "MESH":
        raise RuntimeError("Derived blend is missing %s" % NODE_NAME)

    # Contract assertions.  These are the failures that would otherwise ship
    # silently: a baked-away offset, a leftover floor cap, a second mesh, a
    # decorated face on the wrong axis, a mirror that overlaps kept geometry, or a
    # decoration that reached into the door opening after all.
    problems = []
    mesh_objects = [item for item in bpy.data.objects if item.type == "MESH"]
    if len(mesh_objects) != 1:
        problems.append("expected exactly 1 mesh object, found %d" % len(mesh_objects))
    if obj.matrix_world != Matrix.Identity(4):
        problems.append("root transform is not identity: %s" % obj.matrix_world)

    ground_down = 0
    above_down = 0
    for face in obj.data.polygons:
        # Zero-area faces carry no direction; counting them here would make this
        # assertion depend on how a degenerate normal happened to normalise.
        if face.area <= DEGENERATE_AREA_M2:
            continue
        if face.normal.normalized().z >= DOWN_FACE_NORMAL_Z:
            continue
        if abs(face.center.z) <= GROUND_BAND_M:
            ground_down += 1
        else:
            above_down += 1
    if ground_down != 0:
        problems.append("%d floor-plane downward faces survived the cull" % ground_down)
    if above_down == 0:
        problems.append(
            "no downward faces above the floor band: the lintel underside is gone"
        )

    if [layer.name for layer in obj.data.uv_layers] != ["PaletteUV"]:
        problems.append("unexpected UV layers: %s" % [l.name for l in obj.data.uv_layers])

    lows, highs = local_bounds(obj)
    if abs(lows[0] + 2.5) > BOUNDS_TOLERANCE_M or abs(highs[0] - 2.5) > BOUNDS_TOLERANCE_M:
        problems.append("grid width not centred on X: [%.5f, %.5f]" % (lows[0], highs[0]))
    if abs(lows[2]) > BOUNDS_TOLERANCE_M or abs(highs[2] - 11.9) > BOUNDS_TOLERANCE_M:
        problems.append("height not on Blender Z [0, 11.9]: [%.5f, %.5f]" % (lows[2], highs[2]))
    # Both decorated faces must be present at equal depth; the structural back plane
    # is what used to sit at +0.15 and is now buried behind the mirrored decor.
    if abs(lows[1] + DECOR_DEPTH_M) > BOUNDS_TOLERANCE_M:
        problems.append(
            "decoration front face Y = %.5f, expected %.5f" % (lows[1], -DECOR_DEPTH_M)
        )
    if abs(highs[1] - DECOR_DEPTH_M) > BOUNDS_TOLERANCE_M:
        problems.append(
            "mirrored decoration Y = %.5f, expected %.5f (double-siding lost)"
            % (highs[1], DECOR_DEPTH_M)
        )
    if abs(lows[1] + highs[1]) > BOUNDS_TOLERANCE_M:
        problems.append(
            "thickness is not symmetric about the reference plane: [%.5f, %.5f]"
            % (lows[1], highs[1])
        )

    minus_faces, plus_faces = face_side_counts(obj)
    if minus_faces == 0 or plus_faces == 0:
        problems.append(
            "decoration missing on one side (original=%d mirrored=%d)" % (minus_faces, plus_faces)
        )
    elif minus_faces != plus_faces:
        problems.append(
            "decoration is not symmetric: original=%d mirrored=%d" % (minus_faces, plus_faces)
        )
    mismatches, area_delta, _sample = mirror_symmetry(obj)
    if mismatches:
        problems.append(
            "the mirrored half is not an exact mirror: %d face position keys differ"
            % mismatches
        )
    if area_delta > MIRROR_AREA_REL_TOL:
        problems.append(
            "the mirrored half's winding is wrong: vector area differs by %.4f relative"
            % area_delta
        )
    twin_groups, cross_twins = coincident_cross_side_pairs(obj)
    if cross_twins:
        problems.append(
            "%d coplanar twin groups straddle the cut (e.g. %s); the mirror would z-fight"
            % (len(cross_twins), cross_twins[0])
        )

    aperture = measure_aperture(obj)
    problems.extend(aperture_problems(aperture))

    if problems:
        raise RuntimeError("DOOR_V005_EXPORT_CONTRACT_FAILED: " + " | ".join(problems))

    GLB_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    activate(obj)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUTPUT),
        export_format="GLB",
        use_selection=True,
        use_active_scene=True,
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    verify_glb()

    # Godot-space prediction, Blender (x, y, z) -> Godot (x, z, -y).
    lows, highs = local_bounds(obj)
    godot_size = [highs[0] - lows[0], highs[2] - lows[2], highs[1] - lows[1]]
    godot_min = [lows[0], lows[2], -highs[1]]
    godot_max = [highs[0], highs[2], -lows[1]]
    report = {
        "glb": rel(GLB_OUTPUT),
        "glb_bytes": GLB_OUTPUT.stat().st_size,
        "bounds_godot_predicted_min": [round(v, 5) for v in godot_min],
        "bounds_godot_predicted_max": [round(v, 5) for v in godot_max],
        "bounds_godot_predicted_size": [round(v, 5) for v in godot_size],
        "door_aperture": aperture,
        "decorated_faces_per_side": minus_faces,
        "mirror_position_key_mismatches": mismatches,
        "mirror_vector_area_relative_delta": round(area_delta, 6),
        "coincident_twin_groups": twin_groups,
        "coincident_cross_side_twin_groups": len(cross_twins),
        "material_roles": [
            slot.material.name for slot in obj.material_slots if slot.material
        ],
        "triangles": len(obj.data.loop_triangles),
    }
    print("DOOR_V005_EXPORT_REPORT " + json.dumps(report, ensure_ascii=False))
    print("EXPORT_OK glb=%s" % GLB_OUTPUT)


def main():
    phase = os.environ.get("SS_DOOR_PHASE", "derive").strip().lower()
    if phase == "derive":
        derive()
    elif phase == "export":
        export()
    else:
        raise RuntimeError("Unknown SS_DOOR_PHASE=%s" % phase)


main()
