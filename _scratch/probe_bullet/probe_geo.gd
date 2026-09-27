extends Node3D
## 诊断（只读）：① 玩家实际射击高度（武器 socket / 枪口）② 每只怪的
## 碰撞体世界高度区间 vs 可见模型世界高度区间。用于判断「子弹从枪口水平飞出、
## 是否会从怪的碰撞体上方掠过」。
## 只打印，不改产品代码、不写存档。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000

var tower: TowerDescent3D
var rows: Array[String] = []


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(10)
	_report_player()
	var ids: Array = tower._room_by_id.keys()
	ids.sort()
	for id_value in ids:
		var room := tower._room_by_id[id_value] as DungeonRoom3D
		if room == null:
			continue
		await _inspect_room(room)
	for row in rows:
		print("GEO_ROW %s" % row)
	print("GEO_PROBE_DONE")
	get_tree().quit(0)


func _report_player() -> void:
	var player := tower.player
	if player == null:
		print("GEO_PLAYER missing")
		return
	var origin := player.global_position
	var capsule := -1.0
	for value in player.find_children("*", "CollisionShape3D", true, false):
		var collision := value as CollisionShape3D
		if collision.shape is CapsuleShape3D:
			capsule = (collision.shape as CapsuleShape3D).height
	var socket_y := -1.0
	if player.avatar != null and player.avatar.weapon_socket != null:
		socket_y = player.avatar.weapon_socket.global_position.y - origin.y
	var muzzle_y := -1.0
	var weapon := player.weapon as WeaponModel3D
	if weapon != null:
		var muzzle := weapon.get("_muzzle") as Marker3D
		if muzzle != null and muzzle.is_inside_tree():
			muzzle_y = muzzle.global_position.y - origin.y
		print("GEO_WEAPON gun_id=%s visible=%s stowed=%s" % [
			weapon.gun_id, str(weapon.visible), str(player.get("_stowed_weapon_model") != null),
		])
	print("GEO_PLAYER origin_y=%.3f capsule=%.2f socket_off=%.3f muzzle_off=%.3f" % [
		origin.y, capsule, socket_y, muzzle_y,
	])


func _inspect_room(room: DungeonRoom3D) -> void:
	tower.force_enter_room_for_test(room.room_id)
	if tower.player != null:
		tower.player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(4)
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy == null or not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
			continue
		var collider := _collider_span(enemy)
		var visual := _visual_span(enemy)
		rows.append(
			"room=%s kind=%s scale_y=%.2f collider=%.3f..%.3f visual=%.3f..%.3f visual_above_collider=%.3f" % [
				room.room_id, enemy.enemy_kind, enemy.scale.y,
				collider.x, collider.y, visual.x, visual.y, visual.y - collider.y,
			]
		)


func _collider_span(enemy: Enemy3D) -> Vector2:
	if enemy.collision_shape == null or enemy.collision_shape.shape == null:
		return Vector2(-1.0, -1.0)
	var aabb := enemy.collision_shape.shape.get_debug_mesh().get_aabb()
	var world_aabb: AABB = enemy.collision_shape.global_transform * aabb
	return Vector2(
		world_aabb.position.y - enemy.global_position.y,
		world_aabb.end.y - enemy.global_position.y,
	)


func _visual_span(enemy: Enemy3D) -> Vector2:
	if enemy.avatar == null:
		return Vector2(-1.0, -1.0)
	var min_y := INF
	var max_y := -INF
	for value in enemy.avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if mesh.mesh == null:
			continue
		var world_aabb: AABB = mesh.global_transform * mesh.get_aabb()
		min_y = minf(min_y, world_aabb.position.y)
		max_y = maxf(max_y, world_aabb.end.y)
	if min_y == INF:
		return Vector2(-1.0, -1.0)
	return Vector2(min_y - enemy.global_position.y, max_y - enemy.global_position.y)


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
