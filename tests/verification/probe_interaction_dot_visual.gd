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
## 圆点架高。探针里隐含的玩家站位在原点地面，所以「玩家 → 圆点」的 3D 距离是
## `sqrt(水平² + DOT_HEIGHT_M²)` —— 与控制器 `player.global_position.distance_to(anchor)`
## 同一口径。两档映射都吃这个 3D 距离，探针若直接拿水平距离去喂，会系统性偏乐观。
const FOCUS_PROMPT := "[E] 搜索 · SMALL"
const EXPECTED_FOCUS_KEY_HINT := "(e) 搜索"
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
		dot.global_position = Vector3(0.0, DOT_HEIGHT_M, -float(distance))
		_dots.append(dot)


## 水平距离 → 3D 距离（玩家 → 圆点）。见 DOT_HEIGHT_M 的说明。
func _ramp_distance_for(horizontal_m: float) -> float:
	return sqrt(horizontal_m * horizontal_m + DOT_HEIGHT_M * DOT_HEIGHT_M)


## 与 PlayerInteractionController3D 完全同一套映射：直接调圆点脚本的 static，
## 不再各抄一份算式。尺寸档与清晰度档是两条独立窗口。
func _clarity_for(distance: float) -> float:
	return DOT_SCRIPT.clarity_for_distance(_ramp_distance_for(distance))


func _approach_for(distance: float) -> float:
	return DOT_SCRIPT.approach_for_distance(_ramp_distance_for(distance))


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
		# 功能词只喂给被聚焦那个：真实运行时也是只有聚焦候选才带 prompt。
		dot.call("set_prompt", FOCUS_PROMPT if is_focus else "")
		# 先把尺寸档/清晰度/聚焦/呼吸推到稳定态。与控制器一样每帧先喂距离再 update。
		for _step in range(40):
			dot.call("set_approach_from_distance", _ramp_distance_for(distance))
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

	var probe_dot := _dots[focus_index]
	var snapshot := (probe_dot.call("get_snapshot") as Dictionary)
	var center := _camera.unproject_position(probe_dot.global_position)
	# 期望直径**算出来**，不写死：把圆心沿相机右轴平移 DOT_RADIUS_M 再投影，得到的
	# 屏幕偏移就是这个深度上的半径。比写死「52.6 px/m」准 —— 三个采样距离的视轴深度
	# 并不完全相同，写死会在最远那个上系统性偏大。
	var edge := _camera.unproject_position(
		probe_dot.global_position
			+ _camera.global_transform.basis.x * float(DOT_SCRIPT.DOT_RADIUS_M)
	)
	var expected_diameter_px := (
		absf(edge.x - center.x) * 2.0 * float(snapshot.get("scale_multiplier", 1.0))
	)
	var data := image.get_data()
	var metric := _measure_dot(image, data, _baseline, center, expected_diameter_px * 0.5)
	_dump_diff_mask(image, data, _baseline, slug)
	print(
		"PROBE_VISUAL\t%s\tfocus_m=%.1f\tramp_d=%.2f\tclarity=%.3f\tapproach=%.3f\tscale=%.3f\talpha=%.3f\tring=%s\tverb=%s\thint=%s\texpect_d=%.1f\tdot_px=%d\tfill=%.2f\textra_px=%d\tbbox=%s\tcenter=%s\tframe_diff=%d\t%s"
		% [
			slug,
			focus_distance,
			_ramp_distance_for(focus_distance),
			float(snapshot.get("clarity", 0.0)),
			float(snapshot.get("approach", 0.0)),
			float(snapshot.get("scale_multiplier", 0.0)),
			float(snapshot.get("alpha", 0.0)),
			str(snapshot.get("ring_visible", false)),
			str(snapshot.get("action_verb", "")),
			str(snapshot.get("key_hint_text", "")),
			expected_diameter_px,
			int(metric["inside"]),
			float(metric["fill_ratio"]),
			int(metric["extra"]),
			str(metric["bbox"]),
			str(center),
			_full_diff_count(image, data, _baseline),
			out_path,
		]
	)
	# 断言：期望半径以内必须真的填着一块圆盘。
	# 光靠 `visible=true` / `surfaces=1` 抓不到「几何被 CULL_BACK 整块剔除」那类 bug ——
	# 那种情况下 visible、AABB、surfaces 全都正常，只有画面是空的。
	#
	# 阈值取 0.55：正常的抗锯齿圆盘实测 0.8~0.95；绕序反了只剩 0.62R 内核 → ≈0.38；
	# 圆点没画出来 → 0。三条区间分得开，不怕抖动。
	if float(metric["fill_ratio"]) < 0.55:
		push_error(
			"PROBE_VISUAL_FAIL: %s 在期望半径内只填了 %.0f%%（%d px，期望直径 %.1fpx）—— 圆盘没画出来或被剔掉了一大块"
			% [slug, float(metric["fill_ratio"]) * 100.0, int(metric["inside"]), expected_diameter_px]
		)
		get_tree().quit(1)
		return
	# 功能词牌：聚焦那张必须挂出「(e) 搜索」；读条那张必须**收起**（牌会压到进度环上）。
	if slug == "focus" and str(snapshot.get("key_hint_text", "")) != EXPECTED_FOCUS_KEY_HINT:
		push_error(
			"PROBE_VISUAL_FAIL: focus 帧的按键牌是「%s」，期望「%s」—— 功能词没抽出来"
			% [str(snapshot.get("key_hint_text", "")), EXPECTED_FOCUS_KEY_HINT]
		)
		get_tree().quit(1)
		return
	if slug == "ring" and bool(snapshot.get("key_hint_visible", false)):
		push_error("PROBE_VISUAL_FAIL: 读条期间按键牌没有收起 —— 会压在进度环上")
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


## 量「圆心周围那块圆盘真的被画出来了吗」，而不是量一个什么都会往里装的包围盒。
##
## 为什么不能拿包围盒当直径：这个窗口里除了圆盘还混着别的东西 ——
##   1. 半透明边缘的抗锯齿抖点（散在圆点外围十来像素）；
##   2. 聚焦时圆点下方的功能词牌；
##   3. 圆点上方约 25~29px 处一条 1px 细横带（既有现象，导出的 _diff_mask_*.png 里可直接看到）。
## 直接取 bbox，第 3 条那条 58px 长的横带就会被算进「直径」—— 实测 near 量出 26px，
## 而按机位算出来的几何直径只有 18px。于是尺寸断言就成了一句空话。
##
## 所以改成：只在**期望半径以内**数像素，看这块圆盘被填了多满。
##   fill_ratio = 半径内的实填面积 / πr²
##   正常 ≈ 0.8~0.95（抗锯齿边缘有损耗）；
##   绕序反了只剩 0.62R 内核 → ≈ 0.38；圆点压根没画出来 → 0。
## 半径以外的像素单独报成 extra_px —— 那是「这窗口里还混着什么」，只做诊断、不参与断言。
func _measure_dot(
	image: Image,
	current: PackedByteArray,
	baseline: PackedByteArray,
	center: Vector2,
	expected_radius_px: float
) -> Dictionary:
	var result := {
		"inside": 0, "extra": 0, "fill_ratio": 0.0, "bbox": "", "radius": expected_radius_px
	}
	var width := image.get_width()
	var height := image.get_height()
	var bpp := _bytes_per_pixel(image, current)
	if bpp < 3 or baseline.size() != current.size() or expected_radius_px <= 0.0:
		return result
	var x0 := maxi(0, int(center.x) - WINDOW_HALF_PX)
	var x1 := mini(width - 1, int(center.x) + WINDOW_HALF_PX)
	var y0 := maxi(0, int(center.y) - WINDOW_HALF_PX)
	var y1 := mini(height - 1, int(center.y) + WINDOW_HALF_PX)
	var min_x := width
	var max_x := -1
	var min_y := height
	var max_y := -1
	var limit_sq := expected_radius_px * expected_radius_px
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
			var dx := float(x) - center.x
			var dy := float(y) - center.y
			if dx * dx + dy * dy > limit_sq:
				result["extra"] = int(result["extra"]) + 1
				continue
			result["inside"] = int(result["inside"]) + 1
			min_x = mini(min_x, x)
			max_x = maxi(max_x, x)
			min_y = mini(min_y, y)
			max_y = maxi(max_y, y)
	result["fill_ratio"] = float(result["inside"]) / maxf(1.0, PI * limit_sq)
	if max_x >= 0:
		result["bbox"] = "x[%d..%d] y[%d..%d]" % [min_x, max_x, min_y, max_y]
	return result


## 别写死 4：视口纹理取出来是 RGB8（3 字节/像素），按 4 取样会整片错位，
## 表现出来就是「明明看见圆点在画面里，做差却数出 0 个像素」。
func _bytes_per_pixel(image: Image, data: PackedByteArray) -> int:
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return 0
	return data.size() / (width * height)


## 把「当前帧与基线帧不同的像素」导成黑底白点的掩膜图，用来肉眼回答
## 「包围盒比几何尺寸大出来的那几圈像素到底是什么」——光看 bbox 数字是猜不出来的。
func _dump_diff_mask(
	image: Image, current: PackedByteArray, baseline: PackedByteArray, slug: String
) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var bpp := _bytes_per_pixel(image, current)
	if bpp < 3 or baseline.size() != current.size():
		return
	var mask := Image.create_empty(width, height, false, Image.FORMAT_RGB8)
	mask.fill(Color.BLACK)
	for y in range(height):
		for x in range(width):
			var offset := (y * width + x) * bpp
			var delta := 0
			for channel in range(3):
				delta = maxi(
					delta, absi(int(current[offset + channel]) - int(baseline[offset + channel]))
				)
			if delta > 5:
				mask.set_pixel(x, y, Color.WHITE)
	mask.save_png("%s/_diff_mask_%s.png" % [OUTPUT_DIR, slug])


func _settle(frames: int) -> void:
	for _index in range(frames):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
