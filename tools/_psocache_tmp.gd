extends Node3D
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.5, 3.0), Vector3(0, 1.0, 0), Vector3.UP)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.8, 0.5, 0.3)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	mi.mesh = box
	mi.material_override = m
	add_child(mi)
	for _i in 5:
		await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	m.emission_enabled = true
	var t1 := Time.get_ticks_usec()
	print("PSO first_enable=%.2fms" % ((t1-t0)/1000.0))
	await get_tree().process_frame
	var t2 := Time.get_ticks_usec()
	m.emission_enabled = false
	var t3 := Time.get_ticks_usec()
	print("PSO disable=%.2fms" % ((t3-t2)/1000.0))
	await get_tree().process_frame
	var t4 := Time.get_ticks_usec()
	m.emission_enabled = true
	var t5 := Time.get_ticks_usec()
	print("PSO re-enable=%.2fms" % ((t5-t4)/1000.0))
	get_tree().quit(0)
