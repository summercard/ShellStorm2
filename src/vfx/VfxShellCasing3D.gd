class_name VfxShellCasing3D
extends VfxEffectBase3D
## 开火抛出的弹壳：世界空间弹道、程序化射线落地与两次小弹跳。
## 纯视觉 Prefab，不含碰撞体；地板由场景现有碰撞或 floor_y 兜底判定。

const DEFAULT_LIFETIME := 3.2
const SHELL_RADIUS := 0.045
const GRAVITY := 9.8
const FLOOR_MASK := 1
const MAX_BOUNCES := 2
const REST_SPEED := 0.12

var _body: MeshInstance3D
var _rim: MeshInstance3D
var _primer: MeshInstance3D
var _velocity := Vector3.ZERO
var _spin_axis := Vector3.UP
var _spin_speed := 0.0
var _floor_y := 0.0
var _has_floor_override := false
var _bounces := 0
var _settled := false
var _world_root: Node3D
var _last_tick_elapsed := 0.0

func _ready() -> void:
	lifetime = DEFAULT_LIFETIME
	_build_visuals()
	visible = false

func _build_visuals() -> void:
	if _body != null:
		return
	_body = get_node_or_null("Body") as MeshInstance3D
	_rim = get_node_or_null("Rim") as MeshInstance3D
	_primer = get_node_or_null("Primer") as MeshInstance3D

func _on_configure(context: Dictionary) -> void:
	_has_floor_override = context.has("floor_y")
	_floor_y = float(context.get("floor_y", 0.0))
	_world_root = context.get("world_root") as Node3D
	if _world_root == null:
		_world_root = get_tree().current_scene as Node3D

func _on_activate(_world_pos: Vector3, color: Color, size: float, context: Dictionary) -> void:
	_build_visuals()
	_velocity = context.get("velocity", Vector3(1.8, 1.6, 0.25)) as Vector3
	if _velocity.length_squared() < 0.001:
		_velocity = Vector3(1.8, 1.6, 0.25)
	_spin_axis = (context.get("spin_axis", Vector3(0.7, 1.0, 0.2)) as Vector3).normalized()
	if _spin_axis.length_squared() < 0.001:
		_spin_axis = Vector3.UP
	_spin_speed = float(context.get("spin_speed", 18.0))
	_bounces = 0
	_settled = false
	_last_tick_elapsed = 0.0
	visible = true
	rotation = Vector3.ZERO
	if _body != null:
		_body.scale = Vector3.ONE * size
		_body.visible = true
		_body.material_override = _make_material(color.darkened(0.12), 0.72, 0.24)
	if _rim != null:
		_rim.scale = Vector3.ONE * size
		_rim.visible = true
		_rim.material_override = _make_material(color.lightened(0.12), 0.62, 0.20)
	if _primer != null:
		_primer.scale = Vector3.ONE * size
		_primer.visible = true
		_primer.material_override = _make_material(Color(0.12, 0.10, 0.07), 0.88, 0.32)

func _on_tick(delta_elapsed: float, _total: float) -> void:
	if _settled:
		return
	# _on_tick 接收累计时间；转成相邻 tick 的增量，避免把累计时间当 dt 重复积分。
	var dt: float = clampf(delta_elapsed - _last_tick_elapsed, 0.0, 1.0 / 15.0)
	_last_tick_elapsed = delta_elapsed
	if dt <= 0.0:
		return
	var previous := global_position
	_velocity.y -= GRAVITY * dt
	var next_position := previous + _velocity * dt
	var hit := _raycast_floor(previous, next_position)
	if not hit.is_empty():
		_land_or_bounce(hit, previous)
	else:
		global_position = next_position
	rotation += _spin_axis * _spin_speed * dt
	if _velocity.length() < REST_SPEED and global_position.y <= _floor_y + SHELL_RADIUS + 0.01:
		_settle()

func _raycast_floor(previous: Vector3, next_position: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state if get_world_3d() != null else null
	if space != null:
		var ray_from := previous + Vector3.UP * SHELL_RADIUS
		var ray_to := next_position - Vector3.UP * SHELL_RADIUS
		if ray_to.y <= ray_from.y:
			var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, FLOOR_MASK)
			var result := space.intersect_ray(query)
			if not result.is_empty():
				return result
	if _has_floor_override and next_position.y <= _floor_y + SHELL_RADIUS:
		return {"position": Vector3(next_position.x, _floor_y + SHELL_RADIUS, next_position.z), "normal": Vector3.UP}
	return {}

func _land_or_bounce(hit: Dictionary, previous: Vector3) -> void:
	var hit_position: Vector3 = hit.get("position", Vector3(previous.x, _floor_y, previous.z))
	var normal: Vector3 = (hit.get("normal", Vector3.UP) as Vector3).normalized()
	global_position = hit_position + normal * SHELL_RADIUS
	var incoming := _velocity
	var normal_speed := incoming.dot(normal)
	var tangent := incoming - normal * normal_speed
	if _bounces < MAX_BOUNCES and absf(normal_speed) > REST_SPEED:
		_bounces += 1
		_velocity = tangent * 0.42 - normal * normal_speed * 0.32
		_spin_speed *= 0.68
	else:
		_settle()

func _settle() -> void:
	_settled = true
	_velocity = Vector3.ZERO
	_spin_speed = 0.0
	rotation.x = PI * 0.5
	if global_position.y < _floor_y + SHELL_RADIUS:
		global_position.y = _floor_y + SHELL_RADIUS

func _on_lifetime_expired() -> void:
	_velocity = Vector3.ZERO
	_spin_speed = 0.0
	_settled = false
	visible = false
	if _body != null:
		_body.visible = false
	if _rim != null:
		_rim.visible = false
	if _primer != null:
		_primer.visible = false

func get_presentation_snapshot() -> Dictionary:
	return {
		"asset_id": String(get_meta("asset_id", "")),
		"asset_version": String(get_meta("asset_version", "")),
		"lifetime": lifetime,
		"gravity": GRAVITY,
		"max_bounces": MAX_BOUNCES,
		"settled": _settled,
		"bounce_count": _bounces,
		"velocity": _velocity,
		"body_mesh": _body != null and _body.mesh != null,
		"rim_mesh": _rim != null and _rim.mesh != null,
	}

func _make_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.disable_receive_shadows = false
	return material
