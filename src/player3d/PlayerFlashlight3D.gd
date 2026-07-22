class_name PlayerFlashlight3D
extends Node3D
## 与玩法视野完全解耦的真实玩家灯光。
## 聚光灯照亮前方并投影，近身补光模拟灯具溢光以照亮角色和手持枪。

@export_group("Beam")
@export var beam_color := Color(0.86, 0.96, 0.93)
@export_range(0.0, 32.0, 0.1) var beam_energy := 15.5
@export_range(4.0, 40.0, 0.5) var beam_range := 25.0
@export_range(20.0, 110.0, 1.0) var beam_angle_degrees := 66.0
@export_range(0.1, 2.0, 0.05) var beam_attenuation := 0.48
@export_range(0.1, 4.0, 0.05) var beam_edge_attenuation := 1.15
@export var beam_shadows := true

@export_group("Mount")
@export_range(0.5, 4.0, 0.05) var mount_height := 2.25
@export_range(-1.0, 2.0, 0.05) var mount_forward := 0.42
@export_range(1.0, 24.0, 0.25) var target_forward := 11.0
@export_range(0.0, 2.0, 0.05) var target_height := 0.38

@export_group("Character Spill")
@export var spill_color := Color(0.68, 0.88, 0.84)
@export_range(0.0, 8.0, 0.05) var spill_energy := 2.15
@export_range(1.0, 10.0, 0.25) var spill_range := 4.8
@export_range(0.1, 4.0, 0.05) var spill_attenuation := 1.35

var _player: Player3D
var _beam: SpotLight3D
var _spill: OmniLight3D
var _enabled := true


func _ready() -> void:
	_player = get_parent() as Player3D
	_build_lights()
	_apply_configuration()
	force_sync()


func _process(_delta: float) -> void:
	force_sync()


func force_sync() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_parent() as Player3D
	if _player == null or _beam == null or _spill == null:
		return
	var aim := _player.aim_direction
	aim.y = 0.0
	if aim.length_squared() <= 0.0001:
		aim = Vector3.FORWARD
	aim = aim.normalized()
	_beam.global_position = _player.global_position + Vector3.UP * mount_height + aim * mount_forward
	var beam_target := _player.global_position + aim * target_forward + Vector3.UP * target_height
	_beam.look_at(beam_target, Vector3.UP)
	_spill.global_position = _player.global_position + Vector3.UP * (mount_height + 0.18) - aim * 0.18


func set_light_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _beam != null:
		_beam.visible = enabled
	if _spill != null:
		_spill.visible = enabled


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
		"real_light_count": 2,
		"spotlight_count": 1,
		"spill_light_count": 1,
		"shadow_light_count": 1 if beam_shadows else 0,
		"beam_energy": beam_energy,
		"beam_range": beam_range,
		"beam_angle_degrees": beam_angle_degrees,
		"spill_energy": spill_energy,
		"spill_range": spill_range,
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
	_spill.name = "CharacterSpill"
	_spill.top_level = true
	add_child(_spill)


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
		_beam.visible = _enabled
	if _spill != null:
		_spill.light_color = spill_color
		_spill.light_energy = spill_energy
		_spill.omni_range = spill_range
		_spill.omni_attenuation = spill_attenuation
		_spill.shadow_enabled = false
		_spill.visible = _enabled
