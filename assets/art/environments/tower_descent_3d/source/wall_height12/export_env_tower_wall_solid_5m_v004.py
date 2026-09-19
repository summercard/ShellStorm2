"""Derive the tower A-suite 5m solid-wall module (v004) from battle-zone art.

Source (read-only, never modified):
    assets/art/environments/tower_zones/battle/source/common_components/v007/
        env_battle_common_components_source_v007.blend
        -> collection `wall_standard_5m_通用包`
        -> ROOT empty `ROOT_wall_standard_5m_通用组件`
             + mesh `wall_standard_5m_主体_输出`
             + mesh `wall_standard_5m_UI灯光_柔和自发光`

Derived output (versioned, tower zone owns it):
    assets/art/environments/tower_descent_3d/source/wall_height12/
        env_tower_wall_solid_5m_source_v004.blend

Runtime output (stable path, overwrite in place, no version in the name):
    assets/art/environments/tower_descent_3d/components/
        env_tower_wall_solid_5m_top3d.glb

Why each transform is needed (measured, not assumed):

  * The source component declares `front_axis_blender="+Y"` on both meshes and
    `front_direction="+Y"` on its ROOT empty: the decorated face sits on Blender
    +Y (the flat 4-vertex back plane sits on -Y).  Godot's glTF importer maps
    Blender (x, y, z) -> Godot (x, z, -y), so +Y art lands on Godot -Z.
    The tower A-suite hard-requires forward_axis "+Z"
    (verify_tower_module_prefabs.gd EXPECTED_FORWARD_AXIS).  A 180 deg yaw about
    Blender Z moves the decorated face to -Y -> Godot +Z.  Verified against the
    A-suite door wall, whose frames and SOCKET_INTERACT sit on Godot +Z.

  * The source ROOT empty sits at world (4.0, -58.344406, 0.0).  Godot has a
    second consumer that preloads this GLB *directly* and instantiates the whole
    tree (TowerDescent3D.gd:25 TOWER_WALL_SCENE ->
    _build_stair_approach_corridor), so any non-identity transform written into
    the glTF root node would push corridor wall modules 58m away.  The transform
    is therefore baked into the vertex data (transform_apply) and the empty is
    dropped, so the exported root node is exactly T=0 R=identity S=1.

  * Both meshes are merged into ONE mesh object: the wall is consumed through
    MultiMeshInstance3D (`runtime_instantiation = batched_multimesh`), which only
    ever reads a single Mesh resource.  Scene-level unity is not enough.

  * World-space downward faces (normal.z < -0.5) are deleted, matching the
    project's base-facility precedent (scripts/blender/export_base99_wall_content_v021.py).
    The predicate is yaw-invariant, so it is applied after the rotation.  The cull
    runs AFTER triangulation on purpose: an n-gon's stored normal is the average
    of its corners, so culling first leaves back-facing triangles behind.
    Measured: cull-then-triangulate = 11 hidden triangles survived;
    triangulate-then-cull = 0.

Run:
    SS_WALL_PHASE=derive  blender --factory-startup --background \
        --python export_env_tower_wall_solid_5m_v004.py
    SS_WALL_PHASE=export  blender --factory-startup --background \
        --python export_env_tower_wall_solid_5m_v004.py
"""

import json
import math
import os
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix

ASSET_ID = "ENV-TOWER-WALL-SOLID-5M"
ASSET_VERSION = "v004"
NODE_NAME = "ENV_TOWER_WALL_SOLID_5M"
MESH_NAME = "ENV_TOWER_WALL_SOLID_5M_Mesh"

SOURCE_COMPONENT = "ROOT_wall_standard_5m_通用组件"
SOURCE_PACKAGE = "wall_standard_5m_通用包"
SOURCE_BODY = "wall_standard_5m_主体_输出"
SOURCE_EMISSIVE = "wall_standard_5m_UI灯光_柔和自发光"

DOWN_FACE_NORMAL_Z = -0.5

SCRIPT_DIR = Path(__file__).resolve().parent
TOWER_DIR = SCRIPT_DIR.parents[1]
PROJECT = SCRIPT_DIR.parents[5]

SOURCE_BLEND = (
    PROJECT
    / "assets/art/environments/tower_zones/battle/source/common_components/v007"
    / "env_battle_common_components_source_v007.blend"
)
OUTPUT_BLEND = SCRIPT_DIR / ("env_tower_wall_solid_5m_source_%s.blend" % ASSET_VERSION)
GLB_OUTPUT = TOWER_DIR / "components" / "env_tower_wall_solid_5m_top3d.glb"
MANIFEST = SCRIPT_DIR / ("env_tower_wall_solid_5m_%s_manifest.json" % ASSET_VERSION)


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


def local_bounds(obj):
    import mathutils

    points = [obj.matrix_world @ mathutils.Vector(corner) for corner in obj.bound_box]
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

    # 180 deg yaw about Blender Z, applied about the ROOT origin, then baked so
    # the exported root node stays identity.
    yaw = Matrix.Rotation(math.pi, 4, "Z")
    recenter = Matrix.Translation(-root_location)
    bake = yaw @ recenter

    export_collection = bpy.data.collections.new("runtime_%s" % ASSET_VERSION)
    bpy.context.scene.collection.children.link(export_collection)

    removed_down = 0
    faces_before = 0
    triangles_pre_cull = 0
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
        # Triangulate FIRST, then cull.  An n-gon's stored normal is the average
        # of its corners, so a non-planar face can average above the threshold
        # while its individual triangles fall below it -- culling before
        # triangulation leaves those hidden triangles behind (measured: 11
        # survivors).  Culling triangle normals makes the result exact.
        triangulate(clone)
        triangles_pre_cull += len(clone.data.polygons)
        removed_down += remove_downward_faces(clone)

    activate(export_collection.objects[0])
    for clone in export_collection.objects:
        clone.select_set(True)
    bpy.context.view_layer.objects.active = export_collection.objects[0]
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    merged.name = NODE_NAME
    merged.data.name = MESH_NAME

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

    # Provenance and post-derivation truth.  `front_axis_blender` is corrected
    # because the source declaration ("+Y") is no longer true after the yaw.
    merged["asset_id"] = ASSET_ID
    merged["asset_version"] = ASSET_VERSION
    merged["visual_only"] = True
    merged["origin_contract"] = "bottom_center"
    merged["front_axis_blender"] = "-Y"
    merged["front_axis_godot"] = "+Z"
    merged["collision_owner"] = "DungeonRoom3D"
    merged["derived_from_blend"] = rel(SOURCE_BLEND)
    merged["derived_from_component"] = SOURCE_COMPONENT
    merged["derived_from_package"] = SOURCE_PACKAGE
    merged["source_component_asset_version"] = "v005"
    merged["derivation"] = (
        "yaw 180 about Blender Z (decorated face +Y -> -Y so YUP export lands on "
        "Godot +Z); offset baked and ROOT empty dropped; two meshes joined into one; "
        "downward faces (world normal z < -0.5) deleted; triangulated."
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

    # The batch source carries eleven Scene datablocks (ten empty review scenes
    # plus the production one) and the glTF exporter writes ALL of them by
    # default.  Godot then loads default scene index 0 -- an empty review scene
    # -- and the model imports as nothing.  Collapse to a single clean scene and
    # drop the batch's scene-level extras, which would otherwise ship a policy
    # string ("independent_meshes_no_join") that this derivation deliberately
    # contradicts.
    keep_scene = bpy.context.scene
    scenes_removed = 0
    for scene in list(bpy.data.scenes):
        if scene != keep_scene:
            bpy.data.scenes.remove(scene)
            scenes_removed += 1
    for key in list(keep_scene.keys()):
        del keep_scene[key]
    keep_scene.name = "env_tower_wall_solid_5m_%s" % ASSET_VERSION

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
        "derived_blend": rel(OUTPUT_BLEND),
    }

    OUTPUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    MANIFEST.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("WALL_V004_DERIVE_REPORT " + json.dumps(report, ensure_ascii=False))
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
                    "vertex data (TowerDescent3D preloads this GLB directly)"
                    % (key, node[key])
                )

    meshes = gltf.get("meshes", [])
    if len(meshes) != 1:
        problems.append("expected exactly 1 mesh (batched_multimesh), found %d" % len(meshes))
    primitives = meshes[0].get("primitives", []) if meshes else []
    if len(primitives) != 3:
        problems.append("expected 3 primitives (3 palette roles), found %d" % len(primitives))

    accessors = gltf.get("accessors", [])
    lows = [None, None, None]
    highs = [None, None, None]
    for primitive in primitives:
        accessor = accessors[primitive["attributes"]["POSITION"]]
        for axis in range(3):
            lows[axis] = accessor["min"][axis] if lows[axis] is None else min(lows[axis], accessor["min"][axis])
            highs[axis] = accessor["max"][axis] if highs[axis] is None else max(highs[axis], accessor["max"][axis])

    # Godot space: bottom_center origin, 11.9m tall, decoration on +Z.  Godot Z
    # is the only axis that carries decoration, so an inverted export (the
    # B-suite "-Z" orientation) shows up here as a negative max on Z.
    expected_min = [-2.5, 0.0, -0.15]
    expected_max = [2.5, 11.9, 0.3175]
    for axis in range(3):
        if lows[axis] is None or abs(lows[axis] - expected_min[axis]) > 0.001:
            problems.append("godot bounds min axis %d = %s, expected %.4f" % (axis, lows[axis], expected_min[axis]))
        if highs[axis] is None or abs(highs[axis] - expected_max[axis]) > 0.001:
            problems.append("godot bounds max axis %d = %s, expected %.4f" % (axis, highs[axis], expected_max[axis]))
    if highs[2] is not None and highs[2] <= 0.16:
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
        raise RuntimeError("WALL_V004_GLB_VERIFY_FAILED: " + " | ".join(problems))

    size = [round(highs[axis] - lows[axis], 5) for axis in range(3)]
    print(
        "WALL_V004_GLB_VERIFIED scenes=1 nodes=1 meshes=1 prims=%d "
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
    # silently: a baked-away offset, a leftover downward face, a second mesh the
    # MultiMesh path cannot see, or a decorated face on the wrong axis.
    problems = []
    mesh_objects = [item for item in bpy.data.objects if item.type == "MESH"]
    if len(mesh_objects) != 1:
        problems.append("expected exactly 1 mesh object, found %d" % len(mesh_objects))
    if obj.matrix_world != Matrix.Identity(4):
        problems.append("root transform is not identity: %s" % obj.matrix_world)
    remaining_down = world_down_face_count(obj)
    if remaining_down != 0:
        problems.append("%d downward faces survived the cull" % remaining_down)
    if [layer.name for layer in obj.data.uv_layers] != ["PaletteUV"]:
        problems.append("unexpected UV layers: %s" % [l.name for l in obj.data.uv_layers])
    roles = sorted(slot.material.name for slot in obj.material_slots if slot.material)
    if roles != sorted(["01_精工金属_紫色骨架", "02_细腻哑光_青绿大面", "04_柔和自发光_UI灯光"]):
        problems.append("unexpected material roles: %s" % roles)

    lows, highs = local_bounds(obj)
    expected_min = [-2.5, -0.3175, 0.0]
    expected_max = [2.5, 0.15, 11.9]
    for axis, (got, want) in enumerate(zip(lows, expected_min)):
        if abs(got - want) > 0.001:
            problems.append("bounds min axis %d = %.5f, expected %.5f" % (axis, got, want))
    for axis, (got, want) in enumerate(zip(highs, expected_max)):
        if abs(got - want) > 0.001:
            problems.append("bounds max axis %d = %.5f, expected %.5f" % (axis, got, want))
    # The decorated face must end up on Blender -Y so YUP puts it on Godot +Z.
    # Structure slab is +-0.15; decoration extends past it to about -0.3175.
    if not (lows[1] <= -0.30 and abs(highs[1] - 0.15) <= 0.001):
        problems.append(
            "decoration is not on Blender -Y (thickness axis = %.5f .. %.5f)" % (lows[1], highs[1])
        )

    if problems:
        raise RuntimeError("WALL_V004_EXPORT_CONTRACT_FAILED: " + " | ".join(problems))

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
        "bounds_godot_predicted_min": [round(v, 5) for v in godot_min],
        "bounds_godot_predicted_max": [round(v, 5) for v in godot_max],
        "bounds_godot_predicted_size": [round(v, 5) for v in godot_size],
        "material_roles": [
            slot.material.name for slot in obj.material_slots if slot.material
        ],
        "triangles": len(obj.data.loop_triangles),
    }
    print("WALL_V004_EXPORT_REPORT " + json.dumps(report, ensure_ascii=False))
    print("EXPORT_OK glb=%s" % GLB_OUTPUT)


def main():
    phase = os.environ.get("SS_WALL_PHASE", "derive").strip().lower()
    if phase == "derive":
        derive()
    elif phase == "export":
        export()
    else:
        raise RuntimeError("Unknown SS_WALL_PHASE=%s" % phase)


main()
