class_name TowerDescent3D
extends Dungeon3D
## v0.1 塔楼入口：楼顶、30m基地与98—95层探索区共用 Dungeon3D
## 战斗/命运/掉落管线；这里只定义垂直拓扑、电梯、五层流送、固定镜头
## 下方墙平滑抬升收拢、双端楼梯门、独立墙边电梯与全局固定环境光。

const FACILITY_SCENE: PackedScene = preload("res://assets/art/props/base_world_3d/prp_base_facility_root_top3d_v001.tscn")
const VENDING_FACILITY_SCENE: PackedScene = preload("res://assets/art/props/base_world_3d/prp_base_vending_machine_root_top3d_v001.tscn")
const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
const FLOOR_PLAN_GENERATOR := preload("res://src/map/FloorPlanGenerator.gd")
const FLOOR_STAGE_SCRIPT := preload("res://src/world3d/TowerFloorStage3D.gd")
const ATMOSPHERE_SCRIPT := preload("res://src/world3d/TowerAtmosphere3D.gd")
const DYNAMIC_ROOM_SCENE: PackedScene = preload("res://assets/art/environments/dungeon_3d/env_dungeon_runtime_kit_top3d_v001.tscn")
const TOWER_WALL_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_descent_3d/components/env_tower_wall_solid_5m_top3d_v001.glb"
)
const TOWER_FLOOR_TILE_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_descent_3d/components/env_tower_floor_tile_5m_top3d_v001.glb"
)
const STAIR_GENERIC_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_descent_3d/components/env_tower_stairwell_generic_9m_top3d_v001.glb"
)
const STAIR_ROOFTOP_SCENE: PackedScene = preload(
	"res://assets/art/environments/tower_descent_3d/components/env_tower_stairwell_rooftop_9m_top3d_v001.glb"
)
const COMBAT_FLOOR_COUNT := 4
const DEEPEST_PLANNED_FLOOR := 85
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
const CAMERA_FOV_DEG := 65.0
const CAMERA_LOWER_WALL_PROBE_HEIGHT_M := 0.95
# 探针从角色前侧开始并向镜头后方穿过角色。若从角色身后0.42m起射，
# 角色贴墙时起点会落入0.30m厚的墙体，射线便可能漏掉“从内部出发”的墙。
const CAMERA_LOWER_WALL_PROBE_START_M := -0.40
const CAMERA_LOWER_WALL_PROBE_LENGTH_M := 6.2
const CAMERA_LOWER_WALL_PROBE_LATERAL_OFFSETS_M := [-0.28, 0.0, 0.28]
const CAMERA_LOWER_WALL_LIFT_MAX_M := 0.30
const CAMERA_LOWER_WALL_LIFT_BLEND_DISTANCE_M := 1.2
const CAMERA_LOWER_WALL_LIFT_RISE_RATE := 8.0
const CAMERA_LOWER_WALL_LIFT_FALL_RATE := 4.5
const CAMERA_LOWER_WALL_MIN_TRAILING_M := 0.15
const CAMERA_LOWER_WALL_RETRACT_RATE := 10.0
const CAMERA_LOWER_WALL_EXTEND_RATE := 4.5
const CAMERA_LOWER_WALL_MAX_RAY_HITS := 8
const CAMERA_WALL_COLLISION_MASK := (
	1 | GameDesignConfig.COLLISION_LAYER_CAMERA_ONLY
)
# 楼梯的上下两跑斜楼板会把局部净高压到9m以下。只查询导入楼梯明确
# 标记的两块Flight_Walkable，不让普通房间楼板或其他碰撞改变镜头体验。
const CAMERA_STAIR_SLAB_PROBE_START_HEIGHT_M := 1.15
const CAMERA_STAIR_SLAB_CLEARANCE_M := 0.28
const CAMERA_STAIR_SLAB_MIN_HEIGHT_M := 1.25
const CAMERA_STAIR_SLAB_RECOVER_RATE := 5.0
const CAMERA_STAIR_SLAB_MAX_RAY_HITS := 8
const CAMERA_STAIR_SLAB_LATERAL_OFFSETS_M := [-0.24, 0.0, 0.24]
const STAIR_ARRIVAL_INTERACTION_DISTANCE_M := 3.4
# 楼梯资产位于65m核心外侧：沿外法线预留20m、沿折返方向预留30m。
# 该占位参与整层布局规划，普通/随机房间不得进入；楼梯大厅自身作为接口例外。
const STAIR_PLAN_OUTWARD_DEPTH_M := 20.0
const STAIR_PLAN_TANGENT_LENGTH_M := 30.0
const CAMERA_OCCLUSION_RAY_OFFSETS := [
	Vector3.ZERO,
	Vector3(-0.48, 0.30, 0.0),
	Vector3(0.48, 0.30, 0.0),
	Vector3(0.0, 0.72, 0.0),
]
const CAMERA_OCCLUSION_MIN_BLOCKED_RAYS := 2
# 玩家移动时仍按物理帧刷新，保证贴墙镜头没有额外延迟；站立时降至30Hz，
# 只削减肉眼不可见的重复物理查询，镜头位置和平滑仍保持每物理帧更新。
const CAMERA_PROBE_MOVING_INTERVAL := 1.0 / 60.0
const CAMERA_PROBE_IDLE_INTERVAL := 1.0 / 30.0

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
var _floor_plan_snapshots: Dictionary = {}
var _floor_seed_gate_edges: Dictionary = {}
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
var _tower_base_currency_label: Label
var _loaded_floor_indices: Array[int] = []
var _floor_visibility_poll_count := 0
var _floor_visibility_apply_count := 0
var _generated_floor_indices: Array[int] = []
var _floor_plan_commit_reasons: Dictionary = {}
var _floor_layout_plan_conflicts: Array[String] = []
var _planned_floor_indices: Array[int] = []
var _boss_descent_gate_edges: Dictionary = {}
var _airlock_front_edges: Dictionary = {}
var _boss_descent_key_count := 0
var _level_elevator_edge := ""
var _last_bundle_room_count := 0
var _last_bundle_corridor_count := 0
var _airlock_warning_overlay: Control
var _pending_airlock_candidate: Dictionary = {}
var _active_airlock_room_id := ""
var _unloaded_segment_floor_indices: Array[int] = []
var _last_unloaded_room_count := 0
var _last_destroyed_world_loot_count := 0
var _player_occlusion_meshes: Array[GeometryInstance3D] = []
var _player_original_overlays: Dictionary = {}
var _player_occlusion_material: StandardMaterial3D
var _player_occluded := false
var _camera_blocked_ray_count := 0
var _camera_probe_accumulator := CAMERA_PROBE_IDLE_INTERVAL
var _camera_probe_refresh_count := 0
var _camera_probe_interval_s := CAMERA_PROBE_IDLE_INTERVAL
var _camera_lower_wall_detected := false
var _camera_lower_wall_distance_m := -1.0
var _camera_lift_target_m := 0.0
var _camera_lift_current_m := 0.0
var _camera_trailing_target_m := CAMERA_DEFAULT_TRAILING_M
var _camera_trailing_current_m := CAMERA_DEFAULT_TRAILING_M
var _camera_stair_slab_detected := false
var _camera_stair_slab_clearance_height_m := -1.0
var _camera_stair_slab_drop_target_m := 0.0
var _camera_stair_slab_drop_current_m := 0.0
var _vertical_arrival_open: Dictionary = {}
var _stair_arrival_previous_room := ""
var _stair_arrival_prompt_door: RoomDoor3D
var _facility_outbound_door_edge := ""
var _facility_outbound_door_seen_inside := false
var _corridor_floor_module_mesh: Mesh
var _corridor_wall_module_mesh: Mesh
var _initial_loop_gate_armed := false
var _initial_loop_gate_sealed := false
var _initial_loop_retreat_overlay: Control = null


func _ready() -> void:
	process_physics_priority = 100
	super()
	_ensure_floor_generated(0, "rooftop_bootstrap")
	_build_floor_stages()
	# 镜头固定在9m层高内部的斜俯视位置；墙体和物件不再推动或旋转镜头。
	_apply_indoor_camera_pose()
	player.camera.fov = CAMERA_FOV_DEG
	_install_player_occlusion_silhouette()
	_install_facilities()
	_install_elevator_facility()
	_install_tower_hud()
	_install_atmosphere()
	# 自动化/编辑器验证固定从楼顶开始，避免读取或改写开发者的真实存档。
	var starts_on_rooftop := test_mode or BaseManager == null or BaseManager.should_start_on_rooftop()
	if starts_on_rooftop:
		player.global_position = Vector3(
			TOWER_GEOMETRY.CORE_CENTER_XZ.x - 20.0,
			0.05,
			TOWER_GEOMETRY.CORE_CENTER_XZ.y
		)
	else:
		var facility_room := _room_by_id.get("facility") as DungeonRoom3D
		if facility_room != null:
			player.global_position = facility_room.global_position + Vector3(0.0, 0.05, 0.0)
			player.velocity = Vector3.ZERO
			_current_room_id = ""
			_on_room_entered(facility_room)
	title_label.text = "弹壳风暴2 · 向下爬楼行动"
	seed_label.text = "塔楼种子 %d" % run_seed
	status_label.text = (
		"楼顶新手出生点 · 西侧特殊楼梯门通向99F基地"
		if starts_on_rooftop
		else "已从99F基地中点恢复 · 基地屋内禁射，跨出任一侧门即可开火"
	)
	_update_floor_visibility_state()
	_refresh_tower_hud()
	_refresh_facility_runtime()
	var first_entry := _room_by_id.get("floor_01_entry") as DungeonRoom3D
	if first_entry != null and not first_entry.player_entered.is_connected(_on_initial_loop_entry_physically_entered):
		first_entry.player_entered.connect(_on_initial_loop_entry_physically_entered)


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
	_update_facility_combat_lock()
	_update_facility_door_auto_close()
	_update_stair_arrival_prompt()


func _finish_run(success: bool) -> void:
	# 塔楼成功撤离是“带物返航99F”，不是重新加载塔楼。父类的成功路径会把
	# 战利品复制到待处理集合后重载本场景，导致玩家回100F且I键背包为空。
	if not success:
		super(success)
		return
	if _completed:
		return
	_completed = true
	_close_inventory_for_modal()
	_sync_player_input_lock()
	extraction_panel.visible = false
	_run_loot = _collect_extracted_items(true)
	var extracted_count := _death_settlement.process_extraction_settlement(_inventory, _insurance)
	var summary := {
		"success": true,
		"kills": _kills,
		"value": _run_value,
		"loot": _run_loot.duplicate(true),
		"seed": run_seed,
		"theme_id": gameplay_theme.theme_id,
		"settlement": {"retained": true, "extracted_count": extracted_count},
		"inventory_capacity": _inventory.get_capacity(),
		"insurance_capacity": _insurance.get_max_slots(),
		"return_room_id": "facility",
	}
	if not test_mode:
		BaseManager.record_run(true, _kills)
		BaseManager.add_extraction_points(_run_value)
		BaseManager.clear_active_run_checkpoint("successful_extraction_to_99f")
	status_label.text = "撤离成功 · %d件物资完整保留 · 正在返航99F基地" % _run_loot.size()
	run_completed.emit(true, summary)
	if not test_mode:
		await get_tree().create_timer(0.8).timeout
	_return_successful_extraction_to_facility()


func _return_successful_extraction_to_facility() -> void:
	var retained_loot_count := _run_loot.size()
	# 只复用世界复位部分；与98F撤退不同，这里绝不清背包、武器、背包装备、
	# 快捷栏或保险格，也不写入extraction_loot，避免同一实例同时存在两份。
	_reset_initial_loop_world_after_retreat()
	var facility_room := _room_by_id.get("facility") as DungeonRoom3D
	if facility_room != null and player != null:
		player.global_position = facility_room.global_position + Vector3(0.0, 0.05, 2.7)
		player.velocity = Vector3.ZERO
		# 系统返航不是穿越关闭的到达门；清除旧房间上下文，避免楼梯门防穿越
		# 校验把这次合法传送误判为从上一个房间越过锁门。
		_current_room_id = ""
		_on_room_entered(facility_room)
	_completed = false
	_extraction_defense_active = false
	_active_extraction_beacon = null
	_kills = 0
	_run_value = 0
	GameManager.currency = 0
	GameManager.currency_changed.emit(0)
	FateCardGameBridge.reset_run_state()
	_refresh_loot_label()
	_refresh_tower_hud()
	_sync_player_input_lock()
	status_label.text = "已成功返航99F基地 · %d件战利品、装备与保险物全部保留" % retained_loot_count


func _build_floor_stages() -> void:
	for floor_value in _floor_room_ids.keys():
		_rebuild_floor_stage(int(floor_value))


func _rebuild_floor_stage(floor_index: int) -> void:
	var hole_sides: Array[String] = []
	for declaration in _declared_edges:
		if str(declaration.get("kind", "")) != "vertical":
			continue
		if int(_room_floor_index.get(str(declaration["a"]), -1)) != floor_index:
			continue
		var side := str(declaration.get("side", "west"))
		if side not in hole_sides:
			hole_sides.append(side)
	var previous = _floor_stages.get(floor_index)
	if previous != null and is_instance_valid(previous):
		previous.queue_free()
	var kind := "rooftop" if floor_index == 0 else "facility" if floor_index == 1 else "combat"
	var stage = FLOOR_STAGE_SCRIPT.new()
	stage.call("configure", floor_index, kind, hole_sides)
	stage.position.y = -FLOOR_HEIGHT * float(floor_index)
	$GeneratedRooms.add_child(stage)
	_floor_stages[floor_index] = stage


func _update_floor_visibility_state() -> void:
	if _floor_stages.is_empty() or player == null:
		return
	_floor_visibility_poll_count += 1
	var current_floor := int(_room_floor_index.get(
		_current_room_id,
		maxi(0, int(round(-player.global_position.y / FLOOR_HEIGHT)))
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
	var next_loaded_floor_indices: Array[int] = []
	for candidate_value in _floor_stages.keys():
		var candidate_index := int(candidate_value)
		if absi(candidate_index - stream_center) <= 2:
			next_loaded_floor_indices.append(candidate_index)
	# 楼梯过渡值仍可每帧更新，但只有加载集合真正改变时才重写所有楼层、
	# 66个房间和设施的 visible/process_mode。普通站立不再重复全表施工。
	if next_loaded_floor_indices == _loaded_floor_indices:
		return
	_loaded_floor_indices.assign(next_loaded_floor_indices)
	_floor_visibility_apply_count += 1

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
		var streamed := room.is_streamed()
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
	var planar_velocity := Vector2(player.velocity.x, player.velocity.z)
	var player_is_moving := planar_velocity.length_squared() > 0.01
	_camera_probe_interval_s = (
		CAMERA_PROBE_MOVING_INTERVAL
		if player_is_moving
		else CAMERA_PROBE_IDLE_INTERVAL
	)
	_camera_probe_accumulator += delta
	var refresh_camera_probes := (
		_camera_probe_accumulator + 0.0001 >= _camera_probe_interval_s
	)
	if refresh_camera_probes:
		_camera_probe_accumulator = fmod(
		_camera_probe_accumulator, _camera_probe_interval_s
		)
		_camera_probe_refresh_count += 1
	# v0.1：只允许画面下方墙体驱动固定后方轴上的抬升收拢；禁止侧移与旋转。
	_update_camera_lower_wall_lift(delta, refresh_camera_probes)
	_update_camera_stair_slab_drop(delta, refresh_camera_probes)
	_apply_indoor_camera_pose()
	# v0.1：墙体透明淡化会在摄像机碰撞时留下概率性消失状态。
	# 摄像机现在只沿固定轴缩短距离，墙材质永不被运行时改写。
	_update_floor_visibility_state()
	if refresh_camera_probes:
		_update_camera_occlusion_silhouette()


func _apply_indoor_camera_pose() -> void:
	if player == null or player.camera == null:
		return
	player.camera.position = Vector3(
		0.0,
		CAMERA_HEIGHT_M + _camera_lift_current_m - _camera_stair_slab_drop_current_m,
		_camera_trailing_current_m
	)
	var look_target := player.global_position + Vector3(
		0.0,
		CAMERA_LOOK_HEIGHT_M,
		-CAMERA_LOOK_AHEAD_M
	)
	player.camera.look_at(look_target, Vector3.UP)


func _update_camera_lower_wall_lift(delta: float, refresh_probe: bool = true) -> void:
	# 开门只改变通行碰撞，不得全局跳过后墙探针；否则角色站在开放的
	# 门附近时，同一小房间处于镜头后方的水平墙也会被错误忽略。
	if refresh_probe:
		_camera_lower_wall_distance_m = _find_lower_camera_wall_distance()
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
	var lateral := Vector3.UP.cross(trailing).normalized()
	var space_state := get_world_3d().direct_space_state
	var nearest_distance := INF
	for lateral_offset_value in CAMERA_LOWER_WALL_PROBE_LATERAL_OFFSETS_M:
		var lateral_offset := lateral * float(lateral_offset_value)
		var probe_origin := (
			player.global_position
			+ Vector3.UP * CAMERA_LOWER_WALL_PROBE_HEIGHT_M
			+ trailing * CAMERA_LOWER_WALL_PROBE_START_M
			+ lateral_offset
		)
		var probe_end := (
			player.global_position
			+ Vector3.UP * CAMERA_LOWER_WALL_PROBE_HEIGHT_M
			+ trailing * CAMERA_LOWER_WALL_PROBE_LENGTH_M
			+ lateral_offset
		)
		var ray_from := probe_origin
		var excluded: Array[RID] = []
		if player is CollisionObject3D:
			excluded.append((player as CollisionObject3D).get_rid())
		for _hit_index in range(CAMERA_LOWER_WALL_MAX_RAY_HITS):
			var query := PhysicsRayQueryParameters3D.create(
				ray_from,
				probe_end,
				CAMERA_WALL_COLLISION_MASK,
				excluded
			)
			query.collide_with_areas = false
			query.hit_from_inside = true
			var hit := space_state.intersect_ray(query)
			if hit.is_empty():
				break
			var collider := hit.get("collider") as Node
			var hit_position := hit.get("position", ray_from) as Vector3
			if _is_camera_lower_wall(collider):
				var planar_offset := hit_position - player.global_position
				planar_offset.y = 0.0
				nearest_distance = minf(
					nearest_distance,
					maxf(0.0, planar_offset.dot(trailing))
				)
				break
			if collider is CollisionObject3D:
				excluded.append((collider as CollisionObject3D).get_rid())
			var remaining_direction := ray_from.direction_to(probe_end)
			if remaining_direction.is_zero_approx():
				break
			ray_from = hit_position + remaining_direction * 0.03
	return nearest_distance if is_finite(nearest_distance) else -1.0


func _update_camera_stair_slab_drop(
	delta: float,
	refresh_probe: bool = true
) -> void:
	var desired_height_m := CAMERA_HEIGHT_M + _camera_lift_current_m
	if refresh_probe:
		_camera_stair_slab_clearance_height_m = (
			_find_stair_slab_camera_clearance_height(desired_height_m)
		)
		_camera_stair_slab_detected = (
			_camera_stair_slab_clearance_height_m >= 0.0
		)
	_camera_stair_slab_drop_target_m = 0.0
	if _camera_stair_slab_detected:
		_camera_stair_slab_drop_target_m = maxf(
			0.0,
			desired_height_m - _camera_stair_slab_clearance_height_m
		)
	# 进入楼板时立即向下夹紧，绝不让一帧平滑插值把镜头留在碰撞内部；
	# 离开楼板后才缓慢恢复默认高度，避免楼梯出口处突然弹镜。
	if _camera_stair_slab_drop_target_m > _camera_stair_slab_drop_current_m:
		_camera_stair_slab_drop_current_m = _camera_stair_slab_drop_target_m
	else:
		var blend := 1.0 - exp(
			-CAMERA_STAIR_SLAB_RECOVER_RATE * maxf(delta, 0.0)
		)
		_camera_stair_slab_drop_current_m = lerpf(
			_camera_stair_slab_drop_current_m,
			_camera_stair_slab_drop_target_m,
			blend
		)
		if (
			absf(
				_camera_stair_slab_drop_current_m
				- _camera_stair_slab_drop_target_m
			) <= 0.001
		):
			_camera_stair_slab_drop_current_m = _camera_stair_slab_drop_target_m


func _find_stair_slab_camera_clearance_height(
	desired_height_m: float
) -> float:
	if player == null or not player.is_inside_tree():
		return -1.0
	var probe_start_y := (
		player.global_position.y + CAMERA_STAIR_SLAB_PROBE_START_HEIGHT_M
	)
	var probe_end_y := player.global_position.y + desired_height_m
	if probe_end_y <= probe_start_y + 0.01:
		return -1.0
	var camera_planar_position := player.to_global(
		Vector3(0.0, 0.0, _camera_trailing_current_m)
	)
	var camera_right := player.global_basis.x
	camera_right.y = 0.0
	if camera_right.length_squared() <= 0.0001:
		camera_right = Vector3.RIGHT
	camera_right = camera_right.normalized()
	var space_state := get_world_3d().direct_space_state
	var allowed_height_m := INF
	for offset_value in CAMERA_STAIR_SLAB_LATERAL_OFFSETS_M:
		var offset := camera_right * float(offset_value)
		var probe_start := Vector3(
			camera_planar_position.x + offset.x,
			probe_start_y,
			camera_planar_position.z + offset.z
		)
		var probe_end := Vector3(
			probe_start.x,
			probe_end_y,
			probe_start.z
		)
		var ray_from := probe_start
		var excluded: Array[RID] = []
		if player is CollisionObject3D:
			excluded.append((player as CollisionObject3D).get_rid())
		for _hit_index in range(CAMERA_STAIR_SLAB_MAX_RAY_HITS):
			var query := PhysicsRayQueryParameters3D.create(
				ray_from,
				probe_end,
				CAMERA_WALL_COLLISION_MASK,
				excluded
			)
			query.collide_with_areas = false
			query.hit_back_faces = true
			query.hit_from_inside = true
			var hit := space_state.intersect_ray(query)
			if hit.is_empty():
				break
			var collider := hit.get("collider") as Node
			var hit_position := hit.get("position", ray_from) as Vector3
			if collider != null and bool(
				collider.get_meta("camera_stair_slab", false)
			):
				allowed_height_m = minf(
					allowed_height_m,
					clampf(
						hit_position.y
							- player.global_position.y
							- CAMERA_STAIR_SLAB_CLEARANCE_M,
						CAMERA_STAIR_SLAB_MIN_HEIGHT_M,
						desired_height_m
					)
				)
				break
			if collider is CollisionObject3D:
				excluded.append((collider as CollisionObject3D).get_rid())
			var remaining_direction := ray_from.direction_to(probe_end)
			if remaining_direction.is_zero_approx():
				break
			ray_from = hit_position + remaining_direction * 0.03
	return allowed_height_m if is_finite(allowed_height_m) else -1.0


func _is_camera_lower_wall(collider: Node) -> bool:
	if collider == null:
		return false
	# 不能再根据泛化名称把东西墙、楼梯护栏和走廊端面都当成后墙。
	# 生成组件必须显式标记；射线方向随玩家朝向变化，因此南北共享墙
	# 都可成为镜头后墙，东西墙则不参与抬高/收镜。
	return bool(collider.get_meta("camera_lower_wall", false))


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
	_floor_plan_snapshots.clear()
	_floor_seed_gate_edges.clear()
	_vertical_arrival_open.clear()
	_generated_floor_indices.clear()
	_floor_plan_commit_reasons.clear()
	_floor_layout_plan_conflicts.clear()
	_planned_floor_indices.clear()
	_boss_descent_gate_edges.clear()
	_airlock_front_edges.clear()
	_level_elevator_edge = ""

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
		Vector3(0.0, -FLOOR_HEIGHT, 5.0),
		"start", 1, "facility", Vector2(30.0, 30.0)
	)
	_declare_edge("start", "facility", "vertical", "west", "west", "west")
	_descent_side_sequence.append("west")

	# 纯数据规划可提前计算和存档；场景节点只保留99层与98层入口壳。
	# 其余房间、走廊和下一段楼梯均由下端到达门原子提交。
	for displayed_floor_number in range(98, DEEPEST_PLANNED_FLOOR - 1, -1):
		var sequence_index := 99 - displayed_floor_number
		var physical_floor_index := sequence_index + 1
		var stair_side := "east" if sequence_index % 2 == 1 else "west"
		var plan := FLOOR_PLAN_GENERATOR.generate({
			"run_seed": run_seed,
			"floor_number": displayed_floor_number,
			"floor_index": physical_floor_index,
			"sequence_index": sequence_index,
			"entry_side": stair_side,
			"boss_floor": displayed_floor_number % 5 == 0,
		})
		_floor_plan_snapshots[physical_floor_index] = plan.duplicate(true)
		_floor_layout_templates[physical_floor_index] = str(plan.get("layout_id", ""))
		_planned_floor_indices.append(physical_floor_index)
		if not bool(plan.get("valid", false)):
			for error_value in plan.get("validation_errors", []):
				_floor_layout_plan_conflicts.append(
					"floor %d generator: %s" % [physical_floor_index, str(error_value)]
				)
	# 初始只创建98层15×15入口安全屋。预置前门目标，保证壳体生成时门洞完整，
	# 但Hub节点和通道在到达门打开之前都不存在。
	var first_plan := _floor_plan_snapshots.get(2, {}) as Dictionary
	var first_entry := _plan_spec(first_plan, "entry")
	var first_hub := _plan_spec(first_plan, "hub")
	_append_plan_room_record(first_plan, first_entry, "facility")
	var entry_record := _find_record(str(first_entry.get("id", "")))
	var front_direction := _direction_between(
		entry_record.get("position", Vector3.ZERO) as Vector3,
		_plan_world_position(first_plan, first_hub)
	)
	(entry_record["doors"] as Array).append(front_direction)
	(entry_record["door_targets"] as Dictionary)[front_direction] = str(first_hub.get("id", ""))
	var first_vertical_edge := _edge_key("facility", str(first_entry.get("id", "")))
	_declare_edge("facility", str(first_entry.get("id", "")), "vertical", "east", "east", "east")
	_floor_seed_gate_edges[first_vertical_edge] = 2
	_descent_side_sequence.append("east")
	_validate_floor_layout_plans()


func _plan_spec(plan: Dictionary, key: String) -> Dictionary:
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		if str(spec.get("key", "")) == key:
			return spec
	return {}


func _plan_world_position(plan: Dictionary, spec: Dictionary) -> Vector3:
	var planar := spec.get("position", Vector2.ZERO) as Vector2
	return Vector3(planar.x, -FLOOR_HEIGHT * float(int(plan.get("floor_index", 2))), planar.y)


func _append_plan_room_record(plan: Dictionary, spec: Dictionary, parent_id: String) -> void:
	_append_tower_record(
		str(spec.get("id", "")), str(spec.get("type", "COMBAT")), "tower_cell",
		_plan_world_position(plan, spec), parent_id, int(plan.get("floor_index", 2)),
		str(spec.get("role", "room")),
		spec.get("dimensions", Vector2(30.0, 25.0)) as Vector2,
		spec.get("open_wall_directions", []) as Array
	)
	var record := _records.back() as Dictionary
	record["floor_layout_id"] = str(plan.get("layout_id", ""))
	record["floor_plan_key"] = str(spec.get("key", ""))
	record["floor_plan_main_path"] = str(spec.get("key", "")) in (plan.get("main_path_keys", []) as Array)


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
	var resolved_dimensions := (
		dimensions
		if dimensions.x > 0.0 and dimensions.y > 0.0
		else Vector2(TOWER_GEOMETRY.CORE_SIZE_M, TOWER_GEOMETRY.CORE_SIZE_M)
		if size in ["floor", "rooftop"]
		else Vector2(
			TOWER_GEOMETRY.COMBAT_ROOM_SIZE_M,
			TOWER_GEOMETRY.COMBAT_ROOM_SIZE_Y_M
		)
	)
	var snapped_position := position
	snapped_position.x = TOWER_GEOMETRY.snap_component_axis(
		position.x, resolved_dimensions.x
	)
	snapped_position.z = TOWER_GEOMETRY.snap_component_axis(
		position.z, resolved_dimensions.y
	)
	var record := _record(
		id, type_id, size, snapped_position, [], true, parent, _records.size(), -floor_index
	)
	record["custom_dimensions"] = resolved_dimensions
	record["grid_position_adjusted"] = not snapped_position.is_equal_approx(position)
	record["tower_module_shell"] = true
	record["floor_index"] = floor_index
	record["tower_role"] = role
	record["open_wall_directions"] = open_wall_directions.duplicate()
	_records.append(record)
	_room_floor_index[id] = floor_index
	if not _floor_room_ids.has(floor_index):
		_floor_room_ids[floor_index] = []
	(_floor_room_ids[floor_index] as Array).append(id)


func _validate_floor_layout_plans() -> void:
	var records_by_floor: Dictionary = {}
	for record_value in _records:
		var record := record_value as Dictionary
		var floor_index := int(record.get("floor_index", -1))
		if not records_by_floor.has(floor_index):
			records_by_floor[floor_index] = []
		(records_by_floor[floor_index] as Array).append(record)
	for floor_value in records_by_floor.keys():
		var floor_index := int(floor_value)
		var floor_records := records_by_floor[floor_index] as Array
		for first_index in range(floor_records.size()):
			var first := floor_records[first_index] as Dictionary
			var first_rect := _record_plan_rect(first)
			for second_index in range(first_index + 1, floor_records.size()):
				var second := floor_records[second_index] as Dictionary
				if first_rect.intersection(_record_plan_rect(second)).get_area() > 0.01:
					_floor_layout_plan_conflicts.append(
						"floor %d room %s overlaps room %s" % [
							floor_index,
							str(first.get("id", "")),
							str(second.get("id", "")),
						]
					)
	for declaration_value in _declared_edges:
		var declaration := declaration_value as Dictionary
		if str(declaration.get("kind", "")) != "vertical":
			continue
		var side := str(declaration.get("side", "west"))
		var reservation := _stair_plan_rect(side)
		for endpoint_key in ["a", "b"]:
			var endpoint_id := str(declaration.get(endpoint_key, ""))
			var floor_index := int(_room_floor_index.get(endpoint_id, -1))
			for record_value in records_by_floor.get(floor_index, []):
				var record := record_value as Dictionary
				if str(record.get("id", "")) == endpoint_id:
					continue
				if reservation.intersection(_record_plan_rect(record)).get_area() <= 0.01:
					continue
				_floor_layout_plan_conflicts.append(
					"floor %d room %s overlaps %s stair reservation" % [
						floor_index,
						str(record.get("id", "")),
						side,
					]
				)
	if not _floor_layout_plan_conflicts.is_empty():
		push_error(
			"Tower floor plan rejected before scene generation: %s"
			% "; ".join(_floor_layout_plan_conflicts)
		)


func _record_plan_rect(record: Dictionary) -> Rect2:
	var position := record.get("position", Vector3.ZERO) as Vector3
	var dimensions := record.get("custom_dimensions", Vector2.ZERO) as Vector2
	return Rect2(
		Vector2(position.x, position.z) - dimensions * 0.5,
		dimensions
	)


func _stair_plan_rect(side: String) -> Rect2:
	var outward := {
		"north": Vector2(0.0, -1.0),
		"south": Vector2(0.0, 1.0),
		"west": Vector2(-1.0, 0.0),
		"east": Vector2(1.0, 0.0),
	}.get(side, Vector2.LEFT) as Vector2
	var tangent := Vector2(outward.y, -outward.x)
	var interface := (
		TOWER_GEOMETRY.CORE_CENTER_XZ
		+ outward * (TOWER_GEOMETRY.CORE_SIZE_M * 0.5)
	)
	var corners: Array[Vector2] = []
	for outward_distance in [0.0, STAIR_PLAN_OUTWARD_DEPTH_M]:
		for tangent_distance in [
			-STAIR_PLAN_TANGENT_LENGTH_M * 0.10,
			STAIR_PLAN_TANGENT_LENGTH_M * 0.90,
		]:
			corners.append(
				interface
				+ outward * float(outward_distance)
				+ tangent * float(tangent_distance)
			)
	var minimum := corners[0]
	var maximum := corners[0]
	for corner in corners:
		minimum = minimum.min(corner)
		maximum = maximum.max(corner)
	return Rect2(minimum, maximum - minimum)


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
	if _boss_descent_gate_edges.has(edge):
		return {
			"requires_clear": false,
			"requires_key": false,
			"triggers_fate": false,
		}
	if _airlock_front_edges.has(edge):
		return {
			"requires_clear": false,
			"requires_key": false,
			"triggers_fate": false,
		}
	# 每层入口安全屋的前门都是 floor_seed_gate：免费开启，并在成功交互后
	# 原子提交该层规划。命运选择在下端到达门真正提交后触发，不能在楼梯
	# 上端门先触发或提前把下一层标成已生成。
	if _floor_seed_gate_edges.has(edge):
		return {
			"requires_clear": false,
			"requires_key": false,
			"triggers_fate": false,
		}
	return super(from_room_id, target_room_id)


func _try_open_room_door(target_room_id: String) -> bool:
	var edge := _edge_key(_current_room_id, target_room_id)
	if (
		edge == _edge_key("facility", "floor_01_entry")
		and _current_room_id == "floor_01_entry"
		and _initial_loop_gate_sealed
	):
		_show_initial_loop_retreat_warning()
		return true
	if _airlock_front_edges.has(edge) and _current_room_id == _active_airlock_room_id:
		_finalize_airlock_commit(int(_airlock_front_edges[edge]))
	if _boss_descent_gate_edges.has(edge) and not bool(_open_edges.get(edge, false)):
		if _boss_descent_key_count <= 0:
			status_label.text = "需要击败本段Boss并取得下行权限"
			return false
	var opened := super(target_room_id)
	# 基地门的物理开闭只负责通行表现；路线授权仍由 _open_edges 管理。
	# 这样门在玩家离开基地后能关回去，而下端到达门仍可识别已授权的楼梯。
	if opened and _current_room_id == "facility" and _is_facility_transit_edge(edge):
		# 已授权的垂直路线第二次按E会走通用“刷新已开边”分支。那个分支会
		# 保持下端到达门关闭，不能用于基地向外的可重复滑门；这里强制只打开
		# 基地这一侧的物理门板，路线状态和另一端到达门仍各自独立。
		var facility := _room_by_id.get("facility") as DungeonRoom3D
		var door_sides := _edge_door_sides_by_key.get(edge, {}) as Dictionary
		if facility != null:
			facility.set_door_open(str(door_sides.get("facility", "")), true)
		_facility_outbound_door_edge = edge
		# 自动关门必须先观察到玩家确实在基地屋体内，避免楼梯门槛、传送
		# 或房间事件的逻辑上下文把刚开启的门误判为“已从室内离开”。
		_facility_outbound_door_seen_inside = _is_player_within_facility_shell()
	if opened and _boss_descent_gate_edges.has(edge):
		_boss_descent_key_count = maxi(0, _boss_descent_key_count - 1)
	return opened


func _door_function_for_edge(a: String, b: String) -> String:
	var edge := _edge_key(a, b)
	if edge == _edge_key("start", "facility"):
		return "base_transit"
	if _boss_descent_gate_edges.has(edge):
		return "boss_descent"
	if _airlock_front_edges.has(edge):
		return "airlock_exit"
	if _floor_seed_gate_edges.has(edge):
		return "floor_arrival"
	if str(_edge_kind_by_key.get(edge, "horizontal")) == "vertical":
		return "vertical_transit"
	return "room_progression"


func _door_function_counts() -> Dictionary:
	var counts := {
		"base_transit": 0,
		"floor_arrival": 0,
		"room_progression": 0,
		"boss_descent": 0,
		"airlock_exit": 0,
		"vertical_transit": 0,
	}
	for declaration in _declared_edges:
		var function_id := _door_function_for_edge(
			str(declaration.get("a", "")), str(declaration.get("b", ""))
		)
		counts[function_id] = int(counts.get(function_id, 0)) + 1
	return counts


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
		# 楼顶↔99层基地↔98层入口：默认关闭，需在基地内按 E 开门；
		# 玩家通过后由 _on_room_entered 把门重新关回去，形成开关结构。
		# 出生后门是关的，所以出生位置（楼顶西侧）不会被自动滑门挡住。
		var opens_by_default := false
		_open_edges[edge] = opens_by_default
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
	_build_stair_approach_corridor(
		connector, upper_door, upper_interface, "Upper"
	)
	_build_stair_approach_corridor(
		connector, lower_interface, lower_door, "Lower"
	)
	_configure_stairwell_camera_walls(connector)


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
	var enclosure_collision_count := 0
	for body_value in visual.find_children("*", "StaticBody3D", true, false):
		var body := body_value as StaticBody3D
		if body != null and bool(body.get_meta("stair_enclosure_collision", false)):
			enclosure_collision_count += 1
	connector.set_meta("enclosure_collision_count", enclosure_collision_count)
	_stair_support_surface_count += walkable_collision_count


func _add_imported_stair_collisions(root: Node) -> int:
	var walkable_count := 0
	# 可走楼板和四面围护都直接从同一个可视Mesh生成同形碰撞。不能再用
	# 整段路径包围盒估算楼梯墙，否则包围盒会跨过接驳走廊伸进相邻房间，
	# 形成没有视觉组件对应的空气墙。
	var is_walkable := root is MeshInstance3D and "Walkable" in root.name
	var is_camera_stair_slab := (
		is_walkable
		and (
			"UpperFlight_Walkable" in root.name
			or "LowerFlight_Walkable" in root.name
		)
	)
	var is_enclosure_wall := (
		root is MeshInstance3D
		and "EnclosureWall_" in root.name
	)
	if is_walkable or is_enclosure_wall:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh != null:
			var shape := mesh_instance.mesh.create_trimesh_shape()
			if shape != null:
				var body := StaticBody3D.new()
				body.name = "%sCollisionBody" % mesh_instance.name
				body.collision_layer = 1
				body.collision_mask = 0
				body.set_meta("stair_enclosure_collision", is_enclosure_wall)
				body.set_meta("camera_stair_slab", is_camera_stair_slab)
				if is_camera_stair_slab:
					body.set_meta(
						"camera_stair_slab_role",
						"upper" if "UpperFlight_Walkable" in root.name else "lower"
					)
				body.set_meta("source_visual_name", mesh_instance.name)
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


func _plan_room_layout() -> void:
	# 门槽由连接两端的真实 5m 墙组件求交，不再各自选择“离房间中心最近”的槽。
	# 这保证房间旋转或奇偶格尺寸混接时，两扇门仍落在同一条 5m 通道中心线上。
	for room in _rooms:
		if room == null:
			continue
		for side in room.doors:
			var target_id := str(room.door_targets.get(side, ""))
			var target := _room_by_id.get(target_id) as DungeonRoom3D
			var target_side := _find_reciprocal_door_side(target, room.room_id)
			var shared_along := _shared_door_lane(room, side, target, target_side)
			var room_axis_center := (
				room.global_position.x
				if side in ["north", "south"]
				else room.global_position.z
			)
			room.set_meta(
				"tower_wall_door_offset_%s" % side,
				shared_along - room_axis_center
			)
	for room in _rooms:
		if room == null:
			continue
		for side in room.doors:
			room.set_meta(
				"room_door_world_%s" % side,
				_room_door_world_position(room, side)
			)


func _find_reciprocal_door_side(room: DungeonRoom3D, target_room_id: String) -> String:
	if room == null:
		return ""
	for side in room.doors:
		if str(room.door_targets.get(side, "")) == target_room_id:
			return side
	return ""


func _shared_door_lane(
	room: DungeonRoom3D,
	side: String,
	target: DungeonRoom3D,
	target_side: String
) -> float:
	var room_lanes := _door_lane_candidates(room, side)
	if room_lanes.is_empty():
		return room.global_position.x if side in ["north", "south"] else room.global_position.z
	var target_lanes := _door_lane_candidates(target, target_side)
	var desired := (
		(
			(room.global_position.x + target.global_position.x) * 0.5
			if side in ["north", "south"]
			else (room.global_position.z + target.global_position.z) * 0.5
		)
		if target != null
		else room_lanes[0]
	)
	var shared: Array[float] = []
	for lane in room_lanes:
		for target_lane in target_lanes:
			if is_equal_approx(lane, target_lane):
				shared.append(lane)
				break
	var candidates := shared if not shared.is_empty() else room_lanes
	var best := float(candidates[0])
	for candidate in candidates:
		if absf(float(candidate) - desired) < absf(best - desired):
			best = float(candidate)
	return best


func _door_lane_candidates(room: DungeonRoom3D, side: String) -> Array[float]:
	var lanes: Array[float] = []
	if room == null or side.is_empty():
		return lanes
	var dimensions := room.get_dimensions()
	var length := dimensions.x if side in ["north", "south"] else dimensions.y
	var module_count := maxi(1, int(round(length / TOWER_GEOMETRY.GRID_UNIT_M)))
	var first_index := 1 if module_count >= 3 else 0
	var last_index := module_count - 2 if module_count >= 3 else module_count - 1
	var axis_center := (
		room.global_position.x
		if side in ["north", "south"]
		else room.global_position.z
	)
	for module_index in range(first_index, last_index + 1):
		lanes.append(
			axis_center
			+ -length * 0.5
			+ TOWER_GEOMETRY.GRID_UNIT_M * (float(module_index) + 0.5)
		)
	return lanes


func _room_door_world_position(room: DungeonRoom3D, side: String) -> Vector3:
	var outward := {
		"north": Vector3(0, 0, -1),
		"south": Vector3(0, 0, 1),
		"west": Vector3(-1, 0, 0),
		"east": Vector3(1, 0, 0),
	}.get(side, Vector3(-1, 0, 0)) as Vector3
	var dimensions := room.get_dimensions()
	var half_extent := dimensions.y * 0.5 if side in ["north", "south"] else dimensions.x * 0.5
	# 如果是塔楼房间，门偏到沿墙最近模块位置（5m 偶数段会偏 ±2.5m）。
	var door_offset_along := 0.0
	if room.has_meta("tower_wall_door_offset_%s" % side):
		door_offset_along = float(room.get_meta("tower_wall_door_offset_%s" % side))
	var along_axis := Vector3(1, 0, 0) if side in ["north", "south"] else Vector3(0, 0, 1)
	return room.global_position + outward * half_extent + along_axis * door_offset_along


func _build_tower_horizontal_corridor(
	from_room: DungeonRoom3D,
	to_room: DungeonRoom3D,
	index: int,
	edge: String
) -> void:
	var delta := to_room.global_position - from_room.global_position
	var horizontal_x := absf(delta.x) >= absf(delta.z)
	var direction := Vector3(signf(delta.x), 0.0, 0.0) if horizontal_x else Vector3(0.0, 0.0, signf(delta.z))
	var from_side := "east" if direction.x > 0.0 else "west" if direction.x < 0.0 else "south" if direction.z > 0.0 else "north"
	var to_side := _opposite_direction(from_side)
	# 走廊端点必须取真实门组件坐标；房间中心只负责判断方向，不能再代替门位。
	var start := _room_door_world_position(from_room, from_side)
	var end := _room_door_world_position(to_room, to_side)
	var tangent_error := absf(start.z - end.z) if horizontal_x else absf(start.x - end.x)
	if tangent_error > 0.01:
		push_error(
			"Tower corridor %s door modules are off the 5m lane by %.3fm" % [
				edge, tangent_error,
			]
		)
	var center := (start + end) * 0.5
	var length := start.distance_to(end)
	var connector := Node3D.new()
	connector.name = "TowerRoomCorridor_%02d" % index
	connector.set_meta("is_vertical_connector", false)
	connector.set_meta("from_room_id", from_room.room_id)
	connector.set_meta("to_room_id", to_room.room_id)
	connector.set_meta("passage_width", TOWER_GEOMETRY.GRID_UNIT_M)
	connector.set_meta("start_door_position", start)
	connector.set_meta("end_door_position", end)
	connector.set_meta("door_tangent_error_m", tangent_error)
	var module_count := maxi(
		1,
		int(round(length / TOWER_GEOMETRY.GRID_UNIT_M))
	)
	connector.set_meta("module_count", module_count)
	connector.set_meta("floor_module_count", module_count)
	connector.set_meta("wall_module_count", module_count * 2)
	connector.set_meta(
		"module_coverage_length_m",
		float(module_count) * TOWER_GEOMETRY.GRID_UNIT_M
	)
	connector.visible = false
	connector.process_mode = Node.PROCESS_MODE_DISABLED
	$GeneratedCorridors.add_child(connector)
	_corridor_by_edge[edge] = connector
	# Boss竞技场与下行大厅共墙，两个门洞重合即构成通道；保留连接器状态节点，
	# 但不生成零长度地板或墙碰撞，避免透明阻挡。
	if length <= 0.05:
		connector.set_meta("module_count", 0)
		connector.set_meta("floor_module_count", 0)
		connector.set_meta("wall_module_count", 0)
		connector.set_meta("module_coverage_length_m", 0.0)
		return

	# 门到门距离始终是5m网格的整数倍。地面与双侧墙按实际长度逐格排布，
	# 但重复模块由 MultiMesh 批量提交，避免随机层一次生成后节点数随通道长度暴涨。
	# 不能只在中点放一块5m墙、再用整段碰撞补齐，否则长通道会形成空气墙。
	var perpendicular := Vector3(0.0, 0.0, 1.0) if horizontal_x else Vector3(1.0, 0.0, 0.0)
	var direction_from_start := start.direction_to(end)
	var floor_transforms: Array[Transform3D] = []
	var wall_transforms: Array[Transform3D] = []
	var wall_basis := Basis.IDENTITY if horizontal_x else Basis(Vector3.UP, PI * 0.5)
	var wall_mesh := _get_corridor_wall_module_mesh()
	# 当前实墙 GLB 的几何范围为 Y=0..9m，不能像碰撞盒那样把实例原点
	# 放在半层高。按 Mesh 底面反算偏移，确保以后原点调整后仍贴住楼面。
	var wall_floor_offset_y := -wall_mesh.get_aabb().position.y if wall_mesh != null else 0.0
	for module_index in range(module_count):
		var module_center := (
			start
			+ direction_from_start * TOWER_GEOMETRY.GRID_UNIT_M
			* (float(module_index) + 0.5)
		)
		floor_transforms.append(
			Transform3D(Basis.IDENTITY, module_center + Vector3.UP * 0.015)
		)
		for side_sign in [-1.0, 1.0]:
			wall_transforms.append(
				Transform3D(
					wall_basis,
					module_center
					+ perpendicular * side_sign
					* (TOWER_GEOMETRY.GRID_UNIT_M * 0.5)
					+ Vector3.UP * wall_floor_offset_y
				)
			)
	_add_horizontal_corridor_multimesh(
		connector,
		"ImportedCorridorFloorGrid5M",
		_get_corridor_floor_module_mesh(),
		floor_transforms,
		"ENV-TOWER-FLOOR-TILE-5M",
		"floor"
	)
	_add_horizontal_corridor_multimesh(
		connector,
		"ImportedCorridorWallGrid5M",
		wall_mesh,
		wall_transforms,
		"ENV-TOWER-WALL-SOLID-5M",
		"wall"
	)
	# 两侧碰撞保持整段连续盒体，不在5m拼缝处分割，避免角色和子弹卡缝。
	for side_sign in [-1.0, 1.0]:
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
			Vector3.ZERO,
			false,
			true,
			# 只让东西向通道世界南侧的实墙参与固定镜头抬升；
			# 南北向通道的两侧是东/西墙，不应触发。
			horizontal_x and side_sign > 0.0
		)
	connector.set_meta(
		"south_camera_wall_count",
		1 if horizontal_x else 0
	)


func _add_horizontal_corridor_multimesh(
	connector: Node3D,
	node_name: String,
	mesh: Mesh,
	transforms: Array[Transform3D],
	asset_id: String,
	module_kind: String
) -> void:
	if mesh == null or transforms.is_empty():
		push_error("Tower corridor %s mesh is unavailable" % module_kind)
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var visual := MultiMeshInstance3D.new()
	visual.name = node_name
	visual.multimesh = multimesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	visual.set_meta("asset_id", asset_id)
	visual.set_meta("horizontal_corridor_module_batch", true)
	visual.set_meta("corridor_module_kind", module_kind)
	visual.set_meta("corridor_module_instance_count", transforms.size())
	var module_origins := PackedVector3Array()
	for module_transform in transforms:
		module_origins.append(module_transform.origin)
	# Dummy/headless 渲染器不会回读 MultiMesh transform buffer；保留生成坐标清单，
	# 让网格、覆盖范围和随机种子回归仍可精确验证。
	visual.set_meta("corridor_module_origins", module_origins)
	connector.add_child(visual)


func _get_corridor_floor_module_mesh() -> Mesh:
	if _corridor_floor_module_mesh == null:
		_corridor_floor_module_mesh = _mesh_from_packed_scene(TOWER_FLOOR_TILE_SCENE)
	return _corridor_floor_module_mesh


func _get_corridor_wall_module_mesh() -> Mesh:
	if _corridor_wall_module_mesh == null:
		_corridor_wall_module_mesh = _mesh_from_packed_scene(TOWER_WALL_SCENE)
	return _corridor_wall_module_mesh


func _mesh_from_packed_scene(scene: PackedScene) -> Mesh:
	if scene == null:
		return null
	var instance := scene.instantiate()
	var mesh := _find_first_imported_mesh(instance)
	instance.free()
	return mesh


func _find_first_imported_mesh(root: Node) -> Mesh:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		return (root as MeshInstance3D).mesh
	for child in root.get_children():
		var mesh := _find_first_imported_mesh(child)
		if mesh != null:
			return mesh
	return null

func _build_stair_approach_corridor(
	connector: Node3D,
	start: Vector3,
	end: Vector3,
	label: String
) -> void:
	var delta := end - start
	delta.y = 0.0
	var length := delta.length()
	if length <= 0.05:
		return
	var along_x := absf(delta.x) >= absf(delta.z)
	var module_count := maxi(
		1,
		int(round(length / TOWER_GEOMETRY.GRID_UNIT_M))
	)
	var direction := delta.normalized()
	var center := (start + end) * 0.5
	center.y = start.y
	var perpendicular := (
		Vector3(0.0, 0.0, 1.0)
		if along_x
		else Vector3(1.0, 0.0, 0.0)
	)
	var wall_rotation_y := 0.0 if along_x else PI * 0.5
	for module_index in range(module_count):
		var module_center := (
			start
			+ direction * TOWER_GEOMETRY.GRID_UNIT_M
			* (float(module_index) + 0.5)
		)
		var floor_tile := TOWER_FLOOR_TILE_SCENE.instantiate() as Node3D
		floor_tile.name = "StairApproachFloor_%s_I%02d" % [
			label,
			module_index,
		]
		floor_tile.position = module_center + Vector3.UP * 0.015
		floor_tile.set_meta("asset_id", "ENV-TOWER-FLOOR-TILE-5M")
		floor_tile.set_meta("stair_approach_corridor", true)
		connector.add_child(floor_tile)
		for side_sign in [-1.0, 1.0]:
			var wall := TOWER_WALL_SCENE.instantiate() as Node3D
			wall.name = "StairApproachWall_%s_%s_I%02d" % [
				label,
				"A" if side_sign < 0.0 else "B",
				module_index,
			]
			wall.position = (
				module_center
				+ perpendicular * side_sign
				* (TOWER_GEOMETRY.PASSAGE_WIDTH_M * 0.5)
			)
			wall.rotation.y = wall_rotation_y
			wall.set_meta("asset_id", "ENV-TOWER-WALL-SOLID-5M")
			wall.set_meta("stair_approach_corridor", true)
			connector.add_child(wall)
	for side_sign in [-1.0, 1.0]:
		var side_name := (
			("North" if side_sign < 0.0 else "South")
			if along_x
			else ("West" if side_sign < 0.0 else "East")
		)
		_add_connector_box(
			connector,
			"StairApproachWall_%s_%s" % [label, side_name],
			center
			+ perpendicular * side_sign
			* (TOWER_GEOMETRY.PASSAGE_WIDTH_M * 0.5)
			+ Vector3.UP * (FLOOR_HEIGHT * 0.5),
			(
				Vector3(length, FLOOR_HEIGHT, 0.30)
				if along_x
				else Vector3(0.30, FLOOR_HEIGHT, length)
			),
			Vector3.ZERO,
			false,
			true,
			along_x and side_sign > 0.0
		)
	connector.set_meta(
		"stair_approach_%s_module_count" % label.to_lower(),
		module_count
	)


func _configure_stairwell_camera_walls(connector: Node3D) -> void:
	# 楼梯间同样只让世界南侧朝北的可视墙触发抬镜。直接依据导入墙体的
	# 世界AABB选择最南侧水平墙，避免组件旋转后依赖不稳定的本地名称。
	var south_body: StaticBody3D = null
	var south_z := -INF
	for value in connector.find_children("*", "StaticBody3D", true, false):
		var body := value as StaticBody3D
		if body == null or not bool(body.get_meta("stair_enclosure_collision", false)):
			continue
		body.set_meta("camera_lower_wall", false)
		var visual := body.get_parent() as MeshInstance3D
		if visual == null or visual.mesh == null:
			continue
		var world_aabb := visual.global_transform * visual.get_aabb()
		if world_aabb.size.x <= world_aabb.size.z:
			continue
		var center_z := world_aabb.get_center().z
		if center_z > south_z:
			south_z = center_z
			south_body = body
	if south_body != null:
		south_body.set_meta("camera_lower_wall", true)


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
	# 默认禁用（走廊墙/楼梯护栏/门楣都有视觉 prefab 自带碰撞）。
	# 楼梯围护碰撞只在连接器可见且开放时启用，不能留下隐藏阻挡。
	collision.disabled = not collision_enabled
	collision.set_meta("persistent_stair_support", is_support)
	body.set_meta("camera_lower_wall", camera_lower_wall)
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
	return _activate_stair_arrival(candidate)


func _activate_stair_arrival(candidate: Dictionary) -> bool:
	var edge := str(candidate.get("edge", ""))
	var lower_room := candidate.get("lower_room") as DungeonRoom3D
	var lower_door := candidate.get("lower_door") as RoomDoor3D
	if edge.is_empty() or lower_room == null or lower_door == null:
		return false
	if _boss_descent_gate_edges.has(edge):
		_pending_airlock_candidate = candidate.duplicate()
		_show_airlock_warning()
		return true
	var floor_index := int(_room_floor_index.get(lower_room.room_id, 0))
	var bundle_floor_index := int(_floor_seed_gate_edges.get(edge, -1))
	if bundle_floor_index >= 0 and not _commit_floor_bundle(bundle_floor_index, "arrival_gate"):
		return true
	_vertical_arrival_open[edge] = true
	lower_door.set_open(true)
	if edge == _edge_key("facility", "floor_01_entry"):
		_initial_loop_gate_armed = true
	# 保留跨门之前的真实房间，避免 _on_room_entered 把它误当成"上一个房间"。
	_stair_arrival_previous_room = _current_room_id
	_on_room_entered(lower_room)
	if bundle_floor_index >= 0:
		var plan := _floor_plan_snapshots.get(bundle_floor_index, {}) as Dictionary
		status_label.text = "%d层已建立 · 主路%d房 · 支线%d条" % [
			int(plan.get("floor_number", _floor_number_from_index(bundle_floor_index))),
			int(plan.get("main_path_content_count", 0)),
			int(plan.get("branch_count", 0)),
		]
	else:
		status_label.text = "%d层交通门已开启 · 未触发关卡生成" % _floor_number_from_index(floor_index)
	return true


func _on_initial_loop_entry_physically_entered(room: DungeonRoom3D) -> void:
	if room == null or room.room_id != "floor_01_entry" or not _initial_loop_gate_armed or _initial_loop_gate_sealed:
		return
	var edge := _edge_key("facility", room.room_id)
	_open_edges[edge] = false
	minimap.set_edge_open("facility", room.room_id, false)
	_refresh_edge_visuals("facility", room.room_id, false)
	_initial_loop_gate_sealed = true
	status_label.text = "98–95F Boss大循环已开始 · 身后入口已封闭 · 反向开门将视为撤退"


func _show_initial_loop_retreat_warning() -> void:
	if _initial_loop_retreat_overlay != null and is_instance_valid(_initial_loop_retreat_overlay):
		return
	var overlay := Control.new()
	overlay.name = "InitialLoopRetreatWarning"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 920
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.0, 0.0, 0.78)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-310, -145)
	panel.custom_minimum_size = Vector2(620, 290)
	panel.add_theme_stylebox_override("panel", _make_hud_style(Color(1.0, 0.24, 0.18), Color(0.05, 0.008, 0.010, 0.98), 3))
	overlay.add_child(panel)
	var margin := _make_margin(24, 22, 24, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title := _make_hud_label("放弃 98–95F Boss 大循环？", 24, Color(1.0, 0.36, 0.28))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var detail := _make_hud_label("确认撤退后，背包内全部物品以及主武器、副武器都会永久丢失。\n保险格按保险规则保留；此操作不可撤销。", 15, Color(0.94, 0.88, 0.86))
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	box.add_child(buttons)
	var cancel := Button.new()
	cancel.text = "取消 · 留在98F"
	cancel.custom_minimum_size = Vector2(190, 48)
	cancel.pressed.connect(_cancel_initial_loop_retreat)
	buttons.add_child(cancel)
	var confirm := Button.new()
	confirm.text = "确认撤退 · 全部丢失"
	confirm.custom_minimum_size = Vector2(220, 48)
	confirm.pressed.connect(_confirm_initial_loop_retreat)
	buttons.add_child(confirm)
	$HUD.add_child(overlay)
	_initial_loop_retreat_overlay = overlay
	cancel.grab_focus()
	_sync_player_input_lock()


func _cancel_initial_loop_retreat() -> void:
	if _initial_loop_retreat_overlay != null and is_instance_valid(_initial_loop_retreat_overlay):
		_initial_loop_retreat_overlay.queue_free()
	_initial_loop_retreat_overlay = null
	_sync_player_input_lock()
	status_label.text = "已取消撤退 · 入口继续封闭"


func _confirm_initial_loop_retreat() -> void:
	var discarded_inventory := _inventory.get_occupied_slots().size() if _inventory != null else 0
	var discarded_backpack := player.get_equipped_backpack_item() if player != null and player.has_method("get_equipped_backpack_item") else {}
	if _inventory != null:
		_inventory.clear_all()
		_inventory.resize_capacity_collect_overflow(BASE_INVENTORY_CAPACITY)
	var discarded_weapons: Array[Dictionary] = []
	if player != null and player.has_method("clear_all_equipped_weapons"):
		discarded_weapons = player.call("clear_all_equipped_weapons") as Array[Dictionary]
	if player != null and player.has_method("clear_equipped_backpack"):
		player.call("clear_equipped_backpack")
	_emit_backpack_equipment_changed()
	_quick_item_ids = ["", ""]
	if _inventory_ui != null:
		_inventory_ui.set_quick_item_assignments(_quick_item_ids)
	_refresh_quick_item_hud()
	FateCardGameBridge.reset_run_state()
	_cancel_initial_loop_retreat()
	var facility_room := _room_by_id.get("facility") as DungeonRoom3D
	if facility_room != null:
		player.global_position = facility_room.global_position + Vector3(0.0, 0.05, 2.7)
		player.velocity = Vector3.ZERO
		_on_room_entered(facility_room)
	_reset_initial_loop_world_after_retreat()
	status_label.text = "已撤退至99F基地 · 丢失物品%d格、装备武器%d把、背包%d个" % [
		discarded_inventory, discarded_weapons.size(), 0 if discarded_backpack.is_empty() else 1,
	]


func _reset_initial_loop_world_after_retreat() -> void:
	# 撤退不是一次普通跨房传送，而是放弃98–95F整个行动事务。必须销毁
	# 首门开启后提交的全部楼层、门状态与运行缓存，再恢复为新场景的3房壳体。
	# 若只把edge关上，残留的_vertical_arrival_open和sealed标志会让玩家
	# 再次从基地下来时看到下端门常开，并跳过“首次进入后封门”的循环。
	_unload_completed_segment(6)
	_generated_floor_indices.assign([0])
	for floor_value in _floor_plan_commit_reasons.keys().duplicate():
		if int(floor_value) >= 2:
			_floor_plan_commit_reasons.erase(floor_value)
	_unloaded_segment_floor_indices.clear()
	_floor_seed_gate_edges.clear()
	_boss_descent_gate_edges.clear()
	_airlock_front_edges.clear()
	_pending_airlock_candidate.clear()
	_active_airlock_room_id = ""
	_boss_descent_key_count = 0
	_level_elevator_edge = ""
	_unlocked_elevator_floors = {99: true}
	_last_bundle_room_count = 0
	_last_bundle_corridor_count = 0
	_last_unloaded_room_count = 0
	_last_destroyed_world_loot_count = 0
	_initial_loop_gate_armed = false
	_initial_loop_gate_sealed = false
	_descent_side_sequence.assign(["west"])

	var first_plan := _floor_plan_snapshots.get(2, {}) as Dictionary
	var first_entry := _plan_spec(first_plan, "entry")
	var first_hub := _plan_spec(first_plan, "hub")
	_append_plan_room_record(first_plan, first_entry, "facility")
	var entry_id := str(first_entry.get("id", "floor_01_entry"))
	var entry_record := _find_record(entry_id)
	var front_direction := _direction_between(
		entry_record.get("position", Vector3.ZERO) as Vector3,
		_plan_world_position(first_plan, first_hub)
	)
	(entry_record["doors"] as Array).append(front_direction)
	(entry_record["door_targets"] as Dictionary)[front_direction] = str(first_hub.get("id", ""))
	var edge := _edge_key("facility", entry_id)
	_declare_and_register_edge("facility", entry_id, "vertical", "east", "east", "east")
	_floor_seed_gate_edges[edge] = 2
	_descent_side_sequence.append("east")
	# 与首次加载一致：基地侧楼梯可通行，但98F下端到达门保持关闭，
	# 只有再次交互并成功提交98层FloorBundle后才会打开。
	_open_edges[edge] = true
	_vertical_arrival_open[edge] = false
	_instantiate_dynamic_room(entry_record)
	# 撤退重建也必须遵循正常 FloorBundle 的顺序：先让连接两端共同计算
	# 5m 门槽，再生成房间壳体与楼梯接驳。否则新入口会按默认 0 偏移
	# 开门，而旧基地门及连接器仍位于规划门槽，表现为门已打开但墙体
	# 碰撞留在通道中的“空气墙”。
	_plan_room_layout()
	var entry_room := _room_by_id.get(entry_id) as DungeonRoom3D
	var base_room := _room_by_id.get("facility") as DungeonRoom3D
	if base_room != null and entry_room != null:
		_build_corridor(base_room, entry_room, _corridor_by_edge.size())
		if not entry_room.player_entered.is_connected(_on_initial_loop_entry_physically_entered):
			entry_room.player_entered.connect(_on_initial_loop_entry_physically_entered)
	_rebuild_floor_stage(2)
	_refresh_edge_visuals("facility", entry_id, true)
	minimap.configure(_records, _open_edges)
	_update_room_streaming("facility")


func confirm_initial_loop_retreat_for_test() -> void:
	_confirm_initial_loop_retreat()


func try_open_stair_arrival_for_test() -> bool:
	return _try_open_nearby_stair_arrival()


func activate_arrival_between_for_test(upper_room_id: String, lower_room_id: String) -> bool:
	var edge := _edge_key(upper_room_id, lower_room_id)
	var connector := _corridor_by_edge.get(edge) as Node3D
	var lower_room := _room_by_id.get(lower_room_id) as DungeonRoom3D
	if connector == null or lower_room == null:
		return false
	lower_room.ensure_shell_built()
	var door_sides := _edge_door_sides_by_key.get(edge, {}) as Dictionary
	var lower_side := str(door_sides.get(lower_room_id, connector.get_meta("lower_door_side", "west")))
	var lower_door := lower_room.get_door_node(lower_side)
	if lower_door == null:
		return false
	return _activate_stair_arrival({
		"edge": edge,
		"connector": connector,
		"lower_room": lower_room,
		"lower_door": lower_door,
		"lower_room_id": lower_room_id,
	})


func _show_airlock_warning() -> void:
	if _airlock_warning_overlay != null and is_instance_valid(_airlock_warning_overlay):
		return
	var panel := PanelContainer.new()
	panel.name = "SegmentAirlockWarning"
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(520.0, 220.0)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var title := Label.new()
	title.text = "跨段隔离确认"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var detail := Label.new()
	detail.text = "进入隔离间后，未拾取物将永久丢失；旧段房间、敌人和碰撞将卸载。\n默认取消，确认后才打开下端门。"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(detail)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	var cancel_button := Button.new()
	cancel_button.text = "取消"
	cancel_button.pressed.connect(cancel_airlock_transition)
	buttons.add_child(cancel_button)
	var confirm_button := Button.new()
	confirm_button.text = "确认进入"
	confirm_button.pressed.connect(confirm_airlock_transition)
	buttons.add_child(confirm_button)
	$HUD.add_child(panel)
	_airlock_warning_overlay = panel
	cancel_button.grab_focus()


func cancel_airlock_transition() -> void:
	_pending_airlock_candidate.clear()
	if _airlock_warning_overlay != null and is_instance_valid(_airlock_warning_overlay):
		_airlock_warning_overlay.queue_free()
	_airlock_warning_overlay = null
	status_label.text = "已取消跨段，下端门保持关闭"


func confirm_airlock_transition() -> bool:
	if _pending_airlock_candidate.is_empty():
		return false
	var candidate := _pending_airlock_candidate.duplicate()
	_pending_airlock_candidate.clear()
	if _airlock_warning_overlay != null and is_instance_valid(_airlock_warning_overlay):
		_airlock_warning_overlay.queue_free()
	_airlock_warning_overlay = null
	var edge := str(candidate.get("edge", ""))
	var lower_room := candidate.get("lower_room") as DungeonRoom3D
	var lower_door := candidate.get("lower_door") as RoomDoor3D
	if edge.is_empty() or lower_room == null or lower_door == null:
		return false
	var floor_index := int(_room_floor_index.get(lower_room.room_id, 0))
	if not _commit_floor_bundle(floor_index, "boss_airlock_confirm"):
		return false
	_vertical_arrival_open[edge] = true
	lower_door.set_open(true)
	_active_airlock_room_id = lower_room.room_id
	_on_room_entered(lower_room)
	status_label.text = "隔离间已开启 · 穿过后旧段未拾取物永久丢失"
	return true


func _update_corridor_streaming(current_id: String) -> void:
	for edge in _corridor_by_edge.keys():
		var connector := _corridor_by_edge[edge] as Node3D
		if connector == null:
			continue
		var ids := str(edge).split("|")
		var active := bool(_open_edges.get(edge, false)) and current_id in ids
		connector.visible = active
		connector.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		# 连接器隐藏时所有碰撞一并卸载；不能保留看不见但仍挡角色/子弹的楼梯面。
		_set_connector_collision_enabled(connector, active, false)


func _set_connector_collision_enabled(
	root: Node,
	enabled: bool,
	support_enabled := false
) -> void:
	if root is CollisionShape3D:
		var collision := root as CollisionShape3D
		var persistent_support := bool(collision.get_meta("persistent_stair_support", false))
		collision.set_deferred(
			"disabled",
			not ((enabled or support_enabled) if persistent_support else enabled)
		)
	for child in root.get_children():
		_set_connector_collision_enabled(child, enabled, support_enabled)


func _on_room_entered(room: DungeonRoom3D) -> void:
	if room != null and _is_locked_stair_arrival_room(room.room_id):
		return
	var previous_room_id := _current_room_id
	super(room)
	if room == null:
		return
	# 基地房门为开关结构：玩家跨过门后立刻把基地侧/邻房侧门一起关上。
	# 仅当玩家确实走进新房间时才关门——_activate_stair_arrival 在开门瞬间会
	# 触发一次虚拟 _on_room_entered，那时玩家还站在门外，避免误关。
	var seal_previous_room_id := previous_room_id
	if not _stair_arrival_previous_room.is_empty():
		seal_previous_room_id = _stair_arrival_previous_room
	if _is_player_inside_room(room):
		_seal_facility_doors_after_transition(seal_previous_room_id, room.room_id)
		_stair_arrival_previous_room = ""
	var depth := maxi(0, -int(round(room.global_position.y / FLOOR_HEIGHT)))
	if room.room_id == "start":
		room_label.text = "楼顶 · 250m整层 / 65m核心"
	elif room.room_id == "facility":
		room_label.text = "99层基地 · 30×30m / 6×6地砖 · 安全区"
		if not test_mode and BaseManager != null:
			BaseManager.mark_tutorial_completed()
	else:
		var role := str(_find_record(room.room_id).get("tower_role", "room"))
		var floor_number := 100 - depth
		if room.room_type == "STAIR_LOBBY":
			var lobby_name := "楼梯出口大厅" if role == "stair_exit" else "楼梯入口大厅"
			room_label.text = "%d层 · %s · 交通区" % [floor_number, lobby_name]
		else:
			room_label.text = "%d层 · %s · %s" % [
				floor_number,
				"本批Boss层" if floor_number == 95 else role,
				room.room_type,
			]
	_update_facility_combat_lock()
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


func _is_player_inside_room(room: DungeonRoom3D) -> bool:
	if room == null or player == null:
		return false
	var local_pos := room.to_local(player.global_position)
	var dims := room.get_dimensions()
	return (
		absf(local_pos.x) <= dims.x * 0.42
		and absf(local_pos.z) <= dims.y * 0.42
		and absf(local_pos.y) <= 1.8
	)


func is_player_inside_facility() -> bool:
	# 开火锁定只依赖基地室内的实际空间，不依赖房间触发器、门状态或路线状态。
	var facility := _room_by_id.get("facility") as DungeonRoom3D
	if facility == null or player == null:
		return false
	var local_pos := facility.to_local(player.global_position)
	var dimensions := facility.get_dimensions()
	return (
		absf(local_pos.x) <= dimensions.x * 0.47
		and absf(local_pos.z) <= dimensions.y * 0.47
		and absf(local_pos.y) <= 1.8
	)


func _is_player_within_facility_shell() -> bool:
	# 自动门使用略大于禁射范围的建筑壳体，而不是同一个战斗边界；门口仍算
	# 在屋内，直到角色真正跨过墙体外侧，才允许执行一次自动关闭。
	var facility := _room_by_id.get("facility") as DungeonRoom3D
	if facility == null or player == null:
		return false
	var local_pos := facility.to_local(player.global_position)
	var dimensions := facility.get_dimensions()
	return (
		absf(local_pos.x) <= dimensions.x * 0.505
		and absf(local_pos.z) <= dimensions.y * 0.505
		and absf(local_pos.y) <= 2.2
	)


func _update_facility_combat_lock() -> void:
	if player == null:
		return
	var should_enable_combat := not is_player_inside_facility()
	if player.combat_enabled != should_enable_combat:
		player.set_combat_enabled(should_enable_combat)


func _is_facility_transit_edge(edge: String) -> bool:
	return edge in [
		_edge_key("start", "facility"),
		_edge_key("facility", "floor_01_entry"),
	]


func _update_facility_door_auto_close() -> void:
	if _facility_outbound_door_edge.is_empty() or player == null:
		return
	var door_sides := _edge_door_sides_by_key.get(_facility_outbound_door_edge, {}) as Dictionary
	var facility_side := str(door_sides.get("facility", ""))
	var facility := _room_by_id.get("facility") as DungeonRoom3D
	if facility == null or facility_side.is_empty():
		_facility_outbound_door_edge = ""
		_facility_outbound_door_seen_inside = false
		return
	if _is_player_within_facility_shell():
		_facility_outbound_door_seen_inside = true
		return
	if not _facility_outbound_door_seen_inside:
		return
	var local_pos := facility.to_local(player.global_position)
	var dimensions := facility.get_dimensions()
	var margin := 0.25
	var has_left_through_opening := (
		local_pos.x < -dimensions.x * 0.5 - margin if facility_side == "west"
		else local_pos.x > dimensions.x * 0.5 + margin if facility_side == "east"
		else local_pos.z < -dimensions.y * 0.5 - margin if facility_side == "north"
		else local_pos.z > dimensions.y * 0.5 + margin if facility_side == "south"
		else false
	)
	if not has_left_through_opening:
		return
	_set_facility_transit_door_visual(_facility_outbound_door_edge, false)
	_facility_outbound_door_edge = ""
	_facility_outbound_door_seen_inside = false


func _set_facility_transit_door_visual(edge: String, opened: bool) -> void:
	var endpoints := edge.split("|")
	if endpoints.size() != 2:
		return
	_refresh_edge_visuals(str(endpoints[0]), str(endpoints[1]), opened)


func _seal_facility_doors_after_transition(previous_room_id: String, new_room_id: String) -> void:
	# 基地交通门跨过后只关闭物理门板。路线状态保持已授权，避免关闭上端门后
	# 下端到达门失去楼梯授权；98F首门的不可逆封闭仍由专门流程处理。
	if previous_room_id.is_empty() or previous_room_id == new_room_id:
		return
	if previous_room_id != "facility" and new_room_id != "facility":
		return
	var other_room_id := previous_room_id if new_room_id == "facility" else new_room_id
	var edge := _edge_key("facility", other_room_id)
	if not _is_facility_transit_edge(edge):
		return
	_set_facility_transit_door_visual(edge, false)
	_facility_outbound_door_edge = ""
	_facility_outbound_door_seen_inside = false


func _update_room_streaming(current_id: String) -> void:
	super(current_id)
	_update_floor_visibility_state()
	_refresh_facility_runtime()


func _ensure_floor_generated(floor_index: int, reason := "runtime") -> void:
	if floor_index < 0 or floor_index in _generated_floor_indices:
		return
	# 楼层首次触发时，以整层为最小布局事务：一次冻结全部房间组件坐标、
	# 门轴、水平通道及上下楼梯接口。Mesh实体仍按当前房/已开启邻房流送，
	# 避免四层全部常驻造成节点预算失控；流送绝不能再改动布局坐标。
	for room_id_value in _floor_room_ids.get(floor_index, []):
		var room := _room_by_id.get(str(room_id_value)) as DungeonRoom3D
		if room == null:
			continue
		room.set_meta("floor_plan_generated", true)
		room.set_meta("floor_plan_commit_reason", reason)
		room.set_meta(
			"floor_layout_id",
			str((_floor_plan_snapshots.get(floor_index, {}) as Dictionary).get("layout_id", ""))
		)
		room.set_meta("floor_plan_position", room.position)
		room.set_meta("floor_plan_dimensions", room.get_dimensions())
	for edge_value in _corridor_by_edge.keys():
		var edge := str(edge_value)
		var connector := _corridor_by_edge.get(edge) as Node3D
		if connector == null:
			continue
		var from_id := str(connector.get_meta("from_room_id", ""))
		var to_id := str(connector.get_meta("to_room_id", ""))
		if (
			int(_room_floor_index.get(from_id, -2)) != floor_index
			and int(_room_floor_index.get(to_id, -2)) != floor_index
		):
			continue
		connector.set_meta("floor_plan_generated_%d" % floor_index, true)
	_generated_floor_indices.append(floor_index)
	_generated_floor_indices.sort()
	_floor_plan_commit_reasons[floor_index] = reason


func _commit_floor_bundle(floor_index: int, reason := "arrival_gate") -> bool:
	if floor_index in _generated_floor_indices:
		return true
	var plan := _floor_plan_snapshots.get(floor_index, {}) as Dictionary
	if plan.is_empty() or not bool(plan.get("valid", false)):
		status_label.text = "楼层规划校验失败，入口门保持关闭"
		return false
	var before_rooms := _rooms.size()
	var before_corridors := _corridor_by_edge.size()
	var ids_by_key: Dictionary = {}
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		ids_by_key[str(spec.get("key", ""))] = str(spec.get("id", ""))
	# 入口壳已由上一层事务创建；本次只补齐其余房间。
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		if str(spec.get("key", "")) == "entry":
			continue
		var parent_key := str(spec.get("parent_key", ""))
		_append_plan_room_record(plan, spec, str(ids_by_key.get(parent_key, "")))
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		var parent_key := str(spec.get("parent_key", ""))
		if parent_key.is_empty():
			continue
		_declare_and_register_edge(
			str(ids_by_key.get(parent_key, "")), str(spec.get("id", "")), "horizontal"
		)

	var current_exit_id := str(ids_by_key.get("exit", ""))
	var next_floor_index := floor_index + 1
	var next_plan := _floor_plan_snapshots.get(next_floor_index, {}) as Dictionary
	if not next_plan.is_empty():
		_append_next_arrival_shell(plan, current_exit_id, next_plan)

	# 记录、拓扑全部有效后才实例化，避免半层节点留在场景树中。
	for record in _records:
		var room_id := str(record.get("id", ""))
		if not _room_by_id.has(room_id):
			_instantiate_dynamic_room(record)
	_plan_room_layout()
	for declaration in _declared_edges:
		var edge := _edge_key(str(declaration["a"]), str(declaration["b"]))
		if _corridor_by_edge.has(edge):
			continue
		var parent := _room_by_id.get(str(declaration["a"])) as DungeonRoom3D
		var child := _room_by_id.get(str(declaration["b"])) as DungeonRoom3D
		if parent != null and child != null:
			_build_corridor(parent, child, _corridor_by_edge.size())
	minimap.configure(_records, _open_edges)
	_rebuild_floor_stage(floor_index)
	if _floor_room_ids.has(next_floor_index):
		_rebuild_floor_stage(next_floor_index)
	_ensure_floor_generated(floor_index, reason)
	_last_bundle_room_count = _rooms.size() - before_rooms
	_last_bundle_corridor_count = _corridor_by_edge.size() - before_corridors
	if bool(plan.get("boss_floor", false)) and _extraction == null:
		var boss_room := _room_by_id.get("extraction") as DungeonRoom3D
		if boss_room != null:
			_extraction = _create_extraction_beacon(boss_room, "BOSS_KILL", 30.0, true, Vector3.ZERO)
			_conditional_extractions["BOSS_KILL"] = _extraction
	if int(plan.get("floor_number", 0)) == 95 and not _elevator_facilities_by_floor.has(95):
		var exit_room := _room_by_id.get(current_exit_id) as DungeonRoom3D
		if exit_room != null:
			var pose := _elevator_wall_pose(exit_room)
			var level_elevator := _create_standalone_elevator(
				95, current_exit_id, pose["position"] as Vector3, float(pose["rotation_y"])
			)
			level_elevator.set_meta("unique_level_elevator", true)
	_update_floor_visibility_state()
	return true


func _append_next_arrival_shell(
	current_plan: Dictionary, current_exit_id: String, next_plan: Dictionary
) -> void:
	var next_entry := (_plan_spec(next_plan, "entry") as Dictionary).duplicate(true)
	var next_hub := _plan_spec(next_plan, "hub")
	var upper_floor_number := int(current_plan.get("floor_number", 98))
	var next_floor_index := int(next_plan.get("floor_index", 3))
	var lower_endpoint_id := str(next_entry.get("id", ""))
	if upper_floor_number % 5 == 0:
		var original_position := next_entry.get("position", Vector2.ZERO) as Vector2
		var hub_position := next_hub.get("position", Vector2.ZERO) as Vector2
		var toward_hub := (hub_position - original_position).normalized()
		next_entry["position"] = original_position + toward_hub * 20.0
		lower_endpoint_id = "airlock_%d_%d" % [upper_floor_number, upper_floor_number - 1]
		_append_tower_record(
			lower_endpoint_id, "STAIR_LOBBY", "tower_cell",
			Vector3(original_position.x, -FLOOR_HEIGHT * float(next_floor_index), original_position.y),
			current_exit_id, next_floor_index, "segment_airlock", Vector2(15.0, 15.0)
		)
	_append_plan_room_record(next_plan, next_entry, lower_endpoint_id)
	var next_entry_id := str(next_entry.get("id", ""))
	var entry_record := _find_record(next_entry_id)
	var front_direction := _direction_between(
		entry_record.get("position", Vector3.ZERO) as Vector3,
		_plan_world_position(next_plan, next_hub)
	)
	(entry_record["doors"] as Array).append(front_direction)
	(entry_record["door_targets"] as Dictionary)[front_direction] = str(next_hub.get("id", ""))
	if lower_endpoint_id != next_entry_id:
		_declare_and_register_edge(lower_endpoint_id, next_entry_id, "horizontal")
		_airlock_front_edges[_edge_key(lower_endpoint_id, next_entry_id)] = next_floor_index
	var side := str(current_plan.get("exit_side", "west"))
	_declare_and_register_edge(current_exit_id, lower_endpoint_id, "vertical", side, side, side)
	var vertical_edge := _edge_key(current_exit_id, lower_endpoint_id)
	_floor_seed_gate_edges[vertical_edge] = next_floor_index
	_descent_side_sequence.append(side)
	if upper_floor_number % 5 == 0:
		_boss_descent_gate_edges[vertical_edge] = next_floor_index
	if upper_floor_number == 95:
		_level_elevator_edge = vertical_edge


func _declare_and_register_edge(
	a: String, b: String, kind: String, side := "", a_door_side := "", b_door_side := ""
) -> void:
	var edge := _edge_key(a, b)
	if not _edge_kind_by_key.has(edge):
		_declare_edge(a, b, kind, side, a_door_side, b_door_side)
	_register_edge_topology(a, b, kind, side, a_door_side, b_door_side)


func _register_edge_topology(
	a: String, b: String, kind: String, side := "", a_door_side := "", b_door_side := ""
) -> void:
	if not _room_neighbors.has(a):
		_room_neighbors[a] = []
	if not _room_neighbors.has(b):
		_room_neighbors[b] = []
	if b not in (_room_neighbors[a] as Array):
		(_room_neighbors[a] as Array).append(b)
	if a not in (_room_neighbors[b] as Array):
		(_room_neighbors[b] as Array).append(a)
	var edge := _edge_key(a, b)
	if not _open_edges.has(edge):
		_open_edges[edge] = false
	var a_record := _find_record(a)
	var b_record := _find_record(b)
	if a_record.is_empty() or b_record.is_empty():
		return
	var a_side := a_door_side
	var b_side := b_door_side
	if kind == "vertical":
		a_side = side if a_side.is_empty() else a_side
		b_side = side if b_side.is_empty() else b_side
		_vertical_arrival_open[edge] = false
	else:
		a_side = _direction_between(a_record["position"], b_record["position"])
		b_side = _opposite_direction(a_side)
	for pair in [[a_record, a_side, b], [b_record, b_side, a]]:
		var record := pair[0] as Dictionary
		var direction := str(pair[1])
		if direction not in (record["doors"] as Array):
			(record["doors"] as Array).append(direction)
		(record["door_targets"] as Dictionary)[direction] = str(pair[2])


func _instantiate_dynamic_room(record: Dictionary) -> void:
	var room := DYNAMIC_ROOM_SCENE.instantiate() as DungeonRoom3D
	room.configure({
		"room_id": record["id"], "room_type": record["type"], "size_class": record["size"],
		"doors": record["doors"], "door_targets": record.get("door_targets", {}), "theme": visual_theme,
		"door_policies": _door_policies_for_record(record),
		"seed": run_seed + int(record["index"]) * 104729, "is_main_path": record["main"],
		"custom_dimensions": record.get("custom_dimensions", Vector2.ZERO),
		"tower_module_shell": bool(record.get("tower_module_shell", false)),
		"open_wall_directions": record.get("open_wall_directions", []),
	})
	room.position = record["position"]
	$GeneratedRooms.add_child(room)
	_rooms.append(room)
	_room_by_id[room.room_id] = room
	room.player_entered.connect(_on_room_entered)
	room.prop_searched.connect(_on_prop_searched)
	room.service_activated.connect(_on_service_activated)


func generate_through_floor_for_test(target_floor_number: int) -> bool:
	var target_index := 100 - target_floor_number
	for floor_index in range(2, target_index + 1):
		if not _commit_floor_bundle(floor_index, "verification"):
			return false
	return true


func _mark_room_cleared(room: DungeonRoom3D, spawn_key: bool) -> void:
	var was_cleared := room != null and room.cleared
	super(room, spawn_key)
	if room != null and room.room_type == "BOSS" and not was_cleared:
		_boss_descent_key_count += 1
		status_label.text = "Boss已击败 · 获得本段下行权限"


func _finalize_airlock_commit(lower_floor_index: int) -> void:
	if _active_airlock_room_id.is_empty():
		return
	# 双门隔离：先锁后门，再清掉旧段；前门由调用者随后开启。
	for edge_value in _boss_descent_gate_edges.keys():
		var edge := str(edge_value)
		if int(_boss_descent_gate_edges[edge]) != lower_floor_index:
			continue
		_open_edges[edge] = false
		_vertical_arrival_open[edge] = false
		var ids := edge.split("|")
		for room_id_value in ids:
			var room := _room_by_id.get(str(room_id_value)) as DungeonRoom3D
			if room != null:
				_refresh_edge_visuals(room.room_id, _active_airlock_room_id, false)
	_unload_completed_segment(lower_floor_index)
	_active_airlock_room_id = ""
	status_label.text = "旧段已卸载 · 未拾取物永久丢失"


func commit_active_airlock_for_test(lower_floor_index: int) -> void:
	_finalize_airlock_commit(lower_floor_index)


func _unload_completed_segment(lower_floor_index: int) -> void:
	var first_floor := 2 if lower_floor_index == 6 else lower_floor_index - 5
	var removed_ids: Array[String] = []
	_last_unloaded_room_count = 0
	_last_destroyed_world_loot_count = 0
	for floor_index in range(first_floor, lower_floor_index):
		if floor_index not in _unloaded_segment_floor_indices:
			_unloaded_segment_floor_indices.append(floor_index)
		for room_id_value in (_floor_room_ids.get(floor_index, []) as Array).duplicate():
			var room_id := str(room_id_value)
			removed_ids.append(room_id)
			var room := _room_by_id.get(room_id) as DungeonRoom3D
			if room != null and is_instance_valid(room):
				_last_destroyed_world_loot_count += _count_group_in_subtree(room, "ground_loot_3d")
				_rooms.erase(room)
				room.queue_free()
				_last_unloaded_room_count += 1
			_room_by_id.erase(room_id)
			if room_id == "extraction":
				_extraction = null
				_conditional_extractions.erase("BOSS_KILL")
			_clear_room_runtime_caches(room_id)
		_floor_room_ids.erase(floor_index)
		var stage = _floor_stages.get(floor_index)
		if stage != null and is_instance_valid(stage):
			stage.queue_free()
		_floor_stages.erase(floor_index)
		var elevator := _elevator_facilities_by_floor.get(_floor_number_from_index(floor_index)) as BaseFacility3D
		if elevator != null and is_instance_valid(elevator):
			var bay := elevator.get_parent()
			if bay != null:
				bay.queue_free()
			_elevator_facilities_by_floor.erase(_floor_number_from_index(floor_index))
			_elevator_access_room_by_floor.erase(_floor_number_from_index(floor_index))
	for edge_value in _corridor_by_edge.keys().duplicate():
		var edge := str(edge_value)
		var connector := _corridor_by_edge.get(edge) as Node3D
		if connector == null:
			continue
		if (
			str(connector.get_meta("from_room_id", "")) in removed_ids
			or str(connector.get_meta("to_room_id", "")) in removed_ids
		):
			connector.queue_free()
			_corridor_by_edge.erase(edge)
			_open_edges.erase(edge)
			_vertical_arrival_open.erase(edge)
			_edge_kind_by_key.erase(edge)
			_edge_side_by_key.erase(edge)
			_edge_door_sides_by_key.erase(edge)
	for index in range(_declared_edges.size() - 1, -1, -1):
		var declaration := _declared_edges[index] as Dictionary
		if str(declaration.get("a", "")) in removed_ids or str(declaration.get("b", "")) in removed_ids:
			_declared_edges.remove_at(index)
	for index in range(_records.size() - 1, -1, -1):
		if str(_records[index].get("id", "")) in removed_ids:
			_records.remove_at(index)
	for room_id in removed_ids:
		_room_floor_index.erase(room_id)
		_room_neighbors.erase(room_id)
	for neighbors_value in _room_neighbors.values():
		for room_id in removed_ids:
			(neighbors_value as Array).erase(room_id)
	minimap.configure(_records, _open_edges)
	_unloaded_segment_floor_indices.sort()


func _clear_room_runtime_caches(room_id: String) -> void:
	for cache in [
		_alive_by_room, _spawned_rooms, _spawned_key_rooms, _enemy_nodes_by_room,
		_room_wave_queues, _room_wave_numbers, _room_wave_totals, _wave_spawn_pending,
		_resolved_event_rooms, _event_combat_rooms, _room_enemy_hp_multipliers,
		_room_enemy_damage_multipliers, _room_currency_multipliers,
	]:
		(cache as Dictionary).erase(room_id)


func _count_group_in_subtree(root: Node, group_name: String) -> int:
	var count := 1 if root.is_in_group(group_name) else 0
	for child in root.get_children():
		count += _count_group_in_subtree(child, group_name)
	return count


func _install_facilities() -> void:
	var facility_floor := _room_by_id.get("facility") as DungeonRoom3D
	if facility_floor == null or not _facility_nodes.is_empty():
		return
	var definitions := [
		{
			"name": "MissionOperations", "facility_id": "mission_operations", "position": Vector3(-9.0, 0, -11.6),
			"display": "远征情报终端", "description": "查看本轮楼层与下行规则",
			"menu": "", "color": Color(0.88, 0.48, 0.18),
		},
		{
			"name": "Workshop", "facility_id": "weapon_workshop", "position": Vector3(-3.0, 0, -11.6),
			"display": "枪械工坊", "description": "解锁枪身、弹药与配件蓝图",
			"menu": "res://scenes/WorkshopMenu.tscn", "color": Color(0.75, 0.42, 0.16),
		},
		{
			"name": "Divination", "facility_id": "fate_divination", "position": Vector3(3.0, 0, -11.6),
			"display": "命运占卜台", "description": "为下一次深入准备命运预兆",
			"menu": "res://scenes/DivinationMenu.tscn", "color": Color(0.55, 0.31, 0.78),
		},
		{
			"name": "Vault", "facility_id": "vault", "position": Vector3(-9.0, 0, 11.6),
			"display": "保险柜", "description": "管理撤离物资与下局带入",
			"menu": "res://scenes/VaultMenu.tscn", "color": Color(0.24, 0.58, 0.72),
		},
		{
			"name": "Archive", "facility_id": "monster_archive", "position": Vector3(-3.0, 0, 11.6),
			"display": "怪物档案台", "description": "查看成长中的精英与悬赏情报",
			"menu": "res://scenes/MonsterArchiveMenu.tscn", "color": Color(0.48, 0.65, 0.26),
		},
		{
			"name": "FateCollection", "facility_id": "fate_collection", "position": Vector3(3.0, 0, 11.6),
			"display": "命运卡收藏台", "description": "浏览已发现的命运卡片",
			"menu": "res://scenes/FateCardCollectionMenu.tscn", "color": Color(0.72, 0.28, 0.58),
		},
		{
			"name": "BaseConsole", "facility_id": "base_console", "position": Vector3(9.0, 0, -11.6),
			"display": "基地管理终端", "description": "处理战利品、升级建筑与查看总览",
			"menu": "res://scenes/BaseMenu.tscn", "color": Color(0.28, 0.52, 0.68),
		},
		{
			"name": "BaseVending", "facility_id": "base_vending", "position": Vector3(11.6, 0, 5.6),
			"rotation_y": PI * 0.5,
			"display": "自动贩卖机", "description": "购买基础装备与药水；出售保险柜物品",
			"menu": "res://scenes/BaseVendingMenu.tscn", "color": Color(0.16, 0.78, 0.88),
			"scene": VENDING_FACILITY_SCENE,
		},
	]
	for definition in definitions:
		var facility_scene := definition.get("scene", FACILITY_SCENE) as PackedScene
		var facility := facility_scene.instantiate() as BaseFacility3D
		facility.name = str(definition["name"])
		facility.facility_id = str(definition["facility_id"])
		facility.position = definition["position"] as Vector3
		facility.rotation.y = float(definition.get("rotation_y", 0.0))
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
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
	if menu.has_method("set_inventory_module"):
		menu.call("set_inventory_module", get_inventory_module())
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
	margin.name = "TowerCurrentInfoHUD"
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 14.0
	margin.offset_top = 176.0
	margin.offset_right = 270.0
	margin.offset_bottom = 290.0
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
	style.content_margin_left = 11.0
	style.content_margin_right = 11.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)
	_tower_floor_label = Label.new()
	_tower_floor_label.add_theme_font_size_override("font_size", 19)
	_tower_floor_label.add_theme_color_override("font_color", Color(0.56, 0.93, 1.0))
	vbox.add_child(_tower_floor_label)
	_tower_target_label = Label.new()
	_tower_target_label.add_theme_font_size_override("font_size", 12)
	_tower_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_tower_target_label)
	_tower_elevator_label = Label.new()
	_tower_elevator_label.add_theme_font_size_override("font_size", 11)
	_tower_elevator_label.add_theme_color_override("font_color", Color(0.72, 0.82, 0.88))
	vbox.add_child(_tower_elevator_label)
	_tower_base_currency_label = Label.new()
	_tower_base_currency_label.add_theme_font_size_override("font_size", 12)
	_tower_base_currency_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.28))
	vbox.add_child(_tower_base_currency_label)


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
	_tower_base_currency_label.text = "魂：◈ %d" % BaseManager.get_extraction_points()


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
	return 100 - maxi(0, floor_index)


func _current_floor_number() -> int:
	var fallback_index := maxi(
		0, int(round(-player.global_position.y / FLOOR_HEIGHT)) if player != null else 0
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
		or (_initial_loop_retreat_overlay != null and is_instance_valid(_initial_loop_retreat_overlay))
		or super()
	)


func try_close_modal_for_pause() -> bool:
	if _initial_loop_retreat_overlay != null and is_instance_valid(_initial_loop_retreat_overlay):
		_cancel_initial_loop_retreat()
		return true
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
	var stage_indices: Array = _floor_stages.keys()
	stage_indices.sort()
	for floor_value in stage_indices:
		var floor_index := int(floor_value)
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
		var plan := _floor_plan_snapshots.get(physical_index, {}) as Dictionary
		combat_floor_records.append({
			"id": "floor_%02d" % combat_floor,
			"floor_number": int(plan.get("floor_number", 99 - combat_floor)),
			"type": "BOSS" if bool(plan.get("boss_floor", false)) else "COMBAT",
			"layout_template": str(_floor_layout_templates.get(physical_index, "")),
			"layout_id": str(plan.get("layout_id", "")),
			"dimensions": Vector2(TOWER_GEOMETRY.MAP_SIZE_M, TOWER_GEOMETRY.MAP_SIZE_M),
			"height": -FLOOR_HEIGHT * float(physical_index),
			"room_ids": (_floor_room_ids.get(physical_index, []) as Array).duplicate(),
			"room_count": (_floor_room_ids.get(physical_index, []) as Array).size(),
			"planned_room_count": (plan.get("rooms", []) as Array).size(),
			"main_path_content_count": int(plan.get("main_path_content_count", 0)),
			"branch_count": int(plan.get("branch_count", 0)),
			"area_budget": (plan.get("area_budget", {}) as Dictionary).duplicate(true),
			"seed_gate_committed": physical_index in _generated_floor_indices,
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
		"floor_plan_snapshots": _floor_plan_snapshots.duplicate(true),
		"rooms_per_normal_combat_floor": ((_floor_plan_snapshots.get(2, {}) as Dictionary).get("rooms", []) as Array).size(),
		"boss_floor_room_count": ((_floor_plan_snapshots.get(COMBAT_FLOOR_COUNT + 1, {}) as Dictionary).get("rooms", []) as Array).size(),
		"logical_combat_room_count": _rooms.size() - 2,
		"combat_room_size": Vector2(
			TOWER_GEOMETRY.COMBAT_ROOM_SIZE_M,
			TOWER_GEOMETRY.COMBAT_ROOM_SIZE_Y_M
		),
		"combat_room_grid": TOWER_GEOMETRY.COMBAT_ROOM_GRID,
		"room_corridor_gap_m": TOWER_GEOMETRY.ROOM_CORRIDOR_GAP_M,
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
			15.0
		),
		"facility_count": get_facility_count(),
		"has_base_elevator": _elevator_facility != null,
		"standalone_elevator_count": _elevator_facilities_by_floor.size(),
		"level_elevator_count": 1 if _elevator_facilities_by_floor.has(95) else 0,
		"level_elevator_floor": 95 if _elevator_facilities_by_floor.has(95) else -1,
		"elevator_facilities_are_room_content": false,
		"elevator_access_rooms": _elevator_access_room_by_floor.duplicate(),
		"unlocked_elevator_floors": _sorted_unlocked_elevator_floors(),
		"vertical_connector_count": vertical_connector_count,
		"descent_sides": _descent_side_sequence.duplicate(),
		"support_floor_count": support_floor_count,
		"rendered_floor_count": rendered_floor_count,
		"loaded_floor_count": _loaded_floor_indices.size(),
		"loaded_floor_indices": _loaded_floor_indices.duplicate(),
		"floor_visibility_poll_count": _floor_visibility_poll_count,
		"floor_visibility_apply_count": _floor_visibility_apply_count,
		"floor_visibility_runtime_state_read": "o1_stream_state",
		"floor_generation_mode": "arrival_gate_atomic_floor_bundle",
		"planned_floor_count": _planned_floor_indices.size(),
		"planned_floor_indices": _planned_floor_indices.duplicate(),
		"instantiated_room_count": _rooms.size(),
		"last_bundle_room_count": _last_bundle_room_count,
		"last_bundle_corridor_count": _last_bundle_corridor_count,
		"floor_seed_gate_count": _floor_seed_gate_edges.size(),
		"floor_seed_gate_edges": _floor_seed_gate_edges.duplicate(),
		"door_function_counts": _door_function_counts(),
		"door_function_taxonomy": [
			"base_transit", "floor_arrival", "room_progression",
			"boss_descent", "airlock_exit", "vertical_transit",
		],
		"generated_floor_count": _generated_floor_indices.size(),
		"generated_floor_indices": _generated_floor_indices.duplicate(),
		"floor_plan_commit_reasons": _floor_plan_commit_reasons.duplicate(),
		"floor_layout_plan_valid": _floor_layout_plan_conflicts.is_empty(),
		"floor_layout_plan_conflicts": _floor_layout_plan_conflicts.duplicate(),
		"stair_plan_reservations": {
			"north": _stair_plan_rect("north"),
			"south": _stair_plan_rect("south"),
			"west": _stair_plan_rect("west"),
			"east": _stair_plan_rect("east"),
		},
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
		"camera_height_m": (
			CAMERA_HEIGHT_M
			+ _camera_lift_current_m
			- _camera_stair_slab_drop_current_m
		),
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
		"camera_stair_slab_mode": "tagged_upper_lower_flight_vertical_clamp",
		"camera_stair_slab_detected": _camera_stair_slab_detected,
		"camera_stair_slab_clearance_height_m": _camera_stair_slab_clearance_height_m,
		"camera_stair_slab_drop_current_m": _camera_stair_slab_drop_current_m,
		"camera_stair_slab_drop_target_m": _camera_stair_slab_drop_target_m,
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
		"camera_collision_adjusted": (
			_camera_lift_current_m > 0.01
			or _camera_stair_slab_drop_current_m > 0.01
		),
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
		"camera_probe_mode": "adaptive_60hz_moving_30hz_idle",
		"camera_probe_interval_s": _camera_probe_interval_s,
		"camera_probe_refresh_count": _camera_probe_refresh_count,
		"camera_silhouette_mesh_count": _player_occlusion_meshes.size(),
		"camera_near_fade_candidate_count": 0,
		"camera_near_faded_mesh_count": 0,
		"camera_near_fade_alpha": 1.0,
		"camera_wall_material_mutation_enabled": false,
		"camera_door_bypass_active": false,
		"camera_door_bypass_half_width_m": 0.0,
		"camera_door_bypass_half_depth_m": 0.0,
		"camera_door_bypass_node_count": 0,
		"vertical_arrival_gate_count": _vertical_arrival_open.size(),
		"vertical_arrival_open_count": vertical_arrival_open_count,
		"boss_descent_gate_count": _boss_descent_gate_edges.size(),
		"boss_descent_key_count": _boss_descent_key_count,
		"airlock_front_gate_count": _airlock_front_edges.size(),
		"airlock_warning_active": _airlock_warning_overlay != null and is_instance_valid(_airlock_warning_overlay),
		"unloaded_segment_floor_indices": _unloaded_segment_floor_indices.duplicate(),
		"last_unloaded_room_count": _last_unloaded_room_count,
		"last_destroyed_world_loot_count": _last_destroyed_world_loot_count,
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
