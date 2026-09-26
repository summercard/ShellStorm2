"""Probe a room-type source blend: locate every package collection, compare
against its manifest, and report mesh/material/UV readiness for decomposition.

Read-only. Never saves the source.
Usage:
    blender --background --factory-startup --python dump_room_type_packages.py -- <room_dir_rel> <version_suffix>
"""
import bpy
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

argv = sys.argv
args = argv[argv.index("--") + 1:] if "--" in argv else []
ROOM_DIR = ROOT / args[0]
VER = args[1] if len(args) > 1 else ""

def load_package_rows(room_dir, ver):
    """Per-package asset_manifest.json is the richest source; fall back to the
    batch-level catalog/inventory (some batches only ship the batch list)."""
    manifests = sorted(room_dir.glob("**/asset_manifest.json"))
    if manifests:
        rows = []
        for path in manifests:
            row = json.loads(path.read_text(encoding="utf-8"))
            assert row.get("package_id"), "manifest without package_id: %s" % path
            rows.append(row)
        return rows, manifests[0].parent.parent
    candidates = [room_dir / "component_packages" / "catalog.json"]
    if ver:
        candidates.append(room_dir / ("component_packages_%s" % ver) / "catalog.json")
    candidates.append(room_dir / "component_inventory.json")
    for cand in candidates:
        if cand.exists():
            data = json.loads(cand.read_text(encoding="utf-8"))
            return (data["packages"] if isinstance(data, dict) else data), cand
    return None, None


rows, source_of_rows = load_package_rows(ROOM_DIR, VER)
assert rows, "no package list found under " + str(ROOM_DIR)
source_of_rows = source_of_rows.relative_to(ROOT).as_posix()

blend = next(p for p in sorted(ROOM_DIR.glob("*.blend")))
bpy.ops.wm.open_mainfile(filepath=str(blend))
bpy.context.view_layer.update()

print("PROBE_ROOM_DIR %s" % ROOM_DIR.relative_to(ROOT).as_posix(), flush=True)
print("PROBE_BLEND %s" % blend.name, flush=True)
print("PROBE_PACKAGE_LIST %s" % source_of_rows, flush=True)
print("PROBE_DECLARED_PACKAGES %d" % len(rows), flush=True)

# ---- collection tree (top two levels) ----
print("PROBE_COLLECTIONS_TOP", flush=True)
for c in bpy.data.collections:
    if c.name in [x.name for x in bpy.data.collections]:
        pass
roots = [c for c in bpy.data.collections if not any(c.name in [ch.name for ch in p.children] for p in bpy.data.collections)]
for c in roots[:20]:
    kids = [k.name for k in c.children]
    print("  ROOT %s  (%d children)" % (c.name, len(kids)), flush=True)
    for k in kids[:12]:
        print("      - %s" % k, flush=True)
    if len(kids) > 12:
        print("      ... +%d more" % (len(kids) - 12), flush=True)

# ---- object / material census ----
name_to_collection = {}
for c in bpy.data.collections:
    for obj in c.objects:
        name_to_collection.setdefault(obj.name, []).append(c.name)

mesh_objs = [o for o in bpy.data.objects if o.type == "MESH"]
non_mesh = [o for o in bpy.data.objects if o.type != "MESH"]
print("PROBE_OBJECTS mesh=%d non_mesh=%d" % (len(mesh_objs), len(non_mesh)), flush=True)
print("PROBE_NON_MESH_TYPES %s" % json.dumps(sorted({o.type for o in non_mesh})), flush=True)
print("PROBE_MATERIALS %s" % json.dumps(sorted({m.name for m in bpy.data.materials if m}), ensure_ascii=False), flush=True)

missing_uv = [o.name for o in mesh_objs if not o.data.uv_layers]
print("PROBE_MESH_WITHOUT_UV %d %s" % (len(missing_uv), json.dumps(missing_uv[:6], ensure_ascii=False)), flush=True)

# ---- per package check ----
problems = []
collection_by_name = {c.name: c for c in bpy.data.collections}
ok = 0
example = None


def all_mesh(collection):
    out = [o for o in collection.objects if o.type == "MESH"]
    for ch in collection.children:
        out.extend(all_mesh(ch))
    return out


for row in rows:
    cname = row.get("collection")
    if cname is None:
        problems.append({"package_id": row.get("package_id"), "issue": "manifest has no 'collection' key"})
        continue
    col = collection_by_name.get(cname)
    if col is None:
        problems.append({"package_id": row.get("package_id"), "issue": "collection not found: %s" % cname})
        continue
    objs = all_mesh(col)
    if not objs:
        problems.append({"package_id": row.get("package_id"), "issue": "empty package collection"})
        continue
    declared = row.get("objects")
    if declared is not None:
        # batches differ: some list plain names, some list {name, location_m, ...}
        declared_names = {d if isinstance(d, str) else d.get("name") for d in declared}
        actual = {o.name for o in objs}
        if declared_names != actual:
            problems.append({
                "package_id": row.get("package_id"),
                "issue": "object list mismatch",
                "declared": sorted(declared_names - actual)[:4],
                "actual": sorted(actual - declared_names)[:4],
            })
            continue
    no_uv = [o.name for o in objs if not o.data.uv_layers]
    if no_uv:
        problems.append({"package_id": row.get("package_id"), "issue": "mesh without UV: %s" % no_uv[:3]})
        continue
    if example is None:
        lo = [1e9] * 3
        hi = [-1e9] * 3
        for o in objs:
            for v in o.data.vertices:
                w = o.matrix_world @ v.co
                for i in range(3):
                    lo[i] = min(lo[i], w[i])
                    hi[i] = max(hi[i], w[i])
        example = {
            "package_id": row.get("package_id"),
            "collection": cname,
            "mesh_count": len(objs),
            "bbox_lo": [round(x, 4) for x in lo],
            "bbox_hi": [round(x, 4) for x in hi],
            "materials": sorted({m.name for o in objs for m in o.data.materials if m}),
        }
    ok += 1

print("PROBE_PACKAGES_OK %d / %d" % (ok, len(rows)), flush=True)
print("PROBE_PROBLEM_COUNT %d" % len(problems), flush=True)
for p in problems[:25]:
    print("  PROBLEM %s" % json.dumps(p, ensure_ascii=False), flush=True)
print("PROBE_EXAMPLE %s" % json.dumps(example, ensure_ascii=False), flush=True)
print("PROBE_DONE %s" % ROOM_DIR.relative_to(ROOT).as_posix(), flush=True)
