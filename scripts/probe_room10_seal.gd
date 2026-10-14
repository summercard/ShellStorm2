extends Node
## 诊断探针：room_10 的周界封闭性逐格实测（复刻 verify_expedition_level01_flow 的轮廓感知判据），
## 并打印房间朝向 / 门槽 / 静态布局根变换，定位「墙在但打不到」的原因。

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 77001199
const GRID := 5.0
const SIDES := {
	"north": Vector3(0.0, 0.0, -1.0),
	"south": Vector3(0.0, 0.0, 1.0),
	"east": Vector3(1.0, 0.0, 0.0),
	"west": Vector3(-1.0, 0.0, 0.0),
}
const WATCH: Array[String] = ["room_09", "room_10", "boss"]


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	var tower := EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _i in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	for room_id in WATCH:
		var room := tower._room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			print("SEAL %-8s <缺>" % room_id)
			continue
		var dims := room.get_dimensions()
		print("SEAL %-8s dims=(%.1f,%.1f) rot=%.0f static=%s" % [
			room_id, dims.x, dims.y, rad_to_deg(room.rotation.y),
			str(room.get_meta("static_layout_scene_path", "<无>")),
		])
		var offsets := []
		for d in ["north", "south", "east", "west"]:
			offsets.append("%s=%s" % [d, str(room.get_meta("tower_wall_door_offset_%s" % d, "-"))])
		print("       %s  doors=%s" % [" ".join(offsets), str(room.doors)])
		var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		if art != null:
			print("       art.transform=%s" % str(art.transform))
		var cells := {}
		for value in room.authored_layout_instances:
			var inst := value as Dictionary
			if str(inst.get("slot_role", "")) != "floor_tile":
				continue
			var p := inst.get("position", Vector3.ZERO) as Vector3
			cells[_key(p.x, p.z)] = Vector2(p.x, p.z)
		print("       地砖格数=%d" % cells.size())
		var probe_len := GRID * 0.5 + 0.5
		var face_half := GRID * 0.5
		var bad := 0
		for cell_value in cells.values():
			var local := cell_value as Vector2
			for side in SIDES:
				var dir := SIDES[side] as Vector3
				var nb := local + Vector2(dir.x, dir.z) * GRID
				if cells.has(_key(nb.x, nb.y)):
					continue
				var from := room.global_position + Vector3(local.x, 0.5, local.y)
				var hit := _ray(space, from, from + dir * probe_len)
				if not hit.is_empty():
					continue
				bad += 1
				print("       ✗ %-5s 格心(%.1f,%.1f) 打空  (射线终点 %s)" % [
					side, local.x, local.y,
					"(%.1f,%.1f,%.1f)" % [
						from.x + dir.x * probe_len, from.y + dir.y * probe_len, from.z + dir.z * probe_len,
					],
				])
		print("       打空总数=%d" % bad)
	print("ROOM10_SEAL_DONE")
	get_tree().quit(0)


func _key(x: float, z: float) -> String:
	return "%.2f|%.2f" % [x, z]


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	return space.intersect_ray(query)
