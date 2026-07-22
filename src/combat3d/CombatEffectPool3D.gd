class_name CombatEffectPool3D
extends Node3D
## 按表现类型复用短命特效，降低连射、爆炸和受击时的节点/网格分配尖峰。

const EFFECT_SCENE: PackedScene = preload("res://assets/art/vfx/combat_3d/vfx_combat_kit_root_top3d_v001.tscn")

@export var max_per_kind := 32
var _inactive: Dictionary = {}
var _active := 0
var _created := 0
var _peak_active := 0


func _ready() -> void:
	add_to_group("combat_effect_pool_3d")


func acquire(kind: String, color: Color, size: float, world_position: Vector3, value := "") -> CombatEffect3D:
	var bucket: Array = _inactive.get(kind, [])
	var effect: CombatEffect3D
	if not bucket.is_empty():
		effect = bucket.pop_back() as CombatEffect3D
		_inactive[kind] = bucket
	else:
		effect = EFFECT_SCENE.instantiate() as CombatEffect3D
		effect.configure(kind, color, size, value)
		add_child(effect)
		effect.retired.connect(_on_effect_retired)
		_created += 1
	_active += 1
	_peak_active = maxi(_peak_active, _active)
	effect.activate(kind, color, size, world_position, value)
	return effect


func _on_effect_retired(effect: CombatEffect3D) -> void:
	_active = maxi(0, _active - 1)
	var bucket: Array = _inactive.get(effect.effect_kind, [])
	if bucket.size() >= max_per_kind:
		effect.queue_free()
		_created = maxi(0, _created - 1)
		return
	bucket.append(effect)
	_inactive[effect.effect_kind] = bucket


func get_snapshot() -> Dictionary:
	return {"created": _created, "active": _active, "peak_active": _peak_active, "kinds": _inactive.keys()}
