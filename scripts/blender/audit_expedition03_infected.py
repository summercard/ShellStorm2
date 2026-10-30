"""Independently inspect the saved expedition03 infected source pair.

Run Blender with --factory-startup --background <model.blend>
--python-exit-code 1 --python <this file>.
This script never saves or changes either source file.
"""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from workspace_paths import work_path

SLUG = "enm_melee_expedition03_infected01"
SOURCE = ROOT / "art_source/enemies/enemy_3d" / SLUG / "source"
MODEL = SOURCE / f"{SLUG}_model_v002.blend"
ANIMATION = SOURCE / f"{SLUG}_animation_v002.blend"
PALETTE = ROOT / "assets/art/shared/palette/npc_palette_10x10_512.png"
REPORT = work_path("sessions/2026-10-30_expedition03_infected/v002/independent_audit.json")
EXPECTED_BONES = {"root", "pelvis", "spine", "chest", "neck", "head", "jaw", "tongue"}
EXPECTED_BONES.update(f"{part}.{side}" for side in ("L", "R")
                      for part in ("upper_arm", "forearm", "hand", "thigh", "shin", "foot"))
CHECKS = []


def check(name, passed, detail=None):
    item = {"name": name, "passed": bool(passed)}
    if detail is not None:
        item["detail"] = detail
    CHECKS.append(item)


def path_of(image_or_library):
    return Path(bpy.path.abspath(image_or_library.filepath,
                                library=getattr(image_or_library, "library", None))).resolve()


def vector(value):
    return [round(float(c), 8) for c in value]


def matrix_error(value):
    identity = Matrix.Identity(4)
    return max(abs(value[r][c] - identity[r][c]) for r in range(4) for c in range(4))


def skeleton_snapshot(rig):
    rows = []
    for bone in sorted(rig.data.bones, key=lambda item: item.name):
        rows.append({"name": bone.name, "parent": bone.parent.name if bone.parent else None,
                     "head": vector(bone.head_local), "tail": vector(bone.tail_local),
                     "matrix": [vector(row) for row in bone.matrix_local],
                     "deform": bool(bone.use_deform)})
    encoded = json.dumps(rows, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return {"id": rig.get("skeleton_id"), "bones": rows,
            "signature": hashlib.sha256(encoded).hexdigest()}


def action_curves(action):
    curves = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for channelbag in getattr(strip, "channelbags", []):
                curves.extend(channelbag.fcurves)
    if not curves:
        curves.extend(getattr(action, "fcurves", []))
    return curves


def inspect_actions(label, is_animation):
    result = []
    for action in bpy.data.actions:
        curves = action_curves(action)
        frames = sorted({round(float(key.co.x), 8)
                         for curve in curves for key in curve.keyframe_points})
        values = [float(key.co.y) for curve in curves for key in curve.keyframe_points]
        result.append({"name": action.name, "frames": frames, "curves": len(curves),
                       "keyframes": len(values),
                       "max_abs_rotation": max((abs(v) for v in values), default=0.0),
                       "paths": sorted({curve.data_path for curve in curves})})
    if is_animation:
        check(f"{label}: only TPOSE_reference action", len(result) == 1 and
              result[0]["name"] == "TPOSE_reference", result)
        if result:
            check(f"{label}: single frame neutral T Pose", result[0]["frames"] == [1.0] and
                  result[0]["max_abs_rotation"] <= 1e-7 and
                  all(path.endswith("rotation_euler") for path in result[0]["paths"]), result[0])
        check(f"{label}: timeline is one frame", bpy.context.scene.frame_start == 1 and
              bpy.context.scene.frame_end == 1)
    else:
        check(f"{label}: model has no animation actions", not result, result)
    return result


def inspect_materials(label, meshes):
    used = {}
    materials = {}
    for obj in meshes:
        for face in obj.data.polygons:
            slot = obj.material_slots[face.material_index] if face.material_index < len(obj.material_slots) else None
            if slot is None or slot.material is None:
                check(f"{label}: material assigned on {obj.name}/{face.index}", False)
                continue
            mat = slot.material
            materials[mat.name] = mat
            used[mat.name] = used.get(mat.name, 0) + 1
    check(f"{label}: exactly four material datablocks", len(bpy.data.materials) == 4,
          [mat.name for mat in bpy.data.materials])
    check(f"{label}: all four materials used by faces", len(used) == 4, used)
    image_paths = set()
    for name, material in materials.items():
        check(f"{label}: {name} uses nodes", material.use_nodes)
        images = [node for node in material.node_tree.nodes if node.type == "TEX_IMAGE"]
        check(f"{label}: {name} one palette texture", len(images) == 1)
        for node in images:
            check(f"{label}: {name} Closest sampling", node.interpolation == "Closest")
            links = list(node.inputs["Vector"].links)
            check(f"{label}: {name} explicit PaletteUV input", len(links) == 1 and
                  links[0].from_node.type == "UVMAP" and links[0].from_node.uv_map == "PaletteUV")
            check(f"{label}: {name} has image", node.image is not None)
            if node.image:
                actual = path_of(node.image)
                image_paths.add(str(actual))
                check(f"{label}: {name} canonical external palette", actual == PALETTE.resolve() and actual.is_file(), str(actual))
                check(f"{label}: {name} palette unpacked", node.image.packed_file is None and
                      not len(node.image.packed_files))
                check(f"{label}: {name} palette 512x512", tuple(node.image.size) == (512, 512), list(node.image.size))
    check(f"{label}: one shared palette path", image_paths == {str(PALETTE.resolve())}, sorted(image_paths))
    return used


def inspect_palette_pixels():
    matching = [image for image in bpy.data.images if image.source == "FILE" and path_of(image) == PALETTE.resolve()]
    if not matching:
        check("palette: image available for independent pixel inspection", False)
        return
    image = matching[0]
    image.reload()
    pixels = image.pixels[:]
    channels = image.channels
    size = tuple(image.size)
    check("palette: loaded pixel buffer", size == (512, 512) and len(pixels) == 512 * 512 * channels,
          {"size": size, "channels": channels, "values": len(pixels)})
    bad_cells = []
    if size == (512, 512):
        for row in range(10):
            y0, y1 = round(row * 51.2), round((row + 1) * 51.2)
            for column in range(10):
                x0, x1 = round(column * 51.2), round((column + 1) * 51.2)
                start = (y0 * 512 + x0) * channels
                color = tuple(pixels[start:start + channels])
                if any(tuple(pixels[(y * 512 + x) * channels:(y * 512 + x + 1) * channels]) != color
                       for y in range(y0, y1) for x in range(x0, x1)):
                    bad_cells.append([row, column])
    check("palette: all 100 integer-bounded cells are pure solid colors", not bad_cells, bad_cells)


def inspect_uv(label, obj):
    layers = obj.data.uv_layers
    names = [layer.name for layer in layers]
    check(f"{label}: {obj.name} only PaletteUV", names == ["PaletteUV"], names)
    if "PaletteUV" not in layers:
        return {"faces": len(obj.data.polygons), "valid": 0, "bad": ["missing UV"]}
    layer = layers["PaletteUV"]
    check(f"{label}: {obj.name} active edit/render UV", layers.active == layer and layer.active_render)
    bad = []
    for face in obj.data.polygons:
        uv = [layer.data[index].uv.copy() for index in face.loop_indices]
        area = abs(sum(a.x * b.y - b.x * a.y for a, b in zip(uv, uv[1:] + uv[:1]))) / 2.0
        cells = {(math.floor(value.x * 10), math.floor(value.y * 10)) for value in uv}
        valid_cells = len(cells) == 1 and all(0 <= x <= 9 and 0 <= y <= 9 for x, y in cells)
        safe = valid_cells and all(.1 - 1e-6 <= value.x * 10 - math.floor(value.x * 10) <= .9 + 1e-6 and
                                   .1 - 1e-6 <= value.y * 10 - math.floor(value.y * 10) <= .9 + 1e-6
                                   for value in uv)
        if not (len(uv) == 3 and area > 1e-9 and valid_cells and safe):
            bad.append({"face": face.index, "loops": len(uv), "area": area,
                        "cells": sorted(cells), "safe": safe})
    check(f"{label}: {obj.name} all face islands have area and 10% safe margin", not bad, bad[:20])
    return {"faces": len(obj.data.polygons), "valid": len(obj.data.polygons) - len(bad), "bad": bad[:20]}


def inspect_weights(label, obj, bones):
    bad = []
    for vertex in obj.data.vertices:
        weights = []
        for group in vertex.groups:
            name = obj.vertex_groups[group.group].name if group.group < len(obj.vertex_groups) else None
            weights.append((name, float(group.weight)))
        if not weights or abs(sum(weight for _, weight in weights) - 1.0) > 1e-5 or \
                any(name not in bones or weight < 0 for name, weight in weights):
            bad.append({"vertex": vertex.index, "weights": weights})
    check(f"{label}: {obj.name} every vertex has normalized skeleton weights", not bad, bad[:20])
    return {"vertices": len(obj.data.vertices), "bad": len(bad)}


def inspect_master(path, is_animation):
    label = "animation" if is_animation else "model"
    bpy.ops.wm.open_mainfile(filepath=str(path))
    bpy.context.scene.frame_set(1)
    objects = list(bpy.context.scene.objects)
    meshes = [obj for obj in objects if obj.type == "MESH"]
    rigs = [obj for obj in objects if obj.type == "ARMATURE"]
    check(f"{label}: one skeleton and visible meshes", len(rigs) == 1 and bool(meshes),
          {"skeletons": len(rigs), "meshes": len(meshes)})
    check(f"{label}: source contains no camera or light", not bpy.data.cameras and not bpy.data.lights)
    check(f"{label}: no collision or preview objects", all(
        obj.type in {"MESH", "ARMATURE"} and not any(word in obj.name.lower()
        for word in ("collision", "collider", "camera", "display_ground", "display_plinth")) for obj in objects))
    check(f"{label}: metric unit scale one", bpy.context.scene.unit_settings.system == "METRIC" and
          abs(bpy.context.scene.unit_settings.scale_length - 1.0) < 1e-7)
    check(f"{label}: all object scales one", all(max(abs(value - 1.0) for value in obj.scale) <= 1e-7 for obj in objects))
    check(f"{label}: root transform identity", all(matrix_error(obj.matrix_world) < 1e-7 for obj in objects if not obj.parent))
    graph = bpy.context.evaluated_depsgraph_get()
    points = []
    polygons = triangles = vertices = 0
    parts = []
    degenerate = []
    for obj in meshes:
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=graph)
        mesh.calc_loop_triangles()
        degenerate.extend({"object": obj.name, "triangle": triangle.index, "area": float(triangle.area)}
                          for triangle in mesh.loop_triangles if triangle.area < 1e-10)
        points.extend(evaluated.matrix_world @ vert.co for vert in mesh.vertices)
        vertices += len(mesh.vertices)
        polygons += len(mesh.polygons)
        triangles += len(mesh.loop_triangles)
        parts.append({"name": obj.name, "vertices": len(mesh.vertices), "polygons": len(mesh.polygons),
                      "evaluated_triangles": len(mesh.loop_triangles)})
        evaluated.to_mesh_clear()
    check(f"{label}: at most 500 evaluated triangles", 0 < triangles <= 500, triangles)
    check(f"{label}: at most 500 source polygons", 0 < polygons <= 500, polygons)
    check(f"{label}: no degenerate evaluated triangles", not degenerate, degenerate[:20])
    low = [min(point[i] for point in points) for i in range(3)] if points else [0, 0, 0]
    high = [max(point[i] for point in points) for i in range(3)] if points else [0, 0, 0]
    height = high[2] - low[2]
    check(f"{label}: height 1.600m", abs(height - 1.6) < 1e-5, height)
    check(f"{label}: feet on Z zero", abs(low[2]) < 1e-5, low[2])
    check(f"{label}: shortened arm span 1.130m", abs(high[0]-low[0]-1.13)<1e-5, high[0]-low[0])
    skeleton = None
    if len(rigs) == 1:
        rig = rigs[0]
        skeleton = skeleton_snapshot(rig)
        bone_names = {bone.name for bone in rig.data.bones}
        check(f"{label}: exact 20-bone skeleton", bone_names == EXPECTED_BONES, sorted(bone_names))
        check(f"{label}: independent skeleton ID", rig.get("skeleton_id") == "SKEL-INFECTED01-002", rig.get("skeleton_id"))
        neutral = {bone.name: matrix_error(bone.matrix_basis) for bone in rig.pose.bones}
        check(f"{label}: actual neutral rest pose", all(value < 1e-6 for value in neutral.values()), neutral)
        horizontal = {}
        for side in ("L", "R"):
            for part in ("upper_arm", "forearm", "hand"):
                name = f"{part}.{side}"
                if name not in rig.data.bones:
                    continue
                bone = rig.data.bones[name]
                horizontal[name] = {"head": vector(bone.head_local), "tail": vector(bone.tail_local)}
                check(f"{label}: {name} horizontal T pose", abs(bone.head_local.z - bone.tail_local.z) < 1e-6 and
                      abs(bone.head_local.y - bone.tail_local.y) < 1e-6 and
                      (bone.tail_local.x - bone.head_local.x) * (1 if side == "L" else -1) > 0,
                      horizontal[name])
        for obj in meshes:
            modifiers = [modifier for modifier in obj.modifiers if modifier.type == "ARMATURE"]
            check(f"{label}: {obj.name} bound to source rig", obj.parent == rig and len(modifiers) == 1 and
                  modifiers[0].object == rig)
    else:
        bone_names = set()
    materials = inspect_materials(label, meshes)
    if not is_animation:
        inspect_palette_pixels()
    uv = {obj.name: inspect_uv(label, obj) for obj in meshes}
    weights = {obj.name: inspect_weights(label, obj, bone_names) for obj in meshes}
    libraries = []
    for obj in meshes:
        library = obj.data.library
        actual = path_of(library) if library else None
        libraries.append({"object": obj.name, "mesh_library": str(actual) if actual else None})
        check(f"{label}: {obj.name} mesh source link", (actual == MODEL.resolve() and actual.is_file())
              if is_animation else library is None, libraries[-1])
    if is_animation:
        check("animation: portable relative library paths", bool(bpy.data.libraries) and
              all(library.filepath.startswith("//") for library in bpy.data.libraries),
              [library.filepath for library in bpy.data.libraries])
    actions = inspect_actions(label, is_animation)
    return {"file": str(path.relative_to(ROOT)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "vertices": vertices, "polygons": polygons, "evaluated_triangles": triangles,
            "bounds_min": vector(low), "bounds_max": vector(high), "height_m": height,
            "materials_face_usage": materials, "skeleton": skeleton, "parts": parts,
            "uv": uv, "weights": weights, "linked_meshes": libraries, "actions": actions}


def main():
    report = {"schema_version": 1, "asset_id": "ENM-MELEE-EXPEDITION03-INFECTED01",
              "date": "2026-10-30",
              "scope": "Independent saved Blender source audit; no Godot integration claimed",
              "blender_version": bpy.app.version_string, "files": {}, "checks": CHECKS}
    try:
        for path, key, animation in ((MODEL, "model", False), (ANIMATION, "animation", True)):
            check(f"{key}: file exists", path.is_file(), str(path))
            if path.is_file():
                report["files"][key] = inspect_master(path, animation)
        if set(report["files"]) == {"model", "animation"}:
            model = report["files"]["model"]
            animation = report["files"]["animation"]
            check("pair: identical rest skeleton names hierarchy transforms", model["skeleton"] == animation["skeleton"])
            check("pair: linked geometry counts preserved", all(model[key] == animation[key]
                  for key in ("vertices", "polygons", "evaluated_triangles", "bounds_min", "bounds_max")))
    except Exception as error:
        import traceback
        check("audit execution completed", False, {"error": repr(error), "traceback": traceback.format_exc()})
    report["errors"] = [item for item in CHECKS if not item["passed"]]
    report["passed_checks"] = sum(item["passed"] for item in CHECKS)
    report["total_checks"] = len(CHECKS)
    report["exit_code"] = int(bool(report["errors"]))
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("INDEPENDENT_INFECTED_AUDIT", json.dumps({"report": str(REPORT), "exit_code": report["exit_code"],
          "passed": report["passed_checks"], "total": report["total_checks"], "errors": report["errors"]}, ensure_ascii=False))
    if report["exit_code"]:
        raise RuntimeError("Independent source audit failed; inspect independent_audit.json")


if __name__ == "__main__":
    main()
