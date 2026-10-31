extends Node3D
const PREFAB := preload("res://assets/art/enemies/enemy_3d/enm_ecosystem_kit_root_top3d_v001.tscn")
var _kinds: Array[String] = []

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

	for key in Enemy3D.PROFILES.keys():
		_kinds.append(str(key))
	print("MANIFEST kinds=", _kinds.size())

	for pass_index in 2:
		var total := 0.0
		var worst := 0.0
		var worst_kind := ""
		for kind in _kinds:
			await RenderingServer.frame_post_draw
			var enemy := PREFAB.instantiate() as Enemy3D
			enemy.set("enemy_kind", kind)
			var t0 := Time.get_ticks_usec()
			add_child(enemy)
			var cost := float(Time.get_ticks_usec() - t0) / 1000.0
			total += cost
			if cost > worst:
				worst = cost
				worst_kind = kind
			await get_tree().process_frame
			if pass_index == 1 and cost > 5.0:
				print("  MANIFEST hot2 %-24s %.1fms" % [kind, cost])
			enemy.queue_free()
			await get_tree().process_frame
			await get_tree().process_frame
		print("MANIFEST pass%d total=%.0fms worst=%.0fms(%s) avg=%.1fms vram=%dMB"
			% [pass_index + 1, total, worst, worst_kind, total / maxf(1.0, float(_kinds.size())),
			   int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576)])

	# 武器：一把枪视图的构建代价（会新建 3 份材质）
	var tree_script := load("res://src/weapons/WeaponAssemblyTree.gd")
	print("MANIFEST weapon_tree=", tree_script != null)
	get_tree().quit(0)
