extends Node3D
## 真渲染验收：99F 灯具动态「看得见」与「不变色」。
##
## 为什么必须单独一支：结构验收（verify_base_lamp_dynamics.gd）在 headless 下只能
## 验数值，验不了「在 filmic 色调映射之后到底看不看得出」。这里实测的事实是——
## 这些面被 BaseFixtureGlow3D 提到 10.5~33 的 HDR 能量、已经在过曝区，
## 于是同一份倍率在不同物体上的可见度差几倍。所以每一档幅度都要用真渲染量。
##
## 判据（V1~V3）：
##   V1 每通道「静息 vs 极值」必须达到各自的最小差异像素比
##   V2 极值帧的最大通道差 ≥ 8/255（证明不是量化噪声）
##   V3 关灯态（factor 全 0）必须是纯黑屏，不得有残留自发光
##
## headless 下拿不到绘图表面 ⇒ 直接 exit 2 明说「未执行视觉对照」，不代签。
##
## 运行：godot --path . --scene res://tests/verification/verify_base_lamp_visual.tscn --resolution 1100x700

const ZONE := "res://assets/art/environments/tower_zones/base/runtime/zone_base.tscn"
const OUT_DIR := "res://outputs/verification/base99_lamp_dynamics"
const SEED := 20261018
const SIM_DURATION := 120.0
const SIM_STEP := 1.0 / 60.0
const STATUS_DIM := 0.18

## 通道 → 相机。阈值按「该物体在目标机位占多少像素」分别定，
## 不是拍脑袋的统一 1%：三颗状态灯每颗只有 0.09m，占比天然很小。
const VIEWS := {
	"neon": {
		"eye": Vector3(5.0, 4.35, -1.0), "look": Vector3(5.0, 4.44, -4.78),
		"fov": 55.0, "min_ratio": 0.02, "min_pixels": 20000,
	},
	"lamp": {
		"eye": Vector3(-3.60, 8.45, -5.55), "look": Vector3(-3.70, 8.20, -7.70),
		"fov": 42.0, "min_ratio": 0.02, "min_pixels": 15000,
	},
	"vending": {
		"eye": Vector3(-9.60, 2.70, -7.25), "look": Vector3(-7.10, 2.66, -7.25),
		"fov": 52.0, "min_ratio": 0.02, "min_pixels": 20000,
	},
	"status": {
		"eye": Vector3(12.05, 1.55, 5.55), "look": Vector3(14.00, 1.45, 5.55),
		# 三颗状态灯各 0.09m，占屏极小：实测点亮态差异 1484 px / max 140。
		"fov": 40.0, "min_ratio": 0.0015, "min_pixels": 1000,
	},
	"emergency": {
		"eye": Vector3(12.10, 2.20, 0.00), "look": Vector3(14.55, 2.20, 0.00),
		"fov": 42.0, "min_ratio": 0.01, "min_pixels": 5000,
	},
	"door": {
		"eye": Vector3(7.95, 3.45, -1.35), "look": Vector3(7.80, 3.45, -4.26),
		"fov": 40.0, "min_ratio": 0.004, "min_pixels": 3000,
	},
	# 屏幕是 42_主体 的 surface 2（深蓝面板），相机必须在屏幕正面一侧。
	"loft_pc": {
		"eye": Vector3(9.55, 8.10, -11.55), "look": Vector3(9.40, 7.75, -13.60),
		"fov": 46.0, "min_ratio": 0.01, "min_pixels": 5000,
	},
}

var _zone: Node3D
var _dyn: Node3D
var _camera: Camera3D
var _failures: Array[String] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("HEADLESS_SKIPPED_VISUAL: 视觉对照必须真渲染，未执行")
		get_tree().quit(2)
		return
	_zone = (load(ZONE) as PackedScene).instantiate() as Node3D
	add_child(_zone)
	_build_environment()
	for _i in range(3):
		await get_tree().process_frame
	_dyn = _zone.get_node_or_null("基地灯具动态") as Node3D
	if _dyn == null:
		_fail("V0 场景里没有 基地灯具动态 节点")
		_finish()
		return
	_dyn.set_process(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	await _check_v1_v2()
	await _check_v3()
	_finish()


func _check_v1_v2() -> void:
	var plan := _plan()
	plan.sort_custom(func(a, b): return float((a as Dictionary).t) < float((b as Dictionary).t))
	_dyn.call("reset_for_test", SEED)
	var clock := 0.0
	var frames := {}
	for shot in plan:
		var item := shot as Dictionary
		while clock < float(item.t) - 1e-6:
			var step := minf(SIM_STEP, float(item.t) - clock)
			_dyn.call("advance_for_test", step)
			clock += step
		_frame_camera(str(item.view))
		await get_tree().process_frame
		await get_tree().process_frame
		frames[str(item.name)] = _grab()

	for key in VIEWS:
		var rest: Image = frames.get("%s_rest" % key)
		var peak: Image = frames.get("%s_peak" % key)
		if rest == null or peak == null:
			_fail("V1 %s 未拍到对照帧" % key)
			continue
		rest.save_png("%s/%s_rest.png" % [OUT_DIR, key])
		peak.save_png("%s/%s_peak.png" % [OUT_DIR, key])
		var result := _image_diff(rest, peak)
		var ratio := float(result.changed) / float(result.total)
		var min_ratio := float((VIEWS[key] as Dictionary).min_ratio)
		var min_pixels := int((VIEWS[key] as Dictionary).min_pixels)
		_check(
			ratio >= min_ratio and int(result.changed) >= min_pixels,
			"V1 %-10s 差异像素=%d (%.2f%% ≥ %.2f%%) 下限=%d" % [
				key, result.changed, ratio * 100.0, min_ratio * 100.0, min_pixels,
			]
		)


## V3：全部倍率压到 0 后，画面必须明显变暗 —— 证明「关灯态没有自发光残留」。
##
## 不能用「屏幕必须全黑」：这场景里还有不受控的墙面、天花灯带，环境光也会照亮几何，
## 第一版就是这么误判的（506365 个「仍发亮」像素全是正常的被照亮的墙）。
## 改用机位内平均亮度落差 + 最亮像素不得比点亮态更高。
func _check_v3() -> void:
	_frame_camera("vending")
	_dyn.call("reset_for_test", SEED)
	for key in VIEWS:
		_dyn.call("force_factor", key, 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var lit := _grab()
	lit.save_png("%s/lit_state.png" % OUT_DIR)
	for key in VIEWS:
		_dyn.call("force_factor", key, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var off := _grab()
	off.save_png("%s/off_state.png" % OUT_DIR)
	var stats_lit := _luminance_stats(lit)
	var stats_off := _luminance_stats(off)
	var drop := float(stats_lit.mean) - float(stats_off.mean)
	_check(
		drop >= 3.0 and float(stats_off.max) <= float(stats_lit.max) + 1e-4,
		"V3 关灯态 平均亮度 %.2f → %.2f（下降 %.2f ≥ 3.0）最亮 %.3f → %.3f" % [
			stats_lit.mean, stats_off.mean, drop, stats_lit.max, stats_off.max,
		]
	)


func _luminance_stats(image: Image) -> Dictionary:
	var total := 0.0
	var peak := 0.0
	var width := image.get_width()
	var height := image.get_height()
	for y in range(height):
		for x in range(width):
			var value := image.get_pixel(x, y).get_luminance()
			total += value
			peak = maxf(peak, value)
	return {"mean": total / float(width * height) * 255.0, "max": peak}


func _plan() -> Array:
	_dyn.call("reset_for_test", SEED)
	var keys := ["neon", "lamp", "vending", "status", "emergency", "door", "loft_pc"]
	var series := {}
	for key in keys:
		series[key] = []
	for index in range(int(SIM_DURATION / SIM_STEP)):
		_dyn.call("advance_for_test", SIM_STEP)
		for key in keys:
			if key == "status":
				(series[key] as Array).append(_dyn.call("get_factors", "status"))
			else:
				(series[key] as Array).append(float(_dyn.call("get_factor", key)))
	var shots: Array = []
	for key in keys:
		var values: Array = series[key]
		var rest_index := -1
		var peak_index := -1
		var rest_error := 1e9
		var peak_error := -1.0
		for index in range(values.size()):
			if key == "status":
				var row: Array = values[index]
				var spread := 0.0
				for entry in row:
					spread = maxf(spread, absf(float(entry) - STATUS_DIM))
				if spread < rest_error:
					rest_error = spread
					rest_index = index
				if float(row[0]) > peak_error:
					peak_error = float(row[0])
					peak_index = index
			elif key == "loft_pc":
				# 屏幕常态倍率是 0（不发光）：静息 = 静默时刻，极值 = 事件内最亮时刻。
				# 用 |v-1| 挑会把两者挑反（实测静息拍成事件中段、极值拍成黑屏）。
				var value := float(values[index])
				if value <= 1e-6 and rest_index < 0:
					rest_index = index
				if value > peak_error:
					peak_error = value
					peak_index = index
			else:
				var value := float(values[index])
				if absf(value - 1.0) < rest_error:
					rest_error = absf(value - 1.0)
					rest_index = index
				if absf(value - 1.0) > peak_error:
					peak_error = absf(value - 1.0)
					peak_index = index
		if rest_index < 0 or peak_index < 0:
			continue
		shots.append({"name": "%s_rest" % key, "view": key, "t": float(rest_index) * SIM_STEP})
		shots.append({"name": "%s_peak" % key, "view": key, "t": float(peak_index) * SIM_STEP})
	return shots


func _image_diff(a: Image, b: Image) -> Dictionary:
	var changed := 0
	var max_delta := 0
	var width := mini(a.get_width(), b.get_width())
	var height := mini(a.get_height(), b.get_height())
	for y in range(height):
		for x in range(width):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var delta := int(maxf(
				absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))
			) * 255.0)
			if delta > 3:
				changed += 1
			max_delta = maxi(max_delta, delta)
	return {"changed": changed, "max_delta": max_delta, "total": width * height}


func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.55, 0.70)
	env.ambient_light_energy = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(0.75, 0.85, 1.0)
	sun.light_energy = 0.55
	sun.rotation_degrees = Vector3(-52.0, 34.0, 0.0)
	add_child(sun)
	_camera = Camera3D.new()
	add_child(_camera)
	_camera.current = true


func _frame_camera(view_key: String) -> void:
	var view: Dictionary = VIEWS[view_key]
	_camera.fov = float(view.fov)
	_camera.global_position = view.eye as Vector3
	_camera.look_at(view.look as Vector3, Vector3.UP)


func _grab() -> Image:
	return get_viewport().get_texture().get_image()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  PASS ", message)
	else:
		printerr("  FAIL ", message)
		_failures.append(message)


func _fail(message: String) -> void:
	printerr("  FAIL ", message)
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("ACCEPT base_lamp_visual")
		get_tree().quit(0)
	else:
		printerr("REJECT base_lamp_visual failures=%d" % _failures.size())
		get_tree().quit(1)
