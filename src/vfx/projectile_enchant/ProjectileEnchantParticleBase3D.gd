extends VfxEffectBase3D
## 私有持续附件基类；外观和粒子参数冻结在各自的独立 Prefab。

const BASE_AMOUNT := 24
var _configured := false
var _visual_size := 1.0
var _grow_from := 1.0
var _grow_duration := 0.0
var _flight_time := 0.0
var _axial_scale := 1.0
var _particle_material: ParticleProcessMaterial
var _base_box_extents := Vector3.ZERO
var _base_visibility_aabb := AABB()
@onready var _particles: GPUParticles3D = $Particles


func _ready() -> void:
	set_process(_active and _grow_duration > 0.0 and _grow_from < 1.0)


func _ensure_particles() -> void:
	if _particles == null:
		_particles = get_node("Particles") as GPUParticles3D
	if _particle_material == null:
		# 仅本实例调整轴向范围；共享 Prefab 的其他弹体不得被狙击档位串改。
		_particle_material = _particles.process_material.duplicate() as ParticleProcessMaterial
		_particles.process_material = _particle_material
		_base_box_extents = _particle_material.emission_box_extents
		_base_visibility_aabb = _particles.visibility_aabb


func _on_configure(context: Dictionary) -> void:
	_ensure_particles()
	var requested_size := effect_size
	var requested_color := effect_color
	reset()
	effect_size = requested_size
	effect_color = requested_color
	_configured = true
	_visual_size = maxf(0.05, requested_size)
	_grow_from = clampf(float(context.get("grow_from", 1.0)), 0.05, 1.0)
	_grow_duration = maxf(0.0, float(context.get("grow_duration", 0.0)))
	_axial_scale = maxf(0.05, float(context.get("axial_scale", 1.0)))
	_particles.amount = maxi(1, floori(float(BASE_AMOUNT) / maxi(1, int(context.get("attribute_count", 1)))))
	_particles.position = Vector3.ZERO
	_particle_material.emission_box_extents = Vector3(_base_box_extents.x, _base_box_extents.y, _base_box_extents.z * _axial_scale)
	var axial_bound := maxf(1.0, _particle_material.emission_box_extents.z + 1.0)
	_particles.visibility_aabb = AABB(Vector3(-1.0, -1.0, -axial_bound), Vector3(2.0, 2.0, axial_bound * 2.0 + 1.0))
	_apply_size()


func activate(world_position: Vector3, color: Color, size: float, context: Dictionary = {}) -> void:
	configure(color, size, context)
	global_position = world_position
	set_emitting(true)


func finish() -> void:
	reset()


func set_emitting(enabled: bool) -> void:
	_ensure_particles()
	_active = enabled and _configured
	visible = _active
	_particles.visible = _active
	if _active:
		_particles.speed_scale = 1.0
		_particles.restart()
	_particles.emitting = _active
	if not _active:
		_particles.speed_scale = 0.0
	set_process(_active and _grow_duration > 0.0 and _grow_from < 1.0)


func reset() -> void:
	_ensure_particles()
	# 隐藏整棵附件并重置GPU模拟，复借不让上发尾迹先显示一帧。
	_particles.visible = false
	_particles.restart()
	_particles.emitting = false
	_particles.speed_scale = 0.0
	_particles.amount = 1
	_particles.position = Vector3.ZERO
	_particle_material.emission_box_extents = _base_box_extents
	_particles.visibility_aabb = _base_visibility_aabb
	_configured = false
	_active = false
	_elapsed = 0.0
	_flight_time = 0.0
	_visual_size = 1.0
	_grow_from = 1.0
	_grow_duration = 0.0
	_axial_scale = 1.0
	effect_color = Color.WHITE
	effect_size = 1.0
	_follow = null
	_follow_local_offset = Vector3.ZERO
	scale = Vector3.ONE
	visible = false
	set_process(false)


func deactivate() -> void:
	reset()


func _process(delta: float) -> void:
	if not _active:
		return
	_flight_time += delta
	_apply_size()
	if _flight_time >= _grow_duration:
		set_process(false)


func _growth_factor() -> float:
	return lerpf(_grow_from, 1.0, clampf(_flight_time / _grow_duration, 0.0, 1.0)) if _grow_duration > 0.0 else 1.0


func _apply_size() -> void:
	scale = Vector3.ONE * _visual_size * _growth_factor()


func get_enchantment_snapshot() -> Dictionary:
	_ensure_particles()
	var mesh := _particles.draw_pass_1 as QuadMesh
	var material := mesh.material as StandardMaterial3D
	var scale_curve := _particle_material.scale_curve as CurveTexture
	return {
		"asset_id": String(get_meta("asset_id", "")),
		"asset_version": String(get_meta("asset_version", "")),
		"prefab_path": scene_file_path, "instance_id": get_instance_id(),
		"base_amount": BASE_AMOUNT, "amount": _particles.amount if _configured else 0,
		"particle_capacity": _particles.amount,
		"texture": material.albedo_texture.resource_path,
		"emitting": _particles.emitting, "visible": _particles.visible and visible,
		"configured": _configured, "particle_lifetime": _particles.lifetime,
		"local_coords": _particles.local_coords, "trail_enabled": _particles.trail_enabled,
		"collision_mode": _particle_material.collision_mode,
		"emitter_position": _particles.position,
		"visibility_aabb": _particles.visibility_aabb,
		"gravity": _particle_material.gravity,
		"short_tail_max_distance": _particle_material.initial_velocity_max * _particles.lifetime,
		"emission_shape": _particle_material.emission_shape,
		"emission_box_extents": _particle_material.emission_box_extents,
		"base_emission_box_extents": _base_box_extents,
		"quad_size": mesh.size,
		"scale_min": _particle_material.scale_min, "scale_max": _particle_material.scale_max,
		"birth_scale": scale_curve.curve.sample(0.0),
		"birth_tint": (_particle_material.color_ramp as GradientTexture1D).gradient.sample(0.0),
		"end_tint": (_particle_material.color_ramp as GradientTexture1D).gradient.sample(1.0),
		"end_scale": scale_curve.curve.sample(1.0),
		"direction": _particle_material.direction, "spread": _particle_material.spread,
		"velocity_min": _particle_material.initial_velocity_min,
		"velocity_max": _particle_material.initial_velocity_max,
		"process_material_instance_id": _particle_material.get_instance_id(),
		"axial_scale": _axial_scale, "visual_size": _visual_size,
		"grow_from": _grow_from, "grow_duration": _grow_duration,
		"growth_factor": _growth_factor(),
		"world_position": global_position if is_inside_tree() else position,
		"visual_scale": scale, "flight_time": _flight_time,
	}
