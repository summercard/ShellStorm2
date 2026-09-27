extends Node
## 临时探针（只读）：实测远征关卡01 每间房的**刷怪落点**从哪来。
## 判据全部取运行时对象，不复刻公式（只在打印行里给对照）。
## 关注：size_class / 地砖格心数 / enemy_spawn_points / spawn_point_for_index 实际落点。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"

var _tower: Node = null


func _ready() -> void:
	var packed := load(EXPEDITION_SCENE) as PackedScene
	_tower = packed.instantiate()
	_tower.set("test_mode", true)
	_tower.set("run_seed_override", 77001199)
	add_child(_tower)
	for _index in range(10):
		await get_tree().process_frame
		await get_tree().physics_frame

	var rooms: Array = _tower.get("_rooms")
	print("rooms=%d" % rooms.size())
	print("")
	for room in rooms:
		if room == null:
			continue
		var rid := str(room.get("room_id"))
		var rtype := str(room.get("room_type"))
		var sclass := str(room.get("size_class"))
		var dims: Vector2 = room.call("get_dimensions")
		var gp: Vector3 = room.global_position
		var pts: Array = room.get("enemy_spawn_points")
		var cells: Array = room.get("_authored_tile_cells")
		var plan: Variant = room.get("authored_layout_instances")
		var tile_instances := 0
		if plan is Array:
			for value in (plan as Array):
				if str((value as Dictionary).get("slot_role", "")) == "floor_tile":
					tile_instances += 1
		print("ROOM %-14s type=%-10s size_class=%-11s dims=%.0f x %.0f  半宽(%.1f, %.1f)" % [
			rid, rtype, sclass, dims.x, dims.y, dims.x * 0.5, dims.y * 0.5,
		])
		print("     authored_layout_instances=%d  floor_tile_slots=%d  _authored_tile_cells=%d  环形落点数=%d" % [
			(plan as Array).size() if plan is Array else -1,
			tile_instances, cells.size(), pts.size(),
		])
		for i in range(pts.size()):
			var lp: Vector3 = (pts[i] as Vector3) - gp
			print("       ring[%d] local=(%7.2f, %7.2f)  r=%6.2f" % [
				i, lp.x, lp.z, Vector2(lp.x, lp.z).length(),
			])
		# 实际取点：前 12 只（看超量退让怎么走）
		var line := ""
		for i in range(12):
			var lp2: Vector3 = room.call("spawn_point_for_index", i) - gp
			line += "(%.1f,%.1f) " % [lp2.x, lp2.z]
		print("       idx0..11 -> %s" % line)
		print("")
	print("=== 对照：设计源本房编成（总量区间）===")
	var plan_snapshot: Dictionary = (_tower.get("_floor_plan_snapshots") as Dictionary).get(0, {})
	for value in plan_snapshot.get("rooms", []):
		var spec := value as Dictionary
		var sp := spec.get("enemy_spawn_plan", {}) as Dictionary
		var total := ""
		if not sp.is_empty():
			var parts: Array[String] = []
			for wave_value in (sp.get("waves", []) as Array):
				var wave := wave_value as Dictionary
				var c := wave.get("count", {}) as Dictionary
				parts.append("%s-%s" % [str(c.get("min", "?")), str(c.get("max", "?"))])
			total = " / ".join(parts)
		print("  %-12s key=%-10s waves=%d  每波总量=[%s]" % [
			str(spec.get("id", "")), str(spec.get("key", "")),
			(sp.get("waves", []) as Array).size(), total,
		])
	get_tree().quit(0)
