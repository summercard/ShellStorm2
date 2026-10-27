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
## 全息城里的入口站位。**按 level_id 索引，不按数组下标** ——
## 早期这里是 `SITE_POSITIONS[i]` + 一堆 `if i == 2`，导致"加一张关卡就要改五处下标判断"，
## 而且情报室的导航顺序一变，站位就整体错位。改成按 id 查表后，加关卡只需在这里补一行。
##
## `position`：该入口的楼群基座中心（世界坐标，相对全息城）；
## `clear_radius`：这一带要让出空地的半径（主循环生成楼群时按它挖空，保证入口不被楼挡住）；
## `marker_x`：标记牌相对基座的横向偏移（后排入口会向左偏，避让前排）；
## `marker_scale`：标记牌尺寸倍率 —— 后排入口小一号，形成前后景层次；
## `clear_stage`：`"grid"` = 生成楼群时就跳过这一带（前排两个的历史路径，**改动会偏移整条随机流**）；
## `"post"` = 生成完成后从批次里剔除（后排用，只影响自己那一小块）。
## `sightline`：视廊半径（缺省 0 = 不挖视廊）。
##
## ⚠️ 为什么需要 `sightline`：只挖"落脚点附近的空地"**不足以保证看得见**。
## 后排入口到镜头之间还有一段楼群，它们会把入口牌挡在后面 —— 而 `_pick()` 用的是
## 射线与标记平面的求交，**不考虑遮挡**，所以"点得到"和"看得见"是两件事：
## 03 首次就是断言全绿、截图里却只剩三个入口。视廊只剔除挡在两者之间的方块，
## 既不移动任何入口，也不消耗随机数。
const SITE_ANCHORS := {
	"expedition_01": {"position": Vector3(-5, 2.7, 2), "clear_radius": 2.8, "marker_x": 0.0, "marker_scale": 1.0, "clear_stage": "grid"},
	"99": {"position": Vector3(5, 2.9, 1), "clear_radius": 2.8, "marker_x": 0.0, "marker_scale": 1.0, "clear_stage": "grid"},
	"expedition_02": {"position": Vector3(-4, 2.7, -5), "clear_radius": 2.5, "marker_x": -0.6, "marker_scale": 0.78, "clear_stage": "post"},
	"expedition_03": {"position": Vector3(4.4, 2.8, -5.2), "clear_radius": 2.5, "marker_x": -0.6, "marker_scale": 0.78, "clear_stage": "post", "sightline": 1.9},
}
## 情报室近景镜头在**全息城局部坐标**里的位置。
##
## 这个值不是新的真源，而是 `RogueMapSelectMenu` 那条固定推进路径的换算结果：
## 镜头落点是 `anchor + (0.65, 1.42, 1.85)`，而 `city.scale = 0.09`，
## 因此局部坐标 = `(0.65, 1.42, 1.85) / 0.09 ≈ (7.2, 15.8, 20.6)`。
## 两处硬编码（镜头偏移、城市缩放）在菜单里有注释指回这里；任何一处改了，视廊就要重算。
const APPROACH_CAMERA_LOCAL := Vector3(7.2, 15.8, 20.6)
## 未登记的 level_id 会落到 `_anchor_for()` 的外环兜底站位，而不是崩掉或叠在原点。
var entry_deployment := 0.0
var entries_ready := false
## 由选关菜单在实例化后、`_ready()` 之前写入。**本级不再自己推导关卡清单** ——
## 谁是入口、谁先谁后只允许有一个真源（`GameDesignConfig` + 解锁判定，在菜单侧）。
## `_ready()` 时若仍为空，才退回清单默认值，避免单独预览本场景时什么都不出现。
var level_ids: Array[String] = []
## 与 `level_ids` 一一对应的站位表（含兜底项），下标与 sites/markers/labels 对齐。
var _anchors: Array[Dictionary] = []
## `clear_stage == "grid"` 的站位子集，供主循环挖空判定用。
var _grid_sites: Array[Dictionary] = []
var deployment := 0.0
var elapsed := 0.0
# 视觉焦点（-1 = 无）。必须与"选中项"分开：选中项是 Enter 的确认目标，光标移开时故意保留；
# 焦点才决定放大/流光/高亮，光标离开入口即置 -1，让入口自己缩回去，而不是等悬停到另一个。
var focus := -1
var sites: Array[Node3D] = []
var markers: Array[Node3D] = []
var labels: Array[Label3D] = []
var entry_hints: Array[Label3D] = []
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
	# 导航清单由选关菜单写入（唯一真源）。没写时退回清单登记顺序 ——
	# 这条分支只服务"在编辑器里单独预览 hologram_city.tscn"，不参与正式流程。
	if level_ids.is_empty():
		level_ids = GameDesignConfig.expedition_nav_order()
	_rng.seed = 990129
	_build()


## 关卡 id → 站位。未登记时落到外环兜底，并明确告警 ——
## 静默叠在原点会让"加了一条配置但忘了加站位"表现成"入口全挤成一坨"，极难查。
func _anchor_for(level_id: String) -> Dictionary:
	if SITE_ANCHORS.has(level_id):
		var anchor: Dictionary = (SITE_ANCHORS[level_id] as Dictionary).duplicate()
		if not anchor.has("clear_stage"):
			anchor["clear_stage"] = "post"
		return anchor
	push_warning("[HologramCity] 关卡 %s 未登记 SITE_ANCHORS，使用外环兜底站位" % level_id)
	var angle := float(maxi(level_ids.find(level_id), 0)) * TAU / 6.0 + PI * 0.5
	return {
		"position": Vector3(cos(angle) * 8.0, 2.6, sin(angle) * 7.0),
		"clear_radius": 2.5,
		"marker_x": 0.0,
		"marker_scale": 0.7,
		"clear_stage": "post",
	}


## 主循环阶段的让位判定：只有 `clear_stage == "grid"` 的入口在这里挖空。
##
## ⚠️ 为什么 02/03 不在这里挖：这里 continue 会跳过 `_rng.randf()`，**整条随机流会偏移**，
## 全城天际线随之变化。后排入口是在生成完成后从批次里剔除方块（不消耗随机数），
## 所以它们的天际线影响是局部的、可预期的。
func _grid_cleared(x: float, z: float) -> bool:
	for site in _grid_sites:
		var center: Vector3 = site["position"]
		if Vector2(x - center.x, z - center.z).length() < float(site["clear_radius"]):
			return true
	return false


## 点到线段的平面距离。用于视廊剔除；退化情形（两点重合）按点距处理，不返回 0。
func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var span := to - from
	var length_squared := span.length_squared()
	if length_squared < 0.000001:
		return point.distance_to(from)
	var t := clampf((point - from).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(from + span * t)


## 验收用：数出"挡在镜头与某个入口牌之间"的方块数。
##
## 量的是**已经生成的 MultiMesh 实例**，不是生成前的批次 —— 所以它真的能抓到
## "视廊没剔干净"或"有人挪了入口但忘了重算视廊"。本关首次上线时断言全绿、
## 截图里却只剩三个入口，就是因为当时没有任何一条断言在管遮挡。
## 装饰性的星点方块（名称不以 `AnimatedBlocks` 开头）不计入。
func sightline_occluders(index: int, radius: float) -> int:
	if index < 0 or index >= _anchors.size():
		return -1
	var target: Vector3 = _anchors[index]["position"]
	if index < markers.size():
		target += Vector3(0, markers[index].position.y, 0)
	var flat_from := Vector2(APPROACH_CAMERA_LOCAL.x, APPROACH_CAMERA_LOCAL.z)
	var flat_to := Vector2(target.x, target.z)
	var count := 0
	for child in get_children():
		if not (child is MultiMeshInstance3D) or not String(child.name).begins_with("AnimatedBlocks"):
			continue
		var multimesh: MultiMesh = (child as MultiMeshInstance3D).multimesh
		for i in multimesh.instance_count:
			var pos := multimesh.get_instance_transform(i).origin
			if _distance_to_segment(Vector2(pos.x, pos.z), flat_from, flat_to) < radius:
				count += 1
	return count


func _build() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_anchors.clear()
	_grid_sites.clear()
	for level_id in level_ids:
		var anchor := _anchor_for(level_id)
		_anchors.append(anchor)
		if str(anchor.get("clear_stage", "post")) == "grid":
			_grid_sites.append(anchor)
	var batches: Array[Array] = [[], [], [], []]
	for x in range(-16, 17):
		for z in range(-17, 11):
			if x % 5 == 0 or z % 5 == 0:
				continue
			if _grid_cleared(float(x), float(z)):
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
	# 后排入口的让位在生成完成后做：从批次里剔除方块，不消耗随机数，
	# 因此"某个后排入口在不在"只影响它自己那一小块，不会改动全城天际线。
	for site in _anchors:
		if str(site.get("clear_stage", "post")) != "post":
			continue
		var center: Vector3 = site["position"]
		var clear_radius := float(site["clear_radius"])
		for batch in batches:
			for j in range(batch.size() - 1, -1, -1):
				var pos: Vector3 = batch[j][0]
				if Vector2(pos.x - center.x, pos.z - center.z).length() < clear_radius:
					batch.remove_at(j)
	# 视廊：把"镜头 → 入口"这条连线两侧的方块剔掉。
	#
	# 只管 XYZ 的平面距离，不看方块高度 —— 宁可多剔一点，也不要出现
	# "某栋高楼恰好长在视线上"这种随种子漂移的遮挡（那类问题只在某个种子下复现，最难查）。
	for site in _anchors:
		var sightline := float(site.get("sightline", 0.0))
		if sightline <= 0.0:
			continue
		var target := Vector2(site["position"].x, site["position"].z)
		var eye := Vector2(APPROACH_CAMERA_LOCAL.x, APPROACH_CAMERA_LOCAL.z)
		for batch in batches:
			for j in range(batch.size() - 1, -1, -1):
				var pos: Vector3 = batch[j][0]
				var point := Vector2(pos.x, pos.z)
				if _distance_to_segment(point, eye, target) < sightline:
					batch.remove_at(j)
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
	for i in level_ids.size():
		var id := level_ids[i]
		var anchor: Dictionary = _anchors[i]
		_stage_delay = -1.0
		_hover.append(0.0)
		_punch.append(0.0)
		border_materials.append([])
		var site := Node3D.new()
		site.name = "Site_%s" % id
		site.position = anchor["position"]
		add_child(site)
		sites.append(site)
		# 测试关用洋红、正式远征关卡用青色。按 id 判，不按下标 —— 加关卡不会把别人的配色带走。
		var color := PINK if id == "99" else CYAN
		_box(site, Vector3(0, -1.5, 0), Vector3(3.1, 2.8, 3.1), color * 0.045, 0.4)
		for floor_index in 5:
			_octagon(site, -0.7 - floor_index * 0.4, 1.65, color * 0.45, 0.035)
		for y in [0.0, -0.24, -0.55]:
			_octagon(site, float(y), 1.85 + float(y) * 0.22, color, 0.055)
		var marker := Node3D.new()
		marker.position.y = 1.3
		marker.position.x = float(anchor["marker_x"])
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
		var entry: Dictionary = GameDesignConfig.expedition_level(id)
		labels.append(_label(marker, GameDesignConfig.expedition_level_display_name(id), Vector3(0, 0.22, 0.11), 65, 0.0065, Color.WHITE))
		_label(marker, GameDesignConfig.expedition_nav_badge(id), Vector3(0, 0.75, 0.11), 30, 0.0065, color)
		# 关卡已登记但场景还没建：入口保留在城里（让"这里有一关"可见），
		# 但牌面直接写清楚进不去 —— 不能等玩家点了才说，也不能假装能进。
		entry_hints.append(_label(marker, _entry_hint_text(id), Vector3(0, -0.48, 0.11), 30, 0.0065, color))
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
	_process(0.0)

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
		sites[i].position.y = float(_anchors[i]["position"].y) * rise
		markers[i].visible = entries_ready
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
		var anchor_scale := float(_anchors[i]["marker_scale"]) if i < _anchors.size() else 1.0
		markers[i].global_basis = camera.global_basis.scaled(Vector3.ONE * MARKER_SCALE * anchor_scale * maxf(0.001, site_reveal(i)) * emphasis)

func punch_marker(index: int) -> void:
	# 点击弹性反馈：脉冲置满后由 _process 逐帧衰减回落，形成放大再回弹的手感。
	if index >= 0 and index < _punch.size():
		_punch[index] = 1.0

func site_reveal(index: int) -> float:
	return entry_deployment if index >= 0 and index < sites.size() else 0.0


## 该关卡**现在能不能进**。判定真源只有一个：到达场景文件是否存在。
##
## 为什么不另设 `status` / `available` 配置字段：那等于给"能不能进"再造一份真源，
## 一旦配置写"可玩"而场景其实没建，入口就变成一点就穿帮的假按钮 —— 恰恰是最难查的一类。
## 用 `ResourceLoader.exists()` 则天然跟随工程实际状态：场景建好、导入后入口自动转为可进。
func entry_available(level_id: String) -> bool:
	return ResourceLoader.exists(GameDesignConfig.expedition_level_scene(level_id))


## 入口牌面文案。未开放的入口一进来就写明，不等玩家点了才说。
func _entry_hint_text(level_id: String) -> String:
	return "点击进入  ·  ENTER" if entry_available(level_id) else "尚未开放"

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
