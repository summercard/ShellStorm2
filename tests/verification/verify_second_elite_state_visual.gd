extends "res://tests/verification/support/SecondEliteStateFixture.gd"
var camera: Camera3D
var label: Label
var output := ""
var frame_index := 0
var measurements: Array = []
var show_hit_volumes := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("SECOND_ELITE_STATE_VISUAL requires a real renderer")
		get_tree().quit(1)
		return
	output = OS.get_environment("ELITE_QA_DIR")
	if output.is_empty():output = OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")+"/second_elite"
	show_hit_volumes = "--hit-volumes" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(output+"/frames")
	setup_ground()
	setup_visual_stage()
	await get_tree().physics_frame
	var stages := [["idle",30],["walk",102],["run",102],["attack",162],["hurt",118]] if show_hit_volumes else [["walk",240],["run",240],["attack",162],["hurt",118],["death",270]]
	if "--gait-only" in OS.get_cmdline_user_args():
		stages = [["walk",420],["run",420]]
	for spec in stages:
		await record_stage(str(spec[0]),int(spec[1]))
	clean_effects()
	await get_tree().process_frame
	var file := FileAccess.open(output+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_video_adapter_name(),
		"display_server":DisplayServer.get_name(),"frames":frame_index,"fps":30,
		"measurements":measurements,"checks":checks,"failures":failures,"hit_volume_overlay":show_hit_volumes,
		"expected_errors":[],"not_executed":[],"source_material":"v002 PBR"},"\t"))
	file.close()
	finish("SECOND_ELITE_STATE_VISUAL_OK")

func setup_visual_stage() -> void:
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.065,0.09,0.13)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7,0.8,1.0)
	environment.ambient_light_energy = 0.25
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100,100)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.14,0.19,0.24)
	material.roughness = 0.9
	floor_mesh.material_override = material
	add_child(floor_mesh)
	var grid_material := StandardMaterial3D.new()
	grid_material.albedo_color = Color(0.24,0.33,0.4)
	for index in range(-30,31):
		for axis in 2:
			var line := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(60,0.008,0.015) if axis==0 else Vector3(0.015,0.008,60)
			line.mesh = box
			line.material_override = grid_material
			line.position = Vector3(0,0.005,index) if axis==0 else Vector3(index,0.005,0)
			add_child(line)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50,-35,0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 6.3
	camera.current = true
	add_child(camera)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	label = Label.new()
	label.position = Vector2(24,20)
	label.add_theme_font_size_override("font_size",22)
	canvas.add_child(label)

func record_stage(stage: String, frames: int) -> void:
	var enemy := make_enemy()
	enemy._overhead_health_root.hide()
	if show_hit_volumes:
		add_hit_volume_overlay(enemy)
	var target := make_target(Vector3(0,0.05,-18 if stage=="run" else -1.8))
	if stage == "walk":
		target.remove_from_group("player_3d")
		enemy.transition_to("patrol")
		enemy._patrol_target = Vector3(0,0,-20)
	elif stage == "idle":
		target.remove_from_group("player_3d")
	else:
		bind_target(enemy,target)
		enemy.transition_to("chase")
		enemy._attack_timer = 100.0
		if stage=="attack":enemy.transition_to("telegraph")
		elif stage=="hurt":enemy.take_damage(1,false,Vector3.RIGHT)
		elif stage=="death":enemy._die()
	# Let the actual scene-tree callbacks run. No manual state/pose loop substitutes for AI.
	enemy.avatar.set_process(true)
	enemy.avatar._formal_elite_root.set_process(true)
	enemy.set_process(true)
	if stage != "death":enemy.set_physics_process(true)
	var previous := hip_position(enemy)
	var max_jump := 0.0
	var minimum_facing_dot := 1.0
	var floor_clearance := 0.0
	var maximum_sole_error := 0.0
	var boot_heights := Vector2.ZERO
	var previous_stance: Dictionary = {}
	var support_travel := 0.0
	var support_slip := 0.0
	var support_samples := 0
	var playback_min := INF
	var playback_max := 0.0
	var maximum_contact_error := 0.0
	var contact_samples := 0
	for frame in frames:
		await get_tree().physics_frame
		if not is_instance_valid(enemy):
			check(false,"Visual stage %s freed its model early"%stage)
			break
		if stage == "run":
			target.position.z = enemy.position.z - 18.0
			MonsterAIManager.set_hunt_target(enemy, target)
		var next := hip_position(enemy)
		if frame>15:max_jump=maxf(max_jump,next.distance_to(previous))
		previous=next
		var velocity := Vector3(enemy.get_real_velocity().x,0,enemy.get_real_velocity().z)
		if stage in ["walk","run"] and frame>30 and velocity.length()>0.2:
			minimum_facing_dot=minf(minimum_facing_dot,(-enemy.global_basis.z).normalized().dot(velocity.normalized()))
		camera.position=enemy.position+(Vector3(2.0,2.6,-8.0) if show_hit_volumes else Vector3(5.4,4.0,-7.0))
		camera.look_at(enemy.position+Vector3(0,2.15 if show_hit_volumes else 1.35,0))
		var visual: Dictionary=enemy.avatar._formal_elite_root.get_presentation_snapshot()
		if stage in ["walk", "run"] and visual.clip == stage and frame > 30:
			var stance := sample_stance(enemy)
			if not previous_stance.is_empty():
				var forward_travel := float(previous_stance.root_z) - float(stance.root_z)
				for foot in ["L_Foot", "R_Foot"]:
					var before: Vector2 = previous_stance[foot]
					var now: Vector2 = stance[foot]
					var world_slide := now.x - before.x
					# Use consecutive loaded-foot samples. A foot swinging forwards
					# at a heel strike cannot be held by a change in playback rate.
					if forward_travel > 0.001 and maxf(before.y, now.y) < 0.04 and world_slide + forward_travel > 0.25 * forward_travel:
						support_travel += forward_travel
						support_slip += absf(world_slide)
						support_samples += 1
			previous_stance = stance
			playback_min = minf(playback_min, float(visual.playback_speed))
			playback_max = maxf(playback_max, float(visual.playback_speed))
		label.text="ELITE 02  /  %s\nstate: %s    clip: %s    time: %.2f\nhits: %d    physical speed: %.2f m/s"%[stage,enemy.ai_state,visual.clip,visual.clip_time,target.damage_events,velocity.length()]
		var sample_frame := int(frames/4.0)*2
		var sample_sole := show_hit_volumes and frame in [sample_frame - 8, sample_frame, sample_frame + 8]
		if frame%2==0 and (not show_hit_volumes or sample_sole):
			await RenderingServer.frame_post_draw
			if enemy.is_on_floor() and stage != "death":
				var soles: Dictionary = enemy.avatar.get_animated_elite_root().call("_sample_foot_bottoms")
				var sole_height := minf(soles["L_Foot"], soles["R_Foot"])
				maximum_contact_error = maxf(maximum_contact_error, absf(sole_height + 0.001))
				contact_samples += 1
			var center := camera.unproject_position(enemy.position+Vector3(0,1.3,0))
			var size := get_viewport().get_visible_rect().size
			check(center.x>size.x*0.05 and center.x<size.x*0.95 and center.y>size.y*0.05 and center.y<size.y*0.95,"Actor is outside the visual frame")
			if sample_sole:
				var contact := sample_mesh_contact(enemy)
				maximum_sole_error = maxf(maximum_sole_error, contact.y)
				if frame == sample_frame:
					floor_clearance = contact.x
					boot_heights = Vector2(contact.z, contact.w)
			# 保留逐帧行为和接地采样，只落盘各阶段代表帧。
			if frame==sample_frame:
				check(get_viewport().get_texture().get_image().save_png(output+"/"+stage+".png")==OK,"Cannot save representative frame")
				if not sample_sole:
					var contact := sample_mesh_contact(enemy)
					floor_clearance = contact.x
					boot_heights = Vector2(contact.z, contact.w)
				if stage in ["idle", "walk", "attack", "hurt"]:
					check(absf(minf(boot_heights.x, boot_heights.y) + 0.001) < 0.0005, "Supporting boot must sink exactly one millimeter during %s (%.4f m)" % [stage, minf(boot_heights.x, boot_heights.y)])
				if show_hit_volumes and stage == "idle":
					check(maxf(boot_heights.x, boot_heights.y) < 0.001, "Both idle boot soles must touch the floor")
				if show_hit_volumes and stage in ["idle", "run"]:
					await capture_boot_contact(enemy, stage)
			if not show_hit_volumes or frame==sample_frame:
				frame_index+=1
	if stage in ["walk","run"]:
		check(max_jump<0.25,"Real renderer observed a locomotion teleport in %s"%stage)
		check(minimum_facing_dot>0.9,"Real rendered movement runs backwards in %s"%stage)
		if not show_hit_volumes:
			var slip_limit := 0.17 if stage == "walk" else 0.37
			check(support_samples >= 30, "Too few ground contact samples for %s" % stage)
			check(support_slip < support_travel * slip_limit, "Supporting boot slides too far during %s" % stage)
	if show_hit_volumes:
		check(maximum_sole_error < 0.005, "Boot volume base separates from its own mesh sole during %s (%.3f m)" % [stage, maximum_sole_error])
	if stage != "death":
		check(contact_samples >= (2 if show_hit_volumes else 30), "Too few grounded samples during %s" % stage)
		check(maximum_contact_error < 0.0005, "Boot lifts above the one millimeter ground inset during %s (%.5f m)" % [stage, maximum_contact_error])
	var measurement := {"stage":stage,"max_hip_step_m":max_jump,"minimum_facing_dot":minimum_facing_dot,
		"sample_lowest_mesh_y_m":floor_clearance,"left_boot_y_m":boot_heights.x,"right_boot_y_m":boot_heights.y,
		"max_boot_volume_sole_error_m":maximum_sole_error,"hits":target.damage_events}
	measurement["grounded_contact_samples"] = contact_samples
	measurement["max_grounded_inset_error_m"] = maximum_contact_error
	if support_samples > 0:
		measurement["support_samples"] = support_samples
		measurement["support_slip_per_meter"] = support_slip / support_travel
		measurement["playback_speed_range"] = [playback_min, playback_max]
	measurements.append(measurement)
	enemy.queue_free()
	target.queue_free()
	clean_effects()
	await get_tree().process_frame


func sample_stance(enemy: Enemy3D) -> Dictionary:
	var visual := enemy.avatar.get_animated_elite_root()
	var skeleton := visual.find_child("Skeleton3D", true, false) as Skeleton3D
	var sole_heights: Dictionary = visual.call("_sample_foot_bottoms")
	var stance := {"root_z": enemy.global_position.z}
	for side in ["L", "R"]:
		var foot: String = side + "_Foot"
		var ankle := skeleton.get_bone_global_pose(skeleton.find_bone(foot)).origin
		var toe := skeleton.get_bone_global_pose(skeleton.find_bone(side + "_ToeBase")).origin
		stance[foot] = Vector2(skeleton.to_global((ankle + toe) * 0.5).z, sole_heights[foot])
	return stance


func capture_boot_contact(enemy: Enemy3D, stage: String) -> void:
	camera.size = 2.25
	camera.position = enemy.position + Vector3(1.0, 0.86, -5.5)
	camera.look_at(enemy.position + Vector3(0, 0.46, 0))
	await RenderingServer.frame_post_draw
	check(get_viewport().get_texture().get_image().save_png(output + "/" + stage + "_boot_contact.png") == OK, "Cannot save boot contact close-up")
	camera.size = 6.3


func sample_mesh_contact(enemy: Enemy3D) -> Vector4:
	var model := enemy.avatar.get_animated_elite_root().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var baked := model.bake_mesh_from_current_skeleton_pose()
	if baked == null:
		check(false, "Cannot sample the rendered skinned mesh")
		return Vector4(INF, INF, INF, INF)
	var lowest := INF
	var foot_bottoms := {"L_Foot": INF, "R_Foot": INF}
	for surface in baked.get_surface_count():
		var vertices: PackedVector3Array = baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var source := model.mesh.surface_get_arrays(surface)
		var weights: PackedFloat32Array = source[Mesh.ARRAY_WEIGHTS]
		var binds: PackedInt32Array = source[Mesh.ARRAY_BONES]
		@warning_ignore("integer_division")
		var influences := weights.size() / vertices.size()
		for vertex in vertices.size():
			var height := model.to_global(vertices[vertex]).y
			lowest = minf(lowest, height)
			var first := vertex * influences
			var dominant := first
			for index in range(first + 1, first + influences):
				if weights[index] > weights[dominant]:
					dominant = index
			var bone := String(model.skin.get_bind_name(binds[dominant])).replace("_ToeBase", "_Foot")
			if foot_bottoms.has(bone):
				foot_bottoms[bone] = minf(foot_bottoms[bone], height)
	var maximum_error := 0.0
	if show_hit_volumes:
		var proxy := enemy.get_animated_hit_volume_body()
		for foot in foot_bottoms:
			var volume := proxy.get_node("Volume_" + foot) as CollisionShape3D
			var half_size := (volume.shape as BoxShape3D).size * 0.5
			var bottom := INF
			for x in [-1.0, 1.0]:
				for y in [-1.0, 1.0]:
					for z in [-1.0, 1.0]:
						bottom = minf(bottom, volume.to_global(Vector3(x, y, z) * half_size).y)
			maximum_error = maxf(maximum_error, absf(bottom - foot_bottoms[foot]))
	return Vector4(lowest, maximum_error, foot_bottoms["L_Foot"], foot_bottoms["R_Foot"])


func add_hit_volume_overlay(enemy: Enemy3D) -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.20, 0.88, 1.0, 0.80)
	material.no_depth_test = true
	for volume in enemy.get_animated_hit_volumes():
		var display_box := ImmediateMesh.new()
		var half_size := (volume.shape as BoxShape3D).size * 0.5
		display_box.surface_begin(Mesh.PRIMITIVE_LINES, material)
		for axis in 3:
			for side_a in [-1.0, 1.0]:
				for side_b in [-1.0, 1.0]:
					var start := Vector3.ZERO
					start[axis] = -half_size[axis]
					start[(axis + 1) % 3] = half_size[(axis + 1) % 3] * side_a
					start[(axis + 2) % 3] = half_size[(axis + 2) % 3] * side_b
					var end := start
					end[axis] = half_size[axis]
					display_box.surface_add_vertex(start)
					display_box.surface_add_vertex(end)
		display_box.surface_end()
		var display := MeshInstance3D.new()
		display.mesh = display_box
		display.material_override = material
		display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		volume.add_child(display)
