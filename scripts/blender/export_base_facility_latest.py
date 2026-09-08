"""Create version-matched, optimized Base Facility exports for Godot.

Usage (Blender 4.2+):
  blender --background source/art/blender/base_facility_layout/source/base_facility_runtime_layout_hq_v021.blend \\
    --python scripts/blender/export_base_facility_latest.py -- --stage all --kind all

The script resolves the highest source version unless --source is supplied.  It
never edits that source.  It first writes a lean, version-matched Blend under
export/v###/, reopens that Blend, and only then emits GLBs.  Godot wrappers and
the asset ledger consume export_manifest.json in a later explicit import step.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


PROJECT = Path(__file__).resolve().parents[2]
LAYOUT_ROOT = PROJECT / "source/art/blender/base_facility_layout"
SOURCE_ROOT = LAYOUT_ROOT / "source"
EXPORT_ROOT = LAYOUT_ROOT / "export"
COMPONENT_ROOT = PROJECT / "assets/art/environments/base_facility_3d/components"
PALETTE_PATH = PROJECT / "assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"
SOURCE_PATTERN = re.compile(r"^base_facility_runtime_layout_hq_v(\d{3})\.blend$")

# The only floor package refined in the v019-v021 source chain is emitted as a
# separate visual package.  All other current 02-game-output packages belong to
# the independent-facility stream.
FLOOR_SLUGS = {"loft_floor_finish"}
EXPORT_ROOT_COLLECTION = "00_导出优化资产包"


def parse_args() -> argparse.Namespace:
    raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=("prepare", "export", "all"), default="all")
    parser.add_argument("--kind", choices=("remaining_facilities", "floor_visuals", "all"), default="all")
    parser.add_argument("--source", type=Path, help="Explicit source Blend; defaults to the highest v###")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(raw)


def latest_source(explicit: Path | None) -> tuple[Path, str]:
    if explicit is not None:
        path = explicit if explicit.is_absolute() else PROJECT / explicit
        match = SOURCE_PATTERN.match(path.name)
        if not match or not path.is_file():
            raise RuntimeError("--source must name an existing base_facility_runtime_layout_hq_v###.blend")
        return path.resolve(), "v" + match.group(1)
    choices = []
    for path in SOURCE_ROOT.glob("base_facility_runtime_layout_hq_v*.blend"):
        match = SOURCE_PATTERN.match(path.name)
        if match:
            choices.append((int(match.group(1)), path))
    if not choices:
        raise RuntimeError(f"No versioned source Blend found in {SOURCE_ROOT}")
    number, path = max(choices)
    return path.resolve(), f"v{number:03d}"


def scopes(kind: str) -> list[str]:
    return [kind] if kind != "all" else ["remaining_facilities", "floor_visuals"]


def export_blend_path(version: str, scope: str) -> Path:
    return EXPORT_ROOT / version / f"base_facility_runtime_layout_hq-{version}-{scope}.blend"


def export_manifest_path(version: str) -> Path:
    return EXPORT_ROOT / version / "export_manifest.json"


def child_output_collections(package: bpy.types.Collection) -> list[bpy.types.Collection]:
    return [child for child in package.children if "游戏输出" in child.name]


def package_scope(package: bpy.types.Collection) -> str:
    return "floor_visuals" if package.get("资产包键") in FLOOR_SLUGS else "remaining_facilities"


def package_rows(scope: str) -> list[tuple[bpy.types.Collection, bpy.types.Collection]]:
    rows = []
    for package in bpy.data.collections:
        if not package.get("资产包") or package_scope(package) != scope:
            continue
        outputs = child_output_collections(package)
        if not outputs:
            continue
        if len(outputs) != 1:
            raise RuntimeError(f"{package.name} has {len(outputs)} game-output collections; expected exactly one")
        rows.append((package, outputs[0]))
    if not rows:
        raise RuntimeError(f"No authorized {scope} game-output packages in the selected source")
    rows.sort(key=lambda row: row[0].get("资产包键", row[0].name))
    return rows


def recursive_meshes(collection: bpy.types.Collection) -> list[bpy.types.Object]:
    objects = [obj for obj in collection.objects if obj.type == "MESH"]
    for child in collection.children:
        objects.extend(recursive_meshes(child))
    return objects


def triangles(objects: list[bpy.types.Object]) -> int:
    return sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in objects)


def bbox(objects: list[bpy.types.Object]) -> tuple[list[float], list[float]]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    return ([min(point[i] for point in points) for i in range(3)], [max(point[i] for point in points) for i in range(3)])


def clone_mesh(source: bpy.types.Object, destination: bpy.types.Collection) -> bpy.types.Object:
    clone = source.copy()
    clone.data = source.data.copy()
    clone.animation_data_clear()
    clone.parent = None
    clone.matrix_world = source.matrix_world.copy()
    destination.objects.link(clone)
    return clone


def triangulate_and_remove_downward_faces(obj: bpy.types.Object) -> int:
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    world_matrix = obj.matrix_world.to_3x3()
    downward = [face for face in bm.faces if (world_matrix @ face.normal).normalized().z < -0.5]
    removed = len(downward)
    if downward:
        bmesh.ops.delete(bm, geom=downward, context="FACES")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return removed


def enforce_palette_contract(objects: list[bpy.types.Object]) -> None:
    if not PALETTE_PATH.is_file():
        raise RuntimeError(f"Shared palette missing: {PALETTE_PATH}")
    for obj in objects:
        uv = obj.data.uv_layers.get("PaletteUV")
        if uv is None or obj.data.uv_layers.active != uv or not uv.active_render:
            raise RuntimeError(f"{obj.name} must retain active/render PaletteUV")


def clear_to_export_root(root: bpy.types.Collection) -> None:
    keep = set()

    def visit(collection: bpy.types.Collection) -> None:
        keep.add(collection)
        for child in collection.children:
            visit(child)

    visit(root)
    for obj in list(bpy.data.objects):
        if not any(collection in keep for collection in obj.users_collection):
            bpy.data.objects.remove(obj, do_unlink=True)
    for collection in list(bpy.data.collections):
        if collection not in keep:
            bpy.data.collections.remove(collection)


def make_export_blend(source: Path, version: str, scope: str, dry_run: bool) -> dict:
    rows = package_rows(scope)
    planned = [{"slug": package["资产包键"], "collection": package.name, "output_collection": output.name} for package, output in rows]
    target = export_blend_path(version, scope)
    if dry_run:
        return {"scope": scope, "derived_blend": str(target.relative_to(PROJECT)), "packages": planned, "dry_run": True}
    root = bpy.data.collections.new(f"{EXPORT_ROOT_COLLECTION}_{version}_{scope}")
    bpy.context.scene.collection.children.link(root)
    records = []
    for package, output in rows:
        slug = package["资产包键"]
        package_copy = bpy.data.collections.new(package.name)
        package_copy["资产包"] = True
        package_copy["资产包键"] = slug
        package_copy["source_collection"] = package.name
        package_copy["source_output_collection"] = output.name
        output_copy = bpy.data.collections.new("02_游戏输出_整合模型")
        root.children.link(package_copy)
        package_copy.children.link(output_copy)
        copies = [clone_mesh(obj, output_copy) for obj in recursive_meshes(output)]
        if not copies:
            raise RuntimeError(f"{package.name} output collection has no mesh")
        enforce_palette_contract(copies)
        before = triangles(copies)
        removed = sum(triangulate_and_remove_downward_faces(obj) for obj in copies)
        after = triangles(copies)
        minimum, maximum = bbox(copies)
        records.append({
            "slug": slug,
            "collection": package.name,
            "source_output_collection": output.name,
            "objects": [obj.name for obj in copies],
            "triangles_before": before,
            "triangles_after": after,
            "downward_triangles_removed": removed,
            "bbox_blender": {"min": minimum, "max": maximum},
            "forward": package.get("正面方向", "Blender +Y north"),
            "collision": package.get("collision", "regenerate_from_optimized_output"),
        })
    clear_to_export_root(root)
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(target), check_existing=False)
    return {
        "scope": scope,
        "derived_blend": str(target.relative_to(PROJECT)),
        "source_blend": str(source.relative_to(PROJECT)),
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "packages": records,
    }


def load_manifest(version: str) -> dict:
    path = export_manifest_path(version)
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"version": version, "scopes": {}}


def next_glb_path(version: str, scope: str, slug: str) -> Path:
    root = COMPONENT_ROOT / f"env_base99_{scope}_{version}" / slug
    versions = []
    for path in root.glob(f"{slug}_visual_top3d_v*.glb"):
        match = re.search(r"_v(\d{3})\.glb$", path.name)
        if match:
            versions.append(int(match.group(1)))
    return root / f"{slug}_visual_top3d_v{max(versions, default=0) + 1:03d}.glb"


def export_glbs(version: str, scope: str, dry_run: bool) -> list[dict]:
    root = bpy.data.collections.get(f"{EXPORT_ROOT_COLLECTION}_{version}_{scope}")
    if root is None:
        raise RuntimeError(f"Open {export_blend_path(version, scope)} before --stage export")
    exports = []
    for package in root.children:
        slug = package.get("资产包键")
        output = next((child for child in package.children if "游戏输出" in child.name), None)
        objects = recursive_meshes(output) if output else []
        if not slug or not objects:
            raise RuntimeError(f"Invalid optimized package in {root.name}: {package.name}")
        target = next_glb_path(version, scope, slug)
        if dry_run:
            exports.append({"slug": slug, "visual_glb": str(target.relative_to(PROJECT)), "dry_run": True})
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.object.select_all(action="DESELECT")
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.export_scene.gltf(
            filepath=str(target), export_format="GLB", use_selection=True, export_apply=True,
            export_yup=True, export_texcoords=True, export_normals=True, export_tangents=True,
            export_materials="EXPORT", export_image_format="NONE", export_cameras=False,
            export_lights=False, export_animations=False,
        )
        exports.append({
            "slug": slug,
            "visual_glb": str(target.relative_to(PROJECT)),
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
        })
    return exports


def main() -> None:
    args = parse_args()
    source, version = latest_source(args.source)
    if args.stage in {"prepare", "all"}:
        manifest = load_manifest(version)
        for scope in scopes(args.kind):
            if bpy.data.filepath and Path(bpy.data.filepath).resolve() != source:
                bpy.ops.wm.open_mainfile(filepath=str(source))
            manifest["scopes"][scope] = make_export_blend(source, version, scope, args.dry_run)
            print(
                "BASE_FACILITY_EXPORT_PREPARED"
                f":version={version}:scope={scope}"
                f":packages={len(manifest['scopes'][scope]['packages'])}"
                f":dry_run={args.dry_run}"
            )
            if args.dry_run or args.stage != "all":
                continue
            bpy.ops.wm.open_mainfile(filepath=str(export_blend_path(version, scope)))
            manifest["scopes"][scope]["glbs"] = export_glbs(version, scope, False)
        if not args.dry_run:
            export_manifest_path(version).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    elif args.stage == "export":
        if args.kind == "all":
            raise RuntimeError("--stage export requires one explicit --kind")
        exports = export_glbs(version, args.kind, args.dry_run)
        print(f"BASE_FACILITY_GLB_EXPORT:version={version}:scope={args.kind}:packages={len(exports)}:dry_run={args.dry_run}")
        if not args.dry_run:
            manifest = load_manifest(version)
            manifest.setdefault("scopes", {}).setdefault(args.kind, {})["glbs"] = exports
            export_manifest_path(version).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
