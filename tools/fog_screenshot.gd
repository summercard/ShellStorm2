extends SceneTree
## 一次性工具：跑 TowerDescent3D 主场景几秒后截图存 PNG，然后退出。
## 用法：godot --headless --path . -s tools/fog_screenshot.gd -- <filename> <out.png>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := "user://fog_test.png"
	if args.size() >= 2:
		out_path = args[1]
	print("[fog_screenshot] out_path = %s" % out_path)

	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if packed == null:
		printerr("[fog_screenshot] failed to load TowerDescent3D.tscn")
		quit(1)
		return
	var root_node := packed.instantiate()
	root.add_child(root_node)
	print("[fog_screenshot] scene instantiated")

	# 等几帧让场景初始化、雾参数落位
	for i in range(120):
		await process_frame
	print("[fog_screenshot] warmup done")

	var vp := root.get_viewport()
	var img: Image = vp.get_texture().get_image()
	if img == null:
		printerr("[fog_screenshot] no image")
		quit(2)
		return
	var resolved := ProjectSettings.globalize_path(out_path)
	var err := img.save_png(resolved)
	if err != OK:
		printerr("[fog_screenshot] save_png err=%d -> %s" % [err, resolved])
		quit(3)
		return
	print("[fog_screenshot] saved -> %s" % resolved)
	quit(0)