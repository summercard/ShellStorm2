extends "res://tests/verification/support/SecondEliteStateFixture.gd"
var camera: Camera3D
var label: Label
var output := ""
var frame_index := 0
var measurements: Array = []

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("SECOND_ELITE_STATE_VISUAL requires a real renderer")
		get_tree().quit(1)
		return
	output = OS.get_environment("ELITE_QA_DIR")
	if output.is_empty():output = OS.get_environment("SHELLSTORM_VERIFICATION_OUTPUT")+"/second_elite"
	DirAccess.make_dir_recursive_absolute(output+"/frames")
	setup_ground()
	setup_visual_stage()
	await get_tree().physics_frame
	for spec in [["walk",150],["run",150],["attack",162],["hurt",118],["death",270]]:
		await record_stage(str(spec[0]),int(spec[1]))
	clean_effects()
	await get_tree().process_frame
	var file := FileAccess.open(output+"/report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_video_adapter_name(),
		"display_server":DisplayServer.get_name(),"frames":frame_index,"fps":30,
		"measurements":measurements,"checks":checks,"failures":failures,
		"expected_errors":[],"not_executed":[],"source_material":"original untextured gray"},"\t"))
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
	var target := make_target(Vector3(0,0.05,-18 if stage=="run" else -1.8))
	if stage == "walk":
		target.remove_from_group("player_3d")
		enemy.transition_to("patrol")
		enemy._patrol_target = Vector3(0,0,-20)
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
	for frame in frames:
		await get_tree().physics_frame
		if not is_instance_valid(enemy):
			check(false,"Visual stage %s freed its model early"%stage)
			break
		var next := hip_position(enemy)
		if frame>15:max_jump=maxf(max_jump,next.distance_to(previous))
		previous=next
		var velocity := Vector3(enemy.get_real_velocity().x,0,enemy.get_real_velocity().z)
		if stage in ["walk","run"] and frame>30 and velocity.length()>0.2:
			minimum_facing_dot=minf(minimum_facing_dot,(-enemy.global_basis.z).normalized().dot(velocity.normalized()))
		camera.position=enemy.position+Vector3(5.4,4.0,-7.0)
		camera.look_at(enemy.position+Vector3(0,1.35,0))
		var visual: Dictionary=enemy.avatar._formal_elite_root.get_presentation_snapshot()
		label.text="ELITE 02  /  %s\nstate: %s    clip: %s    time: %.2f\nhits: %d    physical speed: %.2f m/s"%[stage,enemy.ai_state,visual.clip,visual.clip_time,target.damage_events,velocity.length()]
		if frame%2==0:
			await RenderingServer.frame_post_draw
			var center := camera.unproject_position(enemy.position+Vector3(0,1.3,0))
			var size := get_viewport().get_visible_rect().size
			check(center.x>size.x*0.05 and center.x<size.x*0.95 and center.y>size.y*0.05 and center.y<size.y*0.95,"Actor is outside the visual frame")
			check(get_viewport().get_texture().get_image().save_png(output+"/frames/%04d.png"%frame_index)==OK,"Cannot save visual frame")
			if frame==frames/2:
				get_viewport().get_texture().get_image().save_png(output+"/"+stage+".png")
			frame_index+=1
	if stage in ["walk","run"]:
		check(max_jump<0.25,"Real renderer observed a locomotion teleport in %s"%stage)
		check(minimum_facing_dot>0.9,"Real rendered movement runs backwards in %s"%stage)
	measurements.append({"stage":stage,"max_hip_step_m":max_jump,"minimum_facing_dot":minimum_facing_dot,"hits":target.damage_events})
	enemy.queue_free()
	target.queue_free()
	clean_effects()
	await get_tree().process_frame
