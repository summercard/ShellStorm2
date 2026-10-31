extends Node
## 陈设评审出图：按**烘焙文件名**渲染俯视 + 斜视，用于看家具布局。
##
## ## 为什么不复用 `_exp03_manor_shell_shots.gd`
##
## 那个工具按 `room_id` 找文件（扫 tscn 文本里的 `metadata/room_id`）。复用键改成
## 「模板+签名+原型」之后，**同一个文件服务多个 room_id**，烘焙文件里只记着烘焙那次
## 碰到的 room_id（实测 `fireplace_room_inj2` 这一个 id 对应 6 份不同原型的文件）
## ⇒ 按 room_id 找会拿到错的那一份。本工具直接按文件名点对点渲染。
##
## ## 用法
##
## 必须真实渲染（headless 无渲染后端，拍出来是黑的）：
##   godot --path . --scene res://tools/_exp03_furnishing_shots.tscn
##
## 只渲 `TARGETS` 里列出的；要全量就把 `TARGETS` 换成目录扫描。

const ROOM_DIR := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_03/runtime_rooms"
const OUT_DIR := "res://outputs/expedition03_furnishing_20261031"

## 先只看代表性房间，确认风格成立再全量。
const TARGETS := [
	{"file": "boss_50x40_b7446dc46356_c6c134", "label": "01_throne"},
	{"file": "combat_45x40_6351962d84c2_68065f", "label": "02_grand_lobby"},
	{"file": "combat_45x40_6351962d84c2_007418", "label": "03_banquet"},
	{"file": "combat_40x30_18c0881f3934_e86e98", "label": "04_drawing_room"},
	{"file": "upgrade_25x25_2154658c5c32_1b559c", "label": "05_bedroom"},
	{"file": "trap_40x30_29d67dbb9bda_d2426a", "label": "06_study"},
	{"file": "storage_40x30_ef3f827636f7_3e5f15", "label": "07_storage"},
	{"file": "merchant_30x40_f2a374f5465f_d77c54", "label": "08_shop"},
	{"file": "scavenge_40x30_a0eceb3887c9_23641e", "label": "09_kitchen"},
	{"file": "event_40x30_24e9d88c229b_a653bb", "label": "10_cabinet"},
	{"file": "combat_25x25_38083aa33b1a_897612", "label": "11_servant"},
	{"file": "stair_lobby_15x15_703e12bd9aa8_4955df", "label": "12_entrance"},
]

var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for target in TARGETS:
		await _render(str(target["file"]), str(target["label"]))
	print("FURNSHOT_ALL_DONE")
	get_tree().quit(0)


func _render(file_stem: String, label: String) -> void:
	var path := ROOM_DIR.path_join(file_stem + ".tscn")
	if not ResourceLoader.exists(path):
		print("FURNSHOT_SKIP 缺 %s" % file_stem)
		return
	var stage := Node3D.new()
	add_child(stage)
	var room := (load(path) as PackedScene).instantiate() as Node3D
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
	# 顶视：看清平面布局（家具分布、是否挡门、中心是否留空）
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = span * 1.08
	_camera.position = Vector3(0.0, 40.0, 0.0)
	_camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	await _capture("%s_top.png" % label)
	# 45° 斜视：看清体量关系（家具高度 vs 墙高）
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = span * 1.30
	_camera.position = Vector3(span * 0.52, span * 0.62, span * 0.52)
	_camera.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	await _capture("%s_oblique.png" % label)
	var theme := str(room.get_meta("furnishing_theme", "?"))
	print("FURNSHOT %-18s %-16s %.0fx%.0f theme=%s"
		% [label, file_stem.substr(0, 16), dim.x, dim.y, theme])
	stage.queue_free()
	for _frame in 3:
		await get_tree().process_frame


func _setup_environment(stage: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.66)
	e.ambient_light_energy = 1.35
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58.0, -34.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	stage.add_child(sun)


func _capture(file_name: String) -> void:
	# 等两帧：材质与阴影在这一帧还没稳定，第一帧拍出来偏暗。
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var out := OUT_DIR.path_join(file_name)
	var error := image.save_png(out)
	if error != OK:
		push_error("保存失败 %s: %s" % [out, error_string(error)])
