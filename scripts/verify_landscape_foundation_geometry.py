import hashlib
import json
import math
import sys
from pathlib import Path


def overlap(a, b):
    return min(a[1], b[1]) - max(a[0], b[0]) > 0.001


def pair_overlap(a, b):
    return overlap(a["x"], b["x"]) and overlap(a["z"], b["z"])


def main():
    if len(sys.argv) != 3:
        raise SystemExit("用法：verify_landscape_foundation_geometry.py <runtime_dump.json> <output.json>")
    dump_path, output_path = map(Path, sys.argv[1:])
    dump = json.loads(dump_path.read_text(encoding="utf-8"))
    project = Path(__file__).resolve().parents[1]
    evidence = dump_path.parent
    errors, checks, objects = [], [], []

    def check(name, passed, detail=None):
        checks.append({"name": name, "passed": bool(passed), "detail": detail})
        if not passed:
            errors.append(name)

    def add(name, entry, kind, target=None):
        objects.append({"name": name, "kind": kind, "target": target,
                        "x": [entry["min"][0], entry["max"][0]],
                        "y": [entry["min"][1], entry["max"][1]],
                        "z": [entry["min"][2], entry["max"][2]],
                        "mesh_boxes": entry.get("mesh_boxes", [])})

    for name, entry in dump["targets"].items():
        add(name, entry, "target", name)
    for name, entry in dump["bridge"].items():
        add(name, entry, "bridge")
    for entry in dump["city"]:
        add(f"City[r{entry['ring']}:i{entry['index']}]", entry, "city")
    components = {entry["name"]: entry for entry in dump["foundation"]}
    for entry in dump["foundation"]:
        name = entry["name"]
        kind = "ground" if name == "OpenWorldGroundPlane" else "remote" if "RemoteSilhouette" in name else "extension" if "Extension" in name else "foundation"
        add(name, entry, kind, entry["metadata"].get("target"))
        meta = entry["metadata"]
        check(name + ":六项metadata", all(key in meta for key in ["target", "top_y", "ground_y", "footprint_source", "material_source", "future_optimization_space"]))
        check(name + ":正尺寸", all(value > 0 for value in entry["size"]))
        check(name + ":top_bottom一致", abs(entry["max"][1] - meta["top_y"]) < 0.002 and abs(entry["min"][1] - meta["bottom_y"]) < 0.002)
        if kind in ("remote", "extension"):
            check(name + ":同一现有城市材质对象", entry.get("city_material_same_object", False))

    check("独立PackedScene加载12项", len(dump["independent_loads"]) == 12 and all(item["loaded"] for item in dump["independent_loads"]))
    check("景观无新增碰撞", dump["landscape_collision_count"] == 0)
    check("完整当前多层主塔", len(dump["main_tower_stages"]) >= 3 and dump["renderer"] != "headless")
    ground = components["OpenWorldGroundPlane"]
    check("地表顶-80厚0.2", abs(ground["max"][1] + 80) < 0.002 and abs(ground["size"][1] - 0.2) < 0.002)
    non_ground = [item for item in objects if item["kind"] != "ground"]
    margins = {
        "west": min(item["x"][0] for item in non_ground) - ground["min"][0],
        "east": ground["max"][0] - max(item["x"][1] for item in non_ground),
        "north": min(item["z"][0] for item in non_ground) - ground["min"][2],
        "south": ground["max"][2] - max(item["z"][1] for item in non_ground),
    }
    check("完整景观包络至少20m余量", min(margins.values()) >= 19.999, margins)

    baseline_path = evidence / "runtime_before.json"
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    check("城市96栋生产布局逐字段不变", dump["city"] == baseline["city"] and len(dump["city"]) == 96)
    city_rows = []
    extensions = {entry["metadata"]["target"]: entry for entry in dump["foundation"] if "Extension" in entry["name"]}
    runtime_city = dump.get("city_runtime_instances", [])
    check("真实渲染器回读96城市", len(runtime_city) == 96)
    for index, entry in enumerate(dump["city"]):
        name = f"City[r{entry['ring']}:i{entry['index']}]"
        original_bottom, top = entry["min"][1], entry["max"][1]
        extension = extensions.get(name)
        needs = original_bottom > -80.001
        check(name + ":仅未接地者补长", (extension is not None) == needs)
        if extension:
            check(name + ":补长接缝", abs(extension["max"][1] - original_bottom) < 0.002 and abs(extension["min"][1] + 80) < 0.002)
            check(name + ":原XZ完全保留", all(abs(extension[key][axis] - entry[key][axis]) < 0.002 for key in ("min", "max") for axis in (0, 2)))
        if len(runtime_city) == 96:
            actual = runtime_city[index]
            check(name + ":真实MultiMesh未改顶部和包络", all(abs(actual[key][axis] - entry[key][axis]) < 0.002 for key in ("min", "max") for axis in (0, 1, 2)))
        city_rows.append({"name": name, "original_top_y": top, "original_bottom_y": original_bottom,
                          "final_visual_top_y": top, "final_visual_bottom_y": min(original_bottom, -80.0),
                          "operation": "独立下延段" if needs else "不动，原底已低于地表", "xz_and_original_instance_unchanged": True})
    for name in ["Tower2", "Tower3", "Skyline08"]:
        check(name + ":完整矩阵不变", dump["targets"][name]["transform"] == baseline["targets"][name]["transform"])
        check(name + ":楼顶和网格包络不变", all(abs(dump["targets"][name][key][axis] - baseline["targets"][name][key][axis]) < 0.002 for key in ("min", "max") for axis in range(3)))
    tower2 = components["Tower2FoundationBox"]
    check("Tower2原底低于地表的非负向下延续", tower2["max"][1] <= dump["tower2_body"]["min"][1] + 0.002 and tower2["size"][1] > 0 and tower2["metadata"].get("positive_extension_required") is False)
    check("Tower2基础排除塔吊", all(abs(tower2[key][axis] - dump["tower2_body"][key][axis]) < 0.002 for key in ("min", "max") for axis in (0, 2)))
    for name, target in [("Tower1FoundationBox", "Tower1"), ("Tower3FoundationBox", "Tower3"), ("Skyline08FoundationBox", "Skyline08")]:
        check(name + ":接原建筑最低点", abs(components[name]["max"][1] - dump["targets"][target]["min"][1]) < 0.002 and abs(components[name]["min"][1] + 80) < 0.002)

    xz_pairs, existing_pairs, separated, intentional, underground, conflicts = [], [], [], [], [], []
    remote_clearances = []
    for index, first in enumerate(non_ground):
        for second in non_ground[index + 1:]:
            if first["kind"] == "remote" or second["kind"] == "remote":
                dx = max(first["x"][0] - second["x"][1], second["x"][0] - first["x"][1], 0)
                dz = max(first["z"][0] - second["z"][1], second["z"][0] - first["z"][1], 0)
                remote_clearances.append({"a": first["name"], "b": second["name"], "xz_gap_m": math.hypot(dx, dz)})
            if not pair_overlap(first, second):
                continue
            pair = {"a": first["name"], "b": second["name"]}
            xz_pairs.append(pair)
            if first["kind"] in ("target", "bridge", "city") and second["kind"] in ("target", "bridge", "city"):
                existing_pairs.append(pair)
                continue
            if not overlap(first["y"], second["y"]):
                separated.append(pair)
                continue
            if first["target"] == second["name"] or second["target"] == first["name"]:
                intentional.append(pair)
                continue
            if min(first["y"][1], second["y"][1]) <= -80.001:
                underground.append(pair)
                continue
            # 非规则建筑先按实际逐mesh包络细筛，避免塔吊整楼大AABB误报。
            a_boxes = first["mesh_boxes"] or [{"min": [first["x"][0], first["y"][0], first["z"][0]], "max": [first["x"][1], first["y"][1], first["z"][1]]}]
            b_boxes = second["mesh_boxes"] or [{"min": [second["x"][0], second["y"][0], second["z"][0]], "max": [second["x"][1], second["y"][1], second["z"][1]]}]
            hits = [(a.get("path"), b.get("path")) for a in a_boxes for b in b_boxes if all(min(a["max"][axis], b["max"][axis]) - max(a["min"][axis], b["min"][axis]) > 0.001 for axis in range(3))]
            if hits:
                pair["mesh_hits"] = hits
                conflicts.append(pair)
            else:
                separated.append(dict(pair, reason="逐mesh包络排除整楼AABB误报"))
    check("新增远景留空净距至少1m", min(item["xz_gap_m"] for item in remote_clearances) >= 1.0, min(remote_clearances, key=lambda item: item["xz_gap_m"]))
    check("无新增地表以上非自身几何包络冲突", not conflicts, conflicts)

    hashes = json.loads((evidence / "baseline_hashes.json").read_text(encoding="utf-8"))
    protected = {key: value for key, value in hashes.items() if "open_world_landscape_foundation/" not in key.replace("\\", "/")}
    changed = [key for key, value in protected.items() if hashlib.sha256((project / key).read_bytes()).hexdigest() != value]
    check("保护正式塔楼场景布局及生产算法", not changed, changed)
    screenshot_checks = []
    if dump.get("screenshots"):
        from PIL import Image
        check("六张真实渲染截图", len(dump["screenshots"]) == 6)
        for shot in dump["screenshots"]:
            image = Image.open(shot["path"]).convert("RGB")
            levels = len(image.resize((160, 100)).getcolors(16000) or [])
            passed = shot["save_error"] == 0 and levels >= 32 and image.width >= 1000
            check(Path(shot["path"]).name + ":真实图像非空分层", passed, {"color_levels": levels, "size": image.size})
            screenshot_checks.append({"path": shot["path"], "color_levels": levels, "size": image.size})
        framing = dump["screenshots"][0].get("framing", [])
        check("整体机位全部景观部件中心在画内", len(framing) == 11 and all(item["in_frame"] for item in framing), framing)
    else:
        check("六张真实渲染截图", False)
    report = {"schema": "shellstorm2.openworld.landscape_foundation.footprint_check.v004", "runtime_probe_dump": str(dump_path),
              "checks": checks, "errors": errors, "result": "pass" if not errors else "fail", "checked_object_count": len(objects),
              "component_count": len(components), "city_layout_count": 96, "city_top_bottom_proof": city_rows,
              "ground_extent": {"x": [ground["min"][0], ground["max"][0]], "z": [ground["min"][2], ground["max"][2]]},
              "ground_top_y": ground["max"][1], "ground_thickness": ground["size"][1], "ground_margins": margins,
              "remote_clearances": remote_clearances, "all_xz_pairs": xz_pairs, "existing_relationships_not_modified": existing_pairs,
              "vertical_or_per_mesh_separated": separated, "intentional_same_target": intentional,
              "underground_overlap_below_ground": underground, "new_above_ground_conflicts": conflicts,
              "protected_file_count": len(protected), "protected_file_changes": changed,
              "geometry_boundary": "XZ及三维AABB，非规则楼体逐mesh包络细筛；未进行三角级相交。地下延续盒的既有城市重叠单列，不冒称全世界无交叠。"}
    output_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"LANDSCAPE_GEOMETRY_CHECK checks={len(checks)} errors={len(errors)} components={len(components)} existing={len(existing_pairs)} underground={len(underground)} new_conflicts={len(conflicts)}")
    for error in errors:
        print("FAIL", error)
    raise SystemExit(1 if errors else 0)


if __name__ == "__main__":
    main()
