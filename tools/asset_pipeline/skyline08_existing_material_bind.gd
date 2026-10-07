@tool
extends Node3D
## 导入缓存不持有材质；包装实例入树时直接绑定旧PackedScene材质，编辑器同样生效。
## 旧材质的 resource_name 不是稳定契约：Godot 重导入后可能为空或变化。
const OLD_VISUALS := [
	"res://assets/art/environments/open_world/components/tower_02/floor_00/env_tower_02_floor_00_visual_top3d.glb",
	"res://assets/art/environments/open_world/components/tower_02/crane_00_slew_cab/env_tower_02_crane_00_slew_cab_visual_top3d.glb",
	"res://assets/art/environments/open_world/components/tower_02/roof_warning/env_tower_02_roof_warning_visual_top3d.glb",
]

func _enter_tree() -> void:
	var roles: Dictionary = {}
	var legacy_materials: Array[Material] = []
	var materials_by_path: Dictionary = {}
	for path: String in OLD_VISUALS:
		var packed := load(path) as PackedScene
		assert(packed != null, "缺少旧视觉包: " + path)
		if packed == null:
			continue
		var instance := packed.instantiate()
		for value in instance.find_children("*", "MeshInstance3D", true, false):
			var mi := value as MeshInstance3D
			if mi.mesh == null:
				continue
			for i in mi.mesh.get_surface_count():
				var material := mi.get_active_material(i)
				if material == null:
					continue
				var resource_path: String = material.resource_path
				if not legacy_materials.has(material):
					legacy_materials.append(material)
				if not resource_path.is_empty():
					materials_by_path[resource_path] = material
				if not material.resource_name.is_empty() and not roles.has(material.resource_name):
					roles[material.resource_name] = material
		instance.free()
	var fallback_material: Material = null
	if materials_by_path.size() == 1:
		fallback_material = materials_by_path.values()[0] as Material
	for value in find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		var names: Array = mi.get_meta("existing_material_roles", [])
		assert(names.size() == mi.mesh.get_surface_count(), "旧材质角色数量与表面数量不一致: " + str(mi.name))
		if names.size() != mi.mesh.get_surface_count():
			continue
		for i in names.size():
			var role := str(names[i])
			var material: Material = roles.get(role) as Material
			if material == null and i < legacy_materials.size():
				material = legacy_materials[i]
				push_warning("旧材质角色未命中，按表面序号回退旧材质: " + role + " @ " + str(mi.name))
			if material == null and fallback_material != null:
				material = fallback_material
				push_warning("旧材质角色未命中，使用唯一旧材质回退: " + role + " @ " + str(mi.name))
			assert(material != null, "缺少旧材质角色: " + role + " @ " + str(mi.name))
			if material != null:
				mi.set_surface_override_material(i, material)
