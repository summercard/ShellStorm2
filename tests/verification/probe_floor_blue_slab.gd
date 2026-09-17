extends Node
## 只读探查 v8：抓"看起来不对的大块地面"。
## 两条判据，直击成因：
##   A) material_override != null —— 被代码强行套单色材质的大件（美术资产不会这样）
##   B) albedo_texture == null 且颜色是彩色 —— 没有色盘纹理的纯色大件
## 两条都限定水平跨度 >= 3m，并打印所在楼层高度，便于判断是哪一层。

const TOWER_SCENE := "res://scenes/TowerDescent3D.tscn"
const TARGET_FLOOR := 98


func _ready() -> void:
	var scene := load(TOWER_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	tower.generate_through_floor_for_test(TARGET_FLOOR)
	await get_tree().process_frame
	var room_by_id := tower.get("_room_by_id") as Dictionary
	for id_value in room_by_id.keys():
		var room := room_by_id.get(id_value) as DungeonRoom3D
		if room != null:
			room.set_stream_state(1)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	var override_hits: Array[String] = []
	var solid_hits: Array[String] = []
	for value in tower.find_children("*", "VisualInstance3D", true, false):
		var visual := value as VisualInstance3D
		var aabb := _world_aabb(visual)
		if aabb.size == Vector3.ZERO:
			continue
		var horizontal := maxf(aabb.size.x, aabb.size.z)
		if horizontal < 3.0:
			continue
		var path := String(tower.get_path_to(visual))
		var center := aabb.get_center()
		var floor_index := int(round(-center.y / 12.0))
		var override := _override_of(visual)
		if override != null:
			override_hits.append(
				"  %s\n      size=%s center=%s floor=%dF class=%s count=%s\n      override=%s" % [
					path, _vec(aabb.size), _vec(center), 100 - floor_index,
					visual.get_class(), str(_count(visual)), _mat_text(override),
				]
			)
		else:
			var native := _native_of(visual)
			var base := native as BaseMaterial3D
			if base != null and base.albedo_texture == null:
				var c := base.albedo_color
				var chroma := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
				if chroma > 0.05 or base.emission_enabled:
					solid_hits.append(
						"  %s\n      size=%s center=%s floor=%dF class=%s count=%s\n      native=%s" % [
							path, _vec(aabb.size), _vec(center), 100 - floor_index,
							visual.get_class(), str(_count(visual)), _mat_text(native),
						]
					)
	print("=== A) 被 material_override 覆盖的大件（>=3m）: %d ===" % override_hits.size())
	for line in override_hits:
		print(line)
	print("")
	print("=== B) 无色盘纹理的纯色大件（>=3m）: %d ===" % solid_hits.size())
	for line in solid_hits:
		print(line)
	print("PROBE_V8_DONE")
	get_tree().quit(0)


func _count(visual: VisualInstance3D) -> int:
	if visual is MultiMeshInstance3D:
		var mm := visual as MultiMeshInstance3D
		return mm.multimesh.instance_count if mm.multimesh != null else -1
	return 1


func _override_of(visual: VisualInstance3D) -> Material:
	if visual is MultiMeshInstance3D:
		return (visual as MultiMeshInstance3D).material_override
	if visual is MeshInstance3D:
		return (visual as MeshInstance3D).material_override
	return null


func _native_of(visual: VisualInstance3D) -> Material:
	if visual is MultiMeshInstance3D:
		var mm := visual as MultiMeshInstance3D
		if mm.multimesh != null and mm.multimesh.mesh != null and mm.multimesh.mesh.get_surface_count() > 0:
			return mm.multimesh.mesh.surface_get_material(0)
		return null
	if visual is MeshInstance3D:
		return (visual as MeshInstance3D).get_active_material(0)
	return null


func _mat_text(material: Material) -> String:
	var base := material as BaseMaterial3D
	if base == null:
		return "<non-base %s>" % material.get_class()
	return "albedo=(%.3f,%.3f,%.3f) emis=%s(%.3f,%.3f,%.3f) energy=%.2f tex=%s name=%s" % [
		base.albedo_color.r, base.albedo_color.g, base.albedo_color.b,
		str(base.emission_enabled),
		base.emission.r, base.emission.g, base.emission.b,
		base.emission_energy_multiplier,
		"yes" if base.albedo_texture != null else "no",
		material.resource_name,
	]


func _world_aabb(visual: VisualInstance3D) -> AABB:
	if visual is MeshInstance3D:
		var mi := visual as MeshInstance3D
		if mi.mesh == null:
			return AABB()
		return mi.global_transform * mi.mesh.get_aabb()
	if visual is MultiMeshInstance3D:
		var mm := visual as MultiMeshInstance3D
		if mm.multimesh == null or mm.multimesh.mesh == null:
			return AABB()
		var local := mm.multimesh.mesh.get_aabb()
		if mm.multimesh.instance_count > 0:
			var acc := mm.global_transform * (mm.multimesh.get_instance_transform(0) * local)
			for index in range(1, mm.multimesh.instance_count):
				acc = acc.merge(
					mm.global_transform * (mm.multimesh.get_instance_transform(index) * local)
				)
			return acc
		return mm.global_transform * local
	return AABB()


func _vec(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
