class_name VfxBookcaseLandingDust3D
extends "res://src/vfx/VfxEffectBase3D.gd"
## Three authored puffs, one short burst. No collision, light, or secondary particles.
var _materials: Array[StandardMaterial3D] = []
var _origins: Array = []

func _ready() -> void:
	for index in 3:
		var puff := get_node("Puff%d" % index) as MeshInstance3D
		var material := puff.get_active_material(0).duplicate() as StandardMaterial3D
		puff.material_override = material
		_materials.append(material)

func _on_activate(_pos: Vector3, _color: Color, _size: float, context: Dictionary) -> void:
	lifetime = 0.7
	_origins = context.get("puff_offsets",[Vector3(-0.8,0,0),Vector3(0.8,0,0),Vector3(0,0,0.8)])
	rotation = Vector3.ZERO
	global_basis = Basis.IDENTITY
	_on_tick(0,lifetime)

func _on_tick(elapsed: float, total: float) -> void:
	var progress := clampf(elapsed / total,0,1)
	for index in 3:
		var puff := get_node("Puff%d" % index) as MeshInstance3D
		var spread := (index-1)*0.5
		puff.position = (_origins[index] as Vector3) + Vector3(spread*progress*0.25,0.18+progress*0.45,0)*effect_size
		puff.scale = Vector3(1,0.65,0.9)*(0.3+progress*0.65)*effect_size
		_materials[index].albedo_color.a = sin(clampf(progress*3.0,0,1)*PI*0.5)*(1-progress)*0.45

func _on_lifetime_expired() -> void:
	for material in _materials:material.albedo_color.a = 0.0
