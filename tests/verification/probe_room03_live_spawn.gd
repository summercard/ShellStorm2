extends Node

## 一次性探针（业主 2026-10-21）：
##   「room03 手动调整布局后，刷怪会刷在角色去不了的地方。」
##
## 这个探针只回答一件事：**这间房到底出不出怪、出几只、落在哪。**
## 它直接走真实开战入口 `Dungeon3D._spawn_room_enemies(room)`，不做任何模拟。
##
## 用法：
##   godot --headless --path . res://tests/verification/probe_room03_live_spawn.tscn
##   SS2_ROOM=room_03

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 60.0

var _tower: TowerDescent3D = null
var _room: DungeonRoom3D = null


func _ready() -> void:
	var want_room := OS.get_environment("SS2_ROOM")
	if want_room.is_empty():
		want_room = "room_03"
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	var seed_env := OS.get_environment("SS2_SEED")
	if not seed_env.is_empty():
		tower.run_seed_override = int(seed_env)
	_tower = tower
	add_child(tower)

	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var rooms := tower.get("_rooms") as Array
		if rooms != null and rooms.size() >= 4:
			break
	_find_room(want_room)
	print("")
	print("=== 实战刷怪核对  room=%s ===" % want_room)
	if _room == null:
		print("**找不到房间**")
		print("LIVE_SPAWN_PROBE_END")
		get_tree().quit(0)
		return
	_room.ensure_shell_built()
	_room.ensure_detail_built()
	for _i in range(4):
		await get_tree().physics_frame
	print("spawn_boxes_only=%s  spawn_placements=%d  encounter.stages=%d" % [
		str(_room.spawn_boxes_only),
		(_room.spawn_placements as Array).size(),
		(_room.encounter.get("stages", []) as Array).size() if _room.encounter != null else -1,
	])
	var before := _count_enemies()
	var spawned := bool(_tower.call("_spawn_room_enemies", _room))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after := _count_enemies()
	var alive: Variant = (_tower.get("_alive_by_room") as Dictionary).get(_room.room_id, null)
	print("_spawn_room_enemies → %s；场内敌人 %d → %d；_alive_by_room=%s" % [
		str(spawned), before, after, str(alive)
	])
	print("LIVE_SPAWN_PROBE_END")
	get_tree().quit(0)


func _count_enemies() -> int:
	return get_tree().get_nodes_in_group("enemy_3d").size()


func _find_room(room_id: String) -> void:
	var rooms := _tower.get("_rooms") as Array
	if rooms == null:
		return
	for value in rooms:
		var room := value as DungeonRoom3D
		if room != null and String(room.room_id) == room_id:
			_room = room
			return
