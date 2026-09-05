"""Export the four V017 Base99 structural packages as optimized V021 runtime assets."""

import bpy
import bmesh
import json
from mathutils import Vector
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
SOURCE_BLEND = PROJECT / "source/art/blender/base_facility_layout/base_facility_runtime_layout_hq_v017.blend"
OUTPUT_BLEND = PROJECT / "source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_structural.blend"
COMPONENT_ROOT = PROJECT / "assets/art/environments/base_facility_3d/components/env_base99_structural_v021"
RUNTIME_ROOT = PROJECT / "assets/art/environments/base_facility_3d/runtime/env_base99_structural_v021"
MANIFEST_PATH = PROJECT / "assets/art/environments/base_facility_3d/source/env_base99_structural_v021_manifest.json"

PACKAGE_SLUGS = [
    "east_mezzanine_structure",
    "east_upper_transition_stair",
    "northwest_l_stair",
    "underdeck_sheet_blocker",
]


def meshes_in_collection(collection):
    objects = list(collection.objects)
    for child in collection.children:
        objects.extend(meshes_in_collection(child))
    return [obj for obj in objects if obj.type == "MESH"]


def package_for_slug(slug):
    matches = [collection for collection in bpy.data.collections if collection.get("资产包键") == slug]
    if len(matches) != 1:
        raise RuntimeError("Expected one collection for %s, got %d" % (slug, len(matches)))
    return matches[0]


def world_bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    minimum = [min(point[index] for point in points) for index in range(3)]
    maximum = [max(point[index] for point in points) for index in range(3)]
    return minimum, maximum


def godot_vector(values):
    return [values[0], values[2], -values[1]]


def remove_downward_faces(obj):
    mesh = obj.data
    bmesh_data = bmesh.new()
    bmesh_data.from_mesh(mesh)
    transform = obj.matrix_world.to_3x3()
    downward = [face for face in bmesh_data.faces if (transform @ face.normal).normalized().z < -0.5]
    if downward:
        bmesh.ops.delete(bmesh_data, geom=downward, context="FACES")
    bmesh_data.to_mesh(mesh)
    bmesh_data.free()
    mesh.update()
    return len(downward)


def triangulate(obj):
    mesh = obj.data
    bmesh_data = bmesh.new()
    bmesh_data.from_mesh(mesh)
    bmesh.ops.triangulate(bmesh_data, faces=list(bmesh_data.faces))
    bmesh_data.to_mesh(mesh)
    bmesh_data.free()
    mesh.update()


def optimize(obj):
    modifier = obj.modifiers.new(name="V021TopViewDecimate", type="DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = 0.55 if any(token in obj.name.upper() for token in ("TEXT", "LABEL", "LED")) else 0.45
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def triangle_count(objects):
    return sum(len(obj.data.polygons) for obj in objects)


def box_for(obj, preserve_rotation=False):
    if preserve_rotation:
        local = [Vector(corner) for corner in obj.bound_box]
        minimum = [min(point[index] for point in local) for index in range(3)]
        maximum = [max(point[index] for point in local) for index in range(3)]
        size = [maximum[index] - minimum[index] for index in range(3)]
        if min(size) < 0.08 or max(size) < 0.30:
            return None
        center = Vector([(minimum[index] + maximum[index]) * 0.5 for index in range(3)])
        rotation = obj.matrix_world.to_3x3()
        convert = ((1, 0, 0), (0, 0, 1), (0, -1, 0))
        # Godot basis = C * Blender basis * inverse(C), with C:(x,y,z)->(x,z,-y).
        basis = [[sum(convert[row][k] * rotation[k][l] * convert[col][l] for k in range(3) for l in range(3)) for col in range(3)] for row in range(3)]
        return {"center": godot_vector(obj.matrix_world @ center), "size": [size[0], size[2], size[1]], "basis": basis}
    minimum, maximum = world_bounds(obj)
    size = [maximum[index] - minimum[index] for index in range(3)]
    if min(size) < 0.08 or max(size) < 0.30:
        return None
    center = [(minimum[index] + maximum[index]) * 0.5 for index in range(3)]
    return {
        "center": godot_vector(center),
        "size": [max(0.08, size[0]), max(0.08, size[2]), max(0.08, size[1])],
    }


def fmt(value):
    return ("%.6f" % value).rstrip("0").rstrip(".") if value else "0"


def vector(values):
    return "Vector3(%s)" % ", ".join(fmt(value) for value in values)


def export_package(slug):
    package = package_for_slug(slug)
    sources = meshes_in_collection(package)
    collision_sources = [obj for obj in sources if obj.name.upper().startswith("COLLISION_")]
    visual_sources = [obj for obj in sources if obj not in collision_sources]
    if not visual_sources:
        raise RuntimeError("No visual meshes in %s" % slug)
    output = bpy.data.collections.new("runtime_v021_%s" % slug)
    bpy.context.scene.collection.children.link(output)
    clones = []
    removed = 0
    boxes = [box_for(obj, preserve_rotation=bool(collision_sources)) for obj in (collision_sources or visual_sources)]
    boxes = [box for box in boxes if box]
    for source in visual_sources:
        clone = source.copy()
        clone.data = source.data.copy()
        clone.animation_data_clear()
        clone.parent = None
        clone.matrix_world = source.matrix_world.copy()
        clone.name = "V021_%s" % source.name
        output.objects.link(clone)
        removed += remove_downward_faces(clone)
        triangulate(clone)
        clones.append(clone)
    triangles_after_cull = triangle_count(clones)
    for clone in clones:
        optimize(clone)
    bpy.ops.object.select_all(action="DESELECT")
    for clone in clones:
        clone.select_set(True)
    bpy.context.view_layer.objects.active = clones[0]
    bpy.ops.object.join()
    merged = bpy.context.view_layer.objects.active
    merged.name = "ENV_BASE99_STRUCTURAL_%s_V021" % slug.upper()
    output_dir = COMPONENT_ROOT / slug
    output_dir.mkdir(parents=True, exist_ok=True)
    glb_path = output_dir / (slug + "_visual_top3d_v001.glb")
    bpy.ops.export_scene.gltf(
        filepath=str(glb_path), export_format="GLB", use_selection=True, export_apply=True,
        export_materials="EXPORT", export_image_format="NONE", export_lights=False, export_cameras=False,
    )
    return {
        "slug": slug, "display_name": package.name, "source_meshes": len(visual_sources),
        "source_collision_meshes": len(collision_sources), "collision_boxes": boxes,
        "downward_faces_removed": removed, "triangles_after_downward_cull": triangles_after_cull,
        "triangles_after_optimization": triangle_count([merged]), "export": str(glb_path.relative_to(PROJECT)),
    }


def write_scene(entry):
    slug = entry["slug"]
    path = RUNTIME_ROOT / slug / (slug + "_root_top3d_v001.tscn")
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ["[gd_scene load_steps=%d format=3]" % (2 + len(entry["collision_boxes"])), "",
        "[ext_resource type=\"PackedScene\" path=\"res://%s\" id=\"1_visual\"]" % entry["export"]]
    for index, box in enumerate(entry["collision_boxes"]):
        lines += ["", "[sub_resource type=\"BoxShape3D\" id=\"Box_%d\"]" % index, "size = %s" % vector(box["size"])]
    lines += ["", "[node name=\"%s\" type=\"Node3D\"]" % entry["display_name"],
        "metadata/asset_id = \"ENV-BASE99-STRUCTURAL-V021::%s\"" % slug,
        "metadata/asset_version = \"v021\"",
        "metadata/source_blend = \"res://source/art/blender/base_facility_layout/v021/base_facility_runtime_layout_hq_v021_structural.blend\"",
        "metadata/derived_from_blender = \"base_facility_runtime_layout_hq_v017.blend\"",
        "metadata/collision_policy = \"source_collider_boxes\"" if entry["source_collision_meshes"] else "metadata/collision_policy = \"per_visual_component_boxes\"",
        "metadata/placement_policy = \"baked V017 world coordinates; root remains at origin\"", "",
        "[node name=\"ImportedModel\" parent=\".\" instance=ExtResource(\"1_visual\")]", "",
        "[node name=\"StaticCollision\" type=\"StaticBody3D\" parent=\".\"]",
        "collision_layer = 1", "collision_mask = 1"]
    for index, box in enumerate(entry["collision_boxes"]):
        lines += ["", "[node name=\"Blocker_%03d\" type=\"CollisionShape3D\" parent=\"StaticCollision\"]" % index,
            "position = %s" % vector(box["center"])]
        if "basis" in box:
            lines.append("basis = Basis(%s)" % ", ".join(fmt(value) for row in box["basis"] for value in row))
        lines.append("shape = SubResource(\"Box_%d\")" % index)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    entry["runtime"] = str(path.relative_to(PROJECT))


def main():
    if Path(bpy.data.filepath).resolve() != SOURCE_BLEND.resolve():
        raise RuntimeError("Open locked V017 source")
    entries = [export_package(slug) for slug in PACKAGE_SLUGS]
    for entry in entries:
        write_scene(entry)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST_PATH.write_text(json.dumps({
        "asset_id": "ENV-BASE99-STRUCTURAL-V021", "version": "v021",
        "source_blend": str(OUTPUT_BLEND.relative_to(PROJECT)),
        "derived_from_blend": str(SOURCE_BLEND.relative_to(PROJECT)), "packages": entries,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("BASE99_STRUCTURAL_V021_WRITTEN:packages=%d:triangles=%d" % (len(entries), sum(entry["triangles_after_optimization"] for entry in entries)))


if __name__ == "__main__":
    main()
