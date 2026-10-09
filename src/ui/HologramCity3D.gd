extends Node3D
## World-space box city. Shared GPU instance animation; no gameplay/save ownership.
const BLOCK_SHADER = preload("res://assets/art/ui/expedition_city/hologram_block.gdshader")
const WIRE_SHADER = preload("res://assets/art/ui/expedition_city/hologram_wire.gdshader")
const FIELD_SHADER = preload("res://assets/art/ui/expedition_city/hologram_field.gdshader")
const FRAME_SHADER = preload("res://assets/art/ui/expedition_city/hologram_frame.gdshader")
const CITY_LAYER := 1 << 18
const CYAN := Color(0.02, 0.72, 1.0)
const PINK := Color(1.0, 0.025, 0.55)
# 入口标记的世界比例与交互反馈强度。悬停倍率由 1.09 提到 1.32，让"放大感"一眼可辨；
# 倍率与响应率都写在这里，方便按手感调，不散落在 face_markers 里。
const MARKER_SCALE := 0.09
const HOVER_SCALE := 1.32
const PUNCH_SCALE := 0.34
const HOVER_RESPONSE := 14.0
const PUNCH_DECAY := 5.0
const BORDER_FLOW_SPEED := 0.42
# 边框线宽：0.032 在近景下只有一两像素，流光跑起来看不出光带，故加粗到 0.05。
const BORDER_WIDTH := 0.05
var deployment := 0.0
var elapsed := 0.0
# 视觉焦点（-1 = 无）。必须与"选中项"分开：选中项是 Enter 的确认目标，光标移开时故意保留；
# 焦点才决定放大/流光/高亮，光标离开入口即置 -1，让入口自己缩回去，而不是等悬停到另一个。
var focus := -1
var sites: Array[Node3D] = []
var markers: Array[Node3D] = []
var labels: Array[Label3D] = []
var materials: Array[ShaderMaterial] = []
var border_materials: Array[Array] = []
var _hover: Array[float] = []
var _punch: Array[float] = []
var status: Label3D
var return_marker: Node3D
var block_count := 0
var _staged: Array[Dictionary] = []
var _stage_delay := 0.55
var _transition_blocks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 990129
	_build()

func _build() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var batches: Array[Array] = [[], [], [], []]
	for x in range(-16, 17):
		for z in range(-17, 11):
			if x % 5 == 0 or z % 5 == 0:
				continue
			if Vector2(x + 5, z - 2).length() < 2.8 or Vector2(x - 5, z - 1).length() < 2.8:
				continue
			var radius := Vector2(float(x) / 17.0, float(z + 3) / 17.0).length()
			if radius > 1.0 or _rng.randf() > pow(1.0 - radius, 0.40):
				continue
			if abs(x) < 3 and z < -3 and z > -8:
				continue
			var delay := 0.36 + radius * 0.39 + _rng.randf_range(0.0, 0.04)
			var height := _rng.randf_range(0.45, 2.5) * (1.25 - radius * 0.6)
			if z < -2:
				height += _rng.randf_range(0.0, 2.0)
			var width := _rng.randf_range(0.7, 0.96)
			var kind := 1 if _rng.randf() < 0.22 else 0
			_append_stepped_building(batches[kind], Vector3(x, 0, z), width, height, delay)
			if height > 1.5:
				batches[kind].append([Vector3(x, height + 0.22, z), Vector3(width * 0.72, 0.4, width * 0.72), delay])
			if _rng.randf() < 0.45:
				batches[2 + kind].append([Vector3(x, height + 0.8, z), Vector3.ONE * 0.65, delay])

	# Sparse outskirts beyond the main silhouette; varied skyline, not a solid border.
	for i in 42:
		var angle := float(i) * TAU / 42.0 + _rng.randf_range(-0.045, 0.045)
		var p := Vector3(cos(angle) * _rng.randf_range(18.0, 24.0), 0, sin(angle) * _rng.randf_range(14.0, 22.0) - 3.0)
		var height := _rng.randf_range(0.65, 5.5)
		var width := _rng.randf_range(0.55, 1.3)
		var kind := 1 if i % 4 == 0 else 0
		var delay := _rng.randf_range(0.60, 0.78)
		_append_stepped_building(batches[kind], p, width, height, delay)
		batches[2 + kind].append([p + Vector3.UP * (height + 0.5), Vector3.ONE * width * 0.8, delay])
	for tier in 9:
		batches[tier % 2].append([Vector3(0, tier * 1.1 + 0.55, -5), Vector3(4.3 - tier * 0.35, 1.05, 3.1 - tier * 0.22), tier * 0.009])
	for side in [-1, 1]:
		for tier in 5:
			batches[0].append([Vector3(side * 2.6, tier * 0.9 + 0.45, -5.3), Vector3(0.8, 0.86, 0.9), 0.04 + tier * 0.009])
	for index in 4:
		var mat := ShaderMaterial.new()
		mat.shader = BLOCK_SHADER if index < 2 else WIRE_SHADER
		mat.set_shader_parameter("tint", CYAN if index % 2 == 0 else PINK)
		mat.set_shader_parameter("wire_only", 1.0 if index > 1 else 0.0)
		materials.append(mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = box
		mm.instance_count = batches[index].size()
		for i in batches[index].size():
			var b: Array = batches[index][i]
			if index < 2:
				_transition_blocks.append({"position": b[0], "height": b[1].y, "delay": b[2], "color": CYAN if index == 0 else PINK})
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(b[1]), b[0]))
			mm.set_instance_custom_data(i, Color(float(b[2]), _rng.randf(), _rng.randf(), maxf(0.0, b[0].y / b[1].y - 0.5)))
		var instance := MultiMeshInstance3D.new()
		instance.name = "AnimatedBlocks%d" % index
		instance.multimesh = mm
		instance.material_override = mat
		instance.layers = CITY_LAYER
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		block_count += mm.instance_count
	var field := MeshInstance3D.new()
	var field_mesh := PlaneMesh.new()
	field_mesh.size = Vector2(400, 400)
	field.mesh = field_mesh
	field.position.y = -0.32
	field.layers = CITY_LAYER
	var field_mat := ShaderMaterial.new()
	field_mat.shader = FIELD_SHADER
	field.material_override = field_mat
	materials.append(field_mat)
	add_child(field)
	for x in range(-12, 13):
		var extent := sqrt(maxf(0.0, 1.0 - pow(float(x) / 13.0, 2.0))) * 9.0
		_stage_delay = 0.35 + absf(float(x)) * 0.025
		_line(self, Vector3(x, 0, -extent), Vector3(x, 0, extent), CYAN * 0.12, 0.012)
	for z in range(-9, 10):
		var extent := sqrt(maxf(0.0, 1.0 - pow(float(z) / 10.0, 2.0))) * 12.0
		_stage_delay = 0.35 + absf(float(z)) * 0.03
		_line(self, Vector3(-extent, 0, z), Vector3(extent, 0, z), CYAN * 0.12, 0.012)
	for i in 2:
		_stage_delay = -1.0
		_hover.append(0.0)
		_punch.append(0.0)
		border_materials.append([])
		var site := Node3D.new()
		site.name = "Expedition01" if i == 0 else "Test99"
		site.position = Vector3(-5, 2.7, 2) if i == 0 else Vector3(5, 2.9, 1)
		add_child(site)
		sites.append(site)
		var color := CYAN if i == 0 else PINK
		_box(site, Vector3(0, -1.5, 0), Vector3(3.1, 2.8, 3.1), color * 0.045, 0.4)
		for floor_index in 5:
			_octagon(site, -0.7 - floor_index * 0.4, 1.65, color * 0.45, 0.035)
		for y in [0.0, -0.24, -0.55]:
			_octagon(site, float(y), 1.85 + float(y) * 0.22, color, 0.055)
		var marker := Node3D.new()
		marker.position.y = 1.3
		site.add_child(marker)
		markers.append(marker)
		_box(marker, Vector3.ZERO, Vector3(3.2, 2.2, 0.12), Color(0.006, 0.015, 0.04), 0.1)
		# 顺时针四角连成边框；每条边按自身周长占比分配流光相位，四条合起来是一整圈环流。
		var frame_corners := [Vector3(-1.62, 1.1, 0.09), Vector3(1.62, 1.1, 0.09), Vector3(1.62, -1.1, 0.09), Vector3(-1.62, -1.1, 0.09)]
		var perimeter := 0.0
		for corner in 4:
			perimeter += frame_corners[corner].distance_to(frame_corners[(corner + 1) % 4])
		var running := 0.0
		for corner in 4:
			var from: Vector3 = frame_corners[corner]
			var to: Vector3 = frame_corners[(corner + 1) % 4]
			var segment := from.distance_to(to)
			var border := _line(marker, from, to, color, BORDER_WIDTH)
			var flow := ShaderMaterial.new()
			flow.shader = FRAME_SHADER
			flow.set_shader_parameter("tint", color)
			flow.set_shader_parameter("line_length", segment)
			flow.set_shader_parameter("arc_span", segment / perimeter)
			flow.set_shader_parameter("flow_offset", running / perimeter)
			flow.set_shader_parameter("flow_speed", BORDER_FLOW_SPEED)
			border.material_override = flow
			border_materials[i].append(flow)
			running += segment
		var id := "expedition_01" if i == 0 else "99"
		var entry: Dictionary = GameDesignConfig.expedition_level(id)
		labels.append(_label(marker, str(entry.get("display_name", id)), Vector3(0, 0.22, 0.11), 65, 0.0065, Color.WHITE))
		_label(marker, "01  /  EXPEDITION" if i == 0 else "99  /  TEST SECTOR", Vector3(0, 0.75, 0.11), 30, 0.0065, color)
		_label(marker, "点击进入  ·  ENTER", Vector3(0, -0.48, 0.11), 30, 0.0065, color)
	_stage_delay = 0.68
	var points := [Vector3(-5, 2.75, 2), Vector3(-2.5, 2.75, 2), Vector3(0, 2.75, -0.5), Vector3(3, 2.75, -0.5), Vector3(5, 2.75, 1)]
	for i in range(points.size() - 1):
		_line(self, points[i], points[i + 1], CYAN if i < 2 else PINK, 0.07)
	_stage_delay = 0.07
	_box(self, Vector3(0, 5.5, -3.4), Vector3(3.5, 3.9, 0.15), Color(0.012, 0.016, 0.065), 0.2)
	_label(self, "SHELLSTORM", Vector3(0, 4.8, -3.29), 90, 0.007, Color(0.52, 0.39, 1))
	_label(self, "BASE 99F", Vector3(0, 4.1, -3.28), 40, 0.007, CYAN)
	_box(self, Vector3(0, 6, -3.27), Vector3(0.75, 0.65, 0.12), Color(0.7, 0.25, 1), 1.6)
	for side in [-1, 1]:
		var ear := _box(self, Vector3(side * 0.25, 6.65, -3.27), Vector3(0.22, 0.8, 0.12), Color(0.7, 0.25, 1), 1.6)
		ear.rotation.z = side * -0.18
		_box(self, Vector3(side * 0.18, 6.08, -3.19), Vector3(0.085, 0.11, 0.02), Color(0.01, 0.01, 0.03), 0.0)
		_line(self, Vector3(side * 1.78, 3.55, -3.29), Vector3(side * 1.78, 7.45, -3.29), PINK, 0.035)
	_stage_delay = 0.76
	_label(self, "SHELLSTORM  /  BASE 99F", Vector3(-6.5, 0.15, -8.2), 44, 0.006, CYAN)
	status = _label(self, "方向键 / WASD 选择    ENTER 确认    ESC 返回", Vector3(0, 0.3, 9), 36, 0.0065, CYAN)
	return_marker = Node3D.new()
	return_marker.position = Vector3(-7, 1.0, 8.5)
	add_child(return_marker)
	_label(return_marker, "‹ 返回基地", Vector3.ZERO, 50, 0.007, CYAN)
	var stars := MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	stars.mesh = box
	stars.instance_count = 260
	for i in 260:
		var p := Vector3(_rng.randf_range(-16, 16), _rng.randf_range(0.4, 10), _rng.randf_range(-13, 10))
		stars.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * _rng.randf_range(0.018, 0.055)), p))
	var particles := MultiMeshInstance3D.new()
	particles.multimesh = stars
	particles.layers = CITY_LAYER
	particles.material_override = _material(CYAN * 1.8, 1.0)
	add_child(particles)
	_staged.append({"node": particles, "position": particles.position, "delay": 0.32})
	_build_transition_particles()
	_update_staging()

func _append_stepped_building(batch: Array, base: Vector3, width: float, height: float, delay: float) -> void:
	# Four substantial, grid-aligned feet replace the straight lower silhouette.
	# Coordinate-derived variation preserves the existing city layout/random stream.
	var relief := minf(width * 0.48, height * 0.32)
	var body_bottom := relief * 0.82
	batch.append([base + Vector3.UP * (height + body_bottom) * 0.5, Vector3(width, height - body_bottom, width), delay])
	var pattern := posmod(int(base.x * 7.0 + base.z * 11.0), 4)
	var levels := [0.0, 0.32, 0.70, 0.18]
	for cell in 4:
		var bottom: float = relief * float(levels[(cell + pattern) % 4])
		var top := body_bottom + relief * 0.12
		var offset := Vector3((-0.25 if cell % 2 == 0 else 0.25) * width, (bottom + top) * 0.5, (-0.25 if cell < 2 else 0.25) * width)
		batch.append([base + offset, Vector3(width * 0.5, top - bottom, width * 0.5), delay])

func _process(delta: float) -> void:
	elapsed += delta
	for mat in materials:
		mat.set_shader_parameter("clock", elapsed)
		mat.set_shader_parameter("deployment", deployment)
	_update_staging()
	for i in sites.size():
		var rise := site_reveal(i)
		sites[i].visible = rise > 0.001
		sites[i].scale.y = maxf(0.001, rise)
		sites[i].position.y = (2.7 if i == 0 else 2.9) * rise
		markers[i].position.y = 1.3 + sin(elapsed * 1.6 + i) * 0.09
		labels[i].modulate = Color.WHITE if i == focus else Color(0.65, 0.78, 0.9)
		# 悬停强度平滑收敛到焦点：焦点为 -1 时全部回落到静止尺寸，即"光标移开就复原"。
		_hover[i] = lerpf(_hover[i], 1.0 if i == focus else 0.0, 1.0 - exp(-HOVER_RESPONSE * delta))
		_punch[i] = maxf(0.0, _punch[i] - PUNCH_DECAY * delta)
		for flow in border_materials[i]:
			flow.set_shader_parameter("clock", elapsed)
			flow.set_shader_parameter("hover", _hover[i])

func face_markers(camera: Camera3D) -> void:
	for i in markers.size():
		var emphasis := 1.0 + (HOVER_SCALE - 1.0) * _hover[i] + PUNCH_SCALE * pow(_punch[i], 0.7)
		markers[i].global_basis = camera.global_basis.scaled(Vector3.ONE * MARKER_SCALE * maxf(0.001, site_reveal(i)) * emphasis)

func punch_marker(index: int) -> void:
	# 点击弹性反馈：脉冲置满后由 _process 逐帧衰减回落，形成放大再回弹的手感。
	if index >= 0 and index < _punch.size():
		_punch[index] = 1.0

func site_reveal(index: int) -> float:
	return smoothstep(0.24 + index * 0.22, 0.46 + index * 0.22, deployment)

func _update_staging() -> void:
	for item in _staged:
		var rise := smoothstep(float(item.delay), float(item.delay) + 0.2, deployment)
		var node: GeometryInstance3D = item.node
		node.visible = rise > 0.001
		node.transparency = 1.0 - rise
		if node is MeshInstance3D:
			node.position.y = float(item.position.y) * rise
	for item in _transition_blocks:
		if not item.has("node"):
			continue
		var phase := clampf((deployment - float(item.delay)) / 0.2, 0.0, 1.0)
		var envelope := sin(phase * PI)
		var node: MultiMeshInstance3D = item.node
		node.visible = envelope > 0.001
		node.transparency = 1.0 - envelope
		node.position.y = float(item.top) * smoothstep(0.0, 1.0, phase)
		node.scale = Vector3.ONE * maxf(0.001, envelope)

func _build_transition_particles() -> void:
	# Small instanced cubes follow each building's construction/retraction front.
	for index in 2:
		_transition_blocks.append({"position": sites[index].position, "height": 3.0, "delay": 0.24 + index * 0.22, "color": CYAN if index == 0 else PINK})
	for item in _transition_blocks:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * 0.11
		mm.mesh = mesh
		mm.instance_count = 6
		for i in 6:
			var angle := float(i) * TAU / 6.0
			mm.set_instance_transform(i, Transform3D(Basis.from_euler(Vector3(i, i * 0.7, i * 0.3)), Vector3(cos(angle) * 0.6, _rng.randf_range(-0.35, 0.6), sin(angle) * 0.6)))
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.layers = CITY_LAYER
		node.material_override = _material(item.color, 2.0)
		node.position = item.position
		add_child(node)
		item.node = node
		item.top = float(item.position.y) + float(item.height) * 0.5
	# Initial state must be applied before the first rendered frame.

func _label(parent: Node3D, text: String, pos: Vector3, font_size: int, pixel_size: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 3
	label.outline_modulate = Color(0, 0.008, 0.02)
	label.layers = CITY_LAYER
	parent.add_child(label)
	if _stage_delay >= 0.0:
		_staged.append({"node": label, "position": pos, "delay": _stage_delay})
	return label

func _material(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, energy: float = 1.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	node.layers = CITY_LAYER
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = _material(color, energy)
	parent.add_child(node)
	if _stage_delay >= 0.0:
		_staged.append({"node": node, "position": pos, "delay": _stage_delay})
	return node

func _line(parent: Node3D, a: Vector3, b: Vector3, color: Color, width: float) -> MeshInstance3D:
	var node := _box(parent, (a + b) * 0.5, Vector3(width, width, a.distance_to(b)), color, 2.0)
	node.basis = Basis.looking_at((b - a).normalized(), Vector3.RIGHT if absf((b - a).normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP)
	return node

func _octagon(parent: Node3D, y: float, radius: float, color: Color, width: float) -> void:
	for i in 8:
		var a := float(i) * TAU / 8.0
		var b := float(i + 1) * TAU / 8.0
		_line(parent, Vector3(cos(a) * radius, y, sin(a) * radius), Vector3(cos(b) * radius, y, sin(b) * radius), color, width)
