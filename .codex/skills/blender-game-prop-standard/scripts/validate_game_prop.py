"""Run with Blender: blender --background asset.blend --python this_file.py -- --max-materials 12 [--json report.json]"""

import argparse
import json
import sys
from pathlib import Path

import bpy


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-materials", type=int, default=12)
    parser.add_argument("--json", type=Path)
    return parser.parse_args(argv)


def has_output_collection():
    return any(c.name.startswith("02_游戏输出") for c in bpy.data.collections)


def output_meshes():
    result = set()
    for coll in bpy.data.collections:
        if coll.name.startswith("02_游戏输出"):
            result.update(o for o in coll.all_objects if o.type == "MESH")
    if result:
        return sorted(result, key=lambda o: o.name)
    return sorted((o for o in bpy.context.scene.objects if o.type == "MESH"), key=lambda o: o.name)


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


def main():
    args = parse_args()
    meshes = output_meshes()
    material_names = sorted(m.name for m in bpy.data.materials)
    forbidden = sorted(o.name for o in bpy.data.objects if o.name in {"DISPLAY_Ground", "Display_Plinth"})
    missing_uv = sorted(o.name for o in meshes if "PaletteUV" not in o.data.uv_layers)
    mixed_emission = []
    bad_emissive_names = []
    for obj in meshes:
        flags = {material_is_emissive(m) for m in obj.data.materials if m}
        if len(flags) > 1:
            mixed_emission.append(obj.name)
        if True in flags and not any(k in obj.name.lower() for k in ("自发光", "ui灯光", "emissive", "glow")):
            bad_emissive_names.append(obj.name)
    checks = {
        "material_budget": len(material_names) <= args.max_materials,
        "has_game_output_collection": has_output_collection(),
        "has_output_meshes": bool(meshes),
        "palette_uv_on_all_output_meshes": not missing_uv,
        "no_display_ground_or_plinth": not forbidden,
        "emissive_not_mixed_with_body": not mixed_emission,
        "emissive_objects_clearly_named": not bad_emissive_names,
    }
    report = {
        "blend": bpy.data.filepath,
        "passed": all(checks.values()),
        "checks": checks,
        "material_count": len(material_names),
        "materials": material_names,
        "output_mesh_count": len(meshes),
        "missing_palette_uv": missing_uv,
        "forbidden_objects": forbidden,
        "mixed_emission_objects": mixed_emission,
        "poorly_named_emissive_objects": bad_emissive_names,
    }
    text = json.dumps(report, ensure_ascii=False, indent=2)
    print(text)
    if args.json:
        args.json.write_text(text, encoding="utf-8")
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
