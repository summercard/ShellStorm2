class_name ProjectilePool3D
extends Node3D
## 统一复用玩家与敌人的投射物，避免高射速/散弹组合持续创建网格、材质和物理体。

@export var max_pool_size := 128

var _inactive: Array[Projectile3D] = []
var _created := 0
var _active := 0
var _peak_active := 0


func _ready() -> void:
	add_to_group("projectile_pool_3d")


func acquire(config: Dictionary, world_position: Vector3) -> Projectile3D:
	var projectile: Projectile3D
	if not _inactive.is_empty():
		projectile = _inactive.pop_back()
	else:
		projectile = _create_projectile()
	_active += 1
	_peak_active = maxi(_peak_active, _active)
	projectile.activate(config, world_position)
	return projectile


func _create_projectile() -> Projectile3D:
	var projectile := Projectile3D.new()
	add_child(projectile)
	projectile.retired.connect(_on_projectile_retired)
	_created += 1
	return projectile


## Render one real pooled round behind the loading screen without a physics tick.
func begin_render_warmup(world_position: Vector3) -> Projectile3D:
	if not _inactive.is_empty() or _active > 0 or max_pool_size < 1:
		return null
	var sample := _create_projectile()
	sample.activate({"projectile_collision_mask":0}, world_position)
	sample.collision_layer = 0
	sample.process_mode = Node.PROCESS_MODE_DISABLED
	_active += 1
	return sample


func finish_render_warmup(sample: Projectile3D) -> void:
	sample.collision_layer = 8
	sample._retire()


func _on_projectile_retired(projectile: Projectile3D) -> void:
	_active = maxi(0, _active - 1)
	if _inactive.size() >= max_pool_size:
		projectile.queue_free()
		_created = maxi(0, _created - 1)
		return
	_inactive.append(projectile)


func get_snapshot() -> Dictionary:
	return {
		"created": _created, "active": _active, "inactive": _inactive.size(),
		"peak_active": _peak_active, "max_pool_size": max_pool_size,
	}
