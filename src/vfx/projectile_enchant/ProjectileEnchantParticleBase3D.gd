extends VfxEffectBase3D
## 私有持续附件基类；外观和粒子参数冻结在各自的独立 Prefab。

var _authored_amount := 0
var _configured := false
var _visual_size := 1.0
var _grow_from := 1.0
var _grow_duration := 0.0
var _flight_time := 0.0
var _axial_scale := 1.0
var _particle_material: ParticleProcessMaterial
var _base_box_extents := Vector3.ZERO
var _base_visibility_aabb := AABB()
var _body_visual_tint := Color.WHITE
var _body_attribute_tint := Color.WHITE
var _body_root_visible := false
var _base_core_color := Color.WHITE
var _base_core_emission := Color.WHITE
var _base_shell_color := Color.WHITE
var _base_shell_emission := Color.WHITE
var _body_visuals_initialized := false
@onready var _particles: GPUParticles3D = $Particles
@onready var _bullet_root: Node3D = $BulletRoot
@onready var _bullet_core: MeshInstance3D = $BulletRoot/Core
@onready var _bullet_shell: MeshInstance3D = $BulletRoot/Shell
@onready var _bullet_core_material: StandardMaterial3D = $BulletRoot/Core.material_override
@onready var _bullet_shell_material: StandardMaterial3D = $BulletRoot/Shell.material_override


func _ready() -> void:
	_ensure_body_visuals()
	set_process(_active and _grow_duration > 0.0 and _grow_from < 1.0)


func _ensure_body_visuals() -> void:
	if _bullet_root == null:
		_bullet_root = get_node("BulletRoot") as Node3D
	if _bullet_core == null:
		_bullet_core = get_node("BulletRoot/Core") as MeshInstance3D
	if _bullet_shell == null:
		_bullet_shell = get_node("BulletRoot/Shell") as MeshInstance3D
	if _bullet_core_material == null:
		_bullet_core_material = _bullet_core.material_override as StandardMaterial3D
	if _bullet_shell_material == null:
		_bullet_shell_material = _bullet_shell.material_override as StandardMaterial3D
	if not _body_visuals_initialized:
		_base_core_color = _bullet_core_material.albedo_color
		_base_core_emission = _bullet_core_material.emission
		_base_shell_color = _bullet_shell_material.albedo_color
		_base_shell_emission = _bullet_shell_material.emission
		_body_visuals_initialized = true


func _ensure_particles() -> void:
	if _particles == null:
		_particles = get_node("Particles") as GPUParticles3D
	if _authored_amount == 0:
		# 第一次 reset 前捕获场景真源，之后不从混合分摊后的 amount 反推。
		_authored_amount = _particles.amount
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
	_particles.amount = maxi(1, floori(float(_authored_amount) / maxi(1, int(context.get("attribute_count", 1)))))
	_particles.position = Vector3.ZERO
	_body_attribute_tint = context.get("body_tint", Color.WHITE) as Color
	_body_visual_tint = context.get("body_tint_resolved", _body_attribute_tint) as Color
	_body_root_visible = bool(context.get("body_root_visible", false))
	_bullet_shell_material.albedo_color = Color(_body_visual_tint, _base_shell_color.a)
	_bullet_shell_material.emission = _body_visual_tint
	_bullet_core_material.albedo_color = _body_visual_tint.lightened(0.22)
	_bullet_core_material.emission = _bullet_core_material.albedo_color
	_bullet_root.visible = _body_root_visible and _active
	_particle_material.emission_box_extents = Vector3(_base_box_extents.x, _base_box_extents.y, _base_box_extents.z * _axial_scale)
	_particles.visibility_aabb = AABB(
		Vector3(_base_visibility_aabb.position.x, _base_visibility_aabb.position.y, _base_visibility_aabb.position.z * _axial_scale),
		Vector3(_base_visibility_aabb.size.x, _base_visibility_aabb.size.y, _base_visibility_aabb.size.z * _axial_scale)
	)
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
	_bullet_root.visible = _active and _body_root_visible
	if _active:
		_particles.speed_scale = 1.0
		_particles.restart()
	_particles.emitting = _active
	if not _active:
		_particles.speed_scale = 0.0
	set_process(_active and _grow_duration > 0.0 and _grow_from < 1.0)


func reset() -> void:
	_ensure_body_visuals()
	_ensure_particles()
	# 隐藏整棵附件并重置GPU模拟，复借不让上发尾迹先显示一帧。
	_particles.visible = false
	_particles.emitting = false
	_particles.speed_scale = 0.0
	_particles.amount = _authored_amount
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
	_bullet_root.scale = Vector3.ONE
	_body_visual_tint = Color.WHITE
	_body_attribute_tint = Color.WHITE
	_body_root_visible = false
	_bullet_core_material.albedo_color = _base_core_color
	_bullet_core_material.emission = _base_core_emission
	_bullet_shell_material.albedo_color = _base_shell_color
	_bullet_shell_material.emission = _base_shell_emission
	_bullet_root.visible = false
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
	_bullet_root.scale.z = _axial_scale


func get_enchantment_snapshot() -> Dictionary:
	_ensure_particles()
	var mesh := _particles.draw_pass_1 as QuadMesh
	var material := mesh.material as StandardMaterial3D
	var scale_curve := _particle_material.scale_curve as CurveTexture
	return {
		"asset_id": String(get_meta("asset_id", "")),
		"asset_version": String(get_meta("asset_version", "")),
		"prefab_path": scene_file_path, "instance_id": get_instance_id(),
		"base_amount": _authored_amount, "authored_amount": _authored_amount,
		"amount": _particles.amount if _configured else 0,
		"particle_capacity": _particles.amount,
		"texture": material.albedo_texture.resource_path,
		"emitting": _particles.emitting, "visible": _particles.visible and visible,
		"configured": _configured, "particle_lifetime": _particles.lifetime,
		"local_coords": _particles.local_coords, "trail_enabled": _particles.trail_enabled,
		"collision_mode": _particle_material.collision_mode,
		"emitter_position": _particles.position,
		"visibility_aabb": _particles.visibility_aabb,
		"base_visibility_aabb": _base_visibility_aabb,
		"gravity": _particle_material.gravity,
		"short_tail_max_distance": _particle_material.initial_velocity_max * _particles.lifetime,
		"emission_shape": _particle_material.emission_shape,
		"emission_box_extents": _particle_material.emission_box_extents,
		"base_emission_box_extents": _base_box_extents,
		"quad_size": mesh.size,
		"scale_min": _particle_material.scale_min, "scale_max": _particle_material.scale_max,
		"birth_scale": scale_curve.curve.sample(0.0),
		"scale_curve_samples": [scale_curve.curve.sample(0.0), scale_curve.curve.sample(0.25), scale_curve.curve.sample(0.5), scale_curve.curve.sample(0.75), scale_curve.curve.sample(1.0)],
		"birth_tint": (_particle_material.color_ramp as GradientTexture1D).gradient.sample(0.0),
		"end_tint": (_particle_material.color_ramp as GradientTexture1D).gradient.sample(1.0),
		"end_scale": scale_curve.curve.sample(1.0),
		"direction": _particle_material.direction, "spread": _particle_material.spread,
		"velocity_min": _particle_material.initial_velocity_min,
		"velocity_max": _particle_material.initial_velocity_max,
		"angle_min": _particle_material.angle_min, "angle_max": _particle_material.angle_max,
		"angular_velocity_min": _particle_material.angular_velocity_min,
		"angular_velocity_max": _particle_material.angular_velocity_max,
		"lifetime_randomness": _particle_material.lifetime_randomness,
		"linear_accel_min": _particle_material.linear_accel_min,
		"linear_accel_max": _particle_material.linear_accel_max,
		"damping_min": _particle_material.damping_min, "damping_max": _particle_material.damping_max,
		"use_fixed_seed": _particles.use_fixed_seed, "seed": _particles.seed,
		"speed_scale": _particles.speed_scale, "blend_mode": material.blend_mode,
		"process_material_instance_id": _particle_material.get_instance_id(),
		"axial_scale": _axial_scale, "visual_size": _visual_size,
		"grow_from": _grow_from, "grow_duration": _grow_duration,
		"growth_factor": _growth_factor(),
		"world_position": global_position if is_inside_tree() else position,
		"visual_scale": scale, "flight_time": _flight_time,
		"body_visual_tint": _body_visual_tint,
		"body_attribute_tint": _body_attribute_tint,
		"body_root_visible": _bullet_root.visible,
		"body_root": _bullet_root,
		"body_core": _bullet_core,
		"body_shell": _bullet_shell,
	}
