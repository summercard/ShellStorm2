"""Export all remaining non-door, non-wall Base99 V017 asset packages for V021.

The source V017 scene is read only.  This produces a V021 derivation with
top-down optimized per-package GLBs, one PackedScene per asset package, and a
root assembly that preserves Blender's baked world placement in Godot.
"""

import bpy
import bmesh
import json
from mathutils import Vector
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
SOURCE_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_remaining_facilities.blend"
COMPONENT_ROOT = PROJECT / "assets/art/environments/base_facility_3d/components/env_base99_remaining_facilities_v021"
RUNTIME_ROOT = PROJECT / "assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities_v021"
MANIFEST_PATH = PROJECT / "assets/art/environments/base_facility_3d/source/env_base99_remaining_facilities_v021_manifest.json"

# All entries are independent V017 packages that are neither floors, doors,
# door-attached controls, structural walls, nor the already imported V021 wall
# content / V004 structural packages.
PACKAGE_SLUGS = [
    "air_compressor",
    "backup_generator",
    "battery_bank",
    "base_camp_rollup_main_door",
    "corridor_emergency_light_group",
    "east_flammable_bin",
    "east_door_access_control",
    "east_low_storage_bench",
    "east_maintenance_workstation",
    "east_plant_group",
    "east_recycle_bin",
    "east_round_pendant_light",
    "east_supply_24h_station",
    "east_waste_bin",
    "equipment_steam_fx",
    "heavy_supply_shelf",
    "hologram_terminal_platform",
    "industrial_water_tank",
    "loft_battery_cabinet",
    "loft_bed_and_bedding",
    "loft_bedside_lamp",
    "loft_bedside_rug",
    "loft_coffee_table",
    "loft_computer_workstation",
    "loft_food_cabinet",
    "loft_lighting_support",
    "loft_lounge_rug",
    "loft_lounge_sofa",
    "loft_medical_cabinet",
    "loft_nightstand",
    "loft_office_chair",
    "loft_pouf_01",
    "loft_pouf_02",
    "loft_side_table",
    "loft_striped_privacy_curtain",
    "main_door_low_storage_cabinet",
    "medical_cabinet",
    "narrow_battery_cabinet",
    "narrow_emergency_cabinet",
    "tools_cabinet",
    "understair_equipment_cabinet",
    "understair_green_bench",
    "understair_storage_shelf",
    "volumetric_dust_fx",
    "warehouse_pendant_light_group",
    "water_purifier",
    "weapon_workshop_station",
]

# These packages must not create air walls or camera blockers.  Every other
# package receives one simple box per source object above the small-detail
# threshold, a materially closer fit than a package-wide bounding box.
VISUAL_ONLY_SLUGS = {
    "corridor_emergency_light_group",
    "east_plant_group",
    "east_round_pendant_light",
    "equipment_steam_fx",
    "loft_bedside_lamp",
    "loft_bedside_rug",
    "loft_lighting_support",
    "loft_lounge_rug",
    "loft_striped_privacy_curtain",
    "volumetric_dust_fx",
    "warehouse_pendant_light_group",
}


def recursive_meshes(collection):
    result = list(collection.objects)
    for child in collection.children:
        result.extend(recursive_meshes(child))
    return [obj for obj in result if obj.type == "MESH"]


def package_for_slug(slug):
    matches = [coll for coll in bpy.data.collections if coll.get("资产包键") == slug]
    if len(matches) != 1:
        raise RuntimeError("Expected exactly one V017 package collection for %s, got %s" % (slug, len(matches)))
    return matches[0]


def triangle_count(objects):
    return sum(len(obj.data.polygons) for obj in objects)


def remove_downward_faces(obj):
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    transform = obj.matrix_world.to_3x3()
    faces = [face for face in bm.faces if (transform @ face.normal).normalized().z < -0.5]
    if faces:
        bmesh.ops.delete(bm, geom=faces, context="FACES")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return len(faces)


def triangulate(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def decimate_for_top_view(obj):
    name = obj.name.upper()
    ratio = 0.58 if any(token in name for token in ("TEXT", "文字", "LABEL", "SCREEN", "UI", "LED")) else 0.42
    modifier = obj.modifiers.new(name="V021TopViewDecimate", type="DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def bounds_in_world(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = [min(point[i] for point in points) for i in range(3)]
    maximum = [max(point[i] for point in points) for i in range(3)]
    return minimum, maximum


def godot_vector(xyz):
    # Blender +Y north maps to Godot -Z north.
    return [xyz[0], xyz[2], -xyz[1]]


def tscn_float(value):
    return ("%.6f" % value).rstrip("0").rstrip(".") if value else "0"


def vector3(values):
    return "Vector3(%s)" % ", ".join(tscn_float(value) for value in values)


def safe_string(value):
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def write_package_scene(entry):
    path = RUNTIME_ROOT / entry["slug"] / (entry["slug"] + "_root_top3d_v001.tscn")
    path.parent.mkdir(parents=True, exist_ok=True)
    rel_glb = "res://" + entry["export"]
    lines = [
        "[gd_scene load_steps=%d format=3]" % (2 + (len(entry["collision_boxes"]) if entry["collision_boxes"] else 0)),
        "",
        "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_visual\"]" % rel_glb,
    ]
    for index, box in enumerate(entry["collision_boxes"]):
        lines.extend([
            "",
            "[sub_resource type=\"BoxShape3D\" id=\"Box_%d\"]" % index,
            "size = %s" % vector3(box["size"]),
        ])
    lines.extend([
        "",
        "[node name=\"%s\" type=\"Node3D\"]" % safe_string(entry["display_name"]),
        "metadata/asset_id = \"ENV-BASE99-REMAINING-FACILITIES-V021::%s\"" % entry["slug"],
        "metadata/asset_version = \"v021\"",
        "metadata/source_blend = \"res://source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_remaining_facilities.blend\"",
        "metadata/derived_from_version = \"v017\"",
        "metadata/collision_policy = \"%s\"" % entry["collision_policy"],
        "metadata/placement_policy = \"baked world coordinates from Blender; root stays at origin\"",
        "",
        "[node name=\"ImportedModel\" parent=\".\" instance=ExtResource(\"1_visual\")]",
    ])
    if entry["slug"].startswith("loft_"):
        # V017 authored the loft finish at Blender Z=6; the live V020 deck
        # finishes at Godot Y=5, so only freestanding loft packages need this
        # known one-metre assembly correction.
        lines.insert(lines.index("[node name=\"ImportedModel\" parent=\".\" instance=ExtResource(\"1_visual\")]"), "position = Vector3(0, -1, 0)")
    if entry["collision_boxes"]:
        lines.extend([
            "",
            "[node name=\"StaticCollision\" type=\"StaticBody3D\" parent=\".\"]",
            "collision_layer = 1",
            "collision_mask = 1",
        ])
        for index, box in enumerate(entry["collision_boxes"]):
            lines.extend([
                "",
                "[node name=\"SourceObjectBox_%03d\" type=\"CollisionShape3D\" parent=\"StaticCollision\"]" % index,
                "position = %s" % vector3(box["center"]),
                "shape = SubResource(\"Box_%d\")" % index,
            ])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    entry["runtime"] = str(path.relative_to(PROJECT))


def write_root_scene(entries):
    RUNTIME_ROOT.mkdir(parents=True, exist_ok=True)
    path = RUNTIME_ROOT / "env_base99_remaining_facilities_root_top3d_v001.tscn"
    lines = ["[gd_scene load_steps=%d format=3]" % (1 + len(entries)), ""]
    for index, entry in enumerate(entries, 1):
        lines.append(
            "[ext_resource type=\"PackedScene\" path=\"res://%s\" id=\"%d_%s\"]" % (
                entry["runtime"], index, entry["slug"],
            )
        )
    lines.extend([
        "",
        "[node name=\"基地99层剩余非门非墙设施_V021\" type=\"Node3D\"]",
        "metadata/asset_id = \"ENV-BASE99-REMAINING-FACILITIES-V021\"",
        "metadata/asset_version = \"v021\"",
        "metadata/asset_category = \"environment_facility_bundle\"",
        "metadata/source_blend = \"res://source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_remaining_facilities.blend\"",
        "metadata/derived_from_blender = \"base_facility_runtime_layout_hq_v017.blend\"",
        "metadata/derived_from_version = \"v017\"",
        "metadata/excluded_scope = \"floors, doors, door-attached controls, structural walls, wall content, mezzanine and stairs\"",
        "metadata/placement_policy = \"baked world coordinates from Blender; root stays at origin\"",
        "metadata/package_count = %d" % len(entries),
    ])
    for index, entry in enumerate(entries, 1):
        lines.extend([
            "",
            "[node name=\"%s\" parent=\".\" instance=ExtResource(\"%d_%s\")]" % (
                safe_string(entry["display_name"]), index, entry["slug"],
            ),
        ])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def clone_optimize_export(package, slug):
    source_meshes = recursive_meshes(package)
    if not source_meshes:
        raise RuntimeError("No mesh objects in %s" % slug)
    output_collection = bpy.data.collections.new("runtime_v021_%s" % slug)
    bpy.context.scene.collection.children.link(output_collection)
    clones = []
    removed = 0
    collision_boxes = []
    for source in source_meshes:
        clone = source.copy()
        clone.data = source.data.copy()
        clone.animation_data_clear()
        clone.parent = None
        clone.matrix_world = source.matrix_world.copy()
        clone.name = "V021_%s" % source.name
        output_collection.objects.link(clone)
        clones.append(clone)
        removed += remove_downward_faces(clone)
        triangulate(clone)
        if slug not in VISUAL_ONLY_SLUGS:
            minimum, maximum = bounds_in_world(clone)
            size = [maximum[i] - minimum[i] for i in range(3)]
            if min(size) >= 0.12 and max(size) >= 0.30:
                center = [(minimum[i] + maximum[i]) * 0.5 for i in range(3)]
                collision_boxes.append({
                    "center": godot_vector(center),
                    "size": [max(0.08, size[0]), max(0.08, size[2]), max(0.08, size[1])],
                })
    triangles_after_cull = triangle_count(clones)
    for clone in clones:
        decimate_for_top_view(clone)
    bpy.ops.object.select_all(action="DESELECT")
    for clone in clones:
        clone.select_set(True)
    bpy.context.view_layer.objects.active = clones[0]
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    merged.name = "ENV_BASE99_REMAINING_%s_V021" % slug.upper()
    output_dir = COMPONENT_ROOT / slug
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / (slug + "_visual_top3d_v001.glb")
    bpy.ops.object.select_all(action="DESELECT")
    merged.select_set(True)
    bpy.context.view_layer.objects.active = merged
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
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
        "display_name": package.name,
        "source_collection": package.name,
        "source_meshes": len(source_meshes),
        "runtime_meshes": 1,
        "triangles_after_downward_cull": triangles_after_cull,
        "triangles_after_optimization": triangle_count([merged]),
        "downward_faces_removed": removed,
        "export": str(output_path.relative_to(PROJECT)),
        "collision_policy": "per_source_object_box_collision" if collision_boxes else "visual_only_no_collision",
        "collision_boxes": collision_boxes,
    }


def main():
    if bpy.data.filepath and Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
        raise RuntimeError("Open the locked V017 source, not %s" % bpy.data.filepath)
    entries = [clone_optimize_export(package_for_slug(slug), slug) for slug in PACKAGE_SLUGS]
    for entry in entries:
        write_package_scene(entry)
    root_path = write_root_scene(entries)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    manifest = {
        "asset_id": "ENV-BASE99-REMAINING-FACILITIES-V021",
        "display_name": "基地99层剩余非门非墙独立设施资产包",
        "version": "v021",
        "source_blend": str(OUTPUT_BLEND.relative_to(PROJECT)),
        "derived_from_blend": str(SOURCE_BLEND.relative_to(PROJECT)),
        "derived_from_version": "v017",
        "scope": "all remaining unimported independent facility/support packages; excludes floors, doors, door-attached controls, structural walls, wall content, mezzanine and stairs",
        "collision_policy": "furniture has per-source-object simplified BoxShape3D; lights, rugs, curtains, vegetation and FX are visual-only",
        "root_runtime": str(root_path.relative_to(PROJECT)),
        "packages": entries,
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("BASE99_REMAINING_FACILITIES_V021_WRITTEN:packages=%d:triangles=%d" % (
        len(entries), sum(entry["triangles_after_optimization"] for entry in entries),
    ))


if __name__ == "__main__":
    main()
