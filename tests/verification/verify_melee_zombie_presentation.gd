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
	check(triangles == 800, "small zombie geometry must have exactly 800 triangles")
	var expected = {"idle":3.2,"walking":1.6,"running":0.8,"attack":1.7,"hurt":0.8,"dead":2.4}
	for clip in expected:
		check(visual._player.has_animation(clip), "missing clip " + clip)
		if visual._player.has_animation(clip):
			check(absf(visual._player.get_animation(clip).length-expected[clip])<0.0001, "duration " + clip)
			check(visual._player.get_animation(clip).loop_mode == (Animation.LOOP_LINEAR if clip in ["idle", "walking", "running"] else Animation.LOOP_NONE), "loop " + clip)
	check(visual.get_meta("asset_version", "") == "v006", "formal asset version must be v006")
	check(visual.get_meta("skeleton_id", "") == "SKEL-MELEE-ZOMBIE01-005", "formal skeleton id")
	check(visual.get_presentation_snapshot().source == "blender_v006", "snapshot source version")
	var expected_texture := "res://assets/art/shared/textures/enemies/tex_color_85eaa809e59fa600fe6c.png"
	var texture_count := 0
	for material in visual._materials:
		var texture: Texture2D = material.albedo_texture
		check(texture != null, "albedo texture missing: white model")
		if texture != null:
			texture_count += 1
			var actual_size := texture.get_size()
			if OS.get_cmdline_user_args().has("--negative-texture"):
				actual_size = Vector2(2048, 2048)
			check(actual_size == Vector2(256, 256), "albedo texture must load at 256x256")
			check(texture.resource_path == expected_texture, "albedo must use content-hash shared PNG")
	check(texture_count > 0, "no textured materials")
	var root_bone := skeleton.find_bone("Root") if skeleton != null else -1
	for clip in expected:
		for phase in [0.0, 0.48, 1.0]:
			visual._player.play(clip)
			visual._player.seek(float(expected[clip]) * phase, true)
			if root_bone >= 0:
				# Godot骨姿势含静止轴向；静止矩阵不是单位矩阵，必须与绑定静止矩阵比较。
				check(skeleton.get_bone_pose(root_bone).is_equal_approx(skeleton.get_bone_rest(root_bone)), "Root rest matrix drift " + clip)
	var expected_states := {"dormant":"idle", "idle":"running", "patrol":"running",
		"alert":"idle", "chase":"running", "search":"running", "return":"running",
		"telegraph":"attack", "attack":"attack", "recovery":"attack", "stagger":"hurt",
		"dead":"dead", "defeated":"idle", "death_warning":"idle"}
	for state in Enemy3D.VALID_STATES:
		e.avatar.sync_presentation(state, 0.1, 2.0, 0.38, 0.34)
		check(visual.get_presentation_snapshot().state == state, "state " + state)
		check(expected_states.has(state), "unmapped state " + state)
		check(str(visual.get_presentation_snapshot().clip) == str(expected_states.get(state, "missing")), "explicit state output " + state)
	# 满速固定2m/s，明确检验0.62进入/0.50退出及中间迟滞，不放宽为任意移动段。
	visual.sync_state("idle", 0.0, 0.0, 0.38, 0.34, 2.0)
	for row in [[0.60, "walking"], [0.619, "walking"], [0.62, "running"],
		[0.60, "running"], [0.50, "running"], [0.499, "walking"], [0.60, "walking"]]:
		visual.sync_state("patrol", 0.1, float(row[0]) * 2.0, 0.38, 0.34, 2.0)
		check(str(visual.get_presentation_snapshot().clip) == str(row[1]), "patrol speed hysteresis " + str(row))
	visual.sync_state("chase", 0.1, 0.2, 0.38, 0.34, 2.0)
	check(str(visual.get_presentation_snapshot().clip) == "running", "low-speed chase remains running")
	visual.sync_state("patrol", 0.1, 9.0, 0.38, 0.34, 2.0)
	check(str(visual.get_presentation_snapshot().clip) == "running", "high-speed patrol must run")
	e.avatar.sync_presentation("telegraph", 0.38, 0.0, 0.38, 0.34)
	var before: float = visual.get_presentation_snapshot().sample_time
	e.avatar.sync_presentation("attack", 0.0, 0.0, 0.38, 0.34)
	check(is_equal_approx(before, visual.get_presentation_snapshot().sample_time), "attack boundary discontinuity")
	e.avatar.sync_presentation("recovery", 0.34, 0.0, 0.38, 0.34)
	check(absf(visual.get_presentation_snapshot().sample_time-1.7)<0.04, "recovery end")
	e.avatar.sync_presentation("idle", 0.0, 0.0, 0.38, 0.34)
	visual.flash_hit()
	visual._process(0.01)
	# 判据是「闪白真的点亮了」= 自发光**能量**被推上去，不是「自发光开关被翻过」。
	# 后者在 Godot 里是 shader 变体切换（USE_EMISSION），每翻一次要重建 GPU 管线
	# （实测 +98ms），而闪白每次受击翻两次 ⇒ 每打中一下卡一下（2026-10-31 定位）。
	check(
		not visual._materials.is_empty() and visual._materials[0].emission_energy_multiplier > 0.1,
		"hit flash missing"
	)
	e.avatar.sync_presentation("idle", 0.0, 0.0, 0.38, 0.34)
	check(visual.get_presentation_snapshot().clip == "hurt", "non-stagger hurt overlay missing")
	check(absf(before - 1.7 * 0.48) < 0.0001, "attack must sample 48 percent")
	await _check_head_lift(e)
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
		print("MELEE_ZOMBIE_PRESENTATION_OK states=%d clips=6 bones=16 triangles=%d texture=256 version=v006 death=goo_immediate collision_unchanged=true" % [Enemy3D.VALID_STATES.size(), triangles])
	else:
		for failure in failures: push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _check_head_lift(normal: Enemy3D) -> void:
	var strong := _spawn_head_sample("melee_chaser_strong")
	var borrowed := _spawn_head_sample("egt_blobulon")
	normal.avatar.set_process(true)
	await get_tree().process_frame
	await get_tree().process_frame
	check(borrowed.avatar.has_formal_normal(), "borrowed model must exercise the same visual asset")
	if borrowed.avatar.has_formal_normal():
		check(not borrowed.avatar._formal_normal_root._player.has_animation_library(&"head_lift"), "borrowed model must keep authored pose")
	borrowed.free()
	var expected := {"idle": 10.0, "walking": 12.0, "running": 14.0, "attack": 8.0}
	var comparisons := 0
	for enemy: Enemy3D in [normal, strong]:
		var visual := enemy.avatar._formal_normal_root
		var player := visual._player as AnimationPlayer
		var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
		var socket := enemy.avatar.find_child("StrongEyeSocket3D", true, false) as BoneAttachment3D
		var glow := socket.find_child("StrongEyeGlow3D", true, false) as StrongVariantEyeGlow3D if socket != null else null
		check(glow != null, enemy.enemy_kind + " pupil attachment was not finalized")
		if glow == null:
			continue
		var head := skeleton.find_bone("Head")
		var original_offsets: Array[Vector3] = [Vector3(0.189065, 0.087930, 0.449892), Vector3(-0.168118, 0.079885, 0.473035)]
		for clip: String in expected:
			var original := player.get_animation(clip)
			var lifted_name := "head_lift/" + clip
			check(player.has_animation(lifted_name), enemy.enemy_kind + " missing " + lifted_name)
			if not player.has_animation(lifted_name):
				continue
			var lifted := player.get_animation(lifted_name)
			check(is_equal_approx(original.length, lifted.length) and original.loop_mode == lifted.loop_mode, clip + " playback timing changed")
			for phase: float in ([0.12, 0.48, 0.55, 0.92] if clip == "attack" else [0.12, 0.49, 0.8]):
				var degrees := 0.0 if clip == "attack" and phase in [0.48, 0.55] else float(expected[clip])
				var sampled_at := original.length * phase
				player.play(clip)
				player.seek(sampled_at, true)
				var poses: Array[Transform3D] = []
				for index in skeleton.get_bone_count():
					poses.append(skeleton.get_bone_pose(index))
				enemy.rotation.y = -1.1 + phase
				player.play(lifted_name)
				player.seek(sampled_at, true)
				for index in skeleton.get_bone_count():
					var actual := skeleton.get_bone_pose(index)
					if index == head:
						var target := poses[index].basis.get_rotation_quaternion() * Quaternion(Vector3.LEFT, deg_to_rad(degrees))
						check(rad_to_deg(actual.basis.get_rotation_quaternion().angle_to(target.normalized())) < 0.25, clip + " unexpected head pitch at " + str(phase))
						check(actual.origin.is_equal_approx(poses[index].origin), "Head translation changed")
					else:
						check(actual.is_equal_approx(poses[index]), clip + " changed a non-Head bone")
				# Do not move the attachments here: the production bone signal must update them.
				await get_tree().process_frame
				await get_tree().process_frame
				var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(head)
				var eyes := glow.get_eyes()
				check(eyes.size() == 2, "expected both pupil lights")
				if eyes.size() == 2:
					for index in 2:
						check(eyes[index].position.is_equal_approx(original_offsets[index]), "pupil moved in Head local space")
						check(eyes[index].global_position.distance_to(head_world * original_offsets[index]) < 0.001, "pupil did not follow corrected Head")
				comparisons += 1
		visual._blend_left = 0.0
		visual._hurt_time = 10.0
		visual.sync_state("attack", 0.0, 0.0, 0.38, 0.34, 2.45)
		check(player.current_animation == &"head_lift/attack" and is_equal_approx(player.current_animation_position, 0.816), "actual contact frame must still sample 48 percent")
		visual.sync_state("idle", 0.0, 0.0, 0.38, 0.34, 2.45)
		visual.sync_state("chase", 0.0, 2.45, 0.38, 0.34, 2.45)
		visual._process(0.08)
		check(player.current_animation == &"head_lift/running" and visual._blend_left > 0.0, "native locomotion blend no longer active")
		check(not player.has_animation("head_lift/hurt") and not player.has_animation("head_lift/dead"), "hurt/dead must not be lifted")
	strong.free()
	print("SMALL_ZOMBIE_HEAD_LIFT_SAMPLES=", comparisons, " kinds=normal,strong borrow_unchanged=true")


func _spawn_head_sample(kind: String) -> Enemy3D:
	var enemy := ENEMY.instantiate() as Enemy3D
	add_child(enemy)
	enemy.apply_profile(kind)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	return enemy
