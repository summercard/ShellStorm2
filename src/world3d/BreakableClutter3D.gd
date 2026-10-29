class_name BreakableClutter3D
extends Node3D
## Small scene props: bullets use layer 4, players only overlap an Area on layer 1.
## The settled fragments have no collision and no lifetime/reclaim timer.
##
## 碎片按**材质语义**分三类，不是同一套白块换色（业主 2026-10-29 指定「每个不同的东西碎块要不一样」）：
##   陶瓷（罐子 / 花瓶）→ 带鼓面的不规则陶片，颜色取本体陶色
##   木质（椅子 / 木箱）→ 长条木板，颜色取本体木色
##   纸张（书本堆）    → 薄书页，颜色取色盘最亮格；飞得更飘、落得更慢
##
## 业主同轮另三条要求也体现在这里：碎块更大、弧线更高、散得更开且**不许黏在一起**
## （落点做最小间隙松弛，见 `_separate_ends()`）。

signal broken(clutter: BreakableClutter3D, direction: Vector3)

const MAX_FRAGMENTS := 5
## 0.95s：抬升段要够长，弧顶才拉得到 1 米级；0.65s 时弧线会被压成贴地一跳。
const BREAK_DURATION_S := 0.95
const FEEDBACK_DURATION_S := 0.075
## 落点之间的最小间隙。碎块变大之后再挨在一起，看起来就像「根本没散开」。
const MIN_REMNANT_GAP_M := 0.30
const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"

enum ShardKind { CERAMIC, WOOD, PAPER }

## 色盘格心（UV）。由 10×10 公共色盘逐格实测采样得到，不是估的：
##   木色 (5,2)/(6,2)/(7,2)/(4,2) = #70340a/#71421b/#725434/#692805
##   罐陶 (6,3)/(8,4) = #715c09/#546f5e，瓶陶 (2,6)/(8,4) = #0e1a3e/#546f5e
##   书页取最亮格 (9,9)/(9,8)/(9,7) = #c5ced8/#a5b2c1/#8998aa，另加书脊灰 (8,7)
const WOOD_CELLS: Array[Vector2] = [
	Vector2(0.45, 0.75), Vector2(0.55, 0.75), Vector2(0.65, 0.75), Vector2(0.75, 0.75),
]
const PAPER_CELLS: Array[Vector2] = [
	Vector2(0.95, 0.05), Vector2(0.95, 0.15), Vector2(0.95, 0.25), Vector2(0.85, 0.25),
]
const JAR_CELLS: Array[Vector2] = [Vector2(0.65, 0.65), Vector2(0.85, 0.55)]
const VASE_CELLS: Array[Vector2] = [Vector2(0.25, 0.35), Vector2(0.85, 0.55)]
const FRAGMENT_COLORS := [
	Color("62b5b0"), Color("aa687c"), Color("cab48a"), Color("7f8ba7"), Color("75b8b5")
]

@export var asset_id := ""
@export var bounds_size := Vector3(0.5, 0.5, 0.5)
@export var clutter_kind := "generic"
@export var fragment_count := MAX_FRAGMENTS

var _visual: Node3D
var _hit_receiver: StaticBody3D
var _contact_area: Area3D
var _fragments: Array[MeshInstance3D] = []
var _broken := false
var _elapsed := 0.0
var _direction := Vector3.FORWARD
var _fragment_starts: Array[Vector3] = []
var _fragment_ends: Array[Vector3] = []
var _fragment_spin: Array[Vector3] = []
var _fragment_flight: Array[float] = []
var _fragment_arc: Array[float] = []
var _shard_material: Material
var _materials: Array[StandardMaterial3D] = []
var _palette: Texture2D


func _ready() -> void:
	_visual = get_node_or_null("Visual") as Node3D
	_hit_receiver = get_node_or_null("HitReceiver") as StaticBody3D
	_contact_area = get_node_or_null("PlayerContact") as Area3D
	if _hit_receiver != null:
		_hit_receiver.set_meta("breakable_owner", self)
	if _contact_area != null:
		_contact_area.body_entered.connect(_on_player_entered)
	add_to_group("breakable_clutter_3d")


func take_damage(
	_damage: int,
	_critical: bool = false,
	direction: Vector3 = Vector3.ZERO,
	_knockback: float = 0.0
) -> void:
	shatter(direction)


func _on_player_entered(body: Node3D) -> void:
	if _broken or body == null or not body is CharacterBody3D:
		return
	var direction := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if direction.length_squared() < 0.04:
		direction = global_position - body.global_position
	shatter(direction)


func shatter(direction: Vector3) -> bool:
	if _broken:
		return false
	_broken = true
	_direction = _planar_direction(direction)
	if _hit_receiver != null:
		_hit_receiver.set_deferred("collision_layer", 0)
		_hit_receiver.set_deferred("collision_mask", 0)
	if _contact_area != null:
		_contact_area.set_deferred("monitoring", false)
		_contact_area.set_deferred("monitorable", false)
	_create_fragments()
	_elapsed = 0.0
	broken.emit(self, _direction)
	return true


func restore_broken(direction: Vector3 = Vector3.FORWARD) -> void:
	if _broken:
		return
	_direction = _planar_direction(direction)
	_broken = true
	if _hit_receiver != null:
		_hit_receiver.collision_layer = 0
		_hit_receiver.collision_mask = 0
	if _contact_area != null:
		_contact_area.monitoring = false
		_contact_area.monitorable = false
	if _visual != null:
		_visual.visible = false
	_create_fragments()
	for index in range(_fragments.size()):
		_fragments[index].position = _fragment_ends[index]
		_fragments[index].rotation = _rest_rotation(index)
	_elapsed = BREAK_DURATION_S


func is_broken() -> bool:
	return _broken


func is_settled() -> bool:
	return _broken and _elapsed >= BREAK_DURATION_S


func fragment_total() -> int:
	return _fragments.size()


func break_direction() -> Vector3:
	return _direction


func fragment_positions() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for fragment in _fragments:
		result.append(fragment.position)
	return result


func _planar_direction(direction: Vector3) -> Vector3:
	var planar := Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() < 0.0001:
		planar = Vector3.FORWARD
	return planar.normalized()


func _rest_rotation(index: int) -> Vector3:
	# 落定后只保留绕竖轴的朝向：木板/陶片躺平，书页平摊。
	return Vector3(0.0, _fragment_spin[index].y, 0.0)


func _max_dim() -> float:
	return maxf(bounds_size.x, maxf(bounds_size.y, bounds_size.z))


func _shard_kind() -> int:
	match clutter_kind:
		"jar", "vase":
			return ShardKind.CERAMIC
		"book_stack":
			return ShardKind.PAPER
		_:
			return ShardKind.WOOD


func _shard_cells() -> Array[Vector2]:
	match clutter_kind:
		"jar":
			return JAR_CELLS
		"vase":
			return VASE_CELLS
		"book_stack":
			return PAPER_CELLS
		_:
			return WOOD_CELLS


func _physics_process(delta: float) -> void:
	if not _broken or _elapsed >= BREAK_DURATION_S:
		return
	_elapsed = minf(_elapsed + delta, BREAK_DURATION_S)
	if _visual != null and _visual.visible:
		var pulse := clampf(_elapsed / FEEDBACK_DURATION_S, 0.0, 1.0)
		_visual.scale = Vector3.ONE * (1.0 + sin(pulse * PI) * 0.09)
		_visual.rotation.z = sin(pulse * PI) * 0.055
		if pulse >= 1.0:
			_visual.visible = false
	for index in range(_fragments.size()):
		var fragment := _fragments[index]
		var start := _fragment_starts[index]
		var target := _fragment_ends[index]
		var flight_time: float = _fragment_flight[index]
		var flight := clampf(_elapsed / flight_time, 0.0, 1.0)
		var settle := 0.0
		if _elapsed > flight_time:
			settle = clampf(
				(_elapsed - flight_time) / maxf(0.0001, BREAK_DURATION_S - flight_time), 0.0, 1.0
			)
		# 抛物线：水平按减速插值，垂直叠加一条正弦弧，弧高逐块不同 ⇒ 不会齐平飞。
		var eased := 1.0 - pow(1.0 - flight, 2.0)
		var travel := start.lerp(target, eased)
		travel.y = lerpf(start.y, target.y, eased) + sin(flight * PI) * _fragment_arc[index]
		var smooth := settle * settle * (3.0 - 2.0 * settle)
		fragment.position = travel.lerp(target, smooth)
		var tumble := (1.0 - smooth) * flight
		fragment.rotation = Vector3(
			_fragment_spin[index].x * tumble,
			_fragment_spin[index].y * flight,
			_fragment_spin[index].z * tumble
		)
		# 落地再来一次小弹跳，显得「有重量」而不是滑到位。
		if settle > 0.0:
			fragment.position.y += sin(settle * PI) * 0.055 * (1.0 - settle)


func _create_fragments() -> void:
	if not _fragments.is_empty():
		return
	var root := Node3D.new()
	root.name = "GroundRemnants"
	add_child(root)
	_shard_material = _body_palette_material()
	var maxd := _max_dim()
	var planar_span := maxf(bounds_size.x, bounds_size.z)
	var thin_span := minf(bounds_size.x, bounds_size.z)
	var kind := _shard_kind()
	var lateral := _direction.cross(Vector3.UP).normalized()
	# 力度：弧顶 ~1 米级，前抛 ~1.2~1.7 米，横向 ±0.5~0.8 米。
	# 纸张最飘（弧略低、飞得更久），木质/陶质更「砸」得出去。
	var is_paper := kind == ShardKind.PAPER
	var arc_base := (0.42 if is_paper else 0.60) + maxd * (0.34 if is_paper else 0.52)
	var forward_base := 0.55 + planar_span * (0.62 if is_paper else 0.88)
	var lateral_base := 0.28 + thin_span * (0.62 if is_paper else 0.55)
	var actual_count := clampi(fragment_count, 1, MAX_FRAGMENTS)
	for index in range(actual_count):
		var t := float(index) / float(maxi(1, actual_count - 1))
		var angle := _jitter(index, 1) * TAU
		var start := Vector3(
			lerpf(-bounds_size.x, bounds_size.x, _jitter(index, 2)) * 0.30,
			bounds_size.y * lerpf(0.30, 0.70, _jitter(index, 3)),
			lerpf(-bounds_size.z, bounds_size.z, _jitter(index, 4)) * 0.30
		)
		var fragment := MeshInstance3D.new()
		fragment.name = "Fragment_%02d" % (index + 1)
		fragment.mesh = _build_shard(index, kind)
		fragment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# 落地高度按网格最低顶点算，凸块才不会一半埋进地板。
		var lowest := (fragment.mesh as ArrayMesh).get_aabb().position.y
		var ring := lerpf(0.55, 1.0, _jitter(index, 5))
		var end := (
			_direction * forward_base * ring
			+ lateral * lateral_base * lerpf(-1.0, 1.0, t)
			+ Vector3(cos(angle), 0.0, sin(angle)) * planar_span * 0.10
		)
		end.y = -lowest + 0.004
		root.add_child(fragment)
		fragment.position = start
		_fragments.append(fragment)
		_fragment_starts.append(start)
		_fragment_ends.append(end)
		_fragment_spin.append(Vector3(
			lerpf(-3.2, 3.2, _jitter(index, 21)),
			float(index) * 1.13 + angle,
			lerpf(-3.2, 3.2, _jitter(index, 22))
		))
		_fragment_flight.append(
			clampf(0.58 if is_paper else 0.50, 0.2, BREAK_DURATION_S - 0.15)
		)
		_fragment_arc.append(arc_base * lerpf(0.72, 1.15, _jitter(index, 23)))
	_separate_ends()


## 落点松弛：任意两块的水平间距不小于 `MIN_REMNANT_GAP_M`。
## 不做这一步时，五块经常落成一撮，肉眼看起来就是「没散开」。
func _separate_ends() -> void:
	var gap := MIN_REMNANT_GAP_M
	for _pass in range(6):
		var moved := false
		for first in range(_fragment_ends.size()):
			for second in range(first + 1, _fragment_ends.size()):
				var a := _fragment_ends[first]
				var b := _fragment_ends[second]
				var offset := Vector2(a.x - b.x, a.z - b.z)
				var distance := offset.length()
				if distance >= gap:
					continue
				if distance < 0.0001:
					# 完全重合时按角度硬分开，否则归一化会得到 NaN。
					offset = Vector2(cos(float(first) * 1.7), sin(float(first) * 1.7))
					distance = 1.0
				var push := (gap - distance) * 0.5
				var normal := offset / distance
				_fragment_ends[first] = Vector3(a.x + normal.x * push, a.y, a.z + normal.y * push)
				_fragment_ends[second] = Vector3(b.x - normal.x * push, b.y, b.z - normal.y * push)
				moved = true
		if not moved:
			break


func _jitter(index: int, salt: int) -> float:
	# 确定性伪随机：同一物件重建后碎片分布稳定，不用 RandomNumberGenerator 以免污染玩法种子。
	var value := sin(
		float(index) * 12.9898 + float(salt) * 78.233
		+ bounds_size.x * 37.719 + bounds_size.y * 11.17
	) * 43758.5453
	return value - floorf(value)


func _body_palette_material() -> Material:
	# 碎片沿用本体材质（主体与色盘共用一份），只把 UV 放到指定格心 ⇒ 配色与本体一致。
	var surfaces := _collect_palette_surfaces()
	if surfaces.is_empty():
		return null
	return (surfaces[0] as Dictionary)["material"] as Material


func _collect_palette_surfaces() -> Array:
	var result: Array = []
	if _visual == null:
		return result
	var stack: Array[Node] = [_visual]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh := (node as MeshInstance3D).mesh
			for surface in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface)
				if material == null:
					continue
				var arrays := mesh.surface_get_arrays(surface)
				var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
				if uvs != null and not (uvs as PackedVector2Array).is_empty():
					result.append({
						"material": material,
						"uv": (uvs as PackedVector2Array)[0],
					})
		stack.append_array(node.get_children())
	return result


func _build_shard(index: int, kind: int) -> ArrayMesh:
	var cells := _shard_cells()
	var cell: Vector2 = cells[index % cells.size()]
	match kind:
		ShardKind.CERAMIC:
			return _ceramic_shard(index, cell)
		ShardKind.PAPER:
			return _paper_sheet(index, cell)
		_:
			return _wood_plank(index, cell)


## 陶片：不规则五边形，正反面各有一个鼓起的中心点 ⇒ 像崩下来的弧面瓦片。
func _ceramic_shard(index: int, cell: Vector2) -> ArrayMesh:
	var maxd := _max_dim()
	var radius := clampf(maxd * lerpf(0.13, 0.18, _jitter(index, 31)), 0.085, 0.20)
	var half_t := clampf(radius * lerpf(0.11, 0.17, _jitter(index, 32)), 0.012, 0.028)
	var bow := radius * lerpf(0.18, 0.34, _jitter(index, 33))
	var sides := 5
	var vertices := PackedVector3Array()
	for layer in range(2):
		var sign_y := -1.0 if layer == 0 else 1.0
		for i in range(sides):
			var a := TAU * float(i) / float(sides) + _jitter(index, 40 + i) * 0.55
			var r := radius * lerpf(0.72, 1.12, _jitter(index, 50 + i))
			vertices.append(Vector3(cos(a) * r, sign_y * half_t, sin(a) * r))
	# 两个中心点：沿 ±Y 各鼓出 bow，让平面片有弧度。
	vertices.append(Vector3(0.0, half_t + bow, 0.0))
	vertices.append(Vector3(0.0, -half_t - bow, 0.0))
	var top_center := sides * 2
	var bottom_center := sides * 2 + 1
	var indices := PackedInt32Array()
	for i in range(sides):
		var j := (i + 1) % sides
		# 侧面
		indices.append_array([i, j, sides + j, i, sides + j, sides + i])
		# 上面（+Y）
		indices.append_array([top_center, sides + i, sides + j])
		# 下面（−Y）
		indices.append_array([bottom_center, j, i])
	return _make_shard_mesh(vertices, indices, cell, 0.016)


## 木板：一端收窄的长条，带真实厚度 ⇒ 落地是「啪」一下躺平，不是纸片滑走。
func _wood_plank(index: int, cell: Vector2) -> ArrayMesh:
	var maxd := _max_dim()
	var length := clampf(maxd * lerpf(0.30, 0.42, _jitter(index, 11)), 0.24, 0.54)
	var width := clampf(maxd * lerpf(0.10, 0.15, _jitter(index, 12)), 0.07, 0.17)
	var thick := clampf(maxd * lerpf(0.045, 0.070, _jitter(index, 13)), 0.028, 0.062)
	var hx := length * 0.5
	var hy := thick * 0.5
	var hz := width * 0.5
	var taper := lerpf(0.68, 1.0, _jitter(index, 14))
	var vertices := PackedVector3Array([
		Vector3(-hx, -hy, -hz * taper), Vector3(-hx, -hy, hz * taper),
		Vector3(-hx, hy, -hz * taper), Vector3(-hx, hy, hz * taper),
		Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz),
		Vector3(hx, hy, -hz), Vector3(hx, hy, hz),
	])
	var indices := PackedInt32Array([
		0, 1, 3, 0, 3, 2, 4, 6, 7, 4, 7, 5,
		0, 4, 5, 0, 5, 1, 2, 3, 7, 2, 7, 6,
		0, 2, 6, 0, 6, 4, 1, 5, 7, 1, 7, 3,
	])
	return _make_shard_mesh(vertices, indices, cell, 0.020)


## 书页：薄片但仍有实体厚度（能投影），两端微微上翘 ⇒ 看着像被撕下来的纸。
func _paper_sheet(index: int, cell: Vector2) -> ArrayMesh:
	var maxd := _max_dim()
	var half_w := clampf(maxd * lerpf(0.075, 0.105, _jitter(index, 51)), 0.055, 0.13)
	var half_l := clampf(maxd * lerpf(0.10, 0.14, _jitter(index, 52)), 0.075, 0.17)
	var half_t := 0.004
	var curl := half_l * lerpf(0.25, 0.55, _jitter(index, 53))
	var vertices := PackedVector3Array()
	for layer in range(2):
		var sign_y := -1.0 if layer == 0 else 1.0
		for corner in range(4):
			var sx := -1.0 if corner in [0, 2] else 1.0
			var sz := -1.0 if corner in [0, 1] else 1.0
			# 沿 X 的单折：一端抬起、一端压低（±curl/2），网格因此有负向顶点，
			# 「最低点贴地」才算得对。四角同时抬高等于是整体平移，纸就浮在半空。
			var bend := curl * sx * 0.5
			vertices.append(Vector3(sx * half_w, sign_y * half_t + bend, sz * half_l))
	var indices := PackedInt32Array([
		0, 1, 3, 0, 3, 2, 4, 6, 7, 4, 7, 5,
		0, 4, 5, 0, 5, 1, 2, 3, 7, 2, 7, 6,
		0, 2, 6, 0, 6, 4, 1, 5, 7, 1, 7, 3,
	])
	return _make_shard_mesh(vertices, indices, cell, 0.014)


func _make_shard_mesh(
	vertices: PackedVector3Array, indices: PackedInt32Array, cell: Vector2, uv_scale: float
) -> ArrayMesh:
	var uv := PackedVector2Array()
	for vertex in vertices:
		uv.append(cell + Vector2(vertex.x, vertex.z) * uv_scale)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _shard_material != null:
		mesh.surface_set_material(0, _shard_material)
	else:
		mesh.surface_set_material(0, _fallback_material(0))
	return mesh


func _fallback_material(index: int) -> StandardMaterial3D:
	if _materials.is_empty():
		_palette = load(PALETTE_PATH) as Texture2D
	for color_index in range(FRAGMENT_COLORS.size()):
		var material := StandardMaterial3D.new()
		material.albedo_color = FRAGMENT_COLORS[color_index]
		material.roughness = 0.75
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		material.albedo_texture = _palette
		_materials.append(material)
	return _materials[index % _materials.size()]
