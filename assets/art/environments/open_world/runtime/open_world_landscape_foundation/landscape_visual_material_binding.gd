extends Node3D

# 仅认领现有城市材质，不创建材质，也不修改原城市实例或生成规则。
func _ready() -> void:
	_bind_existing_city_material.call_deferred()

func _bind_existing_city_material() -> void:
	for frame in range(120):
		var cities := get_tree().root.find_children("CityBuildingSilhouettes", "MultiMeshInstance3D", true, false)
		if not cities.is_empty():
			var city := cities[0] as MultiMeshInstance3D
			if city.multimesh != null and city.multimesh.mesh != null:
				var material := city.multimesh.mesh.surface_get_material(0)
				if material != null:
					for child in get_children():
						if child is MeshInstance3D and child.get_meta("reuse_city_material", false):
							(child as MeshInstance3D).material_override = material
							child.set_meta("material_bound_to_existing_city", true)
					return
		await get_tree().process_frame
	set_meta("city_material_binding_status", "独立编辑预览未挂载城市，使用组件既有墙材质；正式运行绑定由验收门禁验证")
