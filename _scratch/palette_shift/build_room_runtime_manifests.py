#!/usr/bin/env python3
"""按 skill 04-battle-room-runtime-assembler「房间输出」补齐**逐具体房间**的运行时装配 manifest。

产出（每个房间一份）
  assets/art/environments/tower_zones/expedition/runtime/room_instances/<room_id>/
    room_runtime_manifest.json
    acceptance/replay_verification_log.txt
    acceptance/runtime_material_probe.txt

判定依据（全部可复现）
  - 关卡设计源：source/art/whitebox/tower_zones/expedition_01/v001/data/{level_plan,floors/floor_00}.json
  - 房型模板：  .../data/room_templates/<template_id>.json（尺寸/门契约/墙面车道）
  - 房型布局：  .../source/common_components/v00N/component_instances.json（实例与源哈希）
  - 运行时清单：assets/.../runtime/room_type_components/runtime_manifest.json（PackedScene/包络/碰撞责任）
  - 验收证据：  I:/ss2_iso/room_type_after_import/{replay_verification_log.txt,probe_report.txt,runtime_doors.txt}

门位**以运行时探针实测为准**（`probe_runtime_doors.gd`）：房型源按规范不冻结门位，
且实跑版图由 `FloorPlanGenerator` 按种子现算 ⇒ 静态从兜底样例推导的相邻面只作参考，
不得当作实跑门位。
"""

from __future__ import annotations

import json
import re
import shutil
from pathlib import Path

REPO = Path("I:/工作项目/shellstrom2/ShellStorm2")
LEVEL_DIR = REPO / "source/art/whitebox/tower_zones/expedition_01/v001/data"
RUNTIME_DIR = REPO / "assets/art/environments/tower_zones/expedition/runtime"
COMP_MANIFEST = RUNTIME_DIR / "room_type_components/runtime_manifest.json"
EVIDENCE = Path("I:/ss2_iso/room_type_after_import")
OUT_ROOT = RUNTIME_DIR / "room_instances"

# 运行时换砖口径（skill 04：主层地砖一律换通用棋盘砖）
COMMON_FLOOR_IDS = [
    "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01",
    "ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02",
]

# 房型 → 组件库版本 / 运行时资产 id
ROOM_TYPE_BINDING = {
    "office_60x70": {
        "library_version": "v009",
        "library_room_type": "OFFICE_ROOM",
        "layout_asset_id": "ENV-EXPEDITION-L01-OFFICE-ROOM-TYPE-LAYOUT",
        "component_prefix": "ENV-EXPEDITION-L01-OFFICE-",
    },
    "bridge_60x50": {
        "library_version": "v010",
        "library_room_type": "BRIDGE_ROOM",
        "layout_asset_id": "ENV-EXPEDITION-L01-BRIDGE-ROOM-TYPE-LAYOUT",
        "component_prefix": "ENV-EXPEDITION-L01-BRIDGE-",
    },
    "boss_50x40": {
        "library_version": "v011",
        "library_room_type": "BOSS_ROOM",
        "layout_asset_id": "ENV-EXPEDITION-L01-BOSS-ROOM-TYPE-LAYOUT",
        "component_prefix": "ENV-EXPEDITION-L01-BOSS-",
    },
    "db_70x50": {
        "library_version": "v014",
        "library_room_type": "DB_ROOM",
        "layout_asset_id": "ENV-EXPEDITION-L01-DB-ROOM-TYPE-LAYOUT",
        "component_prefix": "ENV-EXPEDITION-L01-DB-",
    },
    "corridor_45x40": {
        "library_version": "v012",
        "library_room_type": "L_CORRIDOR",
        "layout_asset_id": "ENV-EXPEDITION-L01-CORRIDOR-ROOM-TYPE-LAYOUT",
        "component_prefix": "ENV-EXPEDITION-L01-CORRIDOR-",
    },
}

TARGETS = ["room_01", "room_02", "room_03", "room_05", "room_06", "room_08", "room_09", "room_10", "boss"]
EPS = 1e-6


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def parse_replay_log() -> tuple[dict, dict, str]:
    """从验收日志取 prefabs / plan / runtime 三组权威数字。"""
    text = (EVIDENCE / "replay_verification_log.txt").read_text(encoding="utf-8")
    prefabs = {}
    match = re.search(r"^prefabs loaded=(\d+) instantiated=(\d+) palette_materials=(\d+)", text, re.M)
    if match:
        prefabs = {
            "loaded": int(match.group(1)),
            "instantiated": int(match.group(2)),
            "palette_materials": int(match.group(3)),
        }
    plan, runtime = {}, {}
    for line in text.splitlines():
        match = re.match(r"^plan (\S+)\s+instances=(\d+) roles=(\{.*\})", line)
        if match:
            plan[match.group(1)] = {
                "instances": int(match.group(2)),
                "roles": json.loads(match.group(3)),
            }
        match = re.match(
            r"^runtime (\S+)\s+unresolved=(\d+) floor_tiles=(\d+) room_type=(\d+) doors=(\d+)", line
        )
        if match:
            runtime[match.group(1)] = {
                "unresolved": int(match.group(2)),
                "floor_tiles": int(match.group(3)),
                "room_type_components": int(match.group(4)),
                "doors": int(match.group(5)),
            }
    return {"prefabs": prefabs, "plan": plan, "runtime": runtime}, {}, text


def parse_runtime_doors() -> dict:
    """读运行时门位探针实测结果（**权威门位**）。

    探针：`_scratch/palette_shift/probe_runtime_doors.gd`（RUN_SEED=77001199）。
    房型源按规范不冻结门位，实跑版图由 `FloorPlanGenerator` 按种子现算 ⇒ 一律以本结果为准。
    """
    text = (EVIDENCE / "runtime_doors.txt").read_text(encoding="utf-8")
    rooms: dict[str, dict] = {}
    current: str | None = None
    for line in text.splitlines():
        match = re.match(r"^ROOM (\S+) center=\(([^)]*)\) doors=\[(.*)\]", line)
        if match:
            current = match.group(1)
            rooms[current] = {
                "center_m": [round(float(v), 4) for v in match.group(2).split(",")],
                "declared_sides": [
                    s.strip().strip('"') for s in match.group(3).split(",") if s.strip()
                ],
                "doors": [],
            }
            continue
        match = re.match(
            r"^\s+(\S+)\s+->\s+(\S+)\s+local=\(([^)]*)\)\s+world=\(([^)]*)\)", line
        )
        if match and current is not None:
            rooms[current]["doors"].append(
                {
                    "side": match.group(1),
                    "connect_to": match.group(2),
                    "local_m": [round(float(v), 4) for v in match.group(3).split(",")],
                    "world_m": [round(float(v), 4) for v in match.group(4).split(",")],
                }
            )
    return rooms


def room_rect(entry: dict) -> tuple[float, float, float, float]:
    cx, cy = entry["center_m"]
    sx, sy = entry["size_m"]
    return cx - sx / 2, cx + sx / 2, cy - sy / 2, cy + sy / 2


def door_sides(key: str, entries: dict) -> dict[str, str]:
    """几何推导门位：与主路相邻房共享的那面墙就是门所在面。

    跨语言南北红线（设计页 §4.3）：**平面 `+y` → 南；平面 `−y` → 北**。
    故房间的 **min-y 墙面记作 `north`、max-y 墙面记作 `south`**；
    `+x` → `east`、`−x` → `west`（与 §4.2.1 衔接表逐行一致）。
    """
    result = {}
    ax0, ax1, ay0, ay1 = room_rect(entries[key])
    for other, other_entry in entries.items():
        if other == key:
            continue
        # 只认主路相邻（expo01 是首尾相接的链）
        if other not in ADJACENCY[key]:
            continue
        bx0, bx1, by0, by1 = room_rect(other_entry)
        if abs(ax0 - bx1) < EPS:
            result["west"] = other
        if abs(ax1 - bx0) < EPS:
            result["east"] = other
        # min-y 面朝北、max-y 面朝南
        if abs(ay0 - by1) < EPS:
            result["north"] = other
        if abs(ay1 - by0) < EPS:
            result["south"] = other
    return result


def component_bounds(room_type: str) -> dict:
    manifest = read_json(COMP_MANIFEST)
    out = {}
    for record in manifest["records"]:
        if record.get("room_type") != room_type:
            continue
        out[record["component_id"]] = record
    return out


def envelope_godot(instances: list, bounds: dict) -> dict:
    """Blender 平面 XY/垂直 Z → Godot XZ/垂直 Y：`(bx,by,bz) -> (bx,bz,-by)`。"""
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    for item in instances:
        px, py, pz = item["position_m"]
        gx, gy, gz = float(px), float(pz), -float(py)
        record = bounds.get(item["component_id"])
        if record is None:
            continue
        half = [float(v) / 2.0 for v in record["bounds_size_m_godot"]]
        yaw = int(round(float(item.get("rotation_y_deg", 0.0)))) % 360
        if yaw in (90, 270):
            half[0], half[2] = half[2], half[0]
        for axis, value in enumerate((gx, gy, gz)):
            lo[axis] = min(lo[axis], value - half[axis])
            hi[axis] = max(hi[axis], value + half[axis])
    return {
        "coordinate_contract": "godot_local_xz_vertical_y",
        "min_m": [round(v, 4) for v in lo],
        "max_m": [round(v, 4) for v in hi],
        "size_m": [round(hi[i] - lo[i], 4) for i in range(3)],
        "note": "房间局部坐标下的视觉件包络（含所有 slot_role，不含运行期通用地砖）。",
    }


def main() -> None:
    level = read_json(LEVEL_DIR / "level_plan.json")
    floor = read_json(LEVEL_DIR / "floors/floor_00.json")
    entries = {r["key"]: r for r in floor["rooms"]}
    templates = {
        t.stem: read_json(LEVEL_DIR / "room_templates" / f"{t.stem}.json")
        for t in (LEVEL_DIR / "room_templates").glob("*.json")
    }
    evidence, _, replay_text = parse_replay_log()
    runtime_doors = parse_runtime_doors()

    OUT_ROOT.mkdir(parents=True, exist_ok=True)

    written = []
    for key in TARGETS:
        entry = entries[key]
        template_id = entry["template_id"]
        template = templates[template_id]
        binding = ROOM_TYPE_BINDING[template_id]

        lib_path = (
            REPO
            / "assets/art/environments/tower_zones/expedition/source/common_components"
            / binding["library_version"]
            / "component_instances.json"
        )
        library = read_json(lib_path)
        instances = library["instances"]
        bounds = component_bounds(binding["library_room_type"])

        plan_stats = evidence["plan"].get(key, {})
        runtime_stats = evidence["runtime"].get(key, {})
        resolution = {
            cid: {
                "prefab_path": record["prefab_path"],
                "visual_glb": record["visual_glb"],
                "source_blend": record["source_blend"],
                "collision_owner": record["collision_owner"],
                "collision_policy": record["collision_policy"],
                "bounds_size_m_godot": record["bounds_size_m_godot"],
            }
            for cid, record in bounds.items()
        }

        # 门位以运行时探针实测为准；静态几何推导仅作参考对照。
        static_map = door_sides(key, entries)
        measured = runtime_doors.get(key, {})
        doors = []
        for door in measured.get("doors", []):
            doors.append(
                {
                    "side": door["side"],
                    "side_convention": "平面 +y → 南 / −y → 北（设计页 §4.3 跨语言红线）",
                    "connect_to": door["connect_to"],
                    "aperture_center_local_m": door["local_m"],
                    "aperture_center_world_m": door["world_m"],
                    "local_origin": "房间中心（DungeonRoom3D 原点），Godot 局部 XZ 平面 + Y 竖直",
                    "contract": {
                        "width_m": template["door_contract"]["width_m"],
                        "height_m": template["door_contract"]["height_m"],
                        "clear_floor_gap_m": template["door_contract"]["clear_floor_gap_m"],
                        "bottom_z_m": template["door_contract"]["bottom_z_m"],
                        "lintel_bottom_z_m": template["door_contract"]["lintel_bottom_z_m"],
                    },
                    "carrier": "RoomDoor3D（门扇视觉与开合动画的唯一拥有者）",
                    "wall_owner": "DungeonRoom3D._build_authored_layout_shell"
                    "（按本局门槽 lane 把实墙提升为门墙，门洞处不得有几何）",
                }
            )

        manifest = {
            "schema": "shellstorm2.expedition.room_runtime_manifest.v001",
            "room_id": entry["room_id"],
            "room_key": key,
            "room_type": entry["room_type"],
            "room_role": entry["role"],
            "content_type": entry.get("content_type", ""),
            "assembly_route": "room_type_layout_replay",
            "assembly_route_note": (
                "分支 A0：具体房间白模与房型默认尺寸、门槽与必需设施一致，且 03 的 room_layout "
                "只声明 base_layout（无 instance_overrides）⇒ 直接重放房型 component_instances.json，"
                "不做 Godot 侧第二套手工摆位。"
            ),
            "level": {
                "level_id": level["level_id"],
                "block_id": level["block_id"],
                "floor_index": floor["floor_index"],
                "grid_unit_m": level["grid_unit_m"],
                "wall_thickness_m": level["wall_thickness_m"],
                "visible_wall_height_m": level["visible_wall_height_m"],
                "generator": "res://src/map/FloorPlanGenerator.gd::generate_expedition",
                "geometry_is_generated_at_runtime": True,
            },
            "sources": {
                "whitebox_level_plan": "res://source/art/whitebox/tower_zones/expedition_01/v001/data/level_plan.json",
                "whitebox_floor_plan": "res://source/art/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json",
                "room_template": f"res://source/art/whitebox/tower_zones/expedition_01/v001/data/room_templates/{template_id}.json",
                "template_id": template_id,
                "template_variant": entry.get("template_variant", ""),
                "component_instances": (
                    f"res://assets/art/environments/tower_zones/expedition/source/common_components/"
                    f"{binding['library_version']}/component_instances.json"
                ),
                "component_library_version": binding["library_version"],
                "component_library_room_type": binding["library_room_type"],
                "component_library_source_blend_sha256": library["source_blend_sha256"],
                "rotation_axis": library["rotation_axis"],
                "runtime_component_manifest": (
                    "res://assets/art/environments/tower_zones/expedition/runtime/"
                    "room_type_components/runtime_manifest.json"
                ),
                "component_export_manifest": (
                    "res://assets/art/environments/tower_zones/expedition/runtime/"
                    "room_type_components/export_manifest.json"
                ),
                "component_export_manifest_note": "98 条逐组件 GLB 与 source_sha256/glb_sha256（运行时不加载裸 GLB）",
            },
            "godot_references": {
                "layout_asset_id": binding["layout_asset_id"],
                "component_catalog": "res://assets/art/environments/tower_zones/battle/runtime/shell_component_catalog.json",
                "scene": "res://scenes/ExpeditionLevel01_3D.tscn",
                "room_node_path": f"Blocks/Expedition/{key}",
                "art_root_node": "AuthoredLayoutArtRoot",
                "component_resolution": resolution,
            },
            "assembly": {
                "authored_layout_shell": True,
                "instance_total": len(instances),
                "instance_total_source": "component_instances.validation.instance_count",
                "role_counts_planned": plan_stats.get("roles", {}),
                "role_counts_planned_source": "FloorPlanGenerator 规划记录 + 验收日志 plan 行",
                "runtime_role_counts": {
                    "floor_tile": runtime_stats.get("floor_tiles"),
                    "room_type_component": runtime_stats.get("room_type_components"),
                    "unresolved_instances": runtime_stats.get("unresolved"),
                },
                "envelope_local": envelope_godot(instances, bounds),
                "door_probe": {
                    "probe_scene": "res://_scratch/palette_shift/probe_runtime_doors.tscn",
                    "probe_script": "res://_scratch/palette_shift/probe_runtime_doors.gd",
                    "run_seed": 77001199,
                    "room_center_world_m": measured.get("center_m"),
                    "declared_sides": measured.get("declared_sides", []),
                    "log": "acceptance/runtime_doors.txt",
                },
                "door_apertures_source": (
                    "**运行时探针实测**（probe_runtime_doors.gd，RUN_SEED=77001199）："
                    "房型源按规范不冻结门位，实跑门位由 FloorPlanGenerator 按种子现算（设计页 §4.4），"
                    "故一律以实测为准；静态从兜底样例推导的相邻面只作参考（见 door_apertures_static_reference）。"
                ),
                "door_apertures": doors,
                "door_apertures_static_reference": {
                    "note": "floor_00.json 兜底样例 + 主路主拓扑的几何推导结果，仅供对照，**非**实跑门位。",
                    "sides": static_map,
                },
                "collision_responsibility": {
                    "floor_support": "TowerFloorStage3D（collision_policy=external_floor_support）",
                    "walls_and_props": "逐组件 PackedScene 自带静态碰撞；visual_only 件（门扇/地砖视觉件）无碰撞",
                    "door_passage": "RoomDoor3D（门扇沿 Y 抬升 1.25→4.07 m，门洞处无碰撞）",
                    "runtime_floor_tile_swap": {
                        "policy": "主层地砖一律在运行时换通用棋盘砖",
                        "replacement_ids": COMMON_FLOOR_IDS,
                        "expected_count": runtime_stats.get("floor_tiles"),
                        "pit_bottom_tiles_excluded": key == "room_05",
                    },
                },
            },
            "acceptance": {
                "verification_scene": "res://tests/verification/verify_expedition_room_type_component_replay.tscn",
                "result": "ROOM_TYPE_COMPONENT_REPLAY_OK checks=2051",
                "log": "acceptance/replay_verification_log.txt",
                "material_probe_log": "acceptance/runtime_material_probe.txt",
                "runtime_material_probe_sheet": "res://outputs/room_type_runtime_probe_after_import.png",
                "checks": {
                    "packed_scene_loadable": evidence["prefabs"],
                    "runtime_unresolved_instances": runtime_stats.get("unresolved"),
                    "runtime_door_nodes": runtime_stats.get("doors"),
                    "door_aperture_projection_coverage_pct": 0,
                },
                "level_invocation": "expo01 每局由 ExpeditionLevel01_3D.tscn → TowerDescent3D → FloorPlanGenerator 生成并调用；本房在级别白模中登记为主路房间。",
            },
        }

        room_dir = OUT_ROOT / entry["room_id"]
        (room_dir / "acceptance").mkdir(parents=True, exist_ok=True)
        (room_dir / "room_runtime_manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=1) + "\n", encoding="utf-8"
        )
        shutil.copyfile(EVIDENCE / "replay_verification_log.txt", room_dir / "acceptance/replay_verification_log.txt")
        shutil.copyfile(EVIDENCE / "probe_report.txt", room_dir / "acceptance/runtime_material_probe.txt")
        shutil.copyfile(EVIDENCE / "runtime_doors.txt", room_dir / "acceptance/runtime_doors.txt")
        written.append(str(room_dir / "room_runtime_manifest.json"))

    print("ROOM_RUNTIME_MANIFEST_OK count=%d" % len(written))
    for path in written:
        print("  ", path)


# 主路相邻关系（floor_00.main_path + entry/extraction 两端）
ADJACENCY = {
    "entry": ["room_01"],
    "room_01": ["entry", "room_02"],
    "room_02": ["room_01", "room_03"],
    "room_03": ["room_02", "room_04"],
    "room_04": ["room_03", "room_05"],
    "room_05": ["room_04", "room_06"],
    "room_06": ["room_05", "room_07"],
    "room_07": ["room_06", "room_08"],
    "room_08": ["room_07", "room_09"],
    "room_09": ["room_08", "room_10"],
    "room_10": ["room_09", "boss"],
    "boss": ["room_10", "extraction"],
    "extraction": ["boss"],
}


if __name__ == "__main__":
    main()
