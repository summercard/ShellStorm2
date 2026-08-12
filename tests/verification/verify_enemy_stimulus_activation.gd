extends Node3D

const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.start_with_weapon = false
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)

	var near_enemy := _make_sleeping_enemy(Vector3(37.5, 0.0, 0.0))
	if not near_enemy.activate_from_player_proximity(player, 38.0) or not near_enemy.is_runtime_ai_active():
		failures.append("同层38米屏幕外预激活没有启动怪物")

	var far_enemy := _make_sleeping_enemy(Vector3(40.0, 0.0, 0.0))
	if far_enemy.activate_from_player_proximity(player, 38.0) or far_enemy.is_runtime_ai_active():
		failures.append("超出38米的无刺激怪物被错误预激活")
	far_enemy.notify_attacked_by(player)
	if not far_enemy.is_runtime_ai_active():
		failures.append("屏幕外休眠怪物受击后没有立即激活")

	var other_floor := _make_sleeping_enemy(Vector3(2.0, -9.0, 0.0))
	if other_floor.activate_from_player_proximity(player, 38.0):
		failures.append("预激活跨越楼板启动了其他楼层怪物")

	for node in [near_enemy, far_enemy, other_floor, player]:
		node.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("ENEMY_STIMULUS_ACTIVATION_OK: 38m same-floor preactivation, distant hit wakeup, and floor isolation pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _make_sleeping_enemy(world_position: Vector3) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	enemy.position = world_position
	add_child(enemy)
	enemy.set_runtime_active(false, true)
	return enemy
