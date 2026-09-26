"""Batch-export the expedition office/bridge room-type component packages to stable GLBs.

Run with Blender 4.5+:
  blender --factory-startup --background --python scripts/blender/export_expedition_room_type_components.py -- --project-root <root>
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import bmesh
import bpy


LIBRARIES = (
    ("office_room", "v006"),
    ("bridge_room", "v007"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", required=True)
    argv = []
    if "--" in __import__("sys").argv:
        argv = __import__("sys").argv[__import__("sys").argv.index("--") + 1 :]
    return parser.parse_args(argv)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def selected_output_objects() -> list[bpy.types.Object]:
    roots = [obj for obj in bpy.context.scene.objects if obj.type == "EMPTY" and obj.name.endswith("_组件")]
    output_meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH" and "_输出_" in obj.name]
    if len(roots) != 1:
        raise RuntimeError(f"expected exactly one output root, got {[obj.name for obj in roots]}")
    if not output_meshes:
        raise RuntimeError("component package has no _输出_ mesh")
    selected: list[bpy.types.Object] = [roots[0], *output_meshes]
    for obj in list(selected):
        parent = obj.parent
        while parent is not None:
            if parent not in selected:
                selected.append(parent)
            parent = parent.parent
    return selected


def triangulate_export_meshes(objects: list[bpy.types.Object]) -> int:
    """Triangulate temporary in-memory mesh copies without touching the source .blend."""
    triangle_count = 0
    for obj in objects:
        if obj.type != "MESH":
            continue
        source_mesh = obj.data
        export_mesh = source_mesh.copy()
        export_mesh.name = f"{source_mesh.name}_导出三角化"
        obj.data = export_mesh
        mesh = bmesh.new()
        mesh.from_mesh(export_mesh)
        bmesh.ops.triangulate(mesh, faces=list(mesh.faces))
        mesh.to_mesh(export_mesh)
        mesh.free()
        export_mesh.update()
        triangle_count += len(export_mesh.polygons)
    return triangle_count


def export_component(blend_path: Path, output_path: Path) -> dict[str, object]:
    bpy.ops.wm.open_mainfile(filepath=str(blend_path))
    objects = selected_output_objects()
    source_object_names = [obj.name for obj in objects]
    triangle_count = triangulate_export_meshes(objects)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_tangents=True,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_extras=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
    )
    return {
        "source_blend": blend_path.as_posix(),
        "source_sha256": sha256(blend_path),
        "glb": output_path.as_posix(),
        "glb_sha256": sha256(output_path),
        "selected_objects": source_object_names,
        "mesh_count": sum(1 for obj in objects if obj.type == "MESH"),
        "triangulated_export_copy": True,
        "triangle_count": triangle_count,
    }


def main() -> None:
    args = parse_args()
    root = Path(args.project_root).resolve()
    records: list[dict[str, object]] = []
    for room_slug, version in LIBRARIES:
        source_root = root / "assets/art/environments/tower_zones/expedition/source/common_components" / version
        catalog = json.loads((source_root / "component_catalog.json").read_text(encoding="utf-8"))
        for package in catalog["packages"]:
            slug = package["slug"]
            blend = source_root / "component_packages" / slug / f"{slug}.blend"
            output = (
                root
                / "assets/art/environments/tower_zones/expedition/components/room_type_components"
                / room_slug
                / slug
                / f"{slug}_visual_top3d.glb"
            )
            if not blend.is_file():
                raise FileNotFoundError(blend)
            record = export_component(blend, output)
            record.update({"room_type": catalog["room_type"], "version": version, "component_id": package["component_id"], "slug": slug})
            records.append(record)
            print(f"ROOM_TYPE_COMPONENT_GLB_WRITTEN:{package['component_id']}:{output}")
    manifest_path = root / "assets/art/environments/tower_zones/expedition/runtime/room_type_components/export_manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(
        json.dumps(
            {
                "schema": "shellstorm2.expedition.room_type_component_export.v001",
                "component_count": len(records),
                "records": records,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"ROOM_TYPE_COMPONENT_EXPORT_COMPLETE:{len(records)}:{manifest_path}")


if __name__ == "__main__":
    main()
