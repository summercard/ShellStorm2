extends "res://src/vfx/VfxEffectBase3D.gd"
var visual: Node3D
var materials: Array[ShaderMaterial] = []
var _forward := Vector3.FORWARD
var _side := 1.0
func _on_activate(_pos: Vector3, color: Color, size: float, context: Dictionary) -> void:
	visual = get_node("Visual")
	visual.transform = Transform3D.IDENTITY
	visual.scale = Vector3.ONE * size
	_forward = context.get("forward",Vector3.FORWARD)
	_side = -1.0 if int(context.get("combo_step",1)) == 2 else 1.0
	rotation = Vector3.ZERO
	materials.clear()
	for mesh in visual.find_children("*","MeshInstance3D",true,false):
		var mat := mesh.get_meta("original_material",mesh.material_override) as ShaderMaterial
		mesh.set_meta("original_material",mat)
		var unique := mat.duplicate() as ShaderMaterial
		mesh.material_override = unique
		unique.set_shader_parameter("opacity",1.0)
		materials.append(unique)
	lifetime = float(context.get("duration",0.32))
	_on_tick(0.0,lifetime)
func fade(value: float) -> void:
	for mat in materials:mat.set_shader_parameter("opacity",clampf(value,0.0,1.0))
func face_forward() -> void:
	var forward := follow_forward() if has_follow_target() else _forward
	rotation.y = atan2(-forward.x,-forward.z)
func _on_lifetime_expired() -> void:
	fade(0.0)
