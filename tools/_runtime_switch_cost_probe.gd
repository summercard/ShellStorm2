extends Node3D
## 「非材质属性的运行时代价」体检。
##
## 一起因：2026-10-31 定位受击卡顿，发现 `StandardMaterial3D.emission_enabled` 是 shader
## 变体开关（翻一次 +107ms）。顺线要回答「还有没有别的开关同样贵」，材质那一半已由
## `_material_variant_cost_probe` 覆盖，本探针补**非材质**的那一半：
##   · 灯光：`shadow_enabled` / `visible`
##   · 文字：`Label3D.font_size` / `outline_size`（伤害飘字每发都在改）
##   · 实例：`material_override` 换一份 / `mesh` 换一份 / `visible`
##
## 口径与材质探针一致：**hit_p50 − idle_p50 差值**，阈值 3ms 以上算贵。
## ⚠ 必须 `--disable-vsync`，否则帧时被锁 16.7ms、尖峰全被吃掉。
##
## 用法：
##   godot --path . --scene res://tools/_runtime_switch_cost_probe.tscn --disable-vsync
## 只读。

const SAMPLE_FRAMES := 120
const HIT_EVERY := 6
const EXPENSIVE_MS := 3.0

var _material: StandardMaterial3D
var _alt_material: StandardMaterial3D
var _box: MeshInstance3D
var _light: OmniLight3D
var _sun: DirectionalLight3D
var _label: Label3D
var _rows: Array[Dictionary] = []


func _ready() -> void:
	_build_stage()
	for _i in 5:
		await get_tree().process_frame
	await _run_all()
	_report()
	get_tree().quit(0)


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.10, 0.12)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.environment = environment
	add_child(env)

	# 平行光必须**开阴影**，否则量的是"什么都没有"的假 0。
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, 30, 0)
	_sun.light_energy = 1.2
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(_sun)

	# 点光也开阴影：`WastelandLight3D.set_runtime_active()` 每次流送都翻它的
	# `shadow_enabled`，这条是本次要量的重点。
	_light = OmniLight3D.new()
	_light.position = Vector3(1.5, 2.2, 1.0)
	_light.light_energy = 2.0
	_light.omni_range = 6.0
	_light.shadow_enabled = true
	add_child(_light)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	add_child(floor_mesh)

	# 受光体：让阴影真的被算出来，否则 shadow_enabled 翻转无内容可重建。
	var pillar := MeshInstance3D.new()
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.4
	pillar_mesh.bottom_radius = 0.4
	pillar_mesh.height = 2.0
	pillar.mesh = pillar_mesh
	pillar.position = Vector3(0, 1.0, 0)
	add_child(pillar)

	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.8, 0.7, 0.6)
	_alt_material = StandardMaterial3D.new()
	_alt_material.albedo_color = Color(0.6, 0.7, 0.8)

	_box = MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.0, 1.0, 1.0)
	_box.mesh = box_mesh
	_box.material_override = _material
	_box.position = Vector3(-1.4, 0.5, 0)
	add_child(_box)

	_label = Label3D.new()
	_label.text = "17"
	_label.font_size = 116
	_label.outline_size = 13
	_label.pixel_size = 0.00375
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.transparency = 0.0
	_label.position = Vector3(0, 2.2, 0)
	add_child(_label)

	var camera := Camera3D.new()
	camera.current = true
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 2.0, 5.0), Vector3(0, 1.0, 0), Vector3.UP)


func _run_all() -> void:
	await _measure("baseline (no-op)", func() -> void: pass)

	# ── 灯光 ─────────────────────────────────────────────────────────
	var shadow := [true]
	await _measure("LIGHT omni shadow_enabled", func() -> void:
		shadow[0] = not shadow[0]
		_light.shadow_enabled = shadow[0]
	)
	var sun_shadow := [true]
	await _measure("LIGHT sun shadow_enabled", func() -> void:
		sun_shadow[0] = not sun_shadow[0]
		_sun.shadow_enabled = sun_shadow[0]
	)
	var light_visible := [true]
	await _measure("LIGHT omni visible", func() -> void:
		light_visible[0] = not light_visible[0]
		_light.visible = light_visible[0]
	)
	# 只改能量：这是"灭灯"的正确姿势。
	var energy_lit := [true]
	await _measure("LIGHT omni energy 0<->2(安全姿势)", func() -> void:
		energy_lit[0] = not energy_lit[0]
		_light.light_energy = 2.0 if energy_lit[0] else 0.0
	)

	# ── 文字（伤害飘字每发都改 font_size / outline_size）────────────────
	var big := [false]
	await _measure("LABEL font_size 116<->134", func() -> void:
		big[0] = not big[0]
		_label.font_size = 134 if big[0] else 116
	)
	var fat := [false]
	await _measure("LABEL outline_size 13<->15", func() -> void:
		fat[0] = not fat[0]
		_label.outline_size = 15 if fat[0] else 13
	)
	var text_toggle := [false]
	await _measure("LABEL text \"17\"<->\"18\"", func() -> void:
		text_toggle[0] = not text_toggle[0]
		_label.text = "18" if text_toggle[0] else "17"
	)
	var label_alpha := [0.0]
	await _measure("LABEL transparency 0<->0.5", func() -> void:
		label_alpha[0] = 0.5 if label_alpha[0] == 0.0 else 0.0
		_label.transparency = label_alpha[0]
	)

	# ── 实例级 ───────────────────────────────────────────────────────
	var swap := [false]
	await _measure("MESH material_override 换一份", func() -> void:
		swap[0] = not swap[0]
		_box.material_override = _alt_material if swap[0] else _material
	)
	var mesh_swap := [false]
	await _measure("MESH 换 mesh 资源", func() -> void:
		mesh_swap[0] = not mesh_swap[0]
		var replacement := BoxMesh.new()
		replacement.size = Vector3(1.1, 1.1, 1.1) if mesh_swap[0] else Vector3(1.0, 1.0, 1.0)
		_box.mesh = replacement
	)
	var box_visible := [true]
	await _measure("MESH visible", func() -> void:
		box_visible[0] = not box_visible[0]
		_box.visible = box_visible[0]
	)

	# 材质里**带贴图**的两条：换贴图也是变体（USE_TEXTURE / USE_EMISSION_TEXTURE）。
	#
	# ⚠ 必须先把手上的 override 恢复成 `_material`：上一组把 `material_override` 换成了
	# `_alt_material`，此时改 `_material` 的贴图**没有任何东西在渲染**，读出来必然是 0 ——
	# 那是"假绿"，不是"不贵"（本探针第一版就这么把自己骗过去了）。
	_box.material_override = _material
	await get_tree().process_frame
	var albedo_tex := [false]
	await _measure("MAT albedo_texture 有/无", func() -> void:
		albedo_tex[0] = not albedo_tex[0]
		_material.albedo_texture = _make_texture() if albedo_tex[0] else null
	)
	var emission_tex := [false]
	await _measure("MAT emission_texture 有/无", func() -> void:
		emission_tex[0] = not emission_tex[0]
		_material.emission_texture = _make_texture() if emission_tex[0] else null
	)
	# **阳性对照**：同一份 `_material` 上翻 `emission_enabled`（已知 +100ms 量级）。
	# 没有这一条，上面任何一行读 0 都可能是"探针本身测不出东西"，
	# 而不是"这个开关真的便宜"。同理，`_material` 此刻必须确实挂在渲染面上。
	var emission_gate := [false]
	await _measure("MAT emission_enabled（阳性对照）", func() -> void:
		emission_gate[0] = not emission_gate[0]
		_material.emission_enabled = emission_gate[0]
	)


func _make_texture() -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
	image.fill(Color(0.9, 0.8, 0.7))
	return ImageTexture.create_from_image(image)


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
	_rows.append({"label": label, "delta": delta})
	print("  %-42s hit_p50=%6.2f idle_p50=%6.2f delta=%+7.2fms"
		% [label, _percentile(hits, 0.5), _percentile(idle, 0.5), delta])


func _report() -> void:
	var expensive: Array[String] = []
	print("")
	print("SWITCH_COST 汇总（阈值 %.1fms）" % EXPENSIVE_MS)
	for row in _rows:
		if float(row["delta"]) >= EXPENSIVE_MS:
			expensive.append(str(row["label"]))
	print("  昂贵项 %d / %d" % [expensive.size(), _rows.size()])
	for label in expensive:
		print("    - ", label)
	print("RUNTIME_SWITCH_PROBE_DONE")


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(int(float(sorted.size()) * ratio), sorted.size() - 1)]
