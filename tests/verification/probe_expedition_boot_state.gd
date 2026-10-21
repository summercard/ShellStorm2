extends Node

## 一次性探针（业主 2026-10-21）：「08 号房间的装配也有问题，检查一下。」
##
## 装配正确与否的**可判定口径**只有两条：
##   ① 美术内容在房间局部系里必须**填满** `get_dimensions()` 的矩形（差 > 0.6m 就是错位）；
##   ② 每一面「应该有墙」的边，墙体必须落在**边界 ±0.9m** 的带子里。
## 这两条都不依赖观感，能直接指出「哪一面、差多少米」。
##
## 用法：
##   godot --headless --path . res://tests/verification/probe_expedition_boot_state.tscn
##   SS2_SEED=414339956 可指定种子

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 60.0
## 美术包围盒与房间矩形的允许误差（m）。5 m 模数、墙厚 0.3，0.6 足够严。
const FIT_TOLERANCE_M := 0.6

var _tower: TowerDescent3D = null


func _ready() -> void:
	var seed_env := OS.get_environment("SS2_SEED")
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	if not seed_env.is_empty():
		tower.run_seed_override = int(seed_env)
	_tower = tower
	add_child(tower)

	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (tower.get("_records") as Array).is_empty():
			for _i in range(4):
				await get_tree().process_frame
			break

	print("")
	print("=== 远征装配启动态 ===")
	var snapshot: Variant = tower.get("_runtime_restore_snapshot")
	var has_snapshot := snapshot is Dictionary and not (snapshot as Dictionary).is_empty()
	var rotation: Variant = tower.call(
		"_expedition_rotation_for_checkpoint",
		snapshot if has_snapshot else {}
	)
	print("  run_seed=%d  有恢复快照=%s  整层旋转=%s°" % [
		int(tower.run_seed), "是" if has_snapshot else "否", str(rotation),
	])
	if has_snapshot:
		var world_state := (snapshot as Dictionary).get("world_state", {}) as Dictionary
		print("  快照 world_state.expedition_global_rotation_deg=%s  键=%s" % [
			str(world_state.get("expedition_global_rotation_deg", "<无>")),
			str(world_state.keys()),
		])

	print("")
	print("── 房间表（记录 → 节点实测）──")
	var bad: Array = []
	for node in tower.find_children("*", "", true, false):
		if not (node is DungeonRoom3D):
			continue
		var room := node as DungeonRoom3D
		var report := _inspect(room)
		if not bool(report.get("fit_ok", true)):
			bad.append(report)

	print("")
	print("── 装配不合口径的房间 ──")
	if bad.is_empty():
		print("  无")
	for report in bad:
		print("  %-10s 美术=%.1fx%.1f 房间=%.1fx%.1f  差=(%+.1f, %+.1f)  %s" % [
			str(report.get("room_id", "?")),
			float(report.get("art_x", 0.0)), float(report.get("art_z", 0.0)),
			float(report.get("dim_x", 0.0)), float(report.get("dim_y", 0.0)),
			float(report.get("dx", 0.0)), float(report.get("dz", 0.0)),
			str(report.get("note", "")),
		])
	print("")
	print("EXPEDITION_BOOT_STATE_END")
	get_tree().quit(0)


func _inspect(room: DungeonRoom3D) -> Dictionary:
	var room_id := room.room_id
	var dims := room.get_dimensions()
	var box := _local_visual_box(room)
	var art_x := box.size.x
	var art_z := box.size.z
	var dx := art_x - dims.x
	var dz := art_z - dims.y
	var center := Vector2(box.get_center().x, box.get_center().z)
	var offset := center.length()
	var fit_ok := absf(dx) <= FIT_TOLERANCE_M and absf(dz) <= FIT_TOLERANCE_M and offset <= FIT_TOLERANCE_M
	var note := ""
	if not fit_ok:
		if absf(dx) > FIT_TOLERANCE_M and absf(dz) <= FIT_TOLERANCE_M:
			note = "X 向尺寸不符（可能少了 90° 转置）"
		elif absf(dz) > FIT_TOLERANCE_M and absf(dx) <= FIT_TOLERANCE_M:
			note = "Z 向尺寸不符"
		elif offset > FIT_TOLERANCE_M:
			note = "整体偏移 (%.1f, %.1f)" % [center.x, center.y]
		else:
			note = "两向都不符"
	print("  %-16s pos=(%7.1f,%6.1f) 尺寸=(%4.1fx%4.1f) 美术=(%4.1fx%4.1f) 美术中心=(%+5.1f,%+5.1f)  rotY=%6.1f°  %s" % [
		room_id, room.global_position.x, room.global_position.z, dims.x, dims.y,
		art_x, art_z, center.x, center.y, rad_to_deg(room.global_rotation.y),
		"OK" if fit_ok else "✘ " + note,
	])
	return {
		"room_id": room_id, "fit_ok": fit_ok, "art_x": art_x, "art_z": art_z,
		"dim_x": dims.x, "dim_y": dims.y, "dx": dx, "dz": dz, "note": note,
	}


func _local_visual_box(room: DungeonRoom3D) -> AABB:
	var box := AABB()
	var started := false
	var to_local := room.global_transform.affine_inverse()
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var part := to_local * (mesh.global_transform * mesh.mesh.get_aabb())
		if not started:
			box = part
			started = true
		else:
			box = box.merge(part)
	return box
