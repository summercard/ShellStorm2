extends Node


func _ready() -> void:
	var failures: Array[String] = []
	await _verify_turret_cleanup(failures)
	await _verify_trap_teardown(failures)
	await _verify_reinforcement_spawn_from_physics_signal(failures)
	await VerificationClock.wait(self, 0.55)
	await get_tree().process_frame
	if failures.is_empty():
		print("RUNTIME_SAFETY_FLOW_OK: turret lifetime, trap teardown, and deferred reinforcement spawning are safe")
		VerificationQuitter.schedule(self, 0)
	else:
		for failure in failures:
			push_error(failure)
		VerificationQuitter.schedule(self, 1)


func _verify_turret_cleanup(failures: Array[String]) -> void:
	var bullet_scene: PackedScene = load("res://scenes/Bullet.tscn") as PackedScene
	var source: Area2D = bullet_scene.instantiate() as Area2D
	add_child(source)
	source.set("max_distance", 0.0)
	source.call("fire", Vector2.ZERO, Vector2.RIGHT, 1.0, 10, false)
	source.set("_fate_spawn_turret_on_land", true)
	source.set("_fate_turret_duration", 0.08)
	await get_tree().process_frame
	await get_tree().process_frame

	var turret: Area2D = null
	for child in get_children():
		if child is Area2D and child != source and bool(child.get("_turret_mode")):
			turret = child as Area2D
			break
	if turret == null:
		failures.append("Turret-on-land did not create a turret instance")
		return
	await VerificationClock.wait(self, 0.12)
	await get_tree().process_frame
	if is_instance_valid(turret) and not turret.is_queued_for_deletion():
		failures.append("Turret remains active after its configured lifetime")


func _verify_trap_teardown(failures: Array[String]) -> void:
	var trap_scene: PackedScene = load("res://scenes/RoomTrap.tscn") as PackedScene
	var trap: Node2D = trap_scene.instantiate() as Node2D
	add_child(trap)
	await get_tree().process_frame
	trap.call("_on_falling_rocks_damage_start")
	await get_tree().process_frame
	trap.queue_free()
	await get_tree().process_frame
	await VerificationClock.wait(self, 2.1)
	if is_instance_valid(trap):
		failures.append("Trap room instance was not released after teardown")


func _verify_reinforcement_spawn_from_physics_signal(failures: Array[String]) -> void:
	var room := Node2D.new()
	add_child(room)
	var player := CharacterBody2D.new()
	player.collision_layer = 2
	player.position = Vector2(120.0, 0.0)
	var player_shape := CollisionShape2D.new()
	var player_circle := CircleShape2D.new()
	player_circle.radius = 10.0
	player_shape.shape = player_circle
	player.add_child(player_shape)
	room.add_child(player)

	var spawner := RoomWaveSpawner.new()
	room.add_child(spawner)
	spawner.configure([], room, player, 1, RoomData.FloorLevel.MEDIUM, null, Vector2(960.0, 768.0))

	var trigger := Area2D.new()
	trigger.collision_layer = 0
	trigger.collision_mask = 2
	trigger.monitoring = true
	var trigger_shape := CollisionShape2D.new()
	var trigger_circle := CircleShape2D.new()
	trigger_circle.radius = 20.0
	trigger_shape.shape = trigger_circle
	trigger.add_child(trigger_shape)
	room.add_child(trigger)
	trigger.body_entered.connect(
		func(_body: Node2D) -> void:
			trigger.set_meta("did_enter", true)
			spawner.trigger_extra_spawn(1)
	)

	await get_tree().physics_frame
	player.position = Vector2.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if not trigger.has_meta("did_enter"):
		failures.append("Physics signal setup did not enter the reinforcement trigger")
	if spawner.get_active_enemies().size() != 1:
		failures.append("Reinforcement triggered inside a physics signal was not spawned safely")
	room.queue_free()
	await get_tree().process_frame
