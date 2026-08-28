"""Relink every palette image in scene/facility Blend sources to one external PNG.

Run with Blender in background mode. The script discovers the project source
Blends, leaves files without palette materials untouched, removes packed/legacy
palette image datablocks after material nodes are rebound, and saves in place.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


PROJECT_ROOT = Path("/Users/summercards/ShellStorm2")
SHARED_PALETTE = PROJECT_ROOT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
SOURCE_ROOTS = (
    PROJECT_ROOT / "assets/art/environments",
    PROJECT_ROOT / "assets/art/props/base_world_3d",
)
PALETTE_TOKENS = ("多巴胺色盘", "palette_dopamine")


def is_palette_image(image: bpy.types.Image | None) -> bool:
    if image is None:
        return False
    descriptor = "%s|%s|%s" % (image.name, image.filepath, image.filepath_raw)
    return any(token.lower() in descriptor.lower() for token in PALETTE_TOKENS)


def script_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify", action="store_true", help="audit all Blend sources without saving")
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    return parser.parse_args(argv)


def palette_node_issues(palette_nodes: list[bpy.types.ShaderNodeTexImage]) -> list[str]:
    issues: list[str] = []
    expected = SHARED_PALETTE.resolve()
    for node in palette_nodes:
        image = node.image
        if image is None:
            issues.append("%s:missing_image" % node.name)
            continue
        actual = Path(bpy.path.abspath(image.filepath)).resolve()
        if actual != expected:
            issues.append("%s:wrong_path=%s" % (node.name, actual))
        if image.packed_file is not None:
            issues.append("%s:packed_image" % node.name)
        if node.interpolation != "Closest":
            issues.append("%s:filter=%s" % (node.name, node.interpolation))
    return issues


def relink(path: Path, verify_only: bool) -> tuple[int, int, bool]:
    bpy.ops.wm.open_mainfile(filepath=str(path))
    palette_nodes = [
        node
        for material in bpy.data.materials
        if material.use_nodes and material.node_tree is not None
        for node in material.node_tree.nodes
        if node.type == "TEX_IMAGE"
    ]
    if not palette_nodes:
        return 0, 0, False

    issues = palette_node_issues(palette_nodes)
    if verify_only:
        if issues:
            raise RuntimeError("%s: %s" % (path, "; ".join(issues)))
        return len(palette_nodes), 0, False
    if not issues:
        return len(palette_nodes), 0, False

    previous_images = {node.image for node in palette_nodes if node.image is not None}
    shared = next((image for image in previous_images if not image.packed_file and Path(bpy.path.abspath(image.filepath)).resolve() == SHARED_PALETTE.resolve()), None)
    if shared is None:
        shared = bpy.data.images.load(str(SHARED_PALETTE), check_existing=False)
    shared.name = "SCENE_FACILITY_SHARED_PALETTE"
    shared.filepath = bpy.path.relpath(str(SHARED_PALETTE))
    shared.filepath_raw = shared.filepath
    shared.source = "FILE"
    shared.colorspace_settings.name = "sRGB"

    for node in palette_nodes:
        node.image = shared
        node.interpolation = "Closest"
        node.extension = "EXTEND"

    removed = 0
    for image in previous_images:
        if image != shared and image.users == 0:
            bpy.data.images.remove(image)
            removed += 1

    bpy.context.scene["shared_scene_facility_palette"] = "//" + SHARED_PALETTE.relative_to(PROJECT_ROOT).as_posix()
    bpy.context.scene["palette_embedding_policy"] = "external_source; GLB exports omit images"
    bpy.ops.wm.save_as_mainfile(filepath=str(path), compress=True)
    return len(palette_nodes), removed, True


def main() -> None:
    args = script_args()
    if not SHARED_PALETTE.exists():
        raise RuntimeError("Missing shared scene/facility palette: %s" % SHARED_PALETTE)
    paths = sorted({path for root in SOURCE_ROOTS for path in root.rglob("*.blend")})
    palette_files = 0
    changed = 0
    total_nodes = 0
    for path in paths:
        node_count, removed_count, did_change = relink(path, args.verify)
        if node_count:
            palette_files += 1
            total_nodes += node_count
        if did_change:
            changed += 1
            print("SHARED_PALETTE_RELINKED:%s:nodes=%d:removed_images=%d" % (path, node_count, removed_count))
    if args.verify:
        print("SCENE_FACILITY_BLEND_PALETTE_VERIFY_OK:files=%d:nodes=%d" % (palette_files, total_nodes))
    else:
        print("SCENE_FACILITY_BLEND_PALETTE_RELINK_OK:palette_files=%d:changed=%d:nodes=%d" % (palette_files, changed, total_nodes))


if __name__ == "__main__":
    main()
