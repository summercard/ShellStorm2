extends SceneTree
## 在正式运行验证场景前只做加载/实例化，不把节点加入 SceneTree。
## 解析失败会立即返回非零，避免 Godot 回落主场景并等待 watchdog。


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("SCENE_PREFLIGHT_FAIL: missing res:// scene path")
		quit(2)
		return
	var scene_path := str(args[0])
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		push_error("SCENE_PREFLIGHT_FAIL: scene does not exist: %s" % scene_path)
		quit(2)
		return
	var packed := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null:
		push_error("SCENE_PREFLIGHT_FAIL: cannot load scene: %s" % scene_path)
		quit(2)
		return
	var instance := packed.instantiate()
	if instance == null:
		push_error("SCENE_PREFLIGHT_FAIL: cannot instantiate scene: %s" % scene_path)
		quit(2)
		return
	# PackedScene 在根脚本编译失败时仍可能实例化为无脚本的普通 Node。
	# 验证场景必须有根脚本；否则正式启动可能回落到项目主场景。
	if instance.get_script() == null:
		push_error("SCENE_PREFLIGHT_FAIL: root script missing or invalid: %s" % scene_path)
		instance.free()
		quit(2)
		return
	instance.free()
	quit(0)
