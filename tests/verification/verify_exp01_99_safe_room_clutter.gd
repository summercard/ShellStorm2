extends Node

const TARGETS := {
	"01": "res://scenes/ExpeditionLevel01_3D.tscn",
	"99": "res://scenes/ExpeditionLevel99_3D.tscn",
}

func _ready() -> void:
	if OS.get_environment("SS2_UI_QA_ISOLATED") != "1":
		get_tree().quit(2)
		return
	call_deferred("_verify")

func _verify() -> void:
	for level: String in TARGETS:
		var packed := load(TARGETS[level]) as PackedScene
		var tower := packed.instantiate() as TowerDescent3D
		tower.test_mode = true
		tower.run_seed_override = 77001199
		add_child(tower)
		for step in 4:
			await get_tree().process_frame
			await get_tree().physics_frame
		var rooms: Dictionary = tower.get("_room_by_id")
		var room := rooms.get("start") as DungeonRoom3D
		if room == null or room.room_type != "STAIR_LOBBY":
			_fail(level, "formal entry room missing")
			return
		room.ensure_shell_built()
		room.ensure_detail_built()
		await get_tree().process_frame
		var matches := room.find_children("InteractiveClutter_*", "", true, false)
		var corners := 0
		for node in room.find_children("*", "Node3D", true, false):
			if node.get_meta("asset_id", "") == "ENV-TOWER-CORNER-L-5M":
				corners += 1
		if room.fixed_lobby_clutter_enabled or not matches.is_empty() or not room.get_clutter_warmup_paths().is_empty():
			_fail(level, "fixed breakables remain enabled, instantiated or queued for warmup")
			return
		if not room.has_node("SafeRoomArtRoot") or corners != 4 or room.doors.size() != 2 or not room.procedural_furniture_enabled:
			_fail(level, "unrelated shell, corner, door or furniture contract changed")
			return
		print("EXP_SAFE_ROOM level=%s room=%s fixed=%d corners=%d door_sides=%d" % [level, room.room_id, matches.size(), corners, room.doors.size()])
		tower.queue_free()
		await get_tree().process_frame
	print("EXP01_99_SAFE_ROOM_CLUTTER_OK rooms=2")
	get_tree().quit(0)

func _fail(level: String, reason: String) -> void:
	push_error("EXP_SAFE_ROOM %s: %s" % [level, reason])
	get_tree().quit(1)
