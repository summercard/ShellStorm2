"""Run with Blender: blender --background asset.blend --python this_file.py -- --max-materials 12 [--allow-extra-uv] [--json report.json]"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy


PALETTE_UV = "PaletteUV"
FORBIDDEN_UV_NAMES = {"UVMap", "UV贴图"}
EPSILON = 1.0e-5
MIN_UV_AREA = 1.0e-7
CELL_SAFE_MARGIN = 0.01


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-materials", type=int, default=12)
    parser.add_argument("--allow-extra-uv", action="store_true")
    parser.add_argument("--all-meshes", action="store_true", help="validate every mesh in a multi-asset showcase master")
    parser.add_argument("--json", type=Path)
    return parser.parse_args(argv)


def output_collections():
    return [c for c in bpy.data.collections if c.name.startswith("02_游戏输出")]


def output_meshes(all_meshes=False):
    if all_meshes:
        return sorted((o for o in bpy.context.scene.objects if o.type == "MESH"), key=lambda o: o.name)
    result = set()
    for coll in output_collections():
        result.update(o for o in coll.all_objects if o.type == "MESH")
    return sorted(result, key=lambda o: o.name)


def material_is_emissive(mat):
    if not mat:
        return False
    name = mat.name.lower()
    if any(k in name for k in ("自发光", "emissive", "mat_em_", "_emit", "glow", "neon", "_led")):
        return True
    if mat.use_nodes and mat.node_tree:
        for node in mat.node_tree.nodes:
            if node.type == "EMISSION":
                return True
            if node.type == "BSDF_PRINCIPLED":
                strength = node.inputs.get("Emission Strength")
                if strength and not strength.is_linked and float(strength.default_value) > 0.05:
                    return True
    return False


def uv_polygon_area(uvs):
    return abs(sum(
        uvs[index].x * uvs[(index + 1) % len(uvs)].y
        - uvs[(index + 1) % len(uvs)].x * uvs[index].y
        for index in range(len(uvs))
    )) * 0.5


def audit_palette_uv(obj):
    result = {
        "object": obj.name,
        "polygon_count": len(obj.data.polygons),
        "valid_island_polygon_count": 0,
        "missing_palette_uv": False,
        "active_uv": obj.data.uv_layers.active.name if obj.data.uv_layers.active else "",
        "active_render_uv": next((u.name for u in obj.data.uv_layers if u.active_render), ""),
        "extra_uv_layers": [u.name for u in obj.data.uv_layers if u.name != PALETTE_UV],
        "bad_polygon_examples": [],
    }
    layer = obj.data.uv_layers.get(PALETTE_UV)
    if layer is None:
        result["missing_palette_uv"] = True
        return result
    for polygon in obj.data.polygons:
        uvs = [layer.data[index].uv for index in polygon.loop_indices]
        if not uvs:
            continue
        columns = {min(9, max(0, math.floor(max(0.0, min(0.999999, uv.x)) * 10.0))) for uv in uvs}
        rows = {min(9, max(0, math.floor(max(0.0, min(0.999999, uv.y)) * 10.0))) for uv in uvs}
        same_cell = len(columns) == 1 and len(rows) == 1
        safe = False
        if same_cell:
            column = next(iter(columns))
            row = next(iter(rows))
            safe = all(
                column / 10.0 + CELL_SAFE_MARGIN <= uv.x <= (column + 1) / 10.0 - CELL_SAFE_MARGIN
                and row / 10.0 + CELL_SAFE_MARGIN <= uv.y <= (row + 1) / 10.0 - CELL_SAFE_MARGIN
                for uv in uvs
            )
        has_area = len(uvs) >= 3 and uv_polygon_area(uvs) >= MIN_UV_AREA
        if same_cell and safe and has_area:
            result["valid_island_polygon_count"] += 1
        elif len(result["bad_polygon_examples"]) < 8:
            result["bad_polygon_examples"].append(polygon.index)
    return result


def material_audit(meshes):
    used = {mat for obj in meshes for mat in obj.data.materials if mat}
    # A maintainable source may keep editable component collections whose
    # materials are not used by the integrated output object. They are not unused.
    used_in_file = {
        mat
        for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        for mat in obj.data.materials
        if mat
    }
    unused = sorted(mat.name for mat in bpy.data.materials if mat not in used_in_file)
    bad_uv_nodes = []
    bad_interpolation = []
    missing_uv_nodes = []
    for mat in sorted(used, key=lambda value: value.name):
        uv_nodes = []
        image_nodes = []
        if mat.use_nodes and mat.node_tree:
            uv_nodes = [n for n in mat.node_tree.nodes if n.type == "UVMAP"]
            image_nodes = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"]
        if image_nodes and not uv_nodes:
            missing_uv_nodes.append(mat.name)
        for node in uv_nodes:
            if node.uv_map != PALETTE_UV:
                bad_uv_nodes.append({"material": mat.name, "uv_map": node.uv_map})
        for node in image_nodes:
            if node.interpolation != "Closest":
                bad_interpolation.append({"material": mat.name, "interpolation": node.interpolation})
    return {
        "used_materials": sorted(mat.name for mat in used),
        "unused_materials": unused,
        "bad_uv_map_nodes": bad_uv_nodes,
        "missing_uv_map_nodes": missing_uv_nodes,
        "bad_image_interpolation": bad_interpolation,
    }


def main():
    args = parse_args()
    meshes = output_meshes(args.all_meshes)
    uv_reports = [audit_palette_uv(obj) for obj in meshes]
    material_report = material_audit(meshes)
    forbidden = sorted(o.name for o in bpy.data.objects if o.name in {"DISPLAY_Ground", "Display_Plinth"})
    mixed_emission = []
    bad_emissive_names = []
    body_budget_failures = []
    emissive_budget_failures = []
    for obj in meshes:
        flags = {material_is_emissive(m) for m in obj.data.materials if m}
        if len(flags) > 1:
            mixed_emission.append(obj.name)
        is_emissive = True in flags
        if is_emissive and not any(k in obj.name.lower() for k in ("自发光", "ui灯光", "emissive", "glow")):
            bad_emissive_names.append(obj.name)
        slot_count = len([m for m in obj.data.materials if m])
        if is_emissive and slot_count > 1:
            emissive_budget_failures.append(obj.name)
        if not is_emissive and slot_count > 3:
            body_budget_failures.append(obj.name)

    missing_uv = [r["object"] for r in uv_reports if r["missing_palette_uv"]]
    bad_faces = [r for r in uv_reports if r["valid_island_polygon_count"] != r["polygon_count"]]
    bad_active = [r["object"] for r in uv_reports if r["active_uv"] != PALETTE_UV]
    bad_render = [r["object"] for r in uv_reports if r["active_render_uv"] != PALETTE_UV]
    extra_uv = {r["object"]: r["extra_uv_layers"] for r in uv_reports if r["extra_uv_layers"]}
    checks = {
        "material_budget": len(material_report["used_materials"]) <= args.max_materials,
        "no_unused_materials": not material_report["unused_materials"],
        "has_game_output_collection": args.all_meshes or bool(output_collections()),
        "has_output_meshes": bool(meshes),
        "palette_uv_on_all_output_meshes": not missing_uv,
        "palette_uv_face_islands_within_single_cells": not bad_faces,
        "palette_uv_is_active_edit_layer": not bad_active,
        "palette_uv_is_active_render_layer": not bad_render,
        "no_undeclared_extra_uv_layers": args.allow_extra_uv or not extra_uv,
        "materials_read_palette_uv": not material_report["bad_uv_map_nodes"] and not material_report["missing_uv_map_nodes"],
        "palette_images_use_closest": not material_report["bad_image_interpolation"],
        "no_display_ground_or_plinth": not forbidden,
        "emissive_not_mixed_with_body": not mixed_emission,
        "emissive_objects_clearly_named": not bad_emissive_names,
        "body_has_at_most_three_materials": not body_budget_failures,
        "emissive_has_one_material": not emissive_budget_failures,
    }
    report = {
        "blend": bpy.data.filepath,
        "passed": all(checks.values()),
        "checks": checks,
        "output_mesh_count": len(meshes),
        "polygon_count": sum(r["polygon_count"] for r in uv_reports),
        "valid_island_polygon_count": sum(r["valid_island_polygon_count"] for r in uv_reports),
        "uv_reports": uv_reports,
        "extra_uv_layers": extra_uv,
        "material_audit": material_report,
        "forbidden_objects": forbidden,
        "mixed_emission_objects": mixed_emission,
        "poorly_named_emissive_objects": bad_emissive_names,
        "body_material_budget_failures": body_budget_failures,
        "emissive_material_budget_failures": emissive_budget_failures,
    }
    text = json.dumps(report, ensure_ascii=False, indent=2)
    print(text)
    if args.json:
        args.json.write_text(text, encoding="utf-8")
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
