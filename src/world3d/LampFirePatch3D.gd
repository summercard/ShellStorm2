class_name LampFirePatch3D
extends Area3D
## Gameplay owns damage/lifetime. Flames and the burst come from existing VFX prefabs.

signal extinguished

const BURN_SECONDS := 5.0
const TICK_SECONDS := 0.5
const DEFAULT_RADIUS := 1.25
const FLAME_SIZE := 1.25
var radius := DEFAULT_RADIUS
var damage := 10
var expires_at := 0.0
var _effects: Array[VfxEffectBase3D] = []
var _cooldowns := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	collision_layer = 0
	collision_mask = 5
	add_to_group("lamp_fire_patch_3d")
	var collision := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 1.4
	collision.shape = cylinder
	collision.position.y = 0.7
	add_child(collision)
	if expires_at <= 0.0:
		expires_at = Time.get_unix_time_from_system() + BURN_SECONDS
	_effects = create_ground_flames(_acquire, global_position, radius)

## Shared lamp/molotov composition: same prefab, flame size and placement.
static func create_ground_flames(acquire: Callable, point: Vector3, area_radius: float = DEFAULT_RADIUS) -> Array[VfxEffectBase3D]:
	var effects: Array[VfxEffectBase3D] = []
	var count := 1 if area_radius < DEFAULT_RADIUS * 0.65 else 5
	for index in count:
		var angle := (index - 1) * TAU / 4.0
		var offset := Vector3.ZERO if index == 0 else Vector3(cos(angle), 0, sin(angle)) * area_radius * 0.62
		var effect := acquire.call(VfxPool3D.FX01_FATE_FIRE, point + offset, FLAME_SIZE, {"ground_fire": true, "illuminate": index == 0, "duration": BURN_SECONDS, "light_energy": 4.0 if count > 1 else 1.5, "light_range": 5.625 if count > 1 else 2.2}) as VfxEffectBase3D
		if effect != null:
			effects.append(effect)
	return effects

func _acquire(asset_id: StringName, point: Vector3, size: float, context: Dictionary = {}) -> VfxEffectBase3D:
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool != null:
		return pool.acquire(asset_id, point, Color("ff7b27"), size, context)
	var effect := VfxPool3D.create_unpooled(asset_id)
	if effect != null:
		get_parent().add_child(effect)
		effect.activate(point, Color("ff7b27"), size, context)
	return effect

func burst() -> void:
	_acquire(VfxPool3D.FX01_EXPLOSION, global_position + Vector3.UP * 0.15, 0.9)

func _physics_process(_delta: float) -> void:
	var now := Time.get_unix_time_from_system()
	if now >= expires_at:
		extinguish()
		return
	if get_tree().paused:
		return
	for node in get_overlapping_bodies():
		if not node is CharacterBody3D or not node.has_method("take_damage"):
			continue
		var id := node.get_instance_id()
		if now < float(_cooldowns.get(id, 0.0)):
			continue
		var direction := node.global_position - global_position
		direction.y = 0
		node.call("take_damage", damage, false, direction.normalized())
		_cooldowns[id] = now + TICK_SECONDS

func extinguish() -> void:
	set_physics_process(false)
	set_deferred("monitoring", false)
	_stop_effects()
	extinguished.emit()
	queue_free()

func _stop_effects() -> void:
	for effect in _effects:
		if is_instance_valid(effect):
			effect.finish()
	_effects.clear()

func _exit_tree() -> void:
	_stop_effects()
