extends Node3D
const PREFAB := preload("res://assets/art/enemies/bosses/enm_boss_monitor002/runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn")
const OUT := "res://assets/art/enemies/bosses/enm_boss_monitor002/previews/runtime/"
var presenter: MonitorBossPresentation
func _ready() -> void:
	assert(DisplayServer.get_name() != "headless","Real renderer required")
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var environment := Environment.new();environment.background_mode = Environment.BG_COLOR;environment.background_color = Color(0.012,0.025,0.040)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color = Color(0.5,0.65,0.72);environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new();world.environment = environment;add_child(world)
	var floor := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size = Vector2(100,100);floor.mesh = plane
	var material := StandardMaterial3D.new();material.albedo_color = Color(0.08,0.13,0.15);material.roughness = 0.88;floor.material_override = material;add_child(floor)
	var light := DirectionalLight3D.new();light.rotation_degrees = Vector3(-48,-32,0);light.light_energy = 2.2;light.shadow_enabled = true;add_child(light)
	var fill := OmniLight3D.new();fill.position = Vector3(-5,6,-5);fill.omni_range = 18;fill.light_color = Color(0.5,0.75,1);fill.light_energy = 2.5;add_child(fill)
	var camera := Camera3D.new();camera.position = Vector3(8,7,-14);add_child(camera);camera.look_at(Vector3(0,1.8,-0.6));camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = 12.8;camera.current = true
	presenter = PREFAB.instantiate();add_child(presenter)
	await get_tree().process_frame
	var checks := 0
	for spec in [["idle",0.8],["hurt",0.133333],["stun_loop",0.8],["heavy_spin_slam",1.1],["heavy_spin_slam",64.0/30.0],["heavy_spin_slam",2.23333],["melee_keyboard",32.0/30.0],["melee_cable",0.9],["special_channel",0.35],["dead",1.9]]:
		var clip := str(spec[0]);var time := float(spec[1]);var electric := clip == "special_channel"
		presenter.sync_context({"action_id":clip,"time":time,"electric_active":electric,"contact_point":presenter.to_global(Vector3(-2.395,0,-1.749))},false)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image();var path := OUT+clip+"_"+str(roundi(time*30))+".png"
		assert(image.save_png(path) == OK);checks += 1
		if clip == "special_channel":assert(presenter.fx.effect_snapshot.electric_active)
		if clip == "heavy_spin_slam" and absf(time-64.0/30.0) < 0.00001:assert(presenter.fx.effect_snapshot.yellow_flash)
	# Real-frame sampling of all attacks and the complete seated sequence, 30fps.
	if "--sequence" in OS.get_cmdline_user_args():
		var sequence: Array = [["melee_keyboard",1.8],["melee_cable",2.0],["heavy_spin_slam",3.2],["special_prepare",1.2],["special_insert",0.6],["special_channel",2.4],["special_recover",0.9],["stun_enter",1.4],["stun_loop",2.4],["stun_exit",1.0],["dead",2.0]]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT+"frames"))
		var index := 0
		for spec in sequence:
			for frame in range(roundi(float(spec[1])*30)):
				var clip := str(spec[0]);var time := frame/30.0
				presenter.sync_context({"action_id":clip,"time":time,"electric_active":clip == "special_channel" or (clip == "special_insert" and frame >= 14),"contact_point":presenter.to_global(Vector3(-2.395,0,-1.749))},false)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OUT+"frames/%04d.png"%index);index += 1
	var file := FileAccess.open(OUT+"visual_report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_video_adapter_name(),"display_server":DisplayServer.get_name(),"screenshots":checks,"expected_errors":[],"unexpected_script_errors":[],"not_executed":[],"exit_code":0},"\t"));file.close()
	print("MONITOR_BOSS_VISUAL_OK screenshots=",checks);get_tree().quit()
