extends RefCounted

const DRAW_SHADER := preload("library_draw.gdshader")
const Powerbox := preload("library_powerbox.gd")
const EPSILON := 0.000001
const LOCAL := 0
const VIEW := 1
const FACING := 2
const STRETCH := 3
const HORIZONTAL := 4
const VERTICAL := 5
const VELOCITY := 6
const WORLD := 7

static var _shader_variants: Dictionary = {}

var _anchor: Node3D
var _ribbon_node: MeshInstance3D
var _trail_material: ShaderMaterial
var _enabled := true
var _trail_only_enabled := false
var _capacity := 0
var _geometry := LOCAL
var _is_mesh := false
var _shadow_mode := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
var _receive_shadows := true
var _compatibility := false
var _length_scale := 1.0
var _velocity_scale := 0.0
var _screen_limits := Vector2(0.0, 1.0)
var _trail_segments := 0
var _sorting_offset := 0.0
var _sort_mode := "None"
var _pivot := Vector3.ZERO
var _flip := Vector3.ZERO
var _weights := PackedFloat32Array()
var _weighted := false
var _draw_meshes: Array[Mesh] = []
var _materials: Array[ShaderMaterial] = []
var _surface_meshes: Dictionary = {}
var _batches: Array[Dictionary] = []
var _direct: Array[Dictionary] = []
var _last_slots: Array[Dictionary] = []
var _material_diagnostics: Array[Dictionary] = []
var _limitations: Array[String] = []
var _last_input := 0

func setup(anchor: Node3D, config: Dictionary, mesh: Mesh, texture: Texture2D, trail_texture: Texture2D) -> void:
	var meshes: Array[Mesh] = []
	if mesh != null:
		meshes.append(mesh)
	setup_library(anchor, config, meshes, texture, trail_texture)

func setup_library(anchor: Node3D, config: Dictionary, meshes: Array[Mesh], texture: Texture2D, trail_texture: Texture2D, material_textures: Array = []) -> void:
	_dispose_nodes()
	_anchor = anchor
	var main: Dictionary = config.get("main", {})
	var renderer: Dictionary = config.get("renderer", {})
	var sheet: Dictionary = config.get("sheet", config.get("texture_sheet_animation", {}))
	var mode := str(renderer.get("render_mode", "Mesh"))
	var alignment := str(renderer.get("alignment", "View"))
	var renderer_on := bool(renderer.get("enabled", true)) and not bool(renderer.get("force_rendering_off", false))
	_enabled = renderer_on and mode != "None"
	# Unity's None mode suppresses particle bodies, not the separate Trails mesh.
	_trail_only_enabled = renderer_on and mode == "None" and bool(config.get("trails", {}).get("enabled", false))
	_capacity = maxi(0, int(main.get("max_particles", 1)))
	_is_mesh = mode == "Mesh"
	_shadow_mode = {"On": GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "TwoSided": GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED, "ShadowsOnly": GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY}.get(str(renderer.get("shadow_casting_mode", "Off")), GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	_receive_shadows = bool(renderer.get("receive_shadows", true))
	_compatibility = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	_geometry = {"Stretch": STRETCH, "HorizontalBillboard": HORIZONTAL, "VerticalBillboard": VERTICAL}.get(mode, {"Local": LOCAL, "World": WORLD, "View": VIEW, "Facing": FACING, "Velocity": VELOCITY}.get(alignment, VIEW))
	_length_scale = float(renderer.get("length_scale", 1.0))
	_velocity_scale = float(renderer.get("velocity_scale", 0.0))
	_screen_limits.x = maxf(0.0, float(renderer.get("min_size", renderer.get("min_particle_size", 0.0))))
	_screen_limits.y = maxf(_screen_limits.x, float(renderer.get("max_size", renderer.get("max_particle_size", 1.0))))
	_sorting_offset = -float(renderer.get("sorting_fudge", 0.0))
	_sort_mode = str(renderer.get("sort_mode", "None"))
	_pivot = _vec3(renderer.get("pivot_godot", renderer.get("pivot", [])), Vector3.ZERO)
	if not renderer.has("pivot_godot"):
		_pivot.z = -_pivot.z
	_flip = _vec3(renderer.get("flip", []), Vector3.ZERO).clamp(Vector3.ZERO, Vector3.ONE)
	_weighted = str(renderer.get("mesh_distribution", "UniformRandom")) == "NonUniformRandom"
	_weights.clear()
	_draw_meshes.clear()
	_materials.clear()
	_surface_meshes.clear()
	_material_diagnostics.clear()
	_limitations.clear()
	if _is_mesh and not meshes.is_empty():
		_draw_meshes.assign(meshes)
		var slots: Array = renderer.get("mesh_slots", [])
		_weights.resize(meshes.size())
		_weights.fill(1.0)
		for i in range(slots.size()):
			if slots[i] is Dictionary:
				var slot := int(slots[i].get("slot", i))
				if slot >= 0 and slot < _weights.size():
					_weights[slot] = maxf(0.0, float(slots[i].get("weight", 1.0)))
	else:
		if _is_mesh:
			_limitations.append("mesh_missing_quad_fallback")
		_draw_meshes.append(QuadMesh.new())
	if _geometry == STRETCH:
		_limitations.append("stretch_perspective_and_screen_clamp_approximate")
		if float(renderer.get("camera_velocity_scale", 0.0)) != 0.0 or bool(renderer.get("freeform_stretching", false)) or not bool(renderer.get("rotate_with_stretch_direction", true)):
			_limitations.append("stretch_nondefault_camera_velocity_or_rotation_unsupported")
	if not bool(renderer.get("allow_roll", true)):
		_limitations.append("camera_roll_lock_unsupported")
	if float(renderer.get("normal_direction", 1.0)) != 1.0:
		_limitations.append("billboard_lighting_normal_unsupported")
	var streams: Array = renderer.get("vertex_streams", [])
	for stream in streams:
		if str(stream) not in ["Position", "Normal", "Tangent", "Color", "UV", "UV2"]:
			if "custom_vertex_streams_unsupported" not in _limitations:
				_limitations.append("custom_vertex_streams_unsupported")
	var source_materials: Array = renderer.get("materials", [])
	if source_materials.is_empty():
		source_materials = [{}]
	if material_textures.is_empty():
		material_textures = renderer.get("material_textures", config.get("material_textures", []))
	var priority := clampi(int(renderer.get("sorting_order", 0)), Material.RENDER_PRIORITY_MIN, Material.RENDER_PRIORITY_MAX)
	var sheet_tiles := Vector2.ONE
	if bool(sheet.get("enabled", false)):
		var tiles := _vec2(sheet.get("tiles", [sheet.get("num_tiles_x", 1), sheet.get("num_tiles_y", 1)]), Vector2.ONE)
		sheet_tiles = Vector2(maxf(1.0, tiles.x), maxf(1.0, tiles.y))
	for i in range(source_materials.size()):
		var settings := _settings(source_materials[i], config)
		if source_materials[i] == null and i > 0:
			_materials.append(null)
			continue
		var slot_texture: Texture2D = texture if i == 0 else null
		if i < material_textures.size() and material_textures[i] is Texture2D:
			slot_texture = material_textures[i]
		elif settings.get("texture_resource") is Texture2D:
			slot_texture = settings["texture_resource"]
		var material := _make_material(settings, slot_texture, i)
		material.render_priority = priority
		material.set_shader_parameter("geometry_mode", LOCAL if _geometry == WORLD else _geometry)
		material.set_shader_parameter("mesh_flip", _is_mesh)
		material.set_shader_parameter("pivot", _pivot)
		material.set_shader_parameter("clamp_billboard_size", not _is_mesh)
		material.set_shader_parameter("screen_limits", _screen_limits)
		material.set_shader_parameter("sheet_tiles", sheet_tiles)
		_materials.append(material)
	var trail_settings := _settings(renderer.get("trail_material", {}), config)
	_trail_material = _make_material(trail_settings, trail_texture, -1, true)
	_trail_material.render_priority = priority

func sync(particles: Array, now: float) -> void:
	if not is_instance_valid(_anchor):
		return
	_last_input = particles.size()
	if not _enabled:
		_hide_particle_geometry()
		if _trail_only_enabled:
			_update_ribbon(particles, particles.size())
		else:
			_hide_ribbon()
		return
	var count := 0
	var trail_only: Array = []
	var active_particles: Array = []
	for p: Dictionary in particles:
		if bool(p.get("trail_only", false)):
			trail_only.append(p)
		elif count < _capacity:
			active_particles.append(p)
			count += 1
	var anchor_transform := _anchor.global_transform if _anchor.is_inside_tree() else _anchor.transform
	var anchor_basis := anchor_transform.basis
	var invertible := absf(anchor_basis.determinant()) > 1e-12
	var inverse := anchor_basis.inverse() if invertible else Basis.IDENTITY
	var camera := _active_camera()
	var camera_transform := camera.get_camera_transform() if camera != null else Transform3D.IDENTITY
	var order: Array[Dictionary] = []
	for i in range(count):
		var p: Dictionary = active_particles[i]
		var stable_id := int(p.get("id", i))
		var mesh_slot := _mesh_slot(p, stable_id)
		if mesh_slot < 0:
			continue
		var material_slot := int(p.get("material_slot", p.get("shader_slot", -1)))
		if material_slot >= 0 and (material_slot >= _materials.size() or _materials[material_slot] == null):
			material_slot = -1
		var position: Vector3 = p["position"]
		var depth := (anchor_transform * position - camera_transform.origin).dot(-camera_transform.basis.z)
		var sort_metric := 0.0
		match _sort_mode:
			"Distance":
				if camera != null:
					sort_metric = depth if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else (anchor_transform * position).distance_squared_to(camera_transform.origin)
			"Depth": sort_metric = depth
			"YoungestInFront": sort_metric = float(p.get("age", now - float(p.get("born", now))))
			"OldestInFront": sort_metric = -float(p.get("age", now - float(p.get("born", now))))
		order.append({"index": i, "id": stable_id, "mesh": mesh_slot, "material": material_slot, "sort": sort_metric, "depth": depth})
	if _sort_mode != "None":
		order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if a["sort"] != b["sort"]: return a["sort"] > b["sort"]
			if a["id"] != b["id"]: return a["id"] < b["id"]
			return a["index"] < b["index"])
	_last_slots.clear()
	var runs: Array[Dictionary] = []
	var merged: Dictionary = {}
	var direct_count := 0
	var normal_depth := 0.0
	var anchor_depth := (anchor_transform.origin - camera_transform.origin).dot(-camera_transform.basis.z)
	for item in order:
		normal_depth += float(item["depth"])
	normal_depth /= maxf(1.0, float(order.size()))
	for rank in range(order.size()):
		var item: Dictionary = order[rank]
		var particle: Dictionary = active_particles[item["index"]]
		var mesh_slot: int = item["mesh"]
		var material_slot: int = item["material"]
		var mesh := _draw_meshes[mesh_slot]
		var data := _transform_data(particle, mesh, anchor_transform, inverse, invertible, camera)
		var flags := _flip_flags(particle, item["id"])
		var frame := clampi(roundi(float(particle.get("frame", 0))), -2097151, 2097151)
		var angle: Vector3 = particle["angle"]
		var custom := Color(float(frame * 8 + flags), angle.x, angle.y, angle.z)
		var color: Color = particle["color"]
		_last_slots.append({"id": item["id"], "mesh_slot": mesh_slot, "material_slot": material_slot, "frame": frame, "flip_flags": flags, "sort": item["sort"]})
		# 兼容渲染器的实例颜色和自定义数据可能降精度；独立材质 uniform 保留原值。
		if _compatibility:
			var desired_depth := float(item["depth"]) if _sort_mode == "None" else normal_depth + float(order.size() - rank) * 0.0001
			_write_direct(direct_count, mesh_slot, material_slot, data, color, custom, float(item["depth"]) - desired_depth + _sorting_offset)
			direct_count += 1
			continue
		var key := Vector2i(mesh_slot, material_slot)
		var run: Dictionary
		if _sort_mode == "None" and merged.has(key):
			run = merged[key]
		elif not runs.is_empty() and runs[-1]["key"] == key:
			run = runs[-1]
		else:
			run = {"key": key, "items": [], "depth": normal_depth - anchor_depth + float(order.size() - rank) * 0.0001}
			runs.append(run)
			merged[key] = run
		run["items"].append({"transform": data[0], "bounds": data[1], "color": color, "custom": custom})
	for i in range(runs.size()):
		_write_batch(i, runs[i])
	for i in range(runs.size(), _batches.size()):
		_hide_batch(_batches[i])
	for i in range(direct_count, _direct.size()):
		_direct[i]["node"].hide()
	var trail_particles := active_particles
	if _sort_mode != "None" and order.size() == count:
		trail_particles = []
		for item in order:
			trail_particles.append(active_particles[item["index"]])
	trail_particles.append_array(trail_only)
	_update_ribbon(trail_particles, trail_particles.size())

func clear() -> void:
	_last_input = 0
	_hide_geometry()

func debug_state() -> Dictionary:
	var frames: Array[int] = []
	for slot in _last_slots:
		frames.append(slot["frame"])
	return {"visible_count": _last_slots.size(), "input_count": _last_input, "trail_segments": _trail_segments, "frame_slots": frames, "particle_slots": _last_slots.duplicate(true), "material_slots": _material_diagnostics.duplicate(true), "limitations": _limitations.duplicate(), "geometry_mode": _geometry, "sort_mode": _sort_mode, "compatibility_full_precision_path": _compatibility, "renderer_enabled": _enabled}

func _transform_data(particle: Dictionary, mesh: Mesh, anchor_transform: Transform3D, inverse: Basis, invertible: bool, camera: Camera3D) -> Array:
	var position: Vector3 = particle["position"]
	var size: Vector3 = particle["size"]
	var angle: Vector3 = particle["angle"]
	var basis := Basis.from_scale(size)
	var anchor_basis := anchor_transform.basis
	var stretch_basis := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	if _geometry == LOCAL:
		if particle.get("basis_override") is Basis:
			basis = particle["basis_override"]
		else:
			basis = Basis.from_euler(angle) * basis
	elif _geometry == WORLD:
		var scale := Vector3(anchor_basis.x.length(), anchor_basis.y.length(), anchor_basis.z.length())
		basis = inverse * Basis.from_euler(angle) * Basis.from_scale(size * scale)
	elif _geometry == STRETCH:
		if invertible:
			var velocity: Vector3 = particle["velocity"]
			var stretch_scale := Vector2(anchor_basis.x.length(), anchor_basis.y.length())
			stretch_basis = _stretch_world_basis(anchor_basis * velocity, Vector2(size.x, size.y) * stretch_scale)
		basis = inverse * stretch_basis
	elif _geometry == VELOCITY and invertible:
		var velocity: Vector3 = particle["velocity"]
		var up := (anchor_basis * velocity).normalized()
		if up.length_squared() <= EPSILON:
			up = camera.get_camera_transform().basis.y if camera != null else Vector3.UP
		var reference := Vector3.UP if absf(up.y) < 0.99 else Vector3.BACK
		var right := up.cross(reference).normalized()
		var scale := Vector3(anchor_basis.x.length(), anchor_basis.y.length(), anchor_basis.z.length()) * size.abs()
		basis = inverse * Basis(right * scale.x, up * scale.y, right.cross(up) * scale.z)
	var result := Transform3D(basis, position)
	var mesh_bounds := mesh.get_aabb()
	if _geometry in [LOCAL, WORLD] and _pivot == Vector3.ZERO and (_flip == Vector3.ZERO or not _is_mesh) and not particle.has("flip_uv"):
		return [result, (result * mesh_bounds).grow(EPSILON)]
	var world_basis := anchor_basis * basis
	var extent_in_mesh := mesh_bounds.get_center().abs() + mesh_bounds.size * 0.5 + _pivot.abs()
	var max_axis := maxf(world_basis.x.length(), maxf(world_basis.y.length(), world_basis.z.length()))
	var radius := extent_in_mesh.length() * max_axis
	if _geometry == STRETCH:
		radius = (Vector3(extent_in_mesh.x + 0.5, extent_in_mesh.y, 0.0) * Vector3(stretch_basis.x.length(), stretch_basis.y.length(), 0.0)).length()
	if camera != null and not _is_mesh and _screen_limits.x > 0.0:
		var depth := absf((camera.get_camera_transform().affine_inverse() * (anchor_transform * position)).z)
		var half_height := (1.0 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else depth) / maxf(absf(camera.get_camera_projection().y.y), EPSILON)
		var diameter := stretch_basis.z.length() if _geometry == STRETCH else maxf(world_basis.x.length(), world_basis.y.length())
		if diameter > EPSILON:
			var fraction := diameter * 0.5 / maxf(half_height, EPSILON)
			radius *= maxf(1.0, _screen_limits.x / maxf(fraction, EPSILON))
	var transposed := inverse.transposed()
	var extent := Vector3(transposed.x.length(), transposed.y.length(), transposed.z.length()) * maxf(radius, EPSILON)
	return [result, AABB(position - extent, extent * 2.0)]

func _stretch_world_basis(velocity: Vector3, size: Vector2) -> Basis:
	var speed := velocity.length()
	var signed_length := size.y * _length_scale + speed * _velocity_scale
	if speed == 0.0 or signed_length == 0.0:
		return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var direction := velocity / speed * signf(signed_length)
	var reference := Vector3.UP if absf(direction.y) < 0.99 else Vector3.BACK
	var side := reference.cross(direction).normalized()
	return Basis(direction * absf(signed_length), side * size.x, direction.cross(side) * maxf(absf(size.x), absf(size.y)))

func _mesh_slot(particle: Dictionary, stable_id: int) -> int:
	if not _is_mesh:
		return 0
	var requested := int(particle.get("mesh_slot", -1))
	if requested >= 0 and requested < _draw_meshes.size() and _draw_meshes[requested] != null:
		return requested
	var chosen: Array[int] = []
	var weight_total := 0.0
	for i in range(_draw_meshes.size()):
		if _draw_meshes[i] != null:
			chosen.append(i)
			if _weighted: weight_total += _weights[i]
	if chosen.is_empty():
		return -1
	var sample := _stable_sample(stable_id, 101)
	if weight_total > 0.0:
		var point := sample * weight_total
		for slot in chosen:
			point -= _weights[slot]
			if point < 0.0: return slot
		return chosen[-1]
	return chosen[floori(sample * chosen.size())]

func _flip_flags(particle: Dictionary, stable_id: int) -> int:
	if particle.has("flip_uv"):
		var value: Variant = particle["flip_uv"]
		if value is int:
			return value & 7
		var v := Vector3.ZERO
		if value is Vector2 or value is Vector2i:
			v = Vector3(value.x, value.y, 0.0)
		elif value is Array and value.size() >= 2:
			v = Vector3(float(value[0]), float(value[1]), float(value[2]) if value.size() > 2 else 0.0)
		else:
			v = _vec3(value, Vector3.ZERO)
		var signed_axes := v.x < 0.0 or v.y < 0.0 or v.z < 0.0
		return (1 if (v.x < 0.0 if signed_axes else v.x != 0.0) else 0) | (2 if (v.y < 0.0 if signed_axes else v.y != 0.0) else 0) | (4 if (v.z < 0.0 if signed_axes else v.z != 0.0) else 0)
	return (1 if _stable_sample(stable_id, 149) < _flip.x else 0) | (2 if _stable_sample(stable_id, 211) < _flip.y else 0) | (4 if _stable_sample(stable_id, 277) < _flip.z else 0)

static func _stable_sample(stable_id: int, salt: int) -> float:
	var n := (stable_id ^ (salt * 374761393)) & 0xffffffff
	n = ((n ^ (n >> 16)) * 73244475) & 0xffffffff
	n = ((n ^ (n >> 16)) * 73244475) & 0xffffffff
	n ^= n >> 16
	return float(n) / 4294967296.0

func _write_batch(index: int, run: Dictionary) -> void:
	var key: Vector2i = run["key"]
	var items: Array = run["items"]
	if index >= _batches.size():
		var node := MultiMeshInstance3D.new()
		node.name = "UnityLibraryParticles%d" % index
		node.cast_shadow = _shadow_mode
		node.sorting_use_aabb_center = false
		_anchor.add_child(node)
		_batches.append({"node": node, "key": Vector2i(-1, -2)})
	var batch: Dictionary = _batches[index]
	var node: MultiMeshInstance3D = batch["node"]
	if batch["key"] != key or node.multimesh.instance_count < items.size():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = _batch_mesh(key)
		multimesh.instance_count = mini(_capacity, maxi(1, int(pow(2.0, ceil(log(float(items.size())) / log(2.0))))))
		node.multimesh = multimesh
		node.material_override = _override_material(key)
		batch["key"] = key
	var mm := node.multimesh
	var bounds := AABB()
	for i in range(items.size()):
		var item: Dictionary = items[i]
		mm.set_instance_transform(i, item["transform"])
		mm.set_instance_color(i, item["color"])
		mm.set_instance_custom_data(i, item["custom"])
		bounds = item["bounds"] if i == 0 else bounds.merge(item["bounds"])
	var previous := mm.visible_instance_count if mm.visible_instance_count >= 0 else items.size()
	for i in range(items.size(), previous):
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_color(i, Color(0.0, 0.0, 0.0, 0.0))
		mm.set_instance_custom_data(i, Color(0.0, 0.0, 0.0, 0.0))
	mm.custom_aabb = bounds
	mm.visible_instance_count = items.size()
	node.sorting_offset = _sorting_offset - (float(run["depth"]) if _sort_mode != "None" else 0.0)
	node.show()

func _write_direct(index: int, mesh_slot: int, material_slot: int, data: Array, color: Color, custom: Color, sorting_offset: float) -> void:
	var key := Vector2i(mesh_slot, material_slot)
	if index >= _direct.size():
		var node := MeshInstance3D.new()
		node.name = "UnityLibraryParticle%d" % index
		node.cast_shadow = _shadow_mode
		node.sorting_use_aabb_center = false
		_anchor.add_child(node)
		_direct.append({"node": node, "key": Vector2i(-1, -2), "materials": []})
	var entry: Dictionary = _direct[index]
	var node: MeshInstance3D = entry["node"]
	if entry["key"] != key:
		node.mesh = _draw_meshes[mesh_slot]
		var mats: Array[ShaderMaterial] = []
		var one := _override_material(key)
		if one != null:
			var copy := one.duplicate() as ShaderMaterial
			node.material_override = copy
			mats.append(copy)
		else:
			node.material_override = null
			for surface in range(node.mesh.get_surface_count()):
				var copy := _material_for_surface(surface).duplicate() as ShaderMaterial
				node.set_surface_override_material(surface, copy)
				mats.append(copy)
		entry["key"] = key
		entry["materials"] = mats
	for material: ShaderMaterial in entry["materials"]:
		material.set_shader_parameter("use_per_draw_data", true)
		material.set_shader_parameter("draw_custom", Vector4(custom.r, custom.g, custom.b, custom.a))
		material.set_shader_parameter("draw_color", Vector4(color.r, color.g, color.b, color.a))
	node.transform = data[0]
	var local_bounds: AABB = data[1]
	if absf(node.transform.basis.determinant()) > 1e-12:
		node.custom_aabb = node.transform.affine_inverse() * local_bounds
	else:
		node.custom_aabb = node.mesh.get_aabb()
	node.sorting_offset = sorting_offset
	node.show()

func _override_material(key: Vector2i) -> ShaderMaterial:
	if key.y >= 0:
		return _materials[key.y]
	if _draw_meshes[key.x].get_surface_count() <= 1 or _materials.size() <= 1:
		return _materials[0]
	return null

func _material_for_surface(surface: int) -> ShaderMaterial:
	return _materials[surface] if surface < _materials.size() and _materials[surface] != null else _materials[0]

func _batch_mesh(key: Vector2i) -> Mesh:
	if _override_material(key) != null:
		return _draw_meshes[key.x]
	if not _surface_meshes.has(key.x):
		var mesh := _draw_meshes[key.x].duplicate() as Mesh
		for i in range(mesh.get_surface_count()):
			mesh.surface_set_material(i, _material_for_surface(i))
		_surface_meshes[key.x] = mesh
	return _surface_meshes[key.x]

func _settings(raw: Variant, config: Dictionary) -> Dictionary:
	var source := {} if not raw is Dictionary else raw as Dictionary
	var library: Dictionary = config.get("material_library", {})
	var asset_key := str(source.get("asset_key", raw if raw is String else ""))
	var settings: Dictionary = library.get(asset_key, {})
	return settings.merged(source, true)

func _make_material(settings: Dictionary, texture: Texture2D, slot: int, is_trail := false) -> ShaderMaterial:
	if Powerbox.supports(settings):
		var special := Powerbox.make(settings, texture, {}) as ShaderMaterial
		_material_diagnostics.append({"slot": slot, "shader": settings.shader, "asset_key": settings.get("asset_key", ""),
			"missing_textures": special.get_meta("powerbox_missing_textures", []), "limitations": special.get_meta("powerbox_limitations", []), "specialized": true})
		return special
	var spec := _blend_spec(settings)
	var cull := ["cull_disabled", "cull_front", "cull_back"][clampi(int(settings.get("_Cull", 0 if is_trail else 2)), 0, 2)] as String
	var depth := "depth_draw_always" if float(settings.get("_ZWrite", 1.0 if not spec["transparent"] else 0.0)) > 0.5 else "depth_draw_never"
	var shader_name := str(settings.get("shader", ""))
	var legacy_particles := shader_name.begins_with("Legacy Shaders/Particles/") or shader_name in ["Particles/Additive", "Particles/Additive (Soft)", "Particles/Alpha Blended", "Particles/Alpha Blended Premultiply"]
	var legacy_soft := legacy_particles and float(settings.get("_InvFade", 0.0)) > 0.0
	var soft := float(settings.get("_SoftParticlesEnabled", 1.0 if legacy_soft else 0.0)) > 0.5
	var wrap := str(settings.get("texture_wrap", "Repeat"))
	var wrap_u := str(settings.get("texture_wrap_u", wrap))
	var wrap_v := str(settings.get("texture_wrap_v", wrap))
	var per_axis := wrap_u != wrap_v
	var hardware_repeat := wrap == "Repeat" if not per_axis else wrap_u == "Repeat" or wrap_v == "Repeat"
	var filter_hint := str(settings.get("texture_filter", "Bilinear"))
	var filter_mode := "filter_nearest" if filter_hint in ["Point", "Nearest"] else "filter_linear"
	# Use the source-style sampler only when the resource actually contains mips.
	# Single-level and synthetic inputs must keep the ordinary base-level filter.
	if texture != null and bool(settings.get("texture_mipmaps", false)):
		filter_mode += "_mipmap"
	var is_lit := shader_name == "Legacy Shaders/Particles/VertexLit Blended" or shader_name == "Particles/Standard Surface" or float(settings.get("_LightingEnabled", 0.0)) > 0.5
	var emission_enabled: bool = float(settings.get("_EmissionEnabled", 0.0)) > 0.5 or "_EMISSION" in settings.get("keywords", [])
	var emission_ref: Variant = settings.get("_EmissionMap")
	var emission_map: Texture2D = _aux_texture(emission_ref) if emission_enabled else null
	var key := "%s/%s/%s/%s/%s/%s/%s/%s/%s/%s/%s/%s/%s" % [spec["godot"], cull, depth, soft, wrap, filter_mode, spec["transparent"], spec["cutout"], is_lit, emission_map != null, per_axis, _receive_shadows, hardware_repeat]
	if not _shader_variants.has(key):
		var shader := Shader.new()
		var modes := "%s, %s, %s" % [spec["godot"], cull, depth]
		var sampler_hint := filter_mode + (", repeat_enable" if hardware_repeat else ", repeat_disable")
		var code := DRAW_SHADER.code.replace("blend_mix, cull_back, depth_draw_never", modes).replace("filter_linear, repeat_enable", sampler_hint)
		if is_lit:
			code = code.replace("unshaded, ", "" if _receive_shadows else "shadows_disabled, ").replace("#define VFX_LIT 0", "#define VFX_LIT 1")
		if emission_map != null: code = code.replace("#define VFX_EMISSION_MAP 0", "#define VFX_EMISSION_MAP 1")
		if soft: code = code.replace("#define VFX_SOFT 0", "#define VFX_SOFT 1")
		if not per_axis and wrap == "Mirror": code = code.replace("#define VFX_MIRROR 0", "#define VFX_MIRROR 1")
		if not per_axis and wrap == "MirrorOnce": code = code.replace("#define VFX_MIRROR_ONCE 0", "#define VFX_MIRROR_ONCE 1")
		if not spec["transparent"]: code = code.replace("#define VFX_TRANSPARENT 1", "#define VFX_TRANSPARENT 0")
		if spec["cutout"]: code = code.replace("#define VFX_CUTOUT 0", "#define VFX_CUTOUT 1")
		shader.code = code
		_shader_variants[key] = shader
	var material := ShaderMaterial.new()
	material.shader = _shader_variants[key]
	material.set_shader_parameter("use_texture", texture != null)
	if texture != null:
		material.set_shader_parameter("main_texture", texture)
	if per_axis:
		var operations := {"Repeat": -1 if hardware_repeat else 0, "Clamp": 1, "Mirror": 2, "MirrorOnce": 3}
		material.set_shader_parameter("axis_wrap", Vector2i(int(operations.get(wrap_u, -1)), int(operations.get(wrap_v, -1))))
		material.set_shader_parameter("sampler_uses_mipmaps", bool(settings.get("texture_mipmaps", false)))
	var legacy_add := shader_name in ["Particles/Additive", "Legacy Shaders/Particles/Additive", "Particles/Additive (Soft)", "Legacy Shaders/Particles/Additive (Soft)"]
	var legacy_alpha := shader_name in ["Particles/Alpha Blended", "Legacy Shaders/Particles/Alpha Blended"]
	var legacy_premul := shader_name.ends_with("/Alpha Blended Premultiply")
	var gain := 2.0 if legacy_add or legacy_alpha else 1.0
	var tint := _color(settings.get("_Color", settings.get("_BaseColor", settings.get("_TintColor", Color(0.5, 0.5, 0.5, 0.5) if gain > 1.0 else Color.WHITE))), Color.WHITE)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("tint_gain", gain)
	var uv_scale := _vec2(settings.get("texture_scale", []), Vector2.ONE)
	var uv_offset := _vec2(settings.get("texture_offset", []), Vector2.ZERO)
	material.set_shader_parameter("texture_scale", uv_scale)
	material.set_shader_parameter("texture_offset", Vector2(uv_offset.x, 1.0 - uv_scale.y - uv_offset.y))
	var color_mode := int(settings.get("_ColorMode", 0))
	material.set_shader_parameter("color_mode", color_mode)
	material.set_shader_parameter("color_coefficients", settings.has("_ColorAddSubDiff"))
	material.set_shader_parameter("color_add_sub_diff", _vec2(settings.get("_ColorAddSubDiff", []), Vector2.ZERO))
	material.set_shader_parameter("blend_semantics", spec["semantics"])
	material.set_shader_parameter("cutoff", float(settings.get("_Cutoff", 0.5)))
	if soft:
		var default_soft_far := 1.0 / maxf(float(settings.get("_InvFade", 1.0)), EPSILON) if legacy_soft else 0.2
		material.set_shader_parameter("soft_distances", Vector2(float(settings.get("_SoftParticlesNearFadeDistance", 0.0)), float(settings.get("_SoftParticlesFarFadeDistance", default_soft_far))))
	if float(settings.get("_CameraFadingEnabled", 0.0)) > 0.5:
		material.set_shader_parameter("camera_fade", Vector2(float(settings.get("_CameraNearFadeDistance", 0.0)), float(settings.get("_CameraFarFadeDistance", 2.0))))
	var marks: Array[String] = []
	if not str(spec["mark"]).is_empty(): marks.append(spec["mark"])
	if is_lit:
		marks.append("legacy_vertex_lighting_approximated_by_godot_lighting")
	elif not shader_name.is_empty() and shader_name != "Particles/Standard Unlit" and not legacy_add and not legacy_alpha and not legacy_premul:
		marks.append("custom_shader_unlit_approximation")
	if settings.has("asset_key") and shader_name.is_empty():
		marks.append("unresolved_material_asset")
	if color_mode < 0 or color_mode > 5:
		marks.append("unsupported_color_mode_multiply_fallback")
	if float(settings.get("_DistortionEnabled", 0.0)) > 0.5:
		marks.append("distortion_unsupported")
	if emission_enabled:
		var glow := _color(settings.get("_EmissionColor", Color.BLACK), Color.BLACK)
		material.set_shader_parameter("emission_tint", glow)
		if emission_map != null:
			material.set_shader_parameter("emission_texture", emission_map)
		elif emission_ref != null:
			marks.append("missing_emission_map")
		if maxf(glow.r, maxf(glow.g, glow.b)) > 1.0: marks.append("hdr_postprocessing_not_matched")
	if maxf(tint.r, maxf(tint.g, tint.b)) > 1.0: marks.append("hdr_postprocessing_not_matched")
	if float(settings.get("_FlipbookMode", 0.0)) > 0.5: marks.append("flipbook_frame_interpolation_unsupported")
	_material_diagnostics.append({"slot": slot, "shader": shader_name, "asset_key": settings.get("asset_key", ""), "blend": spec["label"], "source_blend": spec["src"], "destination_blend": spec["dst"], "blend_op": spec["op"], "color_mode": color_mode, "unsupported": marks})
	return material

static func _aux_texture(source: Variant) -> Texture2D:
	if source is Texture2D: return source
	if source is Dictionary:
		var key := str(source.get("asset_key", "")).replace(":", "_")
		if not key.is_empty() and key.is_valid_filename():
			var path := "res://assets/art/vfx/library/UnityVFXLibrary/Assets/tex_%s.res" % key
			if ResourceLoader.exists(path, "Texture2D"): return load(path) as Texture2D
	return null

static func _blend_spec(settings: Dictionary) -> Dictionary:
	var mode := int(settings.get("_Mode", -1))
	var shader_name := str(settings.get("shader", ""))
	var src := int(settings.get("_SrcBlend", 5))
	var dst := int(settings.get("_DstBlend", 10))
	var op := int(settings.get("_BlendOp", 0))
	if not settings.has("_SrcBlend") and not settings.has("_DstBlend"):
		match mode:
			0, 1: src = 1; dst = 0
			3: src = 1; dst = 10
			4: src = 5; dst = 1
			5: src = 5; dst = 1; op = 2
			6: src = 2; dst = 0
		if shader_name.ends_with("/Additive") or shader_name.ends_with("/Additive (Soft)"):
			dst = 1
		elif shader_name.ends_with("/Alpha Blended Premultiply"):
			src = 1
	var spec := {"src": src, "dst": dst, "op": op, "godot": "blend_mix", "semantics": 0, "transparent": true, "cutout": false, "label": "alpha", "mark": ""}
	if op == 2 and src == 5 and dst == 1:
		spec["godot"] = "blend_sub"; spec["label"] = "reverse_subtract"
	elif op != 0:
		spec["mark"] = "unsupported_blend_op_%d_alpha_fallback" % op
	elif src == 1 and dst == 0:
		spec["transparent"] = false; spec["cutout"] = mode == 1; spec["label"] = "cutout" if mode == 1 else "opaque"
	elif src == 5 and dst == 10:
		pass
	elif src == 5 and dst == 1:
		spec["godot"] = "blend_add"; spec["label"] = "add"
	elif src == 1 and dst == 10:
		spec["godot"] = "blend_premul_alpha"; spec["semantics"] = 1; spec["label"] = "premultiplied"
	elif (src == 2 and dst == 0) or (src == 0 and dst == 3):
		spec["godot"] = "blend_mul"; spec["semantics"] = 2 if mode == 6 else 0; spec["label"] = "multiply"
	elif src == 2 and dst == 3:
		spec["godot"] = "blend_mul"; spec["semantics"] = 3; spec["label"] = "multiply_double"
	else:
		spec["mark"] = "unsupported_blend_pair_%d_%d_alpha_fallback" % [src, dst]
	return spec

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
		var camera_transform := camera.get_camera_transform()
		camera_origin = local_from_world * camera_transform.origin
		view = local_from_world.basis * camera_transform.basis.z
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
				tangent = outgoing if j + 1 < path.size() else incoming
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
				indices.append_array(PackedInt32Array([k, k + 1, k + 2, k + 1, k + 3, k + 2]))
				_trail_segments += 1
	if indices.is_empty():
		_hide_ribbon()
		return
	if not is_instance_valid(_ribbon_node):
		_ribbon_node = MeshInstance3D.new()
		_ribbon_node.name = "UnityLibraryRibbon"
		_ribbon_node.material_override = _trail_material
		_ribbon_node.cast_shadow = _shadow_mode
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

func _hide_geometry() -> void:
	_hide_particle_geometry()
	_hide_ribbon()

func _hide_particle_geometry() -> void:
	_last_slots.clear()
	for batch in _batches:
		_hide_batch(batch)
	for entry in _direct:
		if is_instance_valid(entry["node"]):
			entry["node"].hide()

static func _hide_batch(batch: Dictionary) -> void:
	var node: MultiMeshInstance3D = batch["node"]
	if is_instance_valid(node):
		node.hide()
		node.multimesh.visible_instance_count = 0
		node.multimesh.custom_aabb = AABB()

func _dispose_nodes() -> void:
	_last_slots.clear()
	_last_input = 0
	for batch in _batches: _detach(batch["node"])
	for entry in _direct: _detach(entry["node"])
	_detach(_ribbon_node)
	_batches.clear()
	_direct.clear()
	_ribbon_node = null
	_trail_segments = 0

static func _detach(node: Node3D) -> void:
	if is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()

static func _vec2(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2 or value is Vector2i: return Vector2(value)
	if value is Array and value.size() >= 2: return Vector2(float(value[0]), float(value[1]))
	return fallback

static func _vec3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3 or value is Vector3i: return Vector3(value)
	if value is Array and value.size() >= 3: return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback

static func _color(value: Variant, fallback: Color) -> Color:
	if value is Color: return value
	if value is Array and value.size() >= 3: return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]) if value.size() > 3 else 1.0)
	return fallback
