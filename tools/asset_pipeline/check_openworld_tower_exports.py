"""Static roundtrip/export guard complementary to real Godot renderer acceptance."""
import hashlib
import json
import struct
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "assets/art/environments/open_world"
TOWERS = ("tower_02", "tower_03")


def read_json(path: Path) -> dict[str, Any]:
    assert path.is_file(), f"missing JSON: {path}"
    value = json.loads(path.read_text(encoding="utf8"))
    assert isinstance(value, dict), f"JSON root is not an object: {path}"
    return value


def sha256(path: Path) -> str:
    assert path.is_file(), f"missing file for SHA-256: {path}"
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_glb(path: Path) -> dict[str, Any]:
    raw = path.read_bytes()
    assert len(raw) >= 20, f"GLB too small: {path}"
    magic, version, total_length = struct.unpack_from("<4sII", raw, 0)
    assert (magic, version, total_length) == (b"glTF", 2, len(raw)), f"invalid GLB header: {path}"
    json_length, json_kind = struct.unpack_from("<II", raw, 12)
    assert json_kind == 0x4E4F534A, f"first GLB chunk is not JSON: {path}"
    json_end = 20 + json_length
    assert json_end <= len(raw), f"GLB JSON chunk exceeds file: {path}"
    value = json.loads(raw[20:json_end].decode("utf8").rstrip(" \t\r\n\0"))
    assert isinstance(value, dict), f"GLB JSON root is not an object: {path}"
    return value


def primitive_triangle_count(data: dict[str, Any], primitive: dict[str, Any], path: Path) -> int:
    mode = int(primitive.get("mode", 4))
    assert mode == 4, f"non-triangle primitive mode {mode}: {path}"
    attributes = primitive.get("attributes", {})
    assert "TEXCOORD_0" in attributes, f"missing TEXCOORD_0: {path}"
    accessors = data.get("accessors", [])
    if "indices" in primitive:
        accessor_index = int(primitive["indices"])
        accessor = accessors[accessor_index]
        count = int(accessor["count"])
        component_type = int(accessor["componentType"])
        assert component_type in (5121, 5123, 5125), f"invalid index component type: {path}"
    else:
        position_accessor_index = int(attributes["POSITION"])
        count = int(accessors[position_accessor_index]["count"])
    assert count % 3 == 0, f"triangle index/vertex count is not divisible by 3: {path}"
    return count // 3


def glb_triangle_count(data: dict[str, Any], path: Path) -> int:
    triangles = 0
    for mesh in data.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            triangles += primitive_triangle_count(data, primitive, path)
    return triangles


def check_tower(slug: str) -> dict[str, Any]:
    runtime_manifest = read_json(BASE / "runtime" / slug / "asset_manifest.json")
    version = str(runtime_manifest["version"])
    manifest_path = BASE / "source" / slug / "export" / version / "export_manifest.json"
    manifest = read_json(manifest_path)
    assert manifest.get("version") == version, f"export version mismatch: {slug}"
    export_source = str(manifest["source"])
    assert sha256(ROOT / export_source) == manifest["source_sha256"], f"export source SHA-256 mismatch: {slug}"
    runtime_source = str(runtime_manifest["source"])
    runtime_source_sha256 = str(runtime_manifest["source_sha256"])
    assert sha256(ROOT / runtime_source) == runtime_source_sha256, f"runtime source SHA-256 mismatch: {slug}"
    source_sha256 = str(manifest["source_sha256"])
    derived = str(runtime_manifest.get("derived", manifest.get("derived", "")))
    derived_sha256 = str(runtime_manifest.get("derived_sha256", manifest.get("derived_sha256", "")))
    if derived:
        assert derived_sha256, f"derived SHA-256 missing: {slug}"
        assert sha256(ROOT / derived) == derived_sha256, f"derived SHA-256 mismatch: {slug}"

    catalog = read_json(BASE / "source" / slug / version / "catalog.json")
    frozen = {str(record["slug"]): record for record in catalog["packages"]}
    component_evidence: list[dict[str, Any]] = []
    actual_total = 0
    manifest_total = 0
    for record_value in manifest["records"]:
        record = record_value
        record_slug = str(record["slug"])
        runtime_glb = str(record.get("stable_glb", record.get("runtime_glb", record["glb"])))
        glb_path = ROOT / runtime_glb
        data = parse_glb(glb_path)
        assert not data.get("images") and not data.get("textures") and not data.get("animations"), f"unexpected GLB payload: {record_slug}"
        assert not data.get("cameras") and not data.get("extensions", {}).get("KHR_lights_punctual"), f"unexpected GLB extras: {record_slug}"
        assert len(data.get("materials", [])) <= 4, f"too many materials: {record_slug}"
        actual_triangles = glb_triangle_count(data, glb_path)
        manifest_triangles = int(record["triangle_count"])
        assert actual_triangles == manifest_triangles, f"GLB triangle count mismatch {record_slug}: actual={actual_triangles} manifest={manifest_triangles}"
        expected = frozen[record_slug]
        assert all(abs(float(a) - float(b)) < 0.01 for a, b in zip(record["bounds_blender"][0], expected["bounds_min"])), f"minimum bounds mismatch: {record_slug}"
        assert all(abs(float(a) - float(b)) < 0.01 for a, b in zip(record["bounds_blender"][1], expected["bounds_max"])), f"maximum bounds mismatch: {record_slug}"
        prefab_path = ROOT / str(record.get("runtime_prefab", record["prefab"]))
        assert prefab_path.is_file(), f"missing component prefab: {record_slug}"
        glb_sha256 = sha256(glb_path)
        assert glb_sha256 == record["glb_sha256"], f"GLB SHA-256 mismatch: {record_slug}"
        actual_total += actual_triangles
        manifest_total += manifest_triangles
        component_evidence.append({
            "slug": record_slug,
            "version": record.get("version", version),
            "derived": record.get("derived", derived),
            "derived_sha256": record.get("derived_sha256", derived_sha256),
            "glb": runtime_glb,
            "glb_sha256": glb_sha256,
            "tscn": str(prefab_path.relative_to(ROOT)).replace("\\", "/"),
            "tscn_sha256": sha256(prefab_path),
            "actual_triangle_count": actual_triangles,
            "manifest_triangle_count": manifest_triangles,
        })

    assert actual_total == manifest_total, f"tower triangle total mismatch: {slug}"
    if "triangles_glb" in manifest:
        assert actual_total == int(manifest["triangles_glb"]), f"top-level GLB triangle total mismatch: {slug}"
    if "triangle_count" in manifest:
        assert actual_total == int(manifest["triangle_count"]), f"top-level triangle total mismatch: {slug}"
    assert len(manifest["records"]) == int(runtime_manifest.get("component_count", len(manifest["records"]))), f"component count mismatch: {slug}"
    root_prefab = ROOT / str(runtime_manifest.get("prefab", manifest.get("runtime_prefab", "")))
    assert root_prefab.is_file(), f"missing tower root prefab: {slug}"
    root_tscn_sha256 = sha256(root_prefab)
    return {
        "tower": slug,
        "version": version,
        "source": export_source,
        "source_sha256": source_sha256,
        "runtime_source": runtime_source,
        "runtime_source_sha256": runtime_source_sha256,
        "derived": derived,
        "derived_sha256": derived_sha256,
        "tscn": str(root_prefab.relative_to(ROOT)).replace("\\", "/"),
        "tscn_sha256": root_tscn_sha256,
        "components": len(manifest["records"]),
        "triangles_actual": actual_total,
        "triangles_manifest": manifest_total,
        "component_evidence": component_evidence,
    }


counts = [check_tower(slug) for slug in TOWERS]
print("OPENWORLD_TOWER_EXPORTS_OK", json.dumps(counts, ensure_ascii=False))
