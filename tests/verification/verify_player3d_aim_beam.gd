extends Node3D

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")
const AIM_BEAM_SCENE := preload("res://assets/art/vfx/visibility_3d/vfx_player_aim_beam_root_top3d.tscn")
const QUITTER := preload("res://src/testing/VerificationQuitter.gd")

var _player: Player3D
var _beam: Node3D
var _ribbon: MeshInstance3D
var _wall: StaticBody3D
var _checks := 0
var _failures: Array[String] = []
var _output := ""
var _finished := false


func _ready() -> void:
	get_tree().create_timer(60.0, true, false, true).timeout.connect(_timeout)
	call_deferred("_run")


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var verify_paused := "--verify-paused" in args
	if "--visual" in args and not verify_paused:
		_output = OS.get_environment("SHELLSTORM_AIM_BEAM_OUTPUT")
		_check(not _output.is_empty() and DisplayServer.get_name() != "headless", "visual run needs a renderer and output directory")
		if not _failures.is_empty():
			_finish()
			return
		_build_visual_environment()
	_add_box("Floor", Vector3(0.0, -0.10, 0.0), Vector3(16.0, 0.2, 16.0), Color("303945"))
	_player = PLAYER_SCENE.instantiate() as Player3D
	_player.start_with_weapon = false
	_player.combat_enabled = true
	_player.set_aim_locked(true)
	# The normal game leaves the feature unmounted; opt in only for the retained-effect test.
	if not verify_paused and not _player.has_node("AimBeam3D"):
		var fixture := AIM_BEAM_SCENE.instantiate()
		fixture.name = "AimBeam3D"
		_player.add_child(fixture)
	add_child(_player)
	if verify_paused:
		_check(_player.equip_weapon("bp_pistol", "mod_bullet_standard"), "production player can still equip a firearm")
		await _physics_ticks(8)
		_check(_player.find_children("AimBeam3D", "Node3D", true, false).is_empty(), "production firearm has no instantiated aim beam")
		_finish()
		return
	_player.aim_cursor.hide()
	if not _output.is_empty():
		# Detail camera for evidence only; do not let gameplay camera feedback reset it.
		_player.camera_feedback.set_physics_process(false)
		_player.camera.attributes = null
		_player.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_player.camera.size = 5.4
		_player.camera.position = Vector3(0.0, 6.5, 5.0)
		_player.camera.look_at(Vector3(0.8, 0.50, -1.1))
	_set_aim(Vector3(0.91, 0.0, -0.42).normalized())
	await _physics_ticks(5)
	_beam = _player.get_node_or_null("AimBeam3D") as Node3D
	_check(_beam != null, "retained beam is available on the player fixture")
	if _beam == null:
		_finish()
		return
	_ribbon = _beam.get_node_or_null("Ribbon") as MeshInstance3D
	_check(_ribbon != null, "prefab supplies its rendered ribbon")
	if _ribbon == null:
		_finish()
		return
	_check(_beam.get_parent() == _player, "unarmed player retains the inactive instance")
	_check(_beam.get_meta("asset_id", "") == "VFX-PLAYER-AIM-BEAM-3D", "asset identity")
	_check(_ribbon.get_meta("skip_player_occlusion_silhouette", false) == true, "beam opts out of the through-wall silhouette")
	_check(_ribbon.mesh is QuadMesh and _beam.get_child_count() == 1, "only a single quad, no lights or hit bodies")
	_check(_ribbon.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and _ribbon.gi_mode == GeometryInstance3D.GI_MODE_DISABLED, "not a shadow caster or GI input")
	_check(not _beam.is_processing() and not _beam.visible, "unarmed: no beam or self-processing")
	_check(_player.equip_weapon("bp_pistol", "mod_bullet_standard"), "equip a ranged weapon")
	await _physics_ticks(8)
	_check(_beam.is_visible_in_tree(), "equipping a firearm shows the beam without shooting")
	_expect_span(4.0, "pistol in open space")
	_frame_beam_for_capture()
	var full_image := await _capture("01_pistol.png")
	var origin := _from()
	var direction := (_to() - origin).normalized()
	var ammo := _player.weapon.current_ammo
	_player.weapon.current_ammo = ammo - 1
	_check(_player.request_reload(), "start reload")
	await _physics_ticks(10)
	_expect_span(4.0, "while reloading")
	_player.weapon.cancel_reload()
	var muzzle := _player.weapon.get_muzzle_socket()
	var saved_pose := muzzle.transform
	_player.set_physics_process(false)
	muzzle.position += Vector3(0.07, 0.08, 0.03)
	muzzle.rotation.x += 0.3
	muzzle.scale = Vector3(1.3, 0.8, 0.75)
	await get_tree().process_frame
	await get_tree().process_frame
	_expect_span(4.0, "gun-only tilt and scale without a player physics tick")
	_check(absf((_to() - _from()).normalized().y) > 0.12, "beam follows pitch instead of projecting to XZ")
	muzzle.transform = saved_pose
	_player.set_physics_process(true)
	await _physics_ticks()

	_check(_player.request_weapon_slot(0).success, "start holstering")
	await _physics_ticks()
	_check(not _beam.visible, "beam hides during stow")
	await _finish_weapon_transition()
	_check(_player.weapon_holstered and not _beam.visible, "weapon on back: no beam")
	var hidden_image := await _capture("04_holstered.png")
	_check_rendered_beam(full_image, hidden_image, origin, direction)
	_check(_player.request_weapon_slot(0).success, "start drawing the equipped firearm")
	await _physics_ticks()
	_check(not _beam.visible, "no beam until draw completes")
	await _finish_weapon_transition()
	_check(_beam.visible, "draw completion restores the same instance")
	_check(muzzle.get_node_or_null("AimBeam3D") == _beam, "draw reuses the existing muzzle attachment")

	_set_aim(Vector3.RIGHT)
	await _physics_ticks(20)
	_expect_span(4.0, "after rotating")
	_player.avatar.set_process(false)
	var wall_direction := -muzzle.global_basis.z.normalized()
	var wall_center := muzzle.global_position + wall_direction * 2.15
	_wall = _add_box("Wall", wall_center, Vector3(3.0, 2.0, 0.30), Color("53616b"))
	_wall.global_basis = Basis.looking_at(wall_direction)
	# Isolate beam occlusion from the fixture wall pushing the avatar out of the way.
	_player.add_collision_exception_with(_wall)
	await _physics_ticks(4)
	_expect_span(2.0 - 0.025, "wall stop measured from the muzzle")
	await _capture("03_wall.png")
	_wall.global_position = muzzle.global_position
	await _physics_ticks(4)
	_check(absf(_wall.to_local(muzzle.global_position).z) < 0.15, "wall fixture actually contains the muzzle")
	_check(not _beam.is_visible_in_tree(), "beam stays off when the muzzle is inside a wall")
	_player.remove_collision_exception_with(_wall)
	_wall.queue_free()
	_player.avatar.set_process(true)
	await _physics_ticks(3)
	_expect_span(4.0, "wall removed")

	_player.position = Vector3(-1.0, 1.25, 0.5)
	_player.set_debug_scale_step(5)
	await _physics_ticks()
	_expect_span(4.0, "moving to a different elevation and scaling the avatar")
	_player.position = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.set_debug_scale_step(0)
	await _physics_ticks(8)

	_check(_player.equip_weapon("bp_baseball_bat", ""), "equip melee weapon")
	await _physics_ticks()
	_check(not _beam.visible and _beam.get_parent() == _player, "melee parks the beam on the player without rendering it")
	_check(not is_instance_valid(muzzle), "old muzzle was really freed on model rebuild")
	_check(_player.equip_weapon("bp_rifle", "mod_bullet_standard"), "equip another firearm")
	await _physics_ticks(8)
	_expect_span(4.0, "rifle with its own muzzle")
	_frame_beam_for_capture()
	await _capture("02_rifle.png")
	var sidearm := ItemRegistry.get_instance().get_item("weapon_pistol")
	_check(_player.equip_weapon_item_to_slot(sidearm, 1).success, "equip a backup sidearm")
	_check(_player.request_weapon_slot(1).success, "switch from rifle to sidearm")
	await _physics_ticks()
	_check(not _beam.visible, "stow stage of a slot switch hides the beam")
	await _finish_weapon_transition()
	_check(_player.active_weapon_slot == 1, "secondary slot is now held")
	_expect_span(4.0, "switched sidearm")
	_check(_player.find_children("AimBeam3D", "Node3D", true, false).size() == 1, "no extra beam on the stowed rifle")
	_player.weapon.hide()
	await _physics_ticks()
	_check(not _beam.visible, "hidden weapon presentation leaves no floating beam")
	_player.weapon.show()
	await _physics_ticks()
	_check(_beam.visible, "weapon presentation returns")
	_player.set_combat_enabled(false)
	_check(not _beam.visible, "loading or non-combat hides synchronously")
	_player.set_combat_enabled(true)
	await _physics_ticks()
	_check(_beam.visible, "combat resumes")
	_player.clear_all_equipped_weapons()
	await _physics_ticks()
	_check(not _beam.visible, "dropping all equipment clears the beam")
	_check(_player.equip_weapon("bp_pistol", "mod_bullet_standard"), "re-equip before health/lifecycle checks")
	_player.current_hp = 0
	await _physics_ticks()
	_check(not _beam.visible, "inactive player cannot retain a visible beam")
	_player.queue_free()
	await get_tree().process_frame
	_check(not is_instance_valid(_beam), "beam frees with its owning player")
	_finish()


func _physics_ticks(frames := 2) -> void:
	for _i in range(frames):
		await get_tree().physics_frame
	await get_tree().process_frame


func _finish_weapon_transition() -> void:
	for _i in range(80):
		if not bool(_player.get_weapon_transition_snapshot().active):
			await _physics_ticks()
			return
		await get_tree().physics_frame
	_check(false, "weapon transition did not finish")


func _set_aim(direction: Vector3) -> void:
	_player.aim_direction = direction
	_player.aim_yaw = atan2(-direction.x, -direction.z)


func _from() -> Vector3:
	return _ribbon.to_global(Vector3(0.0, -0.5, 0.0))


func _to() -> Vector3:
	return _ribbon.to_global(Vector3(0.0, 0.5, 0.0))


func _expect_span(expected: float, label: String) -> void:
	var muzzle := _player.weapon.get_muzzle_socket()
	_check(is_instance_valid(muzzle) and _beam.get_parent() == muzzle, label + ": parked on the current muzzle socket")
	if not is_instance_valid(muzzle):
		return
	var segment := _to() - _from()
	_check(_beam.is_visible_in_tree() and absf(segment.length() - expected) < 0.015,
		"%s: expected %.3f m span, got %.3f m" % [label, expected, segment.length()])
	_check(_from().distance_to(muzzle.global_position) < 0.002, label + ": no gap or body offset at origin")
	_check(segment.normalized().dot(-muzzle.global_basis.z.normalized()) > 0.9999, label + ": coaxial with the muzzle")
	_check(absf(_ribbon.global_basis.x.length() - 0.105) < 0.001, label + ": constant world width")


func _add_box(label: String, center: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var box := StaticBody3D.new()
	box.name = label
	box.position = center
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	box.add_child(collision)
	if not _output.is_empty():
		var mesh := BoxMesh.new()
		mesh.size = size
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		mesh.material = material
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		box.add_child(visual)
	add_child(box)
	return box


func _build_visual_environment() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("131921")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("a8bacd")
	world.environment.ambient_light_energy = 0.65
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	light.light_energy = 0.75
	light.shadow_enabled = true
	add_child(light)


func _frame_beam_for_capture() -> void:
	if _output.is_empty():
		return
	var center := _player.global_position.lerp(_to(), 0.47) + Vector3.UP * 0.2
	_player.camera.global_position = center + Vector3(0.0, 6.5, 5.0)
	_player.camera.look_at(center)
	var viewport_rect := get_viewport().get_visible_rect().grow(-16.0)
	_check(viewport_rect.has_point(_player.camera.unproject_position(_from()))
		and viewport_rect.has_point(_player.camera.unproject_position(_to())), "muzzle and complete tail are inside the screenshot")


func _capture(file_name: String) -> Image:
	if _output.is_empty():
		return null
	for _i in range(3):
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	_check(image.save_png(_output.path_join(file_name)) == OK, "saved " + file_name)
	return image


func _check_rendered_beam(held: Image, holstered: Image, origin: Vector3, direction: Vector3) -> void:
	if _output.is_empty():
		return
	var head := _player.camera.unproject_position(origin + direction * 1.60)
	var tail := _player.camera.unproject_position(origin + direction * 3.35)
	var tip := _player.camera.unproject_position(origin + direction * 4.00)
	var head_red := _red_strength(held, head)
	var tail_red := _red_strength(held, tail)
	var tip_red := _red_strength(held, tip)
	_check(head_red > 0.15, "ribbon produces visible red pixels")
	_check(tail_red < head_red * 0.72 and tip_red < 0.08, "ribbon visibly tapers to clear by its tip")
	_check(_red_strength(holstered, head) < 0.08, "holstering removes the red pixels")


func _red_strength(image: Image, point: Vector2) -> float:
	var strength := 0.0
	var sample_center := Vector2i(point.round())
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var sample := sample_center + Vector2i(dx, dy)
			if Rect2i(Vector2i.ZERO, image.get_size()).has_point(sample):
				var rgb := image.get_pixelv(sample)
				strength = maxf(strength, rgb.r - maxf(rgb.g, rgb.b))
	return strength


func _check(result: bool, description: String) -> void:
	_checks += 1
	if not result:
		_failures.append(description)


func _timeout() -> void:
	if not _finished:
		_check(false, "verification timed out")
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	for description in _failures:
		push_error(description)
	print("PLAYER_AIM_BEAM_VERIFY checks=", _checks, " failures=", _failures.size())
	QUITTER.schedule(self, 0 if _failures.is_empty() else 1)
