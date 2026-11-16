extends VfxEffectBase3D
## 私有持续附件基类；外观和粒子参数冻结在各自的独立 Prefab。

const BASE_AMOUNT := 24
var _configured := false
var _visual_size := 1.0
var _grow_from := 1.0
var _grow_duration := 0.0
var _flight_time := 0.0
@onready var _particles: GPUParticles3D = $Particles


func _ready() -> void:
	set_process(false)


func _on_configure(context: Dictionary) -> void:
	if _particles == null:
		_particles = get_node("Particles") as GPUParticles3D
	var requested_size := effect_size
	reset()
	effect_size = requested_size
	_configured = true
	_visual_size = maxf(0.05, requested_size)
	_grow_from = clampf(float(context.get("grow_from", 1.0)), 0.05, 1.0)
	_grow_duration = maxf(0.0, float(context.get("grow_duration", 0.0)))
	_particles.amount = maxi(1, floori(float(BASE_AMOUNT) / maxi(1, int(context.get("attribute_count", 1)))))
	_particles.position.z = 0.08 + 0.12 * maxf(0.1, float(context.get("axial_scale", 1.0)))
	_apply_size()


func activate(world_position: Vector3, color: Color, size: float, context: Dictionary = {}) -> void:
	configure(color, size, context)
	global_position = world_position
	set_emitting(true)


func finish() -> void:
	reset()


func set_emitting(enabled: bool) -> void:
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
	if _particles == null:
		_particles = get_node("Particles") as GPUParticles3D
	# 隐藏整棵附件并重置GPU模拟，复借不让上发尾迹先显示一帧。
	_particles.visible = false
	_particles.restart()
	_particles.emitting = false
	_particles.speed_scale = 0.0
	_particles.amount = 1
	_particles.position = Vector3.ZERO
	_configured = false
	_active = false
	_elapsed = 0.0
	_flight_time = 0.0
	_visual_size = 1.0
	_grow_from = 1.0
	_grow_duration = 0.0
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


func _apply_size() -> void:
	var growth := lerpf(_grow_from, 1.0, clampf(_flight_time / _grow_duration, 0.0, 1.0)) if _grow_duration > 0.0 else 1.0
	scale = Vector3.ONE * _visual_size * growth


func get_enchantment_snapshot() -> Dictionary:
	var mesh := _particles.draw_pass_1 as QuadMesh
	var material := mesh.material as StandardMaterial3D
	var particle_material := _particles.process_material as ParticleProcessMaterial
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
		"collision_mode": particle_material.collision_mode,
		"world_position": global_position if is_inside_tree() else position,
		"visual_scale": scale, "flight_time": _flight_time,
	}
