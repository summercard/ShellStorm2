#!/usr/bin/env python3
"""远征01首关小改的数据只读验收。"""
from __future__ import annotations

import hashlib
import json
import subprocess
import shutil
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "art_source/design/whitebox/tower_zones/expedition_01/v001/data"
RUNTIME_ROOT = ROOT / "data/level_plans/expedition_01"
LEVEL_SOURCE = SOURCE_ROOT / "level_plan.json"
FLOOR_SOURCE = SOURCE_ROOT / "floors/floor_00.json"
LEVEL_RUNTIME = RUNTIME_ROOT / "level_plan.json"
FLOOR_RUNTIME = RUNTIME_ROOT / "floors/floor_00.json"
MANIFEST = ROOT / "data/runtime_design_data_manifest.json"


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def fail(message: str) -> None:
    raise AssertionError(message)


def topology(room: dict) -> dict:
    # 只排除本轮获准调整的战斗字段，其余结构字段必须与基线逐键一致。
    return {
        key: value
        for key, value in room.items()
        if key not in ("spawn_placements", "encounter", "boss_reinforcement_plan")
    }


def baseline_data(relative_path: str) -> dict:
    raw = subprocess.check_output(
        ["git", "show", f"6e4c295a:art_source/design/whitebox/tower_zones/expedition_01/v001/data/{relative_path}"],
        cwd=ROOT,
    )
    return json.loads(raw.decode("utf-8"))


def box_count(box: dict, placement: dict, bound: str = "max") -> int:
    total = 0
    bonus_used = False
    multiplier = int(placement.get("count_multiplier", 1))
    bonus = int(placement.get("count_bonus", 0))
    for spawn in placement.get("spawn_overrides", box.get("spawns", [])):
        count = spawn.get("count", 0)
        if isinstance(count, dict):
            count = int(count.get(bound, count.get("min", 0)))
        count = int(count)
        if count > 0 and spawn.get("type") not in ("elite", "boss"):
            count *= multiplier
            if not bonus_used:
                count += bonus
                bonus_used = True
        total += count
    return total


def encounter_stage_count(stage: dict) -> int:
    return sum(int(monster["count"]) for monster in stage.get("monsters", []))


def validate_runtime_plan() -> None:
    sys.path.insert(0, str(ROOT / "scripts"))
    import workspace_paths as wp
    from verify_encounter_safe_selection import run_isolated

    work = wp.work_path(f"verification/shellstorm-verification.data_validator/{time.time_ns()}/marker").parent
    script = work / "validate.gd"
    script.write_text('''extends Node
func _ready() -> void:
    var plan := FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, 2026, 180)
    var report := {"ok": bool(plan.get("valid", false)), "errors": plan.get("validation_errors", []), "rooms": plan.get("rooms", []).size()}
    var preplaced_rooms := ["room_01", "room_02", "room_05", "room_07", "room_08"]
    var preplaced_count := 0
    for room: Dictionary in plan.get("rooms", []):
        var encounter: Dictionary = room.get("encounter", {})
        var expected: bool = str(room.get("id", "")) in preplaced_rooms
        var actual: bool = encounter.get("spawn_mode", "") == "preplaced"
        if expected != actual:
            report.ok = false
            report.errors.append("preplaced_runtime_projection_mismatch:" + str(room.get("id", "")))
        if actual:
            preplaced_count += 1
    if preplaced_count != 5:
        report.ok = false
        report.errors.append("preplaced_runtime_room_count_mismatch")
    print("EXPEDITION01_VALIDATOR_REPORT " + JSON.stringify(report))
    if bool(report.get("ok", false)):
        print("EXPEDITION01_VALIDATOR_OK")
    get_tree().quit(0 if bool(report.get("ok", false)) else 1)
''', encoding="utf-8")
    scene = work / "validate.tscn"
    scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="' + script.as_posix() + '" id="1"]\n[node name="Validate" type="Node"]\nscript = ExtResource("1")\n', encoding="utf-8")
    executable = shutil.which("godot")
    if not executable:
        fail("找不到Godot，不能跳过真实Validator校验")
    result = run_isolated([executable, "--headless", "--path", str(ROOT), str(scene)], work, "EXPEDITION01_VALIDATOR_OK", 90)
    if result:
        fail(f"真实LevelPlanValidator未通过，日志目录: {work}")


def main() -> None:
    source_level = load(LEVEL_SOURCE)
    source_floor = load(FLOOR_SOURCE)
    runtime_level = load(LEVEL_RUNTIME)
    runtime_floor = load(FLOOR_RUNTIME)
    manifest = load(MANIFEST)

    if source_level != runtime_level or source_floor != runtime_floor:
        fail("设计源与运行投影内容不一致")
    if LEVEL_SOURCE.read_bytes() != LEVEL_RUNTIME.read_bytes() or FLOOR_SOURCE.read_bytes() != FLOOR_RUNTIME.read_bytes():
        fail("设计源与运行投影字节不一致")

    manifest_by_source = {entry["source"]: entry for entry in manifest["files"]}
    for source, runtime in (
        (LEVEL_SOURCE, LEVEL_RUNTIME),
        (FLOOR_SOURCE, FLOOR_RUNTIME),
    ):
        source_key = source.relative_to(ROOT).as_posix()
        runtime_key = runtime.relative_to(ROOT).as_posix()
        entry = manifest_by_source.get(source_key)
        if not entry or entry["runtime"] != runtime_key:
            fail(f"manifest 缺少映射: {source_key}")
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if digest != entry["sha256"]:
            fail(f"manifest SHA 不匹配: {source_key}")

    baseline = baseline_data("floors/floor_00.json")
    baseline_rooms = {room["key"]: room for room in baseline["rooms"]}
    rooms = {room["key"]: room for room in source_floor["rooms"]}
    if len(source_floor["rooms"]) != 13 or len(rooms) != 13:
        fail(f"房间数不是13或存在重复key: {len(source_floor['rooms'])}/{len(rooms)}")
    if [room["key"] for room in source_floor["rooms"]] != [room["key"] for room in baseline["rooms"]]:
        fail("房间key集合或顺序与基线不一致")
    if {key: value for key, value in source_floor.items() if key != "rooms"} != {
        key: value for key, value in baseline.items() if key != "rooms"
    }:
        fail("楼层拓扑/主路/边策略等顶层字段与基线不一致")
    for key, baseline_room in baseline_rooms.items():
        actual, wanted = topology(rooms[key]), topology(baseline_room)
        differences = [field for field in actual.keys() | wanted.keys()
                       if (field in actual) != (field in wanted) or actual.get(field) != wanted.get(field)]
        if differences:
            fail(f"房间结构/内容类型/几何字段与基线不一致: {key}: {','.join(sorted(differences))}")
    ordinary_rooms = ("room_01", "room_02", "room_05", "room_07", "room_08")
    trigger_rooms = ("room_03", "room_04", "room_06", "room_09", "room_10")
    for room_id, room in rooms.items():
        wanted_placements = json.loads(json.dumps(baseline_rooms[room_id].get("spawn_placements", [])))
        if room_id == "room_05":
            wanted_placements[4]["spawn_overrides"] = [
                {"type": "melee_chaser", "count": 8, "delay_sec": 0.0},
                {"type": "fat_zombie03", "count": 4, "delay_sec": 1.0},
                {"type": "ranged_caster", "count": 4, "delay_sec": 1.0},
            ]
        if room.get("spawn_placements", []) != wanted_placements:
            fail(f"盒子实例/位置/数量变化或非授权延迟改动: {room_id}")
        if room_id not in ordinary_rooms + trigger_rooms and room != baseline_rooms[room_id]:
            fail(f"非目标房间发生变化（含Boss完整记录）: {room_id}")
    for room_id in ordinary_rooms:
        wanted = dict(baseline_rooms[room_id]["encounter"])
        wanted["stages"] = [{"boxes": list(range(len(rooms[room_id]["spawn_placements"]))) }]
        wanted["intermission_sec"] = 0.0
        wanted["spawn_mode"] = "preplaced"
        if rooms[room_id]["encounter"] != wanted:
            fail(f"{room_id} 必须完整合并所有盒到唯一stage0并显式间歇0")
        if "trigger" in rooms[room_id]["encounter"]:
            fail(f"{room_id} preplaced只允许普通非trigger盒式房")
    actual_preplaced = {room_id for room_id, room in rooms.items()
                        if room.get("encounter", {}).get("spawn_mode") == "preplaced"}
    if actual_preplaced != set(ordinary_rooms):
        fail(f"preplaced房间集合漂移，禁止影响Boss/trigger: {actual_preplaced}")
    # 原声明可保留；preplaced生产消费必须将全部条目有效延迟归零，不再逐条计时补怪。
    encounter03 = rooms["room_03"]["encounter"]
    wanted03 = dict(baseline_rooms["room_03"]["encounter"])
    wanted03.update({
        "trigger": {"shape": "door_entries", "port_ids": ["A", "B"], "inset_m": 2.0, "depth_m": 3.0},
        "start_delay_sec": 3.0, "preparation_sec": 3.0, "freeze_player_sec": 1.0,
        "remote_spawn_policy": "opposite_entry", "hud_countdown": True,
        "alert_style": "red_eva", "alert_text": "接敌警报",
        "alert_beep_interval_sec": 0.5, "alert_pulse": True,
        "stages": [
            {"monsters": [{"type": "ranged_caster", "count": 1}, {"type": "melee_chaser", "count": 4}]},
            {"monsters": [{"type": "fat_zombie03", "count": 1, "min_player_distance_m": 8.0},
                          {"type": "ranged_caster", "count": 2}, {"type": "melee_chaser", "count": 4}]},
            {"monsters": [{"type": "fat_zombie03", "count": 2}, {"type": "ranged_caster", "count": 2},
                          {"type": "melee_chaser", "count": 4}]},
        ],
    })
    if encounter03 != wanted03:
        fail("room_03 进门准备/封门/追猎/远端/距离/有限clear及5/7/8配置不符")
    for room_id in trigger_rooms:
        if room_id == "room_03":
            continue
        wanted = json.loads(json.dumps(baseline_rooms[room_id]["encounter"]))
        preparation = 2.0 if room_id in ("room_04", "room_10") else 3.0
        red = room_id in ("room_06", "room_09")
        wanted.update({
            "trigger": {"shape": "door_entries", "port_ids": ["A", "B"], "inset_m": 2.0, "depth_m": 3.0},
            "preparation_sec": preparation, "start_delay_sec": preparation, "freeze_player_sec": 0.0,
            "remote_spawn_policy": "opposite_entry", "hud_countdown": True,
            "alert_style": "red_eva" if red else "subtle",
            "alert_text": "警报 · 入侵者逼近" if red else "接敌准备",
            "alert_beep_interval_sec": 0.5 if red else 1.0, "alert_pulse": red,
        })
        if rooms[room_id]["encounter"] != wanted:
            fail(f"{room_id} 入口/准备/冻结/告警配置不符或编成被改变")
    for room_id in trigger_rooms:
        ports = {port["port_id"]: port for port in rooms[room_id]["connection_ports"]}
        if not {"A", "B"}.issubset(ports) or not all(ports[port_id]["target"] for port_id in ("A", "B")):
            fail(f"{room_id} 入口必须引用有效A/B端口")
        if "spawn_origin_port_id" in rooms[room_id]["encounter"]:
            fail(f"{room_id} 不得将远端出生硬绑定固定门")
    print("EXPEDITION01_STRUCTURE_OK baseline=6e4c295a rooms=13 topology=unchanged boxes_and_roster=unchanged boss=unchanged")
    print("EXPEDITION01_FLOW_V2_OK ordinary=01/02/05/07/08 spawn_mode=preplaced single_stage intermission=0 effective_delay=0 trigger=03/04/06/09/10 door_entries=AB")

    expected_stages = {
        "room_01": [6],
        "room_02": [(7, 8)],
        "room_03": [5, 7, 8],
        "room_04": [6, 6],
        "room_05": [31],
        "room_06": [8, 9, 13],
        "room_07": [12],
        "room_08": [(16, 17)],
        "room_09": [8, 11, 13, 16],
        "room_10": [5, 5],
    }
    expected_total = {
        "room_01": (6, 6),
        "room_02": (7, 8),
        "room_03": (20, 20),
        "room_04": (12, 12),
        "room_05": (31, 31),
        "room_06": (30, 30),
        "room_07": (12, 12),
        "room_08": (16, 17),
        "room_09": (48, 48),
        "room_10": (10, 10),
    }
    box_root = ROOT / "data/spawn_boxes"
    expected_overrides = {
        ("room_05", 4): [
            {"type": "melee_chaser", "count": 8, "delay_sec": 0.0},
            {"type": "fat_zombie03", "count": 4, "delay_sec": 1.0},
            {"type": "ranged_caster", "count": 4, "delay_sec": 1.0}],
        ("room_05", 2): [
            {"type": "melee_chaser", "count": 1, "delay_sec": 0.5},
            {"type": "melee_chaser_strong", "count": 1, "delay_sec": 0.0}],
        ("room_07", 0): [
            {"type": "melee_chaser", "count": 1, "delay_sec": 0.5},
            {"type": "melee_chaser_strong", "count": 1, "delay_sec": 0.0}],
        ("room_08", 3): [
            {"type": "melee_chaser", "count": 1, "delay_sec": 0.5},
            {"type": "ranged_caster_strong", "count": 1, "delay_sec": 0.0}],
        ("boss", 0): [
            {"type": "boss", "count": 1, "delay_sec": 0.0},
            {"type": "melee_chaser_strong", "count": 1, "delay_sec": 1.5},
            {"type": "ranged_caster_strong", "count": 1, "delay_sec": 1.5},
            {"type": "summoner", "count": 1, "delay_sec": 3.0}],
    }
    actual_overrides = {(room_id, index): placement["spawn_overrides"]
                        for room_id, room in rooms.items()
                        for index, placement in enumerate(room.get("spawn_placements", []))
                        if "spawn_overrides" in placement}
    if actual_overrides != expected_overrides:
        fail(f"实例强化替换清单/顺序/延迟漂移: {actual_overrides}")
    content_kinds = {}
    boss_kinds = {}
    for room_id, room in rooms.items():
        target = boss_kinds if room_id == "boss" else content_kinds
        for placement in room.get("spawn_placements", []):
            box = load(box_root / f"{placement['box']}.json")
            effective = placement.get("spawn_overrides", box["spawns"])
            used = False
            for spawn in effective:
                kind = spawn["type"]
                if kind == "elite":
                    fail(f"本关仍有唯一精英槽: {room_id}")
                count = spawn["count"]
                count = count["max"] if isinstance(count, dict) else count
                if kind not in ("elite", "boss"):
                    count *= placement.get("count_multiplier", 1)
                    if not used:
                        count += placement.get("count_bonus", 0)
                        used = True
                target[kind] = target.get(kind, 0) + count
        for stage in room.get("encounter", {}).get("stages", []):
            for spawn in stage.get("monsters", []):
                target[spawn["type"]] = target.get(spawn["type"], 0) + spawn["count"]
    if content_kinds != {"melee_chaser": 120, "ranged_caster": 39, "fat_zombie03": 17,
                         "exploder": 6, "melee_chaser_strong": 8, "ranged_caster_strong": 4}:
        fail(f"十内容房逐怪种上界漂移: {content_kinds}")
    if boss_kinds != {"boss": 1, "melee_chaser_strong": 1, "ranged_caster_strong": 1,
                      "summoner": 1, "melee_chaser": 4, "exploder": 1, "ranged_caster": 2}:
        fail(f"Boss本体/强化/召唤者编成漂移: {boss_kinds}")
    print(f"EXPEDITION01_STRONG_SQUAD_OK overrides=5 content_max={content_kinds} boss_max={boss_kinds}")
    content_totals = [0, 0]
    for room_id, expected in expected_stages.items():
        room = rooms[room_id]
        stages = room["encounter"]["stages"]
        actual_stage_bounds = []
        for stage in stages:
            if "monsters" in stage:
                count = encounter_stage_count(stage)
                actual_stage_bounds.append((count, count))
            else:
                placements = room["spawn_placements"]
                actual_stage_bounds.append(tuple(
                    sum(box_count(load(box_root / f"{placements[index]['box']}.json"),
                                  placements[index], bound) for index in stage["boxes"])
                    for bound in ("min", "max")
                ))
        if len(actual_stage_bounds) != len(expected):
            fail(f"{room_id} 波次数 {len(actual_stage_bounds)} != {len(expected)}")
        for index, (actual, wanted) in enumerate(zip(actual_stage_bounds, expected), 1):
            wanted_bounds = wanted if isinstance(wanted, tuple) else (wanted, wanted)
            if actual != wanted_bounds:
                fail(f"{room_id} 第{index}波上下界 {actual} != {wanted_bounds}")
        total = tuple(sum(bounds[index] for bounds in actual_stage_bounds) for index in (0, 1))
        if total != expected_total[room_id]:
            fail(f"{room_id} 总怪数上下界 {total} != {expected_total[room_id]}")
        content_totals[0] += total[0]
        content_totals[1] += total[1]
        print(f"EXPEDITION01_WAVES {room_id} waves={actual_stage_bounds} total={total}")
    if content_totals != [192, 194]:
        fail(f"十内容房总怪数上下界错误: {content_totals}")
    boss_room = rooms["boss"]
    boss_bounds = [tuple(
        sum(box_count(load(box_root / f"{boss_room['spawn_placements'][index]['box']}.json"),
                      boss_room["spawn_placements"][index], bound) for index in stage["boxes"])
        for bound in ("min", "max")
    ) for stage in boss_room["encounter"]["stages"]]
    if boss_bounds != [(4, 4), (5, 5), (1, 2)]:
        fail(f"Boss静态波次漂移: {boss_bounds}")
    print(f"EXPEDITION01_WAVES boss waves={boss_bounds} total=(10, 11) dynamic_excluded=true")

    for room_id in ("room_03", "room_04", "room_06", "room_09", "room_10"):
        encounter = rooms[room_id]["encounter"]
        for key, wanted in (("duration_sec", 0.0), ("completion", "clear"), ("stage_advance", "clear"), ("min_player_distance_m", 6.0)):
            if encounter.get(key) != wanted:
                fail(f"{room_id} {key} != {wanted}")
    expected_trigger = {"room_03": (3.0, 8), "room_04": (2.5, 6), "room_06": (2.5, 10), "room_09": (2.5, 12), "room_10": (2.0, 5)}
    for room_id, (intermission, max_alive) in expected_trigger.items():
        encounter = rooms[room_id]["encounter"]
        if encounter["intermission_sec"] != intermission or encounter["max_alive"] != max_alive:
            fail(f"{room_id} 间歇/存活上限不符")
    first_fat = next(monster for stage in encounter03["stages"] for monster in stage["monsters"]
                     if monster["type"] == "fat_zombie03")
    if first_fat.get("min_player_distance_m") != 8.0:
        fail("room_03 第二波首只胖子最小距离不是8米")
    if rooms["room_02"]["encounter"]["monster_ai"]["alert_share_radius_m"] != 10.0:
        fail("room_02 警戒共享半径不是10米")

    baseline_level = baseline_data("level_plan.json")
    wanted_level = json.loads(json.dumps(baseline_level))
    wanted_guarantee = wanted_level["clear_drops"]["room_guarantees"][0]
    wanted_guarantee["candidate_rooms"] = ["room_02"]
    wanted_guarantee["note"] = source_level["clear_drops"]["room_guarantees"][0]["note"]
    if source_level != wanted_level:
        fail("level_plan除首枪保底候选与说明外必须与基线完整一致；02不得再有additional_weapon")
    guarantee = source_level["clear_drops"]["room_guarantees"][0]
    if guarantee["id"] != "exp01_opening_weapon_or_ammo" or guarantee["candidate_rooms"] != ["room_02"]:
        fail("首枪保底必须沿原ID只命中02")
    if guarantee["weapon_count"] != 1 or guarantee["weapon_grade"] != "blue" or guarantee["items"] != [{"item_id": "item_ammo_pack", "count": 100}]:
        fail("02首枪节点必须恰好蓝枪1把+100弹")
    print("EXPEDITION01_ROOM02_WEAPON_OK candidate=room_02 guarantee=one_blue_standard_gun+100 no_duplicate_additional=true")
    overrides = source_level["clear_drops"]["room_overrides"]
    ammo = sum(grant["count"] for item in overrides.values() for grant in item["grants"] if grant["item_id"] == "item_ammo_pack")
    potions = sum(grant["count"] for item in overrides.values() for grant in item["grants"] if grant["item_id"] == "item_health_potion")
    if ammo + 100 != 2200 or potions != 5:
        fail(f"固定奖励总量错误: ammo={ammo + 100}, potions={potions}")
    guarantee = source_level["clear_drops"]["room_guarantees"][0]
    if guarantee.get("bullet_module_id") != "mod_bullet_standard":
        fail("首枪保底缺少标准弹模块")
    for room_id in ("room_01", "room_02", "room_07", "room_09", "room_10"):
        if overrides[room_id].get("mimic_chance") != 0.0:
            fail(f"{room_id} 未禁用拟态")
    if overrides["room_02"].get("fate_card_chance") != 1.0 or not overrides["room_02"].get("fate_common_offer"):
        fail("room_02 命运保底配置错误")
    weapon = overrides["room_07"].get("additional_weapon", {})
    if weapon != {"weapon_id": "weapon_rifle", "grade": "purple", "bullet_module_id": "mod_bullet_standard"}:
        fail(f"room_07 紫枪配置错误: {weapon}")

    boss = rooms["boss"]["boss_reinforcement_plan"]
    for key, wanted in (("activation_delay_sec", 12.0), ("initial_interval_sec", 9.0), ("count_step", 0), ("max_count_per_round", 3), ("min_interval_sec", 9.0), ("max_reinforcement_alive", 6)):
        if boss.get(key) != wanted:
            fail(f"Boss援军 {key} != {wanted}")

    validate_runtime_plan()
    print("EXPEDITION01_DATA_OK rooms=13 ammo=2200 potions=5 topology=unchanged validator=passed")


if __name__ == "__main__":
    main()
