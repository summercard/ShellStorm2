#!/usr/bin/env python3
"""远征01首关小改的数据只读验收。"""
from __future__ import annotations

import hashlib
import json
import subprocess
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


def baseline_floor() -> dict:
    raw = subprocess.check_output(
        ["git", "show", "46c1ca78:art_source/design/whitebox/tower_zones/expedition_01/v001/data/floors/floor_00.json"],
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


def main() -> None:
    source_level = load(LEVEL_SOURCE)
    source_floor = load(FLOOR_SOURCE)
    runtime_level = load(LEVEL_RUNTIME)
    runtime_floor = load(FLOOR_RUNTIME)
    manifest = load(MANIFEST)

    if source_level != runtime_level or source_floor != runtime_floor:
        fail("设计源与运行投影内容不一致")

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

    baseline = baseline_floor()
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
    print("EXPEDITION01_STRUCTURE_OK baseline=46c1ca78 rooms=13 room_type/content_type及所有非战斗结构字段一致")

    expected_stages = {
        "room_01": [4, 2],
        "room_02": [3, (4, 5)],
        "room_03": [1, 8, 11],
        "room_04": [6, 6],
        "room_05": [6, 16, 9],
        "room_06": [8, 9, 13],
        "room_07": [4, 8],
        "room_08": [7, (6, 7), 3],
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
    print(f"EXPEDITION01_STRONG_SQUAD_OK overrides=4 content_max={content_kinds} boss_max={boss_kinds}")
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
    if rooms["room_03"]["encounter"]["stages"][0]["monsters"][0]["min_player_distance_m"] != 8.0:
        fail("room_03 首只胖子最小距离不是8米")
    if rooms["room_02"]["encounter"]["monster_ai"]["alert_share_radius_m"] != 10.0:
        fail("room_02 警戒共享半径不是10米")

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

    print("EXPEDITION01_DATA_OK rooms=13 ammo=2200 potions=5 topology=unchanged")


if __name__ == "__main__":
    main()
