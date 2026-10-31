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

## 要拍的房间：**按 room_id 定位**，不按文件名前缀。
##
## 45×40 有三份文件（hub_01 / hub_02 / n07）而文件名前缀都是 `combat_45x40_*` ——
## 按前缀挑只会拿到字母序第一份，hub 与普通战斗房根本分不开。room_id 记在
## 每份 tscn 的根节点 meta 里，扫目录读文本即可定位，不必实例化。
const SHOT_TARGETS := [
	# 逼仄空厅（25×25 战斗，最暗）
	{"label": "A_empty_hall_n06", "room": "n06"},
	# 中庭回廊（40×30 战斗，每面一对高窗）
	{"label": "B_cloister_n03", "room": "n03"},
	# 大回廊（45×40 战斗，通窗）
	{"label": "C_grand_cloister_n07", "room": "n07"},
	# 大堂（45×40 枢纽，石沿廊 + 木中庭 + 通窗）
	{"label": "D_lobby_hub_01", "room": "hub_01"},
	# 王座间（50×40 Boss，木围廊 + 中央石台 + 无窗）
	{"label": "E_throne_boss", "room": "boss"},
	# 更衣前厅（25×25 升级房，黑白瓷砖 + 高窗）
	{"label": "F_dressing_boss_foyer", "room": "boss_foyer"},
	# 陈列室（40×30 事件房，单向采光）
	{"label": "G_gallery_reward_01", "room": "reward_01"},
]

var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for target in SHOT_TARGETS:
		await _render(str(target["room"]), str(target["label"]))
	print("SHOT_ALL_DONE")
	get_tree().quit(0)


## 扫目录，找出根节点 meta.room_id 匹配的那一份 tscn。
func _find_room_file(room_id: String) -> String:
	var dir := DirAccess.open(ROOM_DIR)
	if dir == null:
		return ""
	for file_name in dir.get_files():
		if not file_name.ends_with(".tscn"):
			continue
		var path := ROOM_DIR.path_join(file_name)
		var text := FileAccess.get_file_as_string(path)
		# meta 写成 `metadata/room_id = "n06"`，引号不能少 —— 否则 "n06" 会误命中 "n060"。
		if text.contains("metadata/room_id = \"%s\"" % room_id):
			return path
	return ""


func _render(room_id: String, label: String) -> void:
	var path := _find_room_file(room_id)
	if path.is_empty():
		print("SHOT_SKIP 找不到 room_id=%s 的文件" % room_id)
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

	# 室内近墙视角：站在离北墙 7m 处，正对护墙拍。
	# **必须贴到 7m**。从房间对角看（45×40 对角约 60m）时，2.8m 高的墙只占垂直视角
	# 约 8°，缩成画面底部一条细线 —— 护墙分格、窗框根本分辨不出。
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 62.0
	_camera.near = 0.1
	_camera.far = 400.0
	var wall_z := -dim.y * 0.5
	var stand := minf(7.0, dim.y * 0.34)
	_camera.position = Vector3(dim.x * 0.10, 1.60, wall_z + stand)
	_camera.look_at(Vector3(0.0, 1.45, wall_z), Vector3.UP)
	await _capture("%s_inside.png" % label)

	print("SHOT %-26s %.0fx%.0f done" % [label, dim.x, dim.y])
	stage.queue_free()
	for _frame in 3:
		await get_tree().process_frame


## 干净环境：深灰底 + 强环境光 + 一盏投影主光 + 三面斜补光。
##
## **为什么必须打这么亮**：公馆资产共用一份「低亮多巴胺色盘」（材质 albedo 是
## 0.9063 白，颜色全由色盘贴图决定）。按常规 0.6 环境光出图的结果是：地板还看得出
## 砖缝，**墙面全黑** —— 因为墙法线水平，而唯一的主光俯角 52°，几乎打不到垂直面。
## 于是「分格、窗框、护墙高度」全看不见，等于没评审。
## 所以这里是**评审用打光**，不是还原游戏内观感（游戏内另有壁灯/烛台照明）：
## 环境光 2.0 抬底 + 三向补光把四个立面都点亮。
func _setup_environment(stage: Node3D) -> void:
	var env := WorldEnvironment.new()
	var res := Environment.new()
	res.background_mode = Environment.BG_COLOR
	res.background_color = Color(0.13, 0.13, 0.145)
	res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	res.ambient_light_color = Color(0.80, 0.78, 0.74)
	res.ambient_light_energy = 1.15
	res.tonemap_mode = Environment.TONE_MAPPER_ACES
	res.tonemap_exposure = 0.95
	env.environment = res
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -38, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = true
	stage.add_child(sun)
	# 三面斜补光：俯角都很浅（20~30°），专门照亮立面。
	# 方向覆盖东南西北四个朝向，任意一面墙至少被一盏斜光正面照到。
	# 能量刻意压低到 0.5 —— 抬到 0.8 以上时**黑白瓷砖会烧成纯白**（albedo 接近 1，
	# 白格再叠加方向光就过曝），砖缝消失，看起来像一块白板。
	for setup in [
		{"rot": Vector3(-24, 150, 0), "energy": 0.50, "color": Color(0.86, 0.90, 1.0)},
		{"rot": Vector3(-20, 40, 0), "energy": 0.44, "color": Color(1.0, 0.94, 0.86)},
		{"rot": Vector3(-26, -80, 0), "energy": 0.40, "color": Color(0.94, 0.94, 0.96)},
	]:
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = setup["rot"]
		fill.light_energy = setup["energy"]
		fill.light_color = setup["color"]
		fill.shadow_enabled = false
		stage.add_child(fill)


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
