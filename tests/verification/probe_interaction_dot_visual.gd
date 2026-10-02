extends Node3D
## 交互圆点的**视觉**采样（真渲染器，非 headless）。
##
## 回答「这套常驻圆点在实际游戏机位下长什么样」：按 TowerDescent3D 的 CAMERA_* 常量
## 复刻塔内相机（高 10.719m / 后拉 4.038m / FOV 65°），在真实比例的地板、货箱、门旁边
## 摆三个距离的圆点，逐状态截图。
##
## 自带像素断言：截图里必须真的出现亮斑。这一条专治「几何生成了、visible=true、
## 但三角绕序反了被 CULL_BACK 整块剔除」那类只看日志看不出来的 bug。
##
## 不走验证套件（`probe_` 前缀），手动跑：
##   godot --path <项目> --scene res://tests/verification/probe_interaction_dot_visual.tscn
## 产物：res://outputs/verification/interaction_dot_<state>.png

const OUTPUT_DIR := "res://outputs/verification"
const DOT_SCRIPT := preload("res://src/ui/InteractionDot3D.gd")

## 与 TowerDescent3D 保持一致 —— 探针必须用真机位，否则是在对着假象调参。
const CAMERA_HEIGHT_M := 10.719009
const CAMERA_TRAILING_M := 4.037671
const CAMERA_LOOK_HEIGHT_M := 0.45
const CAMERA_LOOK_AHEAD_M := 0.75
const CAMERA_FOV_DEG := 65.0

const DOT_HEIGHT_M := 1.5
const ACCENT := Color(0.20, 0.90, 1.0)
## 三个采样距离（玩家到交互物的水平距离，米）。
## 上限不能贪：顶视角相机往下看 65°，8m 左右已接近画面上沿，再远就出画了。
const SAMPLE_DISTANCES := [1.6, 4.6, 8.2]
## 做差统计的窗口半径。三个采样点的屏幕纵距约 110~130px，窗口取 80 不会串味。
const WINDOW_HALF_PX := 80

var _camera: Camera3D
var _dots: Array[MeshInstance3D] = []
## 无圆点基线帧（同一个相机、同一份光照），用来把「圆点真正贡献的像素」差出来。
var _baseline := PackedByteArray()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_build_stage()
	_build_dots()
	await _capture_baseline()
	# 名字 → [聚焦距离, 是否聚焦, 圆环进度, 脉冲相位]
	await _shoot("near", SAMPLE_DISTANCES[0], false, 0.0, 0.0)
	await _shoot("mid", SAMPLE_DISTANCES[1], false, 0.0, 0.0)
	await _shoot("far", SAMPLE_DISTANCES[2], false, 0.0, 0.0)
	await _shoot("focus", SAMPLE_DISTANCES[0], true, 0.0, 0.0)
	await _shoot("ring", SAMPLE_DISTANCES[0], true, 0.62, 0.0)
	await _shoot("pulse", SAMPLE_DISTANCES[0], true, 0.0, 0.15)
	get_tree().quit(0)


## 把所有圆点淡出后拍一帧。后面对每个状态做差，得到「这套表现确实画出来的像素」。
func _capture_baseline() -> void:
	for dot in _dots:
		dot.call("set_visible_state", false)
		for _step in range(40):
			dot.call("update_state", 1.0, false, 0.033)
	await _settle(3)
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("PROBE_VISUAL_FAIL: cannot capture baseline")
		get_tree().quit(1)
		return
	_baseline = image.get_data()


func _build_stage() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.030, 0.045, 0.060)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.94, 1.0)
	environment.ambient_light_energy = 1.2
	world_environment.environment = environment
	add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(36.0), 0.0)
	key_light.light_energy = 1.4
	add_child(key_light)

	# 5m 网格地板：给圆点一个真实尺度参照，也方便判断尺寸是否合适。
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.075, 0.10, 0.125)
	floor_material.roughness = 0.9
	plane.material = floor_material
	floor.mesh = plane
	floor.position = Vector3(0.0, 0.0, -5.0)
	add_child(floor)

	for distance in SAMPLE_DISTANCES:
		# 可搜索货箱：0.8m 立方，圆点锚在它正上方。
		_add_box(Vector3(-0.9, 0.4, -float(distance)), Vector3(0.8, 0.8, 0.8), 0.10)
		# 门：1.2 x 2.2m 竖板，作为第二个尺度参照。
		_add_box(Vector3(0.9, 1.1, -float(distance)), Vector3(1.2, 2.2, 0.16), 0.13)

	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV_DEG
	add_child(_camera)
	# 玩家在原点、朝向 -Z；相机按 TowerDescent3D._apply_indoor_camera_pose 的默认姿态落位。
	_camera.global_position = Vector3(0.0, CAMERA_HEIGHT_M, CAMERA_TRAILING_M)
	_camera.look_at(
		Vector3(0.0, CAMERA_LOOK_HEIGHT_M, -CAMERA_LOOK_AHEAD_M), Vector3.UP
	)
	_camera.current = true


func _add_box(center: Vector3, size: Vector3, albedo: float) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(albedo, albedo * 1.15, albedo * 1.4)
	material.roughness = 0.8
	mesh.material = material
	node.mesh = mesh
	node.position = center
	add_child(node)


func _build_dots() -> void:
	for distance in SAMPLE_DISTANCES:
		var dot := DOT_SCRIPT.new() as MeshInstance3D
		dot.name = "ProbeDot3D_%.1fm" % float(distance)
		add_child(dot)
		dot.call("configure", ACCENT)
		dot.global_position = Vector3(0.0, DOT_HEIGHT_M, -float(distance))
		_dots.append(dot)


## 与 PlayerInteractionController3D 同样的距离→清晰度映射，避免探针自说自话。
func _clarity_for(distance: float) -> float:
	var span := maxf(
		0.001, float(DOT_SCRIPT.FAR_DISTANCE_M) - float(DOT_SCRIPT.NEAR_DISTANCE_M)
	)
	return clampf(
		1.0 - (distance - float(DOT_SCRIPT.NEAR_DISTANCE_M)) / span, 0.0, 1.0
	)


func _shoot(
	slug: String, focus_distance: float, focused: bool, ring_progress: float, pulse_age: float
) -> void:
	var focus_index := 0
	for index in range(_dots.size()):
		var dot := _dots[index]
		var distance := float(SAMPLE_DISTANCES[index])
		var is_focus := focused and absf(distance - focus_distance) < 0.01
		if absf(distance - focus_distance) < 0.01:
			# 不管这轮有没有聚焦，量的都是「这个距离上的那个圆点」。
			focus_index = index
		dot.call("set_visible_state", true)
		dot.call("set_progress", is_focus and ring_progress > 0.001, ring_progress)
		# 先把清晰度/聚焦/呼吸推到稳定态。
		for _step in range(40):
			dot.call("update_state", _clarity_for(distance), is_focus, 0.033)
		if pulse_age > 0.0 and is_focus:
			# 脉冲要停在指定相位：播放后只推进 pulse_age 秒。
			dot.call("play_confirm_pulse")
			dot.call("update_state", _clarity_for(distance), true, pulse_age)
	await _settle(4)

	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("PROBE_VISUAL_FAIL: empty framebuffer for %s" % slug)
		get_tree().quit(1)
		return
	var out_path := "%s/interaction_dot_%s.png" % [OUTPUT_DIR, slug]
	if image.save_png(out_path) != OK:
		push_error("PROBE_VISUAL_FAIL: cannot save %s" % out_path)
		get_tree().quit(1)
		return

	var center := _camera.unproject_position(_dots[focus_index].global_position)
	var data := image.get_data()
	var span := _diff_span(image, data, _baseline, center)
	var snapshot := (_dots[focus_index].call("get_snapshot") as Dictionary)
	print(
		"PROBE_VISUAL\t%s\tfocus_m=%.1f\tclarity=%.3f\tscale=%.3f\talpha=%.3f\tring=%s\tdot_px=%d\tdot_w=%d\tdot_h=%d\tcenter=%s\tframe_diff=%d\t%s"
		% [
			slug,
			focus_distance,
			float(snapshot.get("clarity", 0.0)),
			float(snapshot.get("scale_multiplier", 0.0)),
			float(snapshot.get("alpha", 0.0)),
			str(snapshot.get("ring_visible", false)),
			int(span["count"]),
			int(span["width"]),
			int(span["height"]),
			str(center),
			_full_diff_count(image, data, _baseline),
			out_path,
		]
	)
	# 断言：这套表现必须在画面上真的留下东西，而且尺寸得够看。
	# 光靠 `visible=true` / `surfaces=1` 是抓不到「几何被 CULL_BACK 剔除」那类 bug 的。
	if int(span["count"]) < 40:
		push_error(
			"PROBE_VISUAL_FAIL: %s 相对无圆点基线只差出 %d 个像素 —— 圆点没画出来"
			% [slug, int(span["count"])]
		)
		get_tree().quit(1)
		return
	# 最远处那个也要有能辨认的直径；近处这个必须够大。
	var min_width := 8 if slug == "far" else 12
	if int(span["width"]) < min_width:
		push_error(
			"PROBE_VISUAL_FAIL: %s 圆点只有 %d px 宽（要求 >= %d）—— 尺寸标定偏小"
			% [slug, int(span["width"]), min_width]
		)
		get_tree().quit(1)


## 全帧差异像素数。只用于诊断输出（三个圆点加起来），断言不看它。
func _full_diff_count(image: Image, current: PackedByteArray, baseline: PackedByteArray) -> int:
	var bpp := _bytes_per_pixel(image, current)
	if bpp < 3 or baseline.size() != current.size():
		return -1
	var count := 0
	for index in range(current.size() / bpp):
		var offset := index * bpp
		for channel in range(3):
			if absi(int(current[offset + channel]) - int(baseline[offset + channel])) > 5:
				count += 1
				break
	return count


## 与基线帧逐像素做差，返回被圆点/按键牌改动的像素数与包围盒。
## 只统计以 `center` 为中心、半径 WINDOW_HALF_PX 的窗口 —— 画面里有三个距离的圆点，
## 全帧做差会把它们加在一起，量出来的「直径」就没意义了。
func _diff_span(
	image: Image, current: PackedByteArray, baseline: PackedByteArray, center: Vector2
) -> Dictionary:
	var span := {"count": 0, "width": 0, "height": 0}
	var width := image.get_width()
	var height := image.get_height()
	var bpp := _bytes_per_pixel(image, current)
	if bpp < 3 or baseline.size() != current.size():
		return span
	var x0 := maxi(0, int(center.x) - WINDOW_HALF_PX)
	var x1 := mini(width - 1, int(center.x) + WINDOW_HALF_PX)
	var y0 := maxi(0, int(center.y) - WINDOW_HALF_PX)
	var y1 := mini(height - 1, int(center.y) + WINDOW_HALF_PX)
	var min_x := width
	var max_x := -1
	var min_y := height
	var max_y := -1
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var offset := (y * width + x) * bpp
			var delta := 0
			for channel in range(3):
				delta = maxi(
					delta, absi(int(current[offset + channel]) - int(baseline[offset + channel]))
				)
			if delta <= 5:
				continue
			span["count"] = int(span["count"]) + 1
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	if max_x >= 0:
		span["width"] = max_x - min_x + 1
		span["height"] = max_y - min_y + 1
	return span


## 别写死 4：视口纹理取出来是 RGB8（3 字节/像素），按 4 取样会整片错位，
## 表现出来就是「明明看见圆点在画面里，做差却数出 0 个像素」。
func _bytes_per_pixel(image: Image, data: PackedByteArray) -> int:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return 0
	return data.size() / (width * height)


func _settle(frames: int) -> void:
	for _index in range(frames):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
