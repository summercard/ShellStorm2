extends Node3D
## 单独渲染掉落名牌，逐个看清描边（「框框」）。
## A = outline_size 8（当前）  B = 0（无描边）  C = 4（细描边）

const SHOTS := [
	{"outline": 8, "file": "outline_8.png"},
	{"outline": 0, "file": "outline_0.png"},
	{"outline": 4, "file": "outline_4.png"},
]

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.47, 0.53)
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 0.78, 1.05)
	cam.fov = 42.0
	cam.make_current()

	for shot in SHOTS:
		var label := _make(int(shot["outline"]))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://_scratch/loot_label_probe/" + str(shot["file"]))
		print("SHOT ", shot["file"], " outline=", shot["outline"])
		label.queue_free()
		await get_tree().process_frame

	print("PROBE_DONE")
	get_tree().quit()


func _make(outline: int) -> Label3D:
	var l := Label3D.new()
	l.text = "治疗药水"
	l.font_size = GroundLootPickup3D.LABEL_FONT_SIZE
	l.pixel_size = GroundLootPickup3D.LABEL_PIXEL_SIZE
	l.outline_size = outline
	l.modulate = Color(1.0, 0.58, 0.16).lightened(0.20)
	l.position = Vector3(0.0, 0.78, 0.0)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	return l
