class_name TowerDescent3D
extends Dungeon3D
## PH49 塔楼入口：楼顶、30m基地与98—95层探索区共用 Dungeon3D
## 战斗/命运/掉落管线；这里只定义垂直拓扑、电梯、五层流送、固定镜头
## 下方墙平滑抬升收拢、双端楼梯门、独立墙边电梯与全局固定环境光。

const FACILITY_SCENE: PackedScene = preload("res://assets/art/props/base_world_3d/prp_base_facility_root_top3d_v001.tscn")
const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
const FLOOR_STAGE_SCRIPT := preload("res://src/world3d/TowerFloorStage3D.gd")
const ATMOSPHERE_SCRIPT := preload("res://src/world3d/TowerAtmosphere3D.gd")
const TOWER_WALL_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_solid_5m_top3d_v001.glb"
)
const STAIR_GENERIC_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_descent_3d/components/env_tower_stairwell_generic_9m_top3d_v001.glb"
)
const STAIR_ROOFTOP_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_descent_3d/components/env_tower_stairwell_rooftop_9m_top3d_v001.glb"
)
const COMBAT_FLOOR_COUNT := 4
const FLOOR_HEIGHT := TOWER_GEOMETRY.FLOOR_HEIGHT_M
const STAIR_WIDTH := TOWER_GEOMETRY.PASSAGE_WIDTH_M
const STAIR_RUN := TOWER_GEOMETRY.RUN_LENGTH_M
const STAIR_LANE_SPACING := TOWER_GEOMETRY.LANE_CENTER_SPACING_M
const STAIR_GUARD_HEIGHT := TOWER_GEOMETRY.GUARD_HEIGHT_M
const CAMERA_HEIGHT_M := 8.0
# 镜头相对角色在无遮挡时的默认水平后移：tan(65°)=(8-0.45)/(trailing+0.75)
# ⇒ trailing ≈ 7.55/2.1445 - 0.75 ≈ 2.77m，对应从水平面算起 65° 俯视角。
const CAMERA_DEFAULT_TRAILING_M := 2.77
const CAMERA_LOOK_HEIGHT_M := 0.45
const CAMERA_LOOK_AHEAD_M := 0.75
const CAMERA_FOV_DEG := 55.0
const CAMERA_LOWER_WALL_PROBE_HEIGHT_M := 0.95
const CAMERA_LOWER_WALL_PROBE_START_M := 0.42
const CAMERA_LOWER_WALL_PROBE_LENGTH_M := 6.2
const CAMERA_LOWER_WALL_LIFT_MAX_M := 0.30
const CAMERA_LOWER_WALL_LIFT_BLEND_DISTANCE_M := 1.2
const CAMERA_LOWER_WALL_LIFT_RISE_RATE := 8.0
const CAMERA_LOWER_WALL_LIFT_FALL_RATE := 4.5
const CAMERA_LOWER_WALL_MIN_TRAILING_M := 0.15
const CAMERA_LOWER_WALL_RETRACT_RATE := 10.0
const CAMERA_LOWER_WALL_EXTEND_RATE := 4.5
const CAMERA_LOWER_WALL_MAX_RAY_HITS := 8
const CAMERA_NEAR_FADE_ALPHA := 0.06
const CAMERA_NEAR_FADE_MARGIN_M := 0.08
const CAMERA_NEAR_FADE_IN_RATE := 14.0
const CAMERA_NEAR_FADE_OUT_RATE := 7.0
const CAMERA_DOOR_BYPASS_HALF_WIDTH_M := 2.15
const CAMERA_DOOR_BYPASS_HALF_DEPTH_M := 0.90
const CAMERA_DOOR_BYPASS_HEIGHT_M := 2.0
const STAIR_ARRIVAL_INTERACTION_DISTANCE_M := 3.4
const CAMERA_OCCLUSION_RAY_OFFSETS := [
	Vector3.ZERO,
	Vector3(-0.48, 0.30, 0.0),
	Vector3(0.48, 0.30, 0.0),
	Vector3(0.0, 0.72, 0.0),
]
const CAMERA_OCCLUSION_MIN_BLOCKED_RAYS := 2

var _active_facility_menu: CanvasLayer = null
var _facility_nodes: Array[BaseFacility3D] = []
var _descent_side_sequence: Array[String] = []
var _edge_side_by_key: Dictionary = {}
var _edge_door_sides_by_key: Dictionary = {}
var _stair_surface_snap_count := 0
var _stair_support_surface_count := 0
var _declared_edges: Array[Dictionary] = []
var _edge_kind_by_key: Dictionary = {}
var _room_floor_index: Dictionary = {}
var _floor_room_ids: Dictionary = {}
var _floor_layout_templates: Dictionary = {}
var _floor_stages: Dictionary = {}
var _active_transition_edge := ""
var _transition_upper_floor := -1
var _transition_lower_floor := -1
var _transition_progress := 0.0
var _atmosphere: Node3D
var _unlocked_elevator_floors: Dictionary = {99: true}
var _elevator_overlay: Control
var _elevator_facility: BaseFacility3D
var _elevator_facilities_by_floor: Dictionary = {}
var _elevator_access_room_by_floor: Dictionary = {}
var _tower_floor_label: Label
var _tower_target_label: Label
var _tower_elevator_label: Label
var _tower_hp_bar: ProgressBar
var _loaded_floor_indices: Array[int] = []
var _player_occlusion_meshes: Array[GeometryInstance3D] = []
var _player_original_overlays: Dictionary = {}
var _player_occlusion_material: StandardMaterial3D
var _player_occluded := false
var _camera_blocked_ray_count := 0
var _camera_lower_wall_detected := false
var _camera_lower_wall_distance_m := -1.0
var _camera_lift_target_m := 0.0
var _camera_lift_current_m := 0.0
var _camera_trailing_target_m := CAMERA_DEFAULT_TRAILING_M
var _camera_trailing_current_m := CAMERA_DEFAULT_TRAILING_M
var _camera_near_fade_candidates: Array[MeshInstance3D] = []
var _camera_near_fade_states: Dictionary = {}
var _camera_near_faded_count := 0
var _camera_door_bypass_nodes: Array[RoomDoor3D] = []
var _camera_door_bypass_active := false
var _vertical_arrival_open: Dictionary = {}
var _stair_arrival_prompt_door: RoomDoor3D


func _ready() -> void:
	process_physics_priority = 100
	super()
	_build_floor_stages()
	player.global_position = Vector3(
		TOWER_GEOMETRY.CORE_CENTER_XZ.x - 20.0,
		0.05,
		TOWER_GEOMETRY.CORE_CENTER_XZ.y
	)
	# 镜头固定在9m层高内部的斜俯视位置；墙体和物件不再推动或旋转镜头。
	_apply_indoor_camera_pose()
	player.camera.fov = CAMERA_FOV_DEG
	_install_player_occlusion_silhouette()
	_install_facilities()
	_install_elevator_facility()
	_install_tower_hud()
	_install_atmosphere()
	title_label.text = "弹壳风暴2 · 向下爬楼行动"
	seed_label.text = "塔楼种子 %d" % run_seed
	status_label.text = "楼顶出生点 · 西侧特殊楼梯门通向设施层"
	_update_floor_visibility_state()
	_refresh_tower_hud()
	_refresh_facility_runtime()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("interact")
		and not _completed
		and _try_open_nearby_stair_arrival()
	):
		get_viewport().set_input_as_handled()
		return
	super(event)


func _process(delta: float) -> void:
	super(delta)
	_update_stair_arrival_prompt()


func _build_floor_stages() -> void:
	if not _floor_stages.is_empty():
		return
	var hole_sides_by_floor: Dictionary = {}
	for floor_index in range(COMBAT_FLOOR_COUNT + 2):
		hole_sides_by_floor[floor_index] = []
	for declaration in _declared_edges:
		if str(declaration.get("kind", "")) != "vertical":
			continue
		var upper_id := str(declaration["a"])
		var lower_id := str(declaration["b"])
		var side := str(declaration["side"])
		for floor_index in [
			int(_room_floor_index.get(upper_id, 0)),
			int(_room_floor_index.get(lower_id, 0)),
		]:
			if side not in (hole_sides_by_floor[floor_index] as Array):
				(hole_sides_by_floor[floor_index] as Array).append(side)
	for floor_index in range(COMBAT_FLOOR_COUNT + 2):
		var kind := "rooftop" if floor_index == 0 else "facility" if floor_index == 1 else "combat"
		var stage = FLOOR_STAGE_SCRIPT.new()
		var typed_hole_sides: Array[String] = []
		for hole_side in hole_sides_by_floor[floor_index]:
			typed_hole_sides.append(str(hole_side))
		stage.call("configure", floor_index, kind, typed_hole_sides)
		stage.position.y = -FLOOR_HEIGHT * float(floor_index)
		$GeneratedRooms.add_child(stage)
		_floor_stages[floor_index] = stage


func _update_floor_visibility_state() -> void:
	if _floor_stages.is_empty() or player == null:
		return
	var current_floor := int(_room_floor_index.get(
		_current_room_id,
		clampi(int(round(-player.global_position.y / FLOOR_HEIGHT)), 0, COMBAT_FLOOR_COUNT + 1)
	))
	var active_connector: Node3D = null
	var active_edge := ""
	for edge in _corridor_by_edge.keys():
		if str(_edge_kind_by_key.get(edge, "")) != "vertical":
			continue
		var connector := _corridor_by_edge[edge] as Node3D
		if connector != null and connector.visible and _is_player_on_connector(connector):
			active_connector = connector
			active_edge = str(edge)
			break
	_active_transition_edge = active_edge
	_transition_upper_floor = -1
	_transition_lower_floor = -1
	_transition_progress = 0.0
	if active_connector != null:
		_transition_upper_floor = int(active_connector.get_meta("upper_floor_index", current_floor))
		_transition_lower_floor = int(active_connector.get_meta("lower_floor_index", current_floor + 1))
		var upper_y := -FLOOR_HEIGHT * float(_transition_upper_floor)
		_transition_progress = clampf((upper_y - player.global_position.y) / FLOOR_HEIGHT, 0.0, 1.0)

	var stream_center := current_floor
	if active_connector != null:
		stream_center = (
			_transition_upper_floor
			if _transition_progress < 0.5
			else _transition_lower_floor
		)
	_loaded_floor_indices.clear()
	for candidate_index in range(COMBAT_FLOOR_COUNT + 2):
		if absi(candidate_index - stream_center) <= 2:
			_loaded_floor_indices.append(candidate_index)

	for floor_index in _floor_stages.keys():
		var stage = _floor_stages[floor_index]
		if stage == null:
			continue
		var stage_index := int(floor_index)
		var loaded := stage_index in _loaded_floor_indices
		stage.process_mode = (
			Node.PROCESS_MODE_INHERIT if loaded else Node.PROCESS_MODE_DISABLED
		)
		# 已加载物理层始终完整渲染。8m层内镜头、9m楼层与真实楼梯洞口
		# 负责遮挡；只有超出五层流送窗口时才整体关闭表现。
		stage.call("set_render_state", loaded, loaded)

	for room in _rooms:
		var room_floor := int(_room_floor_index.get(room.room_id, current_floor))
		var streamed := int(room.get_room_snapshot().get("stream_state", 0)) > 0
		var loaded := room_floor in _loaded_floor_indices
		if not loaded:
			room.visible = false
			room.process_mode = Node.PROCESS_MODE_DISABLED
			continue
		room.process_mode = (
			Node.PROCESS_MODE_INHERIT if streamed else Node.PROCESS_MODE_DISABLED
		)
		room.visible = streamed


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# PH46：只允许画面下方墙体驱动固定后方轴上的抬升收拢；禁止侧移与旋转。
	_update_camera_lower_wall_lift(delta)
	_apply_indoor_camera_pose()
	# PH49：墙体透明淡化会在摄像机碰撞时留下概率性消失状态。
	# 摄像机现在只沿固定轴缩短距离，墙材质永不被运行时改写。
	_update_floor_visibility_state()
	_update_camera_occlusion_silhouette()


func _apply_indoor_camera_pose() -> void:
	if player == null or player.camera == null:
		return
	player.camera.position = Vector3(
		0.0,
		CAMERA_HEIGHT_M + _camera_lift_current_m,
		_camera_trailing_current_m
	)
	var look_target := player.global_position + Vector3(
		0.0,
		CAMERA_LOOK_HEIGHT_M,
		-CAMERA_LOOK_AHEAD_M
	)
	player.camera.look_at(look_target, Vector3.UP)


func _update_camera_lower_wall_lift(delta: float) -> void:
	_camera_door_bypass_active = _is_player_in_camera_door_bypass()
	_camera_lower_wall_distance_m = (
		-1.0
		if _camera_door_bypass_active
		else _find_lower_camera_wall_distance()
	)
	_camera_lower_wall_detected = _camera_lower_wall_distance_m >= 0.0
	_camera_lift_target_m = 0.0
	_camera_trailing_target_m = CAMERA_DEFAULT_TRAILING_M
	if _camera_lower_wall_detected:
		var lift_ratio := clampf(
			(
				CAMERA_LOWER_WALL_PROBE_LENGTH_M
				- _camera_lower_wall_distance_m
			) / CAMERA_LOWER_WALL_LIFT_BLEND_DISTANCE_M,
			0.0,
			1.0
		)
		lift_ratio = smoothstep(0.0, 1.0, lift_ratio)
		_camera_lift_target_m = CAMERA_LOWER_WALL_LIFT_MAX_M * lift_ratio
		# 只退到墙内侧仍会让窄楼梯间的墙占满视锥。墙进入默认镜头通道后，
		# 直接沿固定后方轴收至角色正上方附近，保证整个视锥也回到墙内侧。
		if _camera_lower_wall_distance_m < CAMERA_DEFAULT_TRAILING_M:
			_camera_trailing_target_m = CAMERA_LOWER_WALL_MIN_TRAILING_M
	var response_rate := (
		CAMERA_LOWER_WALL_LIFT_RISE_RATE
		if _camera_lift_target_m > _camera_lift_current_m
		else CAMERA_LOWER_WALL_LIFT_FALL_RATE
	)
	if _camera_door_bypass_active:
		response_rate = 8.0
	var blend := 1.0 - exp(-response_rate * maxf(delta, 0.0))
	_camera_lift_current_m = lerpf(
		_camera_lift_current_m,
		_camera_lift_target_m,
		blend
	)
	if absf(_camera_lift_current_m - _camera_lift_target_m) <= 0.001:
		_camera_lift_current_m = _camera_lift_target_m
	var trailing_rate := (
		CAMERA_LOWER_WALL_RETRACT_RATE
		if _camera_trailing_target_m < _camera_trailing_current_m
		else CAMERA_LOWER_WALL_EXTEND_RATE
	)
	if _camera_door_bypass_active:
		trailing_rate = 8.0
	var trailing_blend := 1.0 - exp(-trailing_rate * maxf(delta, 0.0))
	_camera_trailing_current_m = lerpf(
		_camera_trailing_current_m,
		_camera_trailing_target_m,
		trailing_blend
	)
	if (
		absf(_camera_trailing_current_m - _camera_trailing_target_m)
		<= 0.001
	):
		_camera_trailing_current_m = _camera_trailing_target_m


func _find_lower_camera_wall_distance() -> float:
	if player == null or not player.is_inside_tree():
		return -1.0
	var trailing := player.global_basis.z
	trailing.y = 0.0
	if trailing.length_squared() <= 0.0001:
		trailing = Vector3.BACK
	trailing = trailing.normalized()
	var probe_origin := (
		player.global_position
		+ Vector3.UP * CAMERA_LOWER_WALL_PROBE_HEIGHT_M
		+ trailing * CAMERA_LOWER_WALL_PROBE_START_M
	)
	var probe_end := (
		player.global_position
		+ Vector3.UP * CAMERA_LOWER_WALL_PROBE_HEIGHT_M
		+ trailing * CAMERA_LOWER_WALL_PROBE_LENGTH_M
	)
	var ray_from := probe_origin
	var excluded: Array[RID] = []
	if player is CollisionObject3D:
		excluded.append((player as CollisionObject3D).get_rid())
	var space_state := get_world_3d().direct_space_state
	for _hit_index in range(CAMERA_LOWER_WALL_MAX_RAY_HITS):
		var query := PhysicsRayQueryParameters3D.create(
			ray_from,
			probe_end,
			1,
			excluded
		)
		query.collide_with_areas = false
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			return -1.0
		var collider := hit.get("collider") as Node
		var hit_position := hit.get("position", ray_from) as Vector3
		if _is_camera_lower_wall(collider):
			var planar_offset := hit_position - player.global_position
			planar_offset.y = 0.0
			return planar_offset.length()
		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())
		var remaining_direction := ray_from.direction_to(probe_end)
		if remaining_direction.is_zero_approx():
			return -1.0
		ray_from = hit_position + remaining_direction * 0.03
	return -1.0


func _is_camera_lower_wall(collider: Node) -> bool:
	if collider == null:
		return false
	if bool(collider.get_meta("camera_lower_wall", false)):
		return true
	var collider_name := str(collider.name)
	return (
		collider_name.begins_with("TowerWallCollision_")
		or collider_name.begins_with("BaseWall_")
		or collider_name == "FacilityBaseWallBody"
		or collider_name == "FacilityBaseWallSideBody"
		or collider_name == "FacilityBaseWallLintelBody"
		or collider_name.begins_with("CorridorWallCollision_")
		or collider_name.begins_with("StairwellWall_")
		or collider_name == "OuterBoundaryCollision"
		or (
			"EnclosureWall" in collider_name
			and "CollisionBody" in collider_name
		)
	)


func _install_camera_near_fade_candidates() -> void:
	_camera_near_fade_candidates.clear()
	_refresh_camera_door_bypass_nodes()
	for node in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var mesh_name := str(mesh_instance.name)
		if "EnclosureWall" in mesh_name:
			_camera_near_fade_candidates.append(mesh_instance)


func _refresh_camera_door_bypass_nodes() -> void:
	_camera_door_bypass_nodes.clear()
	for node in find_children("*", "RoomDoor3D", true, false):
		var door := node as RoomDoor3D
		if door != null:
			_camera_door_bypass_nodes.append(door)


func _is_player_in_camera_door_bypass() -> bool:
	if player == null:
		return false
	for door in _camera_door_bypass_nodes:
		if (
			not is_instance_valid(door)
			or not door.is_inside_tree()
			or not door.is_open
		):
			continue
		var local_offset := door.to_local(player.global_position)
		if (
			absf(local_offset.y) <= CAMERA_DOOR_BYPASS_HEIGHT_M
			and absf(local_offset.x) <= CAMERA_DOOR_BYPASS_HALF_WIDTH_M
			and absf(local_offset.z) <= CAMERA_DOOR_BYPASS_HALF_DEPTH_M
		):
			return true
	return false


func _update_camera_near_occluder_fade(delta: float) -> void:
	if player == null or player.camera == null:
		return
	var camera_position := player.camera.global_position
	var player_view_target := player.global_position + Vector3.UP * 0.75
	var active_candidates: Dictionary = {}
	if _camera_lower_wall_detected:
		for candidate in _camera_near_fade_candidates:
			if not is_instance_valid(candidate) or not candidate.visible:
				continue
			var global_aabb: AABB = candidate.global_transform * candidate.get_aabb()
			var expanded_aabb := global_aabb.grow(CAMERA_NEAR_FADE_MARGIN_M)
			if (
				expanded_aabb.has_point(camera_position)
				or expanded_aabb.intersects_segment(
					camera_position,
					player_view_target
				) != null
			):
				active_candidates[candidate] = true
				_ensure_camera_near_fade_state(candidate)
	var fading_meshes: Array = _camera_near_fade_states.keys()
	_camera_near_faded_count = 0
	for mesh_value in fading_meshes:
		var mesh_instance := mesh_value as MeshInstance3D
		if not is_instance_valid(mesh_instance):
			_camera_near_fade_states.erase(mesh_value)
			continue
		var state := _camera_near_fade_states.get(mesh_instance, {}) as Dictionary
		var active := bool(active_candidates.get(mesh_instance, false))
		var target_alpha := CAMERA_NEAR_FADE_ALPHA if active else 1.0
		var current_alpha := float(state.get("alpha", 1.0))
		var response_rate := (
			CAMERA_NEAR_FADE_IN_RATE if active else CAMERA_NEAR_FADE_OUT_RATE
		)
		var blend := 1.0 - exp(-response_rate * maxf(delta, 0.0))
		current_alpha = lerpf(current_alpha, target_alpha, blend)
		if absf(current_alpha - target_alpha) <= 0.002:
			current_alpha = target_alpha
		var fade_material := state.get("fade_material") as StandardMaterial3D
		if fade_material != null:
			var fade_color := fade_material.albedo_color
			fade_color.a = current_alpha
			fade_material.albedo_color = fade_color
		state["alpha"] = current_alpha
		_camera_near_fade_states[mesh_instance] = state
		if current_alpha < 0.95:
			_camera_near_faded_count += 1
		if not active and current_alpha >= 0.999:
			mesh_instance.material_override = state.get("original_override") as Material
			_camera_near_fade_states.erase(mesh_instance)


func _ensure_camera_near_fade_state(mesh_instance: MeshInstance3D) -> void:
	if _camera_near_fade_states.has(mesh_instance):
		return
	var original_override := mesh_instance.material_override
	var source_material := original_override as StandardMaterial3D
	if source_material == null and mesh_instance.mesh.get_surface_count() > 0:
		source_material = mesh_instance.get_active_material(0) as StandardMaterial3D
	var fade_material := (
		source_material.duplicate() as StandardMaterial3D
		if source_material != null
		else StandardMaterial3D.new()
	)
	if source_material == null:
		fade_material.albedo_color = Color(0.08, 0.10, 0.11, 1.0)
		fade_material.roughness = 0.72
	fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fade_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	mesh_instance.material_override = fade_material
	_camera_near_fade_states[mesh_instance] = {
		"original_override": original_override,
		"fade_material": fade_material,
		"alpha": 1.0,
	}


func _install_player_occlusion_silhouette() -> void:
	if player == null or player.avatar == null:
		return
	_player_occlusion_material = StandardMaterial3D.new()
	_player_occlusion_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_player_occlusion_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_occlusion_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_player_occlusion_material.albedo_color = Color(0.10, 0.88, 1.0, 0.52)
	_player_occlusion_material.emission_enabled = true
	_player_occlusion_material.emission = Color(0.04, 0.72, 1.0)
	_player_occlusion_material.emission_energy_multiplier = 1.8
	_player_occlusion_material.no_depth_test = true
	_player_occlusion_material.render_priority = 120
	for node in player.avatar.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if geometry == null:
			continue
		_player_occlusion_meshes.append(geometry)
		_player_original_overlays[geometry] = geometry.material_overlay


func _update_camera_occlusion_silhouette() -> void:
	if player == null or player.camera == null or not player.camera.is_inside_tree():
		_set_player_occlusion_silhouette(false)
		return
	var space_state := get_world_3d().direct_space_state
	var camera_origin := player.camera.global_position
	_camera_blocked_ray_count = 0
	var excluded: Array[RID] = []
	if player is CollisionObject3D:
		excluded.append((player as CollisionObject3D).get_rid())
	for target_offset in CAMERA_OCCLUSION_RAY_OFFSETS:
		var ray_to: Vector3 = (
			player.global_position
			+ Vector3(0.0, 0.72, 0.0)
			+ (target_offset as Vector3)
		)
		var query := PhysicsRayQueryParameters3D.create(
			camera_origin,
			ray_to,
			1,
			excluded
		)
		query.collide_with_areas = false
		if not space_state.intersect_ray(query).is_empty():
			_camera_blocked_ray_count += 1
	_set_player_occlusion_silhouette(
		_camera_blocked_ray_count >= CAMERA_OCCLUSION_MIN_BLOCKED_RAYS
	)


func _set_player_occlusion_silhouette(enabled: bool) -> void:
	if _player_occluded == enabled:
		return
	_player_occluded = enabled
	for geometry in _player_occlusion_meshes:
		if not is_instance_valid(geometry):
			continue
		geometry.material_overlay = (
			_player_occlusion_material
			if enabled
			else _player_original_overlays.get(geometry) as Material
		)


func _build_records() -> void:
	_records.clear()
	_descent_side_sequence.clear()
	_edge_side_by_key.clear()
	_edge_door_sides_by_key.clear()
	_declared_edges.clear()
	_edge_kind_by_key.clear()
	_room_floor_index.clear()
	_floor_room_ids.clear()
	_floor_layout_templates.clear()
	_vertical_arrival_open.clear()

	var core_center := Vector3(
		TOWER_GEOMETRY.CORE_CENTER_XZ.x,
		0.0,
		TOWER_GEOMETRY.CORE_CENTER_XZ.y
	)
	_append_tower_record(
		"start", "START", "rooftop", core_center, "", 0, "rooftop"
	)
	_append_tower_record(
		"facility", "FACILITY", "floor",
		core_center + Vector3.DOWN * FLOOR_HEIGHT,
		"start", 1, "facility", Vector2(30.0, 30.0)
	)
	_declare_edge("start", "facility", "vertical", "west", "west", "west")
	_descent_side_sequence.append("west")

	var layout_rng := RandomNumberGenerator.new()
	layout_rng.seed = run_seed ^ 0x544F5745
	var previous_exit_id := "facility"
	for floor_number in range(1, COMBAT_FLOOR_COUNT + 1):
		var physical_floor_index := floor_number + 1
		var floor_y := -FLOOR_HEIGHT * float(physical_floor_index)
		var specs := (
			_boss_floor_specs(floor_number)
			if floor_number == COMBAT_FLOOR_COUNT
			else _normal_floor_specs(floor_number, layout_rng)
		)
		_floor_layout_templates[physical_floor_index] = (
			"boss_90m_inward_entry"
			if floor_number == COMBAT_FLOOR_COUNT
			else "inward_arrival_ring_12_%s" % (
				"east_west" if floor_number % 2 == 1 else "west_east"
			)
		)
		var ids_by_key: Dictionary = {}
		for spec in specs:
			var spec_data := spec as Dictionary
			var id := str(spec_data["id"])
			ids_by_key[str(spec_data["key"])] = id
			var planar := spec_data["position"] as Vector2
			var parent_key := str(spec_data.get("parent_key", ""))
			var parent_id := previous_exit_id if parent_key.is_empty() else str(ids_by_key[parent_key])
			_append_tower_record(
				id,
				str(spec_data["type"]),
				"tower_cell",
				Vector3(planar.x, floor_y, planar.y),
				parent_id,
				physical_floor_index,
				str(spec_data["role"]),
				spec_data.get(
					"dimensions",
					Vector2(
						TOWER_GEOMETRY.COMBAT_ROOM_SIZE_M,
						TOWER_GEOMETRY.COMBAT_ROOM_SIZE_M
					)
				) as Vector2,
				spec_data.get("open_wall_directions", []) as Array
			)
		var entry_id := str(ids_by_key["entry"])
		var exit_id := str(ids_by_key["exit"])
		var stair_side := "east" if floor_number % 2 == 1 else "west"
		# PH49：上下两端都把房间放在核心内侧，因此同一楼梯的两扇门
		# 使用相同世界侧向；不再靠“反向门 + 房间刷在外侧”对齐。
		var upper_door_side := stair_side
		_declare_edge(
			previous_exit_id,
			entry_id,
			"vertical",
			stair_side,
			upper_door_side,
			stair_side
		)
		for spec in specs:
			var spec_data := spec as Dictionary
			var parent_key := str(spec_data.get("parent_key", ""))
			if parent_key.is_empty():
				continue
			_declare_edge(
				str(ids_by_key[parent_key]),
				str(spec_data["id"]),
				"horizontal"
			)
		_descent_side_sequence.append(stair_side)
		previous_exit_id = exit_id


func _normal_floor_specs(
	floor_number: int,
	layout_rng: RandomNumberGenerator
) -> Array[Dictionary]:
	var rotation_steps := 0 if floor_number % 2 == 1 else 2
	var positions := {
		# PH49：东侧楼梯下接口为(35, 2.5)，入口大厅在门的左侧/
		# 核心内侧，东门精确落在接口；不再把关卡刷到门外右侧。
		"entry": Vector2(27.5, 2.5),
		"hub": Vector2(27.5, -32.5),
		"main_02": Vector2(77.5, -32.5),
		"main_03": Vector2(77.5, -82.5),
		"main_04": Vector2(27.5, -82.5),
		"main_05": Vector2(-22.5, -82.5),
		"main_06": Vector2(-22.5, -32.5),
		# 15m出口大厅西门落在核心西接口(-30, 2.5)。
		"exit": Vector2(-22.5, 2.5),
		"branch_01": Vector2(77.5, 17.5),
		"branch_02": Vector2(77.5, 67.5),
		"branch_03": Vector2(27.5, 67.5),
		"elevator": Vector2(-22.5, 67.5),
	}
	var content_types: Array[String] = [
		"COMBAT", "COMBAT", "EVENT", "STORAGE", "SCAVENGE", "ELITE", "TRAP"
	]
	for shuffle_index in range(content_types.size() - 1, 0, -1):
		var swap_index := layout_rng.randi_range(0, shuffle_index)
		var temporary := content_types[shuffle_index]
		content_types[shuffle_index] = content_types[swap_index]
		content_types[swap_index] = temporary
	var raw_specs: Array[Dictionary] = [
		{
			"key": "entry", "id": "floor_%02d_entry" % floor_number,
			"type": "STAIR_LOBBY", "role": "stair_entry",
			"dimensions": Vector2(
				TOWER_GEOMETRY.COMBAT_STAIR_LOBBY_SIZE_M,
				TOWER_GEOMETRY.COMBAT_STAIR_LOBBY_SIZE_M
			),
		},
		{"key": "hub", "id": "floor_%02d_hub" % floor_number, "type": "COMBAT", "role": "hub", "parent_key": "entry"},
		{"key": "main_02", "id": "floor_%02d_main_02" % floor_number, "type": content_types[0], "role": "main", "parent_key": "hub"},
		{"key": "main_03", "id": "floor_%02d_main_03" % floor_number, "type": content_types[1], "role": "main", "parent_key": "main_02"},
		{"key": "main_04", "id": "floor_%02d_main_04" % floor_number, "type": content_types[2], "role": "main", "parent_key": "main_03"},
		{"key": "main_05", "id": "floor_%02d_main_05" % floor_number, "type": content_types[3], "role": "main", "parent_key": "main_04"},
		{"key": "main_06", "id": "floor_%02d_main_06" % floor_number, "type": content_types[4], "role": "main", "parent_key": "main_05"},
		{
			"key": "exit", "id": "floor_%02d_exit" % floor_number,
			"type": "STAIR_LOBBY", "role": "stair_exit", "parent_key": "main_06",
			"dimensions": Vector2(
				TOWER_GEOMETRY.COMBAT_STAIR_LOBBY_SIZE_M,
				TOWER_GEOMETRY.COMBAT_STAIR_LOBBY_SIZE_M
			),
		},
		{"key": "branch_01", "id": "floor_%02d_branch_01" % floor_number, "type": content_types[5], "role": "branch", "parent_key": "main_02"},
		{"key": "branch_02", "id": "floor_%02d_branch_02" % floor_number, "type": content_types[6], "role": "branch", "parent_key": "branch_01"},
		{"key": "branch_03", "id": "floor_%02d_branch_03" % floor_number, "type": "STORAGE", "role": "branch", "parent_key": "branch_02"},
		{"key": "elevator", "id": "floor_%02d_elevator" % floor_number, "type": "SCAVENGE", "role": "elevator_access", "parent_key": "branch_03"},
	]
	for spec in raw_specs:
		var key := str(spec["key"])
		if key == "entry":
			spec["open_wall_directions"] = [
				"north" if rotation_steps == 0 else "south"
			]
		elif key == "exit":
			spec["open_wall_directions"] = [
				"south" if rotation_steps == 0 else "north"
			]
		spec["position"] = _rotate_floor_point(positions[key] as Vector2, rotation_steps)
	return raw_specs


func _boss_floor_specs(floor_number: int) -> Array[Dictionary]:
	return [
		{
			"key": "entry", "id": "floor_%02d_entry" % floor_number,
			"type": "STAIR_LOBBY", "role": "stair_entry",
			"position": Vector2(-22.5, 2.5),
			"dimensions": Vector2(
				TOWER_GEOMETRY.COMBAT_STAIR_LOBBY_SIZE_M,
				TOWER_GEOMETRY.COMBAT_STAIR_LOBBY_SIZE_M
			),
			"open_wall_directions": ["north"],
		},
		{"key": "hub", "id": "floor_%02d_hub" % floor_number, "type": "ELITE", "role": "hub", "parent_key": "entry", "position": Vector2(-22.5, -32.5)},
		{"key": "main_02", "id": "floor_%02d_main_02" % floor_number, "type": "COMBAT", "role": "main", "parent_key": "hub", "position": Vector2(-72.5, -32.5)},
		{"key": "prep", "id": "floor_%02d_boss_prep" % floor_number, "type": "UPGRADE", "role": "boss_prep", "parent_key": "main_02", "position": Vector2(-72.5, 52.5)},
		{
			"key": "exit", "id": "extraction", "type": "BOSS", "role": "boss",
			"parent_key": "prep", "position": Vector2(27.5, 52.5),
			"dimensions": Vector2(
				TOWER_GEOMETRY.BOSS_ARENA_SIZE_M,
				TOWER_GEOMETRY.BOSS_ARENA_SIZE_M
			),
		},
		{"key": "branch_01", "id": "floor_%02d_branch_01" % floor_number, "type": "EVENT", "role": "branch", "parent_key": "hub", "position": Vector2(27.5, -32.5)},
		{"key": "branch_02", "id": "floor_%02d_branch_02" % floor_number, "type": "COMBAT", "role": "branch", "parent_key": "branch_01", "position": Vector2(77.5, -32.5)},
		{"key": "branch_03", "id": "floor_%02d_branch_03" % floor_number, "type": "STORAGE", "role": "branch", "parent_key": "branch_02", "position": Vector2(77.5, -82.5)},
		{"key": "branch_04", "id": "floor_%02d_branch_04" % floor_number, "type": "TRAP", "role": "branch", "parent_key": "branch_03", "position": Vector2(27.5, -82.5)},
		{"key": "elevator", "id": "floor_%02d_elevator" % floor_number, "type": "SCAVENGE", "role": "elevator_access", "parent_key": "branch_04", "position": Vector2(-22.5, -82.5)},
	]


func _append_tower_record(
	id: String,
	type_id: String,
	size: String,
	position: Vector3,
	parent: String,
	floor_index: int,
	role: String,
	dimensions := Vector2.ZERO,
	open_wall_directions: Array = []
) -> void:
	var record := _record(
		id, type_id, size, position, [], true, parent, _records.size(), -floor_index
	)
	record["custom_dimensions"] = (
		dimensions
		if dimensions.x > 0.0 and dimensions.y > 0.0
		else Vector2(TOWER_GEOMETRY.CORE_SIZE_M, TOWER_GEOMETRY.CORE_SIZE_M)
		if size in ["floor", "rooftop"]
		else Vector2(
			TOWER_GEOMETRY.COMBAT_ROOM_SIZE_M,
			TOWER_GEOMETRY.COMBAT_ROOM_SIZE_M
		)
	)
	record["tower_module_shell"] = true
	record["floor_index"] = floor_index
	record["tower_role"] = role
	record["open_wall_directions"] = open_wall_directions.duplicate()
	_records.append(record)
	_room_floor_index[id] = floor_index
	if not _floor_room_ids.has(floor_index):
		_floor_room_ids[floor_index] = []
	(_floor_room_ids[floor_index] as Array).append(id)


func _declare_edge(
	a: String,
	b: String,
	kind: String,
	side := "",
	a_door_side := "",
	b_door_side := ""
) -> void:
	var edge := _edge_key(a, b)
	_declared_edges.append({
		"a": a,
		"b": b,
		"kind": kind,
		"side": side,
		"a_door_side": a_door_side,
		"b_door_side": b_door_side,
	})
	_edge_kind_by_key[edge] = kind
	if kind == "vertical":
		_edge_side_by_key[edge] = side
		_edge_door_sides_by_key[edge] = {
			a: a_door_side if not a_door_side.is_empty() else side,
			b: b_door_side if not b_door_side.is_empty() else side,
		}


func _door_policy_for_edge(from_room_id: String, target_room_id: String) -> Dictionary:
	var edge := _edge_key(from_room_id, target_room_id)
	# 楼顶→99层和99层→98层属于固定交通接口：不检查清房、
	# 不消耗房间钥匙，也不弹命运卡，确保基地动线不会被局内经济锁死。
	if edge in [
		_edge_key("start", "facility"),
		_edge_key("facility", "floor_01_entry"),
	]:
		return {
			"requires_clear": false,
			"requires_key": false,
			"triggers_fate": false,
		}
	# 98层入口→第一战斗枢纽是本局第一次正式探索门：免费开启，
	# 但保留一次命运选择，建立“下楼—定本层构筑方向”的节奏。
	if edge == _edge_key("floor_01_entry", "floor_01_hub"):
		return {
			"requires_clear": true,
			"requires_key": false,
			"triggers_fate": true,
		}
	return super(from_room_id, target_room_id)


func _rotate_floor_point(point: Vector2, rotation_steps: int) -> Vector2:
	var center := TOWER_GEOMETRY.CORE_CENTER_XZ
	var result := point - center
	for _step in range(posmod(rotation_steps, 4)):
		result = Vector2(-result.y, result.x)
	return result + center


func _side_for_point(point: Vector2) -> String:
	if absf(point.x) >= absf(point.y):
		return "east" if point.x > 0.0 else "west"
	return "south" if point.y > 0.0 else "north"


func _build_topology() -> void:
	_room_neighbors.clear()
	_open_edges.clear()
	for record in _records:
		_room_neighbors[str(record["id"])] = []
	for declaration in _declared_edges:
		var parent_id := str(declaration["a"])
		var child_id := str(declaration["b"])
		var edge := _edge_key(parent_id, child_id)
		var parent := _find_record(parent_id)
		var child := _find_record(child_id)
		(_room_neighbors[parent_id] as Array).append(child_id)
		(_room_neighbors[child_id] as Array).append(parent_id)
		_open_edges[edge] = false
		if str(declaration["kind"]) == "vertical":
			_vertical_arrival_open[edge] = false
			var parent_side := str(declaration.get("a_door_side", declaration["side"]))
			var child_side := str(declaration.get("b_door_side", declaration["side"]))
			(parent["doors"] as Array).append(parent_side)
			(child["doors"] as Array).append(child_side)
			(parent["door_targets"] as Dictionary)[parent_side] = child_id
			(child["door_targets"] as Dictionary)[child_side] = parent_id
		else:
			var parent_direction := _direction_between(
				parent["position"] as Vector3,
				child["position"] as Vector3
			)
			var child_direction := _opposite_direction(parent_direction)
			(parent["doors"] as Array).append(parent_direction)
			(child["doors"] as Array).append(child_direction)
			(parent["door_targets"] as Dictionary)[parent_direction] = child_id
			(child["door_targets"] as Dictionary)[child_direction] = parent_id


func _build_corridor(from_room: DungeonRoom3D, to_room: DungeonRoom3D, index: int) -> void:
	var edge := _edge_key(from_room.room_id, to_room.room_id)
	if str(_edge_kind_by_key.get(edge, "horizontal")) != "vertical":
		_build_tower_horizontal_corridor(from_room, to_room, index, edge)
		return
	var side := str(_edge_side_by_key.get(edge, "west"))
	var outward := {
		"north": Vector3(0, 0, -1),
		"south": Vector3(0, 0, 1),
		"west": Vector3(-1, 0, 0),
		"east": Vector3(1, 0, 0),
	}.get(side, Vector3(-1, 0, 0)) as Vector3
	# Blender 资产默认 local +X 朝核心外侧，Blender +Y 导入 Godot 后
	# 对应 local -Z，因此第二轴取 outward 的顺时针正交方向。
	var tangent := Vector3(outward.z, 0, -outward.x)
	var upper_y := from_room.global_position.y
	var lower_y := to_room.global_position.y
	var door_sides := _edge_door_sides_by_key.get(edge, {}) as Dictionary
	var upper_door_side := str(door_sides.get(from_room.room_id, side))
	var lower_door_side := str(door_sides.get(to_room.room_id, side))
	var upper_door := _room_door_world_position(from_room, upper_door_side)
	var lower_door := _room_door_world_position(to_room, lower_door_side)
	var core_center := Vector3(
		TOWER_GEOMETRY.CORE_CENTER_XZ.x,
		0.0,
		TOWER_GEOMETRY.CORE_CENTER_XZ.y
	)
	var upper_interface := (
		core_center
		+ outward * (TOWER_GEOMETRY.CORE_SIZE_M * 0.5)
		+ Vector3.UP * upper_y
	)
	var lower_interface := (
		core_center
		+ outward * (TOWER_GEOMETRY.CORE_SIZE_M * 0.5)
		+ Vector3.UP * lower_y
	)
	var upper_lane := (
		upper_interface
		+ outward * TOWER_GEOMETRY.STAIR_UPPER_LANE_OFFSET_M
	)
	var lower_lane := (
		upper_interface
		+ outward * TOWER_GEOMETRY.STAIR_LOWER_LANE_OFFSET_M
	)
	var middle_y := upper_y - FLOOR_HEIGHT * 0.5
	# 十一节点严格沿 Blender v006 可行走面中心线：上层门厅进入
	# 11.501m 外侧梯跑，15m 下行至半层，经过8m折角平台后由
	# 3.501m 内侧梯跑回到下层门厅；房间门在核心内侧时再由模块地砖补齐。
	var points: Array[Vector3] = [
		upper_door,
		upper_interface,
		upper_lane + tangent * TOWER_GEOMETRY.STAIR_RUN_START_M,
		upper_lane + tangent * TOWER_GEOMETRY.STAIR_RUN_END_M + Vector3.UP * (middle_y - upper_y),
		upper_lane + tangent * TOWER_GEOMETRY.STAIR_TURN_CENTER_M + Vector3.UP * (middle_y - upper_y),
		lower_lane + tangent * TOWER_GEOMETRY.STAIR_TURN_CENTER_M + Vector3.UP * (middle_y - upper_y),
		lower_lane + tangent * TOWER_GEOMETRY.STAIR_RUN_END_M + Vector3.UP * (middle_y - upper_y),
		lower_lane + tangent * TOWER_GEOMETRY.STAIR_RUN_START_M + Vector3.UP * (lower_y - upper_y),
		lower_lane + Vector3.UP * (lower_y - upper_y),
		lower_interface,
		lower_door,
	]
	var connector := Node3D.new()
	connector.name = "TowerStairwell_%02d" % index
	connector.set_meta("is_vertical_connector", true)
	connector.set_meta("from_room_id", from_room.room_id)
	connector.set_meta("to_room_id", to_room.room_id)
	connector.set_meta("upper_floor_index", int(_room_floor_index.get(from_room.room_id, 0)))
	connector.set_meta("lower_floor_index", int(_room_floor_index.get(to_room.room_id, 1)))
	connector.set_meta("height_delta", lower_y - upper_y)
	connector.set_meta("side", side)
	connector.set_meta("upper_door_side", upper_door_side)
	connector.set_meta("lower_door_side", lower_door_side)
	connector.set_meta("path_points", points)
	connector.set_meta("lane_spacing", STAIR_LANE_SPACING)
	connector.set_meta("guard_height", STAIR_GUARD_HEIGHT)
	connector.set_meta("passage_width", STAIR_WIDTH)
	connector.set_meta("approach_outset", TOWER_GEOMETRY.APPROACH_OUTSET_M)
	connector.set_meta("guard_end_clearance", TOWER_GEOMETRY.GUARD_END_CLEARANCE_M)
	connector.set_meta("outward", outward)
	connector.set_meta("upper_door_position", upper_door)
	connector.set_meta("lower_door_position", lower_door)
	var rooftop_variant := from_room.room_id == "start"
	connector.set_meta(
		"stair_asset_id",
		"ENV-TOWER-STAIRWELL-ROOFTOP-9M"
		if rooftop_variant
		else "ENV-TOWER-STAIRWELL-GENERIC-9M"
	)
	connector.set_meta("uses_blender_stairwell_visual", true)
	connector.visible = false
	connector.process_mode = Node.PROCESS_MODE_DISABLED
	$GeneratedCorridors.add_child(connector)
	_corridor_by_edge[edge] = connector
	_add_imported_stairwell_visual(
		connector,
		upper_interface,
		outward,
		rooftop_variant
	)
	for point_index in range(points.size() - 1):
		_add_stair_segment(
			connector,
			points[point_index],
			points[point_index + 1],
			point_index
		)
	_build_stairwell_enclosure(connector, points, outward, lower_y)


func _add_imported_stairwell_visual(
	connector: Node3D,
	upper_interface: Vector3,
	outward: Vector3,
	rooftop_variant: bool
) -> void:
	var packed := STAIR_ROOFTOP_SCENE if rooftop_variant else STAIR_GENERIC_SCENE
	var visual := packed.instantiate() as Node3D
	visual.name = (
		"ImportedStairwellRooftop9M"
		if rooftop_variant
		else "ImportedStairwellGeneric9M"
	)
	visual.position = upper_interface
	# 默认 local +X；旋转后精确朝向 north/south/east/west 任一核心边。
	visual.rotation.y = atan2(-outward.z, outward.x)
	visual.set_meta(
		"asset_id",
		"ENV-TOWER-STAIRWELL-ROOFTOP-9M"
		if rooftop_variant
		else "ENV-TOWER-STAIRWELL-GENERIC-9M"
	)
	visual.set_meta("blender_source_version", "v006")
	connector.add_child(visual)
	var walkable_collision_count := _add_imported_stair_collisions(visual)
	connector.set_meta("walkable_collision_count", walkable_collision_count)
	_stair_support_surface_count += walkable_collision_count


func _add_imported_stair_collisions(root: Node) -> int:
	var walkable_count := 0
	# 门侧、远端、外侧三面围护由规则盒体统一承担。Blender还包含一块
	# 带门厅缺口的内侧墙，只为这块恢复同形碰撞；若把四块导入墙全部
	# 转为三角网格，门侧整墙会再次封死上下层出口。
	var is_walkable := root is MeshInstance3D and "Walkable" in root.name
	var is_inner_wall := (
		root is MeshInstance3D
		and "EnclosureWall_Inner" in root.name
	)
	if is_walkable or is_inner_wall:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh != null:
			var shape := mesh_instance.mesh.create_trimesh_shape()
			if shape != null:
				var body := StaticBody3D.new()
				body.name = "%sCollisionBody" % mesh_instance.name
				body.collision_layer = 1
				body.collision_mask = 0
				mesh_instance.add_child(body)
				var collision := CollisionShape3D.new()
				collision.name = "%sCollisionShape" % mesh_instance.name
				collision.shape = shape
				collision.disabled = true
				collision.set_meta("persistent_stair_support", is_walkable)
				body.add_child(collision)
				if is_walkable:
					walkable_count += 1
	for child in root.get_children():
		walkable_count += _add_imported_stair_collisions(child)
	return walkable_count


func _room_door_world_position(room: DungeonRoom3D, side: String) -> Vector3:
	var outward := {
		"north": Vector3(0, 0, -1),
		"south": Vector3(0, 0, 1),
		"west": Vector3(-1, 0, 0),
		"east": Vector3(1, 0, 0),
	}.get(side, Vector3(-1, 0, 0)) as Vector3
	var dimensions := room.get_dimensions()
	var half_extent := dimensions.y * 0.5 if side in ["north", "south"] else dimensions.x * 0.5
	return room.global_position + outward * half_extent


func _build_tower_horizontal_corridor(
	from_room: DungeonRoom3D,
	to_room: DungeonRoom3D,
	index: int,
	edge: String
) -> void:
	var delta := to_room.global_position - from_room.global_position
	var horizontal_x := absf(delta.x) >= absf(delta.z)
	var direction := Vector3(signf(delta.x), 0.0, 0.0) if horizontal_x else Vector3(0.0, 0.0, signf(delta.z))
	var from_half := from_room.get_dimensions().x * 0.5 if horizontal_x else from_room.get_dimensions().y * 0.5
	var to_half := to_room.get_dimensions().x * 0.5 if horizontal_x else to_room.get_dimensions().y * 0.5
	var start := from_room.global_position + direction * from_half
	var end := to_room.global_position - direction * to_half
	var center := (start + end) * 0.5
	var length := start.distance_to(end)
	var connector := Node3D.new()
	connector.name = "TowerRoomCorridor_%02d" % index
	connector.set_meta("is_vertical_connector", false)
	connector.set_meta("from_room_id", from_room.room_id)
	connector.set_meta("to_room_id", to_room.room_id)
	connector.set_meta("passage_width", TOWER_GEOMETRY.GRID_UNIT_M)
	connector.visible = false
	connector.process_mode = Node.PROCESS_MODE_DISABLED
	$GeneratedCorridors.add_child(connector)
	_corridor_by_edge[edge] = connector

	# 房间之间固定留一个5m走廊格；两侧使用导入的9m满高墙模块。
	var perpendicular := Vector3(0.0, 0.0, 1.0) if horizontal_x else Vector3(1.0, 0.0, 0.0)
	for side_sign in [-1.0, 1.0]:
		var wall := TOWER_WALL_SCENE.instantiate() as Node3D
		wall.name = "ImportedCorridorWall5M_%s" % ("L" if side_sign < 0.0 else "R")
		wall.position = center + perpendicular * side_sign * (TOWER_GEOMETRY.GRID_UNIT_M * 0.5)
		wall.rotation.y = 0.0 if horizontal_x else PI * 0.5
		wall.set_meta("asset_id", "ENV-TOWER-WALL-SOLID-5M")
		connector.add_child(wall)
		var wall_size := (
			Vector3(length, FLOOR_HEIGHT, 0.30)
			if horizontal_x
			else Vector3(0.30, FLOOR_HEIGHT, length)
		)
		_add_connector_box(
			connector,
			"CorridorWallCollision_%s" % ("L" if side_sign < 0.0 else "R"),
			center + perpendicular * side_sign * (TOWER_GEOMETRY.GRID_UNIT_M * 0.5) + Vector3.UP * (FLOOR_HEIGHT * 0.5),
			wall_size,
			Vector3.ZERO
		)


func _build_stairwell_enclosure(
	connector: Node3D,
	points: Array[Vector3],
	outward: Vector3,
	lower_y: float
) -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point in points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	var padding := STAIR_WIDTH * 0.5 + 0.18
	min_x -= padding
	max_x += padding
	min_z -= padding
	max_z += padding
	var center_y := lower_y + FLOOR_HEIGHT * 0.5
	if absf(outward.x) > 0.5:
		var lateral_z := [min_z, max_z]
		for wall_index in range(lateral_z.size()):
			var z := float(lateral_z[wall_index])
			_add_connector_box(
				connector,
				"StairwellWall_Lateral_%s" % ("A" if wall_index == 0 else "B"),
				Vector3((min_x + max_x) * 0.5, center_y, z),
				Vector3(max_x - min_x, FLOOR_HEIGHT, 0.30),
				Vector3.ZERO,
				false,
				true,
				true
			)
		var outer_x := max_x if outward.x > 0.0 else min_x
		_add_connector_box(
			connector,
			"StairwellWall_Outer",
			Vector3(outer_x, center_y, (min_z + max_z) * 0.5),
			Vector3(0.30, FLOOR_HEIGHT, max_z - min_z),
			Vector3.ZERO,
			false,
			true,
			true
		)
	else:
		var lateral_x := [min_x, max_x]
		for wall_index in range(lateral_x.size()):
			var x := float(lateral_x[wall_index])
			_add_connector_box(
				connector,
				"StairwellWall_Lateral_%s" % ("A" if wall_index == 0 else "B"),
				Vector3(x, center_y, (min_z + max_z) * 0.5),
				Vector3(0.30, FLOOR_HEIGHT, max_z - min_z),
				Vector3.ZERO,
				false,
				true,
				true
			)
		var outer_z := max_z if outward.z > 0.0 else min_z
		_add_connector_box(
			connector,
			"StairwellWall_Outer",
			Vector3((min_x + max_x) * 0.5, center_y, outer_z),
			Vector3(max_x - min_x, FLOOR_HEIGHT, 0.30),
			Vector3.ZERO,
			false,
			true,
			true
		)


func _add_stair_segment(
	root: Node3D,
	start: Vector3,
	end: Vector3,
	index: int
) -> void:
	var delta := end - start
	var along_x := absf(delta.x) >= absf(delta.z)
	var planar_length := absf(delta.x) if along_x else absf(delta.z)
	if planar_length <= 0.05:
		return
	var length := sqrt(planar_length * planar_length + delta.y * delta.y)
	var center := (start + end) * 0.5
	var rotation := Vector3.ZERO
	if along_x:
		rotation.z = atan(delta.y / delta.x) if absf(delta.x) > 0.01 else 0.0
	else:
		rotation.x = -atan(delta.y / delta.z) if absf(delta.z) > 0.01 else 0.0
	var surface_normal := Basis.from_euler(rotation) * Vector3.UP
	var sloped := absf(delta.y) > 0.05
	if sloped:
		# 可见台阶仍来自 Blender；程序层用有厚度的坡面楼板和两侧护栏。
		var perpendicular := Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)
		var guard_planar_length := maxf(
			0.4,
			planar_length - TOWER_GEOMETRY.GUARD_END_CLEARANCE_M * 2.0
		)
		var guard_length := length * guard_planar_length / planar_length
		for side_sign in [-1.0, 1.0]:
			var guard_center: Vector3 = (
				center
				+ perpendicular * side_sign * (STAIR_WIDTH * 0.5 + 0.12)
				+ surface_normal * (STAIR_GUARD_HEIGHT * 0.5)
			)
			var guard_size := (
				Vector3(guard_length, STAIR_GUARD_HEIGHT, 0.24)
				if along_x
				else Vector3(0.24, STAIR_GUARD_HEIGHT, guard_length)
			)
			_add_connector_box(
				root,
				"StairGuard_%02d" % index,
				guard_center,
				guard_size,
				rotation
			)


func _add_connector_box(
	root: Node3D,
	node_name: String,
	position: Vector3,
	size: Vector3,
	rotation: Vector3,
	is_support := false,
	collision_enabled := false,
	camera_lower_wall := false
) -> void:
	var body := StaticBody3D.new()
	body.name = "%sBody" % node_name
	body.position = position
	body.rotation = rotation
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = "%sShape" % node_name
	collision.shape = shape
	# 默认禁用（走廊墙/楼梯护栏/门楣都有视觉 prefab 自带碰撞），
	# 楼梯间 3 面围护墙需要射线命中以触发近墙摄像机抬高。
	collision.disabled = not collision_enabled
	collision.set_meta("persistent_stair_support", is_support)
	# 标记为始终启用的摄像机低墙：_set_connector_collision_enabled 会跳过它。
	collision.set_meta("camera_lower_wall", camera_lower_wall)
	body.add_child(collision)


func _is_player_on_connector(connector: Node3D) -> bool:
	var points: Array = connector.get_meta("path_points", [])
	if points.size() < 2:
		return false
	var lower_y := INF
	var upper_y := -INF
	for point_value in points:
		var point := point_value as Vector3
		lower_y = minf(lower_y, point.y)
		upper_y = maxf(upper_y, point.y)
	if player.global_position.y < lower_y - 0.7 or player.global_position.y > upper_y + 1.0:
		return false
	var player_planar := Vector2(player.global_position.x, player.global_position.z)
	for index in range(points.size() - 1):
		var start := points[index] as Vector3
		var end := points[index + 1] as Vector3
		var a := Vector2(start.x, start.z)
		var b := Vector2(end.x, end.z)
		var segment := b - a
		var length_squared := segment.length_squared()
		if length_squared <= 0.001:
			continue
		var ratio := clampf((player_planar - a).dot(segment) / length_squared, 0.0, 1.0)
		if player_planar.distance_to(a + segment * ratio) <= STAIR_WIDTH * 0.64:
			return true
	return false


func _refresh_edge_visuals(a: String, b: String, opened: bool) -> void:
	var edge := _edge_key(a, b)
	if str(_edge_kind_by_key.get(edge, "horizontal")) != "vertical":
		super(a, b, opened)
		return
	var connector := _corridor_by_edge.get(edge) as Node3D
	if connector == null:
		return
	var side := str(_edge_side_by_key.get(edge, "west"))
	var door_sides := _edge_door_sides_by_key.get(edge, {}) as Dictionary
	var upper_id := str(connector.get_meta("from_room_id", a))
	var lower_id := str(connector.get_meta("to_room_id", b))
	var upper_room := _room_by_id.get(upper_id) as DungeonRoom3D
	var lower_room := _room_by_id.get(lower_id) as DungeonRoom3D
	if upper_room == null or lower_room == null:
		return
	# 打开当前楼层的上端门只启用楼梯；下端门保持独立关闭，直到玩家
	# 真实走到下一层门槛并按E，避免在上层开门时远程跳过下一层入口。
	upper_room.set_door_open(
		str(door_sides.get(upper_id, side)),
		opened
	)
	lower_room.set_door_open(
		str(door_sides.get(lower_id, side)),
		opened and bool(_vertical_arrival_open.get(edge, false))
	)


func _find_nearby_stair_arrival() -> Dictionary:
	if player == null or _current_room_id.is_empty():
		return {}
	var nearest_distance := STAIR_ARRIVAL_INTERACTION_DISTANCE_M
	var nearest: Dictionary = {}
	for edge_value in _corridor_by_edge.keys():
		var edge := str(edge_value)
		var connector := _corridor_by_edge.get(edge) as Node3D
		if (
			connector == null
			or not bool(connector.get_meta("is_vertical_connector", false))
			or not bool(_open_edges.get(edge, false))
			or bool(_vertical_arrival_open.get(edge, false))
		):
			continue
		var upper_id := str(connector.get_meta("from_room_id", ""))
		var lower_id := str(connector.get_meta("to_room_id", ""))
		if _current_room_id != upper_id:
			continue
		var lower_room := _room_by_id.get(lower_id) as DungeonRoom3D
		if lower_room == null or not lower_room.visible:
			continue
		var door_sides := _edge_door_sides_by_key.get(edge, {}) as Dictionary
		var lower_side := str(
			door_sides.get(
				lower_id,
				connector.get_meta("lower_door_side", "west")
			)
		)
		var lower_door := lower_room.get_door_node(lower_side)
		if lower_door == null or lower_door.is_open:
			continue
		var distance := player.global_position.distance_to(lower_door.global_position)
		if distance > nearest_distance:
			continue
		nearest_distance = distance
		nearest = {
			"edge": edge,
			"connector": connector,
			"lower_room": lower_room,
			"lower_door": lower_door,
			"lower_room_id": lower_id,
			"distance": distance,
		}
	return nearest


func _update_stair_arrival_prompt() -> void:
	if (
		_stair_arrival_prompt_door != null
		and is_instance_valid(_stair_arrival_prompt_door)
	):
		_stair_arrival_prompt_door.set_prompt_visible(false)
	_stair_arrival_prompt_door = null
	var candidate := _find_nearby_stair_arrival()
	if candidate.is_empty():
		return
	_stair_arrival_prompt_door = candidate.get("lower_door") as RoomDoor3D
	if _stair_arrival_prompt_door != null:
		_stair_arrival_prompt_door.set_prompt_visible(true)


func _try_open_nearby_stair_arrival() -> bool:
	var candidate := _find_nearby_stair_arrival()
	if candidate.is_empty():
		return false
	var edge := str(candidate.get("edge", ""))
	var lower_room := candidate.get("lower_room") as DungeonRoom3D
	var lower_door := candidate.get("lower_door") as RoomDoor3D
	if edge.is_empty() or lower_room == null or lower_door == null:
		return false
	_vertical_arrival_open[edge] = true
	lower_door.set_open(true)
	_on_room_entered(lower_room)
	var floor_index := int(_room_floor_index.get(lower_room.room_id, 0))
	status_label.text = "%d层入口门已开启 · 安全大厅已激活" % (
		_floor_number_from_index(floor_index)
	)
	_refresh_camera_door_bypass_nodes()
	return true


func try_open_stair_arrival_for_test() -> bool:
	return _try_open_nearby_stair_arrival()


func _update_corridor_streaming(current_id: String) -> void:
	for edge in _corridor_by_edge.keys():
		var connector := _corridor_by_edge[edge] as Node3D
		if connector == null:
			continue
		var ids := str(edge).split("|")
		var active := bool(_open_edges.get(edge, false)) and current_id in ids
		var is_vertical := bool(connector.get_meta("is_vertical_connector", false))
		var support_loaded := false
		if is_vertical:
			var upper_floor := int(connector.get_meta("upper_floor_index", -999))
			var lower_floor := int(connector.get_meta("lower_floor_index", -999))
			support_loaded = (
				upper_floor in _loaded_floor_indices
				or lower_floor in _loaded_floor_indices
			)
		connector.visible = active
		connector.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		_set_connector_collision_enabled(connector, active, support_loaded)


func _set_connector_collision_enabled(
	root: Node,
	enabled: bool,
	support_enabled := false
) -> void:
	if root is CollisionShape3D:
		var collision := root as CollisionShape3D
		# StairwellWall 3 面围护墙：永远启用，使近墙摄像机探针在门未开时也能
		# 命中并抬高收镜；玩家通行仍由门碰撞与 _open_edges 控制。
		if bool(collision.get_meta("camera_lower_wall", false)):
			collision.set_deferred("disabled", false)
			return
		var persistent_support := bool(collision.get_meta("persistent_stair_support", false))
		collision.set_deferred(
			"disabled",
			not (support_enabled if persistent_support else enabled)
		)
	for child in root.get_children():
		_set_connector_collision_enabled(child, enabled, support_enabled)


func _on_room_entered(room: DungeonRoom3D) -> void:
	if room != null and _is_locked_stair_arrival_room(room.room_id):
		return
	super(room)
	if room == null:
		return
	var depth := maxi(0, -int(round(room.global_position.y / FLOOR_HEIGHT)))
	if room.room_id == "start":
		room_label.text = "楼顶 · 250m整层 / 65m核心"
		player.set_combat_enabled(false)
	elif room.room_id == "facility":
		room_label.text = "99层基地 · 30×30m / 6×6地砖 · 安全区"
		player.set_combat_enabled(false)
	else:
		var role := str(_find_record(room.room_id).get("tower_role", "room"))
		var floor_number := 100 - depth
		if room.room_type == "STAIR_LOBBY":
			var lobby_name := "楼梯出口大厅" if role == "stair_exit" else "楼梯入口大厅"
			room_label.text = "%d层 · %s · 安全区" % [floor_number, lobby_name]
			player.set_combat_enabled(false)
		else:
			room_label.text = "%d层 · %s · %s" % [
				floor_number,
				"本批Boss层" if floor_number == 95 else role,
				room.room_type,
			]
			player.set_combat_enabled(true)
	if _atmosphere != null:
		_atmosphere.call("set_floor_number", _floor_number_from_index(depth))
	if player.camera != null:
		player.camera.far = 520.0 if depth == 0 else 145.0
	_refresh_tower_hud()
	_refresh_facility_runtime()


func _is_locked_stair_arrival_room(room_id: String) -> bool:
	for edge_value in _vertical_arrival_open.keys():
		var edge := str(edge_value)
		if (
			bool(_vertical_arrival_open.get(edge, false))
			or not bool(_open_edges.get(edge, false))
		):
			continue
		var connector := _corridor_by_edge.get(edge) as Node3D
		if connector == null:
			continue
		if (
			str(connector.get_meta("to_room_id", "")) == room_id
			and str(connector.get_meta("from_room_id", "")) == _current_room_id
		):
			return true
	return false


func _update_room_streaming(current_id: String) -> void:
	super(current_id)
	_refresh_camera_door_bypass_nodes()
	_update_floor_visibility_state()
	_refresh_facility_runtime()


func _install_facilities() -> void:
	var facility_floor := _room_by_id.get("facility") as DungeonRoom3D
	if facility_floor == null or not _facility_nodes.is_empty():
		return
	var definitions := [
		{
			"name": "MissionOperations", "position": Vector3(-9.0, 0, -11.6),
			"display": "远征情报终端", "description": "查看本轮楼层与下行规则",
			"menu": "", "color": Color(0.88, 0.48, 0.18),
		},
		{
			"name": "Workshop", "position": Vector3(-3.0, 0, -11.6),
			"display": "枪械工坊", "description": "解锁枪身、弹药与配件蓝图",
			"menu": "res://scenes/WorkshopMenu.tscn", "color": Color(0.75, 0.42, 0.16),
		},
		{
			"name": "Divination", "position": Vector3(3.0, 0, -11.6),
			"display": "命运占卜台", "description": "为下一次深入准备命运预兆",
			"menu": "res://scenes/DivinationMenu.tscn", "color": Color(0.55, 0.31, 0.78),
		},
		{
			"name": "Vault", "position": Vector3(-9.0, 0, 11.6),
			"display": "保险柜", "description": "管理撤离物资与下局带入",
			"menu": "res://scenes/VaultMenu.tscn", "color": Color(0.24, 0.58, 0.72),
		},
		{
			"name": "Archive", "position": Vector3(-3.0, 0, 11.6),
			"display": "怪物档案台", "description": "查看成长中的精英与悬赏情报",
			"menu": "res://scenes/MonsterArchiveMenu.tscn", "color": Color(0.48, 0.65, 0.26),
		},
		{
			"name": "FateCollection", "position": Vector3(3.0, 0, 11.6),
			"display": "命运卡收藏台", "description": "浏览已发现的命运卡片",
			"menu": "res://scenes/FateCardCollectionMenu.tscn", "color": Color(0.72, 0.28, 0.58),
		},
		{
			"name": "BaseConsole", "position": Vector3(9.0, 0, -11.6),
			"display": "基地管理终端", "description": "处理战利品、升级建筑与查看总览",
			"menu": "res://scenes/BaseMenu.tscn", "color": Color(0.28, 0.52, 0.68),
		},
	]
	for definition in definitions:
		var facility := FACILITY_SCENE.instantiate() as BaseFacility3D
		facility.name = str(definition["name"])
		facility.position = definition["position"] as Vector3
		facility.display_name = str(definition["display"])
		facility.description = str(definition["description"])
		facility.facility_color = definition["color"] as Color
		var menu_path := str(definition["menu"])
		if menu_path.is_empty():
			facility.activation_type = BaseFacility3D.ActivationType.SHOW_INFO
		else:
			facility.activation_type = BaseFacility3D.ActivationType.OPEN_MENU
			facility.menu_scene_path = menu_path
		facility_floor.add_child(facility)
		facility.activated.connect(_on_facility_activated)
		_facility_nodes.append(facility)


func _install_elevator_facility() -> void:
	var facility_floor := _room_by_id.get("facility") as DungeonRoom3D
	if facility_floor == null or not _elevator_facilities_by_floor.is_empty():
		return
	# 电梯全部挂在塔楼的独立设施层级下；视觉贴墙，但不再是房间内容节点。
	_elevator_facility = _create_standalone_elevator(
		99,
		"facility",
		facility_floor.position + Vector3(9.0, 0.0, 11.6),
		PI
	)
	for floor_index in range(2, COMBAT_FLOOR_COUNT + 2):
		var floor_number := _floor_number_from_index(floor_index)
		var access_room_id := ""
		for room_id_value in _floor_room_ids.get(floor_index, []):
			var candidate_id := str(room_id_value)
			if (
				str(_find_record(candidate_id).get("tower_role", ""))
				== "elevator_access"
			):
				access_room_id = candidate_id
				break
		if access_room_id.is_empty():
			continue
		var access_room := _room_by_id.get(access_room_id) as DungeonRoom3D
		if access_room == null:
			continue
		var pose := _elevator_wall_pose(access_room)
		_create_standalone_elevator(
			floor_number,
			access_room_id,
			pose["position"] as Vector3,
			float(pose["rotation_y"])
		)


func _create_standalone_elevator(
	floor_number: int,
	access_room_id: String,
	world_position: Vector3,
	rotation_y: float
) -> BaseFacility3D:
	var bay := Node3D.new()
	bay.name = "StandaloneElevatorBay_%dF" % floor_number
	bay.position = world_position
	bay.rotation.y = rotation_y
	bay.set_meta("standalone_facility", true)
	bay.set_meta("floor_number", floor_number)
	bay.set_meta("access_room_id", access_room_id)
	$GeneratedCorridors.add_child(bay)

	var pad_material := StandardMaterial3D.new()
	pad_material.albedo_color = Color(0.035, 0.12, 0.15)
	pad_material.metallic = 0.72
	pad_material.roughness = 0.30
	pad_material.emission_enabled = true
	pad_material.emission = Color(0.02, 0.45, 0.52)
	pad_material.emission_energy_multiplier = 0.72
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(5.0, 0.08, 4.8)
	pad_mesh.material = pad_material
	var pad := MeshInstance3D.new()
	pad.name = "ElevatorBayFloor"
	pad.position = Vector3(0.0, 0.045, 0.0)
	pad.mesh = pad_mesh
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bay.add_child(pad)

	var facility := FACILITY_SCENE.instantiate() as BaseFacility3D
	facility.name = "TowerElevatorConsole_%dF" % floor_number
	facility.display_name = "%d层塔楼电梯" % floor_number
	facility.description = "独立墙边设施 · 点亮本层后可往返已解锁楼层"
	facility.facility_color = Color(0.22, 0.82, 0.88)
	facility.activation_type = BaseFacility3D.ActivationType.SHOW_INFO
	facility.set_meta("tower_elevator_floor", floor_number)
	facility.set_meta("access_room_id", access_room_id)
	facility.set_meta("placement", "standalone_wall_edge")
	bay.add_child(facility)
	facility.activated.connect(_on_facility_activated)
	_elevator_facilities_by_floor[floor_number] = facility
	_elevator_access_room_by_floor[floor_number] = access_room_id
	return facility


func _elevator_wall_pose(room: DungeonRoom3D) -> Dictionary:
	var dimensions := room.get_dimensions()
	var planar_from_core := Vector2(
		room.position.x - TOWER_GEOMETRY.CORE_CENTER_XZ.x,
		room.position.z - TOWER_GEOMETRY.CORE_CENTER_XZ.y
	)
	var local_offset := Vector3.ZERO
	var rotation_y := 0.0
	if absf(planar_from_core.x) > absf(planar_from_core.y):
		var side_sign := signf(planar_from_core.x)
		local_offset.x = side_sign * (dimensions.x * 0.5 - 3.2)
		rotation_y = PI * 0.5 * side_sign
	else:
		var side_sign := signf(planar_from_core.y)
		local_offset.z = side_sign * (dimensions.y * 0.5 - 3.2)
		rotation_y = PI if side_sign > 0.0 else 0.0
	return {
		"position": room.position + local_offset,
		"rotation_y": rotation_y,
	}


func _on_facility_activated(facility: BaseFacility3D) -> void:
	if _active_facility_menu != null and is_instance_valid(_active_facility_menu):
		return
	if facility.has_meta("tower_elevator_floor"):
		var elevator_floor := int(
			facility.get_meta("tower_elevator_floor", 99)
		)
		_unlocked_elevator_floors[elevator_floor] = true
		status_label.text = "%d层独立电梯已点亮" % elevator_floor
		_refresh_tower_hud()
		_open_elevator_panel()
		return
	status_label.text = "%s：%s" % [facility.display_name, facility.description]
	if facility.activation_type == BaseFacility3D.ActivationType.OPEN_MENU:
		_open_facility_menu(facility.menu_scene_path)


func _open_facility_menu(scene_path: String) -> void:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
		status_label.text = "该设施尚未接入功能。"
		return
	var menu_scene := load(scene_path) as PackedScene
	var menu := menu_scene.instantiate() as CanvasLayer
	if menu == null:
		status_label.text = "设施功能加载失败。"
		return
	if menu is BaseMenu:
		menu.overlay_mode = true
	_active_facility_menu = menu
	add_child(menu)
	menu.tree_exited.connect(_on_active_facility_menu_closed)
	_sync_player_input_lock()


func _on_active_facility_menu_closed() -> void:
	_active_facility_menu = null
	_sync_player_input_lock()


func _install_atmosphere() -> void:
	if _atmosphere != null:
		return
	_atmosphere = ATMOSPHERE_SCRIPT.new()
	_atmosphere.name = "TowerAtmosphere3D"
	_atmosphere.call("configure", world_environment.environment, key_light)
	add_child(_atmosphere)
	_atmosphere.call("set_floor_number", _current_floor_number())


func _install_tower_hud() -> void:
	if _tower_floor_label != null:
		return
	var margin := MarginContainer.new()
	margin.name = "TowerStatusHUD"
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 18.0
	margin.offset_top = 134.0
	margin.offset_right = 338.0
	margin.offset_bottom = 274.0
	$HUD.add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018, 0.035, 0.048, 0.90)
	style.border_color = Color(0.18, 0.74, 0.82, 0.78)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	panel.add_child(vbox)
	_tower_floor_label = Label.new()
	_tower_floor_label.add_theme_font_size_override("font_size", 24)
	_tower_floor_label.add_theme_color_override("font_color", Color(0.56, 0.93, 1.0))
	vbox.add_child(_tower_floor_label)
	_tower_target_label = Label.new()
	_tower_target_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(_tower_target_label)
	_tower_elevator_label = Label.new()
	_tower_elevator_label.add_theme_font_size_override("font_size", 14)
	_tower_elevator_label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.88))
	vbox.add_child(_tower_elevator_label)
	_tower_hp_bar = ProgressBar.new()
	_tower_hp_bar.custom_minimum_size = Vector2(280.0, 13.0)
	_tower_hp_bar.show_percentage = false
	vbox.add_child(_tower_hp_bar)


func _refresh_tower_hud() -> void:
	if _tower_floor_label == null or player == null:
		return
	var floor_number := _current_floor_number()
	_tower_floor_label.text = (
		"楼顶 · 100F"
		if floor_number >= 100
		else "%dF" % floor_number
	)
	if floor_number >= 100:
		_tower_target_label.text = "目标：进入西侧楼梯间，抵达99层基地"
	elif floor_number == 99:
		_tower_target_label.text = "目标：整备后下降；电梯可返回已点亮楼层"
	elif floor_number == 95:
		_tower_target_label.text = "目标：肃清本批Boss层并完成撤离验证"
	else:
		_tower_target_label.text = "目标：搜索钥匙、清理房间、点亮电梯并继续下降"
	_tower_elevator_label.text = "电梯已点亮：%s" % (
		" / ".join(_sorted_unlocked_elevator_floors().map(
			func(value): return "%dF" % int(value)
		))
	)
	_tower_hp_bar.max_value = player.max_hp
	_tower_hp_bar.value = player.current_hp


func _on_player_hp_changed(current: int, maximum: int) -> void:
	super(current, maximum)
	if _tower_hp_bar != null:
		_tower_hp_bar.max_value = maximum
		_tower_hp_bar.value = current


func _on_service_activated(room: DungeonRoom3D, station: ServiceStation3D) -> void:
	if station != null and station.station_type == "elevator":
		var floor_index := int(_room_floor_index.get(room.room_id, -1))
		var floor_number := _floor_number_from_index(floor_index)
		if floor_number < 99:
			_unlocked_elevator_floors[floor_number] = true
			status_label.text = "%d层电梯已点亮 · 现在可快速返回99层" % floor_number
			_refresh_tower_hud()
		_open_elevator_panel()
		return
	super(room, station)


func _open_elevator_panel() -> void:
	if _elevator_overlay != null and is_instance_valid(_elevator_overlay):
		return
	_close_inventory_for_modal()
	_elevator_overlay = Control.new()
	_elevator_overlay.name = "TowerElevatorOverlay"
	_elevator_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_elevator_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	$HUD.add_child(_elevator_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_elevator_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -230.0
	panel.offset_top = -235.0
	panel.offset_right = 230.0
	panel.offset_bottom = 235.0
	_elevator_overlay.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.055, 0.072, 0.98)
	style.border_color = Color(0.20, 0.86, 0.92)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "塔楼电梯"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.60, 0.96, 1.0))
	vbox.add_child(title)
	var hint := Label.new()
	hint.text = "只能前往99层与已经亲自点亮的楼层"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	vbox.add_child(hint)
	for floor_number in _sorted_unlocked_elevator_floors():
		var button := Button.new()
		button.text = "%dF%s" % [
			floor_number,
			" · 当前层" if floor_number == _current_floor_number() else "",
		]
		button.custom_minimum_size.y = 48.0
		button.disabled = floor_number == _current_floor_number()
		button.pressed.connect(_travel_elevator_to.bind(floor_number))
		vbox.add_child(button)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6.0
	vbox.add_child(spacer)
	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size.y = 42.0
	close_button.pressed.connect(_close_elevator_panel)
	vbox.add_child(close_button)
	_sync_player_input_lock()


func _close_elevator_panel() -> void:
	if _elevator_overlay != null and is_instance_valid(_elevator_overlay):
		_elevator_overlay.queue_free()
	_elevator_overlay = null
	_sync_player_input_lock()


func _travel_elevator_to(floor_number: int) -> void:
	if not bool(_unlocked_elevator_floors.get(floor_number, false)):
		status_label.text = "%d层尚未点亮，不能向未探索楼层跳层" % floor_number
		return
	var target_room := _room_by_id.get("facility") as DungeonRoom3D
	if floor_number != 99:
		target_room = null
		var target_index := 100 - floor_number
		for room_id in _floor_room_ids.get(target_index, []):
			var record := _find_record(str(room_id))
			if str(record.get("tower_role", "")) == "elevator_access":
				target_room = _room_by_id.get(str(room_id)) as DungeonRoom3D
				break
	if target_room == null:
		status_label.text = "电梯目标楼层未生成"
		return
	_close_elevator_panel()
	player.global_position = target_room.global_position + Vector3(0.0, 0.05, 2.7)
	player.velocity = Vector3.ZERO
	_on_room_entered(target_room)
	status_label.text = "电梯抵达 %dF" % floor_number


func _floor_number_from_index(floor_index: int) -> int:
	return 100 - clampi(floor_index, 0, COMBAT_FLOOR_COUNT + 1)


func _current_floor_number() -> int:
	var fallback_index := clampi(
		int(round(-player.global_position.y / FLOOR_HEIGHT)) if player != null else 0,
		0,
		COMBAT_FLOOR_COUNT + 1
	)
	return _floor_number_from_index(int(_room_floor_index.get(_current_room_id, fallback_index)))


func _sorted_unlocked_elevator_floors() -> Array:
	var floors: Array = _unlocked_elevator_floors.keys()
	floors.sort_custom(func(a, b): return int(a) > int(b))
	return floors


func _has_exclusive_modal() -> bool:
	return (
		(_active_facility_menu != null and is_instance_valid(_active_facility_menu))
		or (_elevator_overlay != null and is_instance_valid(_elevator_overlay))
		or super()
	)


func try_close_modal_for_pause() -> bool:
	if _elevator_overlay != null and is_instance_valid(_elevator_overlay):
		_close_elevator_panel()
		return true
	if _active_facility_menu != null and is_instance_valid(_active_facility_menu):
		_active_facility_menu.queue_free()
		return true
	return super()


func _refresh_facility_runtime() -> void:
	var active := _current_room_id == "facility"
	for facility in _facility_nodes:
		if not is_instance_valid(facility):
			continue
		facility.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		facility.set_deferred("monitoring", active)
		facility.set_deferred("monitorable", active)
	for floor_number_value in _elevator_facilities_by_floor.keys():
		var floor_number := int(floor_number_value)
		var elevator := (
			_elevator_facilities_by_floor[floor_number_value] as BaseFacility3D
		)
		if elevator == null or not is_instance_valid(elevator):
			continue
		var access_room_id := str(
			_elevator_access_room_by_floor.get(floor_number, "")
		)
		var elevator_active := _current_room_id == access_room_id
		var floor_index := 100 - floor_number
		var floor_loaded := floor_index in _loaded_floor_indices
		var bay := elevator.get_parent() as Node3D
		if bay != null:
			bay.visible = floor_loaded
			bay.process_mode = (
				Node.PROCESS_MODE_INHERIT
				if floor_loaded
				else Node.PROCESS_MODE_DISABLED
			)
		elevator.process_mode = (
			Node.PROCESS_MODE_INHERIT
			if elevator_active
			else Node.PROCESS_MODE_DISABLED
		)
		elevator.set_deferred("monitoring", elevator_active)
		elevator.set_deferred("monitorable", elevator_active)


func _room_status(type_id: String) -> String:
	if type_id == "FACILITY":
		return "设施安全层：整备完成后从右侧通道继续下行"
	return super(type_id)


func get_facility_count() -> int:
	return _facility_nodes.size()


func get_active_facility_menu() -> CanvasLayer:
	return _active_facility_menu


func get_tower_snapshot() -> Dictionary:
	var combat_floor_records: Array[Dictionary] = []
	var floor_heights: Array[float] = []
	var support_floor_count := 0
	var rendered_floor_count := 0
	var floor_stage_snapshots: Array[Dictionary] = []
	for floor_index in range(COMBAT_FLOOR_COUNT + 2):
		floor_heights.append(-FLOOR_HEIGHT * float(floor_index))
		var stage = _floor_stages.get(floor_index)
		if stage != null:
			var stage_snapshot: Dictionary = stage.call("get_snapshot")
			floor_stage_snapshots.append(stage_snapshot)
			if bool(stage_snapshot.get("support_collision_persistent", false)):
				support_floor_count += 1
			if bool(stage_snapshot.get("shell_visible", false)):
				rendered_floor_count += 1
	for combat_floor in range(1, COMBAT_FLOOR_COUNT + 1):
		var physical_index := combat_floor + 1
		combat_floor_records.append({
			"id": "floor_%02d" % combat_floor,
			"type": "BOSS" if combat_floor == COMBAT_FLOOR_COUNT else "COMBAT",
			"layout_template": str(_floor_layout_templates.get(physical_index, "")),
			"dimensions": Vector2(TOWER_GEOMETRY.MAP_SIZE_M, TOWER_GEOMETRY.MAP_SIZE_M),
			"height": -FLOOR_HEIGHT * float(physical_index),
			"room_ids": (_floor_room_ids.get(physical_index, []) as Array).duplicate(),
			"room_count": (_floor_room_ids.get(physical_index, []) as Array).size(),
		})
	var vertical_connector_count := 0
	var closed_door_count := 0
	var visible_room_ids: Array[String] = []
	var visible_room_floor_indices: Array[int] = []
	var vertical_arrival_open_count := 0
	for opened in _vertical_arrival_open.values():
		if bool(opened):
			vertical_arrival_open_count += 1
	for corridor in _corridor_by_edge.values():
		if corridor is Node3D and bool((corridor as Node3D).get_meta("is_vertical_connector", false)):
			vertical_connector_count += 1
	for room in _rooms:
		if room.visible:
			visible_room_ids.append(room.room_id)
			var visible_floor_index := int(_room_floor_index.get(room.room_id, -1))
			if visible_floor_index not in visible_room_floor_indices:
				visible_room_floor_indices.append(visible_floor_index)
		for door_snapshot in room.get_room_snapshot().get("door_snapshots", []):
			if bool(door_snapshot.get("blocks_passage", false)):
				closed_door_count += 1
	return {
		"mode": "tower_descent",
		"rooftop_dimensions": Vector2(TOWER_GEOMETRY.MAP_SIZE_M, TOWER_GEOMETRY.MAP_SIZE_M),
		"facility_dimensions": (_room_by_id["facility"] as DungeonRoom3D).get_dimensions(),
		"combat_floor_count": combat_floor_records.size(),
		"combat_floors": combat_floor_records,
		"floor_layout_templates": _floor_layout_templates.duplicate(),
		"rooms_per_normal_combat_floor": 12,
		"boss_floor_room_count": 10,
		"logical_combat_room_count": _rooms.size() - 2,
		"combat_room_size": Vector2(
			TOWER_GEOMETRY.COMBAT_ROOM_SIZE_M,
			TOWER_GEOMETRY.COMBAT_ROOM_SIZE_M
		),
		"combat_stair_lobby_size": Vector2(
			TOWER_GEOMETRY.COMBAT_STAIR_LOBBY_SIZE_M,
			TOWER_GEOMETRY.COMBAT_STAIR_LOBBY_SIZE_M
		),
		"boss_arena_size": Vector2(
			TOWER_GEOMETRY.BOSS_ARENA_SIZE_M,
			TOWER_GEOMETRY.BOSS_ARENA_SIZE_M
		),
		"floor_heights": floor_heights,
		"floor_height": FLOOR_HEIGHT,
		"map_size": TOWER_GEOMETRY.MAP_SIZE_M,
		"core_size": TOWER_GEOMETRY.CORE_SIZE_M,
		"grid_unit": TOWER_GEOMETRY.GRID_UNIT_M,
		"facility_grid_dimensions": Vector2i(6, 6),
		"facility_grid_tile_count": 36,
		"base_to_stair_corridor_length_m": (
			TOWER_GEOMETRY.CORE_SIZE_M * 0.5 - 15.0
		),
		"facility_count": get_facility_count(),
		"has_base_elevator": _elevator_facility != null,
		"standalone_elevator_count": _elevator_facilities_by_floor.size(),
		"elevator_facilities_are_room_content": false,
		"elevator_access_rooms": _elevator_access_room_by_floor.duplicate(),
		"unlocked_elevator_floors": _sorted_unlocked_elevator_floors(),
		"vertical_connector_count": vertical_connector_count,
		"descent_sides": _descent_side_sequence.duplicate(),
		"support_floor_count": support_floor_count,
		"rendered_floor_count": rendered_floor_count,
		"loaded_floor_count": _loaded_floor_indices.size(),
		"loaded_floor_indices": _loaded_floor_indices.duplicate(),
		"floor_stages": floor_stage_snapshots,
		"closed_door_count": closed_door_count,
		"visible_room_ids": visible_room_ids,
		"visible_room_floor_indices": visible_room_floor_indices,
		"current_room_id": _current_room_id,
		"return_scene_path": return_scene_path,
		"stair_surface_snap_count": _stair_surface_snap_count,
		"stair_surface_snap_enabled": false,
		"stair_support_surface_count": _stair_support_surface_count,
		"stair_support_mode": "imported_walkable_mesh_colliders",
		"camera_height_m": CAMERA_HEIGHT_M + _camera_lift_current_m,
		"camera_base_height_m": CAMERA_HEIGHT_M,
		"camera_lift_current_m": _camera_lift_current_m,
		"camera_lift_target_m": _camera_lift_target_m,
		"camera_lift_max_m": CAMERA_LOWER_WALL_LIFT_MAX_M,
		"camera_trailing_current_m": _camera_trailing_current_m,
		"camera_trailing_target_m": _camera_trailing_target_m,
		"camera_trailing_min_m": CAMERA_LOWER_WALL_MIN_TRAILING_M,
		"camera_lower_wall_detected": _camera_lower_wall_detected,
		"camera_lower_wall_distance_m": _camera_lower_wall_distance_m,
		"camera_collision_mode": "lower_wall_lift_and_retract_arc",
		"camera_trailing_offset_m": _camera_trailing_current_m,
		"camera_planar_offset": Vector3(
			0.0,
			0.0,
			_camera_trailing_current_m
		),
		"camera_desired_trailing_offset_m": CAMERA_DEFAULT_TRAILING_M,
		"camera_look_height_m": CAMERA_LOOK_HEIGHT_M,
		"camera_look_ahead_m": CAMERA_LOOK_AHEAD_M,
		"camera_fov_deg": CAMERA_FOV_DEG,
		"camera_collision_adjusted": _camera_lift_current_m > 0.01,
		"camera_collision_enabled": true,
		"camera_fixed_pose": false,
		"camera_horizontal_pose_fixed": true,
		"camera_yaw_locked": true,
		"camera_floor_cutaway_enabled": false,
		"camera_cutaway_mode": "occluded_player_silhouette",
		"camera_cutaway_count": 0,
		"camera_hidden_wall_count": 0,
		"camera_occlusion_silhouette_enabled": true,
		"camera_occluded_player": _player_occluded,
		"camera_occlusion_blocked_ray_count": _camera_blocked_ray_count,
		"camera_silhouette_mesh_count": _player_occlusion_meshes.size(),
		"camera_near_fade_candidate_count": 0,
		"camera_near_faded_mesh_count": 0,
		"camera_near_fade_alpha": 1.0,
		"camera_wall_material_mutation_enabled": false,
		"camera_door_bypass_active": _camera_door_bypass_active,
		"camera_door_bypass_half_width_m": CAMERA_DOOR_BYPASS_HALF_WIDTH_M,
		"camera_door_bypass_half_depth_m": CAMERA_DOOR_BYPASS_HALF_DEPTH_M,
		"camera_door_bypass_node_count": _camera_door_bypass_nodes.size(),
		"vertical_arrival_gate_count": _vertical_arrival_open.size(),
		"vertical_arrival_open_count": vertical_arrival_open_count,
		"stair_arrival_interaction_distance_m": STAIR_ARRIVAL_INTERACTION_DISTANCE_M,
		"physical_occlusion_only": true,
		"transition_edge": _active_transition_edge,
		"transition_upper_floor": _transition_upper_floor,
		"transition_lower_floor": _transition_lower_floor,
		"transition_progress": _transition_progress,
		"atmosphere": (
			_atmosphere.call("get_snapshot")
			if _atmosphere != null
			else {}
		),
		"stair_geometry_m": {
			"door_clear_width": TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M,
			"door_clear_height": TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M,
			"passage_width": STAIR_WIDTH,
			"approach_outset": TOWER_GEOMETRY.APPROACH_OUTSET_M,
			"run_length": STAIR_RUN,
			"lane_center_spacing": STAIR_LANE_SPACING,
			"guard_end_clearance": TOWER_GEOMETRY.GUARD_END_CLEARANCE_M,
			"floor_thickness": TOWER_GEOMETRY.FLOOR_THICKNESS_M,
		},
	}
