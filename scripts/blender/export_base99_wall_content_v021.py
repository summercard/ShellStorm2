"""Export optimized non-door wall-content packages from the locked V017 layout.

The V017 scene remains untouched.  This script saves a new V021 source, then
exports only non-structural, non-door assets that are mounted on walls.  Every
export is visual-only: structural wall collision continues to be authored by
the base room, preventing decorative meshes from creating air walls.
"""

import bpy
import bmesh
import json
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
SOURCE_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_wall_contents.blend"
RUNTIME_ROOT = PROJECT / "assets/art/environments/base_facility_3d/components/env_base99_wall_contents_v021"
MANIFEST_PATH = PROJECT / "assets/art/environments/base_facility_3d/source/env_base99_wall_contents_v021_manifest.json"

# Explicitly excludes doors, door controls tied to doors, structural wall
# modules, wall panels, wall skins, cabinets and freestanding furniture.
PACKAGE_SLUGS = [
    "loft_backwall_services",
    "loft_tool_pegboard",
    "loft_explore_poster",
    "loft_good_vibes_neon",
    "loft_stay_curious_neon",
    "loft_hanging_plant",
    "base_camp_neon_sign",
    "base_status_terminal",
    "south_wall_pipeline_system",
    "storage_terminal",
    "understair_bulletin_board",
    "understair_lighting_living_support",
    "east_industrial_pipeline_system",
    "east_power_distribution",
    "east_small_safety_devices",
    "east_work_together_poster",
    "south_wall_information_boards",
    "hose_reel",
]


def objects_in_collection(collection):
    result = list(collection.objects)
    for child in collection.children:
        result.extend(objects_in_collection(child))
    return [obj for obj in result if obj.type == "MESH"]


def find_package(slug):
    matches = [c for c in bpy.data.collections if c.get("资产包键") == slug]
    if len(matches) != 1:
        raise RuntimeError("Expected exactly one V017 package collection for %s, found %s" % (slug, len(matches)))
    return matches[0]


def triangle_count(objects):
    return sum(len(obj.data.polygons) for obj in objects if obj.type == "MESH")


def remove_downward_faces(obj):
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    world_rotation = obj.matrix_world.to_3x3()
    remove = []
    for face in bm.faces:
        normal = (world_rotation @ face.normal).normalized()
        if normal.z < -0.5:
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


def decimate_for_top_view(obj):
    """Reduce dense bevel/text tessellation on the runtime copy only."""
    modifier = obj.modifiers.new(name="TopViewRuntimeDecimate", type="DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    # Leave a little more geometry on lettering, which remains readable in the
    # top-down camera, while reducing hidden bevel density everywhere else.
    name = obj.name.upper()
    modifier.ratio = 0.52 if any(token in name for token in ("文字", "TITLE", "GOOD", "VIBES", "WORK", "TOGETHER", "EXPLORE")) else 0.34
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def clone_and_optimize(package, slug, export_dir):
    source_objects = objects_in_collection(package)
    if not source_objects:
        raise RuntimeError("No mesh objects in %s" % slug)

    export_collection = bpy.data.collections.new("runtime_v021_%s" % slug)
    bpy.context.scene.collection.children.link(export_collection)
    clones = []
    removed_faces = 0
    for source in source_objects:
        clone = source.copy()
        clone.data = source.data.copy()
        clone.animation_data_clear()
        # Object.copy retains the production-scene parent.  Disconnect it
        # before linking the export clone, otherwise its world transform is
        # evaluated through the original hierarchy a second time in GLB.
        clone.parent = None
        clone.matrix_world = source.matrix_world.copy()
        clone.name = "V021_%s" % source.name
        export_collection.objects.link(clone)
        clones.append(clone)
        removed_faces += remove_downward_faces(clone)
        triangulate(clone)

    triangles_after_cull = triangle_count(clones)
    for clone in clones:
        decimate_for_top_view(clone)
    bpy.ops.object.select_all(action="DESELECT")
    for clone in clones:
        clone.select_set(True)
    bpy.context.view_layer.objects.active = clones[0]
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    merged.name = "ENV_BASE99_WALL_CONTENT_%s_V021" % slug.upper()
    triangles_after = triangle_count([merged])

    export_dir.mkdir(parents=True, exist_ok=True)
    export_path = export_dir / (slug + "_visual_top3d_v001.glb")
    bpy.ops.object.select_all(action="DESELECT")
    merged.select_set(True)
    bpy.context.view_layer.objects.active = merged
    bpy.ops.export_scene.gltf(
        filepath=str(export_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_lights=False,
        export_cameras=False,
    )
    return {
        "slug": slug,
        "source_collection": package.name,
        "source_meshes": len(source_objects),
        "runtime_meshes": 1,
        "triangles_after_downward_cull": triangles_after_cull,
        "triangles_after_optimization": triangles_after,
        "downward_faces_removed": removed_faces,
        "export": str(export_path.relative_to(PROJECT)),
        "collision_policy": "visual_only_no_collision",
    }


def main():
    if bpy.data.filepath and Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
        raise RuntimeError("Open the locked V017 source, not %s" % bpy.data.filepath)

    entries = []
    for slug in PACKAGE_SLUGS:
        package = find_package(slug)
        entries.append(clone_and_optimize(package, slug, RUNTIME_ROOT / slug))

    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "asset_id": "ENV-BASE99-WALL-CONTENTS-V021",
        "display_name": "基地99层非门墙面内容资产包",
        "version": "v021",
        "source_blend": str(OUTPUT_BLEND.relative_to(PROJECT)),
        "derived_from_blend": str(SOURCE_BLEND.relative_to(PROJECT)),
        "derived_from_version": "v017",
        "scope": "wall-mounted non-door content only; structural walls and all doors excluded",
        "collision_policy": "visual_only_no_collision; base room wall blockers remain authoritative",
        "packages": entries,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("BASE99_WALL_CONTENT_V021_WRITTEN:packages=%d:triangles=%d" % (
        len(entries), sum(entry["triangles_after_optimization"] for entry in entries)))


if __name__ == "__main__":
    main()
