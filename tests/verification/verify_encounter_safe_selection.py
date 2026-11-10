"""抽取生产 Room/Host 函数，在工程外最小 Godot 工程验证空间与派发事务。"""
import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import workspace_paths as wp


def extract(source, name):
    match = re.search(r'^func ' + name + r'\([\s\S]*?(?=^func |\Z)', source, re.M)
    if not match:
        raise AssertionError(f'找不到生产函数：{name}')
    return match[0].rstrip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot', default=shutil.which('godot'))
    args = parser.parse_args()
    work = wp.work_path('probes/2026-11-11_encounter_safe_selection/harness/project.godot').parent
    room = (ROOT / 'src/world3d/DungeonRoom3D.gd').read_text(encoding='utf-8')
    host = (ROOT / 'src/world3d/EncounterEventHost3D.gd').read_text(encoding='utf-8')
    room_names = ['_build_spawn_points', '_spawn_clearance', '_spawn_floor_contains',
                  '_collect_spawn_blockers', '_spawn_obstacle_free', 'spawn_point_for_index',
                  '_spawn_reach_key', '_spawn_reach_contains',
                  'choose_safe_spawn_position', 'is_safe_spawn_position_valid',
                  '_prepare_safe_spawn_selection', '_safe_spawn_geometry_valid',
                  '_safe_spawn_distances_valid', '_spawn_candidate_score']
    constants = '\n'.join(re.findall(r'^const (?:SPAWN_CLEARANCE_M|SPAWN_BOSS_CLEARANCE_M|SPAWN_BODY_HEIGHT_M|SPAWN_GROUND_TOP_MAX_M|SPAWN_MAX_POINTS|SPAWN_REACH_GRID_M) := .+$', room, re.M))
    room_code = constants + '''
var room_id := "test_room"
var room_type := "COMBAT"
var room_seed := 11
var custom_dimensions := Vector2(30, 30)
var authored_layout_instances: Array = []
var enemy_spawn_points: Array[Vector3] = []
var _authored_tile_cells: Array[Vector3] = []
var _spawn_candidates: Array[Vector3] = []
var _spawn_edge_candidates: Array[bool] = []
var _spawn_available: Array[int] = []
var _spawn_blockers: Array[AABB] = []
var _spawn_reach_active := false
var _spawn_reach_cells: Dictionary = {}
func get_dimensions() -> Vector2:
	return custom_dimensions
func is_streamed() -> bool:
	return true
func _ensure_spawn_reach() -> void:
	pass
'''
    room_code += '\n\n'.join(extract(room, n) for n in room_names)
    host_code = '''var dungeon: FakeDungeon
var _elite_spawn_serial := 0
var MonsterAIManager = null
var settlements := 0
func _valid() -> bool:
	return true
func _settle_unspawned_elites(configs: Array) -> void:
	settlements += configs.size()
'''
    host_code += extract(host, 'encounter_event_spawn').replace('as DungeonRoom3D', 'as Room').replace('as Enemy3D', 'as FakeEnemy')
    script = 'extends SceneTree\n\nclass Room extends Node3D:\n'
    script += '\n'.join('\t' + line for line in room_code.splitlines())
    script += '\n\nclass Host extends RefCounted:\n'
    script += '\n'.join('\t' + line for line in host_code.splitlines())
    script += '''

class FakeEnemy extends Node3D:
	var ai_state := "idle"

class FakeDungeon extends Node3D:
	var _room_by_id := {}
	var _room_spawn_blocked := {}
	var _enemy_nodes_by_room := {}
	var _alive_by_room := {}
	var player: Node3D
	var visual_theme := {"difficulty_rank": 1}
	var generated := 0
	var mode := "ok"
	var rng := RandomNumberGenerator.new()
	func _record_index(_id: String) -> int:
		return 0
	func _make_box_enemy(_kind, _rank, _index, _room, _reservation) -> Dictionary:
		generated += 1
		rng.randi()
		return {"hp": 1}
	func _spawn_enemy_batch(room, configs, _additive, _reserved, positions) -> int:
		if mode == "negative":
			return -1
		var count: int = configs.size() - (1 if mode in ["partial", "lying"] else 0)
		if not _enemy_nodes_by_room.has(room.room_id):
			_enemy_nodes_by_room[room.room_id] = []
		for index in count:
			var enemy := FakeEnemy.new()
			add_child(enemy)
			enemy.global_position = positions[index]
			_enemy_nodes_by_room[room.room_id].append(enemy)
		_alive_by_room[room.room_id] = int(_alive_by_room.get(room.room_id, 0)) + count
		return configs.size() if mode == "lying" else count

var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var dungeon := FakeDungeon.new()
	root.add_child(dungeon)
	dungeon.position = Vector3(111, 3, -79)
	dungeon.rotation.y = 0.7
	var room := Room.new()
	dungeon.add_child(room)
	room.position = Vector3(30, 2, 50)
	room.rotation.y = -1.2
	room._build_spawn_points()
	var player := Node3D.new()
	dungeon.add_child(player)
	player.global_position = room.to_global(Vector3.ZERO)
	dungeon.player = player
	dungeon._room_by_id[room.room_id] = room
	var host := Host.new()
	host.dungeon = dungeon
	var legacy := room.spawn_point_for_index(0)
	var default_pick: Dictionary = room.choose_safe_spawn_position()
	check(default_pick.position.is_equal_approx(legacy), "默认零距离首点保持原评分结果")
	var occupied: Array[Vector3] = []
	for minimum in [8.0, 6.0, 6.0]:
		var pick: Dictionary = room.choose_safe_spawn_position(player.global_position, minimum, occupied)
		check(pick.ok, "旋转平移根节点下可选安全点")
		check(room.is_safe_spawn_position_valid(pick.position, player.global_position, minimum, occupied), "世界距离/跨批占位校验一致")
		occupied.append(pick.position)
	var limited: Array[Vector3] = [room.to_global(Vector3(8, 0, 0))]
	check(room.choose_safe_spawn_position(player.global_position, 6, [], limited).ok, "授权盒候选可选")
	check(not room.choose_safe_spawn_position(limited[0], 6, [], limited).ok, "授权盒不足不得扩域")
	check(room.choose_safe_spawn_position(player.global_position, 6, [], limited).ok, "玩家离开后同域可安全重试")
	var old_batch: Array[Vector3] = []
	for index in 24:
		old_batch.append(room.spawn_point_for_index(index))
	check(old_batch.size() == 24 and old_batch[23].is_finite(), "旧索引路径24只仍可用")
	check(not room.choose_safe_spawn_position(player.global_position, 6, [], []).ok, "空授权域不回退")
	check(not room.is_safe_spawn_position_valid(room.to_global(Vector3(0, 2, 0))), "错误高度拒绝")
	check(not room.is_safe_spawn_position_valid(room.to_global(Vector3(16, 0, 0))), "房外拒绝")
	var body := StaticBody3D.new()
	room.add_child(body)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	body.position = Vector3(8, 1, 0)
	check(not room.is_safe_spawn_position_valid(limited[0]), "同帧真实碰撞体阻挡")
	body.free()
	var initial_rng := dungeon.rng.state
	var retry: Dictionary = host.encounter_event_spawn("event", room.room_id, {"type":"melee_chaser", "min_player_distance_m":1000}, 2)
	check(retry.ok and retry.spawned == 0 and retry.retryable, "暂时无点返回可重试零生成")
	check(dungeon.generated == 0 and dungeon.rng.state == initial_rng and host._elite_spawn_serial == 0, "预选失败不生成数值不耗编成RNG不预约")
	var first: Dictionary = host.encounter_event_spawn("event", room.room_id, {"type":"fat_zombie03", "min_player_distance_m":8}, 1)
	check(first.ok and first.spawned == 1, "03首胖8米生成")
	var prior: Array = dungeon._enemy_nodes_by_room[room.room_id].duplicate()
	var next: Dictionary = host.encounter_event_spawn("event", room.room_id, {"type":"melee_chaser", "min_player_distance_m":6}, 2)
	check(next.ok and next.spawned == 2, "跨怪种批次/容量补发生成")
	var nodes: Array = dungeon._enemy_nodes_by_room[room.room_id]
	occupied.clear()
	for node in nodes:
		check(room.is_safe_spawn_position_valid(node.global_position, player.global_position, 6, occupied), "存活实体位置不重叠")
		occupied.append(node.global_position)
	var before_alive: int = dungeon._alive_by_room[room.room_id]
	prior = nodes.duplicate()
	for mode in ["partial", "lying", "negative"]:
		dungeon.mode = mode
		var failed: Dictionary = host.encounter_event_spawn("event", room.room_id, {"type":"elite"}, 2)
		check(not failed.ok and failed.spawned == 0, "交付失败不认spawned：" + mode)
		check(dungeon._alive_by_room[room.room_id] == before_alive and dungeon._enemy_nodes_by_room[room.room_id] == prior, "回滚保留先前批次与存活账：" + mode)
	check(host.settlements == 6, "失败批次全部精英预约结算")
	var bridge := Room.new()
	dungeon.add_child(bridge)
	bridge.authored_layout_instances = [{"slot_role":"floor_tile", "position":Vector3(2.5,0,2.5)}]
	bridge._build_spawn_points()
	check(not bridge.is_safe_spawn_position_valid(bridge.to_global(Vector3(-8,0,0))), "有授权地砖时桥外虚空拒绝")
	check(not bridge.is_safe_spawn_position_valid(bridge.to_global(Vector3(0.5,0,2.5))), "完整占地净距不足拒绝")
	check(bridge.is_safe_spawn_position_valid(bridge.to_global(Vector3(2.5,0,2.5))), "授权地砖内部合法")
	bridge._spawn_reach_active = true
	check(not bridge.is_safe_spawn_position_valid(bridge.to_global(Vector3(2.5,0,2.5))), "可达性Owner拒绝的空腔不能刷怪")
	bridge._spawn_reach_cells[bridge._spawn_reach_key(Vector3(2.5,0,2.5))] = true
	check(bridge.is_safe_spawn_position_valid(bridge.to_global(Vector3(2.5,0,2.5))), "可达格使用原判据放行")
	bridge._spawn_reach_active = false
	bridge.custom_dimensions = Vector2.ONE
	var impossible: Dictionary = bridge.choose_safe_spawn_position()
	check(not impossible.ok and not impossible.retryable and impossible.reason == "spawn_position_failed", "恒无合法空间保留硬失败而非无限重试")
	print("ENCOUNTER_SAFE_SELECTION_OK checks=%d failures=%d" % [checks, failures])
	dungeon.free()
	quit(0 if failures == 0 else 1)
'''
    (work / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="安全选点隔离验证"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
    (work / 'verify.gd').write_text(script, encoding='utf-8')
    command = [args.godot, '--headless', '--path', str(work), '--script', 'verify.gd']
    try:
        result = subprocess.run(command, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=90)
        output = result.stdout + result.stderr
        (work.parent / 'result.log').write_text(output, encoding='utf-8')
        print(output)
        return result.returncode if 'SCRIPT ERROR' not in output else 1
    except subprocess.TimeoutExpired:
        print('最小 harness 超时；不自动重试')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
