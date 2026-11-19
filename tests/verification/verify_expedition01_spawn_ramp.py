#!/usr/bin/env python3
"""远征01 2026-11-16冻结规则、源投影及正式Validator只读验收。"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / 'art_source/design/whitebox/tower_zones/expedition_01/v001/data'
RUNTIME_ROOT = ROOT / 'data/level_plans/expedition_01'
ORDINARY = ('room_01', 'room_02', 'room_05', 'room_07', 'room_08')
TIMED = ('room_03', 'room_04', 'room_06', 'room_09', 'room_10')
COUNTS = {'room_01': (8, 8), 'room_02': (9, 10), 'room_05': (39, 39), 'room_07': (20, 20), 'room_08': (25, 25)}
WAVES = {'room_03': [5, 7, 9, 12], 'room_04': [6, 6, 9, 6], 'room_06': [10, 11, 16, 15], 'room_09': [15, 19, 24, 27], 'room_10': [13, 15, 18, 15]}
# 2026-11-17 业主授权（仅 room_03）：末模板 ×1.5（2/2/4 → 3/3/6），cap 8 → 12（= 最大模板），
# 消除「模板 9 被 cap 8 截成 8+1」的孤儿余量。其余四房仍逐字沿用 2026-11-16 冻结值。
TERMINAL_TEMPLATE_OVERRIDE = {
    'room_03': [{'type': 'fat_zombie03', 'count': 3}, {'type': 'ranged_caster', 'count': 3}, {'type': 'melee_chaser', 'count': 6}],
}
MAX_ALIVE_OVERRIDE = {'room_03': 12}


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def baseline(name):
    # 固定本轮改动前最近提交；不依赖本机备份，也不把当前数据反抄成期望。
    raw = subprocess.check_output(['git', 'show', f'e81c3bc5f22339a9bb4da329bc947a35f3281c25:art_source/design/whitebox/tower_zones/expedition_01/v001/data/{name}'], cwd=ROOT)
    return json.loads(raw.decode('utf-8'))


def check(ok, message):
    if not ok:
        raise AssertionError(message)


def box_count(placement, bound):
    box = load(ROOT / f"data/spawn_boxes/{placement['box']}.json")
    total = 0
    used = False
    for monster in placement.get('spawn_overrides', box['spawns']):
        count = monster['count']
        count = count.get(bound, count.get('min', 0)) if isinstance(count, dict) else count
        if monster['type'] not in ('boss', 'elite') and count > 0:
            count *= placement.get('count_multiplier', 1)
            if not used:
                count += placement.get('count_bonus', 0)
                used = True
        total += count
    return total


def validate_runtime_plan():
    sys.path.insert(0, str(ROOT / 'scripts'))
    import workspace_paths as wp
    base = f'sessions/2026-11-16_exp01_combat/shellstorm-verification/{time.time_ns()}_validator'
    script = wp.work_path(base + '/validate.gd')
    script.write_text('''extends Node
func _ready() -> void:
    var plan := FloorPlanGenerator.generate_from_level_plan("expedition_01", 0, 2026, 180)
    var ok := bool(plan.get("valid", false))
    var errors: Array = plan.get("validation_errors", [])
    var count := 0
    for room: Dictionary in plan.get("rooms", []):
        var encounter: Dictionary = room.get("encounter", {})
        if encounter.get("spawn_mode", "") == "preplaced":
            count += 1
    ok = ok and count == 5 and plan.get("rooms", []).size() == 13
    print("EXPEDITION01_VALIDATOR_REPORT " + JSON.stringify({"ok": ok, "errors": errors, "preplaced": count}))
    get_tree().quit(0 if ok else 1)
''', encoding='utf-8')
    scene = wp.work_path(base + '/validate.tscn')
    scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="' + script.as_posix() + '" id="1"]\n[node name="Validate" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
    executable = os.environ.get('GODOT_BIN') or shutil.which('godot')
    candidate = Path('I:/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe')
    if not executable and candidate.is_file():
        executable = str(candidate)
    check(bool(executable), '找不到Godot，不得跳过真实Validator')
    env = os.environ.copy()
    for name in ('APPDATA', 'LOCALAPPDATA'):
        env[name] = str(wp.work_path(base + '/' + name + '/marker').parent)
    log = wp.work_path(base + '/run.log')
    with log.open('x', encoding='utf-8') as output:
        result = subprocess.run([executable, '--headless', '--path', str(ROOT), str(scene)], cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT, timeout=120)
    text = log.read_text(encoding='utf-8', errors='replace')
    errors = any(x in text for x in ('SCRIPT ERROR', 'Parse Error', 'ERROR:'))
    print(f'EXPEDITION01_VALIDATOR exit={result.returncode} engine_errors={errors} log={log}')
    check(result.returncode == 0 and not errors and 'EXPEDITION01_VALIDATOR_REPORT' in text, '真实Validator未通过')


def main():
    level, floor = load(SOURCE_ROOT / 'level_plan.json'), load(SOURCE_ROOT / 'floors/floor_00.json')
    manifest = {x['source']: x for x in load(ROOT / 'data/runtime_design_data_manifest.json')['files']}
    for name in ('level_plan.json', 'floors/floor_00.json'):
        source, runtime = SOURCE_ROOT / name, RUNTIME_ROOT / name
        check(source.read_bytes() == runtime.read_bytes(), f'源投影字节漂移:{name}')
        entry = manifest[source.relative_to(ROOT).as_posix()]
        check(entry['sha256'] == hashlib.sha256(source.read_bytes()).hexdigest() and entry['runtime'] == runtime.relative_to(ROOT).as_posix(), f'manifest漂移:{name}')
    old_floor = baseline('floors/floor_00.json')
    old_rooms = {r['key']: r for r in old_floor['rooms']}
    rooms = {r['key']: r for r in floor['rooms']}
    check(len(rooms) == 13 and list(rooms) == list(old_rooms), '13房身份或顺序变化')
    check({k:v for k,v in floor.items() if k != 'rooms'} == {k:v for k,v in old_floor.items() if k != 'rooms'}, '楼层拓扑变化')
    for key, room in rooms.items():
        if key not in ORDINARY + TIMED:
            check(room == old_rooms[key], f'Boss/特殊房被修改:{key}')
        else:
            check({k:v for k,v in room.items() if k not in ('encounter','spawn_placements')} == {k:v for k,v in old_rooms[key].items() if k not in ('encounter','spawn_placements')}, f'几何/门/秘密声明变化:{key}')
    for key in ORDINARY:
        room, old = rooms[key], old_rooms[key]
        encounter = room['encounter']
        wanted = dict(old['encounter'], stages=[{'boxes': list(range(len(room['spawn_placements'])))}])
        check(encounter == wanted and encounter['spawn_mode'] == 'preplaced' and encounter['min_player_distance_m'] == 6.0 and encounter['intermission_sec'] == 0.0, f'单波预摆/6m契约变化:{key}')
        if key == 'room_08':
            placements = room['spawn_placements']
            for i, placement in enumerate(placements):
                check(placement.get('rotation_deg', 0) == 0, f'08盒{i}预期为轴对齐')
                clearance = min(room_size / 2 - abs(center) - box_size / 2
                                for room_size, center, box_size in zip(room['size_m'], placement['center_m'], placement['size_m']))
                check(clearance >= 5.0, f'08盒{i}边缘至外墙{clearance:.2f}m，不足5m')
            check([(p['center_m'], p.get('size_m')) for p in placements] == [([-5.0, -7.5], [24.0, 11.0]), ([10.0, 7.5], [15.0, 15.0])], '08必须沿横纵路径保留分离实例域')
            check(room['spawn_placements'][0]['spawn_overrides'] == [{'type':'melee_chaser','count':10,'delay_sec':0.0}, {'type':'exploder','count':2,'delay_sec':0.0}] and room['spawn_placements'][1]['spawn_overrides'] == [{'type':'melee_chaser','count':10,'delay_sec':0.0}, {'type':'ranged_caster','count':2,'delay_sec':0.0}, {'type':'exploder','count':1,'delay_sec':0.0}], '08总数25及M20/R2/X3不得改变')
        else:
            check(len(room['spawn_placements']) > len(old['spawn_placements']), f'未新增分散盒:{key}')
        actual = tuple(sum(box_count(p, bound) for p in room['spawn_placements']) for bound in ('min', 'max'))
        check(actual == COUNTS[key], f'{key}总量{actual}!={COUNTS[key]}')
        for p in room['spawn_placements']:
            box = load(ROOT / f"data/spawn_boxes/{p['box']}.json")
            check(all(not m['type'].endswith('_strong') and m['type'] != 'elite' for m in p.get('spawn_overrides', box['spawns'])), f'普通房残留显式强化:{key}')
        print(f'EXPEDITION01_PREPLACED {key} count={actual} boxes={len(room["spawn_placements"])}')
    for key in TIMED:
        e, old = rooms[key]['encounter'], old_rooms[key]['encounter']
        for field, value in {'duration_sec':40.0,'freeze_player_sec':1.0,'start_delay_sec':2.0,'intermission_sec':0.0,'preparation_sec':0.0,'completion':'clear','stage_advance':'clear','deadline_behavior':'close_dispatch_and_clear','repeat_last_stage':True,'min_player_distance_m':6.0}.items():
            check(e.get(field) == value, f'{key}:{field}冻结规则不符')
        # room_03 的 cap 属 2026-11-17 授权项，单列核对；其余四房仍按冻结值逐字比对。
        frozen_keys = ('duration_sec', 'stages') + (('max_alive',) if key in MAX_ALIVE_OVERRIDE else ())
        check({k:v for k,v in e.items() if k not in frozen_keys} == {k:v for k,v in old.items() if k not in frozen_keys}, f'{key}非授权事件字段变化')
        if key in MAX_ALIVE_OVERRIDE:
            check(e['max_alive'] == MAX_ALIVE_OVERRIDE[key], f'{key}授权cap不符:{e["max_alive"]}')
        check(e['stages'][:2] == old['stages'][:2], f'{key}前两波变化')
        third = e['stages'][2]['monsters']
        strong = [m for m in third if m['type'] == 'fat_zombie03_strong']
        check(strong == [{'type':'fat_zombie03_strong','count':1,'spawn_vfx_asset_id':'VFX-FAT-ENTRY-BREACH-3D'}], f'{key}强化胖子/VFX错误')
        check([m for m in third if m['type'] == 'fat_zombie03'] == [{'type':'fat_zombie03','count':2}], f'{key}普通胖子非严格2')
        original_third = old['stages'][2] if len(old['stages']) > 2 else old['stages'][-1]
        check([m for m in third if not m['type'].startswith('fat_zombie03')] == [m for m in original_third['monsters'] if not m['type'].startswith('fat_zombie03')], f'{key}第三波其它原小怪被改')
        allowed_terminal = TERMINAL_TEMPLATE_OVERRIDE.get(key)
        if allowed_terminal is None:
            check(len(e['stages']) == 4 and e['stages'][3] == old['stages'][-1], f'{key}普通末模板必须保持原末模板')
        else:
            check(len(e['stages']) == 4 and e['stages'][3] == {'monsters': allowed_terminal}, f'{key}授权末模板不符')
        check(sum(m['count'] for s in e['stages'] for m in s['monsters'] if m['type'] == 'fat_zombie03_strong') == 1, f'{key}强化胖子重复')
        counts = [sum(m['count'] for m in s['monsters']) for s in e['stages']]
        check(counts == WAVES[key], f'{key}波次总量漂移:{counts}')
        print(f'EXPEDITION01_TIMED {key} templates={counts} max_alive={e["max_alive"]} repeat=last_only strong_fat=third_once')
    expected = baseline('level_plan.json')
    rules = expected['monster_rules']
    rules['stats']['per_kind']['melee_chaser']['hp'] = 99
    rules['stats']['per_kind']['fat_zombie03']['hp'] = 198
    rules['strong_variant']['chance'] = .03
    rules['strong_variant']['suppressed_rooms'] = list(TIMED)
    rules['strong_variant']['note'] = level['monster_rules']['strong_variant']['note']
    rules['death_explosion']['fat_zombie03']['warning_sec'] = 1.0
    check(level == expected, '关卡非授权规则变化（含伤害、速度、ranged150、Boss18000和奖励）')
    check(99 / 33 == 3 and 198 / 33 == 6, '基准击杀枪数错误')
    validate_runtime_plan()
    print('EXPEDITION01_DATA_OK hp=99/198 chance=0.03 timed=40s boss_and_secret_unchanged=true')


if __name__ == '__main__':
    main()
