import json
import sys
from pathlib import Path


def overlap(a, b):
    return a[0] < b[1] and b[0] < a[1]


def pair_overlap(a, b):
    return overlap(a["x"], b["x"]) and overlap(a["z"], b["z"])


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: verify_landscape_foundation_geometry.py <runtime_dump.json> <output.json>")
    dump_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    dump = json.loads(dump_path.read_text(encoding="utf-8"))
    objects = []

    def add(name, x, z, kind, target=None):
        objects.append({"name": name, "x": list(x), "z": list(z), "kind": kind, "target": target})

    add("Tower1_rooftop_shell", (-50.0, 50.0), (-35.0, 45.0), "target", "Tower1")
    for name, entry in dump["targets"].items():
        add(name, (entry["min"][0], entry["max"][0]), (entry["min"][2], entry["max"][2]), "target", name)
    for name, entry in dump["bridge"].items():
        add(name, (entry["min"][0], entry["max"][0]), (entry["min"][2], entry["max"][2]), "bridge")
    for entry in dump["city"]:
        name = f"City[r{entry['ring']}:i{entry['index']}]"
        add(name, (entry["min"][0], entry["max"][0]), (entry["min"][2], entry["max"][2]), "city")

    for entry in dump["foundation"]:
        metadata = entry.get("metadata", {})
        name = entry["name"]
        if name == "OpenWorldGroundPlane":
            kind = "ground"
        else:
            kind = "remote" if "RemoteSilhouette" in name else "foundation"
        add(name, (entry["min"][0], entry["max"][0]), (entry["min"][2], entry["max"][2]), kind, metadata.get("target"))

    intentional = []
    blocking = []
    all_pairs = []
    for index, first in enumerate(objects):
        for second in objects[index + 1:]:
            if first["kind"] == "ground" or second["kind"] == "ground":
                continue
            if not pair_overlap(first, second):
                continue
            pair = {"a": first["name"], "b": second["name"]}
            all_pairs.append(pair)
            same_target_foundation = (
                first["kind"] == "foundation" and second["kind"] == "target" and first["target"] == second["target"]
            ) or (
                second["kind"] == "foundation" and first["kind"] == "target" and second["target"] == first["target"]
            )
            if same_target_foundation:
                pair["classification"] = "intentional_target_foundation_envelope"
                intentional.append(pair)
            else:
                pair["classification"] = "conservative_aabb_xz_overlap"
                blocking.append(pair)

    measured_objects = [obj for obj in objects if obj["kind"] != "ground"]
    all_bounds = [(obj["x"][0], obj["x"][1], obj["z"][0], obj["z"][1]) for obj in measured_objects]
    min_x = min(item[0] for item in all_bounds)
    max_x = max(item[1] for item in all_bounds)
    min_z = min(item[2] for item in all_bounds)
    max_z = max(item[3] for item in all_bounds)
    margin = 20.25
    report = {
        "schema": "shellstorm2.openworld.landscape_foundation.footprint_check.v003",
        "runtime_probe_dump": str(dump_path),
        "ground_y": -80.0,
        "ground_top_y": -80.0,
        "ground_thickness": 0.2,
        "ground_margin_requirement_m": 20.0,
        "ground_margin_used_m": margin,
        "checked_object_count": len(objects),
        "city_layout_count": len(dump["city"]),
        "checked_objects": objects,
        "ground_extent": {
            "x": [min_x - margin, max_x + margin],
            "z": [min_z - margin, max_z + margin],
        },
        "ground_size": [max_x - min_x + margin * 2.0, 0.2, max_z - min_z + margin * 2.0],
        "intentional_target_foundation_overlaps": intentional,
        "pairwise_aabb_xz_overlap": blocking,
        "pairwise_aabb_xz_overlap_count": len(blocking),
        "all_pairwise_overlap_count_including_intentional": len(all_pairs),
        "triangle_geometry_note": "Only conservative runtime AABB/XZ envelope screening was executed. No triangle-level mesh intersection was run.",
        "result": "blocked_by_conservative_aabb_xz_overlap" if blocking else "pass_for_scene_assembly_aabb_screening",
    }
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"LANDSCAPE_GEOMETRY_CHECK objects={len(objects)} blocking={len(blocking)} intentional={len(intentional)}")


if __name__ == "__main__":
    main()
