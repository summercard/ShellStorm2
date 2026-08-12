class_name MonsterVisionSystem3D
extends RefCounted
## 怪物视野的纯感知模块：距离、水平视锥与静态世界遮挡，绝不执行移动或攻击。

const DEFAULT_VISION_RANGE := 13.5
const DEFAULT_VISION_ANGLE_DEGREES := 120.0
const PROXIMITY_AWARENESS_RANGE := 4.8
const OCCLUSION_MASK := 1


func find_visible_player(
	enemy: CharacterBody3D,
	candidates: Array[Node],
	vision_range := DEFAULT_VISION_RANGE,
	vision_angle_degrees := DEFAULT_VISION_ANGLE_DEGREES
) -> Dictionary:
	var best: Node3D
	var best_distance := INF
	for candidate in candidates:
		if not candidate is Node3D or not is_instance_valid(candidate):
			continue
		var player := candidate as Node3D
		if float(player.get("current_hp")) <= 0.0:
			continue
		var result := evaluate_target(enemy, player, vision_range, vision_angle_degrees)
		if not bool(result.get("visible", false)):
			continue
		var distance := float(result.get("distance", INF))
		if distance < best_distance:
			best = player
			best_distance = distance
	if best == null:
		return {
			"visible": false,
			"target_instance_id": 0,
			"distance": INF,
			"line_of_sight": false,
			"inside_view_cone": false,
		}
	return evaluate_target(enemy, best, vision_range, vision_angle_degrees)


func evaluate_target(
	enemy: CharacterBody3D,
	target: Node3D,
	vision_range := DEFAULT_VISION_RANGE,
	vision_angle_degrees := DEFAULT_VISION_ANGLE_DEGREES
) -> Dictionary:
	if not is_instance_valid(enemy) or not is_instance_valid(target):
		return {"visible": false}
	var offset := target.global_position - enemy.global_position
	offset.y = 0.0
	var distance := offset.length()
	if distance > vision_range:
		return {
			"visible": false, "distance": distance,
			"inside_view_cone": false, "line_of_sight": false,
			"target_instance_id": target.get_instance_id(),
		}
	var forward := -enemy.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var direction := offset.normalized() if distance > 0.001 else forward
	var minimum_dot := cos(deg_to_rad(vision_angle_degrees * 0.5))
	# 近距离使用360°听觉/存在感知，但仍必须通过墙体视线；较远才使用前向视锥。
	var inside_view_cone := distance <= PROXIMITY_AWARENESS_RANGE or forward.dot(direction) >= minimum_dot
	if not inside_view_cone:
		return {
			"visible": false, "distance": distance,
			"inside_view_cone": false, "line_of_sight": false,
			"target_instance_id": target.get_instance_id(),
		}
	var line_of_sight := _has_line_of_sight(enemy, target)
	return {
		"visible": line_of_sight,
		"distance": distance,
		"inside_view_cone": true,
		"line_of_sight": line_of_sight,
		"target_instance_id": target.get_instance_id(),
		"target_position": target.global_position,
	}


func _has_line_of_sight(enemy: CharacterBody3D, target: Node3D) -> bool:
	var from := enemy.global_position + Vector3.UP * 0.72
	var target_points := [
		target.global_position + Vector3.UP * 0.45,
		target.global_position + Vector3.UP * 0.82,
		target.global_position + Vector3.UP * 1.18,
	]
	for to in target_points:
		var query := PhysicsRayQueryParameters3D.create(from, to, OCCLUSION_MASK, [enemy.get_rid()])
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := enemy.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return true
		var collider := hit.get("collider") as Node
		if collider == target or (collider != null and target.is_ancestor_of(collider)):
			return true
	return false
