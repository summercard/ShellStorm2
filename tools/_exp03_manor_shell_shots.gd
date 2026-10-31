extends Node
## 隔离出图：只加载生成的房间 TSCN，放在干净场景里渲染。
##
## **不复用完整关卡**。关卡实例自带 HUD、雾、相机 rig、白盒墙体，
## 直接拍会得到"雾里一片白"——第一版就是这么失败的：
##   · 关卡有 `fog_profile`，远景全被雾吃掉
##   · HUD CanvasLayer 压在画面上
##   · 关卡相机有自己的一套跟随逻辑，覆盖手动设的位置
## 隔离场景只有：地板 + 墙 + 一盏平行光 + 一台正交相机。
##
## 必须**不用 --headless** 运行（headless 无渲染后端）：
##   godot --path . --scene res://tools/_exp03_manor_shell_shots.tscn

const ROOM_DIR := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms"
const OUT_DIR := "res://outputs/expedition03_manor_shell_20261031"

## 要拍的房间：文件名（自动从目录里按前缀挑最新一份）
const SHOT_TARGETS := [
	{"label": "combat_25x25_n06", "prefix": "combat_25x25_38083aa33b1a_0ceb51"},
	{"label": "upgrade_25x25_boss_foyer", "prefix": "upgrade_25x25_2154658c5c32_0ceb51"},
	{"label": "combat_45x40_hub_01", "prefix": "combat_45x40_6351962d84c2_a529ca"},
	{"label": "boss_50x40", "prefix": "boss_50x40_b7446dc46356_f4138d"},
	{"label": "merchant_30x40_shop", "prefix": "merchant_30x40_f2a374f5465f_f16dd2"},
	{"label": "event_40x30_reward_01", "prefix": "event_40x30_24e9d88c229b_9e857c"},
]

var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for target in SHOT_TARGETS:
		await _render(str(target["prefix"]), str(target["label"]))
	print("SHOT_ALL_DONE")
	get_tree().quit(0)


func _render(prefix: String, label: String) -> void:
	var path := ROOM_DIR.path_join(prefix + ".tscn")
	if not ResourceLoader.exists(path, "PackedScene"):
		print("SHOT_SKIP 缺 %s" % prefix)
		return
	# 每个房间一个独立子场景，拍完拆掉 —— 避免前一个房间的灯光/地板影响下一张
	var stage := Node3D.new()
	add_child(stage)
	var packed := load(path) as PackedScene
	var room := packed.instantiate() as Node3D
	stage.add_child(room)
	var dim := Vector2(25.0, 25.0)
	if room.has_meta("size_m"):
		var size: Variant = room.get_meta("size_m")
		dim = Vector2(float(size[0]), float(size[1]))

	_setup_environment(stage)
	_camera = Camera3D.new()
	_camera.current = true
	stage.add_child(_camera)
	var span := maxf(dim.x, dim.y)

	# 顶视
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = span * 1.12
	_camera.position = Vector3(0.0, 30.0, 0.0)
	_camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	await _capture("%s_top.png" % label)

	# 45° 斜视：抬到房间对角外，能同时看到墙高与地面纹理
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = span * 1.42
	_camera.position = Vector3(span * 0.62, span * 0.78, span * 0.62)
	_camera.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	await _capture("%s_oblique.png" % label)

	print("SHOT %-26s %.0fx%.0f done" % [label, dim.x, dim.y])
	stage.queue_free()
	for _frame in 3:
		await get_tree().process_frame


## 干净环境：深灰底 + 中性环境光 + 一盏投影太阳。
## 环境光给到 0.6 是刻意的：公馆资产靠暖光壁灯定调，环境光太低会让深木色糊成黑块，
## 看不出护墙的分格与窗的节奏。
func _setup_environment(stage: Node3D) -> void:
	var env := WorldEnvironment.new()
	var res := Environment.new()
	res.background_mode = Environment.BG_COLOR
	res.background_color = Color(0.10, 0.10, 0.11)
	res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	res.ambient_light_color = Color(0.62, 0.60, 0.57)
	res.ambient_light_energy = 0.62
	res.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = res
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = true
	stage.add_child(sun)


func _capture(file_name: String) -> void:
	for _frame in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := OUT_DIR.path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		printerr("SHOT_FAIL ", path, " ", error)
	else:
		print("SHOT_FILE %s" % path.get_file())
