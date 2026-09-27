extends Node3D
## 诊断 v2（只读）：刷出来的怪「看得见但打不到」到底差在哪一层。
## 对每只怪输出：可见包络 AABB、碰撞包络 AABB（世界空间）、
## 八个方向 × 七个高度（同一高度水平射线）的可命中集合，以及自身 shape 查询结果。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 700000
const RAY_DISTANCE := 3.6
const HEIGHTS: Array[float] = [0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 1.75]

var tower: TowerDescent3D
var unhittable := 0
var total := 0
var not_in_space := 0


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(10)
	var ids: Array = tower._room_by_id.keys()
	ids.sort()
	for id_value in ids:
		var room := tower._room_by_id[id_value] as DungeonRoom3D
		if room != null:
			await _inspect_room(room)
	print("HITTABLE2_SUMMARY enemies=%d unhittable=%d not_in_space=%d" % [total, unhittable, not_in_space])
	print("ENEMY_HITTABLE2_PROBE_DONE")
	get_tree().quit(0)


func _inspect_room(room: DungeonRoom3D) -> void:
	tower.force_enter_room_for_test(room.room_id)
	if tower.player != null:
		tower.player.global_position = room.global_position + Vector3(0.0, 0.10, 0.0)
	await _settle(4)
	var live: Array[Enemy3D] = []
	for value in tower._enemy_nodes_by_room.get(room.room_id, []):
		var enemy := value as Enemy3D
		if enemy != null and is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			live.append(enemy)
	for enemy in live:
		total += 1
		var local := room.to_local(enemy.global_position)
		var visual := _visual_aabb(enemy)
		var collider := _collider_aabb(enemy)
		var hits_by_height: Array[String] = []
		var blocked := 0
		for height in HEIGHTS:
			var hit_any := false
			for dir_index in 8:
				var angle := TAU * float(dir_index) / 8.0
				var origin := enemy.global_position + Vector3(cos(angle), 0.0, sin(angle)) * RAY_DISTANCE + Vector3(0.0, height, 0.0)
				var target := enemy.global_position + Vector3(0.0, height, 0.0)
				var hit := _ray(origin, target)
				if hit.get("collider") == enemy:
					hit_any = true
					break
				if not hit.is_empty():
					blocked += 1
			if hit_any:
				hits_by_height.append("%.2f" % height)
		var self_hits := _self_query(enemy)
		if self_hits == 0:
			not_in_space += 1
		if hits_by_height.is_empty():
			unhittable += 1
		print("E2 room=%s kind=%s scale=%.2f local=(%.1f,%.2f,%.1f) visual_y=[%.2f,%.2f] collider_y=[%.2f,%.2f] hit_heights=[%s] blocked_rays=%d self_hits=%d state=%s active=%s visible=%s" % [
			room.room_id, enemy.enemy_kind, enemy.scale.y, local.x, local.y, local.z,
			visual.position.y, visual.end.y, collider.position.y, collider.end.y,
			",".join(hits_by_height), blocked, self_hits, enemy.ai_state,
			str(enemy.is_runtime_ai_active()), str(enemy.visible),
		])


func _visual_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var found := false
	for value in root.find_children("*", "VisualInstance3D", true, false):
		var node := value as VisualInstance3D
		if node is not MeshInstance3D:
			continue
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		acc = box if not found else acc.merge(box)
		found = true
	return acc


func _collider_aabb(enemy: Enemy3D) -> AABB:
	if enemy.collision_shape == null or enemy.collision_shape.shape == null:
		return AABB()
	var shape := enemy.collision_shape.shape
	var half := Vector3.ZERO
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		half = Vector3(cylinder.radius, cylinder.height * 0.5, cylinder.radius)
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		half = Vector3(capsule.radius, capsule.height * 0.5, capsule.radius)
	elif shape is BoxShape3D:
		half = (shape as BoxShape3D).size * 0.5
	var basis := enemy.collision_shape.global_transform
	var center := basis * Vector3.ZERO
	var extent := Vector3(
		absf(basis.basis.x.x) * half.x + absf(basis.basis.y.x) * half.y + absf(basis.basis.z.x) * half.z,
		absf(basis.basis.x.y) * half.x + absf(basis.basis.y.y) * half.y + absf(basis.basis.z.y) * half.z,
		absf(basis.basis.x.z) * half.x + absf(basis.basis.y.z) * half.y + absf(basis.basis.z.z) * half.z,
	)
	return AABB(center - extent, extent * 2.0)


func _self_query(enemy: Enemy3D) -> int:
	if enemy.collision_shape == null or enemy.collision_shape.shape == null:
		return -1
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = enemy.collision_shape.shape
	query.transform = enemy.collision_shape.global_transform
	query.collision_mask = 5
	query.collide_with_bodies = true
	var hits := get_world_3d().direct_space_state.intersect_shape(query, 16)
	return hits.size()


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 5
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_ray(query)


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
