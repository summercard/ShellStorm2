extends Node
## 门墙资产画面核对（非 headless，真渲染器）。
##
## 为什么要单独拍：门墙是竖直构件，它的「两面都带装饰」这条性质在编辑器里看不到
## （关卡里房间是运行时装配的），而数值门禁只能证明包络与朝向轴，证明不了画面上
## 到底哪一面长什么样、门洞是不是通透。本探针把 prefab 单独摆进带光照的取景棚，
## 从房内侧、走廊侧、门洞近景、门楣底仰视四个机位各拍一张。
##
## 机位（门墙原点在底面中心，v005 起关于基准面对称）：
##   · room_side   —— 站在 +Z 侧正对门墙（房间侧）：装饰门框、门垛、自发光条；
##   · outer_side  —— 站在 -Z 侧正对门墙（走廊侧）：v005 起同样是装饰面，
##                    不应再是 v004 那块平整结构背；
##   · aperture    —— 门洞正前方平视：门洞应通透，门垛内缘在 ±1.1；
##   · lintel_up   —— 站在门洞里仰头：门楣底面必须存在（不许被剔面剔穿）。
##
## 判据 DOOR_WALL_VISUAL_OK（v005 改口径）：
##   · 四张图都不是空白（亮度分层 >= 2，即不是纯色/纯黑）；
##   · 房内侧与走廊侧的局部细节能量都必须达到装饰级下限 —— v004 的实测基线是
##     装饰面 0.0015、素结构背 0.0004，所以下限取 0.0010：素背过不去，装饰面过；
##   · 两侧能量之比必须落在 [0.5, 2.0]。这条才是真的在判「两面都有效果」：
##     v004 的比值是 4.247（一面装饰一面白板），双面之后应该回到 1 附近。
##     包络 / 面数 / 材质角色 / 原点约定四类数值断言对「一面是白板」全都全绿，
##     只有这两条画面判据会翻车。

const PREFAB := "res://assets/art/props/dungeon_3d/prp_tower_wall_door_5m.tscn"
const OUTPUT_DIR := "res://outputs/verification"
const MIN_LUMA_BUCKETS := 2
## 单侧细节能量下限：素结构背实测 0.0004，装饰面实测 0.0015，取中间偏装饰侧。
const SIDE_DETAIL_MIN := 0.0010
## 两侧细节能量之比的允许区间（双面的含义就是两面可比）。
const SIDE_RATIO_MIN := 0.5
const SIDE_RATIO_MAX := 2.0

const SHOTS: Array = [
	{
		"name": "room_side",
		"path": OUTPUT_DIR + "/door_wall_room_side_plus_z.png",
		"eye": Vector3(0.0, 3.0, 13.0),
		"target": Vector3(0.0, 3.0, 0.0),
	},
	{
		"name": "outer_side",
		"path": OUTPUT_DIR + "/door_wall_outer_side_minus_z.png",
		"eye": Vector3(0.0, 3.0, -13.0),
		"target": Vector3(0.0, 3.0, 0.0),
	},
	{
		"name": "aperture",
		"path": OUTPUT_DIR + "/door_wall_aperture_front.png",
		"eye": Vector3(0.0, 1.55, 5.2),
		"target": Vector3(0.0, 1.55, 0.0),
	},
	{
		"name": "lintel_up",
		"path": OUTPUT_DIR + "/door_wall_lintel_underside.png",
		"eye": Vector3(0.0, 1.2, 0.9),
		"target": Vector3(0.0, 4.4, 0.0),
	},
]

var _failures: Array[String] = []
var _captured := 0
var _skipped_headless := 0
## shot name -> 局部细节能量，用于「装饰面朝房内」这条比值判据。
var _detail: Dictionary = {}


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("[door_wall] headless：画面核对跳过（需要真渲染器）")
		_skipped_headless = 1
		get_tree().quit(0)
		return

	_build_rig()
	var packed := load(PREFAB) as PackedScene
	if packed == null:
		_failures.append("门墙 prefab 加载失败：%s" % PREFAB)
		_report()
		return
	var wall := packed.instantiate() as Node3D
	add_child(wall)

	var camera := Camera3D.new()
	camera.name = "ProbeCamera"
	camera.fov = 70.0
	camera.current = true
	add_child(camera)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for shot in SHOTS:
		camera.global_position = shot["eye"]
		camera.look_at(shot["target"], Vector3.UP)
		await _settle()
		print("[door_wall] shot=%s eye=%s" % [str(shot["name"]), str(camera.global_position)])
		_capture(str(shot["name"]), str(shot["path"]), "门墙 %s 采样失败" % str(shot["name"]))
	_verify_two_sided()
	_report()


func _build_rig() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.10, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.76, 0.82)
	environment.ambient_light_energy = 0.9
	var world_environment := WorldEnvironment.new()
	world_environment.name = "ProbeEnvironment"
	world_environment.environment = environment
	add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.name = "ProbeKey"
	key.rotation_degrees = Vector3(-48.0, 34.0, 0.0)
	key.light_energy = 1.1
	add_child(key)
	# 补一盏从外侧打的反向光，让「结构背是否有装饰」这件事在画面上也能看清。
	var fill := DirectionalLight3D.new()
	fill.name = "ProbeFill"
	fill.rotation_degrees = Vector3(-30.0, 200.0, 0.0)
	fill.light_energy = 0.5
	add_child(fill)


func _capture(shot_name: String, path: String, failure: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_failures.append(failure + "（视口纹理为空）")
		return
	var buckets := _luma_buckets(image)
	var mid := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	var detail := _detail_energy(image)
	_detail[shot_name] = detail
	print("[door_wall] diag %s size=%dx%d center_pixel=%s buckets=%d detail=%.4f" % [
		path.get_file(), image.get_width(), image.get_height(), str(mid), buckets, detail
	])
	if buckets < MIN_LUMA_BUCKETS:
		_failures.append("%s（画面只有 %d 层亮度，疑似没渲染出内容）" % [failure, buckets])
		return
	if image.save_png(path) != OK:
		_failures.append(failure + "（PNG 写入失败）")
		return
	_captured += 1
	print("[door_wall] saved %s %dx%d" % [path.get_file(), image.get_width(), image.get_height()])


## 「两面都有效果」的画面判据。
## v004 的单面版在这里判的是「房内侧能量 ≫ 外侧能量」（比值 4.247），那条判据随
## 缺陷一起退役：现在两面都是装饰，比值应该回到 1 附近，而任一侧退化成素平板会
## 立刻从「单侧下限」和「比值上限」两头被抓出来。
func _verify_two_sided() -> void:
	var room := float(_detail.get("room_side", -1.0))
	var outer := float(_detail.get("outer_side", -1.0))
	if room < 0.0 or outer < 0.0:
		_failures.append("双面判据取样缺失：room_side=%.4f outer_side=%.4f" % [room, outer])
		return
	var ratio := room / outer if outer > 0.0001 else INF
	print("[door_wall] two-sided ratio room/outer=%.3f (room=%.4f outer=%.4f)" % [ratio, room, outer])
	if room < SIDE_DETAIL_MIN:
		_failures.append(
			"房内侧细节能量 %.4f 低于装饰级下限 %.4f：房间侧看起来是素面" % [room, SIDE_DETAIL_MIN]
		)
	if outer < SIDE_DETAIL_MIN:
		_failures.append(
			"走廊侧细节能量 %.4f 低于装饰级下限 %.4f：镜像面没生效，走廊侧还是 v004 那块素背板"
			% [outer, SIDE_DETAIL_MIN]
		)
	if ratio < SIDE_RATIO_MIN or ratio > SIDE_RATIO_MAX:
		_failures.append(
			"两侧装饰不对称：room/outer=%.3f 不在 [%.2f, %.2f] 内（room=%.4f outer=%.4f）"
			% [ratio, SIDE_RATIO_MIN, SIDE_RATIO_MAX, room, outer]
		)


## 局部对比度 = 逐点与其 3x3（按 step 间隔）邻域均值的灰度差，取平均。
## 全分辨率逐像素在 GDScript 里太慢，按 step 抽样；step 同时决定邻域半径，
## 等价于一次降低阈值的低通，得到的仍是「装饰纹理 vs 平整大面」这个区分量。
func _detail_energy(image: Image) -> float:
	var width := image.get_width()
	var height := image.get_height()
	var step := 3
	if width <= step * 2 or height <= step * 2:
		return 0.0
	var total := 0.0
	var count := 0
	for y in range(step, height - step, step):
		for x in range(step, width - step, step):
			var center := _luma(image.get_pixel(x, y))
			var sum := 0.0
			for dy in [-step, 0, step]:
				for dx in [-step, 0, step]:
					sum += _luma(image.get_pixel(x + dx, y + dy))
			total += absf(center - sum / 9.0)
			count += 1
	return total / float(maxi(count, 1))


func _luma_buckets(image: Image) -> int:
	var seen := {}
	for y in range(0, image.get_height(), 7):
		for x in range(0, image.get_width(), 7):
			var luma := _luma(image.get_pixel(x, y))
			seen[int(luma * 12.0)] = true
	return seen.size()


func _luma(color: Color) -> float:
	return color.r * 0.299 + color.g * 0.587 + color.b * 0.114


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout


func _report() -> void:
	print("================================================================================")
	if _skipped_headless > 0:
		print("DOOR_WALL_VISUAL_SKIPPED_HEADLESS: 无渲染器，未取证")
		get_tree().quit(0)
		return
	if _failures.is_empty():
		print("DOOR_WALL_VISUAL_OK captured=%d" % _captured)
		get_tree().quit(0)
		return
	for failure in _failures:
		printerr("FAIL: %s" % failure)
	printerr("DOOR_WALL_VISUAL_FAILED count=%d" % _failures.size())
	get_tree().quit(1)
