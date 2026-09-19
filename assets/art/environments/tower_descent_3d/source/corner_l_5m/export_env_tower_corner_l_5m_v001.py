"""Derive the tower A-suite 5m L-corner module (v001) from battle-zone art.

The L corner is *not* authored as a standalone prop: it is two copies of the
already-shipped 5m solid-wall component fitted into an L.  Building it from the
same battle-zone source (rather than from the tower v004 derived blend) keeps a
single upstream truth: if the wall art ever changes, both the straight wall and
the corner are re-derived from the same component and stay identical.

Source (read-only, never modified):
    assets/art/environments/tower_zones/battle/source/common_components/v007/
        env_battle_common_components_source_v007.blend
        -> collection `wall_standard_5m_通用包`
        -> ROOT empty `ROOT_wall_standard_5m_通用组件`
             + mesh `wall_standard_5m_主体_输出`
             + mesh `wall_standard_5m_UI灯光_柔和自发光`
    Two copies of that component are placed into an L; nothing new is modelled.

Derived output (versioned, tower zone owns it):
    assets/art/environments/tower_descent_3d/source/corner_l_5m/
        env_tower_corner_l_5m_source_v001.blend

Runtime output (stable path, overwrite in place, no version in the name):
    assets/art/environments/tower_descent_3d/components/
        env_tower_corner_l_5m_top3d.glb

Placement contract (must match the programmatic prefab it replaces):

    The origin sits at the L's corner, i.e. where the two arms meet.  Arms run
    along Godot +X (long) and Godot -Z (short); the room interior is the CONCAVE
    quadrant BETWEEN them -- Godot +X / -Z, the side `_spawn_room_corner()`
    pushes the arms toward and the side the player walks up to.  That is the
    contract it depends on: it drops the module at the corner point and rotates
    it, so a recentred asset would shift every room corner.

    Both arms present their DECORATED face to that interior side, exactly like a
    straight A-suite wall presents its front (+Z) to the room:

        long arm  = the wall used as a SOUTH wall (yaw 180) -> armor on Godot -Z
        short arm = the wall used as a WEST  wall (yaw  90) -> armor on Godot +X

    (See `_build_corner_aware_wall_run`: direction "south" -> rotation_y PI,
    "west" -> +PI/2, and the wall's +Z front always ends up facing the room.)

    Godot +X arm  : X in [0, 5],   Z in [-0.3175, 0.15]  (armor on Godot -Z)
    Godot -Z arm  : Z in [-5, 0],  X in [-0.15, 0.3175]  (armor on Godot +X)
    Height        : Y in [0, 11.9] for both arms (0.1m top clearance like walls)

Why each transform is needed (measured, not assumed):

  * The source component declares `front_axis_blender="+Y"`: the decorated face
    sits on Blender +Y.  Godot's glTF importer maps Blender (x, y, z) ->
    Godot (x, z, -y), so +Y art lands on Godot -Z.  The tower A-suite requires
    forward_axis "+Z" (verify_tower_module_prefabs.gd EXPECTED_FORWARD_AXIS), so
    a 180 deg yaw about Blender Z is applied first -- identical to the v004 wall.

  * The source ROOT empty sits at world (4.0, -58.344406, 0.0).  Any non-identity
    transform written into the glTF root node would displace the module at every
    call site, so `recenter` removes the ROOT offset and the offset is baked into
    the vertex data (transform_apply); the empty is dropped and the exported root
    node is exactly T=0 R=identity S=1.

  * L placement is expressed in Blender space.  After `bake` the wall module
    occupies Blender X[-2.5, 2.5] (width), Y[-0.3175, 0.15] (thickness, armor on
    -Y) and Z[0, 11.9] (height).  Godot (x, y, z) = Blender (x, z, -y):

        long arm  = Translation(+2.5, 0, 0) @ Rotation(180 deg, Blender Z)
            Rz(180) sends (x, y, z) -> (-x, -y, z).  The width stays on Blender X
            ([-2.5,2.5] -> [0,5] after the +2.5 shift) and the armor normal
            (0,-1,0) -> (0,1,0), i.e. Godot -Z: the room-interior side.  This is
            the same 180 the runtime puts on a tower SOUTH wall.

        short arm = Translation(0, +2.5, 0) @ Rotation(+90 deg, Blender Z)
            Rz(+90) sends (x, y, z) -> (-y, x, z), so the 5m width lands on
            Blender Y (-> Godot -Z after the +2.5 shift: Y[0,5] -> Z[-5,0]), the
            thickness lands on Blender X (Y[-0.3175,0.15] -> X[-0.15,0.3175]) and
            the armor normal (0,-1,0) -> (1,0,0), i.e. Godot +X: also the
            room-interior side.  Same 90 the runtime puts on a WEST wall.

        So each arm is a rigid yaw copy of the shipped wall (180 and 90) and the
        two decorated faces meet at the room's inner corner, at Godot
        (X +0.3175, Z -0.3175) -- the point the player actually walks up to.
        The mirrored short-arm rotation (Rz(-90)) would throw the armor to
        Godot -X, away from the room; `arm_facing` below rejects that too.

  * REVISION 2026-09-19 (still v001, re-derived and re-exported): the long arm
    first shipped with a pure translation -- no yaw -- so it kept the armor on
    Godot +Z, the OUTSIDE of the L, and the face the player sees from inside the
    room was the plain structural back.  Only the long arm was wrong; the short
    arm was already interior-facing.  `arm_facing` now asserts each arm's own
    AABB against the expected interior-facing profile, so a missing/extra yaw
    fails the derive instead of shipping a white-walled corner.

  * All four meshes (2 body/emissive meshes x 2 arms) are joined into ONE mesh
    object: the corner is consumed per instance
    (`runtime_instantiation = per_instance_prefab`) and every other tower module
    ships exactly one mesh.

  * World-space downward faces (normal.z < -0.5) are deleted, matching the v004
    wall precedent, and the cull runs AFTER triangulation on purpose: an n-gon's
    stored normal is the average of its corners, so culling first leaves
    back-facing triangles behind.

    The cull is applied in the SHARED baked frame -- once per source mesh, before
    the arms are placed -- not after placement.  A rotation about Blender Z
    leaves a normal's z component untouched, so the two orders are equivalent in
    exact arithmetic; doing it once keeps both arms identical to the shipped wall
    and to each other.  Measured, culling after placement instead: the long arm
    dropped 1082 body faces and the short arm 1087, against the wall's 1081 --
    10631 triangles instead of 10638, and the two arms disagreed.

  * The -0.5 cut is a knife edge for this art and the export check states so.
    The wall module's 60 deg chamfer faces sit at nz = -0.4999999, 1e-7 above the
    cut, and mesh vertices are stored as float32, so a rigid arm copy rounds a
    couple of dozen of them to about -0.5000007.  The source also ships zero-area
    slivers (measured area ~1e-10, 22 of them in the L) whose normal is
    numerically meaningless -- two read as exactly (0,0,-1).  The exported-mesh
    check therefore fails only on faces that are BOTH beyond a 1e-4 band AND
    larger than 1e-9 m2, and prints the band / degenerate counts so the residual
    is visible rather than hidden.

  * "Identical to two walls" is asserted, not assumed: each arm's own world AABB
    is recorded and compared against the v004 wall module's bounds, the final
    triangle count must be exactly twice the wall's, and `ARM_FACING_GODOT`
    below pins which way each arm's armor points (see REVISION above).

Run:
    SS_CORNER_PHASE=derive  blender --factory-startup --background \
        --python export_env_tower_corner_l_5m_v001.py
    SS_CORNER_PHASE=export  blender --factory-startup --background \
        --python export_env_tower_corner_l_5m_v001.py
"""

import json
import math
import os
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix

ASSET_ID = "ENV-TOWER-CORNER-L-5M"
ASSET_VERSION = "v001"
NODE_NAME = "ENV_TOWER_CORNER_L_5M"
MESH_NAME = "ENV_TOWER_CORNER_L_5M_Mesh"

SOURCE_COMPONENT = "ROOT_wall_standard_5m_通用组件"
SOURCE_PACKAGE = "wall_standard_5m_通用包"
SOURCE_BODY = "wall_standard_5m_主体_输出"
SOURCE_EMISSIVE = "wall_standard_5m_UI灯光_柔和自发光"

MATERIAL_ROLES = [
    "01_精工金属_紫色骨架",
    "02_细腻哑光_青绿大面",
    "04_柔和自发光_UI灯光",
]

DOWN_FACE_NORMAL_Z = -0.5
# The -0.5 cut is a knife edge for this art: the wall module's 60 deg chamfer
# faces sit at nz = -0.4999999, i.e. 1e-7 above the cut.  Mesh vertices are
# stored as float32, so placing a rigid copy rounds those coordinates and nudges
# a couple of dozen of those chamfer faces to -0.5000007.  A second class is
# outright garbage: the source ships zero-area slivers (area ~1e-10) whose
# normal is numerically meaningless -- two of them read as exactly (0,0,-1).
# The contract check therefore ignores faces that are either inside the float32
# boundary band or too small to have a meaningful normal, and still fails hard
# on any face that is genuinely downward.
DOWN_BAND_M = 1e-4
DEGENERATE_FACE_AREA_M2 = 1e-9
ARM_LENGTH_M = 5.0
ARM_SHIFT_M = 2.5
# Out-of-plane profile of the wall art: the armor protrudes ARMOR_FACE_M from the
# module's reference plane, the structural back sits at BACK_FACE_M on the other
# side.  Which one lands on a given Godot axis is what makes an arm's facing
# checkable (see ARM_FACING_GODOT).
ARMOR_FACE_M = 0.3175
BACK_FACE_M = 0.15

# L-corner bounds after derivation, Blender space (x right, y thickness, z up).
# Long arm supplies the X max (its 5m width) and the Y min (its armor at -0.15);
# short arm supplies the X min (-0.15, its structural back) and the Y max (5.0,
# its 5m width).  See ARM_FACING_GODOT for why those two numbers are load-bearing.
BLENDER_MIN = [-0.15, -0.15, 0.0]
BLENDER_MAX = [5.0, 5.0, 11.9]

# Same box predicted in Godot space: (x, y, z) = Blender (x, z, -y).
GODOT_MIN = [-0.15, 0.0, -5.0]
GODOT_MAX = [5.0, 11.9, 0.15]

# Per-arm Godot profile (min_x, min_z, max_x, max_z) -- the orientation lock for
# REVISION 2026-09-19.  The wall art is asymmetric out of plane: the armor face
# protrudes 0.3175 from the module's reference plane and the structural back sits
# at 0.15 on the other side.  An arm's own AABB therefore states which way it
# faces, and a missing or mirrored yaw is caught here instead of in a screenshot.
# The room interior is the concave quadrant between the arms (+X / -Z), so:
#   long arm  (used as a SOUTH wall) must show armor on Godot -Z
#   short arm (used as a WEST  wall) must show armor on Godot +X
ARM_FACING_TOLERANCE_M = 0.001
ARM_FACING_GODOT = {
    "long": (0.0, -0.3175, 5.0, 0.15),
    "short": (-0.15, -5.0, 0.3175, 0.0),
}

SCRIPT_DIR = Path(__file__).resolve().parent
TOWER_DIR = SCRIPT_DIR.parents[1]
PROJECT = SCRIPT_DIR.parents[5]

SOURCE_BLEND = (
    PROJECT
    / "assets/art/environments/tower_zones/battle/source/common_components/v007"
    / "env_battle_common_components_source_v007.blend"
)
OUTPUT_BLEND = SCRIPT_DIR / ("env_tower_corner_l_5m_source_%s.blend" % ASSET_VERSION)
GLB_OUTPUT = TOWER_DIR / "components" / "env_tower_corner_l_5m_top3d.glb"
MANIFEST = SCRIPT_DIR / ("env_tower_corner_l_5m_%s_manifest.json" % ASSET_VERSION)
# Reference manifest of the straight wall this corner is built from.  Used to
# prove the L really is two unmodified wall modules.
WALL_MANIFEST = (
    SCRIPT_DIR.parent
    / "wall_height12"
    / "env_tower_wall_solid_5m_v004_manifest.json"
)


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


def world_down_face_count(obj):
    import mathutils

    rotation = obj.matrix_world.to_3x3()
    total = 0
    for face in obj.data.polygons:
        if (rotation @ mathutils.Vector(face.normal)).normalized().z < DOWN_FACE_NORMAL_Z:
            total += 1
    return total


def remove_downward_faces(obj):
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    rotation = obj.matrix_world.to_3x3()
    remove = [
        face
        for face in bm.faces
        if (rotation @ face.normal).normalized().z < DOWN_FACE_NORMAL_Z
    ]
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


def union_bounds(objects):
    """World-space AABB union across a list of mesh objects."""
    import mathutils

    lows = [None, None, None]
    highs = [None, None, None]
    for obj in objects:
        for corner in obj.bound_box:
            point = obj.matrix_world @ mathutils.Vector(corner)
            for axis in range(3):
                value = point[axis]
                lows[axis] = value if lows[axis] is None else min(lows[axis], value)
                highs[axis] = value if highs[axis] is None else max(highs[axis], value)
    return lows, highs


def bounds_report_from(lows, highs):
    return {
        "min": [round(v, 5) for v in lows],
        "max": [round(v, 5) for v in highs],
        "size": [round(highs[i] - lows[i], 5) for i in range(3)],
    }


def bounds_report(obj):
    lows, highs = union_bounds([obj])
    return bounds_report_from(lows, highs)


def read_wall_reference():
    """The wall this corner must be an exact duplicate of."""
    if not WALL_MANIFEST.exists():
        raise RuntimeError("Missing wall reference manifest: %s" % WALL_MANIFEST)
    data = json.loads(WALL_MANIFEST.read_text(encoding="utf-8"))
    return {
        "asset_version": data.get("asset_version"),
        "triangles": data.get("triangles_after_optimize"),
        "material_roles": data.get("material_roles"),
        "bounds_blender": data.get("bounds_blender"),
    }


def placements():
    """(tag, matrix) for the two arms, in Blender space, applied AFTER bake.

    Both yaws put the arm's armor on the room-interior side (see the module
    docstring and REVISION 2026-09-19); the long arm's 180 is what was missing
    in the first export.
    """
    return [
        (
            "long",
            Matrix.Translation((ARM_SHIFT_M, 0.0, 0.0))
            @ Matrix.Rotation(math.pi, 4, "Z"),
        ),
        (
            "short",
            Matrix.Translation((0.0, ARM_SHIFT_M, 0.0))
            @ Matrix.Rotation(math.pi * 0.5, 4, "Z"),
        ),
    ]


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

    sources = []
    for name in (SOURCE_BODY, SOURCE_EMISSIVE):
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            raise RuntimeError("Missing source mesh %s" % name)
        if not any(collection == package for collection in obj.users_collection):
            raise RuntimeError("%s is not in %s" % (name, SOURCE_PACKAGE))
        sources.append(obj)

    wall_reference = read_wall_reference()
    wall_triangles = wall_reference["triangles"]
    if not wall_triangles:
        raise RuntimeError("Wall reference manifest has no triangle count")

    # 180 deg yaw about Blender Z (so the decorated face lands on Godot +Z, the
    # A-suite front), applied about the ROOT origin, then baked so the exported
    # root is identity.  This is the SHARED wall frame -- identical to the v004
    # wall -- and placements() yaws each arm again to face the room interior.
    yaw = Matrix.Rotation(math.pi, 4, "Z")
    recenter = Matrix.Translation(-root_location)
    bake = yaw @ recenter

    export_collection = bpy.data.collections.new("runtime_%s" % ASSET_VERSION)
    bpy.context.scene.collection.children.link(export_collection)

    # Stage 1 -- optimise the wall component ONCE, with exactly the v004 wall
    # transform (yaw 180 about the ROOT origin, offset baked).  Running the
    # triangulate/cull pass here, BEFORE the arm placements, is what makes both
    # arms byte-identical to the shipped wall and to each other.
    #
    # The cull predicate is "world-space normal z < -0.5".  A rotation about Z
    # leaves a normal's z component untouched, so culling in the baked frame is
    # EQUIVALENT to culling after placement -- except that placing first forces a
    # second transform_apply, whose float rounding perturbs borderline faces.
    # Measured, same source: cull after placement removed 1082 (long arm) and
    # 1087 (short arm) body faces against the wall's 1081, yielding 10631
    # triangles instead of 10638 -- and the two arms disagreed with each other.
    # Culling once in the shared frame removes that nondeterminism entirely.
    removed_down = 0
    faces_before = 0
    triangles_pre_cull = 0
    optimized = []
    for source in sources:
        clone = source.copy()
        clone.data = source.data.copy()
        clone.animation_data_clear()
        # Object.copy keeps the production parent; drop it or the world
        # transform is evaluated through the original hierarchy twice.
        clone.parent = None
        clone.matrix_world = bake @ source.matrix_world
        clone.name = "OPT_%s" % source.name
        export_collection.objects.link(clone)

        faces_before += len(clone.data.polygons)
        activate(clone)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        triangulate(clone)
        triangles_pre_cull += len(clone.data.polygons)
        removed_here = remove_downward_faces(clone)
        removed_down += removed_here
        print(
            "    OPT %s triangulated=%d removed_down=%d kept=%d"
            % (
                source.name,
                len(clone.data.polygons) + removed_here,
                removed_here,
                len(clone.data.polygons),
            )
        )
        optimized.append(clone)

    optimized_triangles = sum(len(item.data.polygons) for item in optimized)
    if optimized_triangles != wall_triangles:
        raise RuntimeError(
            "CORNER_ARM_NOT_WALL: optimised component has %d triangles, wall has %d"
            % (optimized_triangles, wall_triangles)
        )

    # Stage 2 -- drop two rigid, unmodified copies of that optimised component
    # into the L.  Rigid placement cannot change topology, so each arm is exactly
    # one wall module and the L is exactly two walls.
    arm_reports = {}
    for tag, place in placements():
        arm_objects = []
        for base in optimized:
            dup = base.copy()
            dup.data = base.data.copy()
            dup.parent = None
            dup.matrix_world = place @ base.matrix_world
            dup.name = "DERIVED_%s_%s" % (tag, base.name)
            export_collection.objects.link(dup)
            activate(dup)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            arm_objects.append(dup)

        lows, highs = union_bounds(arm_objects)
        arm_reports[tag] = bounds_report_from(lows, highs)
        arm_triangles = sum(len(item.data.polygons) for item in arm_objects)
        print(
            "ARM %s objects=%d triangles=%d size=%s"
            % (tag, len(arm_objects), arm_triangles, arm_reports[tag]["size"])
        )
        if arm_triangles != wall_triangles:
            raise RuntimeError(
                "CORNER_ARM_NOT_WALL: %s arm has %d triangles, wall has %d"
                % (tag, arm_triangles, wall_triangles)
            )

    # "Identical to the shipped wall" -- each arm is one unmodified wall module,
    # so its AABB must be the wall's AABB with the width/thickness axes swapped
    # for the rotated arm.  Size multiset is the yaw/rotation invariant check.
    wall_size = wall_reference["bounds_blender"]["size"]
    for tag, report in arm_reports.items():
        size = sorted(report["size"])
        if any(abs(size[i] - sorted(wall_size)[i]) > 0.001 for i in range(3)):
            raise RuntimeError(
                "CORNER_ARM_NOT_WALL_SHAPED: %s arm size %s != wall size %s"
                % (tag, report["size"], wall_size)
            )

    # Orientation lock (REVISION 2026-09-19): an arm's own out-of-plane AABB says
    # which way it faces, because the armor protrudes 0.3175 and the structural
    # back sits at 0.15.  Both arms must show armor to the room interior; the
    # first export shipped the long arm armor-outward and looked like a plain
    # white wall from inside the room.
    for tag, expected in ARM_FACING_GODOT.items():
        report = arm_reports[tag]
        got = tuple(
            value + 0.0  # normalise -0.0 so the log has no "-0.0000"
            for value in (
                report["min"][0],
                -report["max"][1],
                report["max"][0],
                -report["min"][1],
            )
        )
        if any(abs(got[i] - expected[i]) > ARM_FACING_TOLERANCE_M for i in range(4)):
            raise RuntimeError(
                "CORNER_ARM_FACING_WRONG: %s arm godot profile x[%.4f, %.4f] "
                "z[%.4f, %.4f], expected x[%.4f, %.4f] z[%.4f, %.4f] -- the arm "
                "must present its armor (the 0.3175 protrusion) to the room "
                "interior"
                % (
                    tag,
                    got[0],
                    got[2],
                    got[1],
                    got[3],
                    expected[0],
                    expected[2],
                    expected[1],
                    expected[3],
                )
            )
        print(
            "ARM %s facing godot x[%.4f, %.4f] z[%.4f, %.4f] OK (armor on %s)"
            % (
                tag,
                got[0],
                got[2],
                got[1],
                got[3],
                "Godot -Z" if tag == "long" else "Godot +X",
            )
        )

    # The optimised originals are scaffolding: only the placed copies ship.
    for base in optimized:
        bpy.data.objects.remove(base, do_unlink=True)

    activate(export_collection.objects[0])
    for clone in list(export_collection.objects):
        clone.select_set(True)
    bpy.context.view_layer.objects.active = export_collection.objects[0]
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    merged.name = NODE_NAME
    merged.data.name = MESH_NAME

    # Every face was triangulated before the join, so polygon count == triangle
    # count here (loop_triangles is only populated after calc_loop_triangles()).
    triangles_after = len(merged.data.polygons)
    if triangles_after != wall_triangles * 2:
        raise RuntimeError(
            "CORNER_NOT_TWO_WALLS: L has %d triangles, expected 2 x %d = %d"
            % (triangles_after, wall_triangles, wall_triangles * 2)
        )

    # Drop material slots that carry no face (the source ships
    # 03_清漆反光_紫粉点缀 with 0 polygons).  A surface-less slot cannot survive
    # glTF anyway; removing it here keeps the export honest.
    dropped_slots = []
    used = {poly.material_index for poly in merged.data.polygons}
    for index in reversed(range(len(merged.material_slots))):
        if index not in used:
            dropped_slots.append(merged.material_slots[index].material.name)
            activate(merged)
            merged.active_material_index = index
            bpy.ops.object.material_slot_remove()

    merged["asset_id"] = ASSET_ID
    merged["asset_version"] = ASSET_VERSION
    merged["visual_only"] = False
    merged["origin_contract"] = "bottom_corner"
    merged["front_axis_blender"] = "+Y (long arm) / +X (short arm)"
    merged["front_axis_godot"] = "-Z (long arm) / +X (short arm); both room-interior"
    merged["collision_owner"] = "prp_corner_l_5m.tscn (WallCollisionLong/Short)"
    merged["derived_from_blend"] = rel(SOURCE_BLEND)
    merged["derived_from_component"] = SOURCE_COMPONENT
    merged["derived_from_package"] = SOURCE_PACKAGE
    merged["built_from_arm_count"] = 2
    merged["derivation"] = (
        "two copies of the 5m solid-wall component placed into an L "
        "(long arm = T(+2.5,0,0) @ Rz(180); short arm = T(0,+2.5,0) @ Rz(+90)); "
        "each arm is yawed about Blender Z so its decoration faces the room "
        "interior (armor on Godot -Z for the long arm, +X for the short one); "
        "ROOT offset baked into vertices and the empty dropped; four meshes "
        "joined into one; downward faces (world normal z < -0.5) deleted; "
        "triangulated. REVISION 2026-09-19: the long arm's Rz(180) was missing "
        "in the first export, which left it armor-outward."
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

    # The batch source carries many Scene datablocks and the glTF exporter writes
    # ALL of them by default; Godot then loads default scene index 0 and the
    # model imports as nothing.  Collapse to a single clean scene.
    keep_scene = bpy.context.scene
    scenes_removed = 0
    for scene in list(bpy.data.scenes):
        if scene != keep_scene:
            bpy.data.scenes.remove(scene)
            scenes_removed += 1
    for key in list(keep_scene.keys()):
        del keep_scene[key]
    keep_scene.name = "env_tower_corner_l_5m_%s" % ASSET_VERSION

    uv_layers = [layer.name for layer in merged.data.uv_layers]
    if "PaletteUV" in uv_layers:
        merged.data.uv_layers["PaletteUV"].active_render = True
    merged.data.calc_loop_triangles()

    lows, highs = union_bounds([merged])
    for axis in range(3):
        if abs(lows[axis] - BLENDER_MIN[axis]) > 0.001:
            raise RuntimeError(
                "CORNER_BOUNDS_MIN: axis %d = %.5f, expected %.5f"
                % (axis, lows[axis], BLENDER_MIN[axis])
            )
        if abs(highs[axis] - BLENDER_MAX[axis]) > 0.001:
            raise RuntimeError(
                "CORNER_BOUNDS_MAX: axis %d = %.5f, expected %.5f"
                % (axis, highs[axis], BLENDER_MAX[axis])
            )

    report = {
        "asset_id": ASSET_ID,
        "asset_version": ASSET_VERSION,
        "node_name": NODE_NAME,
        "source_blend": rel(SOURCE_BLEND),
        "source_package": SOURCE_PACKAGE,
        "source_component": SOURCE_COMPONENT,
        "source_root_world_translation": [round(v, 6) for v in root_location],
        "baked_yaw_deg": 180,
        "arm_count": 2,
        "arm_placement_blender": {
            "long": "Translation(+2.5, 0, 0) @ Rotation(+180 deg, Z)",
            "short": "Translation(0, +2.5, 0) @ Rotation(+90 deg, Z)",
        },
        "arm_facing_godot": {
            "long": "armor on Godot -Z (room interior), structural back at +0.15",
            "short": "armor on Godot +X (room interior), structural back at -0.15",
        },
        "arm_bounds_blender": arm_reports,
        "wall_reference": wall_reference,
        "faces_before_optimize": faces_before,
        "triangles_before_cull": triangles_pre_cull,
        "downward_faces_removed": removed_down,
        "faces_after_optimize": len(merged.data.polygons),
        "triangles_after_optimize": len(merged.data.loop_triangles),
        "material_roles": [
            slot.material.name for slot in merged.material_slots if slot.material
        ],
        "dropped_empty_material_slots": dropped_slots,
        "scenes_removed": scenes_removed,
        "uv_layers": uv_layers,
        "bounds_blender": bounds_report(merged),
        "bounds_godot_predicted_min": [round(v, 5) for v in GODOT_MIN],
        "bounds_godot_predicted_max": [round(v, 5) for v in GODOT_MAX],
        "derived_blend": rel(OUTPUT_BLEND),
    }

    OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    MANIFEST.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("CORNER_L_V001_DERIVE_REPORT " + json.dumps(report, ensure_ascii=False))
    print("DERIVE_OK blend=%s" % OUTPUT_BLEND)


def read_glb_json(path):
    """Parse the JSON chunk straight out of the .glb (no importer involved)."""
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
    if gltf.get("scene", 0) != 0:
        problems.append("default scene index is not 0")

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

    meshes = gltf.get("meshes", [])
    if len(meshes) != 1:
        problems.append("expected exactly 1 mesh, found %d" % len(meshes))
    primitives = meshes[0].get("primitives", []) if meshes else []
    if len(primitives) != len(MATERIAL_ROLES):
        problems.append(
            "expected %d primitives (palette roles), found %d"
            % (len(MATERIAL_ROLES), len(primitives))
        )

    accessors = gltf.get("accessors", [])
    lows = [None, None, None]
    highs = [None, None, None]
    for primitive in primitives:
        accessor = accessors[primitive["attributes"]["POSITION"]]
        for axis in range(3):
            lows[axis] = accessor["min"][axis] if lows[axis] is None else min(lows[axis], accessor["min"][axis])
            highs[axis] = accessor["max"][axis] if highs[axis] is None else max(highs[axis], accessor["max"][axis])

    for axis in range(3):
        if lows[axis] is None or abs(lows[axis] - GODOT_MIN[axis]) > 0.001:
            problems.append(
                "godot bounds min axis %d = %s, expected %.4f"
                % (axis, lows[axis], GODOT_MIN[axis])
            )
        if highs[axis] is None or abs(highs[axis] - GODOT_MAX[axis]) > 0.001:
            problems.append(
                "godot bounds max axis %d = %s, expected %.4f"
                % (axis, highs[axis], GODOT_MAX[axis])
            )
    # Every extreme of the union AABB pins one arm, and two of them pin the
    # orientation the 2026-09-19 revision fixed:
    #   max X = +5.0   the long arm reaches its full 5m
    #   min Z = -5.0   the short arm reaches its full 5m
    #   max Z = +0.15  the LONG arm's structural back -- it would read +0.3175
    #                  (the armor) if the long arm still faced outward
    #   min X = -0.15  the SHORT arm's structural back -- would read -0.3175 if
    #                  that arm were mirrored
    # So the two extremes together assert "armor on the room-interior side"
    # (-Z / +X) on the GLB itself, not just in the derive-time arm reports.
    if highs[0] is None or abs(highs[0] - ARM_LENGTH_M) > 0.001:
        problems.append(
            "long arm does not reach Godot X=%.2f (max X = %s)" % (ARM_LENGTH_M, highs[0])
        )
    if lows[2] is None or abs(lows[2] + ARM_LENGTH_M) > 0.001:
        problems.append(
            "short arm does not reach Godot Z=-%.2f (min Z = %s)" % (ARM_LENGTH_M, lows[2])
        )
    if highs[2] is None or abs(highs[2] - BACK_FACE_M) > 0.001:
        problems.append(
            "long arm does not present its structural back on Godot +Z "
            "(max Z = %s, expected %.4f): the armor must face the room interior "
            "(-Z), so the far side is the thin one" % (highs[2], BACK_FACE_M)
        )
    if lows[0] is None or abs(lows[0] + BACK_FACE_M) > 0.001:
        problems.append(
            "short arm does not present its structural back on Godot -X "
            "(min X = %s, expected %.4f): the armor must face the room interior "
            "(+X)" % (lows[0], -BACK_FACE_M)
        )
    print(
        "    orientation: armor on -Z (long) / +X (short), back faces at Z=+%.4f / X=-%.4f"
        % (BACK_FACE_M, BACK_FACE_M)
    )

    if gltf.get("images") or gltf.get("textures"):
        problems.append(
            "GLB embeds images/textures; the shared palette must be bound after "
            "import, not baked in"
        )

    if problems:
        raise RuntimeError("CORNER_L_V001_GLB_VERIFY_FAILED: " + " | ".join(problems))

    size = [round(highs[axis] - lows[axis], 5) for axis in range(3)]
    print(
        "CORNER_L_V001_GLB_VERIFIED scenes=1 nodes=1 meshes=1 prims=%d "
        "godot_min=%s godot_max=%s godot_size=%s nodes_trs=identity"
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

    wall_reference = read_wall_reference()

    problems = []
    mesh_objects = [item for item in bpy.data.objects if item.type == "MESH"]
    if len(mesh_objects) != 1:
        problems.append("expected exactly 1 mesh object, found %d" % len(mesh_objects))
    if obj.matrix_world != Matrix.Identity(4):
        problems.append("root transform is not identity: %s" % obj.matrix_world)
    # Band-aware downward check -- see DOWN_BAND_M / DEGENERATE_FACE_AREA_M2.
    below_cut = [
        (face.normal.z, face.area)
        for face in obj.data.polygons
        if face.normal.z < DOWN_FACE_NORMAL_Z
    ]
    hard_down = [
        nz
        for nz, area in below_cut
        if nz < DOWN_FACE_NORMAL_Z - DOWN_BAND_M and area > DEGENERATE_FACE_AREA_M2
    ]
    if hard_down:
        problems.append(
            "%d genuinely downward faces survived the cull (worst nz=%.6f)"
            % (len(hard_down), min(hard_down))
        )
    print(
        "    downward: below_cut=%d hard=%d band=%.0e degenerate_band=%d"
        % (
            len(below_cut),
            len(hard_down),
            DOWN_BAND_M,
            len([1 for nz, area in below_cut if area <= DEGENERATE_FACE_AREA_M2]),
        )
    )
    if [layer.name for layer in obj.data.uv_layers] != ["PaletteUV"]:
        problems.append("unexpected UV layers: %s" % [l.name for l in obj.data.uv_layers])
    roles = sorted(slot.material.name for slot in obj.material_slots if slot.material)
    if roles != sorted(MATERIAL_ROLES):
        problems.append("unexpected material roles: %s" % roles)
    triangles = len(obj.data.loop_triangles)
    if triangles != wall_reference["triangles"] * 2:
        problems.append(
            "triangle count %d != 2 x wall (%d)"
            % (triangles, wall_reference["triangles"] * 2)
        )

    lows, highs = union_bounds([obj])
    for axis, (got, want) in enumerate(zip(lows, BLENDER_MIN)):
        if abs(got - want) > 0.001:
            problems.append("bounds min axis %d = %.5f, expected %.5f" % (axis, got, want))
    for axis, (got, want) in enumerate(zip(highs, BLENDER_MAX)):
        if abs(got - want) > 0.001:
            problems.append("bounds max axis %d = %.5f, expected %.5f" % (axis, got, want))

    if problems:
        raise RuntimeError("CORNER_L_V001_EXPORT_CONTRACT_FAILED: " + " | ".join(problems))

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

    lows, highs = union_bounds([obj])
    godot_size = [highs[0] - lows[0], highs[2] - lows[2], highs[1] - lows[1]]
    report = {
        "glb": rel(GLB_OUTPUT),
        "bounds_godot_predicted_min": [lows[0], lows[2], -highs[1]],
        "bounds_godot_predicted_max": [highs[0], highs[2], -lows[1]],
        "bounds_godot_predicted_size": godot_size,
        "material_roles": [
            slot.material.name for slot in obj.material_slots if slot.material
        ],
        "triangles": triangles,
    }
    print("CORNER_L_V001_EXPORT_REPORT " + json.dumps(report, ensure_ascii=False))
    print("EXPORT_OK glb=%s" % GLB_OUTPUT)


def main():
    phase = os.environ.get("SS_CORNER_PHASE", "derive").strip().lower()
    if phase == "derive":
        derive()
    elif phase == "export":
        export()
    else:
        raise RuntimeError("Unknown SS_CORNER_PHASE=%s" % phase)


main()
