extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")

var _hit_results: Array[Dictionary] = []


func _ready() -> void:
	seed(4100810)
	var failures: Array[String] = []
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.position = Vector3.ZERO
	add_child(player)
	await get_tree().process_frame
	player.set_physics_process(false)
	player.position = Vector3.ZERO
	var locomotion_machine := player.get("_state_machine") as StateMachine
	locomotion_machine.stop()
	locomotion_machine.start("idle")
	player.aim_direction = Vector3.FORWARD
	player.combat_enabled = true
	player.melee_hit_resolved.connect(func(result: Dictionary): _hit_results.append(result.duplicate(true)))

	_verify_content_and_instance_contract(player, failures)
	await _verify_three_step_state_machine(player, failures)
	await _verify_hit_filters_and_interruptions(player, failures)
	_verify_large_visual_contract(player, failures)

	if failures.is_empty():
		print("3D_MELEE_COMBAT_FLOW_OK: two large melee instances, four-phase action machine, three-step combo, deduped arc/LOS hits, knockback and interruption rules pass")
		player.queue_free()
		await get_tree().process_frame
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	player.queue_free()
	await get_tree().process_frame
	get_tree().quit(1)


func _verify_content_and_instance_contract(player: Player3D, failures: Array[String]) -> void:
	for item_id in ["weapon_baseball_bat", "weapon_greatblade", "weapon_waraxe"]:
		var item := ItemRegistry.get_instance().get_item(item_id)
		if item.is_empty() or str(item.get("subtype", "")) != "melee_weapon":
			failures.append("Missing melee item registration: %s" % item_id)
			continue
		var instance := WeaponInstance.from_item(item)
		var tree := instance.build_runtime_tree() if instance != null else null
		if tree == null or tree.get_root() == null or "melee" not in tree.get_root().tags:
			failures.append("Melee item cannot rebuild its tagged WeaponInstance tree: %s" % item_id)
		elif tree.get_root().slots.get(AssemblyNode.SlotType.BULLET) != null:
			failures.append("Melee instance incorrectly owns a bullet module: %s" % item_id)
		elif item_id == "weapon_greatblade":
			var bullet := BlueprintRegistry.create_assembly_node("mod_bullet_standard")
			if tree.mount(tree.get_root(), AssemblyNode.SlotType.BULLET, bullet):
				failures.append("Melee assembly tree accepts an incompatible bullet module")
			else:
				bullet.free()
		if tree != null:
			tree.free()
	var bat_instance := WeaponInstance.from_item(ItemRegistry.get_instance().get_item("weapon_baseball_bat"))
	var bat_tree := bat_instance.build_runtime_tree()
	var bat_stats := bat_tree.get_computed_stats()
	if int(bat_stats.get("damage", 0)) != 20 or int(bat_stats.get("melee_combo_count", 0)) != 3:
		failures.append("Entry baseball bat is not configured as the intended three-step melee weapon")
	bat_tree.free()
	var greatblade := ItemRegistry.get_instance().get_item("weapon_greatblade")
	var waraxe := ItemRegistry.get_instance().get_item("weapon_waraxe")
	var result0 := player.equip_weapon_item_to_slot(greatblade, 0)
	var result1 := player.equip_weapon_item_to_slot(waraxe, 1)
	if not bool(result0.get("success", false)) or not bool(result1.get("success", false)):
		failures.append("Two melee weapons cannot occupy independent primary/secondary slots")
		return
	var primary_id := player.get_equipped_weapon_instance_id_for_slot(0)
	var secondary_id := player.get_equipped_weapon_instance_id_for_slot(1)
	if primary_id.is_empty() or secondary_id.is_empty() or primary_id == secondary_id:
		failures.append("Melee primary/secondary slots do not retain distinct WeaponInstance IDs")
	var swap := player.switch_weapon_slot(1)
	if not bool(swap.get("success", false)) or str(player.get_weapon_snapshot().get("gun_id", "")) != "bp_waraxe":
		failures.append("Switching to the secondary waraxe does not rebuild the active melee model")
	player.switch_weapon_slot(0)
	var snapshot := player.get_weapon_snapshot()
	if (
		str(snapshot.get("gun_id", "")) != "bp_greatblade"
		or not bool(snapshot.get("melee", false))
		or bool(snapshot.get("uses_ammo", true))
		or int(snapshot.get("magazine_size", -1)) != 0
	):
		failures.append("Greatblade is not exposed as an ammo-free melee weapon")


func _verify_three_step_state_machine(player: Player3D, failures: Array[String]) -> void:
	var enemy := _make_enemy(Vector3(0.0, 0.0, -2.0))
	await get_tree().process_frame
	var initial_hp := enemy.current_hp
	_hit_results.clear()
	if not player.request_melee_attack():
		failures.append("Ready melee state rejects a legal primary attack")
		return
	var observed: Dictionary = {}
	var queued_steps: Dictionary = {}
	for _frame in range(260):
		var snapshot := player.melee_combat.get_snapshot()
		var phase := str(snapshot.get("phase", ""))
		observed[phase] = true
		var step := int(snapshot.get("combo_step", 0))
		if phase == "recovery" and step in [1, 2] and not queued_steps.has(step):
			queued_steps[step] = player.request_melee_attack()
		player.melee_combat.physics_update(0.02)
		if phase == "ready" and observed.has("recovery") and _hit_results.size() >= 3:
			break
	for required_phase in ["ready", "windup", "active", "recovery"]:
		if not observed.has(required_phase):
			failures.append("Melee action state machine never entered %s" % required_phase)
	if not bool(queued_steps.get(1, false)) or not bool(queued_steps.get(2, false)):
		failures.append("Recovery input buffer did not queue all three combo steps")
	if _hit_results.size() != 3:
		failures.append("Three-step combo resolved %d hits instead of exactly 3" % _hit_results.size())
	else:
		for index in range(3):
			if int(_hit_results[index].get("combo_step", 0)) != index + 1:
				failures.append("Melee hit results are not ordered 1/2/3")
	var melee_machine := player.get_state_machine_snapshot().get("melee_action_machine", {}) as Dictionary
	if int((melee_machine.get("state_machine", {}).get("states", []) as Array).size()) != 4:
		failures.append("Melee action machine does not expose exactly four phases")
	if int((player.get_state_machine_snapshot().get("states", []) as Array).size()) != 8:
		failures.append("Adding melee changed the eight-state locomotion machine")
	if enemy.current_hp >= initial_hp:
		failures.append("Melee active windows did not damage the target")
	if (enemy.get("_external_velocity") as Vector3).length() <= 0.01:
		failures.append("Melee hit did not apply knockback through the enemy public interface")
	enemy.queue_free()
	await get_tree().process_frame


func _verify_hit_filters_and_interruptions(player: Player3D, failures: Array[String]) -> void:
	var behind := _make_enemy(Vector3(0.0, 0.0, 1.8))
	var far := _make_enemy(Vector3(0.0, 0.0, -4.2))
	var blocked := _make_enemy(Vector3(0.0, 0.0, -2.2))
	var wall := _make_wall(Vector3(0.0, 0.9, -1.1))
	await get_tree().physics_frame
	var hp_before := [behind.current_hp, far.current_hp, blocked.current_hp]
	player.request_melee_attack()
	_tick_until_ready(player)
	if behind.current_hp != hp_before[0]:
		failures.append("Melee arc damaged a target behind the player")
	if far.current_hp != hp_before[1]:
		failures.append("Melee reach damaged an out-of-range target")
	if blocked.current_hp != hp_before[2]:
		failures.append("Melee hit passed through a layer-1 wall")
	wall.queue_free()
	behind.queue_free()
	far.queue_free()
	blocked.queue_free()
	await get_tree().process_frame

	player.request_melee_attack()
	player.melee_combat.physics_update(0.04)
	(player.get("_state_machine") as StateMachine).transition_to("hurt", true)
	player.melee_combat.physics_update(0.02)
	if str(player.melee_combat.get_snapshot().get("phase", "")) != "ready":
		failures.append("Hurt state does not cancel an in-progress melee action")
	(player.get("_state_machine") as StateMachine).transition_to("idle")
	player.request_melee_attack()
	player.melee_combat.physics_update(0.04)
	player.switch_weapon_slot(1)
	if str(player.melee_combat.get_snapshot().get("phase", "")) != "ready":
		failures.append("Weapon switching does not cancel and reset the melee combo")
	player.switch_weapon_slot(0)


func _verify_large_visual_contract(player: Player3D, failures: Array[String]) -> void:
	for slot_index in [0, 1]:
		player.switch_weapon_slot(slot_index)
		var snapshot := player.get_weapon_snapshot()
		var bounds := snapshot.get("visual_bounds_hint", Vector3.ZERO) as Vector3
		if bounds.z < 2.30 or bounds.x < 0.80:
			failures.append("Melee weapon %s is not authored as a visibly large model" % snapshot.get("gun_id", ""))
		if player.weapon.find_children("*", "MeshInstance3D", true, false).size() < 5:
			failures.append("Melee weapon %s does not build a readable modular 3D model" % snapshot.get("gun_id", ""))
		if player.weapon.find_children("*", "CollisionObject3D", true, false).size() != 0:
			failures.append("Large melee visual adds gameplay collision to the player")
	player.switch_weapon_slot(0)


func _tick_until_ready(player: Player3D) -> void:
	for _frame in range(120):
		player.melee_combat.physics_update(0.02)
		if str(player.melee_combat.get_snapshot().get("phase", "")) == "ready":
			return


func _make_enemy(position: Vector3) -> Enemy3D:
	var enemy := ENEMY_SCENE.instantiate() as Enemy3D
	enemy.enemy_kind = "melee_chaser"
	enemy.position = position
	add_child(enemy)
	enemy.set_runtime_active(false, true)
	return enemy


func _make_wall(position: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.4, 2.0, 0.22)
	collision.shape = shape
	wall.add_child(collision)
	add_child(wall)
	return wall
