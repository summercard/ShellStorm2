extends Node

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player3D.tscn")
const ENEMY_SCENE: PackedScene = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
const OUTPUT := "res://outputs/verification/melee_combat_large_weapons.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var stage := _build_stage()
	add_child(stage)
	var greatblade_target := await _make_target(stage, Vector3(-1.28, 0.0, -2.05), Color("4db8d1"))
	var waraxe_target := await _make_target(stage, Vector3(1.28, 0.0, -2.20), Color("e58335"))
	var greatblade_player := await _make_player(stage, Vector3(-1.05, 0.0, 0.0), "weapon_greatblade")
	var waraxe_player := await _make_player(stage, Vector3(1.05, 0.0, 0.0), "weapon_waraxe")
	_drive_to_combo_active(greatblade_player, 1, 0.62)
	_drive_to_combo_active(waraxe_player, 3, 0.54)
	for _index in range(5):
		greatblade_player.avatar.call("_process", 0.08)
		waraxe_player.avatar.call("_process", 0.08)

	_assert_melee_pose(greatblade_player, "bp_greatblade", 1, failures)
	_assert_melee_pose(waraxe_player, "bp_waraxe", 3, failures)
	var effect_pool := stage.get_node("CombatEffectPool3D") as CombatEffectPool3D
	var effect_counts := effect_pool.get_snapshot().get("acquire_counts", {}) as Dictionary
	if int(effect_counts.get("slash", 0)) != 4 or int(effect_counts.get("melee_impact", 0)) != 4:
		failures.append("Visual preview does not contain all four driven slash arcs and target impact bursts")
	if greatblade_target.current_hp >= greatblade_target.max_hp or waraxe_target.current_hp >= waraxe_target.max_hp:
		failures.append("Visual preview targets were not struck by the displayed active poses")
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 2.35, -6.7)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.78, -0.10), Vector3.UP)
	camera.fov = 31.0
	camera.current = true
	stage.add_child(camera)
	await get_tree().process_frame
	await get_tree().process_frame
	for node in get_tree().root.find_children("*", "Control", true, false):
		(node as Control).visible = false
	for node in get_tree().root.find_children("*", "Label3D", true, false):
		(node as Label3D).visible = false
	for target in [greatblade_target, waraxe_target]:
		var overhead := (target as Enemy3D).get_node_or_null("OverheadHealthBar") as Node3D
		if overhead != null:
			overhead.visible = false
	await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(OUTPUT) != OK:
		failures.append("Cannot save large melee weapon combat preview")

	if failures.is_empty():
		print("3D_MELEE_COMBAT_VISUAL_OK: greatblade combo-1 and waraxe combo-3 active poses with slash/impact feedback saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _build_stage() -> Node3D:
	var stage := Node3D.new()
	var effect_pool := CombatEffectPool3D.new()
	effect_pool.name = "CombatEffectPool3D"
	stage.add_child(effect_pool)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("182a34")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("cfe5ec")
	environment.ambient_light_energy = 1.35
	world_environment.environment = environment
	stage.add_child(world_environment)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(7.4, 5.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("304953")
	floor_material.roughness = 0.9
	plane.material = floor_material
	floor.mesh = plane
	stage.add_child(floor)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	key.light_energy = 1.65
	stage.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(2.8, 3.6, -3.5)
	rim.light_color = Color("a9dfff")
	rim.omni_range = 10.0
	rim.light_energy = 5.0
	stage.add_child(rim)
	return stage


func _make_target(stage: Node3D, spawn_position: Vector3, tint: Color) -> Enemy3D:
	var target := ENEMY_SCENE.instantiate() as Enemy3D
	target.enemy_kind = "melee_chaser"
	target.position = spawn_position
	stage.add_child(target)
	await get_tree().process_frame
	target.set_runtime_active(false, true)
	target.max_hp = 999
	target.current_hp = 999
	target.scale = Vector3.ONE * 0.28
	for mesh in target.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		if instance.material_override != null:
			continue
		var material := StandardMaterial3D.new()
		material.albedo_color = tint
		material.roughness = 0.5
		instance.material_override = material
	return target


func _make_player(stage: Node3D, spawn_position: Vector3, item_id: String) -> Player3D:
	var player := PLAYER_SCENE.instantiate() as Player3D
	player.position = spawn_position
	stage.add_child(player)
	await get_tree().process_frame
	player.set_process(false)
	player.set_physics_process(false)
	player.avatar.set_process(false)
	var locomotion_machine := player.get("_state_machine") as StateMachine
	locomotion_machine.stop()
	locomotion_machine.start("idle")
	player.get_node("Camera3D").current = false
	player.get_node("AimCursor").visible = false
	player.aim_direction = Vector3.FORWARD
	player.aim_yaw = 0.0
	player.avatar.visual_root.rotation.y = 0.0
	player.combat_enabled = true
	var item := ItemRegistry.get_instance().get_item(item_id)
	var equip_result := player.equip_weapon_item_to_slot(item, 0)
	if not bool(equip_result.get("success", false)):
		push_error("Cannot equip melee preview item: %s" % item_id)
	return player


func _drive_to_combo_active(player: Player3D, target_step: int, target_progress: float) -> void:
	player.request_melee_attack()
	var queued_steps: Dictionary = {}
	for _frame in range(520):
		var snapshot := player.melee_combat.get_snapshot()
		var phase := str(snapshot.get("phase", "ready"))
		var step := int(snapshot.get("combo_step", 0))
		if phase == "recovery" and step < target_step and not queued_steps.has(step):
			queued_steps[step] = player.request_melee_attack()
		if phase == "active" and step == target_step and float(snapshot.get("phase_progress", 0.0)) >= target_progress:
			return
		player.melee_combat.physics_update(0.012)


func _assert_melee_pose(player: Player3D, weapon_id: String, combo_step: int, failures: Array[String]) -> void:
	var action := player.get_action_snapshot()
	var avatar := player.avatar.get_component_snapshot()
	var weapon := player.get_weapon_snapshot()
	if str(weapon.get("gun_id", "")) != weapon_id:
		failures.append("Visual preview equipped the wrong weapon for %s" % weapon_id)
	if str(action.get("melee_phase", "")) != "active" or int(action.get("melee_combo_step", 0)) != combo_step:
		failures.append("Visual preview did not reach %s combo-%d active" % [weapon_id, combo_step])
	if str(avatar.get("weapon_pose_state", "")) != "heavy_melee_active":
		failures.append("Avatar is not rendering the heavy_melee_active pose for %s" % weapon_id)
	if int(avatar.get("active_grip_hand_count", 0)) != 2:
		failures.append("Large melee pose does not keep both hands on %s" % weapon_id)
	var bounds := weapon.get("visual_bounds_hint", Vector3.ZERO) as Vector3
	if bounds.z < 2.30 or bounds.x < 0.80:
		failures.append("Rendered melee silhouette is below the large-weapon contract for %s" % weapon_id)
