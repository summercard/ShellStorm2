extends Node3D
const ENEMY = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
var failures: Array[String] = []
var checks := 0
var serial := 0

class Target extends CharacterBody3D:
	var current_hp := 100000
	var damage_events := 0
	func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO) -> void:
		current_hp -= amount
		damage_events += 1

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and not failures.has(message):
		failures.append(message)

func setup_ground() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100,0.4,100)
	collision.shape = box
	ground.position.y = -0.2
	ground.add_child(collision)
	add_child(ground)

func make_target(position_value: Vector3) -> Target:
	var target := Target.new()
	target.position = position_value
	target.add_to_group("player_3d")
	add_child(target)
	return target

func make_enemy() -> Enemy3D:
	var definition := EliteContentCatalog.get_by_id("elite_arms_taker")
	var enemy := ENEMY.instantiate() as Enemy3D
	add_child(enemy)
	serial += 1
	enemy.configure_from_enemy_data({"enemy_type":"melee_chaser", "is_elite":true,
		"elite_id":"elite_arms_taker", "elite_behavior_id":"weapon_phase_swap", "elite_level":1,
		"modifier_id_en":"Elite.WeaponParasite", "persistent_id":"arms_qa_%d"%serial,
		"presentation_asset_id":definition.presentation_asset_id, "presentation_scene":definition.presentation_scene})
	enemy.position = Vector3(0,0.05,0)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.avatar.set_process(false)
	var visual := enemy.avatar._formal_elite_root
	visual.set_process(false)
	enemy._home_initialized = true
	enemy._home_position = enemy.position
	return enemy

func bind_target(enemy: Enemy3D, target: Node3D) -> void:
	enemy._target = target
	MonsterAIManager.notify_enemy_attacked(enemy, target)
	MonsterAIManager.force_refresh_enemy(enemy)

func step(enemy: Enemy3D, delta := 1.0/60.0) -> void:
	enemy._physics_process(delta)
	present(enemy, delta)

func present(enemy: Enemy3D, delta := 1.0/60.0) -> void:
	enemy.avatar._formal_elite_root.call("_process", delta)
	enemy.avatar._process(delta)
	enemy._process(0.0)

func hip_position(enemy: Enemy3D) -> Vector3:
	var skeleton := enemy.avatar._formal_elite_root.find_child("Skeleton3D",true,false) as Skeleton3D
	return skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Hip")).origin)

func clean_effects() -> void:
	for node in get_children():
		if node is Projectile3D:
			node.queue_free()
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool != null:
		pool.clear_all()

func finish(marker: String) -> void:
	if failures.is_empty():
		print(marker+" checks=%d"%checks)
	else:
		for failure in failures:
			push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
