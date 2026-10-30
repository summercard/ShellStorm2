extends Node3D
const ENEMY = preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
func _ready() -> void:
	var e = ENEMY.instantiate()
	add_child(e)
	e.set_physics_process(false)
	e.configure_from_enemy_data({"enemy_type":"melee_chaser", "name":"暗影小菌猪"})
	await get_tree().process_frame
	check(e.enemy_data.name == "暗影小僵尸", "legacy display name")
	check(e.avatar.has_formal_normal(), "formal normal missing")
	check(is_equal_approx(float(e.collision_shape.shape.height), 1.3), "collision changed")
	check(e.avatar.get_component_snapshot().component_count == 2, "component count")
	var visual = e.avatar._formal_normal_root
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var expected_bones := ["Root", "Hip", "Waist", "Spine02", "Neck", "Head",
		"L_Clavicle", "L_Upperarm", "L_Forearm", "R_Clavicle", "R_Upperarm", "R_Forearm",
		"L_Thigh", "L_Calf", "R_Thigh", "R_Calf"]
	check(skeleton != null and skeleton.get_bone_count() == expected_bones.size(), "optimized skeleton must have 16 bones")
	if skeleton != null:
		for bone_name in expected_bones:
			check(skeleton.find_bone(bone_name) >= 0, "required body bone missing: " + bone_name)
		for bone in range(skeleton.get_bone_count()):
			var bone_name := skeleton.get_bone_name(bone)
			check(bone_name in expected_bones, "unexpected bone: " + bone_name)
			for forbidden in ["Thumb", "Index", "Middle", "Pinky", "Ring", "Hand", "Foot", "Toe"]:
				check(not forbidden in bone_name, "removed hand/foot/finger bone remains: " + bone_name)
	var triangles := 0
	for mesh_instance in visual.find_children("*", "MeshInstance3D", true, false):
		for surface in range(mesh_instance.mesh.get_surface_count()):
			triangles += mesh_instance.mesh.surface_get_array_index_len(surface) / 3
	if OS.get_cmdline_user_args().has("--negative-budget"):
		triangles = 801
	check(triangles > 0 and triangles <= 800, "small zombie triangle budget at most 800")
	var expected = {"idle":3.2,"walking":1.6,"running":0.8,"attack":1.7,"hurt":0.8,"dead":2.4}
	for clip in expected:
		check(visual._player.has_animation(clip), "missing clip " + clip)
		if visual._player.has_animation(clip):
			check(absf(visual._player.get_animation(clip).length-expected[clip])<0.04, "duration " + clip)
			check(visual._player.get_animation(clip).loop_mode == (Animation.LOOP_LINEAR if clip in ["idle", "walking", "running"] else Animation.LOOP_NONE), "loop " + clip)
	var walking_states: Array[String] = []
	for state in Enemy3D.VALID_STATES:
		e.avatar.sync_presentation(state, 0.1, 2.0, 0.38, 0.34)
		check(visual.get_presentation_snapshot().state == state, "state " + state)
		if str(visual.get_presentation_snapshot().clip) == "walking":
			walking_states.append(state)
	check(walking_states == ["patrol"], "walking clip used outside patrol: " + str(walking_states))
	# 反向对照：接近玩家时不再按速度切档，低速追击也必须是跑步；巡逻高速也必须是走路。
	e.avatar.sync_presentation("chase", 0.1, 0.2, 0.38, 0.34)
	check(str(visual.get_presentation_snapshot().clip) == "running", "low-speed chase is not running")
	e.avatar.sync_presentation("patrol", 0.1, 9.0, 0.38, 0.34)
	check(str(visual.get_presentation_snapshot().clip) == "walking", "high-speed patrol is not walking")
	e.avatar.sync_presentation("telegraph", 0.38, 0.0, 0.38, 0.34)
	var before: float = visual.get_presentation_snapshot().sample_time
	e.avatar.sync_presentation("attack", 0.0, 0.0, 0.38, 0.34)
	check(is_equal_approx(before, visual.get_presentation_snapshot().sample_time), "attack boundary discontinuity")
	e.avatar.sync_presentation("recovery", 0.34, 0.0, 0.38, 0.34)
	check(absf(visual.get_presentation_snapshot().sample_time-1.7)<0.04, "recovery end")
	e.avatar.sync_presentation("idle", 0.0, 0.0, 0.38, 0.34)
	visual.flash_hit()
	visual._process(0.01)
	check(not visual._materials.is_empty() and visual._materials[0].emission_enabled, "hit flash missing")
	e.avatar.sync_presentation("idle", 0.0, 0.0, 0.38, 0.34)
	check(visual.get_presentation_snapshot().clip == "hurt", "non-stagger hurt overlay missing")
	var scale_before: Vector3 = e.scale
	e._die()
	check(not e.is_in_group("enemy_3d"), "dead still in enemy group")
	# Current goo-death contract: hide immediately and free at the end of the frame.
	check(not e.avatar.visible, "death frame kept zombie model visible")
	check(e.is_queued_for_deletion(), "goo death did not queue immediate removal")
	check(e.scale.is_equal_approx(scale_before), "death changed enemy scale")
	check(not e.is_in_group("enemy_death_visual_3d"), "goo death kept a corpse group member")
	await get_tree().process_frame
	check(not is_instance_valid(e), "goo death kept a corpse after the frame")
	var elite = ENEMY.instantiate()
	add_child(elite)
	elite.set_physics_process(false)
	elite.configure_from_enemy_data({"enemy_type":"melee_chaser", "name":"专名", "is_elite":true})
	check(not elite.avatar.has_formal_normal(), "elite double model")
	check(elite.enemy_data.name == "专名", "elite renamed")
	elite.free()
	await get_tree().process_frame
	if failures.is_empty():
		print("MELEE_ZOMBIE_PRESENTATION_OK states=12 clips=6 bones=16 triangles=%d death=goo_immediate collision_unchanged=true" % triangles)
	else:
		for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)
