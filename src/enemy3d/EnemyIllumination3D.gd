class_name EnemyIllumination3D
extends RefCounted
## 敌人三态受光传感器。只读取显式登记的真实 3D 光源，并使用物理射线确认投影遮挡。

signal illumination_state_changed(previous: String, current: String, context: Dictionary)

const STATE_DARKNESS := "darkness"
const STATE_ARTIFICIAL_LIGHT := "artificial_light"
const STATE_SUNLIGHT := "sunlight"
const VALID_STATES := [STATE_DARKNESS, STATE_ARTIFICIAL_LIGHT, STATE_SUNLIGHT]
const SUN_GROUP := &"gameplay_sun_3d"
const LOCAL_LIGHT_GROUP := &"gameplay_local_light_3d"
const RECEIVER_GROUP := &"enemy_3d"
const WORLD_RENDER_LAYER := 1

var sample_interval := 0.12
var sunlight_ray_length := 1000.0
var minimum_light_contribution := 0.035
var maximum_local_raycasts := 4
var occlusion_mask := 1

var illumination_state := STATE_DARKNESS
var sun_exposure_ratio := 0.0
var artificial_light_contribution := 0.0
var dominant_light_instance_id := 0
var dominant_light_kind := "none"
var last_sample_world_position := Vector3.ZERO
var last_sun_raycast_count := 0
var last_local_raycast_count := 0

var _enemy: CharacterBody3D
var _accumulator := 0.0
var _candidate_state := STATE_DARKNESS
var _candidate_count := 0
var _sun_lights: Array[DirectionalLight3D] = []
var _local_lights: Array[Light3D] = []
var _cache_age := INF


func configure(enemy: CharacterBody3D) -> void:
	_enemy = enemy
	# 依据实例错峰，避免同一帧集中对所有怪物执行物理射线。
	_accumulator = float(get_instance_id() % 97) / 97.0 * sample_interval


func tick(delta: float) -> void:
	if not is_instance_valid(_enemy) or not _enemy.is_inside_tree():
		return
	if str(_enemy.get("ai_state")) == "dead":
		return
	_accumulator += delta
	_cache_age += delta
	if _accumulator < sample_interval:
		return
	_accumulator = fmod(_accumulator, sample_interval)
	_sample_and_submit(false)


func force_refresh(commit_immediately := true) -> void:
	if not is_instance_valid(_enemy) or not _enemy.is_inside_tree():
		return
	_refresh_light_cache()
	_sample_and_submit(commit_immediately)


func get_snapshot() -> Dictionary:
	return {
		"illumination_state": illumination_state,
		"valid_illumination_states": VALID_STATES.duplicate(),
		"sun_exposure_ratio": sun_exposure_ratio,
		"artificial_light_contribution": artificial_light_contribution,
		"dominant_light_instance_id": dominant_light_instance_id,
		"dominant_light_kind": dominant_light_kind,
		"last_sample_world_position": last_sample_world_position,
		"last_sun_raycast_count": last_sun_raycast_count,
		"last_local_raycast_count": last_local_raycast_count,
		"sun_light_count": _sun_lights.size(),
		"local_light_count": _local_lights.size(),
		"sample_interval": sample_interval,
	}


func find_nearby_dark_position(radius: float, candidate_count: int) -> Vector3:
	if not is_instance_valid(_enemy) or not _enemy.is_inside_tree():
		return Vector3.ZERO
	if _cache_age >= 1.0:
		_refresh_light_cache()
	var saved_sun_rays := last_sun_raycast_count
	var saved_local_rays := last_local_raycast_count
	var start_angle := float(_enemy.get_instance_id() % 29) / 29.0 * TAU
	var count := clampi(candidate_count, 4, 12)
	for index in range(count):
		var angle := start_angle + TAU * float(index) / float(count)
		var candidate := _enemy.global_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
		if not _ray_is_clear(
			_enemy.global_position + Vector3.UP * 0.45,
			candidate + Vector3.UP * 0.45
		):
			continue
		var samples: Array[Vector3] = [
			candidate + Vector3.UP * 0.22,
			candidate + Vector3.UP * 0.68,
			candidate + Vector3.UP * 1.12,
		]
		var result := _evaluate(samples)
		if str(result.get("state", STATE_DARKNESS)) == STATE_DARKNESS:
			last_sun_raycast_count = saved_sun_rays
			last_local_raycast_count = saved_local_rays
			return candidate
	last_sun_raycast_count = saved_sun_rays
	last_local_raycast_count = saved_local_rays
	return Vector3.ZERO


func _sample_and_submit(commit_immediately: bool) -> void:
	if _cache_age >= 1.0:
		_refresh_light_cache()
	var samples := _body_sample_points()
	last_sample_world_position = samples[1]
	var result := _evaluate(samples)
	sun_exposure_ratio = float(result.get("sun_exposure_ratio", 0.0))
	artificial_light_contribution = float(result.get("artificial_light_contribution", 0.0))
	dominant_light_instance_id = int(result.get("dominant_light_instance_id", 0))
	dominant_light_kind = str(result.get("dominant_light_kind", "none"))
	_submit_state(str(result.get("state", STATE_DARKNESS)), commit_immediately)


func _evaluate(samples: Array[Vector3]) -> Dictionary:
	last_sun_raycast_count = 0
	last_local_raycast_count = 0
	var sun_result := _evaluate_sunlight(samples)
	if float(sun_result.get("ratio", 0.0)) > 0.0:
		return {
			"state": STATE_SUNLIGHT,
			"sun_exposure_ratio": sun_result["ratio"],
			"artificial_light_contribution": 0.0,
			"dominant_light_instance_id": sun_result["instance_id"],
			"dominant_light_kind": "sun",
		}
	var local_result := _evaluate_local_lights(samples)
	var contribution := float(local_result.get("contribution", 0.0))
	if contribution >= minimum_light_contribution:
		return {
			"state": STATE_ARTIFICIAL_LIGHT,
			"sun_exposure_ratio": 0.0,
			"artificial_light_contribution": contribution,
			"dominant_light_instance_id": local_result["instance_id"],
			"dominant_light_kind": local_result["kind"],
		}
	return {
		"state": STATE_DARKNESS,
		"sun_exposure_ratio": 0.0,
		"artificial_light_contribution": 0.0,
		"dominant_light_instance_id": 0,
		"dominant_light_kind": "none",
	}


func _evaluate_sunlight(samples: Array[Vector3]) -> Dictionary:
	for sun in _sun_lights:
		if not _is_active_light(sun):
			continue
		var toward_sun := sun.global_transform.basis.z.normalized()
		if toward_sun.is_zero_approx():
			continue
		var exposed := 0
		for sample in samples:
			last_sun_raycast_count += 1
			if _ray_is_clear(sample, sample + toward_sun * sunlight_ray_length):
				exposed += 1
		if exposed > 0:
			return {
				"ratio": float(exposed) / float(samples.size()),
				"instance_id": sun.get_instance_id(),
			}
	return {"ratio": 0.0, "instance_id": 0}


func _evaluate_local_lights(samples: Array[Vector3]) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for light in _local_lights:
		if not _is_active_light(light):
			continue
		for sample in samples:
			var contribution := _theoretical_contribution(light, sample)
			if contribution < minimum_light_contribution:
				continue
			candidates.append({
				"light": light,
				"sample": sample,
				"contribution": contribution,
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["contribution"]) > float(b["contribution"])
	)
	var raycast_count := mini(candidates.size(), maximum_local_raycasts)
	for index in range(raycast_count):
		var candidate := candidates[index]
		var light := candidate["light"] as Light3D
		last_local_raycast_count += 1
		if light == null or not _ray_is_clear(candidate["sample"], light.global_position):
			continue
		return {
			"contribution": candidate["contribution"],
			"instance_id": light.get_instance_id(),
			"kind": str(light.get_meta("gameplay_light_kind", _light_kind(light))),
		}
	return {"contribution": 0.0, "instance_id": 0, "kind": "none"}


func _theoretical_contribution(light: Light3D, sample: Vector3) -> float:
	var offset := sample - light.global_position
	var distance := offset.length()
	if light is OmniLight3D:
		var omni := light as OmniLight3D
		if distance >= omni.omni_range or omni.omni_range <= 0.0:
			return 0.0
		var remaining := clampf(1.0 - distance / omni.omni_range, 0.0, 1.0)
		return omni.light_energy * pow(remaining, maxf(0.1, omni.omni_attenuation))
	if light is SpotLight3D:
		var spot := light as SpotLight3D
		if distance >= spot.spot_range or spot.spot_range <= 0.0 or distance <= 0.001:
			return 0.0
		var beam_direction := -spot.global_transform.basis.z.normalized()
		var alignment := beam_direction.dot(offset / distance)
		var outer_cos := cos(deg_to_rad(spot.spot_angle))
		if alignment <= outer_cos:
			return 0.0
		var angular := clampf((alignment - outer_cos) / maxf(0.0001, 1.0 - outer_cos), 0.0, 1.0)
		angular = pow(angular, maxf(0.1, spot.spot_angle_attenuation))
		var remaining := clampf(1.0 - distance / spot.spot_range, 0.0, 1.0)
		return spot.light_energy * pow(remaining, maxf(0.1, spot.spot_attenuation)) * angular
	return 0.0


func _is_active_light(light: Light3D) -> bool:
	return (
		is_instance_valid(light)
		and light.is_inside_tree()
		and light.is_visible_in_tree()
		and light.light_energy > 0.001
		and (light.light_cull_mask & WORLD_RENDER_LAYER) != 0
	)


func _ray_is_clear(from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) <= 0.0001:
		return true
	var exclude: Array[RID] = []
	if is_instance_valid(_enemy):
		exclude.append(_enemy.get_rid())
	var direction := (to - from).normalized()
	var query := PhysicsRayQueryParameters3D.create(
		from + direction * 0.025,
		to - direction * 0.025,
		occlusion_mask,
		exclude
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return _enemy.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _body_sample_points() -> Array[Vector3]:
	var height := 1.2 * absf(_enemy.global_transform.basis.y.length())
	var shape_node := _enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node != null:
		if shape_node.shape is CylinderShape3D:
			height = (shape_node.shape as CylinderShape3D).height * absf(_enemy.global_transform.basis.y.length())
		elif shape_node.shape is CapsuleShape3D:
			height = (shape_node.shape as CapsuleShape3D).height * absf(_enemy.global_transform.basis.y.length())
	var base := _enemy.global_position
	return [
		base + Vector3.UP * height * 0.18,
		base + Vector3.UP * height * 0.52,
		base + Vector3.UP * height * 0.86,
	]


func _submit_state(next_state: String, commit_immediately: bool) -> void:
	if not VALID_STATES.has(next_state):
		next_state = STATE_DARKNESS
	if commit_immediately:
		_candidate_state = next_state
		_candidate_count = 2
		_commit_state(next_state)
		return
	if next_state != _candidate_state:
		_candidate_state = next_state
		_candidate_count = 1
		return
	_candidate_count += 1
	if _candidate_count >= 2:
		_commit_state(next_state)


func _commit_state(next_state: String) -> void:
	if illumination_state == next_state:
		return
	var previous := illumination_state
	illumination_state = next_state
	illumination_state_changed.emit(previous, next_state, get_snapshot())


func _refresh_light_cache() -> void:
	_sun_lights.clear()
	_local_lights.clear()
	for node in _enemy.get_tree().get_nodes_in_group(SUN_GROUP):
		if node is DirectionalLight3D:
			_sun_lights.append(node as DirectionalLight3D)
	for node in _enemy.get_tree().get_nodes_in_group(LOCAL_LIGHT_GROUP):
		if node is Light3D and not node is DirectionalLight3D:
			_local_lights.append(node as Light3D)
	_cache_age = 0.0


func _light_kind(light: Light3D) -> String:
	if light is SpotLight3D:
		return "spot"
	if light is OmniLight3D:
		return "omni"
	return "none"
