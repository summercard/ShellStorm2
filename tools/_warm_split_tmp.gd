extends Node3D
const PREFAB := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	env.environment = e
	add_child(env)
	var cam := Camera3D.new()
	cam.current = true
	add_child(cam)
	cam.look_at_from_position(Vector3(0, 2.0, 8.0), Vector3(0, 1.0, 0), Vector3.UP)
	for _i in 5:
		await get_tree().process_frame
	for pass_index in 2:
		for kind in ["egt_bullet_kin", "egt_bandana_kin", "egt_veteran_kin", "ranged_caster"]:
			await RenderingServer.frame_post_draw
			var enemy := PREFAB.instantiate() as Enemy3D
			enemy.set("enemy_kind", kind)
			var t0 := Time.get_ticks_usec()
			add_child(enemy)
			print("KIND p%d %-16s %dms" % [pass_index, kind, (Time.get_ticks_usec() - t0) / 1000])
			await get_tree().process_frame
			enemy.free()
			await get_tree().process_frame
	get_tree().quit(0)
