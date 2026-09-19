"""Derive the tower A-suite 5m door-wall module (v004) from battle-zone art.

Replaces the legacy tower-kit procedural door wall
(`env_tower_descent_kit_top3d_v007.blend` -> collection `10D_MOD_WALL_DOOR_5M_U01`,
which shipped box-built piers and a lintel with no authored palette, no PaletteUV
and an unbound `.import`), exactly the way the solid wall was replaced in its own
v004 pass.

Source (read-only, never modified):
    assets/art/environments/tower_zones/battle/source/common_components/v007/
        env_battle_common_components_source_v007.blend
        -> collection `wall_door_5m_通用包`
        -> ROOT empty `ROOT_wall_door_5m_通用组件`
             + mesh `wall_door_5m_主体_输出`          (4410 polys, roles 01/02/03)
             + mesh `wall_door_5m_UI灯光_柔和自发光`   (182 polys, role 04)

    v007 is used rather than v006 because v007 carries the package at the world
    origin (measured: ROOT at (0,0,0), body bounds x[-2.5,2.5] y[-0.15,0.3415]
    z[0,11.9]); v006 has the identical geometry but shifted to (8.0,-58.344398,0),
    which would need a recenter the A-suite derivation does not otherwise require.

Derived output (versioned, tower zone owns it):
    assets/art/environments/tower_descent_3d/source/wall_height12/
        env_tower_wall_door_5m_source_v004.blend

Runtime output (stable path, overwrite in place, no version in the name):
    assets/art/environments/tower_descent_3d/components/
        env_tower_wall_door_5m_top3d.glb

Why each transform is needed (measured, not assumed):

  * Both meshes declare `front_axis_blender="+Y"` and the ROOT empty declares
    `front_direction="+Y"`: the decorated face sits on Blender +Y.  Godot's glTF
    importer maps Blender (x, y, z) -> Godot (x, z, -y), so +Y art lands on Godot
    -Z.  The tower A-suite hard-requires forward_axis "+Z"
    (verify_tower_module_prefabs.gd EXPECTED_FORWARD_AXIS), so a 180 deg yaw about
    Blender Z moves the decorated face to -Y -> Godot +Z.  Same correction, same
    reason, as the solid-wall v004 derivation.

  * Offset baked into the vertex data and both meshes joined into ONE mesh object,
    so the exported root node is exactly T=0 R=identity S=1.  The door wall is
    consumed as `per_instance_prefab` (not MultiMesh), so a single mesh is not a
    hard requirement here -- but the identity root is: TowerDescent3D.gd:25
    TOWER_WALL_SCENE preloads the sibling solid GLB directly and instantiates the
    whole tree, and the project's contracts assume the same root convention
    everywhere.

  * Downward faces are culled with a GROUND BAND, unlike the solid wall's blanket
    cull.  This is the one deliberate divergence and it matters: the door wall has
    a lintel whose underside faces straight down at z=2.5 inside the door opening.
    Blanket-culling world-down faces would punch the lintel's underside out and let
    the player see through the wall from below.  Only faces lying on the floor
    plane (|z| <= GROUND_BAND_M) are removed, i.e. the bottom caps that no camera
    can ever see but that the batch source still carries.

  * World-space downward culling runs AFTER triangulation on purpose: an n-gon's
    stored normal is the average of its corners, so culling first leaves
    back-facing triangles behind (measured on the solid wall: cull-then-triangulate
    = 11 survivors, triangulate-then-cull = 0).

Contract assertions this script enforces (all measured on the baked result, never
read back from the source's own metadata):

  * grid width 5.0 exactly, centred on the origin
  * structural back plane lands on Blender +Y = 0.15 with the decoration on -Y,
    which is what puts the decoration on Godot +Z after the YUP export
  * the door opening survives: clear width 2.2 and clear height 2.5, verified by
    ray casting out of the opening's own volume, so a decoration that reaches into
    the aperture is caught rather than assumed away
  * the lintel underside (the only downward-facing surface a player can look up at)
    is still present after the cull
  * one scene, one node, identity root, no embedded images

Run:
    SS_DOOR_PHASE=derive  blender --factory-startup --background \
        --python export_env_tower_wall_door_5m_v004.py
    SS_DOOR_PHASE=export  blender --factory-startup --background \
        --python export_env_tower_wall_door_5m_v004.py
"""

import json
import math
import os
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ASSET_ID = "ENV-TOWER-WALL-DOOR-5M"
ASSET_VERSION = "v004"
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

DOWN_FACE_NORMAL_Z = -0.5
# Only faces sitting on the floor plane are culled -- see the module docstring.
GROUND_BAND_M = 0.05
# The aperture probe casts from this height, i.e. mid-opening, well clear of both
# the floor band and the lintel.
APERTURE_PROBE_Z_M = 1.25

BOUNDS_TOLERANCE_M = 0.002
APERTURE_TOLERANCE_M = 0.002

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


def classify_down_faces(obj):
    """Split world-downward faces into floor-band ones and everything above."""
    ground = 0
    above = 0
    for face in obj.data.polygons:
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
        "clear_width_m": round(plus[0] - minus[0], 5) if plus and minus else None,
        "clear_height_m": round(up[2], 5) if up else None,
        "floor_hit_z_m": round(down[2], 5) if down else None,
    }


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
        # Triangulate FIRST, then cull -- see the module docstring.
        triangulate(clone)
        _ground, above = classify_down_faces(clone)
        down_above_before += above
        removed_ground += remove_ground_down_faces(clone)

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

    # Drop material slots that carry no face.  Unlike the solid wall this package
    # does use all four roles, so nothing is expected to drop -- the loop stays as
    # a guard, and the report says what actually happened.
    dropped_slots = []
    used = {poly.material_index for poly in merged.data.polygons}
    for index in reversed(range(len(merged.material_slots))):
        if index not in used:
            dropped_slots.append(merged.material_slots[index].material.name)
            activate(merged)
            merged.active_material_index = index
            bpy.ops.object.material_slot_remove()

    # The lintel underside must have survived the cull.  If the cull ever widens
    # back to a blanket one, this is the assertion that fails.
    _ground_after, above_after = classify_down_faces(merged)
    if above_after != down_above_before:
        raise RuntimeError(
            "lintel underside was culled: %d downward faces above the floor band "
            "before the cull, %d after" % (down_above_before, above_after)
        )

    aperture = measure_aperture(merged)
    print("APERTURE before export %s" % json.dumps(aperture, ensure_ascii=False))
    aperture_problems = []
    if aperture["clear_width_m"] is None:
        aperture_problems.append("could not measure the door opening width")
    elif abs(aperture["clear_width_m"] - DOOR_CLEAR_WIDTH_M) > APERTURE_TOLERANCE_M:
        aperture_problems.append(
            "clear width %.5f, expected %.2f" % (aperture["clear_width_m"], DOOR_CLEAR_WIDTH_M)
        )
    if aperture["clear_height_m"] is None:
        aperture_problems.append("could not measure the door opening height")
    elif abs(aperture["clear_height_m"] - DOOR_CLEAR_HEIGHT_M) > APERTURE_TOLERANCE_M:
        aperture_problems.append(
            "clear height %.5f, expected %.2f" % (aperture["clear_height_m"], DOOR_CLEAR_HEIGHT_M)
        )
    if aperture_problems:
        raise RuntimeError("DOOR_V004_APERTURE_FAILED: " + " | ".join(aperture_problems))

    lows, highs = local_bounds(merged)
    bounds_problems = []
    if abs((highs[0] - lows[0]) - GRID_UNIT_M) > BOUNDS_TOLERANCE_M:
        bounds_problems.append("grid width %.5f, expected %.2f" % (highs[0] - lows[0], GRID_UNIT_M))
    if abs(lows[0] + highs[0]) > BOUNDS_TOLERANCE_M:
        bounds_problems.append("not centred on X: [%.5f, %.5f]" % (lows[0], highs[0]))
    if abs(lows[2]) > BOUNDS_TOLERANCE_M:
        bounds_problems.append("bottom not on Y=0 in Blender Z: %.5f" % lows[2])
    if abs(highs[1] - STRUCTURAL_BACK_Y_M) > BOUNDS_TOLERANCE_M:
        bounds_problems.append("structural back plane Y = %.5f, expected %.5f" % (highs[1], STRUCTURAL_BACK_Y_M))
    if lows[1] > -0.25:
        bounds_problems.append(
            "decoration is not on Blender -Y (min Y = %.5f); after the yaw the "
            "decorated face must sit on -Y so YUP puts it on Godot +Z" % lows[1]
        )
    if bounds_problems:
        raise RuntimeError("DOOR_V004_DERIVE_CONTRACT_FAILED: " + " | ".join(bounds_problems))

    # Provenance and post-derivation truth.  `front_axis_blender` is corrected
    # because the source declaration ("+Y") is no longer true after the yaw.
    merged["asset_id"] = ASSET_ID
    merged["asset_version"] = ASSET_VERSION
    merged["visual_only"] = True
    merged["origin_contract"] = "bottom_center"
    merged["front_axis_blender"] = "-Y"
    merged["front_axis_godot"] = "+Z"
    merged["collision_owner"] = "DungeonRoom3D"
    merged["door_clear_width_m"] = DOOR_CLEAR_WIDTH_M
    merged["door_clear_height_m"] = DOOR_CLEAR_HEIGHT_M
    merged["derived_from_blend"] = rel(SOURCE_BLEND)
    merged["derived_from_component"] = SOURCE_COMPONENT
    merged["derived_from_package"] = SOURCE_PACKAGE
    merged["source_component_asset_version"] = str(
        bpy.data.objects[SOURCE_BODY].get("asset_version", "")
    )
    merged["supersedes"] = "v003 legacy tower-kit procedural door wall"
    merged["derivation"] = (
        "yaw 180 about Blender Z (decorated face +Y -> -Y so YUP export lands on "
        "Godot +Z); offset baked and ROOT empty dropped; two meshes joined into one; "
        "only floor-plane downward faces culled (the lintel underside is kept "
        "because a player can look up at it); triangulated."
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
        "source_blend": rel(SOURCE_BLEND),
        "source_package": SOURCE_PACKAGE,
        "source_component": SOURCE_COMPONENT,
        "source_root_world_translation": [round(v, 6) for v in root_location],
        "baked_yaw_deg": 180,
        "faces_before_optimize": faces_before,
        "downward_faces_above_floor_band_kept": down_above_before,
        "downward_faces_removed_on_floor_band": removed_ground,
        "faces_after_optimize": len(merged.data.polygons),
        "triangles_after_optimize": len(merged.data.loop_triangles),
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
    print("DOOR_V004_DERIVE_REPORT " + json.dumps(report, ensure_ascii=False))
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

    meshes = gltf.get("meshes", [])
    if len(meshes) != 1:
        problems.append("expected exactly 1 mesh, found %d" % len(meshes))
    primitives = meshes[0].get("primitives", []) if meshes else []

    accessors = gltf.get("accessors", [])
    lows = [None, None, None]
    highs = [None, None, None]
    for primitive in primitives:
        accessor = accessors[primitive["attributes"]["POSITION"]]
        for axis in range(3):
            lows[axis] = accessor["min"][axis] if lows[axis] is None else min(lows[axis], accessor["min"][axis])
            highs[axis] = accessor["max"][axis] if highs[axis] is None else max(highs[axis], accessor["max"][axis])

    # Godot space: bottom_center origin, 11.9m tall, decoration on +Z.  The
    # structural back plane must land on -0.15 so the wall keeps sharing the grid
    # centreline with the solid wall and the floor tiles.
    expected_min = [-2.5, 0.0, -STRUCTURAL_BACK_Y_M]
    expected_max = [2.5, 11.9, None]
    if lows[0] is None or abs(lows[0] - expected_min[0]) > BOUNDS_TOLERANCE_M:
        problems.append("godot bounds min X = %s, expected %.4f" % (lows[0], expected_min[0]))
    if highs[0] is None or abs(highs[0] - expected_max[0]) > BOUNDS_TOLERANCE_M:
        problems.append("godot bounds max X = %s, expected %.4f" % (highs[0], expected_max[0]))
    if lows[1] is None or abs(lows[1] - expected_min[1]) > BOUNDS_TOLERANCE_M:
        problems.append("godot bounds min Y = %s, expected %.4f" % (lows[1], expected_min[1]))
    if highs[1] is None or abs(highs[1] - expected_max[1]) > BOUNDS_TOLERANCE_M:
        problems.append("godot bounds max Y = %s, expected %.4f" % (highs[1], expected_max[1]))
    if lows[2] is None or abs(lows[2] - expected_min[2]) > BOUNDS_TOLERANCE_M:
        problems.append("godot bounds min Z = %s, expected %.4f" % (lows[2], expected_min[2]))
    if highs[2] is None or highs[2] <= 0.16:
        problems.append(
            "decoration is not on Godot +Z (max Z = %s); the tower A-suite requires "
            "forward_axis +Z" % highs[2]
        )

    if gltf.get("images") or gltf.get("textures"):
        problems.append(
            "GLB embeds images/textures; the shared palette must be bound after "
            "import, not baked in"
        )

    if problems:
        raise RuntimeError("DOOR_V004_GLB_VERIFY_FAILED: " + " | ".join(problems))

    size = [round(highs[axis] - lows[axis], 5) for axis in range(3)]
    print(
        "DOOR_V004_GLB_VERIFIED scenes=1 nodes=1 meshes=1 prims=%d "
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

    # Contract assertions.  These are the failures that would otherwise ship
    # silently: a baked-away offset, a leftover floor cap, a second mesh, a
    # decorated face on the wrong axis, or a decoration that reached into the door
    # opening after all.
    problems = []
    mesh_objects = [item for item in bpy.data.objects if item.type == "MESH"]
    if len(mesh_objects) != 1:
        problems.append("expected exactly 1 mesh object, found %d" % len(mesh_objects))
    if obj.matrix_world != Matrix.Identity(4):
        problems.append("root transform is not identity: %s" % obj.matrix_world)

    ground_down = 0
    above_down = 0
    for face in obj.data.polygons:
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
    # The decorated face must end up on Blender -Y so YUP puts it on Godot +Z.
    # Structure slab is +-0.15; decoration extends past it.
    if not (lows[1] <= -0.25 and abs(highs[1] - STRUCTURAL_BACK_Y_M) <= BOUNDS_TOLERANCE_M):
        problems.append(
            "decoration is not on Blender -Y (thickness axis = %.5f .. %.5f)" % (lows[1], highs[1])
        )

    aperture = measure_aperture(obj)
    if aperture["clear_width_m"] is None or abs(aperture["clear_width_m"] - DOOR_CLEAR_WIDTH_M) > APERTURE_TOLERANCE_M:
        problems.append("door clear width = %s, expected %.2f" % (aperture["clear_width_m"], DOOR_CLEAR_WIDTH_M))
    if aperture["clear_height_m"] is None or abs(aperture["clear_height_m"] - DOOR_CLEAR_HEIGHT_M) > APERTURE_TOLERANCE_M:
        problems.append("door clear height = %s, expected %.2f" % (aperture["clear_height_m"], DOOR_CLEAR_HEIGHT_M))

    if problems:
        raise RuntimeError("DOOR_V004_EXPORT_CONTRACT_FAILED: " + " | ".join(problems))

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
        "material_roles": [
            slot.material.name for slot in obj.material_slots if slot.material
        ],
        "triangles": len(obj.data.loop_triangles),
    }
    print("DOOR_V004_EXPORT_REPORT " + json.dumps(report, ensure_ascii=False))
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
