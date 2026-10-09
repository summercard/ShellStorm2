class_name Base99Radio3D
extends Node3D
## 收音机只拥有自身状态；E 由统一控制器转发，左键只消费命中本机的事件。

const TRACK_PATHS := [
	"res://assets/audio/music/base_passion/base_passion_a_v001.ogg",
	"res://assets/audio/music/base_passion/base_passion_b_v001.ogg",
]
const RANGE_M := 2.2
## 与 TowerFloorStage3D.TOWER_SHELL_WORLD_RECT 同步：99F 正式基地外框。
const BASE99_WORLD_RECT := Rect2(-50.0, -35.0, 100.0, 80.0)
const AUDIO_UNIT_SIZE_M := 18.0
const AUDIO_MAX_DISTANCE_M := 78.0
const OUTSIDE_BASE_EDGE_DROP_DB := -18.0
const OUTSIDE_BASE_DISTANCE_DROP_DB_PER_M := 4.0
const OUTSIDE_BASE_MAX_DROP_DB := -42.0

var radio_state := "off"
var _floor_active := true
var _focused := false
var _last_interaction_frame := -1
var _status_materials: Array[BaseMaterial3D] = []

@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var status_light: Node3D = find_child("StatusLight", true, false) as Node3D
@onready var tooltip: Label3D = $Tooltip
@onready var music_notes: VfxRadioMusicNotes3D = $MusicNotes


func _ready() -> void:
	audio_player.unit_size = AUDIO_UNIT_SIZE_M
	audio_player.max_distance = AUDIO_MAX_DISTANCE_M
	audio_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	_refresh_spatial_volume()
	if status_light != null:
		if status_light is MeshInstance3D:
			_collect_status_materials(status_light as MeshInstance3D)
		for node in status_light.find_children("*", "MeshInstance3D", true, false):
			_collect_status_materials(node as MeshInstance3D)
	_update_feedback()


func _collect_status_materials(mesh_node: MeshInstance3D) -> void:
	if mesh_node.mesh == null:
		return
	for index in mesh_node.mesh.get_surface_count():
		var original := mesh_node.get_active_material(index) as BaseMaterial3D
		if original == null:
			continue
		var material := original.duplicate() as BaseMaterial3D
		material.set_meta("radio_status_feedback_owned", true)
		mesh_node.set_surface_override_material(index, material)
		_status_materials.append(material)


func _exit_tree() -> void:
	music_notes.set_emitting(false)
	audio_player.stop()
	audio_player.stream = null


func _process(_delta: float) -> void:
	_refresh_spatial_volume()
	_sync_music_notes()
	var player := _get_player()
	var hovered := _can_interact(player) and _mouse_hits_radio(get_viewport().get_mouse_position(), player)
	tooltip.visible = hovered or (_focused and _can_interact(player))
	tooltip.text = get_next_prompt()


func _refresh_spatial_volume() -> void:
	if audio_player == null:
		return
	if not audio_player.playing:
		audio_player.volume_db = 0.0
		return
	var listener_position := _get_audio_listener_position()
	if _listener_inside_base99(listener_position):
		audio_player.volume_db = 0.0
		return
	var distance_outside := _distance_to_base99(listener_position)
	audio_player.volume_db = maxf(
		OUTSIDE_BASE_MAX_DROP_DB,
		OUTSIDE_BASE_EDGE_DROP_DB - distance_outside * OUTSIDE_BASE_DISTANCE_DROP_DB_PER_M,
	)


func _get_audio_listener_position() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera != null else global_position


func _listener_inside_base99(listener_position: Vector3) -> bool:
	return BASE99_WORLD_RECT.has_point(Vector2(listener_position.x, listener_position.z))


func _distance_to_base99(listener_position: Vector3) -> float:
	var point := Vector2(listener_position.x, listener_position.z)
	var closest := Vector2(
		clampf(point.x, BASE99_WORLD_RECT.position.x, BASE99_WORLD_RECT.end.x),
		clampf(point.y, BASE99_WORLD_RECT.position.y, BASE99_WORLD_RECT.end.y),
	)
	return point.distance_to(closest)


func get_spatial_audio_snapshot(listener_position: Vector3 = Vector3.INF) -> Dictionary:
	if not listener_position.is_finite():
		listener_position = _get_audio_listener_position()
	var inside := _listener_inside_base99(listener_position)
	var distance_outside := 0.0 if inside else _distance_to_base99(listener_position)
	var source_distance := global_position.distance_to(listener_position)
	var attenuation_gain := 1.0 / (1.0 + pow(source_distance / maxf(AUDIO_UNIT_SIZE_M, 0.001), 2.0))
	var outside_volume_db := 0.0 if inside else maxf(
		OUTSIDE_BASE_MAX_DROP_DB,
		OUTSIDE_BASE_EDGE_DROP_DB - distance_outside * OUTSIDE_BASE_DISTANCE_DROP_DB_PER_M,
	)
	return {
		"listener_position": listener_position,
		"inside_base99": inside,
		"distance_to_source_m": source_distance,
		"distance_outside_base_m": distance_outside,
		"source_volume_db": outside_volume_db,
		"inverse_square_gain": attenuation_gain,
		"effective_gain": attenuation_gain * db_to_linear(outside_volume_db),
		"unit_size_m": AUDIO_UNIT_SIZE_M,
		"max_distance_m": AUDIO_MAX_DISTANCE_M,
		"attenuation_model": audio_player.attenuation_model,
	}


func _input(event: InputEvent) -> void:
	_consume_mouse_input(event)


func _unhandled_input(event: InputEvent) -> void:
	_consume_mouse_input(event)


func _consume_mouse_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	var player := _get_player()
	if _can_interact(player) and _mouse_hits_radio(mouse.position, player):
		if perform_interaction(player, get_interaction_candidate(player)):
			get_viewport().set_input_as_handled()


func _get_player() -> Player3D:
	for node in get_tree().get_nodes_in_group("player_3d"):
		var player := node as Player3D
		if player != null and player.get_world_3d() == get_world_3d():
			return player
	return null


func _can_interact(player: Player3D) -> bool:
	return (
		_floor_active and not get_tree().paused and is_visible_in_tree()
		and player != null and not player.input_locked and player.current_hp > 0
		and not player.combat_enabled
		and player.get_state_machine_state() in ["idle", "moving"]
		and player.global_position.distance_to(global_position) <= RANGE_M
	)


func _mouse_hits_radio(screen_position: Vector2, player: Player3D) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null or player == null:
		return false
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	if not origin.is_finite() or not direction.is_finite():
		return false
	# 同时检查真实世界阻挡，不能隔着墙或桌体点击；排除玩家自己的胶囊。
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 100.0, 1, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") == $WorldCollision


func get_interaction_candidate(player: Player3D) -> Dictionary:
	if not _can_interact(player):
		return {}
	return {
		"available": true, "interaction_id": "base99_radio_cycle",
		"prompt": get_next_prompt(), "priority": 75, "position": global_position,
	}


func perform_interaction(player: Player3D, candidate: Dictionary) -> bool:
	if not _can_interact(player) or candidate.get("interaction_id", "") != "base99_radio_cycle":
		return false
	# 同一帧的左键和统一交互请求只执行一次，不读取第二条全局输入路径。
	if _last_interaction_frame == Engine.get_process_frames():
		return false
	_last_interaction_frame = Engine.get_process_frames()
	var next_state := {"off": "a", "a": "b", "b": "off"}
	_set_state(next_state[radio_state])
	return true


func cycle_state() -> String:
	var next_state := {"off": "a", "a": "b", "b": "off"}
	_set_state(next_state[radio_state])
	return radio_state


func set_radio_state(state: String) -> bool:
	if state not in ["off", "a", "b"]:
		return false
	_set_state(state)
	return true


func get_radio_state() -> String:
	return radio_state


func _set_state(state: String) -> void:
	audio_player.stop()
	audio_player.stream = null
	radio_state = state
	if state != "off":
		# 独立复制资源，不改 MusicManager 共享的 OGG；循环只回到这首曲目的开头。
		var stream := load(TRACK_PATHS[0 if state == "a" else 1]).duplicate() as AudioStreamOggVorbis
		stream.loop = true
		stream.loop_offset = 0.0
		audio_player.stream = stream
		audio_player.play()
	_sync_music_notes()
	_update_feedback()


func _sync_music_notes() -> void:
	music_notes.set_emitting(_floor_active and radio_state != "off" and audio_player.playing)


func set_floor_active(active: bool) -> void:
	_floor_active = active
	if not active:
		_set_state("off")
		_focused = false
		tooltip.visible = false


func set_interaction_focus(_candidate: Dictionary, focused: bool) -> void:
	_focused = focused


func get_interaction_dot_anchor() -> Vector3:
	return to_global(Vector3(0.0, 1.05, 0.0))


func is_interaction_dot_visible() -> bool:
	return _floor_active and is_visible_in_tree()


func get_next_prompt() -> String:
	return {
		"off": "左键 / E · 播放收音机 A",
		"a": "左键 / E · 切换收音机 B",
		"b": "左键 / E · 关闭收音机",
	}[radio_state]


func _update_feedback() -> void:
	# 小灯源UV为红格(4,8)；glTF翻转V后，偏移到绿格(5,5)。白乘色保留色盘原色。
	for material in _status_materials:
		material.uv1_offset = Vector3.ZERO if radio_state == "off" else Vector3(0.1, 0.3, 0.0)
		material.albedo_color = Color.WHITE
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		material.emission_energy_multiplier = 1.5
	tooltip.text = get_next_prompt()


func get_state_snapshot() -> Dictionary:
	return {
		"state": radio_state, "floor_active": _floor_active,
		"playing": audio_player.playing,
		"track": "" if radio_state == "off" else TRACK_PATHS[0 if radio_state == "a" else 1],
		"loop": audio_player.stream != null and (audio_player.stream as AudioStreamOggVorbis).loop,
		"emission": _status_materials[0].emission_energy_multiplier,
		"prompt": get_next_prompt(),
	}
