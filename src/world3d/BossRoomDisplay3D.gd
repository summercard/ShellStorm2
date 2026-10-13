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

func _ready() -> void:
	_apply(get_node_or_null("ImportedModel"))

func set_lit(value: bool) -> void:
	lit = value

func _apply(node: Node) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if screen_material:
			mesh_node.material_override = screen_material
		elif lamp_material and mesh_node.mesh:
			for i in range(mesh_node.mesh.get_surface_count()):
				var material := mesh_node.mesh.surface_get_material(i)
				if material and material.resource_name.begins_with("04_柔和自发光"):
					mesh_node.set_surface_override_material(i, lamp_material)
		mesh_node.set_instance_shader_parameter("lamp_brightness", 1.0 if lit else 0.0)
	for child in node.get_children():
		_apply(child)
