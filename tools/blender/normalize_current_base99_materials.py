"""Normalize current ShellStorm2 Base99 Blender sources to the four scene roles.

This is a baseline-cleanup tool for the current formal sources. It remaps
legacy material copies (for example *_v018公共色盘 or *.001) onto the canonical
four shared scene roles, removes the now-unused duplicate materials, relinks
palette images to the project palette, and preserves face material assignments.
"""
from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path

import bpy


ROLE_RULES = (
    ("01_精工金属", "01_精工金属_紫色骨架"),
    ("02_细腻哑光", "02_细腻哑光_青绿大面"),
    ("03_清漆反光", "03_清漆反光_紫粉点缀"),
    ("04_柔和自发光", "04_柔和自发光_UI灯光"),
)
CANONICAL_NAMES = {canonical for _, canonical in ROLE_RULES}


def canonical_role(name: str) -> str | None:
    for prefix, canonical in ROLE_RULES:
        if name == canonical or name.startswith(prefix):
            return canonical
    return None


def project_root(blend: Path) -> Path:
    for parent in (blend, *blend.parents):
        if (parent / "project.godot").is_file():
            return parent
    raise RuntimeError(f"Cannot locate project.godot above {blend}")


def normalize_material_nodes(material: bpy.types.Material, palette: Path) -> None:
    if not material.use_nodes or material.node_tree is None:
        return
    rel_palette = bpy.path.relpath(str(palette))
    for node in material.node_tree.nodes:
        if node.type != "TEX_IMAGE" or node.image is None:
            continue
        node.image.filepath = rel_palette
        node.interpolation = "Closest"


def normalize_blend(path: Path, dry_run: bool) -> dict:
    bpy.ops.wm.open_mainfile(filepath=str(path))
    root = project_root(path)
    palette = root / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
    if not palette.is_file():
        raise RuntimeError(f"Missing shared palette: {palette}")

    before_names = sorted(material.name for material in bpy.data.materials)
    role_sources: dict[str, list[bpy.types.Material]] = {name: [] for name in CANONICAL_NAMES}
    for material in bpy.data.materials:
        role = canonical_role(material.name)
        if role:
            role_sources[role].append(material)

    canonical_materials: dict[str, bpy.types.Material] = {}
    for canonical in sorted(CANONICAL_NAMES):
        sources = role_sources[canonical]
        if not sources:
            continue
        exact = next((material for material in sources if material.name == canonical), None)
        if exact is None:
            exact = sources[0].copy()
            exact.name = canonical
        canonical_materials[canonical] = exact

    remapped_faces = 0
    for mesh in bpy.data.meshes:
        old_materials = list(mesh.materials)
        if not old_materials:
            continue
        target_by_old_index: dict[int, bpy.types.Material] = {}
        unique_targets: list[bpy.types.Material] = []
        for index, material in enumerate(old_materials):
            if material is None:
                continue
            role = canonical_role(material.name)
            target = canonical_materials.get(role, material) if role else material
            target_by_old_index[index] = target
            if target not in unique_targets:
                unique_targets.append(target)
        if not unique_targets:
            continue
        new_index = {material: index for index, material in enumerate(unique_targets)}
        mesh.materials.clear()
        for material in unique_targets:
            mesh.materials.append(material)
        for polygon in mesh.polygons:
            target = target_by_old_index.get(polygon.material_index)
            if target is not None:
                polygon.material_index = new_index[target]
                remapped_faces += 1

    used = {
        material
        for mesh in bpy.data.meshes
        for material in mesh.materials
        if material is not None
    }
    for material in list(bpy.data.materials):
        if material not in used and material.users == 0:
            bpy.data.materials.remove(material)

    for material in used:
        normalize_material_nodes(material, palette)

    after_names = sorted(material.name for material in bpy.data.materials)
    unknown = [name for name in after_names if name not in CANONICAL_NAMES]
    if len(after_names) > 4:
        raise RuntimeError(f"{path}: material budget exceeded after normalization: {after_names}")
    if unknown:
        raise RuntimeError(f"{path}: non-canonical materials remain: {unknown}")
    if not dry_run:
        bpy.ops.wm.save_as_mainfile(filepath=str(path), check_existing=False)
    return {
        "file": str(path),
        "before": before_names,
        "after": after_names,
        "remapped_faces": remapped_faces,
        "saved": not dry_run,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", type=Path, action="append", required=True)
    parser.add_argument("--dry-run", action="store_true")
    script_args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    args = parser.parse_args(script_args)
    reports = [normalize_blend(path.resolve(), args.dry_run) for path in args.blend]
    for report in reports:
        print(
            "BASE99_MATERIAL_NORMALIZE",
            report["file"],
            "before=" + str(len(report["before"])),
            "after=" + ",".join(report["after"]),
            "faces=" + str(report["remapped_faces"]),
            "saved=" + str(report["saved"]),
        )


if __name__ == "__main__":
    main()




