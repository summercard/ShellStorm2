"""Export Tower02 v004 optimized component GLBs and manifests."""
from __future__ import annotations
import bpy, json, hashlib, struct
from pathlib import Path

ROOT = Path(r"I:/工作项目/shellstrom2/ShellStorm2")
BLEND = Path(bpy.data.filepath)
BASE = ROOT / "assets/art/environments/open_world"
OLD = BASE / "source/tower_02/export/v003"
NEW = BASE / "source/tower_02/export/v004"
COMPONENT_ROOT = BASE / "components/tower_02_v004"
RUNTIME_ROOT = BASE / "runtime/tower_02_v004"

old_manifest = json.loads((OLD / "export_manifest.json").read_text(encoding="utf8"))
old_catalog = json.loads((BASE / "source/tower_02/v003/catalog.json").read_text(encoding="utf8"))
root = bpy.data.collections.get("02_游戏输出_独立资产包_v003")
assert root is not None


def tri(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def export_one(obj, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True,
        export_apply=True, export_yup=True, export_materials="EXPORT",
        export_image_format="NONE", export_texcoords=True, export_normals=True,
        export_tangents=True, export_lights=False, export_cameras=False,
        export_animations=False)
    obj.select_set(False)


def find_obj(record):
    names = record.get("objects", [])
    assert names, record["slug"]
    obj = bpy.data.objects.get(names[0])
    assert obj is not None, names[0]
    assert obj.type == "MESH", names[0]
    return obj

records = []
for old_record in old_manifest["records"]:
    obj = find_obj(old_record)
    slug = old_record["slug"]
    category = old_record["category"]
    glb_rel = Path("assets/art/environments/open_world/components/tower_02_v004") / category / f"{slug}.glb"
    glb = ROOT / glb_rel
    export_one(obj, glb)
    digest = hashlib.sha256(glb.read_bytes()).hexdigest()
    record = dict(old_record)
    record.update(version="v004", source_blend="env_tower_02-v004-runtime.blend",
        glb=glb_rel.as_posix(), glb_sha256=digest, triangle_count=tri(obj),
        runtime_glb=glb_rel.as_posix(),
        runtime_prefab=(Path("assets/art/environments/open_world/runtime/tower_02_v004") / category / f"{slug}.tscn").as_posix())
    records.append(record)

manifest = dict(old_manifest)
manifest.update(version="v004", source="assets/art/environments/open_world/source/tower_02/export/v004/env_tower_02-v004-runtime.blend",
    source_sha256=hashlib.sha256(BLEND.read_bytes()).hexdigest(), derived="", derived_sha256="", records=records,
    optimization={"method":"per-component COLLAPSE decimate", "ratio":0.22, "target_triangles":100000,
                  "source_triangles":406088, "optimized_triangles":sum(r["triangle_count"] for r in records),
                  "modular_boundaries_preserved":True})
NEW.mkdir(parents=True, exist_ok=True)
(NEW / "export_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf8")

catalog = json.loads(json.dumps(old_catalog))
catalog.update(version="v004", source_blend="env_tower_02-v004-runtime.blend", runtime_integrated=False,
    runtime_prefab="assets/art/environments/open_world/runtime/tower_02_v004/env_tower_02_root_top3d.tscn")
lookup = {r["slug"]: r for r in records}
for package in catalog["packages"]:
    r=lookup[package["slug"]]
    package.update(version="v004", source_blend="env_tower_02-v004-runtime.blend", exported=True,
        runtime_glb=r["glb"], runtime_prefab=r["runtime_prefab"], runtime_asset_id=r["asset_id"]+"-V004")
(BASE / "source/tower_02/v004").mkdir(parents=True, exist_ok=True)
(BASE / "source/tower_02/v004/catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+"\n", encoding="utf8")
print(json.dumps({"passed":True,"records":len(records),"triangles":sum(r["triangle_count"] for r in records),"manifest":str(NEW/"export_manifest.json")},ensure_ascii=False))
