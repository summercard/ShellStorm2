extends RefCounted

const DRAW_SHADER := preload("unity_vfx_draw.gdshader")
const EPSILON := 0.000001
const LOCAL := 0
const VIEW := 1
const FACING := 2
const STRETCH := 3

static var _shader_variants: Dictionary = {}

var _anchor: Node3D
var _particle_node: MultiMeshInstance3D
var _ribbon_node: MeshInstance3D
var _multimesh: MultiMesh
var _mesh_bounds: AABB
var _mesh_radius: float
var _trail_material: ShaderMaterial
var _enabled := true
var _capacity := 0
var _geometry := LOCAL
var _length_scale := 1.0
var _velocity_scale := 0.0
var _screen_limits := Vector2(0.0, 1.0)
var _trail_segments := 0
var _sorting_offset := 0.0

func setup(anchor: Node3D, config: Dictionary, mesh: Mesh, texture: Texture2D, trail_texture: Texture2D) -> void:
	clear()
	_detach(_particle_node)
	_detach(_ribbon_node)
	_ribbon_node = null
	_anchor = anchor
	var main: Dictionary = config.get("main", {})
	var renderer: Dictionary = config.get("renderer", {})
	var sheet: Dictionary = config.get("sheet", {})
	var mode: String = renderer.get("render_mode", "Mesh")
	var alignment: String = renderer.get("alignment", "View")
	_enabled = bool(renderer.get("enabled", true)) and mode != "None"
	_capacity = maxi(0, int(main.get("max_particles", 1)))
	_geometry = STRETCH if mode == "Stretch" else {"View": VIEW, "Facing": FACING}.get(alignment, LOCAL)
	_length_scale = float(renderer.get("length_scale", 1.0))
	_velocity_scale = float(renderer.get("velocity_scale", 0.0))
	_screen_limits.x = maxf(0.0, float(renderer.get("min_size", 0.0)))
	_screen_limits.y = maxf(_screen_limits.x, float(renderer.get("max_size", 1.0)))

	var draw_mesh: Mesh = mesh if mode == "Mesh" and mesh != null else QuadMesh.new()
	_mesh_bounds = draw_mesh.get_aabb()
	_mesh_radius = (_mesh_bounds.get_center().abs() + _mesh_bounds.size * 0.5).length()
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	_multimesh.use_custom_data = true
	_multimesh.mesh = draw_mesh
	_multimesh.instance_count = _capacity
	_multimesh.visible_instance_count = 0

	var materials: Array = renderer.get("materials", [])
	var settings: Dictionary = materials[0] if not materials.is_empty() else {}
	var material := _make_material(settings, texture)
	material.render_priority = int(renderer.get("sorting_order", 0))
	_sorting_offset = -float(renderer.get("sorting_fudge", 0.0))
	material.set_shader_parameter("geometry_mode", _geometry)
	material.set_shader_parameter("clamp_billboard_size", mode == "Billboard" or mode == "Stretch")
	material.set_shader_parameter("screen_limits", _screen_limits)
	if bool(sheet.get("enabled", false)):
		var tiles: Array = sheet.get("tiles", [1, 1])
		material.set_shader_parameter("sheet_tiles", Vector2(maxi(1, int(tiles[0])), maxi(1, int(tiles[1]))))

	_particle_node = MultiMeshInstance3D.new()
	_particle_node.name = "UnityVfxDrawParticles"
	_particle_node.multimesh = _multimesh
	_particle_node.material_override = material
	_particle_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_particle_node.sorting_offset = _sorting_offset
	_particle_node.visible = false
	_anchor.add_child(_particle_node)

	var trail_settings: Dictionary = renderer.get("trail_material", {})
	_trail_material = _make_material(trail_settings, trail_texture, true)
	_trail_material.render_priority = material.render_priority

func sync(particles: Array, _now: float) -> void:
	if not is_instance_valid(_particle_node):
		return
	if not _enabled:
		clear()
		return
	var count := mini(particles.size(), _capacity)
	var previous := _multimesh.visible_instance_count
	var bounds := AABB()
	var anchor_basis := _anchor.global_basis if _anchor.is_inside_tree() else _anchor.transform.basis
	var stretch := _geometry == STRETCH
	var determinant := anchor_basis.determinant()
	var invertible := determinant != 0.0 if stretch else not is_zero_approx(determinant)
	var anchor_inverse := Basis.IDENTITY
	# 顶点着色器会在世界空间重定向；用逆基底的行长度将保守球包围盒转回锚点空间。
	var to_local_extent := Vector3.ONE
	if _geometry != LOCAL and invertible:
		anchor_inverse = anchor_basis.inverse()
		var inverse_transposed := anchor_inverse.transposed()
		to_local_extent = Vector3(inverse_transposed.x.length(), inverse_transposed.y.length(), inverse_transposed.z.length())
	var camera := _active_camera() if _screen_limits.x > 0.0 else null
	var stretch_scale := Vector2(anchor_basis.x.length(), anchor_basis.y.length()) if stretch else Vector2.ONE
	for i in range(count):
		var particle: Dictionary = particles[i]
		var position: Vector3 = particle["position"]
		var size: Vector3 = particle["size"]
		var angle: Vector3 = particle["angle"]
		var basis := Basis.from_scale(size)
		var stretch_basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
		if _geometry == LOCAL:
			basis = Basis.from_euler(angle) * basis
		elif stretch:
			var velocity: Vector3 = particle["velocity"]
			if invertible:
				stretch_basis = _stretch_world_basis(anchor_basis * velocity, Vector2(size.x, size.y) * stretch_scale)
			basis = anchor_inverse * stretch_basis
		var transform := Transform3D(basis, position)
		_multimesh.set_instance_transform(i, transform)
		_multimesh.set_instance_color(i, particle["color"])
		# R 是未折返的帧号；GBA 仍是已转换的 Euler 角。
		_multimesh.set_instance_custom_data(i, Color(float(particle["frame"]), angle.x, angle.y, angle.z))
		var item_bounds := transform * _mesh_bounds
		if _geometry != LOCAL:
			var radius: float
			if stretch:
				radius = Vector2(stretch_basis.x.length(), stretch_basis.y.length() * 0.5).length()
			else:
				var world_basis := anchor_basis * basis
				var max_axis := maxf(world_basis.x.length(), maxf(world_basis.y.length(), world_basis.z.length()))
				radius = _mesh_radius * max_axis
			if camera != null:
				var depth := absf((camera.global_transform.affine_inverse() * (_anchor.global_transform * position)).z)
				var half_height := depth / maxf(absf(camera.get_camera_projection().y.y), EPSILON)
				if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
					half_height = 1.0 / maxf(absf(camera.get_camera_projection().y.y), EPSILON)
				if stretch:
					var diameter := stretch_basis.z.length()
					if diameter > EPSILON:
						var fraction := diameter * 0.5 / maxf(half_height, EPSILON)
						radius *= maxf(1.0, _screen_limits.x / maxf(fraction, EPSILON))
				else:
					radius = maxf(radius, half_height * _screen_limits.x * 4.0)
			var extent := to_local_extent * radius
			item_bounds = AABB(position - extent, extent * 2.0)
		bounds = item_bounds if i == 0 else bounds.merge(item_bounds)
	for i in range(count, previous):
		_reset_slot(i)
	_multimesh.custom_aabb = bounds.grow(EPSILON) if count > 0 else AABB()
	_multimesh.visible_instance_count = count
	_particle_node.visible = count > 0
	_update_ribbon(particles, count)

func clear() -> void:
	if _multimesh != null:
		for i in range(_multimesh.visible_instance_count):
			_reset_slot(i)
		_multimesh.visible_instance_count = 0
		_multimesh.custom_aabb = AABB()
	if is_instance_valid(_particle_node):
		_particle_node.hide()
	_hide_ribbon()

func debug_state() -> Dictionary:
	var count := _multimesh.visible_instance_count if is_instance_valid(_particle_node) else 0
	var frame_slots: Array[int] = []
	for i in range(count):
		frame_slots.append(roundi(_multimesh.get_instance_custom_data(i).r))
	return {"visible_count": count, "trail_segments": _trail_segments if is_instance_valid(_ribbon_node) else 0, "frame_slots": frame_slots}

func _stretch_world_basis(velocity: Vector3, size: Vector2) -> Basis:
	var speed := velocity.length()
	var signed_length := size.y * _length_scale + speed * _velocity_scale
	if speed == 0.0 or signed_length == 0.0:
		return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var direction := velocity / speed * signf(signed_length)
	var reference := Vector3.UP if absf(direction.y) < 0.99 else Vector3.BACK
	var side := reference.cross(direction).normalized()
	# 矩阵以全精度保留有符号纵轴、宽度和钳制用原始直径，不依赖半精度实例自定义数据。
	return Basis(direction * absf(signed_length), side * size.x, direction.cross(side) * maxf(absf(size.x), absf(size.y)))

static func _make_material(settings: Dictionary, texture: Texture2D, is_trail := false) -> ShaderMaterial:
	var blend := "blend_add" if int(settings.get("_DstBlend", 10)) == 1 else "blend_mix"
	var cull := "cull_back"
	match int(settings.get("_Cull", 0 if is_trail else 2)):
		0: cull = "cull_disabled"
		1: cull = "cull_front"
	var depth := "depth_draw_always" if float(settings.get("_ZWrite", 0.0)) > 0.5 else "depth_draw_never"
	var soft := float(settings.get("_SoftParticlesEnabled", 0.0)) > 0.5
	var wrap: String = settings.get("texture_wrap", "Repeat")
	var key := "%s/%s/%s/%s/%s" % [blend, cull, depth, soft, wrap]
	if not _shader_variants.has(key):
		var shader := Shader.new()
		var modes := "%s, %s, %s" % [blend, cull, depth]
		var code := DRAW_SHADER.code.replace("blend_mix, cull_back, depth_draw_never", modes).replace("#define VFX_SOFT 0", "#define VFX_SOFT 1" if soft else "#define VFX_SOFT 0")
		if wrap != "Repeat": code = code.replace("filter_linear, repeat_enable", "filter_linear, repeat_disable")
		if wrap == "Mirror": code = code.replace("#define VFX_MIRROR 0", "#define VFX_MIRROR 1")
		shader.code = code
		_shader_variants[key] = shader
	var material := ShaderMaterial.new()
	material.shader = _shader_variants[key]
	material.set_shader_parameter("use_texture", texture != null)
	if texture != null:
		material.set_shader_parameter("main_texture", texture)
	var tint: Array = settings.get("_Color", [1.0, 1.0, 1.0, 1.0])
	material.set_shader_parameter("tint", Color(float(tint[0]), float(tint[1]), float(tint[2]), float(tint[3])))
	var uv_scale: Array = settings.get("texture_scale", [1.0, 1.0])
	var uv_offset: Array = settings.get("texture_offset", [0.0, 0.0])
	material.set_shader_parameter("texture_scale", Vector2(float(uv_scale[0]), float(uv_scale[1])))
	# Godot 的纹理 V 原点在上方；将 Unity 的 scale/offset 换到该约定。
	material.set_shader_parameter("texture_offset", Vector2(float(uv_offset[0]), 1.0 - float(uv_scale[1]) - float(uv_offset[1])))
	if soft:
		var near_distance := float(settings.get("_SoftParticlesNearFadeDistance", 0.0))
		var far_distance := float(settings.get("_SoftParticlesFarFadeDistance", 0.2))
		material.set_shader_parameter("soft_distances", Vector2(near_distance, far_distance))
	return material

func _update_ribbon(particles: Array, count: int) -> void:
	_trail_segments = 0
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var camera := _active_camera()
	var camera_origin := Vector3.BACK
	var view := Vector3.BACK
	var perspective := false
	if camera != null and not is_zero_approx(_anchor.global_basis.determinant()):
		var local_from_world := _anchor.global_transform.affine_inverse()
		camera_origin = local_from_world * camera.global_position
		view = local_from_world.basis * camera.global_basis.z
		perspective = camera.projection != Camera3D.PROJECTION_ORTHOGONAL
	for i in range(count):
		var points: Array = particles[i].get("trail", [])
		if points.size() < 2:
			continue
		var path := PackedVector3Array()
		var widths := PackedFloat32Array()
		var point_colors := PackedColorArray()
		var lengths := PackedFloat32Array()
		var total := 0.0
		for point in points:
			var p: Vector3 = point["position"]
			if not path.is_empty():
				var step := p.distance_to(path[-1])
				if step <= EPSILON:
					widths[-1] = maxf(0.0, float(point["width"])) * 0.5
					point_colors[-1] = point["color"]
					continue
				total += step
			path.append(p)
			widths.append(maxf(0.0, float(point["width"])) * 0.5)
			point_colors.append(point["color"])
			lengths.append(total)
		if path.size() < 2:
			continue
		var previous_side := Vector3.ZERO
		var base := vertices.size()
		for j in range(path.size()):
			var incoming := (path[j] - path[j - 1]).normalized() if j > 0 else Vector3.ZERO
			var outgoing := (path[j + 1] - path[j]).normalized() if j + 1 < path.size() else Vector3.ZERO
			var tangent := (incoming + outgoing).normalized()
			if tangent.length_squared() < EPSILON:
				tangent = outgoing
			var toward_camera := camera_origin - path[j] if perspective else view
			var side := tangent.cross(toward_camera).normalized()
			if side.length_squared() < EPSILON:
				side = tangent.cross(Vector3.UP if absf(tangent.y) < 0.99 else Vector3.RIGHT).normalized()
			if side.dot(previous_side) < 0.0:
				side = -side
			previous_side = side
			vertices.append(path[j] + side * widths[j])
			vertices.append(path[j] - side * widths[j])
			colors.append(point_colors[j])
			colors.append(point_colors[j])
			var u := lengths[j] / total
			uvs.append(Vector2(u, 1.0))
			uvs.append(Vector2(u, 0.0))
			if j > 0 and (widths[j - 1] > 0.0 or widths[j] > 0.0):
				var k := base + (j - 1) * 2
				# Godot 正面为顺时针；在连续拐角处共享同一对顶点。
				indices.append_array(PackedInt32Array([k, k + 1, k + 2, k + 1, k + 3, k + 2]))
				_trail_segments += 1
	if indices.is_empty():
		_hide_ribbon()
		return
	if not is_instance_valid(_ribbon_node):
		_ribbon_node = MeshInstance3D.new()
		_ribbon_node.name = "UnityVfxDrawRibbon"
		_ribbon_node.material_override = _trail_material
		_ribbon_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ribbon_node.sorting_offset = _sorting_offset
		_anchor.add_child(_ribbon_node)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var ribbon := ArrayMesh.new()
	ribbon.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_ribbon_node.mesh = ribbon
	_ribbon_node.show()

func _active_camera() -> Camera3D:
	return _anchor.get_viewport().get_camera_3d() if _anchor.is_inside_tree() else null

func _hide_ribbon() -> void:
	_trail_segments = 0
	if is_instance_valid(_ribbon_node):
		_ribbon_node.hide()
		_ribbon_node.mesh = null

func _reset_slot(index: int) -> void:
	_multimesh.set_instance_transform(index, Transform3D.IDENTITY)
	_multimesh.set_instance_color(index, Color(0.0, 0.0, 0.0, 0.0))
	_multimesh.set_instance_custom_data(index, Color(0.0, 0.0, 0.0, 0.0))

static func _detach(node: Node3D) -> void:
	if is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()
