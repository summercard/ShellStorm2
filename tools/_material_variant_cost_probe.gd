extends Node3D
## 「材质属性开关的运行时代价」体检。
##
## 起因（2026-10-31）：远征03 打中怪物会卡。定位到受击闪白用
## `material.emission_enabled = _flash_time > 0.0` 实现，而这个属性在 Godot 里是
## **shader define（USE_EMISSION）不是 uniform**，每翻一次要重建 GPU 管线
## （实测 +98ms/次）。闪白恰好每次受击翻两次 ⇒ 每打中一下卡一下。
##
## 本项目里同类的「运行时翻材质属性」还有十几处（灯具、图标、全息楼群、VFX）。
## 到底哪些贵、哪些白担心，靠猜没用 —— 这个探针逐项量：
##   · 变体类（shader define）：翻一次就是一次管线重建
##   · uniform 类：随便每帧改
##
## 判据：**hit_p50 − idle_p50**（窗口模式帧率会漂，差值才是"这一下额外付了多少"）。
## 阈值 3ms 以上算贵（16.7ms 帧预算的 18%），肉眼就是一次顿。
##
## 用法：
##   godot --path . --scene res://tools/_material_variant_cost_probe.tscn --disable-vsync
## ⚠ 必须带 `--disable-vsync`：开同步时帧时被锁在 16.7ms，尖峰被吃掉、全部读成 0。

const SAMPLE_FRAMES := 120
const HIT_EVERY := 6
const EXPENSIVE_MS := 3.0

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _rows: Array[Dictionary] = []


func _ready() -> void:
	_build_stage()
	for _i in 4:
		await get_tree().process_frame
	await _run_all()
	_report()
	get_tree().quit(0)


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.12, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-52, 35, 0)
	light.light_energy = 1.2
	add_child(light)

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.75, 0.72, 0.68)
	_material.roughness = 0.7
	_mesh = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.2, 1.8, 1.2)
	_mesh.mesh = mesh
	_mesh.material_override = _material
	add_child(_mesh)

	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 1.4, 3.4), Vector3(0, 0.9, 0), Vector3.UP)


func _run_all() -> void:
	# 基线：什么都不做 / 只改 uniform。
	await _measure("baseline (no-op)", func() -> void: pass)
	await _measure("uniform albedo_color", func() -> void:
		_material.albedo_color = Color(0.8, 0.6, 0.5) if _material.albedo_color.r < 0.78 else Color(0.75, 0.72, 0.68)
	)
	await _measure("uniform emission_energy", func() -> void:
		_material.emission_energy_multiplier = 0.6 if _material.emission_energy_multiplier == 0.0 else 0.0
	)
	await _measure("uniform roughness", func() -> void:
		_material.roughness = 0.4 if _material.roughness > 0.5 else 0.7
	)
	# 变体类：每次翻都要换 shader 变体。
	await _measure("VAR emission_enabled", func() -> void:
		_material.emission_enabled = not _material.emission_enabled
	)
	await _measure("VAR transparency", func() -> void:
		_material.transparency = (
			BaseMaterial3D.TRANSPARENCY_DISABLED
			if _material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
			else BaseMaterial3D.TRANSPARENCY_ALPHA
		)
	)
	await _measure("VAR shading_mode", func() -> void:
		_material.shading_mode = (
			BaseMaterial3D.SHADING_MODE_UNSHADED
			if _material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL
			else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		)
	)
	await _measure("VAR cull_mode", func() -> void:
		_material.cull_mode = (
			BaseMaterial3D.CULL_DISABLED
			if _material.cull_mode == BaseMaterial3D.CULL_BACK
			else BaseMaterial3D.CULL_BACK
		)
	)
	await _measure("VAR depth_draw_mode", func() -> void:
		_material.depth_draw_mode = (
			BaseMaterial3D.DEPTH_DRAW_ALWAYS
			if _material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
			else BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		)
	)
	await _measure("VAR vertex_color_albedo", func() -> void:
		_material.vertex_color_use_as_albedo = not _material.vertex_color_use_as_albedo
	)
	await _measure("VAR billboard_mode", func() -> void:
		_material.billboard_mode = (
			BaseMaterial3D.BILLBOARD_ENABLED
			if _material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED
			else BaseMaterial3D.BILLBOARD_DISABLED
		)
	)
	await _measure("VAR receive_shadows", func() -> void:
		_material.disable_receive_shadows = not _material.disable_receive_shadows
	)
	await _measure("VAR no_depth_test", func() -> void:
		_material.no_depth_test = not _material.no_depth_test
	)
	# 非材质、但同一类"实例级开关"，用来划清边界：这些是 uniform，不该贵。
	await _measure("instance transparency(GeometryInstance3D)", func() -> void:
		_mesh.transparency = 0.3 if _mesh.transparency == 0.0 else 0.0
	)
	await _measure("instance cast_shadow", func() -> void:
		_mesh.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if _mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
	)


func _measure(label: String, action: Callable) -> void:
	var hits: Array[float] = []
	var idle: Array[float] = []
	var last := Time.get_ticks_usec()
	for i in SAMPLE_FRAMES:
		var will_hit := i % HIT_EVERY == 0
		if will_hit:
			action.call()
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - last) / 1000.0
		last = now
		if will_hit:
			hits.append(frame_ms)
		else:
			idle.append(frame_ms)
	var delta := _percentile(hits, 0.5) - _percentile(idle, 0.5)
	_rows.append({"label": label, "delta": delta, "hit": _percentile(hits, 0.5), "idle": _percentile(idle, 0.5)})
	print("  %-40s hit_p50=%6.2f idle_p50=%6.2f delta=%+7.2fms" % [label, _percentile(hits, 0.5), _percentile(idle, 0.5), delta])


func _report() -> void:
	var expensive: Array[String] = []
	print("")
	print("VARIANT_COST 汇总（阈值 %.1fms）" % EXPENSIVE_MS)
	for row in _rows:
		if float(row["delta"]) >= EXPENSIVE_MS:
			expensive.append(str(row["label"]))
	print("  昂贵项 %d / %d：%s" % [expensive.size(), _rows.size(), ", ".join(expensive)])
	print("MATERIAL_VARIANT_PROBE_DONE")


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(int(float(sorted.size()) * ratio), sorted.size() - 1)]
