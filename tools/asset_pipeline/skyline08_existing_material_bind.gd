@tool
extends Node3D
## 导入缓存不持有材质；包装实例入树时直接绑定旧PackedScene材质，编辑器同样生效。
const OLD_VISUALS := [
	"res://assets/art/environments/open_world/components/tower_02/floor_00/env_tower_02_floor_00_visual_top3d.glb",
	"res://assets/art/environments/open_world/components/tower_02/crane_00_slew_cab/env_tower_02_crane_00_slew_cab_visual_top3d.glb",
	"res://assets/art/environments/open_world/components/tower_02/roof_warning/env_tower_02_roof_warning_visual_top3d.glb",
]
func _enter_tree() -> void:
	var roles: Dictionary = {}
	for path: String in OLD_VISUALS:
		var packed := load(path) as PackedScene
		var instance := packed.instantiate()
		for value in instance.find_children("*", "MeshInstance3D", true, false):
			var mi := value as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				var material := mi.get_active_material(i)
				if material != null and not roles.has(material.resource_name):
					roles[material.resource_name] = material
		instance.free()
	for value in find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		var names: Array = mi.get_meta("existing_material_roles", [])
		assert(names.size() == mi.mesh.get_surface_count())
		for i in names.size():
			assert(roles.has(names[i]), "缺少旧材质角色")
			mi.set_surface_override_material(i, roles[names[i]])
