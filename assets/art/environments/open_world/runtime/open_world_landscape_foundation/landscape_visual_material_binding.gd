extends Node3D

## 仅认领现有城市材质，不创建材质，也不修改原城市实例或生成规则。
##
## 绑定要等程序城市（`CityBuildingSilhouettes`）生成出来，所以要轮询若干帧。
## **轮询期间本节点可能已经被移出树** —— `_ready` 里排的 `call_deferred` 至少隔一帧才跑，
## 而这一帧里场景可能被整个换掉（实测：带续局存档时，引导用的 TowerDescent3D 会在第 1 帧
## 被 `TowerDescent3D._resume_expedition_runtime_scene()` 的 `change_scene_to_file` 顶掉）。
##
## 关键：**不能靠 `get_tree()` 的返回值判空**。`Node::get_tree()` 自己就带
## `ERR_FAIL_NULL_V`，出树时哪怕只读返回值也会先打一条
## `ERROR: Parameter "data.tree" is null.`。所以必须先 `is_inside_tree()`（纯读标志位，
## 无副作用）挡掉，再去取 tree；否则 `.root` 还会接着抛
## `Invalid access to property or key 'root' on a base object of type 'null instance'`。
##
## 这是**结构判据**，不是错误容忍 —— 出树的实例本来就没有可认领的城市。
const BIND_POLL_FRAMES := 120

## 轮询上限内没等到城市时的落账说明（原行为，保持不变）。
const BIND_DEFERRED_REASON := "独立编辑预览未挂载城市，使用组件既有墙材质；正式运行绑定由验收门禁验证"


func _ready() -> void:
	_bind_existing_city_material.call_deferred()


func _bind_existing_city_material() -> void:
	for _frame in range(BIND_POLL_FRAMES):
		if not is_inside_tree():
			# 已经不在这棵树里（换场景 / 引导场景被顶掉）—— 没有可认领的对象，安静收工。
			return
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
	set_meta("city_material_binding_status", BIND_DEFERRED_REASON)
