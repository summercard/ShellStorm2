@tool
extends EditorScenePostImport
## 新景观所有表面直接复用塔2既有材质子资源，禁止生成或保存新材质。
const EXISTING := {
	"01_精工金属_紫色骨架": true,
	"02_细腻哑光_青绿大面": true,
	"03_清漆反光_紫粉点缀": true,
	"04_柔和自发光_UI灯光": true,
}
func _post_import(scene: Node) -> Object:
	_remap(scene, EXISTING)
	return scene
func _remap(node: Node, roles: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		var names: Array[String] = []
		for i in mesh.get_surface_count():
			var original: Material = mesh.surface_get_material(i)
			assert(original != null and roles.has(original.resource_name), "未知材质角色")
			names.append(original.resource_name)
			mesh.surface_set_material(i, null)
		node.set_meta("existing_material_roles", names)
	for child in node.get_children():
		_remap(child, roles)
