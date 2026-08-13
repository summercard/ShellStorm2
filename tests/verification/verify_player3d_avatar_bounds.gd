extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const EXPECTED_STATIC_HEIGHT_M := 1.05


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	add_child(player)
	player.set_physics_process(false)
	player.avatar.set_process(false)
	player.get_node("Camera3D").current = false
	player.global_position = Vector3.ZERO
	await get_tree().process_frame
	player.avatar.visual_root.position = Vector3.ZERO
	player.avatar.visual_root.rotation = Vector3.ZERO
	player.avatar.visual_root.scale = Vector3.ONE

	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	var mesh_count := 0
	for child in player.avatar.get_node("VisualRoot/BunnyRig").find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if (
			not mesh_instance.is_visible_in_tree()
			or mesh_instance.mesh == null
			or String(mesh_instance.get_path()).contains("/WeaponSocket/")
		):
			continue
		var world_aabb := mesh_instance.global_transform * mesh_instance.get_aabb()
		low = low.min(world_aabb.position)
		high = high.max(world_aabb.end)
		mesh_count += 1
		print(
			"PLAYER3D_AVATAR_PART_BOUNDS ",
			mesh_instance.get_path(),
			" low=",
			world_aabb.position,
			" high=",
			world_aabb.end
		)
	var height := high.y - low.y
	if mesh_count != 10:
		failures.append("Expected 10 visible Bunny mesh primitives, got %d" % mesh_count)
	if absf(low.y) > 0.001:
		failures.append("Bunny static assembly does not start at ground Y=0: %.6f" % low.y)
	if absf(height - EXPECTED_STATIC_HEIGHT_M) > 0.001:
		failures.append("Bunny runtime assembly height is not the new 1.05 m base: %.6f" % height)
	if low.x < -0.378 or high.x > 0.378 or low.z < -0.263 or high.z > 0.263:
		failures.append("Bunny runtime assembly footprint escaped the new 70% base bounds")

	if failures.is_empty():
		print("BUNNY_V006_BOUNDS_OK: mesh_count=%d low=%s high=%s height=%.6f" % [
			mesh_count,
			low,
			high,
			height,
		])
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
