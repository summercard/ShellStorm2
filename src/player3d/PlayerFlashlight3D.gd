class_name PlayerFlashlight3D
extends Node3D
## 与玩法视野完全解耦的真实玩家灯光。
## 主聚光与近身溢光只照环境；角色正面柔光只照角色和手持枪，避免头顶亮斑。

signal light_enabled_changed(enabled: bool)

const ENVIRONMENT_RENDER_LAYER := 1
const AVATAR_RENDER_LAYER := 2

@export_group("Input")
@export var toggle_action := "toggle_flashlight"
@export var start_enabled := false

@export_group("Beam")
@export var beam_color := Color(0.86, 0.96, 0.93)
@export_range(0.0, 32.0, 0.1) var beam_energy := 15.5
@export_range(4.0, 40.0, 0.5) var beam_range := 25.0
@export_range(20.0, 110.0, 1.0) var beam_angle_degrees := 66.0
@export_range(0.1, 2.0, 0.05) var beam_attenuation := 0.48
@export_range(0.1, 4.0, 0.05) var beam_edge_attenuation := 1.15
@export var beam_shadows := true

@export_group("Mount")
@export_range(0.5, 4.0, 0.05) var mount_height := 1.15
@export_range(-1.0, 2.0, 0.05) var mount_forward := 0.42
@export_range(1.0, 24.0, 0.25) var target_forward := 11.0
@export_range(0.0, 2.0, 0.05) var target_height := 0.38

@export_group("Environment Spill")
@export var spill_color := Color(0.68, 0.88, 0.84)
@export_range(0.0, 8.0, 0.05) var spill_energy := 2.0
@export_range(1.0, 10.0, 0.25) var spill_range := 4.8
@export_range(0.1, 4.0, 0.05) var spill_attenuation := 1.35

@export_group("Avatar Front Fill")
@export var front_fill_color := Color(0.70, 0.90, 0.86)
@export_range(0.0, 4.0, 0.05) var front_fill_energy := 0.95
@export_range(1.0, 8.0, 0.25) var front_fill_range := 4.0
@export_range(20.0, 110.0, 1.0) var front_fill_angle_degrees := 74.0
@export_range(0.1, 3.0, 0.05) var front_fill_attenuation := 1.15
@export_range(0.2, 3.0, 0.05) var front_fill_forward := 1.45
@export_range(0.5, 3.0, 0.05) var front_fill_height := 1.22
@export_range(0.2, 2.5, 0.05) var avatar_target_height := 0.82

var _player: Player3D
var _beam: SpotLight3D
var _spill: OmniLight3D
var _front_fill: SpotLight3D
var _enabled := false


func _ready() -> void:
	_player = get_parent() as Player3D
	_enabled = start_enabled
	_build_lights()
	_apply_configuration()
	force_sync()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(toggle_action):
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if _player == null or _player.input_locked or _player.current_hp <= 0:
		return
	toggle_light()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	force_sync()


func force_sync() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_parent() as Player3D
	if _player == null or _beam == null or _spill == null or _front_fill == null:
		return
	var aim := _player.aim_direction
	aim.y = 0.0
	if aim.length_squared() <= 0.0001:
		aim = Vector3.FORWARD
	aim = aim.normalized()
	_beam.global_position = _player.global_position + Vector3.UP * mount_height + aim * mount_forward
	var beam_target := _player.global_position + aim * target_forward + Vector3.UP * target_height
	_beam.look_at(beam_target, Vector3.UP)
	_spill.global_position = _player.global_position + Vector3.UP * 0.90 - aim * 0.12
	_front_fill.global_position = _player.global_position + aim * front_fill_forward + Vector3.UP * front_fill_height
	_front_fill.look_at(_player.global_position + Vector3.UP * avatar_target_height, Vector3.UP)


func set_light_enabled(enabled: bool) -> void:
	if _enabled == enabled:
		return
	_enabled = enabled
	if _beam != null:
		_beam.visible = enabled
	if _spill != null:
		_spill.visible = enabled
	if _front_fill != null:
		_front_fill.visible = enabled
	light_enabled_changed.emit(enabled)


func toggle_light() -> bool:
	set_light_enabled(not _enabled)
	return _enabled


func apply_configuration() -> void:
	## 允许运行时调参面板或主题预设修改导出值后立即应用，不需要重建节点。
	_apply_configuration()
	force_sync()


func is_light_enabled() -> bool:
	return _enabled


func get_snapshot() -> Dictionary:
	var aim_alignment := 0.0
	if _player != null and _beam != null:
		var aim := _player.aim_direction.normalized()
		var beam_forward := -_beam.global_basis.z.normalized()
		aim_alignment = Vector2(aim.x, aim.z).normalized().dot(Vector2(beam_forward.x, beam_forward.z).normalized())
	return {
		"enabled": _enabled,
		"start_enabled": start_enabled,
		"manual_toggle": true,
		"toggle_action": toggle_action,
		"real_light_count": 3,
		"spotlight_count": 2,
		"spill_light_count": 1,
		"front_fill_light_count": 1,
		"shadow_light_count": 1 if beam_shadows else 0,
		"beam_energy": beam_energy,
		"beam_range": beam_range,
		"beam_angle_degrees": beam_angle_degrees,
		"spill_energy": spill_energy,
		"spill_range": spill_range,
		"front_fill_energy": front_fill_energy,
		"environment_light_cull_mask": ENVIRONMENT_RENDER_LAYER,
		"avatar_light_cull_mask": AVATAR_RENDER_LAYER,
		"environment_spill_affects_avatar": false,
		"front_fill_affects_avatar": true,
		"aim_alignment": aim_alignment,
		"gameplay_light_dependent": false,
		"configurable": true,
	}


func _build_lights() -> void:
	_beam = SpotLight3D.new()
	_beam.name = "ForwardBeam"
	_beam.top_level = true
	add_child(_beam)
	_spill = OmniLight3D.new()
	_spill.name = "EnvironmentSpill"
	_spill.top_level = true
	add_child(_spill)
	_front_fill = SpotLight3D.new()
	_front_fill.name = "AvatarFrontFill"
	_front_fill.top_level = true
	add_child(_front_fill)


func _apply_configuration() -> void:
	if _beam != null:
		_beam.light_color = beam_color
		_beam.light_energy = beam_energy
		_beam.spot_range = beam_range
		_beam.spot_angle = beam_angle_degrees
		_beam.spot_attenuation = beam_attenuation
		_beam.spot_angle_attenuation = beam_edge_attenuation
		_beam.shadow_enabled = beam_shadows
		_beam.shadow_bias = 0.055
		_beam.light_cull_mask = ENVIRONMENT_RENDER_LAYER
		_beam.visible = _enabled
	if _spill != null:
		_spill.light_color = spill_color
		_spill.light_energy = spill_energy
		_spill.omni_range = spill_range
		_spill.omni_attenuation = spill_attenuation
		_spill.shadow_enabled = false
		_spill.light_cull_mask = ENVIRONMENT_RENDER_LAYER
		_spill.visible = _enabled
	if _front_fill != null:
		_front_fill.light_color = front_fill_color
		_front_fill.light_energy = front_fill_energy
		_front_fill.spot_range = front_fill_range
		_front_fill.spot_angle = front_fill_angle_degrees
		_front_fill.spot_attenuation = front_fill_attenuation
		_front_fill.spot_angle_attenuation = 1.35
		_front_fill.shadow_enabled = false
		_front_fill.light_cull_mask = AVATAR_RENDER_LAYER
		_front_fill.visible = _enabled
