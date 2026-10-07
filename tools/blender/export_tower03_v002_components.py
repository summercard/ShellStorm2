"""Export Tower03 v002 optimized components to source/export staging paths.

The optimized Blend must already exist and is reopened by Blender before export.
Stable runtime paths are not touched here; promotion is a separate audited step.
"""
from __future__ import annotations

import bpy
import hashlib
import json
import struct
from pathlib import Path

ROOT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
BASE = ROOT / "assets/art/environments/open_world"
BLEND = BASE / "source/tower_03/export/v002/env_tower_03-v002-runtime_optimized.blend"
OLD_MANIFEST = BASE / "source/tower_03/export/v001/export_manifest.json"
OLD_CATALOG = BASE / "source/tower_03/v001/catalog.json"
NEW_DIR = BASE / "source/tower_03/export/v002"
STAGED_COMPONENTS = NEW_DIR / "staged_components"
STAGED_RUNTIME = NEW_DIR / "staged_runtime"
QA = NEW_DIR / "qa"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def tri(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def glb_json(path: Path):
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", raw, 0)
    assert (magic, version, length) == (b"glTF", 2, len(raw)), path
    chunk_length, chunk_type = struct.unpack_from("<II", raw, 12)
    assert chunk_type == 0x4E4F534A, path
    return json.loads(raw[20:20 + chunk_length])


def export_one(objects, path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_materials="EXPORT",
        export_image_format="NONE", export_texcoords=True, export_normals=True,
        export_tangents=True, export_lights=False, export_cameras=False,
        export_animations=False, export_extras=False,
    )
    bpy.ops.object.select_all(action="DESELECT")


assert Path(bpy.data.filepath).resolve() == BLEND.resolve(), (bpy.data.filepath, BLEND)
assert BLEND.is_file()
old = json.loads(OLD_MANIFEST.read_text(encoding="utf-8"))
old_catalog = json.loads(OLD_CATALOG.read_text(encoding="utf-8"))
assert len(old["records"]) == 217
records = []
for old_record in old["records"]:
    objects = [bpy.data.objects.get(name) for name in old_record["objects"]]
    assert all(obj is not None and obj.type == "MESH" for obj in objects), old_record["slug"]
    slug = old_record["slug"]
    category = old_record["category"]
    staged_rel = Path("assets/art/environments/open_world/source/tower_03/export/v002/staged_components") / category / f"{slug}.glb"
    staged = ROOT / staged_rel
    export_one(objects, staged)
    data = glb_json(staged)
    assert not data.get("images") and not data.get("textures") and not data.get("animations")
    assert not data.get("cameras") and not data.get("extensions", {}).get("KHR_lights_punctual")
    assert len(data.get("materials", [])) <= 4
    assert all(m["name"].startswith(("01_", "02_", "03_", "04_")) for m in data.get("materials", []))
    for mesh in data.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            assert primitive.get("mode", 4) == 4 and "TEXCOORD_0" in primitive["attributes"]
    record = dict(old_record)
    record.update(
        version="v002",
        source_blend="env_tower_03-v002-runtime_optimized.blend",
        glb=staged_rel.as_posix(),
        stable_glb=f"assets/art/environments/open_world/components/tower_03/{slug}/env_tower_03_{slug}_visual_top3d.glb",
        glb_sha256=sha256(staged),
        triangle_count=sum(tri(obj) for obj in objects),
        runtime_glb=staged_rel.as_posix(),
        runtime_prefab=f"assets/art/environments/open_world/runtime/tower_03_v002/{slug}/env_tower_03_{slug}_root_top3d.tscn",
    )
    records.append(record)

manifest = dict(old)
manifest.update(
    version="v002",
    source="assets/art/environments/open_world/source/tower_03/v001/塔楼03_设备天台办公楼_v001.blend",
    source_sha256=old["source_sha256"],
    derived=BLEND.relative_to(ROOT).as_posix(),
    derived_sha256=sha256(BLEND),
    optimization={
        "method": "partitioned per-component COLLAPSE decimate on independent optimized derivative",
        "target_triangles": 100000,
        "source_triangles": sum(r["triangle_count"] for r in old["records"]),
        "optimized_triangles_blend": sum(r["triangle_count"] for r in records),
        "modular_boundaries_preserved": True,
        "walkable_rooftop_policy": "floor clean-only; rails/stairs/vertical access/plant room conservative 0.82; non-walkable details deeper",
        "optimization_qa": "assets/art/environments/open_world/source/tower_03/export/v002/qa/optimization_v002.json",
    },
    records=records,
)
NEW_DIR.mkdir(parents=True, exist_ok=True)
(NEW_DIR / "export_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

catalog = json.loads(json.dumps(old_catalog))
catalog.update(
    version="v002",
    source_blend="env_tower_03-v002-runtime_optimized.blend",
    runtime_integrated=False,
    runtime_prefab="assets/art/environments/open_world/runtime/tower_03_v002/env_tower_03_root_top3d.tscn",
)
lookup = {r["slug"]: r for r in records}
for package in catalog["packages"]:
    record = lookup[package["slug"]]
    package.update(
        version="v002",
        source_blend="env_tower_03-v002-runtime_optimized.blend",
        exported=True,
        runtime_glb=record["glb"],
        runtime_prefab=record["runtime_prefab"],
        runtime_asset_id=record["asset_id"],
    )
(BASE / "source/tower_03/v002").mkdir(parents=True, exist_ok=True)
(BASE / "source/tower_03/v002/catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

report = {
    "passed": True,
    "asset_id": "ENV-OPENWORLD-TOWER03",
    "version": "v002",
    "records": len(records),
    "triangles_after_blend": sum(r["triangle_count"] for r in records),
    "source_sha256": old["source_sha256"],
    "optimized_blend_sha256": sha256(BLEND),
    "staged_component_root": STAGED_COMPONENTS.relative_to(ROOT).as_posix(),
    "stable_paths_untouched": True,
}
(QA / "export_v002.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps(report, ensure_ascii=False))
