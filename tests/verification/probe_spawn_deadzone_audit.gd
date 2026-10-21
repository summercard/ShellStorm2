extends Node

## 全房刷怪死区审计（业主 2026-10-21）。
##
## 逐房回答：
##   ① 闸门启用前，候选落点里有多少个落在「玩家走不到」的格上 —— 这就是玩家看到的现象；
##   ② 闸门启用后还剩几个（目标：0）；
##   ③ 该房有没有触发盒、几盒、每盒能取到几个点（取不到 ⇒ 少出怪甚至整房白送）。
##
## 用法：
##   godot --headless --path . res://tests/verification/probe_spawn_deadzone_audit.tscn

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"

var _tower: TowerDescent3D = null


func _ready() -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	_tower = tower
	add_child(tower)
	var waited := 0.0
	while waited < 60.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var rooms := tower.get("_rooms") as Array
		if rooms != null and rooms.size() >= 4:
			break
	await _audit()
	print("")
	print("DEADZONE_AUDIT_END")
	get_tree().quit(0)


func _audit() -> void:
	print("")
	print("=== 全房刷怪死区审计 ===")
	print("%-12s %-14s %8s %8s %8s %6s %s" % ["房号", "类型", "旧候选", "死区", "新候选", "盒数", "每盒取点"])
	var rooms := _tower.get("_rooms") as Array
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		room.ensure_shell_built()
		room.ensure_detail_built()
		await get_tree().physics_frame
		var old_candidates := (room.get("_spawn_candidates") as Array).duplicate()
		room.call("_ensure_spawn_reach")
		var active := bool(room.get("_spawn_reach_active"))
		var reach := room.get("_spawn_reach_cells") as Dictionary
		var dead_old := 0
		if active and reach != null:
			for candidate in old_candidates:
				var point := candidate as Vector3
				var key: Vector2i = room.call("_spawn_reach_key", point)
				if not reach.has(key):
					dead_old += 1
		var new_candidates := room.get("_spawn_candidates") as Array
		var placements := room.get("spawn_placements") as Array
		var box_text := ""
		for index in placements.size():
			var placement := _tower.call("_box_placement_at", placements, index) as Dictionary
			if placement.is_empty():
				box_text += "  #%d=解析失败" % index
				continue
			var points := room.spawn_points_in_box(
				placement.get("box_center", Vector2.ZERO) as Vector2,
				placement.get("box_size", Vector2.ZERO) as Vector2,
				13, 0.0, 0.0, int(placement.get("box_wall_recess_tiles", 1))
			)
			var finite := 0
			for point in points:
				if (point as Vector3).is_finite():
					finite += 1
			box_text += "  #%d=%d" % [index, finite]
		print("%-12s %-14s %8d %8d %8d %6d %s" % [
			room.room_id, str(room.room_type), old_candidates.size(), dead_old,
			new_candidates.size(), placements.size(),
			box_text if not box_text.is_empty() else "-",
		])
		if not active:
			print("              ↑ 闸门未启用（可达性覆盖不足或多级房，走旧行为）")
