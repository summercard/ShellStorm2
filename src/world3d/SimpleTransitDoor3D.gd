class_name SimpleTransitDoor3D
extends Node
## 基地普通交通门组件：只拥有实体门的统一表现、E键开启与离开后自动关闭。
## 路线授权、楼梯端点、FloorBundle和撤退事务仍由塔楼世界负责。

const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
const INTERACTION_DISTANCE_M := 3.4
const AUTO_CLOSE_DISTANCE_M := 2.85
const AUTO_CLOSE_DELAY_S := 0.40
const MOTION_DURATION_S := 0.72

var door: RoomDoor3D
var player: Node3D
var _clear_elapsed := 0.0


func configure(p_door: RoomDoor3D, p_player: Node3D) -> void:
	door = p_door
	player = p_player
	process_mode = Node.PROCESS_MODE_ALWAYS
	if door == null:
		set_process(false)
		return
	door.process_mode = Node.PROCESS_MODE_ALWAYS
	door.set_motion_profile(MOTION_DURATION_S, true)
	door.set_manual_close_enabled(false)
	door.set_meta("transit_component", "simple_base_transit_v1")
	door.set_meta("auto_close_distance_m", AUTO_CLOSE_DISTANCE_M)
	door.set_meta("auto_close_delay_s", AUTO_CLOSE_DELAY_S)


func request_open() -> bool:
	if door == null or not is_instance_valid(door):
		return false
	# 普通交通门只有“E键开门”；开启中或已开启时重复交互不切换为关闭。
	if door.is_open:
		return true
	# 自动关闭动画尚未落到底时再次按E，应立即反向重新开启，不能只吞掉输入。
	if door.is_in_motion() and bool(door.get_snapshot().get("target_open", false)):
		return true
	_clear_elapsed = 0.0
	door.set_open(true)
	return true


func is_player_in_interaction_range() -> bool:
	return (
		door != null
		and is_instance_valid(door)
		and player != null
		and is_instance_valid(player)
		and player.global_position.distance_to(door.global_position) <= INTERACTION_DISTANCE_M
	)


func get_snapshot() -> Dictionary:
	return {
		"component": "simple_base_transit_v1",
		"door": door.name if door != null else "",
		"is_open": door.is_open if door != null else false,
		"interaction_distance_m": INTERACTION_DISTANCE_M,
		"auto_close_distance_m": AUTO_CLOSE_DISTANCE_M,
		"auto_close_delay_s": AUTO_CLOSE_DELAY_S,
		"motion_duration_s": MOTION_DURATION_S,
	}


func _process(delta: float) -> void:
	if door == null or not is_instance_valid(door) or player == null or not is_instance_valid(player):
		_clear_elapsed = 0.0
		return
	if not door.is_open or door.is_in_motion():
		_clear_elapsed = 0.0
		return
	if _is_player_in_doorway() or player.global_position.distance_to(door.global_position) <= AUTO_CLOSE_DISTANCE_M:
		_clear_elapsed = 0.0
		return
	_clear_elapsed += delta
	if _clear_elapsed < AUTO_CLOSE_DELAY_S:
		return
	_clear_elapsed = 0.0
	door.set_open(false)


func _is_player_in_doorway() -> bool:
	var local_pos := door.to_local(player.global_position)
	return (
		absf(local_pos.x) <= TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M * 0.5 + 0.35
		and absf(local_pos.z) <= 0.72
		and local_pos.y >= -0.4
		and local_pos.y <= TOWER_GEOMETRY.DOOR_CLEAR_HEIGHT_M + 0.4
	)
