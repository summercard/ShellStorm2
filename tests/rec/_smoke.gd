extends Node3D
## SSE 冒烟：验证 SSH(session 0) 下 Godot 能否离屏渲染并保存 PNG。
## godot --path . res://tests/rec/_smoke.tscn --resolution 960x540

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.2, 4.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.6, 0.0))
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	mi.mesh = sphere
	mi.position = Vector3(0.0, 0.6, 0.0)
	add_child(mi)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.15)
	mi.set_surface_override_material(0, mat)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	light.light_energy = 1.6
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.10, 0.14)
	e.ambient_light_color = Color(0.4, 0.45, 0.6)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	for i in range(8):
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://tests/rec/_smoke.png")
	var err := img.save_png(out)
	print("SMOKE_RESULT err=%d size=%s path=%s" % [err, str(img.get_size()), out])
	get_tree().quit(0)
