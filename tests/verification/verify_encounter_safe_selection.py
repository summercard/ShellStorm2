"""抽取生产 Room/Host 函数，在工程外最小 Godot 工程验证空间与派发事务。"""
import argparse
import os
import time
import psutil
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
    parser.add_argument('--production-boss', action='store_true')
    args = parser.parse_args()
    if args.production_boss:
        output_dir = wp.work_path(f'probes/2026-11-11_boss_walk_surface/production_{time.time_ns()}/marker').parent
        scene = output_dir / 'probe.tscn'
        scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://tests/verification/probe_boss_walk_surface_spawn.gd" id="1"]\n[node name="Probe" type="Node"]\nscript = ExtResource("1")\n', encoding='utf-8')
        command = [args.godot, '--headless', '--path', str(ROOT), str(scene)]
        return run_isolated(command, output_dir, 'BOSS_BOX_PROBE_DONE', 120)
    work = wp.work_path('probes/2026-11-11_encounter_safe_selection/harness/project.godot').parent
    room = (ROOT / 'src/world3d/DungeonRoom3D.gd').read_text(encoding='utf-8')
    host = (ROOT / 'src/world3d/EncounterEventHost3D.gd').read_text(encoding='utf-8')
    room_names = ['_build_spawn_points', '_spawn_clearance', '_spawn_floor_contains',
                  '_collect_spawn_blockers', '_spawn_obstacle_free', '_spawn_surface_contains', 'resolve_enemy_spawn_position', 'spawn_point_for_index',
                  '_spawn_reach_key', '_spawn_reach_contains',
                  'choose_safe_spawn_position', 'is_safe_spawn_position_valid',
                  '_prepare_safe_spawn_selection', '_safe_spawn_geometry_valid',
                  '_safe_spawn_distances_valid', '_spawn_candidate_score',
                  '_placement_vec2', 'get_connection_port_by_id', 'match_door_entry_trigger',
                  'get_encounter_spawn_candidates']
    constants = '\n'.join(re.findall(r'^const (?:SPAWN_CLEARANCE_M|SPAWN_BOSS_CLEARANCE_M|SPAWN_BODY_HEIGHT_M|SPAWN_GROUND_TOP_MAX_M|SPAWN_MAX_POINTS|SPAWN_REACH_GRID_M) := .+$', room, re.M))
    room_code = 'const TOWER_GEOMETRY = {"DOOR_CLEAR_WIDTH_M":2.2}\n' + constants + '''
var room_id := "test_room"
var room_type := "COMBAT"
var room_seed := 11
var connection_ports: Array = []
var custom_dimensions := Vector2(30, 30)
var authored_layout_instances: Array = []
var enemy_spawn_points: Array[Vector3] = []
var _authored_tile_cells: Array[Vector3] = []
var _spawn_candidates: Array[Vector3] = []
var _spawn_edge_candidates: Array[bool] = []
var _spawn_available: Array[int] = []
var _spawn_blockers: Array[AABB] = []
var _spawn_support_triangles: Array[PackedVector3Array] = []
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
	var _reserved_room_spawns := {}
	var _pending_delayed_spawns := {}
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

func add_rectangle(faces: PackedVector3Array, x0: float, x1: float, z0: float, z1: float, y: float) -> void:
	faces.append_array(PackedVector3Array([Vector3(x0,y,z0), Vector3(x0,y,z1), Vector3(x1,y,z1), Vector3(x0,y,z0), Vector3(x1,y,z1), Vector3(x1,y,z0)]))

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
	room.connection_ports = [
		{"port_id":"west", "position_m":[-15.0,0.0], "outward":[-1.0,0.0], "door_width_m":5.0},
		{"port_id":"east", "position_m":[15.0,0.0], "outward":[1.0,0.0], "door_width_m":5.0}]
	var trigger := {"shape":"door_entries", "port_ids":["west","east"], "inset_m":2.0, "depth_m":3.0}
	check(room.match_door_entry_trigger(trigger, room.to_global(Vector3(-12,0,2.4))).port_id == "west", "旋转根下门宽内命中西入口")
	check(room.match_door_entry_trigger(trigger, room.to_global(Vector3(12,0,-2.4))).port_id == "east", "另一入口OR命中")
	check(not room.match_door_entry_trigger(trigger, room.to_global(Vector3(-12,0,2.6))).hit, "门宽外不误命中")
	check(not room.match_door_entry_trigger(trigger, room.to_global(Vector3(-14,0,0))).hit, "尚未内缩不触发")
	check(not room.match_door_entry_trigger(trigger, room.to_global(Vector3.ZERO)).hit, "房心不冒充入口")
	room.connection_ports[0].door_width_m = 0.0
	check(room.match_door_entry_trigger(trigger, room.to_global(Vector3(-12,0,1.0))).hit and not room.match_door_entry_trigger(trigger, room.to_global(Vector3(-12,0,1.2))).hit, "旧零宽端口沿用真实2.2米门洞净宽")
	room.connection_ports[0].door_width_m = 5.0
	for entry in ["west", "east"]:
		var candidates := room.get_encounter_spawn_candidates(entry, "", "opposite_entry")
		check(not candidates.is_empty(), "反入口候选域非空:" + entry)
		for candidate in candidates:
			check(room.to_local(candidate).x >= -0.001 if entry == "west" else room.to_local(candidate).x <= 0.001, "候选不能漏回入口半区")
	var remote_candidates := room.get_encounter_spawn_candidates("west", "east", "opposite_entry")
	check(not remote_candidates.is_empty(), "指定远端端口内侧带有候选")
	for candidate in remote_candidates:
		check(room.to_local(candidate).x >= 4.49, "远端带不扩为整房")
	check(room.get_encounter_spawn_candidates("missing", "", "opposite_entry").is_empty(), "未知入口无候选不回退")
	dungeon.mode = "ok"
	var generated_before := dungeon.generated
	var remote_retry := host.encounter_event_spawn("remote", room.room_id, {"type":"melee_chaser", "trigger_port_id":"west", "remote_spawn_policy":"opposite_entry", "min_player_distance_m":1000}, 8)
	check(remote_retry.ok and remote_retry.spawned == 0 and remote_retry.retryable and dungeon.generated == generated_before, "远端无合法点pending且不耗随机")
	var remote_batch := host.encounter_event_spawn("remote", room.room_id, {"type":"melee_chaser", "trigger_port_id":"west", "spawn_origin_port_id":"east", "remote_spawn_policy":"opposite_entry", "min_player_distance_m":6}, 8)
	check(remote_batch.ok and remote_batch.spawned > 0 and remote_batch.spawned <= 8, "远端安全子批支持容量分批")
	var empty_remote := host.encounter_event_spawn("remote", room.room_id, {"type":"melee_chaser", "trigger_port_id":"missing", "remote_spawn_policy":"opposite_entry"}, 1)
	check(empty_remote.ok and empty_remote.spawned == 0 and empty_remote.retryable, "空远端域必须保留pending不回房心")
	print("ENCOUNTER_SAFE_SELECTION_BASELINE checks=%d failures=%d" % [checks, failures])
	var multi := Room.new()
	dungeon.add_child(multi)
	multi.custom_dimensions = Vector2(80,100)
	multi.room_type = "BOSS"
	multi.position = Vector3(-70,4,0)
	multi.rotation.y = 0.9
	var surface := Node3D.new()
	multi.add_child(surface)
	surface.set_meta("contiguous_top_surface", true)
	var support_body := StaticBody3D.new()
	surface.add_child(support_body)
	var support_shape := CollisionShape3D.new()
	support_body.add_child(support_shape)
	var triangles := PackedVector3Array()
	# 故意在足迹内部留下小孔：中心与四角射线全有地仍必须拒绝。
	add_rectangle(triangles, -12, 0.4, -12, 12, 0)
	add_rectangle(triangles, 0.8, 12, -12, 12, 0)
	add_rectangle(triangles, 0.4, 0.8, -12, 0.4, 0)
	add_rectangle(triangles, 0.4, 0.8, 0.8, 12, 0)
	# 同一个形状中不相连的12米高台，使整体AABB跨高度。
	add_rectangle(triangles, -8, 8, 20, 36, 12)
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(triangles)
	support_shape.shape = concave
	multi._build_spawn_points()
	check(multi.is_safe_spawn_position_valid(multi.to_global(Vector3(-6,0,0))), "跨高度一体形状不能整体封死低平台")
	check(not multi.is_safe_spawn_position_valid(multi.to_global(Vector3(0,0,0))), "中心四角均有地但足迹内部孔洞仍拒绝")
	check(not multi.is_safe_spawn_position_valid(multi.to_global(Vector3(0,0,16))), "同一AABB中的大虚空拒绝")
	check(multi.is_safe_spawn_position_valid(multi.to_global(Vector3(0,12,28))), "给定高台候选相对真实支持面验证")
	check(not multi.is_safe_spawn_position_valid(multi.to_global(Vector3(0,0,28))), "不能用12米高台给0米假落点提供支撑")
	check(not multi.is_safe_spawn_position_valid(multi.to_global(Vector3(0,12.3,28))), "离真实高台超过15厘米拒绝")
	check(multi.resolve_enemy_spawn_position(multi.to_global(Vector3(0,12,28))).is_equal_approx(multi.to_global(Vector3(0,12,28))), "正式显式落点解析保留合法高台高度")
	check(not multi.resolve_enemy_spawn_position(multi.to_global(Vector3(0,30,28))).is_finite(), "显式解析不将低层候选抬到无支撑的30米")
	var wall := StaticBody3D.new()
	surface.add_child(wall)
	var wall_shape := CollisionShape3D.new()
	wall.add_child(wall_shape)
	var wall_mesh := ConcavePolygonShape3D.new()
	wall_mesh.set_faces(PackedVector3Array([Vector3(-6,0,-5), Vector3(-6,3,-5), Vector3(-6,3,5), Vector3(-6,0,-5), Vector3(-6,3,5), Vector3(-6,0,5)]))
	wall_shape.shape = wall_mesh
	check(not multi.is_safe_spawn_position_valid(multi.to_global(Vector3(-6,0,0))), "真正Concave墙不能被当走面放行")
	wall.free()
	var upper_furniture := StaticBody3D.new()
	multi.add_child(upper_furniture)
	upper_furniture.position = Vector3(0,13,28)
	var furniture_shape := CollisionShape3D.new()
	upper_furniture.add_child(furniture_shape)
	furniture_shape.shape = BoxShape3D.new()
	check(not multi.is_safe_spawn_position_valid(multi.to_global(Vector3(0,12,28))), "高台真实家具按候选高度挡住")
	print("ENCOUNTER_SAFE_SELECTION_OK checks=%d failures=%d" % [checks, failures])
	dungeon.free()
	quit(0 if failures == 0 else 1)
'''
    (work / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="安全选点隔离验证"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
    (work / 'verify.gd').write_text(script, encoding='utf-8')
    command = [args.godot, '--headless', '--path', str(work), '--script', 'verify.gd']
    return run_isolated(command, work.parent, 'ENCOUNTER_SAFE_SELECTION_OK', 90)


def run_isolated(command, output_dir, marker, timeout):
    env = os.environ.copy()
    for key in ('APPDATA', 'LOCALAPPDATA', 'HOME', 'USERPROFILE'):
        folder = output_dir / key.lower()
        folder.mkdir(parents=True, exist_ok=True)
        env[key] = str(folder)
    log = output_dir / 'result.log'
    tracked = {}
    code = 124
    residual = []
    with log.open('w', encoding='utf-8') as output:
        process = subprocess.Popen(command, env=env, stdout=output, stderr=subprocess.STDOUT)
        parent = psutil.Process(process.pid)
        tracked[parent.pid] = parent
        deadline = time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                for item in list(tracked.values()):
                    try:
                        tracked.update({p.pid: p for p in item.children(recursive=True)})
                    except psutil.NoSuchProcess:
                        pass
                alive = [p for p in tracked.values() if p.pid != process.pid and p.is_running()]
                if process.poll() is not None and not alive:
                    code = process.returncode
                    break
                try:
                    process.wait(timeout=0.2)
                except subprocess.TimeoutExpired:
                    continue
                if alive:
                    psutil.wait_procs(alive, timeout=0.2)
        finally:
            for item in list(tracked.values()):
                try:
                    tracked.update({p.pid: p for p in item.children(recursive=True)})
                except psutil.NoSuchProcess:
                    pass
            targets = [p for p in tracked.values() if p.is_running()]
            for item in reversed(targets):
                try:
                    item.terminate()
                except psutil.NoSuchProcess:
                    pass
            _, alive = psutil.wait_procs(targets, timeout=3)
            for item in alive:
                try:
                    item.kill()
                except psutil.NoSuchProcess:
                    pass
            _, residual = psutil.wait_procs(alive, timeout=3)
            process.wait(timeout=5)
    text = log.read_text(encoding='utf-8', errors='replace')
    for line in text.splitlines():
        if any(token in line for token in ('ENCOUNTER_', 'SAFE_SELECTION', 'BOSS_BOX', 'FAIL:', 'SCRIPT ERROR', 'ERROR:', 'Parse Error')):
            print(line)
    print('日志', log, '退出码', code, '子树残留', [p.pid for p in residual])
    return 0 if code == 0 and marker in text and not residual and not any(t in text for t in ('SCRIPT ERROR', 'ERROR:', 'FAIL:')) else 1


if __name__ == '__main__':
    raise SystemExit(main())
