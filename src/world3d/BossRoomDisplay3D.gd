@tool
extends Node3D
## Presentation-only control surface. Character triggers own the sequence externally.
@export var screen_material: ShaderMaterial
@export var lamp_material: ShaderMaterial
@export var lit := true:
	set(value):
		lit = value
		if is_inside_tree():
			_apply(get_node_or_null("ImportedModel"))

# Encoded positive state enables the new shader path only in the shared Boss room.
var _screen_state := 0.0
var _screen_slot := 0
var _interference := 0.0
var _screen_meshes: Array[MeshInstance3D] = []
var _screen_tween: Tween

func _ready() -> void:
	_apply(get_node_or_null("ImportedModel"))

func set_signal_picture(state: int, slot: int, burst: bool = false) -> void:
	if not screen_material:
		return
	if _screen_tween != null:
		_screen_tween.kill()
		_screen_tween = null
	_screen_state = float(state)
	_screen_slot = slot
	_set_interference(0.0)
	if not burst or state == 0:
		return
	# Center, left, right lock and release separately. One decaying pulse; no flash train.
	var delay := 0.0 if slot == 1 else (0.12 if slot == 0 else 0.24)
	var peak := 1.0 if slot == 1 else 0.64
	_screen_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_screen_tween.tween_method(_set_interference, 0.0, peak, 0.075).set_delay(delay)
	_screen_tween.tween_method(_set_interference, peak, 0.0, 0.58).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_interference(value: float) -> void:
	_interference = value
	for mesh in _screen_meshes:
		mesh.set_instance_shader_parameter("signal_picture", Vector4(_screen_state, float(_screen_slot), value, 0.0))

func set_lit(value: bool) -> void:
	lit = value

func _apply(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if screen_material:
			mesh_node.material_override = screen_material
			if not _screen_meshes.has(mesh_node):
				_screen_meshes.append(mesh_node)
			mesh_node.set_instance_shader_parameter("signal_picture", Vector4(_screen_state, float(_screen_slot), _interference, 0.0))
		elif lamp_material and mesh_node.mesh:
			for i in range(mesh_node.mesh.get_surface_count()):
				var material := mesh_node.mesh.surface_get_material(i)
				if material and material.resource_name.begins_with("04_柔和自发光"):
					mesh_node.set_surface_override_material(i, lamp_material)
		mesh_node.set_instance_shader_parameter("lamp_brightness", 1.0 if lit else 0.0)
	for child in node.get_children():
		_apply(child)
